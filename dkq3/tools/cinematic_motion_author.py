#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Author a bounded cinematic performance from rig-space acting keys.

The original vertex animation is deliberately not an input. Source sequences
still determine the runtime identifier and duration when this motion is used
by animation_author.py; this file determines only cosmetic skeletal poses.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation

import animation_manifest as schema
import animation_motion as motion
from neural_assets import connected_motion
import skeletal_iqm as sk


CONTROLS = (
    "root", "spine", "chest", "neck", "head",
    "hand_l", "hand_r", "elbow_l", "elbow_r", "palm_l", "palm_r",
)
ANGLES = {"spine", "chest", "neck", "head", "palm_l", "palm_r"}
TRANSLATIONS = set(CONTROLS) - ANGLES


def _keys(document: dict, model: sk.Model) -> tuple[np.ndarray, dict[str, np.ndarray]]:
    schema.fields(document, ("version", "fps", "frames", "loop", "keys", "provenance"),
                  ("version", "fps", "frames", "loop", "keys", "provenance"), "authored motion")
    if document["version"] != 1 or type(document["loop"]) is not bool:
        raise schema.Error("version 1 and explicit loop boolean required", "ANIM_INVALID_RANGE")
    fps = schema.number(document["fps"], 1, 120, "fps")
    count = schema.number(document["frames"], 2, 4096, "frames", integer=True)
    if not isinstance(document["provenance"], str) or not document["provenance"].strip():
        raise schema.Error("authored motion requires provenance")
    keys = document["keys"]
    if not isinstance(keys, list) or not 2 <= len(keys) <= 128:
        raise schema.Error("2..128 acting keys required", "ANIM_INVALID_RANGE")
    times = []
    values = {name: [] for name in CONTROLS}
    previous = {name: np.zeros(3) for name in CONTROLS}
    required = {"pelvis", "spine", "chest", "neck", "head",
                "upperarm_l", "forearm_l", "hand_l", "upperarm_r", "forearm_r", "hand_r"}
    missing = required - set(model.names)
    if missing:
        raise schema.Error("authored rig lacks " + sorted(missing)[0], "ANIM_UNKNOWN_BONE")
    for index, key in enumerate(keys):
        schema.fields(key, ("frame", *CONTROLS), ("frame",), f"key {index}")
        frame = schema.number(key["frame"], 0, count - 1, f"key {index}.frame", integer=True)
        if times and frame <= times[-1]:
            raise schema.Error("acting key frames must increase", "ANIM_INVALID_RANGE", f"key {index}.frame")
        times.append(frame)
        for name in CONTROLS:
            if name in key:
                vector = np.asarray(schema.vector(key[name], f"key {index}.{name}"), dtype=float)
                bound = 90 if name in ANGLES else 20
                if np.any(np.abs(vector) > bound):
                    raise schema.Error("acting control exceeds bound", "ANIM_INVALID_RANGE", f"key {index}.{name}")
                previous[name] = vector
            values[name].append(previous[name].copy())
    if times[0] != 0 or times[-1] != count - 1:
        raise schema.Error("keys must cover first and last frame", "ANIM_INVALID_RANGE")
    if document["loop"] and any(not np.allclose(row[0], row[-1], atol=1e-8) for row in values.values()):
        raise schema.Error("loop end key differs from first key", "ANIM_LOOP_POSE_DISCONTINUITY")
    return np.asarray(times), {name: np.asarray(rows) for name, rows in values.items()}


def _sample(times: np.ndarray, keys: np.ndarray, count: int) -> np.ndarray:
    frame = np.arange(count)
    segment = np.clip(np.searchsorted(times, frame, side="right") - 1, 0, len(times) - 2)
    t = (frame - times[segment]) / (times[segment + 1] - times[segment])
    t = t * t * (3 - 2 * t)
    return keys[segment] * (1 - t[:, None]) + keys[segment + 1] * t[:, None]


def author(document: dict, model: sk.Model) -> motion.Motion:
    times, keys = _keys(document, model)
    count = document["frames"]
    controls = {name: _sample(times, values, count) for name, values in keys.items()}
    bind = sk.matrices(model.bind, model.parents)
    fitted = np.broadcast_to(bind, (count, len(model.names), 4, 4)).copy()
    index = {name: i for i, name in enumerate(model.names)}
    fitted[:, index["pelvis"], :3, 3] += controls["root"]
    for name in ("spine", "chest", "neck", "head"):
        fitted[:, index[name], :3, :3] = (
            bind[index[name], :3, :3] @ Rotation.from_euler("xyz", controls[name], degrees=True).as_matrix()
        )
    for side in ("l", "r"):
        hand = "hand_" + side
        elbow = "forearm_" + side
        fitted[:, index[hand], :3, 3] += controls["hand_" + side] + controls["root"]
        fitted[:, index[elbow], :3, 3] += controls["elbow_" + side] + controls["root"]
        fitted[:, index[hand], :3, :3] = (
            bind[index[hand], :3, :3] @ Rotation.from_euler("xyz", controls["palm_" + side], degrees=True).as_matrix()
        )
    channels = connected_motion(model, fitted, temporal_poles=True, preserve_observed_poles=True)
    world = sk.matrices(channels, model.parents)
    # Corrective joints in the captured rig were measurements, but authored
    # motion has no source measurement. Follow the anatomical parent exactly.
    # This leaves a stable local bind channel and works with anatomical skin.
    for j, name in enumerate(model.names):
        if name.startswith("deform_"):
            parent = model.parents[j]
            if parent < 0 or model.names[parent] != name.removeprefix("deform_"):
                raise schema.Error("authored corrective has no anatomical parent", "ANIM_UNKNOWN_BONE", name)
            world[:, j] = world[:, parent] @ sk.matrices(model.bind[j:j+1],[-1])[0]
    authored = motion.Motion(list(model.names), list(model.parents), bind, world, float(document["fps"]),
                             np.zeros((count, 3)), dict(kind="authored_cinematic",
                             provenance=document["provenance"], controls=list(CONTROLS),
                             loop=document["loop"]))
    motion.validate_motion(authored)
    return authored


def build(spec: Path, rig: Path, output: Path) -> dict:
    if output.exists() and any(output.iterdir()):
        raise schema.Error("authoring output must be fresh", "ANIM_INVALID_PATH", str(output))
    if rig.stat().st_size > 32 * 1024 * 1024:
        raise schema.Error("rig exceeds 32 MiB", "ANIM_INVALID_PATH", str(rig))
    model = sk.read(rig.read_bytes())
    document = schema.load(spec)
    authored = author(document, model)
    output.mkdir(parents=True, exist_ok=True)
    target = output / "motion.npz"
    temporary = output / "motion.partial.npz"
    motion.write(temporary, authored)
    temporary.replace(target)
    report = dict(version=1,kind="independently authored cinematic performance",
                  spec_sha256=schema.sha(spec),rig_sha256=schema.sha(rig),
                  output_sha256=schema.sha(target),frames=len(authored.world),
                  fps=authored.fps,loop=document["loop"],
                  source_animation_used=False,visual_acceptance="unverified")
    schema.write_json(output / "report.json", report)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec", type=Path)
    parser.add_argument("--rig", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(build(args.spec, args.rig, args.out), indent=2))
    except (schema.Error, OSError, ValueError, KeyError) as error:
        parser.exit(1, f"cinematic motion author: {error}\n")


if __name__ == "__main__":
    main()
