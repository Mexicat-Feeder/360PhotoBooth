"""Style presets — each is just a prompt (+ denoise) the same pipeline renders."""

NEGATIVE = ("lowres, bad anatomy, blurry, deformed, disfigured, extra limbs, "
            "text, watermark, jpeg artifacts, photograph, realistic")

# id, label, positive prompt, denoise (higher = more transformation)
STYLES = [
    {"id": "van_gogh", "label": "Van Gogh",
     "prompt": "in the style of Vincent van Gogh, Starry Night, swirling thick "
               "impasto oil brushstrokes, post-impressionism, vibrant blues and yellows",
     "denoise": 0.62},
    {"id": "anime", "label": "Anime",
     "prompt": "anime style, cel shaded, studio anime key visual, clean line art, "
               "vibrant colors, detailed anime illustration",
     "denoise": 0.62},
    {"id": "comic", "label": "Comic / Pop-Art",
     "prompt": "comic book pop art style, bold black ink outlines, halftone ben-day "
               "dots, vivid flat colors, Roy Lichtenstein",
     "denoise": 0.6},
    {"id": "cyberpunk", "label": "Cyberpunk",
     "prompt": "cyberpunk neon style, blade runner, glowing neon lights, futuristic "
               "city, rim lighting, vibrant magenta and cyan, cinematic",
     "denoise": 0.62},
    {"id": "watercolor", "label": "Watercolor",
     "prompt": "watercolor painting, soft washes, wet-on-wet, delicate pigment bleed, "
               "textured paper, hand painted",
     "denoise": 0.6},
    {"id": "pixar", "label": "3D Cartoon",
     "prompt": "3D animated movie character, Pixar style, soft global illumination, "
               "subsurface scattering, cute stylized 3d render, big expressive eyes",
     "denoise": 0.6},
    {"id": "sketch", "label": "Pencil Sketch",
     "prompt": "detailed pencil sketch, graphite drawing, cross-hatching, charcoal, "
               "monochrome hand-drawn portrait",
     "denoise": 0.6},
    {"id": "statue", "label": "Marble Statue",
     "prompt": "white marble statue, classical greek sculpture, carved polished marble, "
               "smooth stone, museum lighting",
     "denoise": 0.68},
    {"id": "jedi", "label": "Space Knight",
     "prompt": "a heroic space knight in brown hooded robes holding a glowing energy "
               "sword, epic sci-fi fantasy, cinematic dramatic lighting, detailed",
     "denoise": 0.78},
]

BY_ID = {s["id"]: s for s in STYLES}
