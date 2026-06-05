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
import os
import queue
import socket
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from fastapi import FastAPI, Form, UploadFile
from fastapi.responses import JSONResponse, Response

from .comfy_client import ComfyClient, Progress

COMFY_URL = os.environ.get("COMFY_URL", "http://127.0.0.1:8188")
WORKFLOW_PATH = Path(os.environ.get(
    "WORKFLOW", "booth_backend/workflows/vangogh_vid2vid.json"))
PORT = int(os.environ.get("BOOTH_PORT", "8000"))
DATA = Path(os.environ.get("BOOTH_DATA", "booth_backend/_data"))
DATA.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="360 Booth Backend (ComfyUI)")
comfy = ComfyClient(COMFY_URL)


@dataclass
class Job:
    id: str
    name: str
    email: str
    src: str                       # local path to uploaded mp4
    status: str = "queued"         # queued|generating|done|failed
    progress: float = 0.0
    preview: bytes | None = None   # latest preview jpeg
    result: str | None = None      # local path to stylized mp4
    error: str | None = None
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


def _process(job: Job) -> None:
    if not WORKFLOW_PATH.exists():
        raise RuntimeError(f"workflow not found: {WORKFLOW_PATH} "
                           "(author it in ComfyUI and export API JSON)")
    wf = json.loads(WORKFLOW_PATH.read_text())
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
    out_path = DATA / f"{job.id}.mp4"
    out_path.write_bytes(data)
    with _lock:
        job.result = str(out_path)
        job.progress = 1.0


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
async def create_job(file: UploadFile, name: str = Form(""), email: str = Form("")):
    jid = uuid.uuid4().hex[:8]
    src = DATA / f"{jid}_src.mp4"
    src.write_bytes(await file.read())
    job = Job(id=jid, name=name, email=email, src=str(src))
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
    return {"ok": True, "comfy": COMFY_URL, "jobs": len(_jobs)}
