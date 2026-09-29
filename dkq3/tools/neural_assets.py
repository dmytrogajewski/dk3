#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Adapt explicitly selected local neural character assets to the native game.

Reads the five experiment's full-body IQMs and baked textures as data, never its
runtime or Python modules. Gameplay clips are resampled onto authored sequence
timelines. Cinematic vertex animation is fitted to the replacement skeleton.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import zipfile

import numpy as np

import dkimg
import dkm2md3
import md3
import skeletal_iqm as sk
from neural_package import MANIFEST, validate_package

CHARACTERS = ('hiro', 'mikiko', 'superfly', 'mishima', 'usagi')
COLORS = ((1, 1, 1), (.25, .85, .35), (.2, .45, 1), (.8, .85, .9), (1, .45, .15),
          (.7, .25, .9), (1, .85, .15), (1, .18, .12), (.15, .25, .65), (1, .7, .15),
          (.55, .12, .2), (.45, .5, .2))


def character(path):
    stem = Path(path).stem
    if stem in ('m_mikikofly', 'c_mikikofly'): return 'mikikofly'
    if stem in ('m_hiro', 'm_hiro2', 'hiro') or stem.startswith(('c_hiro_', 'c_phiro_', 'c_inshiro_')):
        return 'hiro'
    if stem in ('m_mikiko', 'm_smikiko', 'mikiko', 'd1_mikdead') or stem.startswith(('c_mikiko_', 'c_smikiko_')):
        return 'mikiko'
    if stem in ('m_superfly', 'superfly', 'd2_superfly', 'd1_supertorture') or stem.startswith('c_super_'):
        return 'superfly'
    if stem == 'm_kage' or stem == 'c_kage' or stem.startswith('c_kage_'):
        return 'mishima'
    if stem.startswith(('c_usagi_', 'c_gusagi_')):
        return 'usagi'
    return None


def read_md3(data):
    h = md3.HEADER.unpack_from(data)
    if h[0] != md3.IDENT or h[1] != md3.VERSION or h[-1] != len(data):
        raise ValueError('invalid source MD3')
    surfaces, offset = [], h[-2]
    for _ in range(h[6]):
        s = md3.SURFACE.unpack_from(data, offset)
        name = s[1].split(b'\0')[0].decode('ascii')
        material = md3.SHADER.unpack_from(data, offset+s[-4])[0].split(b'\0')[0].decode('ascii')
        packed = np.frombuffer(data, '<i2', count=s[3]*s[5]*4, offset=offset+s[-2]).reshape(s[3], s[5], 4)
        points = packed[..., :3].astype(float) / 64
        codes = packed[..., 3].astype(np.uint16)
        lat, lng = (codes >> 8) * (2*np.pi/256), (codes & 255) * (2*np.pi/256)
        normals = np.stack((np.cos(lat)*np.sin(lng), np.sin(lat)*np.sin(lng), np.cos(lng)), axis=-1)
        uv = np.frombuffer(data, '<f4', count=s[5]*2, offset=offset+s[-3]).reshape(-1, 2).copy()
        tri = np.frombuffer(data, '<u4', count=s[6]*3, offset=offset+s[-5]).reshape(-1, 3).copy()
        surfaces.append(dict(name=name, material=material, points=points, normals=normals, uv=uv, tri=tri))
        offset += s[-1]
    tags = {}
    for f in range(h[4]):
        for j in range(h[5]):
            row = md3.TAG.unpack_from(data, h[-3] + (f*h[5]+j)*md3.TAG.size)
            name = row[0].split(b'\0')[0].decode('ascii')
            tags.setdefault(name, []).append(row[1:4])
    return surfaces, {k: np.array(v) for k, v in tags.items()}


def clip_name(name):
    name = name.lower()
    if 'die' in name or 'death' in name: return 'BOTH_DEATH1'
    if 'dead' in name: return 'BOTH_DEAD1'
    if 'swim' in name: return 'LEGS_SWIM'
    if 'jump' in name or 'air' in name: return 'LEGS_JUMP'
    if 'land' in name: return 'LEGS_LAND'
    if 'run' in name: return 'LEGS_RUN'
    if 'walk' in name: return 'LEGS_WALKCR' if name.startswith('c') else 'LEGS_WALK'
    if 'back' in name: return 'LEGS_BACK'
    if 'atak' in name or 'attack' in name: return 'TORSO_ATTACK2' if name.endswith('b') else 'TORSO_ATTACK'
    if 'pain' in name or 'hit' in name: return 'TORSO_ATTACK'
    if name.startswith('camb'): return 'LEGS_IDLECR'
    return 'LEGS_IDLE'


