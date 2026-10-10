"""Assemble reviewed AI shots with the untouched original cinematic soundtrack."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys


def probe(path: Path) -> dict:
    raw = subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type,width,height",
        "-of", "json", str(path),
    ])
    return json.loads(raw)


def assemble(plan: dict, recording: Path, shots_dir: Path, output: Path,
             report_path: Path) -> dict:
    if not isinstance(plan.get("shots"), list) or not plan["shots"]:
        raise ValueError("audio plan has no shots")
    source = probe(recording)
    if not any(s["codec_type"] == "audio" for s in source["streams"]):
        raise ValueError("original recording has no audio")
    fps = 30
    opening_frames = round(float(plan["scene_start"]) * fps)
    recording_frames = round(float(source["format"]["duration"]) * fps)
    shot_files = []
    shot_frames = []
    for index, shot in enumerate(plan["shots"]):
        path = shots_dir / f"shot-{index:02d}.mp4"
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"missing generated shot {index}: {path}")
        metadata = probe(path)
        if not any(s["codec_type"] == "video" for s in metadata["streams"]):
            raise ValueError(f"shot {index} has no video")
        count = round(float(shot["duration"]) * fps)
        if float(metadata["format"]["duration"]) < count / fps - 0.05:
            raise ValueError(f"shot {index} is shorter than its source duration")
        shot_files.append(path)
        shot_frames.append(count)
    ending_frames = recording_frames - opening_frames - sum(shot_frames)
    if not 0 <= ending_frames <= fps:
        raise ValueError("shot lengths do not agree with the original recording")
    if output.resolve() == recording.resolve() or output.resolve() in {p.resolve() for p in shot_files}:
        raise ValueError("output cannot overwrite an input")

    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(recording)]
    for path in shot_files:
        command.extend(["-i", str(path)])
    filters = []
    pieces = []
    if opening_frames:
        filters.append(f"[0:v]fps={fps},trim=end_frame={opening_frames},setpts=N/({fps}*TB)[pre]")
        pieces.append("[pre]")
    for index, count in enumerate(shot_frames):
        name = f"s{index}"
        filters.append(f"[{index+1}:v]crop=iw:trunc(iw*9/16/2)*2:0:(ih-oh)/2,"
                       f"scale=960:540,fps={fps},tpad=stop_mode=clone:stop_duration=0.05,"
                       f"trim=end_frame={count},setpts=N/({fps}*TB)[{name}]")
        pieces.append(f"[{name}]")
    if ending_frames:
        start = recording_frames - ending_frames
        filters.append(f"[0:v]fps={fps},trim=start_frame={start}:end_frame={recording_frames},"
                       f"setpts=N/({fps}*TB)[post]")
        pieces.append("[post]")
    filters.append(f"{''.join(pieces)}concat=n={len(pieces)}:v=1:a=0[v]")
    output.parent.mkdir(parents=True, exist_ok=True)
    command.extend(["-filter_complex", ";".join(filters), "-map", "[v]", "-map", "0:a:0",
                    "-c:v", "libx264", "-preset", "medium", "-crf", "17",
                    "-pix_fmt", "yuv420p", "-c:a", "copy", "-movflags", "+faststart", str(output)])
    subprocess.run(command, check=True)
    final = probe(output)
    report = {"source_recording": str(recording.resolve()), "output": str(output.resolve()),
              "shot_files": [str(p.resolve()) for p in shot_files],
              "opening_frames": opening_frames, "shot_frames": shot_frames,
              "ending_frames": ending_frames, "expected_frames": recording_frames,
              "duration": float(final["format"]["duration"]),
              "audio": "bitstream copied from original recording", "visual_review": "required"}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--recording", type=Path, required=True)
    parser.add_argument("--shots-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = assemble(json.loads(args.plan.read_text(encoding="utf-8")), args.recording,
                      args.shots_dir, args.out, args.report)
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
