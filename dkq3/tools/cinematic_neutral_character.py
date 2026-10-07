#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build an independent neutral cinematic body with the approved Hiro face.

The generated costume is never deformed to a legacy pose. The only reference
capture input is a static head orientation used to retain the approved face.
Runtime animation identifiers and original-asset fallback are separate.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import numpy as np

import animation_manifest as schema
from generated_character import admitted_head_rows, join_neck, neck_boundary, neutral_admitted_head
from neural_head import body_below, split_surfaces
from neural_monster_skeleton import skeleton, append_attachment
from neural_rig import skin_weights
import skeletal_iqm as sk


def _normalized_body(source: sk.Model) -> tuple[sk.Model, dict]:
    points = source.arrays[0]
    height = float(np.ptp(points[:, 2]))
    low = float(points[:, 2].min())
    center_y = float((points[:, 1].min() + points[:, 1].max()) / 2)
    z = (points[:, 2] - low) * 56 / height - 24
    torso = points[(z > 8) & (z < 20) & (np.abs(points[:, 1] - center_y) < height / 10)]
    if not 45 <= height <= 80 or len(torso) < 8:
        raise schema.Error('generated neutral body scale or torso is unobservable', 'ANIM_INVALID_BIND')
    origin = np.array([np.median(torso[:, 0]), center_y, low + 24 * height / 56])
    result = copy.deepcopy(source)
    result.arrays[0] = (points - origin) * 56 / height
    return result, dict(origin=origin.tolist(), scale=56 / height)


def _convert_head_weights(rows: list, old_names: list[str], names: list[str]) -> None:
    for row in rows:
        for corner in row:
            for slot, weight in enumerate(corner[5]):
                if weight:
                    name = old_names[int(corner[4][slot])]
                    if name not in names:
                        raise schema.Error('approved head uses unknown neutral bone', 'ANIM_UNKNOWN_BONE', name)
                    corner[4][slot] = names.index(name)


def _append(model: sk.Model, rows: list, material: str, name: str) -> None:
    arrays, triangles, meshes = split_surfaces(rows, material, name)
    first_vertex = len(model.arrays[0])
    first_triangle = len(model.triangles)
    for key in (0, 1, 2, 4, 5):
        model.arrays[key] = np.concatenate((model.arrays[key], arrays[key]))
    model.triangles = np.concatenate((model.triangles, triangles + first_vertex))
    model.meshes.extend((n, mat, fv + first_vertex, nv, ft + first_triangle, nt)
                        for n, mat, fv, nv, ft, nt in meshes)


def _ring_center(model: sk.Model, height: float) -> np.ndarray:
    ring = model.arrays[0][np.abs(model.arrays[0][:, 2] - height) < .001]
    if not 8 <= len(ring) <= 4096:
        raise schema.Error('neutral neck cut has no bounded ring', 'ANIM_ATTACHMENT_ERROR')
    return ring[:, :2].mean(axis=0)


