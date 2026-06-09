"""
Booth backend — brokers the Flutter app <-> local ComfyUI (Van Gogh vid2vid).

Same HTTP contract as mock_backend (so the app is unchanged):
  POST /jobs                  multipart: file(mp4), name, email   -> {job_id}
  GET  /jobs/{id}             -> {status, progress, preview_url, result_url}
  GET  /jobs/{id}/preview     -> latest generation preview (jpeg)
  GET  /jobs/{id}/result      -> stylized mp4

Run:
  pip install --user --break-system-packages -r booth_backend/requirements.txt
  python -m uvicorn booth_backend.server:app --host 0.0.0.0 --port 8000
Env:
  COMFY_URL   (default http://127.0.0.1:8188)
  WORKFLOW    (default booth_backend/workflows/vangogh_vid2vid.json)
"""
from __future__ import annotations

import json
import mimetypes
import os
import queue
import socket
import smtplib
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from email.message import EmailMessage
from pathlib import Path

from fastapi import FastAPI, Form, UploadFile
from fastapi.responses import JSONResponse, Response

from .comfy_client import ComfyClient, Progress


def _load_env_file() -> None:
    env_file = Path(os.environ.get(
        "BOOTH_ENV_FILE",
        Path(__file__).resolve().parents[1] / "booth.env",
    ))
    if not env_file.exists():
        return
    for raw in env_file.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


_load_env_file()

COMFY_URL = os.environ.get("COMFY_URL", "http://127.0.0.1:8188")
WORKFLOW_DIR = Path(os.environ.get("WORKFLOW_DIR", "booth_backend/workflows"))
DEFAULT_WORKFLOW = os.environ.get("WORKFLOW", "vangogh_vid2vid")
PORT = int(os.environ.get("BOOTH_PORT", "8000"))
DATA = Path(os.environ.get("BOOTH_DATA", "booth_backend/_data"))
DATA.mkdir(parents=True, exist_ok=True)

SMTP_HOST = os.environ.get("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
SMTP_FROM = os.environ.get("SMTP_FROM", SMTP_USER)
EMAIL_ATTACH_MAX_MB = float(os.environ.get("EMAIL_ATTACH_MAX_MB", "22"))

app = FastAPI(title="360 Booth Backend (ComfyUI)")
comfy = ComfyClient(COMFY_URL)


@dataclass
class Job:
    id: str
    name: str
    email: str
    consent: bool
    workflow: str
    direction: str
    speed: int
    duration_seconds: int
    src: str                       # local path to uploaded mp4
    status: str = "queued"         # queued|generating|done|failed
    progress: float = 0.0
    preview: bytes | None = None   # latest preview jpeg
    result: str | None = None      # local path to stylized mp4
    error: str | None = None
    email_status: str = "pending"  # pending|sent|disabled|failed
    email_error: str | None = None
    created: float = field(default_factory=time.time)


_jobs: dict[str, Job] = {}
_lock = threading.Lock()
_work: "queue.Queue[str]" = queue.Queue()


def _lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def _patch_workflow(wf: dict, input_name: str, job_id: str) -> dict:
    """Insert the per-job input video filename + a unique output prefix.
    Style/prompt/LoRA/steps live in the template itself."""
    for node in wf.values():
        ct = node.get("class_type", "")
        ins = node.setdefault("inputs", {})
        if ct in ("VHS_LoadVideo", "VHS_LoadVideoPath", "LoadVideo"):
            # VHS uses "video" for the uploaded filename
            if "video" in ins:
                ins["video"] = input_name
        if ct in ("VHS_VideoCombine",) and "filename_prefix" in ins:
            ins["filename_prefix"] = f"booth_{job_id}"
    return wf


def _workflow_path(workflow: str) -> Path:
    safe = Path(workflow).stem or DEFAULT_WORKFLOW
    path = WORKFLOW_DIR / f"{safe}.json"
    if not path.exists() and workflow.endswith(".json"):
        path = WORKFLOW_DIR / Path(workflow).name
    return path


def _public_base_url() -> str:
    return os.environ.get("PUBLIC_BASE_URL", f"http://{_lan_ip()}:{PORT}")


def _send_email(job: Job) -> None:
    if not (SMTP_HOST and SMTP_PORT and SMTP_USER and SMTP_PASSWORD and SMTP_FROM):
        with _lock:
            job.email_status = "disabled"
            job.email_error = "SMTP env vars not configured"
        return
    if not job.email:
        with _lock:
            job.email_status = "failed"
            job.email_error = "missing recipient email"
        return
    if not job.result:
        with _lock:
            job.email_status = "failed"
            job.email_error = "missing generated video"
        return

    result_path = Path(job.result)
    result_url = f"{_public_base_url()}/jobs/{job.id}/result"

    msg = EmailMessage()
    msg["Subject"] = "Your AI 360 booth video is ready"
    msg["From"] = SMTP_FROM
    msg["To"] = job.email
    guest = job.name or "there"
    msg.set_content(
        f"Hi {guest},\n\n"
        "Your AI 360 booth video is ready.\n\n"
        f"Download/view it here while on the event network:\n{result_url}\n\n"
        "Thanks for visiting.\n"
    )

    max_bytes = int(EMAIL_ATTACH_MAX_MB * 1024 * 1024)
    if result_path.exists() and result_path.stat().st_size <= max_bytes:
        ctype, _ = mimetypes.guess_type(result_path.name)
        maintype, subtype = (ctype or "video/mp4").split("/", 1)
        msg.add_attachment(
            result_path.read_bytes(),
            maintype=maintype,
            subtype=subtype,
            filename=f"booth-{job.id}.mp4",
        )

    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=60) as smtp:
            smtp.starttls()
            smtp.login(SMTP_USER, SMTP_PASSWORD)
            smtp.send_message(msg)
        with _lock:
            job.email_status = "sent"
            job.email_error = None
    except Exception as exc:  # noqa: BLE001
        with _lock:
            job.email_status = "failed"
            job.email_error = str(exc)


