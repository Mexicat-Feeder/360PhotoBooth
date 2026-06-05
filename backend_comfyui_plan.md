# Backend — ComfyUI Van Gogh Video Stylization (local on Strix Halo)

Goal: app sends the **720p booth video** → backend runs it through **ComfyUI** →
**Van Gogh–style** AI video → returned to the guest. All **local** on this box.

> This is the real backend that replaces `mock_backend/`. The Flutter app's HTTP
> contract stays the same (`POST /jobs`, `GET /jobs/{id}`, `/jobs/{id}/result`,
> plus `preview_url` during generation), so the app barely changes.

---

## 0. Hardware reality (confirmed on this machine)

- **This box IS the AMD Strix Halo backend**: Ryzen AI Max+ 395, **Radeon 8060S
  iGPU (gfx1151)**, 16c/32t, 128 GB unified memory (62 GB currently visible to the
  OS; rest is BIOS UMA/GTT for the iGPU). Running **Ubuntu 24.04** (not Windows —
  the old notes are obsolete).
- No ROCm / PyTorch / ComfyUI installed yet.
- So "AI compute" = the **Radeon 8060S via ROCm on Linux**. gfx1151 isn't on AMD's
  official ROCm matrix but is proven working in 2026 with the right stack.

---

## 1. Compute stack (how we run ComfyUI on gfx1151)

**Recommended: Docker, AMD's prebuilt ROCm+PyTorch image** (least dependency pain):
- Base `rocm/pytorch` (Ubuntu 24.04, ROCm 7.2, PyTorch 2.9.1) **or** the community
  `comfyui-gfx1151` image (PyTorch + flash-attention prebuilt for gfx1151).
- Run with `--device /dev/kfd --device /dev/dri --group-add video --ipc=host`,
  mount `models/`, `input/`, `output/`, expose **:8188**.
- Fallback (native): TheRock ROCm nightlies + pip PyTorch (rocm) wheels for gfx1151.
- Likely env knobs: `HSA_OVERRIDE_GFX_VERSION=11.5.1` (or `11.0.0`) if a lib
  refuses gfx1151; `PYTORCH_HIP_ALLOC_CONF=expandable_segments:True`; raise the
  BIOS UMA / GTT so the iGPU can map enough VRAM (≥ 32–64 GB).

**Smoke test before anything else:** ROCm sees the GPU (`rocminfo` shows gfx1151),
`torch.cuda.is_available()` is True, and ComfyUI generates one SD1.5 image. That's
the go/no-go gate for the whole backend.

---

## 2. The AI pipeline (ultrathought)

A 360 clip is ~8 s × ~24–30 fps = **200–240 frames** — far too many to diffuse
per-frame at quality within a booth time budget. The pipeline trims + speeds
aggressively and leans on a few-step, temporally-coherent model.

### Chosen approach: **AnimateLCM vid2vid + ControlNet (SD1.5)**
Few-step (LCM) *and* temporally coherent (AnimateDiff) — the sweet spot for an iGPU.

```
input 720p mp4
  │ VHS "Load Video"  → force ~12–15 fps, cap ~48–64 frames, resize short side 512
  ▼
SD1.5 checkpoint (DreamShaper 8 / Photon)            ── style via Van Gogh LoRA
  + AnimateDiff-Evolved  motion = AnimateLCM           and/or prompt:
  + LCM sampler, 6–8 steps, cfg ~1.8                   "Vincent van Gogh, Starry
  + ControlNet  lineart/softedge  (strength ~0.6)       Night, swirling impasto
      from source frames → preserves the person+motion   oil brushstrokes"
  + img2img denoise ~0.6 (higher = more painterly)     neg: "photo, realistic"
  ▼ KSampler (LCM) → VAE decode → stylized frames
  │ (optional) RIFE ×2 interpolation → smoother / higher fps
  ▼ VHS "Video Combine" → H.264 mp4  (hardware encode if available)
output mp4  → returned to the guest
```

**Why each piece**
- **AnimateLCM** = AnimateDiff coherence + LCM speed → no flicker, few steps.
- **ControlNet lineart/softedge** keeps the guest recognizable while the style is
  applied (this is what makes it "them, as a Van Gogh" not random art).
- **LCM 6–8 steps** instead of 20–30 → ~3–5× faster, essential on the iGPU.
- **Trim/downscale** → frame count is the #1 time lever.

### Models / custom nodes to install (SD1.5 stack, ROCm-friendly)
| Need | Model / node |
|---|---|
| Base | SD1.5 checkpoint (DreamShaper 8 or Photon) |
| Motion+speed | AnimateLCM motion module + AnimateLCM LoRA |
| (or) speed | LCM-LoRA SD1.5 |
| Structure | ControlNet `control_v11p_sd15_lineart` (+ `comfyui_controlnet_aux` preproc) |
| Style | Van Gogh LoRA (civitai) — or prompt-only to start |
| Smooth | RIFE (`ComfyUI-Frame-Interpolation`) — optional |
| Video IO | `ComfyUI-VideoHelperSuite` (Load Video / Video Combine) |
| Animate | `ComfyUI-AnimateDiff-Evolved`, `ComfyUI-Advanced-ControlNet` |

