"""Generate local cinematic video latents from a photorealistic keyframe.

This is an offline authoring tool. It never modifies DK3's runtime or source
assets; output is confined to the caller's report directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
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
    import torch
    from PIL import Image
    from diffusers import BitsAndBytesConfig, HunyuanVideo15ImageToVideoPipeline
    from diffusers.quantizers import PipelineQuantizationConfig
    from safetensors.torch import save_file

    model_dir = args.model_dir.resolve(strict=True)
    image_path = args.image.resolve(strict=True)
    report_dir = args.report_dir.resolve()
    report_dir.mkdir(parents=True, exist_ok=True)

    image = Image.open(image_path).convert("RGB")
    quantization = PipelineQuantizationConfig(
        quant_mapping={"transformer": BitsAndBytesConfig(load_in_8bit=True)}
    )
    pipe = HunyuanVideo15ImageToVideoPipeline.from_pretrained(
        str(model_dir),
        torch_dtype=torch.bfloat16,
        quantization_config=quantization,
        local_files_only=True,
    )
    pipe.target_size = args.target_size
    pipe.vae.enable_tiling()
    # The quantized transformer starts on CUDA. Encoding text on CUDA at the
    # same time would load the 7B language encoder beside it and exhaust VRAM.
    # Produce both CFG embeddings on CPU, then move only the image/VAE modules.
    with torch.inference_mode():
        positive = pipe.encode_prompt(args.prompt, device=torch.device("cpu"))
        negative = pipe.encode_prompt(args.negative_prompt, device=torch.device("cpu"))
    pipe.image_encoder.to("cuda")
    pipe.vae.to("cuda")
    generator = torch.Generator(device="cuda").manual_seed(args.seed)
    with torch.inference_mode():
        latents = pipe(
            image=image,
            prompt_embeds=positive[0],
            prompt_embeds_mask=positive[1],
            prompt_embeds_2=positive[2],
            prompt_embeds_mask_2=positive[3],
            negative_prompt_embeds=negative[0],
            negative_prompt_embeds_mask=negative[1],
            negative_prompt_embeds_2=negative[2],
            negative_prompt_embeds_mask_2=negative[3],
            generator=generator,
            num_frames=args.frames,
            num_inference_steps=args.steps,
            output_type="latent",
        ).frames

    latent_path = report_dir / "latents.safetensors"
    save_file({"latents": latents.detach().cpu().contiguous()}, latent_path)
    report = {
        "model": MODEL_ID,
        "model_revision": MODEL_REVISION,
        "source_image": str(image_path),
        "source_sha256": sha256(image_path),
        "prompt": args.prompt,
        "negative_prompt": args.negative_prompt,
        "seed": args.seed,
        "steps": args.steps,
        "requested_frames": args.frames,
        "latent_shape": list(latents.shape),
        "latents": str(latent_path),
        "latents_sha256": sha256(latent_path),
        "target_size": args.target_size,
        "fps": 24,
        "torch": torch.__version__,
        "transformer_quantization": "bitsandbytes_int8",
        "cuda": torch.version.cuda,
        "gpu": torch.cuda.get_device_name(0),
        "status": "latents ready; run cinematic_ai_decode.py in a fresh process",
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
    parser.add_argument("--target-size", type=int, default=640)
    args = parser.parse_args()
    if args.frames < 5 or args.frames > 121 or args.frames % 4 != 1:
        parser.error("--frames must be 4n+1, from 5 through 121")
    if args.steps < 1 or args.steps > 50:
        parser.error("--steps must be from 1 through 50")
    if args.target_size < 256 or args.target_size > 640 or args.target_size % 32:
        parser.error("--target-size must be a multiple of 32 from 256 through 640")
    if not args.prompt.strip():
        parser.error("--prompt must not be blank")
    generate(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
