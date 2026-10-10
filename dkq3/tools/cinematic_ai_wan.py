"""Submit a pose-driven Wan Animate trial to a local ComfyUI instance.

The source image and motion tracks are copied into the instance's local input
directory. DK3 assets, recordings, and installed game files are never edited.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import urllib.parse
import urllib.request


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def stage(source: Path, input_dir: Path) -> str:
    source = source.resolve(strict=True)
    input_dir = input_dir.resolve(strict=True)
    target = input_dir / f"dk3-{digest(source)[:16]}-{source.name}"
    if not target.exists() or digest(target) != digest(source):
        temporary = target.with_name(target.name + ".tmp")
        shutil.copyfile(source, temporary)
        temporary.replace(target)
    return str(target)


def graph(args: argparse.Namespace, image_name: str, pose_path: str, face_path: str) -> dict[str, dict]:
    def node(kind: str, **inputs: object) -> dict:
        return {"class_type": kind, "inputs": inputs}

    video_input = dict(force_rate=args.fps, custom_width=0, custom_height=0,
                       frame_load_cap=0, skip_first_frames=0, select_every_nth=1)
    result = {
        "1": node("LoadImage", image=image_name),
        "2": node("VHS_LoadVideoPath", video=pose_path, **video_input),
        "3": node("VHS_LoadVideoPath", video=face_path, **video_input),
        "4": node("WanVideoVAELoader", model_name=args.vae, precision="bf16"),
        "5": node("CLIPVisionLoader", clip_name=args.clip_vision),
        "6": node("WanVideoClipVisionEncode", clip_vision=["5", 0], image_1=["1", 0],
                  strength_1=1.0, strength_2=1.0, crop="center",
                  combine_embeds="average", force_offload=True),
        "7": node("WanVideoAnimateEmbeds", vae=["4", 0], width=args.width,
                  height=args.height, num_frames=args.frames, force_offload=True,
                  frame_window_size=args.frames, colormatch="disabled",
                  pose_strength=1.0, face_strength=1.0, clip_embeds=["6", 0],
                  ref_images=["1", 0], pose_images=["2", 0], face_images=["3", 0]),
        "8": node("WanVideoTextEncodeCached", model_name=args.text_encoder,
                  precision="bf16", positive_prompt=args.prompt,
                  negative_prompt=args.negative_prompt, quantization="disabled",
                  use_disk_cache=True, device="cpu"),
        "9": node("WanVideoBlockSwap", blocks_to_swap=args.blocks_to_swap,
                  offload_img_emb=False, offload_txt_emb=False,
                  use_non_blocking=False, vace_blocks_to_swap=0,
                  prefetch_blocks=0, block_swap_debug=False),
        "10": node("WanVideoModelLoader", model=args.model,
                   base_precision="fp16_fast", quantization="disabled",
                   load_device="offload_device", attention_mode="sdpa",
                   block_swap_args=["9", 0]),
        "11": node("WanVideoSampler", model=["10", 0], image_embeds=["7", 0],
                   steps=args.steps, cfg=1.0, shift=5.0, seed=args.seed,
                   force_offload=True, scheduler="dpm++_sde",
                   riflex_freq_index=0, text_embeds=["8", 0]),
        "12": node("WanVideoDecode", vae=["4", 0], samples=["11", 0],
                   enable_vae_tiling=False, tile_x=272, tile_y=272,
                   tile_stride_x=144, tile_stride_y=128),
        "13": node("VHS_VideoCombine", images=["12", 0], frame_rate=args.fps,
                   loop_count=0, filename_prefix=args.output_prefix,
                   format="video/h264-mp4", pingpong=False, save_output=True),
    }
    if args.lora:
        result["14"] = node("WanVideoLoraSelectMulti", lora_0=args.lora,
                            strength_0=args.lora_strength, lora_1="none", strength_1=1.0,
                            lora_2="none", strength_2=1.0, lora_3="none", strength_3=1.0,
                            lora_4="none", strength_4=1.0, merge_loras=False)
        result["15"] = node("WanVideoSetLoRAs", model=["10", 0], lora=["14", 0])
        result["11"]["inputs"]["model"] = ["15", 0]
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", default="http://127.0.0.1:8188")
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--pose-video", type=Path, required=True)
    parser.add_argument("--face-video", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--output-prefix", default="dk3-wan-trial")
    parser.add_argument("--model", default="Wan2_2-Animate-14B_fp8_e4m3fn_scaled_KJ.safetensors")
    parser.add_argument("--text-encoder", default="umt5-xxl-enc-fp8_e4m3fn.safetensors")
    parser.add_argument("--clip-vision", default="clip_vision_h.safetensors")
    parser.add_argument("--vae", default="Wan2_1_VAE_bf16.safetensors")
    parser.add_argument("--width", type=int, default=832)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--frames", type=int, default=45)
    parser.add_argument("--fps", type=int, default=24)
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--seed", type=int, default=346)
    parser.add_argument("--blocks-to-swap", type=int, default=30)
    parser.add_argument("--lora", default="", help="optional model LoRA name")
    parser.add_argument("--lora-strength", type=float, default=1.2)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--negative-prompt", default="cartoon, CGI, warped face, extra limbs")
    args = parser.parse_args()
    address = urllib.parse.urlparse(args.server)
    if address.hostname not in ("127.0.0.1", "localhost", "::1"):
        parser.error("--server must be loopback")
    if args.frames < 5 or args.frames > 121 or args.frames % 4 != 1:
        parser.error("--frames must be 4n+1 from 5 through 121")
    if args.width % 16 or args.height % 16 or min(args.width, args.height) < 256:
        parser.error("width and height must be multiples of 16 and at least 256")
    if args.steps < 1 or args.steps > 50 or not 0 <= args.blocks_to_swap <= 40:
        parser.error("steps or blocks-to-swap out of range")
    if not 0 <= args.lora_strength <= 3:
        parser.error("LoRA strength must be between 0 and 3")
    if not args.prompt.strip():
        parser.error("--prompt must not be blank")
    image_path = stage(args.image, args.input_dir)
    pose_path = stage(args.pose_video, args.input_dir)
    face_path = stage(args.face_video, args.input_dir)
    payload = {"prompt": graph(args, Path(image_path).name, pose_path, face_path),
               "client_id": "dk3-cinematic-ai-wan"}
    request = urllib.request.Request(args.server.rstrip("/") + "/prompt",
                                     data=json.dumps(payload).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        result = json.load(response)
    report = {"prompt_id": result.get("prompt_id"), "server_response": result,
              "input_sha256": {"image": digest(args.image), "pose": digest(args.pose_video),
                               "face": digest(args.face_video)},
              "graph": payload["prompt"]}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("prompt_id") else 1


if __name__ == "__main__":
    sys.exit(main())
