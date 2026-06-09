"""
Generate MOTION / FORMAT ComfyUI workflows for the booth — the cornerstone 360
effects, done entirely in ComfyUI (no separate ffmpeg path):

  slowmo       RIFE VFI frame interpolation -> buttery slow motion (the #1 effect)
  boomerang    VHS_VideoCombine pingpong = forward then reverse loop
  vertical     letterboxed 9:16 for Reels/TikTok
  slowmo_vert  slow-mo + 9:16 (the social-ready combo)

No checkpoint / diffusion — these are light graphs. They keep the SAME
`VHS_LoadVideo` (node 1) and `VHS_VideoCombine` (last node) the backend's
_patch_workflow expects.

>>> RIFE needs a custom node <<<
slowmo/slowmo_vert use **ComfyUI-Frame-Interpolation** (Fannovel16), node
`class_type: "RIFE VFI"`. Install it via ComfyUI-Manager; the rife model
auto-downloads. boomerang/vertical use only core + VHS nodes. Verify node keys on
the GPU box (Save API Format) — see README_motion.md.

Run from repo root:
    python scripts/make_motion_workflows.py
    python scripts/make_motion_workflows.py --list
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path

WF_DIR = Path("booth_backend/workflows")

# Capture: keep native fps high enough that slow-mo looks smooth after RIFE.
LOAD_RATE = 30.0
FRAME_CAP = 240          # ~8 s at 30 fps; booth clips are short
SIZE_W = 720
SIZE_H = 720


@dataclass(frozen=True)
class MotionPreset:
    name: str
    label: str
    slowmo: bool = False      # insert RIFE VFI
    multiplier: int = 2       # RIFE: frames generated between each pair
    out_fps: float = 30.0     # VideoCombine frame_rate (lower vs source = slower)
    boomerang: bool = False   # VHS pingpong
    vertical: bool = False    # pad to 9:16


PRESETS: list[MotionPreset] = [
    MotionPreset("slowmo", "Slow Motion", slowmo=True, multiplier=2, out_fps=30),
    MotionPreset("boomerang", "Boomerang", boomerang=True, out_fps=30),
    MotionPreset("vertical", "Vertical 9:16", vertical=True, out_fps=30),
    MotionPreset("slowmo_vert", "Slow-Mo Vertical", slowmo=True, multiplier=2,
                 out_fps=30, vertical=True),
]


def _load_video_node() -> dict:
    return {
        "class_type": "VHS_LoadVideo",
        "inputs": {
            "video": "PLACEHOLDER.mp4",
            "force_rate": LOAD_RATE,
            "custom_width": SIZE_W,
            "custom_height": SIZE_H,
            "frame_load_cap": FRAME_CAP,
            "skip_first_frames": 0,
            "select_every_nth": 1,
            "format": "AnimateDiff",
        },
    }


def _rife_node(frames_ref) -> dict:
    return {
        "class_type": "RIFE VFI",
        "inputs": {
            "frames": frames_ref,
            "ckpt_name": "rife47.pth",
            "clear_cache_after_n_frames": 10,
            "multiplier": 2,
            "fast_mode": True,
            "ensemble": True,
            "scale_factor": 1.0,
        },
    }


def _vertical_node(image_ref) -> dict:
    # Pad/letterbox the square frames into a 9:16 canvas (1080x1920-ish ratio).
    # ImagePadForOutpaint adds borders; we center the subject.
    # 720 wide -> 9:16 height = 720*16/9 = 1280.
    pad = (1280 - SIZE_H) // 2
    return {
        "class_type": "ImagePadForOutpaint",
        "inputs": {
            "image": image_ref,
            "left": 0,
            "right": 0,
            "top": pad,
            "bottom": pad,
            "feathering": 0,
        },
    }


def _video_combine_node(images_ref, prefix, fps, pingpong) -> dict:
    return {
        "class_type": "VHS_VideoCombine",
        "inputs": {
            "images": images_ref,
            "frame_rate": fps,
            "loop_count": 0,
            "filename_prefix": prefix,
            "format": "video/h264-mp4",
            "pingpong": pingpong,
            "save_output": True,
        },
    }


def build(p: MotionPreset) -> dict:
    g: dict[str, dict] = {}
    g["1"] = _load_video_node()
    ref = ["1", 0]
    nid = 2

    if p.slowmo:
        g[str(nid)] = _rife_node(ref)
        g[str(nid)]["inputs"]["multiplier"] = p.multiplier
        ref = [str(nid), 0]
        nid += 1

    if p.vertical:
        g[str(nid)] = _vertical_node(ref)
        ref = [str(nid), 0]
        nid += 1

    g[str(nid)] = _video_combine_node(ref, f"booth_{p.name}", p.out_fps,
                                      p.boomerang)
    return g


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ns = ap.parse_args(argv)

    if ns.list:
        for p in PRESETS:
            tags = ",".join(t for t, on in (
                ("slowmo", p.slowmo), ("boomerang", p.boomerang),
                ("vertical", p.vertical)) if on) or "—"
            print(f"  {p.name:14} {p.label:18} [{tags}]")
        return 0

    WF_DIR.mkdir(parents=True, exist_ok=True)
    written = 0
    for p in PRESETS:
        wf = build(p)
        json.dumps(wf)
        out = WF_DIR / f"{p.name}.json"
        out.write_text(json.dumps(wf, indent=2))
        json.loads(out.read_text())
        print(f"wrote {out}  ({p.label})")
        written += 1

    print(f"\n{written} motion/format workflow(s) in {WF_DIR}/.")
    print("slowmo* need ComfyUI-Frame-Interpolation (RIFE). Verify node keys on "
          "the GPU box — see README_motion.md.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
