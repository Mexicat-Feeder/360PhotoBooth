"""
Booth backend — app <-> local ComfyUI, multi-style.

Flow:
  POST /jobs (mp4,name,email) -> {job_id}; backend extracts a frame and renders a
       fast stylized STILL for each style (the preview menu).
  GET  /jobs/{id} -> {status, progress, styles:[{id,label,preview_url}], result_url}
       status: previewing -> choose -> rendering -> done | failed
  POST /jobs/{id}/select {style} -> render the full Van-Gogh-style VIDEO for that
       style (AnimateLCM vid2vid) + ffmpeg motion-smoothing.
  GET  /jobs/{id}/preview/{style} -> stylized still (png)
  GET  /jobs/{id}/result -> final stylized mp4

Run:
  COMFY_URL=http://127.0.0.1:8188 BOOTH_PORT=8500 \
    python -m uvicorn booth_backend.server:app --host 0.0.0.0 --port 8500
"""
from __future__ import annotations

import json
import os
import queue
import socket
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from fastapi import FastAPI, Form, UploadFile
from fastapi.responses import JSONResponse, Response

from .comfy_client import ComfyClient
from .styles import BY_ID, NEGATIVE, STYLES

COMFY_URL = os.environ.get("COMFY_URL", "http://127.0.0.1:8188")
WF_DIR = Path(os.environ.get("WF_DIR", "booth_backend/workflows"))
STILL_WF = WF_DIR / "style_still.json"
VIDEO_WF = WF_DIR / "vangogh_vid2vid.json"
PORT = int(os.environ.get("BOOTH_PORT", "8500"))
DATA = Path(os.environ.get("BOOTH_DATA", "booth_backend/_data"))
DATA.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="360 Booth Backend (multi-style)")
comfy = ComfyClient(COMFY_URL)


@dataclass
class Job:
    id: str
    name: str
    email: str
    src: str
    status: str = "previewing"   # previewing|choose|rendering|done|failed
    progress: float = 0.0
    previews: dict = field(default_factory=dict)  # style_id -> png bytes
    selected: str | None = None
    result: str | None = None
    error: str | None = None


_jobs: dict[str, Job] = {}
_lock = threading.Lock()
_work: "queue.Queue[tuple[str, str]]" = queue.Queue()


def _lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def _extract_frame(video: str, out: str) -> bool:
    try:
        # grab a frame ~1.5s in (past the initial motion blur)
        r = subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", "1.5",
             "-i", video, "-frames:v", "1", "-y", out], timeout=30)
        return r.returncode == 0 and Path(out).exists()
    except Exception:
        return False


def _smooth(src: Path, dst: Path, fps: int = 16) -> bool:
    try:
        r = subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(src),
             "-vf", f"minterpolate=fps={fps}:mi_mode=mci:mc_mode=aobmc:vsbmc=1",
             "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
             "-y", str(dst)], timeout=120)
        return r.returncode == 0 and dst.exists()
    except Exception:
        return False


def _do_previews(job: Job) -> None:
    frame = DATA / f"{job.id}_frame.jpg"
    if not _extract_frame(job.src, str(frame)):
        raise RuntimeError("could not extract a frame from the recording")
    frame_name = comfy.upload_image(str(frame))
    wf_tpl = json.loads(STILL_WF.read_text())
    for i, st in enumerate(STYLES):
        wf = json.loads(json.dumps(wf_tpl))
        wf["2"]["inputs"]["image"] = frame_name
        wf["4"]["inputs"]["text"] = st["prompt"]
        wf["9"]["inputs"]["denoise"] = st["denoise"]
        outputs = comfy.run_and_wait(wf, f"{job.id}-prev-{st['id']}")
        found = ComfyClient.find_output_image(outputs)
        if found:
            png = comfy.view_bytes(found[0], found[1], "output")
            with _lock:
                job.previews[st["id"]] = png
        with _lock:
            job.progress = (i + 1) / len(STYLES)
    with _lock:
        job.status = "choose"
        job.progress = 0.0


