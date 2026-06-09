# ComfyUI workflows

Each `*.json` is an **API-format** ComfyUI graph. The app picks a look by sending
the **file stem** as the `workflow` field (`POST /jobs`); the backend loads
`workflows/<name>.json` and patches per job:
- the `VHS_LoadVideo` node's `video` input  -> the uploaded guest clip
- the `VHS_VideoCombine` node's `filename_prefix` -> `booth_<jobid>`

Style/prompt/LoRA/steps/denoise live in the template itself.

## Available looks
`vangogh_vid2vid` is the hand-built base (export from the ComfyUI UI via
"Save (API Format)"). The rest are generated from it by
`scripts/make_workflows.py`, which only changes the prompt + a few tuning values:

| workflow name | look | denoise | controlnet |
|---|---|---|---|
| `vangogh_vid2vid` | Van Gogh | 0.70 | 0.60 |
| `anime` | Anime | 0.65 | 0.70 |
| `watercolor` | Watercolor | 0.72 | 0.55 |
| `comic` | Comic Book | 0.68 | 0.72 |
| `cyberpunk` | Cyberpunk Neon | 0.62 | 0.65 |
| `ukiyoe` | Ukiyo-e | 0.74 | 0.58 |
| `popart` | Pop Art | 0.70 | 0.66 |
| `claymation` | Claymation | 0.66 | 0.68 |
| `pencil` | Pencil Sketch | 0.64 | 0.75 |

All share the same models/custom nodes (DreamShaper 8 + AnimateLCM + ControlNet
lineart) — adding looks needs **no extra downloads**.
- **denoise** higher = more transformed / more painterly.
- **controlnet** higher = the guest stays more recognizable.

## Background removal / replacement (different effect family)
`bg_black`, `bg_white`, `bg_magenta`, `bg_blur`, `bg_image` segment the guest out
and recomposite on a new background (no diffusion — much faster). They use the
**ComfyUI-RMBG / BEN2** custom node and are **generated + documented separately**
in `README_background.md` (and `scripts/make_bg_workflows.py`).
**These are unverified on the authoring machine — confirm on the GPU box.**

## Motion / format (the cornerstone 360 effects)
`slowmo`, `boomerang`, `vertical`, `slowmo_vert` — slow motion (RIFE), boomerang
loop, and 9:16 vertical, all as ComfyUI graphs (no ffmpeg path). Generated +
documented in `README_motion.md` (and `scripts/make_motion_workflows.py`).
`slowmo*` need the **ComfyUI-Frame-Interpolation** custom node; the others use
only core + VHS nodes. **Verify node keys on the GPU box.**

## The in-app picker (how guests choose a look)
The app shows a **style picker** (info → pick a look → preview) populated from
`GET /workflows`, which the backend builds from `booth_backend/catalog.py` —
filtered to only the looks whose `<id>.json` exists on disk. The guest's choice is
sent back as the `workflow` field on `POST /jobs`.

- **Single source of truth:** `booth_backend/catalog.py` (id, label, family,
  blurb). The app keeps a matching offline fallback (`kFallbackCatalog` in
  `app/lib/backend/backend_client.dart`) so the picker works even before the
  backend is reachable.
- **Add a look → it appears automatically:** drop a new `<id>.json` here AND add a
  one-line entry to `catalog.py` (and, to keep offline parity, the Dart fallback).
  If you skip `catalog.py`, the file still works via `BOOTH_WORKFLOW`/`-F workflow`
  but won't show in the picker.

### Per-look availability (custom-node safety net)
`GET /workflows` checks each look's node types against ComfyUI's `/object_info`
(cached ~30 s) and marks looks whose custom node is missing as
`available: false` with a `reason` (e.g. "needs ComfyUI-RMBG"). The picker shows
those greyed-out + locked and won't let a guest select them. As a backstop, the
backend also pre-flights `POST /jobs` and returns a friendly "this look isn't
available" error instead of a cryptic ComfyUI 400. If ComfyUI is unreachable, the
check is skipped (nothing is hidden) so a transient blip doesn't empty the picker.
So: install `ComfyUI-RMBG` to unlock the `bg_*` looks and
`ComfyUI-Frame-Interpolation` to unlock `slowmo*`; the rest work out of the box.

## Effect families at a glance
| family | workflows | extra custom node |
|---|---|---|
| AI style | vangogh_vid2vid, anime, watercolor, comic, cyberpunk, ukiyoe, popart, claymation, pencil | (base diffusion stack) |
| Background | bg_black, bg_white, bg_magenta, bg_blur, bg_image | ComfyUI-RMBG (BEN2) |
| Motion/format | slowmo, boomerang, vertical, slowmo_vert | ComfyUI-Frame-Interpolation (slowmo only) |

## Add or tune a look
Edit the `PRESETS` list in `scripts/make_workflows.py`, then:
```bash
python scripts/make_workflows.py          # regenerates every non-base JSON
python scripts/make_workflows.py --list   # preview the catalog
```
Or for a fully custom graph, build it in the ComfyUI UI and drop the exported
API JSON here as `<name>.json` — the backend will serve it by name automatically.
