"""Decode HunyuanVideo 1.5 latents in a fresh, VAE-only process."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", required=True, type=Path)
    parser.add_argument("--latents", required=True, type=Path)
    parser.add_argument("--report-dir", required=True, type=Path)
    args = parser.parse_args()

    import numpy as np
    import torch
    from PIL import Image
    from diffusers import AutoencoderKLHunyuanVideo15
    from safetensors.torch import load_file

    report_dir = args.report_dir.resolve()
    report_dir.mkdir(parents=True, exist_ok=True)
    frames_dir = report_dir / "frames"
    frames_dir.mkdir(exist_ok=True)

    vae = AutoencoderKLHunyuanVideo15.from_pretrained(
        str(args.model_dir.resolve(strict=True) / "vae"),
        torch_dtype=torch.bfloat16,
        local_files_only=True,
    ).to("cuda")
    # Keep the model's matching sample/latent tile sizes. Smaller spatial
    # tiles changed its output dimensions and duplicated image features.
    vae.enable_tiling()
    latents = load_file(str(args.latents.resolve(strict=True)), device="cpu")["latents"]
    frame_count = 4 * (latents.shape[2] - 1) + 1
    written = -1
    with torch.inference_mode():
        for start in range(0, latents.shape[2], 2):
            end = min(start + 6, latents.shape[2])
            if end <= start + 1 and start != 0:
                break
            decoded = vae.decode(
                latents[:, :, start:end].to(device="cuda", dtype=vae.dtype) / vae.config.scaling_factor,
                return_dict=False,
            )[0]
            decoded = ((decoded / 2 + 0.5).clamp(0, 1) * 255).to(torch.uint8).cpu().numpy()
            for local in range(decoded.shape[2]):
                index = start * 4 + local
                if index <= written or index >= frame_count:
                    continue
                pixels = np.transpose(decoded[0, :, local], (1, 2, 0))
                Image.fromarray(pixels).save(frames_dir / f"frame_{index:04d}.png")
                written = index
            del decoded
            torch.cuda.empty_cache()
            if written == frame_count - 1:
                break
    if written != frame_count - 1:
        raise RuntimeError(f"temporal decode stopped at frame {written} of {frame_count}")

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
    report_path = report_dir / "generation.json"
    report = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else {}
    report.update({
        "frames": frame_count,
        "fps": 24,
        "video": str(video_path),
        "video_sha256": sha256(video_path),
        "status": "generated; visual review required",
    })
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
