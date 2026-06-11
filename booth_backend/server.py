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
FORCE_WORKFLOW = os.environ.get("FORCE_WORKFLOW", "").strip()
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
    session_id: str
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


@dataclass(frozen=True)
class Preset:
    id: str
    name: str
    description: str
    preview_workflow: str
    final_workflow: str


PRESETS = [
    Preset(
        id="cinematic_glow",
        name="Cinematic Glow",
        description="Soft bloom, polished contrast, and a clean event-video look.",
        preview_workflow="preset_cinematic_glow_preview",
        final_workflow="preset_cinematic_glow_final",
    ),
    Preset(
        id="neon_edge",
        name="Neon Edge",
        description="Bright contour lines blended back over the original footage.",
        preview_workflow="preset_neon_edge_preview",
        final_workflow="preset_neon_edge_final",
    ),
    Preset(
        id="comic_pop",
        name="Comic Pop",
        description="Reduced colors, crisp edges, and a punchy graphic finish.",
        preview_workflow="preset_comic_pop_preview",
        final_workflow="preset_comic_pop_final",
    ),
    Preset(
        id="chrome_negative",
        name="Chrome Negative",
        description="High-contrast inverted chrome with sharp futuristic detail.",
        preview_workflow="preset_chrome_negative_preview",
        final_workflow="preset_chrome_negative_final",
    ),
]
PRESET_BY_ID = {p.id: p for p in PRESETS}


@dataclass
class PreviewJob:
    id: str
    session_id: str
    name: str
    email: str
    consent: bool
    requested_workflow: str
    direction: str
    speed: int
    duration_seconds: int
    src: str
    status: str = "queued"
    progress: float = 0.0
    previews: dict[str, str] = field(default_factory=dict)
    error: str | None = None
    created: float = field(default_factory=time.time)


_jobs: dict[str, Job] = {}
_preview_jobs: dict[str, PreviewJob] = {}
_lock = threading.Lock()
_work: "queue.Queue[str]" = queue.Queue()
_preview_work: "queue.Queue[str]" = queue.Queue()


def _safe_session_id(value: str) -> str:
    safe = "".join(ch for ch in value if ch.isalnum() or ch in ("-", "_"))
    return safe or uuid.uuid4().hex[:8]


def _session_dir(session_id: str) -> Path:
    path = DATA / _safe_session_id(session_id)
    path.mkdir(parents=True, exist_ok=True)
    return path


def _storage_dir_for(src: str | Path) -> Path:
    return Path(src).parent


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
        if ct in ("VHS_LoadVideo", "VHS_LoadVideoPath"):
            # VHS uses "video" for the uploaded filename
            if "video" in ins:
                ins["video"] = input_name
        if ct == "LoadVideo" and "file" in ins:
            ins["file"] = input_name
        if ct in ("VHS_VideoCombine",) and "filename_prefix" in ins:
            ins["filename_prefix"] = f"booth_{job_id}"
        if ct == "SaveVideo" and "filename_prefix" in ins:
            ins["filename_prefix"] = f"booth_{job_id}"
    return wf


def _load_workflow(workflow: str) -> dict:
    workflow_path = _workflow_path(workflow)
    if not workflow_path.exists():
        raise RuntimeError(f"workflow not found: {workflow_path} "
                           "(author it in ComfyUI and export API JSON)")
    return json.loads(workflow_path.read_text())


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
    attachment_path = _attachment_path_for_email(result_path, job.id, max_bytes)
    if attachment_path is None:
        with _lock:
            job.email_status = "failed"
            job.email_error = (
                f"generated video is too large to attach "
                f"(limit {EMAIL_ATTACH_MAX_MB:g} MB)"
            )
        return

    ctype, _ = mimetypes.guess_type(attachment_path.name)
    maintype, subtype = (ctype or "video/mp4").split("/", 1)
    msg.add_attachment(
        attachment_path.read_bytes(),
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


def _run_comfy_video(
    *,
    src: str,
    workflow: str,
    client_id: str,
    out_path: Path,
    on_progress=None,
    on_preview=None,
) -> Path:
    wf = _load_workflow(workflow)
    input_name = comfy.upload_video(src)
    wf = _patch_workflow(wf, input_name, client_id)
    outputs = comfy.run_and_wait(wf, client_id, on_progress, on_preview)
    found = ComfyClient.find_output_video(outputs)
    if not found:
        raise RuntimeError("ComfyUI produced no video output")
    fn, sub = found
    out_path.write_bytes(comfy.view_bytes(fn, sub, "output"))
    return out_path


def _process(job: Job) -> None:
    client_id = job.id

    def on_progress(p: Progress) -> None:
        with _lock:
            job.progress = round(p.fraction, 3)

    def on_preview(jpeg: bytes) -> None:
        with _lock:
            job.preview = jpeg

    storage_dir = _storage_dir_for(job.src)
    raw_path = storage_dir / f"{job.id}_raw.mp4"
    _run_comfy_video(
        src=job.src,
        workflow=job.workflow,
        client_id=client_id,
        out_path=raw_path,
        on_progress=on_progress,
        on_preview=on_preview,
    )
    out_path = storage_dir / f"{job.id}.mp4"
    # motion-interpolate the low-fps AI frames up to a smooth fps (ffmpeg on the
    # host; in-graph RIFE is broken on this ROCm build)
    if not _smooth(raw_path, out_path):
        out_path.write_bytes(raw_path.read_bytes())  # fallback: serve the raw clip
    with _lock:
        job.result = str(out_path)
        job.progress = 1.0
    _send_email(job)


def _smooth(src: Path, dst: Path, fps: int = 16) -> bool:
    try:
        r = subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(src),
             "-vf", f"minterpolate=fps={fps}:mi_mode=mci:mc_mode=aobmc:vsbmc=1",
             "-c:v", "libx264", "-preset", "medium", "-crf", "24",
             "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-y", str(dst)],
            timeout=120,
        )
        return r.returncode == 0 and dst.exists()
    except Exception:  # noqa: BLE001
        return False


