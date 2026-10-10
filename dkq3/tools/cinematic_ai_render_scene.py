"""Render a recorded cinematic scene from a versioned local video recipe.

The recipe holds prompts and filenames, while all private keyframes, model
weights, and generated media stay in ignored local report directories.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys


def load_recipe(recipe_path: Path, audio_plan_path: Path) -> tuple[dict, dict]:
    recipe = json.loads(recipe_path.read_text(encoding="utf-8"))
    audio = json.loads(audio_plan_path.read_text(encoding="utf-8"))
    if recipe.get("version") != 1 or recipe.get("fps") != 24:
        raise ValueError("unsupported cinematic video recipe version or frame rate")
    if recipe.get("scene") != audio.get("scene"):
        raise ValueError("video recipe and audio plan name different scenes")
    if len(recipe.get("shots", [])) != len(audio.get("shots", [])):
        raise ValueError("video recipe must contain every shot from the audio plan")
    for index, (video, source) in enumerate(zip(recipe["shots"], audio["shots"])):
        if video.get("index") != index or source.get("index") != index:
            raise ValueError(f"missing or out-of-order shot {index}")
        name = video.get("keyframe")
        if not isinstance(name, str) or Path(name).name != name or name in ("", ".", ".."):
            raise ValueError(f"shot {index} has unsafe keyframe name")
        if not isinstance(video.get("prompt"), str) or not video["prompt"].strip():
            raise ValueError(f"shot {index} has no prompt")
    return recipe, audio


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recipe", type=Path, required=True)
    parser.add_argument("--audio-plan", type=Path, required=True)
    parser.add_argument("--keyframe-dir", type=Path, required=True)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--shots", help="comma-separated shot indices; default all")
    parser.add_argument("--skip-existing", action="store_true")
    parser.add_argument("--steps", type=int, default=8)
    parser.add_argument("--target-size", type=int, default=576)
    args = parser.parse_args()
    recipe, audio = load_recipe(args.recipe, args.audio_plan)
    chosen = (set(range(len(recipe["shots"]))) if args.shots is None
              else {int(part) for part in args.shots.split(",")})
    if not chosen or any(index < 0 or index >= len(recipe["shots"]) for index in chosen):
        parser.error("--shots contains an invalid index")
    keyframes = args.keyframe_dir.resolve(strict=True)
    model = args.model_dir.resolve(strict=True)
    output = args.out_dir.resolve()
    shots_dir = output / "shots"
    shots_dir.mkdir(parents=True, exist_ok=True)
    for index in sorted(chosen):
        video = recipe["shots"][index]
        source = audio["shots"][index]
        keyframe = keyframes / video["keyframe"]
        if not keyframe.is_file() or keyframe.is_symlink():
            raise ValueError(f"shot {index} keyframe missing or symbolic link: {keyframe}")
        clip = shots_dir / f"shot-{index:02d}.mp4"
        if clip.exists():
            if not args.skip_existing:
                raise ValueError(f"shot {index} exists; use --skip-existing or choose a new output: {clip}")
            probe = json.loads(subprocess.check_output([
                "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json",
                str(clip),
            ]))
            if float(probe["format"]["duration"]) < float(source["duration"]) - 0.05:
                raise ValueError(f"shot {index} exists but is shorter than its source scene")
            print(f"shot {index:02d}: existing clip accepted", flush=True)
            continue
        command = [sys.executable, str(Path(__file__).with_name("cinematic_ai_render_shot.py")),
                   "--model-dir", str(model), "--image", str(keyframe),
                   "--out-dir", str(output / f"shot-{index:02d}-render"),
                   "--clip-out", str(clip), "--duration", str(source["duration"]),
                   "--prompt", video["prompt"],
                   "--negative-prompt", video.get("negative_prompt", recipe["negative_prompt"]),
                   "--seed", str(video["seed"]), "--steps", str(args.steps),
                   "--target-size", str(args.target_size)]
        print(f"shot {index:02d}: rendering {source['duration']:.3f}s", flush=True)
        subprocess.run(command, check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
