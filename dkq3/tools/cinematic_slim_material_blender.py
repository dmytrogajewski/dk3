#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Bake a clean material from measured neutral-space surface classes.

The generated atlas contains extensive black bake holes. Retaining its cloth
pixels makes them look like tears, so the costume gets a restrained 3D-space
albedo; the existing geometry and lighting supply the folds.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import animation_manifest as schema
from generated_materials import sample_uv_rgb
import skeletal_iqm as sk
import dkimg


def paint(points: np.ndarray, rgb: np.ndarray,
          arm_ownership: np.ndarray | None = None,
          hand_ownership: np.ndarray | None = None) -> tuple[np.ndarray, dict]:
    """Classify in neutral 3D and repair only the measured garment surface."""
    if points.shape != rgb.shape or not np.isfinite(points).all() or not np.isfinite(rgb).all():
        raise schema.Error('nonfinite slim material input', 'ANIM_NONFINITE_TRANSFORM')
    x, y, z = points.T
    side = np.abs(y)
    brightness = rgb.mean(axis=1)
    # The generated forearm/palm color is a reproducible neutral grey. Its
    # geometric band excludes gray leather belt and boots.
    arm_band = (side > 7.4) & (z > 2.5) & (z < 14)
    skin = arm_band & (brightness > .34) & (brightness < .75)
    for sign in (-1, 1):
        palm = np.array([1.7, sign * 10., 3.2])
        hand_surface = np.linalg.norm(points - palm, axis=1) < 3.5
        skin |= hand_surface & (z < 7) & (side > 7.4) & (x > .5)
    if arm_ownership is not None:
        if arm_ownership.shape != (len(points),) or not np.isfinite(arm_ownership).all():
            raise schema.Error('invalid neutral arm ownership', 'ANIM_INVALID_WEIGHTS')
        near_arm = np.zeros(len(points), dtype=bool)
        for sign in (-1, 1):
            elbow = np.array([0., sign * 8.8, 12.])
            wrist = np.array([0., sign * 10.3, 5.])
            axis = wrist - elbow
            fraction = np.clip((points - elbow) @ axis / (axis @ axis), 0, 1)
            near_arm |= np.linalg.norm(points - (elbow + fraction[:, None] * axis), axis=1) < 2.45
        skin |= (arm_ownership > .38) & near_arm & (z < 15.5) & (side > 7.5)
        skin |= (arm_ownership > .15) & near_arm & (z > 8) & (z < 15) & (side > 6.6)
    if hand_ownership is not None:
        if hand_ownership.shape != (len(points),) or not np.isfinite(hand_ownership).all():
            raise schema.Error('invalid neutral hand ownership', 'ANIM_INVALID_WEIGHTS')
        # The side tabs also have high hand weights, but their x coordinate is
        # positive. Only the distal tips turn behind the neutral hand center.
        skin |= (hand_ownership > .7) & (z < 6.5) & (side > 6) & (x < 0)
    # The generated atlas's dark waist islands are not a reliable belt mask;
    # on the mesh they cover the lower robe hem. A separate geometric belt
    # can be authored later, but the damaged band must not be baked in.
    boots = z < -20.5
    cloth = ~skin & ~boots & (z < 24.5)
    if cloth.sum() < 1000 or skin.sum() < 1000:
        raise schema.Error('slim costume material regions are unobservable', 'ANIM_INVALID_SOURCE')
    result = np.empty_like(rgb)
    # Bounded variation prevents corrupt atlas texels from reappearing as
    # mottled cloth, while retaining some nonuniformity on a large white area.
    weave = .012 * np.sin(x * 2.1 + z * .6) * np.sin(y * 1.8 - z * .4)
    fold = .014 * np.sin(z * .9 + x * .4)
    shade = weave + fold
    result[:] = np.column_stack((.78 + shade, .77 + shade, .73 + shade))
    skin_tone = np.clip(.58 + .12 * (brightness - .5), .53, .64)
    result[skin] = np.column_stack((skin_tone, skin_tone * .75, skin_tone * .63))[skin]
    shoe_mix = np.clip((-z - 19.8) / 1.5, 0., 1.)[:, None]
    result = result * (1 - shoe_mix) + np.array([.27, .265, .25]) * shoe_mix
    return np.clip(result, 0, 1), dict(skin_vertices=int(skin.sum()),
                                     cloth_vertices=int(cloth.sum()),
                                     method='neutral 3D semantic albedo')


