#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Replace a rejected inferred head with a dedicated close-up reconstruction.

The body atlas, skeleton and authored animation channels are retained. The new
head has its own atlas and triangle budget; shared renderer surface limits apply.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil

import numpy as np
from scipy.spatial import cKDTree
import skeletal_iqm as sk


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def influences(model, vertex):
    weights = np.zeros(len(model.names))
    np.add.at(weights, model.arrays[4][vertex], model.arrays[5][vertex] / 255.)
    return weights


def pack_weights(weights):
    joints = np.argsort(-weights, kind='stable')[:4]
    selected = weights[joints]
    if selected.sum() <= 0:
        raise ValueError('Unweighted replacement vertex')
    amounts = np.rint(selected / selected.sum() * 255).astype(int)
    amounts[0] += 255 - amounts.sum()
    return joints.astype('u1'), amounts.astype('u1')


def split_surfaces(rows, material, label):
    """Serialize triangle corners in bounded surfaces, preserving shared corners."""
    arrays = {kind: [] for kind in (0, 1, 2, 4, 5)}
    triangles, meshes, lookup = [], [], {}
    first_vertex = first_triangle = 0

    def flush():
        nonlocal first_vertex, first_triangle, lookup
        if len(triangles) > first_triangle:
            meshes.append((f'{label}_{len(meshes)}', material, first_vertex,
                           len(arrays[0]) - first_vertex, first_triangle,
                           len(triangles) - first_triangle))
        first_vertex, first_triangle, lookup = len(arrays[0]), len(triangles), {}

    for row in rows:
        keys = [b''.join(np.asarray(corner[kind], dtype='u1' if kind in (4, 5) else '<f4').tobytes()
                         for kind in arrays) for corner in row]
        if len(lookup) + sum(key not in lookup for key in keys) >= 990 or len(triangles) - first_triangle >= 1900:
            flush()
        face = []
        for key, corner in zip(keys, row):
            if key not in lookup:
                lookup[key] = len(arrays[0])
                for kind in arrays:
                    arrays[kind].append(corner[kind])
            face.append(lookup[key])
        triangles.append(face)
    flush()
    return ({kind: np.asarray(values, dtype='u1' if kind in (4, 5) else 'f4') for kind, values in arrays.items()},
            np.asarray(triangles, dtype='u4'), meshes)


def body_below(model, height, retain_upper_body=True, collar=None, collar_scope_radius=None):
    """Clip only the hidden neck join, retaining interpolated UVs and skinning."""
    rows = []
    def clip(polygon,normal,offset):
        if not polygon:return []
        result=[];previous=polygon[-1]
        previous_distance=float(normal@previous[0]-offset)
        for current in polygon:
            current_distance=float(normal@current[0]-offset)
            if (previous_distance<=0)!=(current_distance<=0):
                amount=previous_distance/(previous_distance-current_distance)
                result.append({key:previous[key]+amount*(current[key]-previous[key]) for key in previous})
            if current_distance<=0:result.append(current)
            previous,previous_distance=current,current_distance
        return result
    if collar:
        if not (collar['radius']>0 and collar['center_z']<=height):
            raise ValueError('Invalid contoured collar boundary')
        slope=(height-collar['center_z'])/collar['radius']
    if collar_scope_radius is not None and (not collar or not np.isfinite(collar_scope_radius) or collar_scope_radius <= 0):
        raise ValueError('A bounded neck cut needs a finite positive radius and a contoured collar')
    head_joints = [model.names.index(name) for name in ('head', 'neck') if name in model.names]
    for triangle in model.triangles:
        polygon = [{kind: model.arrays[kind][vertex].astype(float) for kind in (0, 1, 2)} |
                   {'weights': influences(model, vertex)} for vertex in triangle]
        # Keep shoulder armor and other chest/arm surfaces above the neck
        # plane. A height-only cut would discard those along with the old head.
        head_amount = np.mean([corner['weights'][head_joints].sum() for corner in polygon]) if retain_upper_body else 1.
        if head_amount < .5 and collar_scope_radius is None:
            pieces = [polygon]
        else:
            retained=[]
            if head_amount < .5:
                # The old reconstruction can attach throat/beard fragments
                # to the chest. Remove those inside the neck aperture while
                # preserving shoulder armor beyond it, regardless of weights.
                retained=[clip(polygon,np.array([0.,sign,0.]),-collar_scope_radius) for sign in (-1,1)]
                polygon=clip(clip(polygon,np.array([0.,1.,0.]),collar_scope_radius),np.array([0.,-1.,0.]),collar_scope_radius)
            clipped = clip(polygon,np.array([0.,0.,1.]),height)
            if collar:
                # Two linear half-spaces give an exact V-shaped hidden collar
                # boundary. Lower the neck center while retaining outer cowl
                # and shoulder height; interpolate UVs/skin at every cut.
                pieces=[]
                for sign in (-1,1):
                    side=clip(clipped,np.array([0.,-sign,0.]),0.)
                    pieces.append(clip(side,np.array([0.,-sign*slope,1.]),collar['center_z']))
            else:pieces=[clipped]
            pieces+=retained
        for clipped in pieces:
            for i in range(1, len(clipped) - 1):
                corners = []
                for corner in [clipped[0], clipped[i], clipped[i + 1]]:
                    weights = corner['weights']
                    joints, amounts = pack_weights(weights)
                    normal = corner[2] / max(np.linalg.norm(corner[2]), 1e-9)
                    corners.append({0: corner[0], 1: corner[1], 2: normal, 4: joints, 5: amounts})
                p = [corner[0] for corner in corners]
                if np.linalg.norm(np.cross(p[1] - p[0], p[2] - p[0])) > 1e-9:
                    rows.append(corners)
    return rows


