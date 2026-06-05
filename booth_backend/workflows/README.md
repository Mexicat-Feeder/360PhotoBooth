# ComfyUI workflows

`vangogh_vid2vid.json` — the **API-format** export of the Van Gogh AnimateLCM
vid2vid workflow. Created by building the graph in the ComfyUI UI on a sample
clip, then "Save (API Format)". The backend (`server.py`) loads it and patches:
- the `VHS_LoadVideo` node's `video` input  -> the uploaded guest clip
- the `VHS_VideoCombine` node's `filename_prefix` -> `booth_<jobid>`

Style/prompt/LoRA/steps/denoise live in the template itself.