def gameplay(model, metadata, clips, tags=None):
    original = model.frames
    idle = clips['LEGS_IDLE']
    frames = np.repeat(original[idle['first']:idle['first']+1], len(metadata['frames']), axis=0)
    mapping, appended = [], []
    for seq in metadata['sequences']['frame_data']:
        name = clip_name(seq['animation_name'])
        grip = 'RIFLE' if seq['animation_name'].endswith('b') else 'PISTOL' if seq['animation_name'].endswith('a') else 'GLOVE'
        if 'atak' in seq['animation_name'] and f'TORSO_ATTACK_{grip}' in clips:
            name = f'TORSO_ATTACK_{grip}'
        clip = clips[name]
        posed = original[clip['first']:clip['first']+clip['count']].copy()
        if name.startswith('LEGS_') and name != 'LEGS_SWIM':
            ready = clips.get(f'TORSO_STAND_{grip}', clips['TORSO_STAND'])
            for joint, joint_name in enumerate(model.names):
                if joint_name.startswith(('clavicle_', 'upperarm_', 'forearm_', 'hand_', 'fingers_', 'thumb_')) or joint_name == 'tag_weapon':
                    posed[:, joint] = original[ready['first'], joint]
        count = seq['last'] - seq['first'] + 1
        indices = np.linspace(0, len(posed)-1, count)
        lo, hi = np.floor(indices).astype(int), np.ceil(indices).astype(int)
        fraction = (indices-lo)[:, None, None]
        frames[seq['first']:seq['last']+1] = posed[lo]*(1-fraction) + posed[hi]*fraction
        first = len(frames)+sum(len(a) for a in appended)
        appended.append(posed)
        mapping.append(dict(sequence=seq['animation_name'], clip=name, first=seq['first'], last=seq['last'],
                            playback_first=first, playback_last=first+len(posed)-1,
                            rate=clip['fps'] if clip.get('loop') else 0))
        # Precompose upper-body attacks with each locomotion phase. IQM keeps
        # skeletal interpolation and weapon tags on exactly the same pose;
        # firing no longer replaces moving legs with a stationary full body.
        attack = clips.get(f'TORSO_ATTACK_{grip}')
        if name.startswith('LEGS_') and attack:
            upper = [j for j, n in enumerate(model.names)
                     if n.startswith(('clavicle_', 'upperarm_', 'forearm_', 'hand_', 'fingers_', 'thumb_')) or n == 'tag_weapon']
            grid = np.tile(posed, (attack['count'], 1, 1))
            for phase in range(attack['count']):
                grid[phase*len(posed):(phase+1)*len(posed), upper] = original[attack['first']+phase, upper]
            mapping[-1].update(attack_first=first+len(posed), attack_count=attack['count'])
            appended.append(grid)
    model.frames = np.concatenate([frames, *appended])
    # Gameplay weapons use the rig's grip, with legacy hardpoint names retained.
    add_joint(model, 'hp_gun', model.names.index('tag_weapon'), np.zeros((len(model.frames), 3)))
    add_joint(model, 'ctf_flag', model.names.index('chest'), np.tile([-8, 0, 0], (len(model.frames), 1)))
    for name in tags or {}:
        if name in model.names: continue
        parent = 'hand_l' if name == 'sword1' else 'hand_r' if name == 'sword2' else 'head'
        position = [4, 2 if name == 'eye1' else -2, 0] if name.startswith('eye') else [0, 0, 0]
        add_joint(model, name, model.names.index(parent), np.tile(position, (len(model.frames), 1)))
    return mapping


def add_joint(model, name, parent, positions):
    if name in model.names:
        return model.names.index(name)
    index = len(model.names)
    pose = np.tile([0, 0, 0, 0, 0, 0, 1, 1, 1, 1], (len(model.frames), 1)).astype(float)
    pose[:, :3] = positions
    model.names.append(name)
    model.parents.append(parent)
    model.bind = np.concatenate((model.bind, pose[:1]), axis=0)
    model.frames = np.concatenate((model.frames, pose[:, None]), axis=1)
    return index


def rigid_fit(rest, posed, weights):
    """Weighted least-squares rigid motion; batched over authored frames."""
    weights = weights / weights.sum()
    a = np.einsum('v,vi->i', weights, rest)
    b = np.einsum('v,fvi->fi', weights, posed)
    covariance = np.einsum('vi,fvj,v->fij', rest-a, posed-b[:, None], weights)
    u, _, vt = np.linalg.svd(covariance)
    reflection = np.linalg.det(vt.transpose(0, 2, 1) @ u.transpose(0, 2, 1))
    vt[:, -1] *= reflection[:, None]
    rotation = vt.transpose(0, 2, 1) @ u.transpose(0, 2, 1)
    result = np.tile(np.eye(4), (len(posed), 1, 1))
    result[:, :3, :3] = rotation
    result[:, :3, 3] = b - np.einsum('fij,j->fi', rotation, a)
    return result


def align_vectors(a, b):
    """Shortest rotation between vectors, including straight/antipodal limbs."""
    a = a / np.maximum(np.linalg.norm(a, axis=-1, keepdims=True), 1e-9)
    b = b / np.maximum(np.linalg.norm(b, axis=-1, keepdims=True), 1e-9)
    axis = np.cross(a, b)
    cosine = np.clip((a*b).sum(axis=-1), -1, 1)
    q = np.column_stack((axis, 1+cosine))
    opposite = cosine < -.99999
    if opposite.any():
        fallback = np.eye(3)[np.argmin(np.abs(a[opposite]), axis=1)]
        q[opposite, :3] = np.cross(a[opposite], fallback)
        q[opposite, 3] = 0
    poses = np.tile([0., 0, 0, 0, 0, 0, 1, 1, 1, 1], (len(a), 1, 1))
    poses[:, 0, 3:7] = q
    return sk.matrices(poses, [-1])[:, 0, :3, :3]