def compose(actor, head, output, config):
    baseline = actor / 'head-baseline'
    basis = baseline if (baseline / 'model.iqm').is_file() else actor
    original_iqm_sha = sha(basis / 'model.iqm')
    original_texture_sha = sha(basis / 'body.png')
    original = sk.read((basis / 'model.iqm').read_bytes())
    geometry = np.load(head / 'head-geometry.npz')
    raw = geometry['points'].astype(float)
    points = raw - (raw.min(axis=0) + raw.max(axis=0)) / 2
    scale = config['height'] / np.ptp(raw[:, 2])
    yaw = np.deg2rad(config.get('yaw', 0))
    rotation = np.array([[np.cos(yaw), -np.sin(yaw), 0], [np.sin(yaw), np.cos(yaw), 0], [0, 0, 1]])
    translation = np.asarray([*config.get('center_xy', [0, 0]), config['bottom_z'] + config['height'] / 2])
    points = points @ rotation.T * scale + translation
    normals = geometry['normals'] @ rotation.T
    if 'neck_extension' in config:
        extension=config['neck_extension'];top=float(extension['top_z']);bottom=float(extension['bottom_z'])
        if not (np.isfinite(top) and np.isfinite(bottom) and bottom<config['bottom_z']<top):
            raise ValueError('Neck extension must end below the head and preserve the jaw')
        amount=(top-bottom)/(top-config['bottom_z'])
        affected=points[:,2]<top
        radial=float(extension.get('radial_scale',1.))
        if not np.isfinite(radial) or not 1 <= radial <= 3:
            raise ValueError('Neck radius scale must be finite and between one and three')
        fraction=(top-points[affected,2])/(top-config['bottom_z'])
        widening=1+(radial-1)*fraction
        relative=points[affected,:2]-translation[:2]
        # Inverse transpose of the neck deformation Jacobian, including the
        # changing radius. The jaw and all points above it remain exact.
        normals[affected,2]+=(radial-1)/(top-config['bottom_z'])*np.sum(relative*normals[affected,:2],axis=1)/widening
        normals[affected,:2]/=widening[:,None]
        points[affected,:2]=translation[:2]+relative*widening[:,None]
        points[affected,2]=top-(top-points[affected,2])*amount
        normals[affected,2]/=amount
        normals[affected]/=np.maximum(np.linalg.norm(normals[affected],axis=1,keepdims=True),1e-12)
    body = copy.deepcopy(original)
    # Transfer the retained rig's real neck/head blending rather than inventing
    # another skeleton or rescheduling any gameplay/cinematic channels.
    source_points = original.arrays[0]
    candidates = np.flatnonzero(source_points[:, 2] >= config['cut_z'] - 1.5)
    distance, nearest = cKDTree(source_points[candidates]).query(points, k=min(4, len(candidates)))
    nearest = candidates[nearest]
    inverse = 1 / np.maximum(distance, .01)
    inverse /= inverse.sum(axis=1, keepdims=True)
    weights = np.zeros((len(points), len(original.names)))
    for column in range(nearest.shape[1]):
        vertices = nearest[:, column]
        for influence in range(4):
            np.add.at(weights, (np.arange(len(points)), original.arrays[4][vertices, influence]),
                      inverse[:, column] * original.arrays[5][vertices, influence] / 255)
    if 'rigid_head_above_z' in config:
        threshold = float(config['rigid_head_above_z'])
        if not np.isfinite(threshold) or 'head' not in original.names:
            raise ValueError('Rigid facial skinning needs a finite threshold and the retained head bone')
        # The authored rig has no independent facial animation. A nearest-body
        # lookup can accidentally attach nose/cheek vertices to the chest or
        # neck. Keep facial anatomy rigid, blending into the inherited collar
        # weights only below the jaw; original animation channels stay exact.
        amount = np.clip((points[:, 2] - (threshold - 1.5)) / 1.5, 0, 1)
        amount = amount * amount * (3 - 2 * amount)
        weights *= 1 - amount[:, None]
        weights[:, original.names.index('head')] += amount
    packed = [pack_weights(weight) for weight in weights]
    head_arrays = {0: points, 1: geometry['uv'], 2: normals,
                   4: np.asarray([pair[0] for pair in packed]), 5: np.asarray([pair[1] for pair in packed])}
    head_triangles=geometry['triangles']
    body_texture=basis/'body.png'
    if config.get('body_texture') == 'before-face':
        body_texture = actor / 'body-before-face.png'
        expected = json.loads((actor / 'body.face.json').read_text())['original_texture_sha256']
        if sha(body_texture) != expected:
            raise ValueError('Untouched body atlas belongs to another conversion')
    retain_upper_body = config.get('retain_upper_body', True)
    if not isinstance(retain_upper_body, bool):
        raise ValueError('Upper-body retention must be boolean')
    body_rows = body_below(body, config['cut_z'], retain_upper_body,config.get('collar'),config.get('collar_scope_radius'))
    head_rows = [[{kind: values[vertex] for kind, values in head_arrays.items()} for vertex in triangle]
                 for triangle in head_triangles]
    body_arrays, body_triangles, body_meshes = split_surfaces(body_rows,
                                                           f'models/neural/{actor.name}/body', 'body')
    new_arrays, new_triangles, new_meshes = split_surfaces(head_rows, f'models/neural/{actor.name}/head', 'head')
    vertex_offset, triangle_offset = len(body_arrays[0]), len(body_triangles)
    model = copy.deepcopy(original)
    model.arrays = {kind: np.concatenate((body_arrays[kind], new_arrays[kind])) for kind in body_arrays}
    model.triangles = np.concatenate((body_triangles, new_triangles + vertex_offset))
    model.meshes = body_meshes + [(name, material, fv + vertex_offset, nv, ft + triangle_offset, nt)
                                for name, material, fv, nv, ft, nt in new_meshes]
    output.mkdir(parents=True, exist_ok=True)
    if actor.resolve() == output.resolve():
        backup = actor / ('model-before-head-' + original_iqm_sha[:12] + '.iqm')
        if not backup.exists():
            shutil.copy2(basis / 'model.iqm', backup)
    (output / 'model.iqm').write_bytes(sk.write(model))
    if actor.resolve() != output.resolve():
        shutil.copy2(body_texture, output / 'body.png')
    shutil.copy2(head / 'head.png', output / 'head.png')
    head_model = copy.deepcopy(original)
    head_model.arrays = new_arrays
    head_model.triangles = new_triangles
    head_model.meshes = new_meshes
    head_model.frames = original.bind[None].copy()
    (output / 'head-model.iqm').write_bytes(sk.write(head_model))
    body_model = copy.deepcopy(original)
    body_model.arrays,body_model.triangles,body_model.meshes=body_arrays,body_triangles,body_meshes
    body_model.frames=original.bind[None].copy()
    (output/'body-model.iqm').write_bytes(sk.write(body_model))
    serialized = sk.read((output / 'model.iqm').read_bytes())
    assert serialized.names == original.names and serialized.parents == original.parents
    assert np.array_equal(serialized.bind, original.bind)
    assert np.array_equal(serialized.frames, original.frames)
    report = dict(format=1, method='Dedicated close-up TRELLIS head, separate full-resolution atlas and head budget; original body and animation retained',
                  body_iqm_sha256=original_iqm_sha, body_texture_sha256=original_texture_sha,
                  head_concept_sha256=sha(head / 'concept.png'), head_glb_sha256=sha(head / 'model.glb'),
                  head_geometry_sha256=sha(head / 'head-geometry.npz'), head_texture_sha256=sha(output / 'head.png'),
                  output_iqm_sha256=sha(output / 'model.iqm'), config=config,
                  retained_body_atlas_sha256=sha(output/'body.png'),
                  body_triangles=len(body_triangles), head_triangles=len(new_triangles),
                  skeleton_and_serialized_frame_channels='exact',
                  join='Clipped internal body boundary is covered by the overlapping reconstructed collar; visual and animated acceptance required.')
    (output / 'head-reconstruction.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor', type=Path, required=True)
    parser.add_argument('--head', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(compose(args.actor, args.head, args.out, json.loads(args.config.read_text())), indent=2))
