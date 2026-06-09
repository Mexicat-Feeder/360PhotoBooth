"""
Generate ComfyUI workflow presets for the booth from the base AnimateLCM vid2vid
template (booth_backend/workflows/vangogh_vid2vid.json).

Every preset shares the SAME models/custom nodes as the base (DreamShaper 8 +
AnimateLCM + ControlNet lineart) and differs only by:
  * positive prompt (the look)
  * negative prompt (optional override)
  * denoise        (node 12) — higher = more transformed / more painterly
  * cn_strength     (node 10) — higher = guest stays more recognizable
  * steps / cfg     (node 12) — usually left at the LCM defaults

So adding looks needs NO extra downloads. The app picks a look by sending the
workflow NAME (file stem); the server loads workflows/<name>.json.

Run from repo root:
    python scripts/make_workflows.py            # write + validate all presets
    python scripts/make_workflows.py --list     # just print the catalog
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path

WF_DIR = Path("booth_backend/workflows")
BASE = WF_DIR / "vangogh_vid2vid.json"

NEG_DEFAULT = ("photograph, realistic, blurry, low quality, deformed, "
               "extra limbs, text, watermark, jpeg artifacts")


@dataclass(frozen=True)
class Preset:
    name: str            # file stem == the workflow name the app sends
    label: str           # human label (for the app catalog / docs)
    prompt: str
    denoise: float = 0.7
    cn_strength: float = 0.6
    steps: int = 6
    cfg: float = 1.8
    neg: str = NEG_DEFAULT


# The catalog. vangogh_vid2vid is the existing base; the rest are new.
PRESETS: list[Preset] = [
    Preset(
        "vangogh_vid2vid", "Van Gogh",
        "a portrait in the style of Vincent van Gogh, Starry Night, swirling "
        "thick impasto oil brushstrokes, post-impressionist painting, vibrant "
        "blues and yellows",
        denoise=0.70, cn_strength=0.60),
    Preset(
        "anime", "Anime",
        "anime key visual, cel shaded, clean bold lineart, vibrant flat colors, "
        "studio anime portrait, highly detailed, trending on pixiv",
        denoise=0.65, cn_strength=0.70),
    Preset(
        "watercolor", "Watercolor",
        "delicate watercolor painting, soft wet-on-wet washes, bleeding pigment, "
        "pastel palette, textured cold-press paper, loose painterly portrait",
        denoise=0.72, cn_strength=0.55),
    Preset(
        "comic", "Comic Book",
        "comic book illustration, bold black ink outlines, flat cel colors, "
        "halftone ben-day dots, dynamic graphic novel portrait",
        denoise=0.68, cn_strength=0.72),
    Preset(
        "cyberpunk", "Cyberpunk Neon",
        "cyberpunk neon portrait, glowing magenta and cyan rim light, rainy "
        "night city bokeh, blade-runner cinematic, high contrast, detailed",
        denoise=0.62, cn_strength=0.65),
    Preset(
        "ukiyoe", "Ukiyo-e",
        "ukiyo-e japanese woodblock print, Hokusai style, flat color planes, "
        "bold outlines, delicate linework, edo period art",
        denoise=0.74, cn_strength=0.58),
    Preset(
        "popart", "Pop Art",
        "Andy Warhol pop art, bold saturated complementary colors, high "
        "contrast screenprint, graphic flat shading, iconic portrait",
        denoise=0.70, cn_strength=0.66),
    Preset(
        "claymation", "Claymation",
        "claymation character, sculpted plasticine, soft studio lighting, "
        "stop-motion aardman style, tactile fingerprints, 3d clay portrait",
        denoise=0.66, cn_strength=0.68),
    Preset(
        "pencil", "Pencil Sketch",
        "detailed graphite pencil sketch, hand-drawn cross-hatching, soft "
        "shading, sketchbook portrait, monochrome",
        denoise=0.64, cn_strength=0.75),
]


def build(base: dict, p: Preset) -> dict:
    wf = json.loads(json.dumps(base))  # deep copy
    for node in wf.values():
        ct = node.get("class_type", "")
        ins = node.get("inputs", {})
        if ct == "CLIPTextEncode":
            txt = str(ins.get("text", "")).lower()
            is_neg = any(w in txt for w in
                         ("photograph", "realistic", "blurry", "low quality",
                          "deformed", "watermark", "worst"))
            ins["text"] = p.neg if is_neg else p.prompt
        elif ct == "ControlNetApplyAdvanced":
            ins["strength"] = p.cn_strength
        elif ct == "KSampler":
            ins["denoise"] = p.denoise
            ins["steps"] = p.steps
            ins["cfg"] = p.cfg
        elif ct == "VHS_VideoCombine":
            ins["filename_prefix"] = f"booth_{p.name}"
    return wf


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print catalog, write nothing")
    ns = ap.parse_args(argv)

    if ns.list:
        for p in PRESETS:
            print(f"  {p.name:18} {p.label:16} denoise={p.denoise} cn={p.cn_strength}")
        return 0

    if not BASE.exists():
        print(f"base workflow missing: {BASE}", file=sys.stderr)
        return 1
    base = json.loads(BASE.read_text())

    written = 0
    for p in PRESETS:
        if p.name == BASE.stem:
            continue  # don't overwrite the hand-made base
        out = WF_DIR / f"{p.name}.json"
        wf = build(base, p)
        json.loads(json.dumps(wf))  # validate serializable
        out.write_text(json.dumps(wf, indent=2))
        # re-read to confirm valid JSON on disk
        json.loads(out.read_text())
        print(f"wrote {out}  ({p.label})")
        written += 1

    print(f"\n{written} new workflow(s) in {WF_DIR}/  "
          f"(+ base {BASE.name}). App sends the file stem as the workflow name.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
