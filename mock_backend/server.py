"""
Mock booth backend — stands in for the real AMD ComfyUI/CyberLink pipeline so the
Flutter app's full flow (upload -> generating -> result) works locally on one PC.

Same HTTP contract the real backend will expose; to go live, point the app at the
AMD box's LAN IP instead of localhost.

Run:
    pip install --user --break-system-packages -r mock_backend/requirements.txt
    python -m uvicorn mock_backend.server:app --host 0.0.0.0 --port 8000
"""
from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field

from fastapi import FastAPI, Form, UploadFile
from fastapi.responses import JSONResponse, Response

app = FastAPI(title="360 Booth — Mock Backend")

# Simulated generation time (seconds) for a guest job.
GEN_SECONDS = 7.0


@dataclass
class Job:
    id: str
    name: str
    email: str
    video: bytes
    created: float = field(default_factory=time.time)

    @property
    def progress(self) -> float:
        return min(1.0, (time.time() - self.created) / GEN_SECONDS)

    @property
    def status(self) -> str:
        return "done" if self.progress >= 1.0 else "generating"


JOBS: dict[str, Job] = {}


@app.post("/jobs")
async def create_job(file: UploadFile, name: str = Form(""), email: str = Form("")):
    job = Job(id=uuid.uuid4().hex[:8], name=name, email=email,
              video=await file.read())
    JOBS[job.id] = job
    return {"job_id": job.id}


@app.get("/jobs/{job_id}")
async def job_status(job_id: str):
    job = JOBS.get(job_id)
    if job is None:
        return JSONResponse({"error": "not found"}, status_code=404)
    done = job.status == "done"
    return {
        "status": job.status,
        "progress": round(job.progress, 3),
        "preview_url": None,
        "result_url": f"/jobs/{job_id}/result" if done else None,
    }


@app.get("/jobs/{job_id}/result")
async def job_result(job_id: str):
    job = JOBS.get(job_id)
    if job is None:
        return JSONResponse({"error": "not found"}, status_code=404)
    # echo the uploaded clip back as the "stylized" result (mock)
    return Response(content=job.video, media_type="video/mp4")


@app.get("/")
async def root():
    return {"ok": True, "jobs": len(JOBS)}
