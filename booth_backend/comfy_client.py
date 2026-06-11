"""
Thin client for a local ComfyUI server (HTTP + WebSocket API).

Endpoints used:
  POST /upload/image           upload the guest clip into ComfyUI's input dir
  POST /prompt                 queue a workflow (API-format JSON) -> prompt_id
  GET  /history/{prompt_id}    fetch outputs once finished
  GET  /view                   download an output file
  WS   /ws?clientId=...        live progress + KSampler preview frames
"""
from __future__ import annotations

import json
import os
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import requests
import websocket  # websocket-client


@dataclass
class Progress:
    value: int = 0
    max: int = 0
    node: str | None = None

    @property
    def fraction(self) -> float:
        return (self.value / self.max) if self.max else 0.0


class ComfyClient:
    def __init__(self, base_url: str = "http://127.0.0.1:8188"):
        self.base = base_url.rstrip("/")
        self.ws_base = "ws" + self.base[len("http"):]
        output_dir = os.environ.get("COMFY_OUTPUT_DIR", "").strip()
        self.output_dir = Path(output_dir) if output_dir else None

    # --- HTTP ---------------------------------------------------------------
    def upload_video(self, path: str) -> str:
        """Upload a file into ComfyUI's input folder; returns the stored name."""
        with open(path, "rb") as f:
            r = requests.post(
                f"{self.base}/upload/image",
                files={"image": (Path(path).name, f, "video/mp4")},
                data={"type": "input", "overwrite": "true"},
                timeout=120,
            )
        r.raise_for_status()
        j = r.json()
        name = j["name"]
        if j.get("subfolder"):
            name = f"{j['subfolder']}/{name}"
        return name

    def queue_prompt(self, workflow: dict, client_id: str) -> str:
        r = requests.post(
            f"{self.base}/prompt",
            json={"prompt": workflow, "client_id": client_id},
            timeout=60,
        )
        if r.status_code >= 400:
            raise RuntimeError(f"/prompt failed {r.status_code}: {r.text}")
        return r.json()["prompt_id"]

    def history(self, prompt_id: str) -> dict:
        r = requests.get(f"{self.base}/history/{prompt_id}", timeout=30)
        r.raise_for_status()
        return r.json()

    def node_types(self) -> set[str]:
        """All node class_types registered in this ComfyUI (from /object_info).
        Returns an empty set if ComfyUI is unreachable — callers treat empty as
        'unknown', not 'nothing available'."""
        try:
            r = requests.get(f"{self.base}/object_info", timeout=10)
            r.raise_for_status()
            return set(r.json().keys())
        except Exception:  # noqa: BLE001
            return set()

    def view_bytes(self, filename: str, subfolder: str = "", type_: str = "output") -> bytes:
        local = self._local_view_path(filename, subfolder, type_)
        if local is not None and local.exists():
            return local.read_bytes()

        q = urllib.parse.urlencode(
            {"filename": filename, "subfolder": subfolder, "type": type_})
        try:
            r = requests.get(f"{self.base}/view?{q}", timeout=120)
            r.raise_for_status()
            return r.content
        except requests.RequestException:
            if local is not None and local.exists():
                return local.read_bytes()
            raise

    def _local_view_path(
        self,
        filename: str,
        subfolder: str = "",
        type_: str = "output",
    ) -> Path | None:
        if self.output_dir is None or type_ != "output":
            return None
        base = self.output_dir.resolve()
        candidate = (base / subfolder / filename).resolve()
        try:
            candidate.relative_to(base)
        except ValueError:
            return None
        return candidate

    # --- WebSocket ----------------------------------------------------------
    def run_and_wait(
        self,
        workflow: dict,
        client_id: str,
        on_progress: Callable[[Progress], None] | None = None,
        on_preview: Callable[[bytes], None] | None = None,
        timeout_s: float = 600,
    ) -> dict:
        """Queue the workflow and block until it finishes; returns history outputs.
        Calls on_progress(Progress) and on_preview(jpeg_bytes) as they arrive."""
        ws = websocket.create_connection(
            f"{self.ws_base}/ws?clientId={client_id}", timeout=timeout_s)
        try:
            prompt_id = self.queue_prompt(workflow, client_id)
            prog = Progress()
            while True:
                msg = ws.recv()
                if isinstance(msg, bytes):
                    # binary = preview image; first 8 bytes are a type header
                    if on_preview and len(msg) > 8:
                        on_preview(msg[8:])
                    continue
                data = json.loads(msg)
                t = data.get("type")
                d = data.get("data", {})
                if t == "progress":
                    prog = Progress(d.get("value", 0), d.get("max", 0), prog.node)
                    if on_progress:
                        on_progress(prog)
                elif t == "executing":
                    prog.node = d.get("node")
                    # node == None and matching prompt_id => finished
                    if d.get("node") is None and d.get("prompt_id") == prompt_id:
                        break
                elif t == "execution_error":
                    raise RuntimeError(f"ComfyUI error: {d}")
            return self.history(prompt_id).get(prompt_id, {})
        finally:
            ws.close()

    @staticmethod
    def find_output_video(outputs: dict) -> tuple[str, str] | None:
        """Scan history outputs for a produced video/gif/mp4 (VideoHelperSuite)."""
        for node in outputs.get("outputs", {}).values():
            for key in ("gifs", "videos", "images"):
                for item in node.get(key, []) or []:
                    fn = item.get("filename", "")
                    if fn.lower().endswith((".mp4", ".webm", ".gif", ".mov")):
                        return fn, item.get("subfolder", "")
        return None