def _process(job: Job) -> None:
    workflow_path = _workflow_path(job.workflow)
    if not workflow_path.exists():
        raise RuntimeError(f"workflow not found: {workflow_path} "
                           "(author it in ComfyUI and export API JSON)")
    wf = json.loads(workflow_path.read_text())
    input_name = comfy.upload_video(job.src)
    wf = _patch_workflow(wf, input_name, job.id)
    client_id = job.id

    def on_progress(p: Progress) -> None:
        with _lock:
            job.progress = round(p.fraction, 3)

    def on_preview(jpeg: bytes) -> None:
        with _lock:
            job.preview = jpeg

    outputs = comfy.run_and_wait(wf, client_id, on_progress, on_preview)
    found = ComfyClient.find_output_video(outputs)
    if not found:
        raise RuntimeError("ComfyUI produced no video output")
    fn, sub = found
    data = comfy.view_bytes(fn, sub, "output")
    raw_path = DATA / f"{job.id}_raw.mp4"
    raw_path.write_bytes(data)
    out_path = DATA / f"{job.id}.mp4"
    # motion-interpolate the low-fps AI frames up to a smooth fps (ffmpeg on the
    # host; in-graph RIFE is broken on this ROCm build)
    if not _smooth(raw_path, out_path):
        out_path.write_bytes(data)  # fallback: serve the raw clip
    with _lock:
        job.result = str(out_path)
        job.progress = 1.0
    _send_email(job)


def _smooth(src: Path, dst: Path, fps: int = 16) -> bool:
    try:
        r = subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(src),
             "-vf", f"minterpolate=fps={fps}:mi_mode=mci:mc_mode=aobmc:vsbmc=1",
             "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
             "-y", str(dst)],
            timeout=120,
        )
        return r.returncode == 0 and dst.exists()
    except Exception:  # noqa: BLE001
        return False


def _worker() -> None:
    while True:
        jid = _work.get()
        job = _jobs.get(jid)
        if job is None:
            continue
        with _lock:
            job.status = "generating"
        try:
            _process(job)
            with _lock:
                job.status = "done"
        except Exception as e:  # noqa: BLE001
            with _lock:
                job.status = "failed"
                job.error = str(e)


threading.Thread(target=_worker, daemon=True).start()


@app.post("/jobs")
async def create_job(
    file: UploadFile,
    name: str = Form(""),
    email: str = Form(""),
    consent: bool = Form(False),
    workflow: str = Form(DEFAULT_WORKFLOW),
    direction: str = Form(""),
    speed: int = Form(0),
    duration_seconds: int = Form(0),
):
    if not consent:
        return JSONResponse({"error": "consent required"}, status_code=400)
    if not email.strip():
        return JSONResponse({"error": "email required"}, status_code=400)

    jid = uuid.uuid4().hex[:8]
    src = DATA / f"{jid}_src.mp4"
    src.write_bytes(await file.read())
    job = Job(
        id=jid,
        name=name,
        email=email.strip(),
        consent=consent,
        workflow=workflow,
        direction=direction,
        speed=speed,
        duration_seconds=duration_seconds,
        src=str(src),
    )
    meta = {
        "job_id": jid,
        "name": name,
        "email": email.strip(),
        "consent": consent,
        "workflow": workflow,
        "direction": direction,
        "speed": speed,
        "duration_seconds": duration_seconds,
        "source_video": str(src),
        "created": job.created,
    }
    (DATA / f"{jid}_meta.json").write_text(json.dumps(meta, indent=2))
    with _lock:
        _jobs[jid] = job
    _work.put(jid)
    return {"job_id": jid}


@app.get("/jobs/{jid}")
async def job_status(jid: str):
    job = _jobs.get(jid)
    if job is None:
        return JSONResponse({"error": "not found"}, status_code=404)
    base = f"http://{_lan_ip()}:{PORT}"
    with _lock:
        return {
            "status": job.status,
            "progress": job.progress,
            "preview_url": f"{base}/jobs/{jid}/preview?t={int(time.time())}"
            if job.preview else None,
            "result_url": f"{base}/jobs/{jid}/result" if job.result else None,
            "email_status": job.email_status,
            "email_error": job.email_error,
            "error": job.error,
        }


@app.get("/jobs/{jid}/preview")
async def job_preview(jid: str):
    job = _jobs.get(jid)
    if job is None or job.preview is None:
        return JSONResponse({"error": "no preview"}, status_code=404)
    return Response(content=job.preview, media_type="image/jpeg")


@app.get("/jobs/{jid}/result")
async def job_result(jid: str):
    job = _jobs.get(jid)
    if job is None or job.result is None:
        return JSONResponse({"error": "not ready"}, status_code=404)
    return Response(content=Path(job.result).read_bytes(), media_type="video/mp4")


@app.get("/")
async def root():
    return {
        "ok": True,
        "comfy": COMFY_URL,
        "workflow_dir": str(WORKFLOW_DIR),
        "default_workflow": DEFAULT_WORKFLOW,
        "smtp_configured": bool(SMTP_USER and SMTP_PASSWORD),
        "jobs": len(_jobs),
    }
