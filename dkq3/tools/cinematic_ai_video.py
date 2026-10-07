"""Generate a local cinematic video proof from a recorded game frame.

This is an offline authoring tool. It never modifies DK3's runtime or source
assets; output is confined to the caller's report directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


MODEL_ID = "hunyuanvideo-community/HunyuanVideo-1.5-Diffusers-480p_i2v_step_distilled"
MODEL_REVISION = "854c04a4c8a53d990b418c7478f0802c0fc8c726"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def generate(args: argparse.Namespace) -> None:
    import numpy as np
    import torch
    from PIL import Image
    from diffusers import HunyuanVideo15ImageToVideoPipeline

    model_dir = args.model_dir.resolve(strict=True)
    image_path = args.image.resolve(strict=True)
    report_dir = args.report_dir.resolve()
    report_dir.mkdir(parents=True, exist_ok=True)
    frames_dir = report_dir / "frames"
    frames_dir.mkdir(exist_ok=True)

    image = Image.open(image_path).convert("RGB")
    pipe = HunyuanVideo15ImageToVideoPipeline.from_pretrained(
        str(model_dir), torch_dtype=torch.bfloat16, local_files_only=True
    )
    pipe.target_size = args.target_size
    # Variable-length padded attention is a major source of wasted VRAM here.
    # The optimized backend is documented for HunyuanVideo 1.5 by Diffusers.
    pipe.transformer.set_attention_backend("flash_hub")
    pipe.enable_model_cpu_offload()
    pipe.vae.enable_tiling()
    generator = torch.Generator(device="cuda").manual_seed(args.seed)
    with torch.inference_mode():
        frames = pipe(
            image=image,
            prompt=args.prompt,
            negative_prompt=args.negative_prompt,
            generator=generator,
            num_frames=args.frames,
            num_inference_steps=args.steps,
        ).frames[0]

    for index, frame in enumerate(frames):
        pixels = np.asarray(frame)
        if pixels.dtype != np.uint8:
            pixels = np.clip(pixels * 255.0, 0, 255).astype(np.uint8)
        Image.fromarray(pixels).save(frames_dir / f"frame_{index:04d}.png")

    video_path = report_dir / "generated.mp4"
    subprocess.run(
        [
            "ffmpeg", "-y", "-v", "error", "-framerate", "24",
            "-i", str(frames_dir / "frame_%04d.png"),
            "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p",
            str(video_path),
        ],
        check=True,
    )
    report = {
        "model": MODEL_ID,
        "model_revision": MODEL_REVISION,
        "source_image": str(image_path),
        "source_sha256": sha256(image_path),
        "prompt": args.prompt,
        "negative_prompt": args.negative_prompt,
        "seed": args.seed,
        "steps": args.steps,
        "frames": len(frames),
        "target_size": args.target_size,
        "fps": 24,
        "torch": torch.__version__,
        "cuda": torch.version.cuda,
        "gpu": torch.cuda.get_device_name(0),
        "video": str(video_path),
        "video_sha256": sha256(video_path),
        "status": "generated; visual review required",
    }
    (report_dir / "generation.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, indent=2, sort_keys=True))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--negative-prompt", default="")
    parser.add_argument("--seed", type=int, default=345)
    parser.add_argument("--frames", type=int, default=49)
    parser.add_argument("--steps", type=int, default=12)
    parser.add_argument("--target-size", type=int, default=384)
    args = parser.parse_args()
    if args.frames < 5 or args.frames > 121 or args.frames % 4 != 1:
        parser.error("--frames must be 4n+1, from 5 through 121")
    if args.steps < 1 or args.steps > 50:
        parser.error("--steps must be from 1 through 50")
    if args.target_size < 256 or args.target_size > 480 or args.target_size % 32:
        parser.error("--target-size must be a multiple of 32 from 256 through 480")
    if not args.prompt.strip():
        parser.error("--prompt must not be blank")
    generate(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
