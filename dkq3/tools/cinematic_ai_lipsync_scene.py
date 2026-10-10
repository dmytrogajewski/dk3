"""Apply isolated original dialogue to visible mouths in generated scene shots."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys

from cinematic_ai_render_scene import load_recipe


def active_speakers(plan: dict, shot: dict) -> set[str]:
    start = float(shot["start"])
    end = float(shot["end"])
    return {event["speaker"] for event in plan["voice_events"]
            if min(end, float(event["video_time"]) + float(event["duration"]))
            - max(start, float(event["video_time"])) > 0.1}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recipe", type=Path, required=True)
    parser.add_argument("--audio-plan", type=Path, required=True)
    parser.add_argument("--audio-dir", type=Path, required=True)
    parser.add_argument("--shots-dir", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--musetalk-source", type=Path, required=True)
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--detector", type=Path, required=True)
    parser.add_argument("--shots", help="comma-separated shot indices; default all")
    parser.add_argument("--skip-existing", action="store_true")
    args = parser.parse_args()
    recipe, plan = load_recipe(args.recipe, args.audio_plan)
    chosen = (set(range(len(recipe["shots"]))) if args.shots is None
              else {int(part) for part in args.shots.split(",")})
    if not chosen or any(index < 0 or index >= len(recipe["shots"]) for index in chosen):
        parser.error("--shots contains an invalid index")
    output = args.out_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for index in sorted(chosen):
        shot = plan["shots"][index]
        visual = recipe["shots"][index]
        source = args.shots_dir.resolve(strict=True) / f"shot-{index:02d}.mp4"
        if not source.is_file():
            raise ValueError(f"missing generated video for shot {index}: {source}")
        final = output / f"shot-{index:02d}.mp4"
        if final.exists():
            if args.skip_existing:
                print(f"shot {index:02d}: existing lip-sync clip accepted", flush=True)
                continue
            raise ValueError(f"lip-sync shot already exists: {final}")
        mouth_map = visual.get("mouths", {})
        if not isinstance(mouth_map, dict):
            raise ValueError(f"shot {index} mouths must be an object")
        speakers = active_speakers(plan, shot)
        sequence = [speaker for speaker in mouth_map if speaker in speakers]
        current = source
        operations = []
        for speaker in sequence:
            hint = mouth_map[speaker]
            if (not isinstance(hint, list) or len(hint) != 2 or
                    any(not isinstance(value, (int, float)) or not math.isfinite(value)
                        or not 0 <= value <= 1 for value in hint)):
                raise ValueError(f"shot {index} has invalid face hint for {speaker}")
            track = args.audio_dir.resolve(strict=True) / f"{speaker}-voice.wav"
            if not track.is_file():
                raise ValueError(f"missing isolated voice track: {track}")
            voice = output / f"shot-{index:02d}-{speaker}-voice.wav"
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                            "-ss", str(shot["start"]), "-t", str(shot["duration"]),
                            "-i", str(track), "-ac", "1", "-ar", "16000", "-c:a",
                            "pcm_s16le", str(voice)], check=True)
            stage = output / f"shot-{index:02d}-{speaker}.mp4"
            report = output / f"shot-{index:02d}-{speaker}.json"
            log = output / f"shot-{index:02d}-{speaker}.log"
            command = [sys.executable,
                       str(Path(__file__).with_name("cinematic_ai_lipsync.py")),
                       "--source", str(args.musetalk_source.resolve(strict=True)),
                       "--models", str(args.models.resolve(strict=True)),
                       "--detector", str(args.detector.resolve(strict=True)),
                       "--video", str(current), "--voice", str(voice),
                       "--out", str(stage), "--report", str(report),
                       "--face-hint", str(hint[0]), str(hint[1])]
            with log.open("w", encoding="utf-8") as stream:
                subprocess.run(command, check=True, stdout=stream, stderr=subprocess.STDOUT)
            operations.append({"speaker": speaker, "face_hint": hint, "report": str(report),
                               "voice": str(voice)})
            current = stage
        if current == source:
            shutil.copyfile(source, final)
        else:
            shutil.copyfile(current, final)
        (output / f"shot-{index:02d}-report.json").write_text(json.dumps({
            "shot": index, "source": str(source), "output": str(final),
            "active_speakers": sorted(speakers), "visible_speakers": sequence,
            "operations": operations,
            "unresolved_visible_speakers": sorted(speakers - set(sequence)),
            "visual_review": "required",
        }, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"shot {index:02d}: lip-sync passes {sequence}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