def _do_render(job: Job) -> None:
    st = BY_ID[job.selected]
    video_name = comfy.upload_video(job.src)
    wf = json.loads(VIDEO_WF.read_text())
    wf["5"]["inputs"]["video"] = video_name
    wf["7"]["inputs"]["text"] = st["prompt"]
    wf["8"]["inputs"]["text"] = NEGATIVE
    wf["12"]["inputs"]["denoise"] = st["denoise"]
    if "14" in wf:
        wf["14"]["inputs"]["filename_prefix"] = f"booth_{job.id}"

    def on_prog(p):
        with _lock:
            job.progress = round(p.fraction, 3)

    outputs = comfy.run_and_wait(wf, f"{job.id}-render", on_progress=on_prog)
    found = ComfyClient.find_output_video(outputs)
    if not found:
        raise RuntimeError("ComfyUI produced no video")
    raw = DATA / f"{job.id}_raw.mp4"
    raw.write_bytes(comfy.view_bytes(found[0], found[1], "output"))
    out = DATA / f"{job.id}.mp4"
    if not _smooth(raw, out):
        out.write_bytes(raw.read_bytes())
    with _lock:
        job.result = str(out)
        job.progress = 1.0
        job.status = "done"


def _worker() -> None:
    while True:
        jid, action = _work.get()
        job = _jobs.get(jid)
        if job is None:
            continue
        try:
            if action == "preview":
                _do_previews(job)
            elif action == "render":
                _do_render(job)
        except Exception as e:  # noqa: BLE001
            with _lock:
                job.status = "failed"
                job.error = str(e)


threading.Thread(target=_worker, daemon=True).start()


@app.post("/jobs")
async def create_job(file: UploadFile, name: str = Form(""), email: str = Form("")):
    jid = uuid.uuid4().hex[:8]
    src = DATA / f"{jid}_src.mp4"
    src.write_bytes(await file.read())
    job = Job(id=jid, name=name, email=email, src=str(src))
    with _lock:
        _jobs[jid] = job
    _work.put((jid, "preview"))
    return {"job_id": jid}


@app.get("/jobs/{jid}")
async def status(jid: str):
    job = _jobs.get(jid)
    if job is None:
        return JSONResponse({"error": "not found"}, status_code=404)
    base = f"http://{_lan_ip()}:{PORT}"
    with _lock:
        styles = [
            {"id": s["id"], "label": s["label"],
             "preview_url": f"{base}/jobs/{jid}/preview/{s['id']}"}
            for s in STYLES if s["id"] in job.previews
        ]
        return {
            "status": job.status,
            "progress": job.progress,
            "selected": job.selected,
            "styles": styles,
            "result_url": f"{base}/jobs/{jid}/result" if job.result else None,
            "error": job.error,
        }


@app.post("/jobs/{jid}/select")
async def select(jid: str, style: str = Form(...)):
    job = _jobs.get(jid)
    if job is None:
        return JSONResponse({"error": "not found"}, status_code=404)
    if style not in BY_ID:
        return JSONResponse({"error": "unknown style"}, status_code=400)
    with _lock:
        job.selected = style
        job.status = "rendering"
        job.progress = 0.0
        job.result = None
    _work.put((jid, "render"))
    return {"ok": True}


@app.get("/jobs/{jid}/preview/{style}")
async def preview(jid: str, style: str):
    job = _jobs.get(jid)
    if job is None or style not in job.previews:
        return JSONResponse({"error": "no preview"}, status_code=404)
    return Response(content=job.previews[style], media_type="image/png")


@app.get("/jobs/{jid}/result")
async def result(jid: str):
    job = _jobs.get(jid)
    if job is None or job.result is None:
        return JSONResponse({"error": "not ready"}, status_code=404)
    return Response(content=Path(job.result).read_bytes(), media_type="video/mp4")


@app.get("/")
async def root():
    return {"ok": True, "comfy": COMFY_URL, "styles": len(STYLES),
            "jobs": len(_jobs)}
