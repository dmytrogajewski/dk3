"""Apply local MuseTalk 1.5 to one generated cinematic shot.

This narrow adapter uses YuNet face tracking instead of MuseTalk's MMPose
preprocessor. The input video and voice are read only. Original scene audio
must be muxed back separately after all shots are assembled.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys

import cv2
import numpy as np
import torch


def detect_face(detector: cv2.FaceDetectorYN, image: np.ndarray,
                previous: tuple[float, float] | None) -> np.ndarray | None:
    height, width = image.shape[:2]
    detector.setInputSize((width, height))
    _, candidates = detector.detect(image)
    if candidates is None or not len(candidates):
        return None
    if previous is None:
        return max(candidates, key=lambda row: float(row[2] * row[3] * row[14]))
    return min(candidates, key=lambda row: (float(row[0] + row[2] / 2) - previous[0]) ** 2
               + (float(row[1] + row[3] / 2) - previous[1]) ** 2)


def crop_box(face: np.ndarray, width: int, height: int) -> tuple[int, int, int, int]:
    x, y, w, h = (float(value) for value in face[:4])
    x0 = max(0, round(x - 0.08 * w))
    y0 = max(0, round(y - 0.05 * h))
    x1 = min(width, round(x + 1.08 * w))
    y1 = min(height, round(y + 1.12 * h))
    if x1 - x0 < 32 or y1 - y0 < 32:
        raise ValueError("detected face crop is too small")
    return x0, y0, x1, y1


def blend_mouth(frame: np.ndarray, generated: np.ndarray, box: tuple[int, int, int, int],
                face: np.ndarray) -> np.ndarray:
    x0, y0, x1, y1 = box
    region = cv2.resize(generated, (x1 - x0, y1 - y0), interpolation=cv2.INTER_LANCZOS4)
    # YuNet's five landmark pairs occupy indexes 4..13; 10..13 are mouth corners.
    mouth_x = float(face[10] + face[12]) / 2 - x0
    mouth_y = float(face[11] + face[13]) / 2 - y0
    crop_h, crop_w = region.shape[:2]
    yy, xx = np.mgrid[:crop_h, :crop_w]
    rx = max(10.0, crop_w * 0.24)
    ry = max(10.0, crop_h * 0.16)
    center_y = mouth_y + crop_h * 0.03
    distance = ((xx - mouth_x) / rx) ** 2 + ((yy - center_y) / ry) ** 2
    alpha = np.clip((1.0 - distance) / 0.4, 0.0, 1.0)[..., None].astype(np.float32)
    result = frame.copy()
    original = frame[y0:y1, x0:x1].astype(np.float32)
    result[y0:y1, x0:x1] = np.clip(original * (1 - alpha) + region * alpha, 0, 255).astype(np.uint8)
    return result


def read_video(path: Path) -> tuple[list[np.ndarray], float]:
    capture = cv2.VideoCapture(str(path))
    if not capture.isOpened():
        raise ValueError(f"cannot open video: {path}")
    fps = capture.get(cv2.CAP_PROP_FPS)
    if not 1 <= fps <= 120:
        raise ValueError(f"invalid source frame rate: {fps}")
    frames = []
    while len(frames) <= 2400:
        ok, frame = capture.read()
        if not ok:
            break
        frames.append(frame)
    capture.release()
    if not frames or len(frames) > 2400:
        raise ValueError("video must contain 1 through 2400 frames")
    return frames, fps


def write_video(path: Path, frames: list[np.ndarray], fps: float) -> None:
    height, width = frames[0].shape[:2]
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo",
               "-pixel_format", "bgr24", "-video_size", f"{width}x{height}",
               "-framerate", f"{fps:.8f}", "-i", "pipe:0", "-an", "-c:v", "libx264",
               "-crf", "18", "-pix_fmt", "yuv420p", str(path)]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    assert process.stdin is not None
    try:
        for frame in frames:
            process.stdin.write(frame.tobytes())
    finally:
        process.stdin.close()
    if process.wait() != 0:
        raise RuntimeError("ffmpeg failed to encode lip-sync video")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="MuseTalk source checkout")
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--detector", type=Path, required=True)
    parser.add_argument("--video", type=Path, required=True)
    parser.add_argument("--voice", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--face-hint", type=float, nargs=2, metavar=("X", "Y"),
                        help="normalized center of the speaking face in the first frame")
    args = parser.parse_args()
    if not 1 <= args.batch_size <= 16:
        parser.error("batch size must be 1 through 16")
    if args.face_hint and any(not 0 <= value <= 1 for value in args.face_hint):
        parser.error("face hint coordinates must be in [0, 1]")
    if args.out.resolve() in (args.video.resolve(), args.voice.resolve()):
        parser.error("output cannot overwrite source")
    for path in (args.source, args.models, args.detector, args.video, args.voice):
        if not path.exists():
            parser.error(f"missing input: {path}")
    source = args.source.resolve()
    sys.path.insert(0, str(source))
    from musetalk.models.vae import VAE
    from musetalk.models.unet import UNet, PositionalEncoding
    from musetalk.utils.audio_processor import AudioProcessor
    from transformers import WhisperModel

    frames, fps = read_video(args.video)
    detector = cv2.FaceDetectorYN.create(str(args.detector), "", (320, 320), score_threshold=0.6)
    faces = []
    boxes = []
    previous = ((args.face_hint[0] * frames[0].shape[1],
                 args.face_hint[1] * frames[0].shape[0]) if args.face_hint else None)
    misses = 0
    for frame in frames:
        face = detect_face(detector, frame, previous)
        if face is None:
            misses += 1
            faces.append(None)
            boxes.append(None)
            continue
        previous = (float(face[0] + face[2] / 2), float(face[1] + face[3] / 2))
        faces.append(face)
        boxes.append(crop_box(face, frame.shape[1], frame.shape[0]))
    if misses > max(2, len(frames) // 10):
        raise ValueError(f"face detection failed on {misses}/{len(frames)} frames")

    torch.manual_seed(0)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    vae = VAE(model_path=str(args.models / "sd-vae"), use_float16=device.type == "cuda")
    unet = UNet(str(args.models / "musetalkV15" / "musetalk.json"),
                str(args.models / "musetalkV15" / "unet.pth"),
                use_float16=device.type == "cuda", device=device)
    pe = PositionalEncoding(d_model=384).to(device=device, dtype=unet.model.dtype)
    whisper = WhisperModel.from_pretrained(str(args.models / "whisper"))
    whisper = whisper.to(device=device, dtype=unet.model.dtype).eval()
    whisper.requires_grad_(False)
    processor = AudioProcessor(feature_extractor_path=str(args.models / "whisper"))
    audio_features, sample_count = processor.get_audio_feature(str(args.voice))
    chunks = processor.get_whisper_chunk(audio_features, device, unet.model.dtype,
                                         whisper, sample_count, fps=fps)
    if abs(len(chunks) - len(frames)) > 2:
        raise ValueError(f"voice/video duration mismatch: {len(chunks)} versus {len(frames)} frames")

    output = [frame.copy() for frame in frames]
    valid = [(i, box, faces[i]) for i, box in enumerate(boxes)
             if box is not None and i < len(chunks)]
    with torch.no_grad():
        for start in range(0, len(valid), args.batch_size):
            group = valid[start:start + args.batch_size]
            latents = []
            for i, (x0, y0, x1, y1), _ in group:
                crop = cv2.resize(frames[i][y0:y1, x0:x1], (256, 256),
                                  interpolation=cv2.INTER_LANCZOS4)
                latents.append(vae.get_latents_for_unet(crop))
            batch = torch.cat(latents, dim=0).to(device=device, dtype=unet.model.dtype)
            audio = torch.stack([chunks[i] for i, _, _ in group]).to(device)
            generated = unet.model(batch, torch.tensor([0], device=device),
                                   encoder_hidden_states=pe(audio)).sample
            decoded = vae.decode_latents(generated)
            for row, image in zip(group, decoded):
                i, box, face = row
                output[i] = blend_mouth(frames[i], image, box, face)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    write_video(args.out, output, fps)
    report = {"source_video": str(args.video.resolve()), "voice": str(args.voice.resolve()),
              "output": str(args.out.resolve()), "frames": len(frames), "fps": fps,
              "faces_missing": misses, "model": "MuseTalk 1.5", "face_detector": "YuNet 2023mar",
              "face_hint": args.face_hint,
              "torch": torch.__version__, "opencv": cv2.__version__,
              "status": "visual review required"}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
