# Local photoreal cinematic video trial (sequence 345)

This is a **two-second authoring trial**, not an installed cinematic replacement.
The original 66-second `dojo_dialogue` recording supplies timing, blocking, set
layout, and audio. The photoreal Hiro face in
`zig-out/neural-monsters/head-neutral/hiro/concept.png` and the white gi in
`zig-out/cinematic-model-341/regenerated-solid/hiro-dojo/concept.png` define the
new character. A scene keyframe made from those references is at
`zig-out/reports/cinematic-video-ai-345/hiro-photoreal-keyframe.png`.

The trial uses [HunyuanVideo 1.5](https://github.com/Tencent-Hunyuan/HunyuanVideo-1.5)
through its Diffusers 480p image-to-video conversion. Model revision
`854c04a4c8a53d990b418c7478f0802c0fc8c726` is pinned. Its weights and
license stay local. The local CUDA environment used Torch 2.9.0, Diffusers
0.39.0, Transformers 4.57.1, bitsandbytes 0.50.2, and safetensors 0.6.2.
The RTX 5090 Laptop GPU has 24,463 MiB physical VRAM. The video transformer
is loaded in 8-bit; both text conditions are encoded on CPU before denoising.
Generation and VAE decoding run in **separate processes**. The decoder keeps
the model's default spatial tile dimensions and uses overlapping temporal
windows so 49 frames fit in memory without changing image geometry.

To reproduce from this checkout, create an isolated environment and install
the pinned Python packages, then download the pinned model snapshot:

```sh
python3 -m venv --system-site-packages zig-out/video-ai-venv
zig-out/video-ai-venv/bin/python -m pip install \
  'diffusers==0.39.0' 'transformers==4.57.1' \
  'bitsandbytes==0.50.2' 'safetensors==0.6.2' 'kernels==0.9.0'

zig-out/video-ai-venv/bin/python - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download(
    'hunyuanvideo-community/HunyuanVideo-1.5-Diffusers-480p_i2v_step_distilled',
    revision='854c04a4c8a53d990b418c7478f0802c0fc8c726',
    local_dir='zig-out/models/hunyuanvideo15-480p-i2v-step',
)
PY

PYTORCH_ALLOC_CONF=expandable_segments:True zig-out/video-ai-venv/bin/python \
  dkq3/tools/cinematic_ai_video.py \
  --model-dir zig-out/models/hunyuanvideo15-480p-i2v-step \
  --image zig-out/reports/cinematic-video-ai-345/hiro-photoreal-keyframe.png \
  --report-dir zig-out/reports/cinematic-video-ai-345/hiro-photoreal-shot-01 \
  --target-size 640 --frames 49 --steps 8 --seed 345 \
  --prompt 'The same Hiro faces the hooded adversary in the dojo. He breathes and moves into a natural two-handed sword guard. Keep his exact face, white gi, sword, set and camera framing.' \
  --negative-prompt 'different face, costume change, malformed hands, extra fingers, bent sword, camera cut'

PYTORCH_ALLOC_CONF=expandable_segments:True zig-out/video-ai-venv/bin/python \
  dkq3/tools/cinematic_ai_decode.py \
  --model-dir zig-out/models/hunyuanvideo15-480p-i2v-step \
  --latents zig-out/reports/cinematic-video-ai-345/hiro-photoreal-shot-01/latents.safetensors \
  --report-dir zig-out/reports/cinematic-video-ai-345/hiro-photoreal-shot-01
```

The exact prompt used for this trial, source hash, seed, model revision, output
hash, and tool versions are in `hiro-photoreal-shot-01/generation.json`. The
review outputs are `generated.mp4`, `generated-with-original-audio.mp4`,
`original-vs-ai.mp4`, and `hiro-photoreal-contact-correct.jpg` in the report
tree. The original comparison video plays 38.0–40.04 seconds of the recorded
cinematic beside the generated clip. Generated images, model weights, latents,
videos, and source captures remain local under `zig-out`.

The first decode used a smaller spatial VAE tile; it produced repeated image
features and a wrong output size. The corrected 848×480/49-frame result uses
default spatial tiles. It is visually closer to the concepts and shows natural
guard motion, but one short shot cannot establish facial identity continuity,
dialogue lip sync, continuity across cuts, or suitability for the full scene.
Neither the native cinematic runtime nor its original-asset fallback changed.

The same method was tested for Toshiro. His keyframe is at
`zig-out/reports/cinematic-video-ai-345/toshiro-photoreal-keyframe.png` and
`toshiro-keyframe-provenance.json` records the face and full-body concept
references. The original 42-second frame supplied only camera blocking and
the staff/katana positions. The exact generation prompt and settings are
recorded in `toshiro-photoreal-shot-01/generation.json`. The resulting
`generated.mp4` is also 848×480, 49 frames, 24 fps. Review copies are
`generated-with-original-audio.mp4` and `original-vs-ai.mp4` in that directory.
The sampled frames retain a coherent staff and hand grip, but Toshiro's face
looks younger and drifts away from the approved close-up by the middle of the
shot. This fails identity continuity and needs a stronger character-reference
method before producing the complete cinematic.