> Avoid CUDA-only nodes (xformers etc.) — use PyTorch attention on ROCm.

### Fallback for reliability: **fast neural style transfer**
A feed-forward Van Gogh model (Johnson et al. style) per-frame + optical-flow
deflicker runs in **seconds**, very stable, unmistakably Van Gogh. Less
"generative wow", but a bulletproof safety net if diffusion is too slow/flaky at
the event. Keep it as a one-switch fallback.

---

## 3. Backend service (replaces the mock; same API)

A FastAPI service (`booth_backend/`) that brokers between the app and ComfyUI.

```
Flutter app                 booth_backend (FastAPI :8000)        ComfyUI (:8188)
 POST /jobs (mp4,name,email) ─► save mp4, create job
                                upload mp4 to ComfyUI input ──────► /upload/image
                                submit workflow (API JSON) ───────► POST /prompt
                                listen ComfyUI websocket ◄───────── /ws (progress,
 GET /jobs/{id} (poll) ◄──────  map node/step → progress %,         KSampler preview)
   {progress, preview_url,      cache latest preview frame
    status, result_url}
                                on finish: fetch output ◄────────── GET /view
 GET /jobs/{id}/result ◄──────  serve stored stylized mp4
```

- **ComfyUI API**: `POST /upload/image` (works for video), `POST /prompt` with the
  workflow's **API-format JSON** (placeholders for input filename + style/denoise/
  steps), `GET /ws?clientId=...` for live progress + preview images,
  `GET /history/{prompt_id}` + `GET /view?filename=...` for the result.
- **Live "generating" preview**: relay ComfyUI's KSampler preview frames as
  `preview_url` — the app's processing screen already renders it.
- **Job queue**: one job at a time (single iGPU); FastAPI + an asyncio worker.
- **Delivery URL**: result served on the **LAN IP** (not localhost) so the QR works
  on a phone — bind `0.0.0.0`, build the QR with the box's LAN address.
- The Flutter app only needs its `backendBaseUrl()` pointed at this box's LAN IP
  (already overridable via `--dart-define=BOOTH_BACKEND`).

---

## 4. Time budget (needs benchmarking on gfx1151)

| Step | Estimate |
|---|---|
| Upload 720p clip (LAN) | 1–3 s |
| Load/trim/resize (48–64 frames @ 512) | 2–4 s |
| AnimateLCM 6–8 step + ControlNet | **30–120 s** (the unknown — benchmark) |
| RIFE + encode | 3–8 s |
| **Total** | target ≤ ~90–120 s |

Levers if too slow: fewer frames (32), lower res (448), fewer steps (4–6), drop
RIFE, drop ControlNet to depth-only. First MIOpen run is slow (kernel cache) —
**always pre-warm** before doors open.

---

## 5. Risks & mitigations
| Risk | Mitigation |
|---|---|
| gfx1151 ROCm instability / memory-access faults | Use AMD's prebuilt image; pin known-good ROCm; `HSA_OVERRIDE_GFX_VERSION`; pre-warm |
| Too slow for booth budget | few-step LCM, trim frames/res, neural-style fallback |
| Temporal flicker | AnimateLCM context windows + ControlNet + RIFE |
| Person unrecognizable | raise ControlNet strength / lower denoise |
| A custom node needs CUDA | swap for ROCm-safe equivalent; PyTorch attention |
| QR unreachable from phone | serve result on LAN IP; same Wi-Fi/AP as before |

---

## 6. Build order
1. **ROCm bring-up + smoke test** — GPU visible, torch CUDA True, one SD1.5 image. (gate)
2. **ComfyUI up** (Docker) on :8188 + custom nodes + models downloaded.
3. **Author the workflow in the ComfyUI UI** (Van Gogh AnimateLCM vid2vid) by hand
   on a sample clip until the look + time are right; export **API JSON**.
4. **`booth_backend/`** FastAPI: upload → /prompt → /ws progress → /view result;
   same endpoints as the mock.
5. **Point the app** at the box LAN IP; end-to-end with the real booth + real gen.
6. **Pre-warm + fallback** (neural style) wired; benchmark + tune to budget.

## 7. Decisions to confirm
- **Run mode**: Docker (AMD prebuilt image, recommended) vs native ROCm install?
- **Model family**: SD1.5 + AnimateLCM (recommended, fast on iGPU) vs SDXL (nicer,
  slower) vs Wan2.1-VACE (reference-image v2v, heaviest)?
- **Style source**: Van Gogh **LoRA** (more reliable) vs **prompt-only** (zero
  download) to start?
- **Scope now**: stand up ROCm+ComfyUI and prove one stylized clip first, then wire
  the backend service?
