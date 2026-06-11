# ComfyUI workflows

The production guest flow does not use a pre-capture style picker.

Current flow:

1. The phone records and uploads the booth video to `POST /preview-jobs`.
2. The backend generates four short preview MP4s from the captured video.
3. The guest selects one preview.
4. The phone calls `POST /preview-jobs/{id}/finalize`.
5. The backend renders the selected final version and emails it as an attachment.

## Current supported presets

The four visible presets are plain ComfyUI API workflow JSON files in this
folder. Each preset has one fast preview workflow and one higher-resolution
final workflow. These are img2img AI workflows, not deterministic image
filters.

- `preset_cinematic_glow_preview.json`
- `preset_cinematic_glow_final.json`
- `preset_neon_edge_preview.json`
- `preset_neon_edge_final.json`
- `preset_comic_pop_preview.json`
- `preset_comic_pop_final.json`
- `preset_chrome_negative_preview.json`
- `preset_chrome_negative_final.json`

Each preset workflow uses the Z-Image Turbo loader stack from the local ComfyUI
blueprints:

- `UNETLoader` loads `z_image_turbo_bf16.safetensors`.
- `CLIPLoader` loads `qwen_3_4b.safetensors` with type `lumina2`.
- `VAELoader` loads `ae.safetensors`.
- `ModelSamplingAuraFlow` adapts the model before sampling.

The workflow then encodes the video frames through the standalone VAE, runs
`KSampler` with preset-specific positive and negative prompts, decodes the
sampled latents, and saves a video.

Preview renders target `360x640` with fewer sampler steps and lower denoise.
Final renders target `720x1280` with more sampler steps and stronger denoise,
while staying small enough to attach to email.

The backend preset list in `booth_backend/server.py` only maps user-facing
names/descriptions to these workflow filenames. The workflow graph itself
lives here, not hard-coded in Python.

At runtime the backend patches:

- `LoadVideo.inputs.file` to the uploaded ComfyUI input filename.
- `SaveVideo.inputs.filename_prefix` to a unique per-job prefix.

If a preset should change style, edit the corresponding workflow JSON prompt,
sampler settings, denoise value, or model node in this folder.

## Session storage

New uploads are stored under `booth_backend/_data/<session_id>/` instead of
being dumped directly into `_data`.

For the normal preview/finalize flow, `session_id` is the `preview_job_id`.
Typical files in the session folder:

- `source.mp4`
- `preview_meta.json`
- `preview_source.mp4`
- `<preset_id>_preview.mp4`
- `<final_job_id>_raw.mp4`
- `<final_job_id>.mp4`
- `<final_job_id>_meta.json`
- `<final_job_id>_email.mp4` when compression is needed for email

## Fallback workflow file

`native_video_invert.json` is a simple native-node workflow kept on disk for
direct `/jobs` compatibility and backend override testing.

`vangogh_vid2vid.json` is historical. It requires custom nodes that may not be
installed on the active ComfyUI machine, so it is not the default operational
path right now.
