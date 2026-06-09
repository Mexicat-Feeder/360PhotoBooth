"""
The booth's workflow catalog — the single source of truth for which looks the app
offers and how they're labelled/grouped. Served to the app via GET /workflows.

Each entry's `id` is the workflow file stem (booth_backend/workflows/<id>.json),
which is exactly what the app sends back as the `workflow` field on POST /jobs.

`available()` returns only the looks whose JSON actually exists on disk, so the
picker never offers a workflow the backend can't run.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

WORKFLOW_DIR_DEFAULT = Path(__file__).resolve().parent / "workflows"

# Display order of the families in the picker.
FAMILY_ORDER = ["style", "background", "motion"]
FAMILY_LABELS = {
    "style": "AI Styles",
    "background": "Backgrounds",
    "motion": "Motion & Format",
}


@dataclass(frozen=True)
class Look:
    id: str          # == workflow file stem
    label: str
    family: str      # style | background | motion
    blurb: str
    needs: str = ""  # extra custom node the GPU box must have (for ops docs)


CATALOG: list[Look] = [
    # --- AI styles (diffusion restyle) ---
    Look("vangogh_vid2vid", "Van Gogh", "style",
         "Swirling impasto oil — the hero look"),
    Look("anime", "Anime", "style", "Clean cel-shaded anime"),
    Look("watercolor", "Watercolor", "style", "Soft washed painting"),
    Look("comic", "Comic Book", "style", "Bold ink & flat color"),
    Look("cyberpunk", "Cyberpunk", "style", "Neon rain, blade-runner glow"),
    Look("ukiyoe", "Ukiyo-e", "style", "Japanese woodblock print"),
    Look("popart", "Pop Art", "style", "Warhol screenprint pop"),
    Look("claymation", "Claymation", "style", "Sculpted stop-motion clay"),
    Look("pencil", "Pencil Sketch", "style", "Hand-drawn graphite"),
    # --- Background removal / replacement (RMBG/BEN2) ---
    Look("bg_black", "Spotlight", "background", "Guest on solid black",
         needs="ComfyUI-RMBG"),
    Look("bg_white", "Studio", "background", "Guest on clean white",
         needs="ComfyUI-RMBG"),
    Look("bg_magenta", "Neon Pop", "background", "Guest on neon magenta",
         needs="ComfyUI-RMBG"),
    Look("bg_blur", "Blurred Backdrop", "background",
         "Guest sharp, background blurred", needs="ComfyUI-RMBG"),
    Look("bg_image", "Custom Backdrop", "background",
         "Guest on your own image", needs="ComfyUI-RMBG"),
    # --- Motion / format ---
    Look("slowmo", "Slow Motion", "motion", "Buttery RIFE slow-mo",
         needs="ComfyUI-Frame-Interpolation"),
    Look("boomerang", "Boomerang", "motion", "Forward then reverse loop"),
    Look("vertical", "Vertical 9:16", "motion", "Ready for Reels/TikTok"),
    Look("slowmo_vert", "Slow-Mo Vertical", "motion",
         "Slow-mo + 9:16 combo", needs="ComfyUI-Frame-Interpolation"),
]

CATALOG_BY_ID: dict[str, Look] = {look.id: look for look in CATALOG}


def available(workflow_dir: Path | None = None) -> list[Look]:
    """Catalog entries whose <id>.json exists in the workflow dir."""
    wf_dir = workflow_dir or WORKFLOW_DIR_DEFAULT
    return [look for look in CATALOG if (wf_dir / f"{look.id}.json").exists()]


def required_nodes(look_id: str, workflow_dir: Path | None = None) -> set[str]:
    """The set of ComfyUI node class_types a workflow uses (empty if unreadable)."""
    wf_dir = workflow_dir or WORKFLOW_DIR_DEFAULT
    path = wf_dir / f"{look_id}.json"
    try:
        wf = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return set()
    return {n.get("class_type", "") for n in wf.values() if isinstance(n, dict)}


def missing_nodes(look_id: str, installed: set[str],
                  workflow_dir: Path | None = None) -> list[str]:
    """Node class_types this workflow needs that ComfyUI does NOT have.
    With `installed` empty (ComfyUI unknown), returns [] — we don't claim missing
    when we simply couldn't ask."""
    if not installed:
        return []
    return sorted(required_nodes(look_id, workflow_dir) - installed)


def as_json(workflow_dir: Path | None = None,
            installed: set[str] | None = None) -> dict:
    """Payload for GET /workflows: grouped families + flat list, on-disk only.

    If `installed` (ComfyUI's node set) is given, each look also reports
    `available` and, when unavailable, a `reason` naming the missing node(s).
    A look with `installed` unknown (None/empty) is reported available — we don't
    block on a check we couldn't run."""
    wf_dir = workflow_dir or WORKFLOW_DIR_DEFAULT
    looks = available(wf_dir)
    nodes = installed or set()

    def entry(look: Look) -> dict:
        miss = missing_nodes(look.id, nodes, wf_dir)
        d = _look_dict(look)
        d["available"] = not miss
        if miss:
            d["reason"] = f"needs {look.needs or ', '.join(miss)}"
        return d

    groups = []
    for fam in FAMILY_ORDER:
        items = [entry(look) for look in looks if look.family == fam]
        if items:
            groups.append({
                "family": fam,
                "label": FAMILY_LABELS.get(fam, fam.title()),
                "items": items,
            })
    return {
        "default": "vangogh_vid2vid",
        "comfy_known": bool(nodes),
        "families": groups,
        "looks": [entry(look) for look in looks],
    }


def _look_dict(look: Look) -> dict:
    return {"id": look.id, "label": look.label,
            "family": look.family, "blurb": look.blurb}