def bake(model_path: Path, texture_path: Path, output: Path) -> dict:
    import bpy
    if output.is_symlink() or output.is_file() or (output.exists() and any(output.iterdir())):
        raise schema.Error('material output must be fresh', 'ANIM_INVALID_PATH')
    if model_path.stat().st_size > 32 * 1024 * 1024 or texture_path.stat().st_size > 64 * 1024 * 1024:
        raise schema.Error('slim material input exceeds limit', 'ANIM_INVALID_PATH')
    model = sk.read(model_path.read_bytes())
    with Image.open(texture_path) as image:
        if image.format != 'PNG' or image.size != (4096, 4096):
            raise schema.Error('slim source texture must be 4096px PNG')
        source = np.asarray(image.convert('RGB'))
    points = model.arrays[0]
    height = np.ptp(points[:, 2]); low = points[:, 2].min()
    center_y = (points[:, 1].min() + points[:, 1].max()) / 2
    z = (points[:, 2] - low) * 56 / height - 24
    torso = points[(z > 8) & (z < 20) & (np.abs(points[:, 1] - center_y) < height / 10)]
    if not 45 <= height <= 80 or len(torso) < 8:
        raise schema.Error('slim material body scale is unobservable', 'ANIM_INVALID_BIND')
    origin = np.array([np.median(torso[:, 0]), center_y, low + 24 * height / 56])
    neutral = (points - origin) * 56 / height
    arm_bones = [i for i, name in enumerate(model.names)
                 if name.startswith(('upperarm_', 'forearm_', 'hand_', 'fingers_', 'thumb_'))]
    hand_bones = [i for i, name in enumerate(model.names)
                  if name.startswith(('hand_', 'fingers_', 'thumb_'))]
    ownership = np.sum(model.arrays[5] * np.isin(model.arrays[4], arm_bones), axis=1) / 255. \
        if arm_bones else None
    hand_ownership = np.sum(model.arrays[5] * np.isin(model.arrays[4], hand_bones), axis=1) / 255. \
        if hand_bones else None
    colors, regions = paint(neutral, sample_uv_rgb(source, model.arrays[1]), ownership, hand_ownership)
    body_material = 'models/neural/hiro-dojo-slim/body'
    body_triangles = np.concatenate([model.triangles[ft:ft + nt]
                                     for _, material, _, _, ft, nt in model.meshes
                                     if material == body_material])
    if len(body_triangles) < 1000:
        raise schema.Error('slim body surface absent', 'ANIM_INVALID_SOURCE')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = bpy.data.meshes.new('generated slim gi surface')
    mesh.from_pydata(points.tolist(), [], body_triangles[:, [0, 2, 1]].tolist())
    mesh.update()
    obj = bpy.data.objects.new('generated slim gi', mesh)
    bpy.context.collection.objects.link(obj)
    uv = mesh.uv_layers.new(name='qualified atlas')
    for loop in mesh.loops:
        u, v = model.arrays[1][loop.vertex_index]
        uv.data[loop.index].uv = (u, 1 - v)
    attribute = mesh.color_attributes.new(name='authored generated albedo', type='FLOAT_COLOR', domain='CORNER')
    for loop in mesh.loops:
        attribute.data[loop.index].color = (*colors[loop.vertex_index], 1.)
    material = bpy.data.materials.new('slim gi albedo')
    material.use_nodes = True
    mesh.materials.append(material)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    source_node = nodes.new('ShaderNodeVertexColor')
    source_node.layer_name = attribute.name
    emission = nodes.new('ShaderNodeEmission')
    links.new(source_node.outputs['Color'], emission.inputs['Color'])
    links.new(emission.outputs[0], nodes.get('Material Output').inputs['Surface'])
    target_image = bpy.data.images.new('baked slim gi albedo', width=4096, height=4096, alpha=False)
    target_image.colorspace_settings.name = 'Non-Color'
    target = nodes.new('ShaderNodeTexImage'); target.image = target_image; nodes.active = target
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 1
    bpy.context.view_layer.objects.active = obj; obj.select_set(True)
    bpy.ops.object.bake(type='EMIT', use_selected_to_active=False, margin=8)
    pixels = np.empty(len(target_image.pixels), np.float32)
    target_image.pixels.foreach_get(pixels)
    baked = np.rint(np.clip(pixels.reshape(4096, 4096, 4)[::-1, :, :3], 0, 1) * 255).astype('u1')
    output.mkdir(parents=True, exist_ok=True)
    path = output / 'body.png'; temporary = output / 'body.partial'
    temporary.write_bytes(dkimg.encode_png(baked)); temporary.replace(path)
    report = dict(passed=True, model_sha256=schema.sha(model_path), source_texture_sha256=schema.sha(texture_path),
                  output_sha256=schema.sha(path), tool_sha256=schema.sha(Path(__file__)),
                  blender=bpy.app.version_string, texture_size=[4096, 4096], regions=regions,
                  originals_modified=False, visual_acceptance='unverified')
    schema.write_json(output / 'materials.json', report)
    return report


def main() -> None:
    argv = sys.argv[sys.argv.index('--') + 1:]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--texture', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        print(json.dumps(bake(args.model, args.texture, args.out), sort_keys=True))
    except (schema.Error, ValueError, OSError, KeyError) as error:
        parser.exit(1, f'slim gi material: {error}\n')


if __name__ == '__main__':
    main()
