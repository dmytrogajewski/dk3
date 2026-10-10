"""Render a long local I2V shot in resumable, overlapping Hunyuan segments.

The first frame of every later segment is the previous segment's last frame.
That repeated boundary frame is removed before the shot is concatenated.
This is offline authoring; generated clips still require visual review.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys


FPS = 24


def segment_frames(duration: float, maximum: int = 81) -> tuple[int, list[int]]:
    if not math.isfinite(duration) or not 0 < duration <= 60:
        raise ValueError("shot duration must be finite and between 0 and 60 seconds")
    if maximum < 5 or maximum > 121 or maximum % 4 != 1:
        raise ValueError("maximum frames must be 4n+1 in [5, 121]")
    target = round(duration * FPS)
    if target < 1:
        raise ValueError("shot is shorter than one video frame")
    planned: list[int] = []
    assembled = 0
    while assembled < target:
        needed = target - assembled + (1 if planned else 0)
        count = min(maximum, max(5, 4 * math.ceil((needed - 1) / 4) + 1))
        planned.append(count)
        assembled += count - (1 if len(planned) > 1 else 0)
    return target, planned


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_logged(command: list[str], log: Path) -> None:
    with log.open("w", encoding="utf-8") as stream:
        subprocess.run(command, check=True, stdout=stream, stderr=subprocess.STDOUT)


def render(args: argparse.Namespace) -> dict:
    model = args.model_dir.resolve(strict=True)
    image = args.image.resolve(strict=True)
    output = args.out_dir.resolve()
    clip = args.clip_out.resolve()
    if clip == image or clip == model or clip == output:
        raise ValueError("clip output cannot overwrite an input")
    output.mkdir(parents=True, exist_ok=True)
    clip.parent.mkdir(parents=True, exist_ok=True)
    target, counts = segment_frames(args.duration, args.max_frames)
    source = image
    generated: list[Path] = []
    for index, count in enumerate(counts):
        segment = output / f"segment-{index:02d}"
        segment.mkdir(exist_ok=True)
        video = segment / "generated.mp4"
        metadata = segment / "generation.json"
        seed = args.seed + index
        if metadata.exists():
            existing = json.loads(metadata.read_text(encoding="utf-8"))
            expected = {"source_sha256": sha256(source), "prompt": args.prompt,
                        "negative_prompt": args.negative_prompt, "seed": seed,
                        "requested_frames": count, "steps": args.steps,
                        "target_size": args.target_size}
            if any(existing.get(key) != value for key, value in expected.items()):
                raise ValueError(f"segment {index} exists with a different recipe: {segment}")
            if not video.exists():
                if not (segment / "latents.safetensors").is_file():
                    raise ValueError(f"segment {index} has metadata but no latents: {segment}")
                run_logged([
                    sys.executable, str(Path(__file__).with_name("cinematic_ai_decode.py")),
                    "--model-dir", str(model), "--latents", str(segment / "latents.safetensors"),
                    "--report-dir", str(segment),
                ], output / f"segment-{index:02d}-decode.log")
        else:
            if video.exists():
                raise ValueError(f"partial segment exists; inspect before retry: {segment}")
            run_logged([
                sys.executable, str(Path(__file__).with_name("cinematic_ai_video.py")),
                "--model-dir", str(model), "--image", str(source),
                "--report-dir", str(segment), "--prompt", args.prompt,
                "--negative-prompt", args.negative_prompt, "--seed", str(seed),
                "--frames", str(count), "--steps", str(args.steps),
                "--target-size", str(args.target_size),
            ], output / f"segment-{index:02d}-generate.log")
            run_logged([
                sys.executable, str(Path(__file__).with_name("cinematic_ai_decode.py")),
                "--model-dir", str(model), "--latents", str(segment / "latents.safetensors"),
                "--report-dir", str(segment),
            ], output / f"segment-{index:02d}-decode.log")
        generated.append(video)
        source = segment / "frames" / f"frame_{count - 1:04d}.png"
        if not source.is_file():
            raise ValueError(f"segment {index} has no final continuity frame: {source}")

    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
    for video in generated:
        command.extend(["-i", str(video)])
    filters = []
    labels = []
    for index in range(len(generated)):
        start = 1 if index else 0
        label = f"s{index}"
        filters.append(f"[{index}:v]trim=start_frame={start},setpts=PTS-STARTPTS[{label}]")
        labels.append(f"[{label}]")
    filters.append(f"{''.join(labels)}concat=n={len(labels)}:v=1:a=0,"
                   f"trim=end_frame={target},setpts=N/({FPS}*TB)[v]")
    command.extend(["-filter_complex", ";".join(filters), "-map", "[v]",
                    "-frames:v", str(target), "-an", "-c:v", "libx264", "-crf", "18",
                    "-pix_fmt", "yuv420p", str(clip)])
    run_logged(command, output / "assemble.log")
    probe = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-count_frames", "-show_entries",
        "stream=nb_read_frames,r_frame_rate", "-of", "json", str(clip),
    ]))
    actual = int(probe["streams"][0]["nb_read_frames"])
    if actual != target:
        raise ValueError(f"assembled shot has {actual} frames; expected {target}")
    report = {"source_image": str(image), "source_sha256": sha256(image),
              "clip": str(clip), "clip_sha256": sha256(clip), "duration": args.duration,
              "fps": FPS, "frames": target, "segment_frames": counts,
              "segment_videos": [str(path) for path in generated],
              "visual_review": "required; continuity and identity are unverified"}
    (output / "shot-report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--clip-out", type=Path, required=True)
    parser.add_argument("--duration", type=float, required=True)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--negative-prompt", default="")
    parser.add_argument("--seed", type=int, default=345)
    parser.add_argument("--steps", type=int, default=8)
    parser.add_argument("--target-size", type=int, default=576)
    parser.add_argument("--max-frames", type=int, default=81)
    args = parser.parse_args()
    if not args.prompt.strip() or args.steps < 1 or args.target_size % 32:
        parser.error("prompt, steps, or target size is invalid")
    print(json.dumps(render(args), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