def _attachment_path_for_email(src: Path, job_id: str, max_bytes: int) -> Path | None:
    if not src.exists():
        return None
    if src.stat().st_size <= max_bytes:
        return src

    dst = src.parent / f"{job_id}_email.mp4"
    for crf in (26, 30, 34):
        try:
            if dst.exists():
                dst.unlink()
            r = subprocess.run(
                [
                    "ffmpeg", "-hide_banner", "-loglevel", "error",
                    "-i", str(src),
                    "-vf",
                    "scale=720:1280:force_original_aspect_ratio=decrease:"
                    "force_divisible_by=2",
                    "-an",
                    "-c:v", "libx264",
                    "-preset", "medium",
                    "-crf", str(crf),
                    "-pix_fmt", "yuv420p",
                    "-movflags", "+faststart",
                    "-y", str(dst),
                ],
                timeout=180,
            )
            if r.returncode == 0 and dst.exists() and dst.stat().st_size <= max_bytes:
                return dst
        except Exception:  # noqa: BLE001
            continue
    return None


def _make_preview_source(src: str) -> Path:
    out = _storage_dir_for(src) / "preview_source.mp4"
    try:
        r = subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error",
                "-i", src,
                "-t", "1.6",
                "-vf",
                "fps=8,scale=360:640:force_original_aspect_ratio=increase,"
                "crop=360:640",
                "-an",
                "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", "-y", str(out),
            ],
            timeout=60,
        )
        if r.returncode == 0 and out.exists():
            return out
    except Exception:  # noqa: BLE001
        pass
    return Path(src)


def _process_preview_job(job: PreviewJob) -> None:
    preview_src = _make_preview_source(job.src)
    storage_dir = _storage_dir_for(job.src)
    for index, preset in enumerate(PRESETS, start=1):
        out_path = storage_dir / f"{preset.id}_preview.mp4"
        _run_comfy_video(
            src=str(preview_src),
            workflow=preset.preview_workflow,
            client_id=f"{job.id}_{preset.id}_preview",
            out_path=out_path,
        )
        with _lock:
            job.previews[preset.id] = str(out_path)
            job.progress = round(index / len(PRESETS), 3)


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


def _preview_worker() -> None:
    while True:
        jid = _preview_work.get()
        job = _preview_jobs.get(jid)
        if job is None:
            continue
        with _lock:
            job.status = "generating"
        try:
            _process_preview_job(job)
            with _lock:
                job.status = "done"
                job.progress = 1.0
        except Exception as e:  # noqa: BLE001
            with _lock:
                job.status = "failed"
                job.error = str(e)


threading.Thread(target=_worker, daemon=True).start()
threading.Thread(target=_preview_worker, daemon=True).start()


def _effective_workflow(requested: str) -> str:
    requested = (requested or "").strip()
    if FORCE_WORKFLOW:
        return FORCE_WORKFLOW
    return requested or DEFAULT_WORKFLOW


def _preset_payload(preview_id: str | None = None) -> list[dict]:
    base = _public_base_url()
    rows = []
    for preset in PRESETS:
        row = {
            "id": preset.id,
            "name": preset.name,
            "description": preset.description,
        }
        if preview_id is not None:
            row["preview_url"] = (
                f"{base}/preview-jobs/{preview_id}/previews/{preset.id}"
            )
        rows.append(row)
    return rows


@app.get("/presets")
async def presets():
    return {"presets": _preset_payload()}


