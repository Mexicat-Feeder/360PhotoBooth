"""
Generate BACKGROUND-removal / replacement ComfyUI workflows for the booth.

These are a DIFFERENT graph shape from the style presets (make_workflows.py):
no diffusion — just segment the guest out and recomposite onto a new background.
They use the ComfyUI-RMBG custom node (1038lab) with the video-optimized **BEN2**
model, which runs offline.

>>> UNVERIFIED ON THIS MACHINE <<<
ComfyUI cannot run here (Windows iGPU, no models), so the exact node `class_type`
and input keys for ComfyUI-RMBG could differ by version. The JSON is authored
from the v3.x docs but you MUST confirm it on the Strix box: build the graph once
in the ComfyUI UI, "Save (API Format)", and reconcile any key names. See
booth_backend/workflows/README_background.md.

Each output keeps the SAME `VHS_LoadVideo` (node 1) and `VHS_VideoCombine`
(last node) the backend's _patch_workflow expects:
  - VHS_LoadVideo.video        <- patched to the uploaded clip
  - VHS_VideoCombine.filename_prefix <- patched to booth_<jobid>

Run from repo root:
    python scripts/make_bg_workflows.py
    python scripts/make_bg_workflows.py --list
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path

WF_DIR = Path("booth_backend/workflows")

# Default capture settings mirror the style workflows (booth clips are short).
FORCE_RATE = 12.0
FRAME_CAP = 64
SIZE = 512


@dataclass(frozen=True)
class BgPreset:
    name: str
    label: str
    mode: str          # "color" | "image" | "blur"
    color: str = "#000000"   # for mode=color (hex)
    bg_image: str = ""        # for mode=image (filename in ComfyUI input dir)
    blur: int = 25            # for mode=blur (gaussian sigma-ish)


PRESETS: list[BgPreset] = [
    BgPreset("bg_black", "Spotlight (black)", "color", color="#000000"),
    BgPreset("bg_white", "Studio (white)", "color", color="#FFFFFF"),
    BgPreset("bg_magenta", "Neon Pop (magenta)", "color", color="#FF1FA0"),
    BgPreset("bg_blur", "Blurred Backdrop", "blur", blur=30),
    BgPreset("bg_image", "Custom Backdrop (image)", "image",
             bg_image="booth_background.png"),
]


def _load_video_node(video="PLACEHOLDER.mp4") -> dict:
    return {
        "class_type": "VHS_LoadVideo",
        "inputs": {
            "video": video,
            "force_rate": FORCE_RATE,
            "custom_width": SIZE,
            "custom_height": SIZE,
            "frame_load_cap": FRAME_CAP,
            "skip_first_frames": 0,
            "select_every_nth": 1,
            "format": "AnimateDiff",
        },
    }


def _video_combine_node(images_ref, prefix) -> dict:
    return {
        "class_type": "VHS_VideoCombine",
        "inputs": {
            "images": images_ref,
            "frame_rate": FORCE_RATE,
            "loop_count": 0,
            "filename_prefix": prefix,
            "format": "video/h264-mp4",
            "pingpong": False,
            "save_output": True,
        },
    }


def build(p: BgPreset) -> dict:
    """Graph: LoadVideo -> RMBG(BEN2) -> composite onto new bg -> VideoCombine.

    Node ids are strings (ComfyUI API format). The RMBG node outputs
    [IMAGE(0, cutout w/ alpha), MASK(1)]. We rebuild the background per mode and
    composite the cutout over it with ImageCompositeMasked.
    """
    g: dict[str, dict] = {}
    g["1"] = _load_video_node()

    # 2: background removal (BEN2 = video-optimized, less flicker)
    g["2"] = {
        "class_type": "RMBG",
        "inputs": {
            "image": ["1", 0],
            "model": "BEN2",
            "sensitivity": 1.0,
            "process_res": SIZE,
            "mask_blur": 2,
            "mask_offset": 0,
            "background": "Alpha",   # keep transparent; we composite ourselves
            "invert_output": False,
            "refine_foreground": True,
        },
    }
    # cutout image = ["2",0], subject mask = ["2",1]

    if p.mode == "color":
        # solid color plate the size of the frames
        g["3"] = {
            "class_type": "EmptyImage",
            "inputs": {
                "width": SIZE,
                "height": SIZE,
                "batch_size": FRAME_CAP,
                "color": int(p.color.lstrip("#"), 16),
            },
        }
        bg_ref = ["3", 0]
    elif p.mode == "blur":
        # blurred copy of the ORIGINAL frames as the backdrop
        g["3"] = {
            "class_type": "ImageBlur",
            "inputs": {
                "image": ["1", 0],
                "blur_radius": p.blur,
                "sigma": 1.0,
            },
        }
        bg_ref = ["3", 0]
    else:  # image
        # a still backdrop loaded from ComfyUI's input dir, repeated per frame
        g["3"] = {
            "class_type": "LoadImage",
            "inputs": {"image": p.bg_image, "upload": "image"},
        }
        g["4"] = {
            "class_type": "RepeatImageBatch",
            "inputs": {"image": ["3", 0], "amount": FRAME_CAP},
        }
        bg_ref = ["4", 0]

    # composite: subject (cutout) over background using the subject mask
    g["5"] = {
        "class_type": "ImageCompositeMasked",
        "inputs": {
            "destination": bg_ref,
            "source": ["2", 0],
            "mask": ["2", 1],
            "x": 0,
            "y": 0,
            "resize_source": False,
        },
    }

    g["6"] = _video_combine_node(["5", 0], f"booth_{p.name}")
    return g


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ns = ap.parse_args(argv)

    if ns.list:
        for p in PRESETS:
            extra = {"color": p.color, "image": p.bg_image,
                     "blur": p.blur}[p.mode]
            print(f"  {p.name:14} {p.label:24} mode={p.mode} ({extra})")
        return 0

    WF_DIR.mkdir(parents=True, exist_ok=True)
    written = 0
    for p in PRESETS:
        wf = build(p)
        json.dumps(wf)  # serializable check
        out = WF_DIR / f"{p.name}.json"
        out.write_text(json.dumps(wf, indent=2))
        json.loads(out.read_text())  # valid-on-disk check
        print(f"wrote {out}  ({p.label})")
        written += 1

    print(f"\n{written} background workflow(s) in {WF_DIR}/.")
    print("UNVERIFIED: confirm RMBG node keys on the GPU box "
          "(see README_background.md).", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