def build(recipe_path: Path, body_path: Path, head_path: Path,
          rest_path: Path, output: Path) -> dict:
    recipe = schema.load(recipe_path)
    schema.fields(recipe, ('version', 'body_sha256', 'head_sha256', 'rest_sha256',
                           'body_material', 'head_material', 'rig', 'body_cut',
                           'head_cut', 'head_neck_blend', 'head_translation',
                           'head_ring_hint', 'neck_policy', 'head_scale', 'provenance'),
                  ('version', 'body_sha256', 'head_sha256', 'rest_sha256',
                   'body_material', 'head_material', 'rig', 'body_cut',
                   'head_cut', 'head_neck_blend', 'head_translation', 'provenance'),
                  'neutral character')
    if recipe['version'] != 1:
        raise schema.Error('neutral character version must be 1')
    for key, path in (('body_sha256', body_path), ('head_sha256', head_path),
                      ('rest_sha256', rest_path)):
        if path.stat().st_size > 32 * 1024 * 1024 or schema.sha(path) != recipe[key]:
            raise schema.Error('declared neutral input changed', 'ANIM_SOURCE_HASH_MISMATCH', key)
    if output.is_symlink() or output.is_file() or (output.exists() and any(output.iterdir())):
        raise schema.Error('neutral character output must be fresh', 'ANIM_INVALID_PATH')
    body_material = schema.asset(recipe['body_material'])
    head_material = schema.asset(recipe['head_material'])
    body_cut = schema.number(recipe['body_cut'], 21, 25, 'body_cut')
    head_cut = schema.number(recipe['head_cut'], body_cut + .05, body_cut + 2, 'head_cut')
    neck_policy = recipe.get('neck_policy', 'bridge')
    if neck_policy not in ('bridge', 'weighted_overlap'):
        raise schema.Error('unknown neutral neck policy', 'ANIM_INVALID_SOURCE', 'neck_policy')
    translation = schema.vector(recipe['head_translation'], 'head_translation')
    head_scale = schema.number(recipe.get('head_scale', 1.), .9, 1.2, 'head_scale')
    if any(abs(value) > 8 for value in translation):
        raise schema.Error('head translation exceeds neutral fit bounds', 'ANIM_INVALID_RANGE')
    source, normalization = _normalized_body(sk.read(body_path.read_bytes()))
    names, parents, absolute = skeleton(recipe['rig'])
    for name, parent, delta in (('tag_torso', 'spine', [0, 0, 0]),
                                ('tag_head', 'head', [0, 0, 0]),
                                ('tag_weapon', 'hand_r', [1.5, 0, -1.8])):
        absolute = append_attachment(names, parents, absolute, name, parent, np.asarray(delta))
    source.names, source.parents = names, parents
    source.bind = sk.channels(absolute, parents)
    source.frames = source.bind[None].copy()
    skin_weights(source, 'hiro', absolute, landmarks=recipe['rig'])
    # Cut the featureless generated head at the declared neck ring.
    body_rows = body_below(source, body_cut, retain_upper_body=neck_policy == 'weighted_overlap')
    body_arrays, body_triangles, body_meshes = split_surfaces(body_rows, body_material, 'generated_gi')
    model = sk.Model(body_arrays, body_meshes, body_triangles, names, parents,
                     source.bind.copy(), source.frames.copy())
    if neck_policy == 'bridge':
        try:
            body_ring = neck_boundary(model, body_cut, _ring_center(model, body_cut))
        except schema.Error as error:
            raise schema.Error(f'generated body: {error}', error.code, 'body_cut') from error
        body_center = np.mean([row[0][:2] for row in body_ring], axis=0)
    else:
        body_center = np.array([0., 0.])
    # The approved face is rigidly reoriented once. The static rest capture
    # supplies orientation only, never new body geometry or animation frames.
    approved = sk.read(head_path.read_bytes())
    with np.load(rest_path, allow_pickle=False) as rest:
        old_names = rest['names'].tolist()
        rotation = rest['rest'][old_names.index('head'), :3, :3]
    head = neutral_admitted_head(approved, rotation, recipe['head_neck_blend'], translation)
    head_rows = admitted_head_rows(head, head_material, head_cut)
    _convert_head_weights(head_rows, approved.names, names)
    head_arrays, head_triangles, head_meshes = split_surfaces(head_rows, head_material, 'approved_head')
    head_model = sk.Model(head_arrays, head_meshes, head_triangles, names, parents,
                          source.bind.copy(), source.frames.copy())
    ring_hint = np.asarray(schema.vector(recipe['head_ring_hint'], 'head_ring_hint', 2)) \
        if 'head_ring_hint' in recipe else _ring_center(head_model, head_cut)
    try:
        head_ring = neck_boundary(head_model, head_cut, ring_hint)
    except schema.Error as error:
        raise schema.Error(f'approved head: {error}', error.code, 'head_cut') from error
    head_center = np.mean([row[0][:2] for row in head_ring], axis=0)
    delta = body_center - head_center
    head_model.arrays[0][:, :2] += delta
    # Uniform sizing preserves the approved face's proportions and UVs. The
    # cut plane remains fixed so the neck sits inside the generated collar.
    pivot = np.array([*body_center, head_cut])
    head_model.arrays[0] = pivot + (head_model.arrays[0] - pivot) * head_scale
    if neck_policy == 'bridge':
        bridge, receipt = join_neck(model, head_model, body_cut, head_cut, body_center.tolist())
        # The bridge inherits approved neck UVs and the endpoint bone weights.
        _append(model, bridge, head_material, 'neck_bridge')
    else:
        receipt = dict(policy=neck_policy, boundary_connection=False)
    _append(model, [[{key: head_model.arrays[key][v].copy() for key in (0, 1, 2, 4, 5)}
                     for v in tri] for tri in head_model.triangles], head_material, 'approved_head')
    sk.validate(model)
    output.mkdir(parents=True, exist_ok=True)
    target = output / 'neutral.iqm'
    schema.write_if_changed(target, sk.write(model))
    report = dict(version=1, passed=True, kind='independent neutral generated body with approved face',
                  recipe_sha256=schema.sha(recipe_path), output_sha256=schema.sha(target),
                  body_sha256=schema.sha(body_path), head_sha256=schema.sha(head_path),
                  rest_sha256=schema.sha(rest_path),
                  normalization=normalization, body_ring_center=body_center.tolist(),
                  head_ring_center_before_fit=head_center.tolist(), head_fit_delta=delta.tolist(),
                  head_scale=head_scale,
                  neck=receipt, vertices=len(model.arrays[0]), triangles=len(model.triangles),
                  frames=len(model.frames), provenance=recipe['provenance'],
                  visual_acceptance='unverified')
    schema.write_json(output / 'neutral.json', report)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recipe', type=Path)
    parser.add_argument('--body', type=Path, required=True)
    parser.add_argument('--head', type=Path, required=True)
    parser.add_argument('--rest', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    arguments = parser.parse_args()
    try:
        print(json.dumps(build(arguments.recipe, arguments.body, arguments.head,
                               arguments.rest, arguments.out), indent=2))
    except (schema.Error, ValueError, OSError, KeyError, IndexError) as error:
        parser.exit(1, f'cinematic neutral character: {error}\n')


if __name__ == '__main__':
    main()
