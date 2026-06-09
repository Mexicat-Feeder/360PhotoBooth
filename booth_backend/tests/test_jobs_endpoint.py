from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path

from fastapi.testclient import TestClient


class QueueSink:
    def __init__(self) -> None:
        self.items: list[str] = []

    def put(self, item: str) -> None:
        self.items.append(item)


def load_server(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("BOOTH_DATA", str(tmp_path))
    monkeypatch.setenv("BOOTH_ENV_FILE", str(tmp_path / "missing.env"))
    sys.modules.pop("booth_backend.server", None)
    server = importlib.import_module("booth_backend.server")

    queue_sink = QueueSink()
    server._work = queue_sink
    server._jobs.clear()
    return server, queue_sink


def test_create_job_persists_upload_metadata_and_queues_job(tmp_path, monkeypatch):
    server, queue_sink = load_server(tmp_path, monkeypatch)
    client = TestClient(server.app)

    video_bytes = b"fake-mp4-bytes"
    response = client.post(
        "/jobs",
        data={
            "name": "Test Guest",
            "email": "guest@example.com",
            "consent": "true",
            "workflow": "vangogh_vid2vid",
            "direction": "clock",
            "speed": "5",
            "duration_seconds": "10",
        },
        files={"file": ("capture.mp4", video_bytes, "video/mp4")},
    )

    assert response.status_code == 200
    job_id = response.json()["job_id"]
    assert len(job_id) == 8
    assert queue_sink.items == [job_id]

    src = tmp_path / f"{job_id}_src.mp4"
    meta_path = tmp_path / f"{job_id}_meta.json"
    assert src.read_bytes() == video_bytes
    assert meta_path.exists()

    meta = json.loads(meta_path.read_text())
    assert meta == {
        "job_id": job_id,
        "name": "Test Guest",
        "email": "guest@example.com",
        "consent": True,
        "workflow": "vangogh_vid2vid",
        "direction": "clock",
        "speed": 5,
        "duration_seconds": 10,
        "source_video": str(src),
        "created": meta["created"],
    }

    job = server._jobs[job_id]
    assert job.name == "Test Guest"
    assert job.email == "guest@example.com"
    assert job.consent is True
    assert job.workflow == "vangogh_vid2vid"
    assert job.direction == "clock"
    assert job.speed == 5
    assert job.duration_seconds == 10
    assert job.src == str(src)
    assert job.status == "queued"


def test_create_job_requires_consent(tmp_path, monkeypatch):
    server, queue_sink = load_server(tmp_path, monkeypatch)
    client = TestClient(server.app)

    response = client.post(
        "/jobs",
        data={
            "name": "Test Guest",
            "email": "guest@example.com",
            "consent": "false",
        },
        files={"file": ("capture.mp4", b"fake-mp4-bytes", "video/mp4")},
    )

    assert response.status_code == 400
    assert response.json() == {"error": "consent required"}
    assert queue_sink.items == []
    assert list(tmp_path.iterdir()) == []


def test_create_job_requires_email(tmp_path, monkeypatch):
    server, queue_sink = load_server(tmp_path, monkeypatch)
    client = TestClient(server.app)

    response = client.post(
        "/jobs",
        data={
            "name": "Test Guest",
            "email": " ",
            "consent": "true",
        },
        files={"file": ("capture.mp4", b"fake-mp4-bytes", "video/mp4")},
    )

    assert response.status_code == 400
    assert response.json() == {"error": "email required"}
    assert queue_sink.items == []
    assert list(tmp_path.iterdir()) == []


def test_job_status_includes_failure_error(tmp_path, monkeypatch):
    server, _ = load_server(tmp_path, monkeypatch)
    client = TestClient(server.app)

    job = server.Job(
        id="deadbeef",
        name="Test Guest",
        email="guest@example.com",
        consent=True,
        workflow="missing_workflow",
        direction="clock",
        speed=5,
        duration_seconds=8,
        src=str(tmp_path / "deadbeef_src.mp4"),
        status="failed",
        error="workflow not found: missing_workflow.json",
    )
    server._jobs[job.id] = job

    response = client.get("/jobs/deadbeef")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "failed"
    assert body["error"] == "workflow not found: missing_workflow.json"
    assert body["result_url"] is None