def limited_rotation(parent, desired, degrees):
    """Bound a joint's relative rotation without Euler wrapping or axis flips."""
    relative = np.tile(np.eye(4), (len(parent), 1, 1, 1))
    relative[:, 0, :3, :3] = parent.transpose(0, 2, 1) @ desired
    channels = sk.channels(relative, [-1])
    q = channels[:, 0, 3:7]
    q *= np.where(q[:, 3:4] < 0, -1, 1)
    length = np.linalg.norm(q[:, :3], axis=1)
    angle = np.minimum(2*np.arctan2(length, q[:, 3]), np.deg2rad(degrees))
    q[:, :3] *= (np.sin(angle/2)/np.maximum(length, 1e-9))[:, None]
    q[:, 3] = np.cos(angle/2)
    return parent @ sk.matrices(channels, [-1])[:, 0, :3, :3]


def connected_motion(model, fitted):
    """Fixed lengths and anatomical leg constraints for generated/retargeted motion."""
    chains = {}
    for side in ('l', 'r'):
        for names in ((f'upperarm_{side}', f'forearm_{side}', f'hand_{side}'),
                      (f'thigh_{side}', f'shin_{side}', f'foot_{side}')):
            if all(n in model.names for n in names):
                a, b, c = (model.names.index(n) for n in names)
                chains[a] = b, c
    result, pending = fitted.copy(), {}
    for j, parent in enumerate(model.parents):
        if parent >= 0:
            result[:, j, :3, 3] = np.einsum('fij,j->fi', result[:, parent, :3, :3], model.bind[j, :3]) + result[:, parent, :3, 3]
        if j in pending: result[:, j, :3, :3] = pending[j]
        if model.names[j].startswith('foot_'):
            result[:, j, :3, :3] = limited_rotation(result[:, parent, :3, :3], fitted[:, j, :3, :3], 70)
        elif model.names[j].startswith('toe_'):
            result[:, j, :3, :3] = limited_rotation(result[:, parent, :3, :3], fitted[:, j, :3, :3], 35)
        if j not in chains: continue
        middle, end = chains[j]
        origin = result[:, j, :3, 3]
        target = fitted[:, end, :3, 3] - origin
        length = np.linalg.norm(target, axis=1)
        direction = target / np.maximum(length[:, None], 1e-8)
        l1, l2 = np.linalg.norm(model.bind[middle, :3]), np.linalg.norm(model.bind[end, :3])
        leg = model.names[j].startswith('thigh_')
        # Knees bend forward between 3 and 145 degrees, never backwards or
        # fully folded. Keep the bending plane attached to the pelvis rather
        # than unconstrained least-squares rotations of a tiny knee surface.
        distance = np.clip(length,
                           np.sqrt(l1*l1+l2*l2+2*l1*l2*np.cos(np.deg2rad(145))) if leg else abs(l1-l2)+1e-5,
                           np.sqrt(l1*l1+l2*l2+2*l1*l2*np.cos(np.deg2rad(3))) if leg else l1+l2-1e-5)
        pole = fitted[:, middle, :3, 3] - origin
        if leg:
            hip = result[:, parent, :3, :3]
            local = np.einsum('fji,fj->fi', hip, direction)
            sign = 1 if model.names[j].endswith('_l') else -1
            pitch = np.clip(np.arctan2(local[:, 0], -local[:, 2]), np.deg2rad(-50), np.deg2rad(110))
            spread = np.clip(np.arcsin(np.clip(local[:, 1]*sign, -1, 1)), np.deg2rad(-12), np.deg2rad(55))
            local = np.column_stack((np.sin(pitch)*np.cos(spread), sign*np.sin(spread), -np.cos(pitch)*np.cos(spread)))
            direction = np.einsum('fij,fj->fi', hip, local)
            pole = hip[:, :, 0].copy()
        pole -= direction * (pole*direction).sum(axis=1, keepdims=True)
        weak = np.linalg.norm(pole, axis=1) < 1e-6
        if weak.any():
            axis = np.eye(3)[np.argmin(np.abs(direction[weak]), axis=1)]
            pole[weak] = np.cross(direction[weak], axis)
        pole /= np.maximum(np.linalg.norm(pole, axis=1, keepdims=True), 1e-8)
        along = (l1*l1-l2*l2+distance*distance)/(2*distance)
        height = np.sqrt(np.maximum(0, l1*l1-along*along))
        elbow = direction*along[:, None] + pole*height[:, None]
        wrist = direction*distance[:, None] - elbow
        for bone, child, goal in ((j, middle, elbow), (middle, end, wrist)):
            # Legs use the pelvis frame and solved thigh frame for roll; a
            # fitted shin rotation must never twist the hinge independently.
            rotation = (result[:, parent, :3, :3] if bone == j else result[:, j, :3, :3]) if leg else fitted[:, bone, :3, :3]
            vector = np.einsum('fij,j->fi', rotation, model.bind[child, :3])
            posed = align_vectors(vector, goal) @ rotation
            if bone == j: result[:, bone, :3, :3] = posed
            else: pending[bone] = posed
    return sk.channels(result, model.parents)


