"""Extract timed dialogue tracks for offline cinematic lip-sync authoring.

The finished film should keep the original recording's mixed audio. These
speaker-isolated WAVs are conditioning inputs only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import zipfile

import numpy as np
from scipy.signal import fftconvolve
import yaml


def sha256(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def duration(path: Path) -> float:
    data = subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "json", str(path),
    ])
    return float(json.loads(data)["format"]["duration"])


def samples(path: Path, rate: int = 8000) -> np.ndarray:
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(rate),
        "-f", "f32le", "pipe:1",
    ])
    return np.frombuffer(raw, dtype="<f4")


def align_voice(recording: np.ndarray, voice: np.ndarray, expected: float,
                rate: int = 8000, radius: float = 0.25) -> tuple[float, float]:
    """Locate an original voice asset inside the engine's recorded audio."""
    low = max(0, round((expected - radius) * rate))
    high = min(len(recording), round((expected + radius) * rate) + len(voice))
    window = recording[low:high]
    if len(window) < len(voice) or not np.any(voice):
        raise ValueError("recording cannot contain this voice near its authored time")
    correlation = fftconvolve(window, voice[::-1], mode="valid")
    index = int(np.argmax(np.abs(correlation)))
    match = window[index:index + len(voice)]
    denominator = float(np.linalg.norm(match) * np.linalg.norm(voice))
    confidence = abs(float(correlation[index])) / denominator if denominator else 0.0
    if confidence < 0.15:
        raise ValueError(f"voice alignment confidence {confidence:.3f} is below 0.15")
    return (low + index) / rate, confidence


def speaker(sound: str) -> str:
    parts = PurePosixPath(sound).parts
    if len(parts) < 3 or parts[0] != "voices" or any(p in ("", ".", "..") for p in parts):
        raise ValueError(f"invalid voice asset path: {sound}")
    return parts[1]


def mix(events: list[dict], length: float, output: Path) -> None:
    commands = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
    for event in events:
        commands.extend(["-i", event["local_path"]])
    filters = []
    for index, event in enumerate(events):
        milliseconds = round(event["video_time"] * 1000)
        filters.append(f"[{index}:a]adelay={milliseconds}:all=1[a{index}]")
    inputs = "".join(f"[a{i}]" for i in range(len(events)))
    filters.append(f"{inputs}amix=inputs={len(events)}:duration=longest:normalize=0,"
                   f"apad,atrim=0:{length:.6f}[out]")
    commands.extend(["-filter_complex", ";".join(filters), "-map", "[out]",
                     "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(output)])
    subprocess.run(commands, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene", type=Path, required=True)
    parser.add_argument("--voice-package", type=Path, required=True)
    parser.add_argument("--recording", type=Path, required=True)
    parser.add_argument("--scene-start", type=float, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if not 0 <= args.scene_start < 10:
        parser.error("--scene-start must be between 0 and 10 seconds")
    scene = yaml.safe_load(args.scene.read_text(encoding="utf-8"))
    if not isinstance(scene, dict) or not isinstance(scene.get("shots"), list):
        parser.error("scene must contain a shots list")
    output = args.out.resolve()
    if output == args.scene.resolve() or output == args.voice_package.resolve():
        parser.error("output cannot be an input file")
    output.mkdir(parents=True, exist_ok=True)
    voices = output / "voices"
    voices.mkdir(exist_ok=True)
    events = []
    shot_rows = []
    elapsed = args.scene_start
    with zipfile.ZipFile(args.voice_package) as package:
        members = set(package.namelist())
        for index, shot in enumerate(scene["shots"]):
            span = float(shot["duration"])
            if not 0 < span <= 120:
                parser.error(f"shot {index} has invalid duration")
            shot_rows.append({"index": index, "start": round(elapsed, 6),
                              "end": round(elapsed + span, 6), "duration": span})
            for event in shot.get("events", []):
                sound = event.get("sound", "")
                if not sound.startswith("voices/"):
                    continue
                who = speaker(sound)
                relative = float(event["at"])
                if not 0 <= relative <= span:
                    parser.error(f"shot {index}: voice event time outside shot")
                member = "sounds/" + sound + ".ogg"
                if member not in members:
                    parser.error(f"missing voice asset: {member}")
                local = voices / (PurePosixPath(sound).name + ".ogg")
                source_bytes = package.read(member)
                if not local.exists() or local.read_bytes() != source_bytes:
                    local.write_bytes(source_bytes)
                events.append({"shot": index, "speaker": who, "asset": sound,
                               "local_path": str(local), "video_time": round(elapsed + relative, 6),
                               "duration": round(duration(local), 6)})
            elapsed += span
    recording_length = duration(args.recording)
    recorded_samples = samples(args.recording)
    for event in events:
        authored_time = event["video_time"]
        matched_time, confidence = align_voice(
            recorded_samples, samples(Path(event["local_path"])), authored_time)
        event["authored_video_time"] = authored_time
        event["video_time"] = round(matched_time, 6)
        event["alignment_offset"] = round(matched_time - authored_time, 6)
        event["alignment_confidence"] = round(confidence, 6)
    for who in sorted({e["speaker"] for e in events}):
        isolated = [e for e in events if e["speaker"] == who]
        mix(isolated, recording_length, output / f"{who}-voice.wav")
    report = {"scene": scene.get("scene"), "scene_source": str(args.scene.resolve()),
              "scene_sha256": sha256(args.scene), "voice_package_sha256": sha256(args.voice_package),
              "recording_sha256": sha256(args.recording), "recording_duration": recording_length,
              "scene_start": args.scene_start, "shots": shot_rows, "voice_events": events,
              "purpose": "speaker-isolated lip-sync conditions; preserve original mixed audio in final video"}
    (output / "audio-plan.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                                              encoding="utf-8")
    print(json.dumps({"shots": len(shot_rows), "voice_events": len(events),
                      "speakers": sorted({e["speaker"] for e in events}),
                      "output": str(output / "audio-plan.json")}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
