# ComfyUI workflows

The production guest flow does not use a pre-capture style picker.

Current flow:

1. The phone records and uploads the booth video to `POST /preview-jobs`.
2. The backend generates four short preview MP4s from the captured video.
3. The guest selects one preview.
4. The phone calls `POST /preview-jobs/{id}/finalize`.
5. The backend renders the selected final version and emails it as an attachment.

## Current supported presets

The four visible presets are generated dynamically in `booth_backend/server.py`
using ComfyUI native video/image nodes:

- `cinematic_glow`
- `neon_edge`
- `comic_pop`
- `chrome_negative`

Preview renders target `360x640`. Final renders target `720x1280` so the MP4
stays small enough to attach to email.

## Fallback workflow file

`native_video_invert.json` is a simple native-node workflow kept on disk for
direct `/jobs` compatibility and backend override testing.

`vangogh_vid2vid.json` is historical. It requires custom nodes that may not be
installed on the active ComfyUI machine, so it is not the default operational
path right now.