def split_hidden_props(surfaces):
    """Extract small collapsing props even when they share the body's material."""
    result = []
    for surface in surfaces:
        points = surface['points']
        signature = np.concatenate([points[f] for f in (0, len(points)//2, len(points)-1)], axis=1)
        _, welded = np.unique(signature, axis=0, return_inverse=True)
        parents = list(range(int(welded.max())+1))
        def root(i):
            while parents[i] != i: i = parents[i]
            return i
        for tri in welded[surface['tri']]:
            for index in tri[1:]: parents[root(index)] = root(tri[0])
        groups = {}
        for index, tri in enumerate(welded[surface['tri']]):
            groups.setdefault(root(tri[0]), []).append(index)
        hidden, retained = [], []
        for triangles in groups.values():
            vertices = np.unique(surface['tri'][triangles])
            extent = np.ptp(points[:, vertices], axis=1).max(axis=1)
            if len(triangles) < 64 and extent.min() < .1 and extent.max() > 1:
                hidden.append(triangles)
            else: retained += triangles
        if not hidden:
            result.append(surface)
            continue
        for index, triangles in enumerate([retained]+hidden):
            if not triangles: continue
            vertices, remap = np.unique(surface['tri'][triangles], return_inverse=True)
            result.append(dict(name=surface['name']+f'_part{index}', material=surface['material'],
                               points=points[:, vertices], normals=surface['normals'][:, vertices],
                               uv=surface['uv'][vertices], tri=remap.reshape(-1, 3), prop=index > 0))
    return result


def carried_anchors(surfaces):
    """Reference landmarks for the authored, face-down over-shoulder pose.

    The named head/torso/leg surfaces supply local measurements. An upright
    silhouette cannot calibrate this pose: the bent legs and hanging head make
    its vertical extent shorter than its actual body length.
    """
    bounds = {}
    for name in ('s_head', 's_torso', 's_legs'):
        points = np.concatenate([s['points'][0] for s in surfaces if s['name'] == name])
        bounds[name] = points.min(axis=0), np.ptp(points, axis=0)
    head, torso, legs = (bounds[n] for n in ('s_head', 's_torso', 's_legs'))
    center = head[0][1] + head[1][1]*.5
    def point(box, x, z, side=0, width=0):
        lo, extent = box
        return np.array([lo[0]+extent[0]*x, center+side*width, lo[2]+extent[2]*z])
    anchors = dict(pelvis=point(legs, .16, .92), spine=point(torso, .88, .88),
                   chest=point(torso, .60, .82), neck=point(head, .91, .92),
                   head=point(head, .50, .82))
    for suffix, side in (('l', -1), ('r', 1)):
        width = legs[1][1]*.25
        anchors.update({f'thigh_{suffix}': point(legs, .16, .87, side, width),
                        f'shin_{suffix}': point(legs, .40, .45, side, width),
                        f'foot_{suffix}': point(legs, .88, .17, side, width),
                        f'toe_{suffix}': point(legs, .91, .04, side, width),
                        f'upperarm_{suffix}': point(torso, .60, .77, side, torso[1][1]*.30),
                        f'forearm_{suffix}': point(torso, .23, .43, side, torso[1][1]*.32),
                        f'hand_{suffix}': point(torso, .15, .08, side, torso[1][1]*.32)})
    return anchors


def carried_reference(model, bind, anchors):
    """Orient the measured reference skeleton face down, with bent limbs."""
    result = bind.copy()
    up = anchors['chest']-anchors['pelvis']
    up /= np.linalg.norm(up)
    forward = np.array([0., 0, -1.])
    forward -= up*(up@forward)
    forward /= np.linalg.norm(forward)
    orientation = np.column_stack((forward, np.cross(up, forward), up))
    for j, name in enumerate(model.names):
        if name not in anchors:
            parent = model.parents[j]
            result[j] = result[parent] @ np.linalg.inv(bind[parent]) @ bind[j]
            continue
        result[j, :3, 3] = anchors[name]
        children = [c for c, p in enumerate(model.parents) if p == j and model.names[c] in anchors]
        parent = model.parents[j]
        other = children[0] if children else parent
        a = bind[other, :3, 3]-bind[j, :3, 3]
        b = anchors[model.names[other]]-anchors[name]
        result[j, :3, :3] = align_vectors((orientation@a)[None], b[None])[0] @ orientation @ bind[j, :3, :3]
    return result


def cinematic(model, surfaces, tags, *, carried=False, calibrate=True):
    surfaces = split_hidden_props(surfaces)
    visible = [s for s in surfaces if s['material'] != dkm2md3.NODRAW_SHADER]
    props = [s for s in visible if s.get('prop') or any(word in s['material'] for word in ('daikatana', 'purifier', 'w_', 'sword'))]
    body = [s for s in visible if not any(s is p for p in props)]
    if not body: raise ValueError('cinematic has no character body')
    source = np.concatenate([s['points'] for s in body], axis=1)
    # UV seams duplicate vertices; remove duplicates consistently on all frames.
    _, unique = np.unique(source[0], axis=0, return_index=True)
    source = source[:, unique]
    target = model.arrays[0].astype(float)
    # Choose the most upright, neutral available pose. Actual frame ordering,
    # including one-frame holds and authored root motion, is retained below.
    height = np.ptp(source[..., 2], axis=1)
    # A raised hand must not become the top of the character's calibration
    # box. Use typical height, then prefer the closest neutral body silhouette.
    typical_height = np.median(height)
    candidates = np.flatnonzero((height >= typical_height * .92) & (height <= typical_height * 1.08))
    if not len(candidates): candidates = np.arange(len(source))
    # A carried body or a one-frame corpse may have no upright reference pose.
    # Align the bind body's long axis before fitting its local bone motion.
    extent = np.ptp(source, axis=1)
    longest = int(np.argmax(extent[np.argmax(height)]))
    rotation = np.eye(3)
    if not carried and longest != 2 and height.max() < extent[:, longest].max() * .7:
        rotation = np.array([[0., 0, 1], [0, 1, 0], [-1, 0, 0]]) if longest == 0 else np.array([[1., 0, 0], [0, 0, 1], [0, -1, 0]])
    target = target @ rotation.T
    target_extent = np.ptp(target, axis=0)
    best = None
    anchors = carried_anchors(body) if carried else None
    if carried:
        bind = sk.matrices(model.bind, model.parents)
        # Keep the same normalized body size used in gameplay. Bent source
        # legs have different proportions and cannot define whole-body scale.
        scale = 1.
        offset = anchors['pelvis']-bind[model.names.index('pelvis'), :3, 3]*scale
        best = 0, 0, scale, offset
    for f in ([] if carried else candidates[::max(1, len(candidates)//100)]):
        scale = extent[f, longest] / target_extent[longest] if calibrate else 1.
        offset = (source[f].min(axis=0)+source[f].max(axis=0))/2 - (target.min(axis=0)+target.max(axis=0))*scale/2
        fitted = target * scale + offset
        # Symmetric cloud distance prevents a bent arm from winning by density.
        dist = ((source[f, :, None] - fitted[None, ::8])**2).sum(axis=-1)
        score = np.mean(np.min(dist, axis=0)) + np.mean(np.min(dist, axis=1))
        if best is None or score < best[0]: best = score, int(f), scale, offset
    _, reference, scale, offset = best
    model.arrays[0] = target*scale + offset
    model.arrays[2] = model.arrays[2] @ rotation.T
    bind_absolute = sk.matrices(model.bind, model.parents)
    bind_absolute[:, :3, :3] = rotation @ bind_absolute[:, :3, :3]
    bind_absolute[:, :3, 3] = (bind_absolute[:, :3, 3] @ rotation.T)*scale + offset
    model.bind = sk.channels(bind_absolute, model.parents)
    target = model.arrays[0]
    rest = source[reference]
    # Fit one rigid transform per anatomical source region.
    bind = sk.matrices(model.bind, model.parents)
    # The source actor generally rests with hands beside its hips; the neural
    # rig rests with bent elbows and spread arms. Fit source motion on its own
    # anatomical segments instead of assigning a source elbow to a neural hand
    # merely because their reference positions happen to be close.
    source_bind = bind.copy()
    canonical = rest @ rotation
    anchors = bind[:, :3, 3] @ rotation
    lo, hi = canonical.min(axis=0), canonical.max(axis=0)
    center = (lo+hi)/2
    body_height = hi[2]-lo[2]
    spread = np.ptp(target @ rotation, axis=0)[1]
    anchors[:, 1] = center[1] + (anchors[:, 1]-center[1]) * (hi[1]-lo[1])/spread
    for j, name in enumerate(model.names):
        if name.startswith('hand_'): anchors[j, 2] = lo[2]+body_height*.44
        elif name.startswith('forearm_'): anchors[j, 2] = lo[2]+body_height*.62
    source_bind[:, :3, 3] = anchors @ rotation.T
    if carried:
        source_bind = carried_reference(model, bind, carried_anchors(body))
    else:
        for j, name in enumerate(model.names):
            if name.startswith(('fingers_', 'thumb_')):
                parent = model.parents[j]
                source_bind[j, :3, 3] += source_bind[parent, :3, 3]-bind[parent, :3, 3]
    weights = np.zeros((len(rest), len(model.names)))
    for j, name in enumerate(model.names):
        if name.startswith(('tag_', 'fingers_', 'thumb_', 'cloth_')): continue
        children = [c for c, parent in enumerate(model.parents) if parent == j and not model.names[c].startswith('tag_')]
        start = source_bind[j, :3, 3]
        if children:
            # Torso branches use their central child; arms/legs have one child.
            end = source_bind[children[0], :3, 3]
        else:
            parent = model.parents[j]
            direction = start-source_bind[parent, :3, 3] if parent >= 0 else rotation[:, 2]
            end = start + direction/ max(np.linalg.norm(direction), 1e-8)*body_height*.06
        delta = end-start
        t = np.clip((rest-start) @ delta / max(float(delta@delta), 1e-8), 0, 1)
        distance = ((rest-(start+t[:, None]*delta))**2).sum(axis=1)
        weights[:, j] = 1/(distance+1)**2
    weights /= weights.sum(axis=1, keepdims=True)
    absolute = np.tile(bind, (len(source), 1, 1, 1))
    residual = []
    for j in range(len(model.names)):
        w = weights[:, j]
        if np.count_nonzero(w > .01) < 4:
            parent = model.parents[j]
            if parent >= 0:
                absolute[:, j] = absolute[:, parent] @ np.linalg.inv(bind[parent]) @ bind[j]
            continue
        transform = rigid_fit(rest, source, w)
        absolute[:, j] = transform @ source_bind[j]
        predicted = np.einsum('fij,vj->fvi', transform[:, :3, :3], rest) + transform[:, None, :3, 3]
        residual.append(float(np.sqrt(np.mean(np.einsum('fv,v->f', ((predicted-source)**2).sum(axis=-1), w/w.sum())))))
    model.frames = connected_motion(model, absolute)
    # Preserve authored ground/root height after fitting different proportions.
    # Include spatial extremes and evenly distributed vertices for a bounded
    # skinning sample, independent of mesh detail or UV seam duplication.
    samples = set(range(0, len(target), max(1, len(target)//1000)))
    for joint in range(len(model.names)):
        vertices = np.flatnonzero(((model.arrays[4] == joint) & (model.arrays[5] > 0)).any(axis=1))
        if len(vertices):
            samples.update(vertices[np.argmin(target[vertices], axis=0)])
            samples.update(vertices[np.argmax(target[vertices], axis=0)])
    sample = copy.copy(model)
    sample.arrays = {k: v[sorted(samples)] for k, v in model.arrays.items()}
    # A carried actor is anchored on the carrier's shoulder, not on the floor.
    for start in ([] if carried else range(0, len(source), 128)):
        end = start+128
        posed = sk.skin(sample, model.frames[start:end])
        height_offset = source[start:end, :, 2].min(axis=1) - posed[..., 2].min(axis=1)
        for joint, parent in enumerate(model.parents):
            if parent < 0: model.frames[start:end, joint, 2] += height_offset
    for name, positions in tags.items(): add_joint(model, name, -1, positions)
    attach_props(model, props, absolute)
    return dict(reference_frame=reference, scale=float(scale), fit_rms_mean=float(np.mean(residual)),
                fit_rms_max=float(max(residual)), props=[s['name'] for s in props])


def combined(sources, surfaces, tags):
    models, details = [], []
    for name, material in (('mikiko', 'miko_'), ('superfly', 'sfly_')):
        model = copy.deepcopy(sources[name][0])
        body = [s for s in surfaces if material in s['material']]
        details.append(cinematic(model, body, {}, carried=name == 'mikiko', calibrate=False))
        model.names = [name+'_'+n for n in model.names]
        model.meshes = [(name+'_'+n, m, *r) for n, m, *r in model.meshes]
        models.append(model)
    first, second = models
    joints, vertices, triangles = len(first.names), len(first.arrays[0]), len(first.triangles)
    second.arrays[4] = second.arrays[4].astype(int) + joints
    for kind in first.arrays: first.arrays[kind] = np.concatenate((first.arrays[kind], second.arrays[kind]))
    first.triangles = np.concatenate((first.triangles, second.triangles+vertices))
    first.meshes += [(n, m, fv+vertices, nv, ft+triangles, nt) for n,m,fv,nv,ft,nt in second.meshes]
    first.names += second.names
    first.parents += [p+joints if p >= 0 else -1 for p in second.parents]
    first.bind = np.concatenate((first.bind, second.bind))
    first.frames = np.concatenate((first.frames, second.frames), axis=1)
    for name, positions in tags.items(): add_joint(first, name, -1, positions)
    return first, dict(characters=details)


def attach_props(model, props, source_pose):
    """Keep authored held props rigidly in a real hand, including split swords.

    Original free motion is retained when a prop leaves both hands. Geometry
    that shares one source surface shares one grip at a jointly visible pose.
    """
    groups = {}
    for prop in props:
        key = prop['name'].rsplit('_part', 1)[0]
        groups.setdefault(key, []).append(prop)
    hands = [model.names.index(n) for n in ('hand_l', 'hand_r') if n in model.names]
    for group in groups.values():
        points = np.concatenate([p['points'] for p in group], axis=1)
        visibility = [np.ptp(p['points'], axis=1).max(axis=1) >= .1 for p in group]
        visible = np.logical_or.reduce(visibility)
        together = np.logical_and.reduce(visibility)
        if len(group) > 1 and not together.any():
            # Separately appearing objects share no pose in which their
            # geometry can be assembled. Give each its own reference grip.
            for prop in group: attach_props(model, [prop], source_pose)
            continue
        if not visible.any() or not hands:
            for prop in group: append_prop(model, prop)
            continue
        point_visible = np.concatenate([np.repeat(v[:, None], len(p['uv']), axis=1) for p, v in zip(group, visibility)], axis=1)
        distances = np.array([np.where(point_visible, np.linalg.norm(points-source_pose[:, None, hand, :3, 3], axis=-1), np.inf).min(axis=1) for hand in hands])
        references = distances.copy()
        references[:, ~together] = np.inf
        hand_number, reference = np.unravel_index(np.argmin(references), references.shape)
        hand = hands[hand_number]
        if distances[hand_number, reference] > 12:
            for prop in group: append_prop(model, prop)
            continue
        wrist = source_pose[reference, hand, :3, 3]
        nearest = np.argsort(np.linalg.norm(points[reference]-wrist, axis=1))[:min(8, points.shape[1])]
        grip = points[reference, nearest].mean(axis=0)
        actual = sk.matrices(model.frames, model.parents)[:, hand]
        relative = np.linalg.inv(actual[reference])
        relative[:3, 3] = np.array([1.5, 0, -1.8])-relative[:3, :3]@grip
        held = visible & (distances[hand_number] < 20)
        for prop in group: append_prop(model, prop, attachment=(hand, relative, held, actual), reference=int(reference))
        suffix = model.names[hand][-1]
        for name, axis, angle in ((f'fingers_{suffix}', 1, -1.2), (f'thumb_{suffix}', 0, .7 if suffix == 'l' else -.7)):
            if name in model.names:
                q = np.zeros(4)
                q[axis], q[3] = np.sin(angle/2), np.cos(angle/2)
                model.frames[held, model.names.index(name), 3:7] = q


def append_prop(model, prop, attachment=None, reference=None):
    # Authors hide weapons by collapsing their vertices. Choose a visible
    # reference independently of the body, then retain those hidden frames as
    # zero bone scale; rigid fitting alone would leave the weapon visible.
    extent = np.ptp(prop['points'], axis=1).max(axis=1)
    if extent.max() < .1:
        return
    reference = int(np.argmax(extent)) if reference is None else reference
    parent = attachment[0] if attachment else -1
    index = add_joint(model, 'prop_' + str(len(model.names)), parent, np.zeros((len(model.frames), 3)))
    transform = rigid_fit(prop['points'][reference], prop['points'], np.ones(prop['points'].shape[1]))
    if attachment:
        _, relative, held, actual = attachment
        transform = np.linalg.inv(actual) @ transform
        transform[held] = relative
    model.frames[:, index] = sk.channels(transform[:, None], [-1])[:, 0]
    hidden = extent < .1
    model.frames[hidden, index, 7:10] = 0
    if not attachment: model.frames[hidden, index, :3] = prop['points'][hidden].mean(axis=1)
    model.bind[index] = sk.channels(np.linalg.inv(sk.matrices(model.bind, model.parents)[parent])[None], [-1])[0] if attachment else [0, 0, 0, 0, 0, 0, 1, 1, 1, 1]
    fv, ft, nv = len(model.arrays[0]), len(model.triangles), len(prop['uv'])
    arrays = {0: prop['points'][reference], 1: prop['uv'], 2: prop['normals'][reference],
              4: np.tile([index, 0, 0, 0], (nv, 1)), 5: np.tile([255, 0, 0, 0], (nv, 1))}
    for kind, array in arrays.items(): model.arrays[kind] = np.concatenate((model.arrays[kind], array))
    model.triangles = np.concatenate((model.triangles, prop['tri'] + fv))
    model.meshes.append(('prop_' + str(index), prop['material'], fv, nv, ft, len(prop['tri'])))


def texture_files(name, texture):
    material = f'models/neural/{name}'
    raw = texture.read_bytes()
    files = {material+'/body.png': raw, material+'/color0.png': raw}
    rgba = dkimg.read_png(texture)
    protection_path = texture.with_suffix('.face-mask.png')
    protection = dkimg.read_png(protection_path)[..., :1] if protection_path.exists() else None
    if protection is not None and protection.shape[:2] != rgba.shape[:2]:
        raise ValueError('Face tint protection must match the atlas dimensions')
    # Retain full detail for the default body; bound team texture residency.
    step = max(1, max(rgba.shape[:2]) // 2048)
    if step > 1:
        h, w, channels = rgba.shape
        rgba = rgba.reshape(h//step, step, w//step, step, channels).mean(axis=(1, 3)).astype(np.uint8)
        if protection is not None:
            protection = protection.reshape(h//step, step, w//step, step, 1).mean(axis=(1, 3))
    rgb = rgba[..., :3].astype(np.float32)/255
    amount = (1-np.clip((rgb.max(axis=-1)-rgb.min(axis=-1))*3, 0, 1))[..., None]*.8
    if protection is not None: amount *= 1-protection/255
    for color, tint in enumerate(COLORS[1:], 1):
        colored = rgba.copy()
        colored[..., :3] = np.clip(rgb*((1-amount)+amount*np.array(tint))*255, 0, 255).astype(np.uint8)
        files[f'{material}/color{color}.png'] = dkimg.encode_png(colored)
    return files


def build(source, assets, output, meshes=None):
    root = (assets / 'current').resolve() if (assets / 'current').exists() else assets.resolve()
    base = root / 'packages/dk3-models.pk3'
    sources, files, report, lines, shader = {}, {}, [], [], []
    provenance = {}
    for name in CHARACTERS:
        directory = source / 'out' / name
        iqm_file = meshes / f'{name}.iqm' if meshes else directory / f'models/players/{name}/{name}.iqm'
        manifest_path = meshes/f'{name}.clips.json' if meshes and (meshes/f'{name}.clips.json').exists() else directory/'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        model = sk.read(iqm_file.read_bytes())
        material = f'models/neural/{name}/body'
        model.meshes = [(n, material, *rest) for n, _, *rest in model.meshes]
        sources[name] = model, {c['name']: c for c in manifest['animations']}
        texture = meshes / f'{name}.png' if meshes else directory / f'models/players/{name}/{name}.png'
        provenance[name] = dict(iqm_sha256=hashlib.sha256(iqm_file.read_bytes()).hexdigest(),
                                texture_sha256=hashlib.sha256(texture.read_bytes()).hexdigest())
        if meshes: provenance[name]['mesh'] = json.loads((meshes / f'{name}.json').read_text())
        files.update(texture_files(name, texture))
        face_report = texture.with_suffix('.face.json')
        if face_report.exists(): provenance[name]['face_repair'] = json.loads(face_report.read_text())
        shader.append(dkm2md3.variant_stanzas(material, material+'.png', False))
        print(f'neural: prepared {name} mesh/materials', flush=True)
    with zipfile.ZipFile(base) as archive:
        for entry in sorted(archive.namelist()):
            if not entry.endswith('.dkm.json'): continue
            metadata = json.loads(archive.read(entry))
            name, path = character(metadata['model']), metadata['model']
            if name is None: continue
            surfaces, tags = read_md3(archive.read(path+'.md3'))
            cinematic_model = '/cinematic/' in path or '/characters/' in path or '/d1_' in path or '/d2_' in path or name == 'mikikofly'
            if name == 'mikikofly':
                model, detail = combined(sources, surfaces, tags)
            else:
                model, clips = sources[name]
                model = copy.deepcopy(model)
                detail = cinematic(model, surfaces, tags) if cinematic_model else gameplay(model, metadata, clips, tags)
            key = Path(path).stem
            destination = f'models/neural/{key}.iqm'
            if destination in files: raise ValueError('duplicate neural model key')
            files[destination] = sk.write(model)
            lines.append(f'{path} {destination}')
            for variant, suffix in enumerate(dkm2md3.RENDER_VARIANTS):
                files[destination+f'.{variant}.skin'] = ''.join(f'{n},{m}{suffix}\n' for n, m, *_ in model.meshes).encode()
            if path in ('models/global/m_hiro.dkm', 'models/global/m_mikiko.dkm', 'models/global/m_superfly.dkm'):
                for color in range(12):
                    files[f'models/neural/{name}/{color}.skin'] = ''.join(f'{n},models/neural/{name}/color{color}\n' for n, *_ in model.meshes).encode()
            report.append(dict(source=path, character=name, target=destination, frames=len(model.frames),
                               joints=len(model.names), method='cinematic-fit' if cinematic_model else 'q3-clips', conversion=detail))
            print(f'neural: {path}: {len(model.frames)} skeletal frames', flush=True)
        # The two additional multiplayer appearances use Hiro/Mikiko gameplay
        # rules and timelines. Their model and material selection is cosmetic.
        for name, original in (('mishima', 'hiro'), ('usagi', 'mikiko')):
            model, clips = sources[name]
            model = copy.deepcopy(model)
            metadata = json.loads(archive.read(f'models/global/m_{original}.dkm.json'))
            gameplay(model, metadata, clips)
            destination = f'models/neural/player_{name}.iqm'
            files[destination] = sk.write(model)
            for color in range(12):
                files[f'models/neural/{name}/{color}.skin'] = ''.join(f'{n},models/neural/{name}/color{color}\n' for n, *_ in model.meshes).encode()
            lines.append(f'player/{name} {destination}')
    files[MANIFEST] = ('\n'.join(lines)+'\n').encode()
    files['dk3/neural-animations.cfg'] = ''.join(
        f'{row["source"]} {clip["first"]} {clip["last"]} {clip["playback_first"]} {clip["playback_last"]} {clip["rate"]} {clip.get("attack_first", 0)} {clip.get("attack_count", 0)}\n'
        for row in report if row['method'] == 'q3-clips' for clip in row['conversion']).encode()
    files['scripts/dk3-neural.shader'] = '\n'.join(shader).encode()
    document = dict(format=1, source_models_sha256=hashlib.sha256(base.read_bytes()).hexdigest(),
                    inputs=provenance, models=report, files={k:hashlib.sha256(v).hexdigest() for k,v in files.items()},
                    limitations=['Cinematic skeleton fitting approximates vertex poses; facial morphs are not retained.',
                                 'Procedural gameplay clips replace authored performances.',
                                 'Diffuse materials preserve the selected source; glTF metallic/roughness maps are not used by this material path.'])
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix('.partial')
    files['dk3/neural-assets.json'] = json.dumps(document, sort_keys=True, indent=2).encode()
    with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    validate_package(temporary, base)
    temporary.replace(output)
    output.with_suffix('.json').write_text(json.dumps(document, indent=2, sort_keys=True)+'\n')
    print(f'neural: published {len(report)} models: {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--assets', type=Path, default=Path('zig-out/assets'))
    parser.add_argument('--out', type=Path, default=Path('zig-out/neural-assets/dk3-neural.pk3'))
    parser.add_argument('--meshes', type=Path, help='detailed meshes rebuilt with neural_meshes.py and neural_rig.py')
    args = parser.parse_args()
    build(args.source, args.assets, args.out, args.meshes)