@app.post("/preview-jobs")
async def create_preview_job(
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
    session_id = jid
    session_dir = _session_dir(session_id)
    src = session_dir / "source.mp4"
    src.write_bytes(await file.read())
    job = PreviewJob(
        id=jid,
        session_id=session_id,
        name=name,
        email=email.strip(),
        consent=consent,
        requested_workflow=workflow,
        direction=direction,
        speed=speed,
        duration_seconds=duration_seconds,
        src=str(src),
    )
    meta = {
        "preview_job_id": jid,
        "session_id": session_id,
        "name": name,
        "email": email.strip(),
        "consent": consent,
        "requested_workflow": workflow,
        "direction": direction,
        "speed": speed,
        "duration_seconds": duration_seconds,
        "source_video": str(src),
        "created": job.created,
    }
    (session_dir / "preview_meta.json").write_text(json.dumps(meta, indent=2))
    with _lock:
        _preview_jobs[jid] = job
    _preview_work.put(jid)
    return {"preview_job_id": jid, "session_id": session_id}


@app.get("/preview-jobs/{jid}")
async def preview_job_status(jid: str):
    job = _preview_jobs.get(jid)
    if job is None:
        return JSONResponse({"error": "not found"}, status_code=404)
    with _lock:
        presets_payload = []
        for preset in PRESETS:
            row = {
                "id": preset.id,
                "name": preset.name,
                "description": preset.description,
                "preview_url": None,
            }
            if preset.id in job.previews:
                row["preview_url"] = (
                    f"{_public_base_url()}/preview-jobs/{jid}/previews/{preset.id}"
                )
            presets_payload.append(row)
        return {
            "status": job.status,
            "progress": job.progress,
            "error": job.error,
            "presets": presets_payload,
        }


@app.get("/preview-jobs/{jid}/previews/{preset_id}")
async def preview_job_video(jid: str, preset_id: str):
    job = _preview_jobs.get(jid)
    if job is None or preset_id not in job.previews:
        return JSONResponse({"error": "not found"}, status_code=404)
    return Response(
        content=Path(job.previews[preset_id]).read_bytes(),
        media_type="video/mp4",
    )


@app.post("/preview-jobs/{jid}/finalize")
async def finalize_preview_job(jid: str, preset_id: str = Form("")):
    preview = _preview_jobs.get(jid)
    preset = PRESET_BY_ID.get(preset_id)
    if preview is None:
        return JSONResponse({"error": "not found"}, status_code=404)
    if preset is None:
        return JSONResponse({"error": "unknown preset"}, status_code=400)
    if preview.status != "done":
        return JSONResponse({"error": "previews not ready"}, status_code=409)

    job_id = uuid.uuid4().hex[:8]
    job = Job(
        id=job_id,
        session_id=preview.session_id,
        name=preview.name,
        email=preview.email,
        consent=preview.consent,
        workflow=preset.final_workflow,
        direction=preview.direction,
        speed=preview.speed,
        duration_seconds=preview.duration_seconds,
        src=preview.src,
    )
    meta = {
        "job_id": job_id,
        "preview_job_id": jid,
        "session_id": preview.session_id,
        "name": preview.name,
        "email": preview.email,
        "consent": preview.consent,
        "workflow": preset.final_workflow,
        "preset_id": preset.id,
        "preset_name": preset.name,
        "requested_workflow": preview.requested_workflow,
        "direction": preview.direction,
        "speed": preview.speed,
        "duration_seconds": preview.duration_seconds,
        "source_video": preview.src,
        "created": job.created,
    }
    (_storage_dir_for(preview.src) / f"{job_id}_meta.json").write_text(
        json.dumps(meta, indent=2)
    )
    with _lock:
        _jobs[job_id] = job
    _work.put(job_id)
    return {"job_id": job_id, "session_id": preview.session_id}


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

    requested_workflow = workflow
    effective_workflow = _effective_workflow(workflow)
    jid = uuid.uuid4().hex[:8]
    session_id = jid
    session_dir = _session_dir(session_id)
    src = session_dir / "source.mp4"
    src.write_bytes(await file.read())
    job = Job(
        id=jid,
        session_id=session_id,
        name=name,
        email=email.strip(),
        consent=consent,
        workflow=effective_workflow,
        direction=direction,
        speed=speed,
        duration_seconds=duration_seconds,
        src=str(src),
    )
    meta = {
        "job_id": jid,
        "session_id": session_id,
        "name": name,
        "email": email.strip(),
        "consent": consent,
        "workflow": effective_workflow,
        "requested_workflow": requested_workflow,
        "direction": direction,
        "speed": speed,
        "duration_seconds": duration_seconds,
        "source_video": str(src),
        "created": job.created,
    }
    (session_dir / "meta.json").write_text(json.dumps(meta, indent=2))
    with _lock:
        _jobs[jid] = job
    _work.put(jid)
    return {"job_id": jid, "session_id": session_id}


@app.get("/jobs/{jid}")
async def job_status(jid: str):
    job = _jobs.get(jid)
    if job is None:
        return JSONResponse({"error": "not found"}, status_code=404)
    base = _public_base_url()
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
        "force_workflow": FORCE_WORKFLOW or None,
        "smtp_configured": bool(SMTP_USER and SMTP_PASSWORD),
        "jobs": len(_jobs),
    }
