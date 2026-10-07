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
from neural_package import MANIFEST, NON_CHARACTER_MODELS, validate_package

CHARACTERS = ('hiro', 'mikiko', 'superfly', 'mishima', 'usagi')
# Additional story identities are generated from this checkout's original models.
# The five historical identities remain the default for the older standalone tool.
STORY_CHARACTERS = {
    'casseti': ('c_casseti_e4m1',), 'charon': ('c_char_e2m1','c_char_e2m2','c_ferryman_e2m1'),
    'femaleguard': ('c_fmg_e4m3',),
    'garroth': ('c_ghar_e3m6','c_pghar_e3m6'), 'warriorguard': ('c_mwguard_e4m6',),
    'ninja': ('c_ninja_intr',), 'osaka': ('c_osaka_intr',),
    'priest': ('c_priest_e3m1','c_priest_e3m6'),
    'tatsuo': ('c_tatsuo_e4m4','c_tatsuo_end'), 'toshiro': ('c_tosh_intr',),
}
COLORS = ((1, 1, 1), (.25, .85, .35), (.2, .45, 1), (.8, .85, .9), (1, .45, .15),
          (.7, .25, .9), (1, .85, .15), (1, .18, .12), (.15, .25, .65), (1, .7, .15),
          (.55, .12, .2), (.45, .5, .2))

# Measured on the original kneeling model's side and frontal mesh views.
# A clip with no standing frame cannot infer standing body size from height.
# Pin the measurements to the entire original vertex animation below.
CINEMATIC_REFERENCES = {
    'models/cinematic/c_hiro_end.dkm': dict(
        points_sha256='819cd7c2bc23d4c94cdcac78885fb7cbbad16c42fe921b1ce1226fe7b7f60fc5', frame=0, scale=.85,
        landmarks=dict(pelvis=[-1,-5,-13], spine=[-1,-5,-9],
            chest=[-1,-5,-5], neck=[1,-5,-2], head=[2,-5,1],
            upperarm_l=[-1,1,-4], forearm_l=[0,3,-10], hand_l=[6,2,-15],
            upperarm_r=[-1,-11,-4], forearm_r=[0,-13,-10], hand_r=[6,-12,-15],
            thigh_l=[-1,-1,-14], shin_l=[9,-1,-22], foot_l=[-11,-1,-23], toe_l=[-15,-1,-23],
            thigh_r=[-1,-9,-14], shin_r=[9,-9,-22], foot_r=[-11,-9,-23], toe_r=[-15,-9,-23])),
    # The authored punch starts standing. Most frames are crouches/jumps;
    # their median height cannot define this actor's standing proportions.
    'models/cinematic/c_ninja_intr.dkm': dict(
        points_sha256='d63ee69496b0902297e10ea42e9f26e0db56af9e62c0650da16f658f9506edf0',
        frame=143,
        landmarks=dict(pelvis=[-2.5,.2,11], spine=[-2.3,.2,17],
            chest=[-1,.2,24], neck=[-1.5,0,29], head=[-1.2,0,35]),
        # Measured body vertices after whole-trajectory prop extraction and
        # first-frame deduplication. The sparse robe previously let a nearby
        # wrist dominate the spine fit and turn a running torso horizontal.
        joint_vertices=dict(pelvis=[17,19,21,25,26,27,32,33],
            spine=[41,58,59,67,75,76,79], chest=[41,58,59,67,75,76,79],
            neck=[90,91,95,96]))
}

# The original ferryman's pole and blade share welded edges with his hands.
# The source topology/UV receipt pins this reviewed triangle selection; body
# triangles 147..153 are deliberately excluded from the weapon surface.
CINEMATIC_PROP_TOPOLOGY = {
    'models/cinematic/'+stem+'.dkm': dict(
        sha256='5094fa1f6a72b9a8e5731414af74edea73c9ac66abcaa8ddb1b6932e33dd7792',
        ranges=((65,147),(154,156)))
    for stem in ('c_char_e2m1','c_char_e2m2','c_ferryman_e2m1')
}
# Two blades and two hilts remain visible throughout this original performance.
# Their short proportions cannot satisfy the generic long-staff detector.
CINEMATIC_PROP_TOPOLOGY['models/cinematic/c_fmg_e4m3.dkm'] = dict(
    sha256='076e2fc9af908ae4519e9ac9e85d0f93c79d0de4a0264208b97669518908fa78',
    groups=((133,134,137,140,141,142,143,144,145,146,147,148,149,150,151,152,153,154),
            (135,136,138,139,155,156,157,158,159,160,161,162,163,164,165,166,167,168)))


def source_props(surfaces, metadata):
    receipt=CINEMATIC_PROP_TOPOLOGY.get(metadata.get('model')) if metadata else None
    if not receipt:return surfaces
    if len(surfaces)!=1:raise ValueError('Reviewed source weapon topology changed')
    surface=surfaces[0]
    digest=hashlib.sha256(surface['tri'].astype('<u4').tobytes()+surface['uv'].astype('<f4').tobytes()).hexdigest()
    if digest!=receipt['sha256']:raise ValueError('Reviewed source weapon topology changed')
    groups=receipt.get('groups')
    if groups is None:groups=(tuple(i for first,last in receipt['ranges'] for i in range(first,last)),)
    masks=[]
    for group in groups:
        mask=np.zeros(len(surface['tri']),bool);mask[list(group)]=True;masks.append(mask)
    selected=np.logical_or.reduce(masks)
    result=[]
    for index,mask in enumerate([~selected]+masks):
        vertices,remap=np.unique(surface['tri'][mask],return_inverse=True)
        suffix='' if index==0 else '_weapon' if len(masks)==1 else f'_weapon_{index}'
        result.append(dict(name=surface['name']+suffix,material=surface['material'],
            points=surface['points'][:,vertices],normals=surface['normals'][:,vertices],
            uv=surface['uv'][vertices],tri=remap.reshape(-1,3),prop=index>0))
    return result


def character(path, story=False):
    if path in NON_CHARACTER_MODELS: return None
    stem = Path(path).stem
    if story:
        for name,stems in STORY_CHARACTERS.items():
            if stem in stems:return name
    if stem in ('m_mikikofly', 'c_mikikofly'): return 'mikikofly'
    if stem in ('m_hiro', 'm_hiro2', 'hiro') or stem.startswith(('c_hiro_', 'c_phiro_', 'c_inshiro_')):
        return 'hiro'
    if stem in ('m_mikiko', 'm_smikiko', 'mikiko', 'd1_mikdead') or stem.startswith(('c_mikiko_', 'c_smikiko_')):
        return 'mikiko'
    if stem in ('m_superfly', 'superfly', 'd2_superfly') or stem.startswith('c_super_'):
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


def gameplay(model, metadata, clips, tags=None, *, regenerate_motion=False):
    if regenerate_motion:
        # Animate the admitted geometry and bind rig; never rerig a repaired
        # head, change its weights or fall back to an earlier character mesh.
        from neural_rig import clips as author_clips
        clips = {c['name']: c for c in author_clips(model, sk.matrices(model.bind, model.parents))}
    original = model.frames
    idle = clips['LEGS_IDLE']
    frames = np.repeat(original[idle['first']:idle['first']+1], len(metadata['frames']), axis=0)
    mapping, appended, shared = [], [], {}
    appended_count = 0
    def append_pose_block(block):
        nonlocal appended_count
        # Several authored sequence names select the same locomotion/grip
        # block. Share exact serialized poses while retaining every authored
        # frame and each sequence's independent playback interval.
        key=(block.shape,block.dtype.str,hashlib.sha256(block.tobytes()).digest())
        if key not in shared:
            shared[key]=len(frames)+appended_count
            appended.append(block)
            appended_count+=len(block)
        return shared[key]
    for seq in metadata['sequences']['frame_data']:
        name = clip_name(seq['animation_name'])
        grip = 'RIFLE' if seq['animation_name'].endswith('b') else 'PISTOL' if seq['animation_name'].endswith('a') else 'GLOVE'
        if 'atak' in seq['animation_name'] and f'TORSO_ATTACK_{grip}' in clips:
            name = f'TORSO_ATTACK_{grip}'
        specific = f'{name}_{grip}'
        clip = clips.get(specific, clips[name])
        posed = original[clip['first']:clip['first']+clip['count']].copy()
        if name.startswith('LEGS_') and name != 'LEGS_SWIM' and specific not in clips:
            ready = clips.get(f'TORSO_STAND_{grip}', clips['TORSO_STAND'])
            for joint, joint_name in enumerate(model.names):
                if joint_name.startswith(('clavicle_', 'upperarm_', 'forearm_', 'hand_', 'fingers_', 'thumb_')) or joint_name == 'tag_weapon':
                    posed[:, joint] = original[ready['first'], joint]
        count = seq['last'] - seq['first'] + 1
        indices = np.linspace(0, len(posed)-1, count)
        lo, hi = np.floor(indices).astype(int), np.ceil(indices).astype(int)
        fraction = (indices-lo)[:, None, None]
        frames[seq['first']:seq['last']+1] = posed[lo]*(1-fraction) + posed[hi]*fraction
        first = append_pose_block(posed)
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
            mapping[-1].update(attack_first=append_pose_block(grid), attack_count=attack['count'])
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


def wrist_rotation(neutral, desired, axis, bend=35):
    """Limit wrist bend separately from forearm pronation and palm roll."""
    axis = axis / max(np.linalg.norm(axis), 1e-9)
    a, b = neutral @ axis, desired @ axis
    swing = align_vectors(a, b)
    # Roll around the palm's long axis must not turn a forward fist upside
    # down. Preserve modest authored gestures while rejecting fit inversions.
    rolled = limited_rotation(neutral, swing.transpose(0, 2, 1) @ desired, 80)
    limited = limited_rotation(np.tile(np.eye(3), (len(neutral), 1, 1)), swing, bend)
    return limited @ rolled


def connected_motion(model, fitted, temporal_poles=False, cyclic_poles=False,
                     preserve_observed_poles=False):
    """Fixed lengths and anatomical leg constraints for generated/retargeted motion."""
    chains = {}
    for side in ('l', 'r'):
        for names in ((f'upperarm_{side}', f'forearm_{side}', f'hand_{side}'),
                      (f'thigh_{side}', f'shin_{side}', f'foot_{side}')):
            if all(n in model.names for n in names):
                a, b, c = (model.names.index(n) for n in names)
                chains[a] = b, c
    result, pending = fitted.copy(), {}
    bind = sk.matrices(model.bind, model.parents)
    for j, parent in enumerate(model.parents):
        if parent >= 0:
            result[:, j, :3, 3] = np.einsum('fij,j->fi', result[:, parent, :3, :3], model.bind[j, :3]) + result[:, parent, :3, 3]
        if j in pending: result[:, j, :3, :3] = pending[j]
        if model.names[j].startswith('foot_'):
            result[:, j, :3, :3] = limited_rotation(result[:, parent, :3, :3], fitted[:, j, :3, :3], 70)
        elif model.names[j].startswith('toe_'):
            result[:, j, :3, :3] = limited_rotation(result[:, parent, :3, :3], fitted[:, j, :3, :3], 35)
        elif model.names[j].startswith('hand_'):
            fingers = 'fingers_' + model.names[j][-1]
            if fingers in model.names:
                neutral = result[:, parent, :3, :3] @ bind[parent, :3, :3].T @ bind[j, :3, :3]
                axis = model.bind[model.names.index(fingers), :3]
                result[:, j, :3, :3] = wrist_rotation(neutral, fitted[:, j, :3, :3], axis)
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
        # A measured bent elbow determines its own bending plane. Clamping
        # that plane to a generic rest-pose cone changes the performance even
        # when its endpoints and joint angles are anatomically valid.
        observable = np.linalg.norm(pole, axis=1) > l1 * .08
        if not leg and not preserve_observed_poles:
            sign = 1 if model.names[j].endswith('_l') else -1
            anatomical = result[:, parent, :3, :3] @ np.array([.25, sign*.7, -.6])
            anatomical -= direction * (anatomical*direction).sum(axis=1, keepdims=True)
            anatomical /= np.maximum(np.linalg.norm(anatomical, axis=1, keepdims=True), 1e-8)
            pole /= np.maximum(np.linalg.norm(pole, axis=1, keepdims=True), 1e-8)
            swing = align_vectors(anatomical, pole)
            pole = limited_rotation(np.tile(np.eye(3), (len(pole), 1, 1)), swing, 65) @ anatomical[..., None]
            pole = pole[..., 0]
        weak = np.linalg.norm(pole, axis=1) < 1e-6
        if weak.any():
            axis = np.eye(3)[np.argmin(np.abs(direction[weak]), axis=1)]
            pole[weak] = np.cross(direction[weak], axis)
        pole /= np.maximum(np.linalg.norm(pole, axis=1, keepdims=True), 1e-8)
        if temporal_poles and not leg:
            # The elbow plane is unobservable as the arm straightens. Carry
            # the previous plane along the new aim direction, then approach
            # the measured plane with a bounded angular change. Endpoints
            # and segment lengths still come from the same two-bone solve.
            measured=pole.copy();previous=pole[0].copy()
            for cycle in range(3 if cyclic_poles else 1):
                for frame in range(0 if cyclic_poles else 1,len(pole)):
                    if preserve_observed_poles and observable[frame]:
                        pole[frame]=measured[frame];previous=pole[frame];continue
                    prior=previous-direction[frame]*(previous@direction[frame])
                    if np.linalg.norm(prior)<1e-6:previous=measured[frame];continue
                    prior/=np.linalg.norm(prior)
                    swing=align_vectors(prior[None],measured[frame:frame+1])
                    bounded=limited_rotation(np.eye(3)[None],swing,8)[0]
                    pole[frame]=bounded@prior;previous=pole[frame]
        along = (l1*l1-l2*l2+distance*distance)/(2*distance)
        height = np.sqrt(np.maximum(0, l1*l1-along*along))
        elbow = direction*along[:, None] + pole*height[:, None]
        wrist = direction*distance[:, None] - elbow
        for bone, child, goal in ((j, middle, elbow), (middle, end, wrist)):
            # Legs use the pelvis frame and solved thigh frame for roll; a
            # fitted shin rotation must never twist the hinge independently.
            rotation = result[:, parent, :3, :3] if bone == j else result[:, j, :3, :3]
            vector = np.einsum('fij,j->fi', rotation, model.bind[child, :3])
            posed = align_vectors(vector, goal) @ rotation
            if bone == j: result[:, bone, :3, :3] = posed
            else: pending[bone] = posed
    return sk.channels(result, model.parents)


def split_hidden_props(surfaces):
    """Extract small collapsing props even when they share the body's material."""
    result = []
    for surface in surfaces:
        if surface.get('prop'):
            result.append(surface)
            continue
        points = surface['points']
        # A sword may be hidden at all three conventional sample frames.
        # Weld on its complete trajectory so a visible blade stays a surface.
        signature = points.transpose(1,0,2).reshape(points.shape[1],-1)
        _, welded = np.unique(signature, axis=0, return_inverse=True)
        parents = list(range(len(surface['tri'])))
        def root(i):
            while parents[i] != i: i = parents[i]
            return i
        edges={}
        for index,tri in enumerate(welded[surface['tri']]):
            for a,b in ((tri[0],tri[1]),(tri[1],tri[2]),(tri[2],tri[0])):
                if a==b:continue
                edge=tuple(sorted((int(a),int(b))))
                if edge in edges:parents[root(index)]=root(edges[edge])
                else:edges[edge]=index
        groups = {}
        for index in range(len(surface['tri'])):
            groups.setdefault(root(index), []).append(index)
        hidden, retained = [], []
        for triangles in groups.values():
            vertices = np.unique(surface['tri'][triangles])
            extent = np.ptp(points[:, vertices], axis=1).max(axis=1)
            # Compressed original vertices retain a small quantization box
            # when a staff is hidden. It need not collapse to an exact point.
            collapsing=len(triangles)<128 and extent.min()<max(.2,extent.max()*.005) and extent.max()>1
            elongated=False
            if not collapsing and len(triangles)<128 and len(vertices)>=4:
                reference=int(np.argmax(extent));rest=points[reference,vertices]
                axes=np.linalg.svd(rest-rest.mean(0),compute_uv=False)
                long=axes[0]>max(axes[1],1e-8)*8 and extent.max()>np.median(np.ptp(points[:,:,2],axis=1))*.3
                if long:
                    sample=points[::max(1,len(points)//32),vertices]
                    transform=rigid_fit(rest,sample,np.ones(len(vertices)))
                    predicted=np.einsum('fij,vj->fvi',transform[:,:3,:3],rest)+transform[:,None,:3,3]
                    elongated=float(np.max(np.sqrt(np.mean((predicted-sample)**2,axis=(1,2)))))<max(.08,float(extent.max())*.003)
            if collapsing or elongated:
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


def cinematic(model, surfaces, tags, *, carried=False, calibrate=True, metadata=None):
    reference_pose = CINEMATIC_REFERENCES.get(metadata.get('model')) if metadata else None
    if reference_pose:
        digest=hashlib.sha256(np.concatenate([s['points'] for s in surfaces],axis=1).astype('<f8').tobytes()).hexdigest()
        if digest!=reference_pose['points_sha256']:
            raise ValueError('Cinematic reference landmarks belong to different source geometry')
    surfaces = split_hidden_props(source_props(surfaces,metadata))
    visible = [s for s in surfaces if s['material'] != dkm2md3.NODRAW_SHADER]
    props = [s for s in visible if s.get('prop') or any(word in s['material'] for word in ('daikatana', 'purifier', 'w_', 'sword'))]
    body = [s for s in visible if not any(s is p for p in props)]
    if not body: raise ValueError('cinematic has no character body')
    source = np.concatenate([s['points'] for s in body], axis=1)
    regions = np.concatenate([np.full(len(s['uv']),
        'head' if 'head' in s['material'] or 'head' in s['name'].lower() else
        'lower' if 'legs' in s['name'].lower() else
        'upper' if 'torso' in s['name'].lower() else 'body') for s in body])
    # UV seams duplicate vertices; remove duplicates consistently on all frames.
    _, unique = np.unique(source[0], axis=0, return_index=True)
    source = source[:, unique]
    regions = regions[unique]
    target = model.arrays[0].astype(float)
    # Choose the most upright, neutral available pose. Actual frame ordering,
    # including one-frame holds and authored root motion, is retained below.
    height = np.ptp(source[..., 2], axis=1)
    # A raised hand must not become the top of the character's calibration
    # box. Use typical height, then prefer the closest neutral body silhouette.
    typical_height = np.median(height)
    candidates = np.flatnonzero((height >= typical_height * .92) & (height <= typical_height * 1.08))
    if not len(candidates): candidates = np.arange(len(source))
    # Prefer authored neutral holds over an unrelated action frame whose
    # silhouette happens to resemble the generated A pose.
    if metadata and not carried:
        neutral=[]
        for clip in metadata['sequences']['frame_data']:
            label=clip['animation_name'].lower()
            if ('standamb' in label or label in ('amb','amba','ambb','ambba','ambbb','oamba','oambb')):
                neutral.extend(range(clip['first'],clip['last']+1))
        if neutral:
            preferred=np.intersect1d(candidates,neutral)
            if len(preferred):candidates=preferred
    if not carried:
        # Source models use their initial upright pose as the local facing
        # basis. Picking a later turned gesture loses that constant rotation
        # when its motion is applied to a forward-facing replacement.
        upright_zero=height[0]>=height.max()*.85
        if upright_zero:candidates=np.array([0])
        elif metadata:
            standing=[clip['first'] for clip in metadata['sequences']['frame_data']
                      if clip['animation_name'].lower().startswith(('walka','standamb','c_standamb'))
                      and clip['first'] in candidates]
            if standing:candidates=np.array([standing[0]])
    if reference_pose:candidates=np.array([reference_pose['frame']])
    # A carried body or a one-frame corpse may have no upright reference pose.
    # Align the bind body's long axis before fitting its local bone motion.
    extent = np.ptp(source, axis=1)
    longest = int(np.argmax(extent[np.argmax(height)]))
    rotation = np.eye(3)
    if not carried and longest != 2 and height.max() < extent[:, longest].max() * .7:
        rotation = np.array([[0., 0, 1], [0, 1, 0], [-1, 0, 0]]) if longest == 0 else np.array([[1., 0, 0], [0, 0, 1], [0, -1, 0]])
    elif not carried:
        # A kneeling or wide stance can be wider than it is tall. Its width
        # does not define the scale of an upright generated skeleton.
        longest=2
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
        if reference_pose and 'scale' in reference_pose:scale=reference_pose['scale']
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
    if not carried:
        # Measure the reference end effectors on the original mesh. A hand
        # already raised in the source reference is not a hand at hip height.
        # Feet use their own low surface, so a backward foot cannot be fitted
        # to the nearer shin of an upright replacement.
        for side in ('l','r'):
            hand, elbow, shoulder, foot, knee = (model.names.index(n+'_'+side)
                if n+'_'+side in model.names else -1
                for n in ('hand','forearm','upperarm','foot','shin'))
            sign=np.sign(anchors[hand,1]-center[1]) if hand>=0 else 0
            lateral=(canonical[:,1]-center[1])*sign
            arm=(lateral>body_height*.10)&(canonical[:,2]>lo[2]+body_height*.33)&(canonical[:,2]<lo[2]+body_height*.86)&(regions!='head')&(regions!='lower')
            if hand>=0 and arm.sum()>=8:
                points=canonical[arm]
                distance=np.linalg.norm(points-anchors[hand],axis=1)
                anchors[hand]=points[np.argsort(distance)[:min(12,len(points))]].mean(axis=0)
                if elbow>=0 and shoulder>=0:
                    midpoint=(anchors[shoulder]+anchors[hand])/2
                    points=canonical[arm&(canonical[:,2]>min(anchors[hand,2],anchors[shoulder,2]))]
                    if len(points)>=4:
                        distance=np.linalg.norm(points-midpoint,axis=1)
                        anchors[elbow]=points[np.argsort(distance)[:min(8,len(points))]].mean(axis=0)
            sole=(lateral>body_height*.025)&(canonical[:,2]<lo[2]+body_height*.08)&(regions!='head')&(regions!='upper')
            if foot>=0 and sole.sum()>=4:
                anchors[foot]=canonical[sole].mean(axis=0)
                if knee>=0:
                    points=canonical[(lateral>body_height*.04)&(canonical[:,2]>lo[2]+body_height*.18)&(canonical[:,2]<lo[2]+body_height*.38)&(regions!='upper')&(regions!='head')]
                    if len(points)>=4:
                        distance=np.linalg.norm(points-anchors[knee],axis=1)
                        anchors[knee]=points[np.argsort(distance)[:min(12,len(points))]].mean(axis=0)
    source_bind[:, :3, 3] = anchors @ rotation.T
    if carried:
        source_bind = carried_reference(model, bind, carried_anchors(body))
    else:
        if reference_pose and reference_pose.get('landmarks'):
            measured={n:np.array(p,float) for n,p in reference_pose['landmarks'].items()}
            for j,name in enumerate(model.names):
                if name in measured:source_bind[j,:3,3]=measured[name]
            for j,name in enumerate(model.names):
                if name not in measured:continue
                children=[c for c,p in enumerate(model.parents) if p==j and model.names[c] in measured]
                other=children[0] if children else model.parents[j]
                if other<0:continue
                a=bind[other,:3,3]-bind[j,:3,3]
                b=source_bind[other,:3,3]-source_bind[j,:3,3]
                source_bind[j,:3,:3]=align_vectors(a[None],b[None])[0]@bind[j,:3,:3]
        # Calibrate each source limb's reference orientation as well as its
        # location. The rigid motion is a delta from this pose, not from the
        # generated body's A pose.
        for j,name in enumerate(model.names):
            if not name.startswith(('upperarm_','forearm_','hand_','thigh_','shin_')):continue
            children=[c for c,p in enumerate(model.parents) if p==j and not model.names[c].startswith('tag_')]
            other=model.parents[j] if name.startswith('hand_') else (children[0] if children else model.parents[j])
            if other<0:continue
            a=bind[other,:3,3]-bind[j,:3,3]
            b=source_bind[other,:3,3]-source_bind[j,:3,3]
            if np.linalg.norm(a)>1e-6 and np.linalg.norm(b)>1e-6:
                source_bind[j,:3,:3]=align_vectors(a[None],b[None])[0]@bind[j,:3,:3]
        for j, name in enumerate(model.names):
            if name.startswith(('fingers_', 'thumb_')):
                parent = model.parents[j]
                source_bind[j, :3, 3] += source_bind[parent, :3, 3]-bind[parent, :3, 3]
    weights = np.zeros((len(rest), len(model.names)))
    distances = np.full_like(weights,np.inf)
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
        distances[:,j]=distance
        weights[:, j] = 1/(distance+1)**2
    # Far-away source parts must not rotate a head or wrist. Keep regional
    # support compact, and honor the original model's explicit head/torso/leg
    # surfaces when it supplies them.
    nearest=distances.min(axis=1)
    weights[distances>nearest[:,None]+(body_height*.045)**2]=0
    lower=np.array([n=='pelvis' or n.startswith(('thigh_','shin_','foot_','toe_')) for n in model.names])
    upper=np.array([n in ('pelvis','chest','neck') or n.startswith(('upperarm_','forearm_','hand_')) for n in model.names])
    weights[np.ix_(regions=='lower',~lower)]=0
    weights[np.ix_(regions=='upper',~upper)]=0
    distances[np.ix_(regions=='lower',~lower)]=np.inf
    distances[np.ix_(regions=='upper',~upper)]=np.inf
    head_region=regions=='head'
    if not head_region.any():
        head_region=(canonical[:,2]>hi[2]-body_height*.18)&(np.abs(canonical[:,1]-center[1])<body_height*.12)
    if head_region.sum()>=12 and 'head' in model.names:
        head_joint=model.names.index('head')
        weights[~head_region,head_joint]=0
        distances[~head_region,head_joint]=np.inf
        weights[head_region]=0
        weights[head_region,head_joint]=1
    empty=weights.sum(axis=1)==0
    weights[empty,np.argmin(distances[empty],axis=1)]=1
    weights /= weights.sum(axis=1, keepdims=True)
    absolute = np.tile(bind, (len(source), 1, 1, 1))
    residual = []
    for j in range(len(model.names)):
        w = weights[:, j]
        support=(reference_pose or {}).get('joint_vertices',{}).get(model.names[j])
        if support is not None:
            if len(set(support))<4 or min(support)<0 or max(support)>=len(rest):
                raise ValueError('Cinematic anatomical support changed')
            w=np.zeros(len(rest));w[support]=1
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
    attach_props(model, props, absolute, reference_frame=reference)
    return dict(reference_frame=reference, scale=float(scale), fit_rms_mean=float(np.mean(residual)),
                regional_support='Compact source segment support; explicit source head, torso and leg surfaces; geometric head fallback',
                source_head_vertices=int(head_region.sum()),
                reference_landmarks=bool(reference_pose and reference_pose.get('landmarks')),
                source_reference_pinned=reference_pose is not None,
                source_anatomical_support=(reference_pose or {}).get('joint_vertices',{}),
                fit_rms_max=float(max(residual)), props=[s['name'] for s in props])


def combined(sources, surfaces, tags, metadata=None):
    models, details = [], []
    for name, material in (('mikiko', 'miko_'), ('superfly', 'sfly_')):
        model = copy.deepcopy(sources[name][0])
        body = [s for s in surfaces if material in s['material']]
        details.append(cinematic(model, body, {}, carried=name == 'mikiko', calibrate=False,metadata=metadata))
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


def attach_props(model, props, source_pose, reference_frame=None):
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
        visibility = [prop_visibility(p['points']) for p in group]
        visible = np.logical_or.reduce(visibility)
        together = np.logical_and.reduce(visibility)
        if len(group) > 1 and not together.any():
            # Separately appearing objects share no pose in which their
            # geometry can be assembled. Give each its own reference grip.
            for prop in group: attach_props(model, [prop], source_pose,reference_frame)
            continue
        if not visible.any() or not hands:
            for prop in group: append_prop(model, prop)
            continue
        point_visible = np.concatenate([np.repeat(v[:, None], len(p['uv']), axis=1) for p, v in zip(group, visibility)], axis=1)
        triangles=np.concatenate([p['tri']+sum(len(q['uv']) for q in group[:i]) for i,p in enumerate(group)])
        triangle_visible=np.concatenate([np.repeat(v[:,None],len(p['tri']),axis=1) for p,v in zip(group,visibility)],axis=1)
        grips=[closest_surface_point(points,triangles,source_pose[:,hand,:3,3],triangle_visible) for hand in hands]
        distances=np.array([np.linalg.norm(p-source_pose[:,hand,:3,3],axis=-1) for p,hand in zip(grips,hands)])
        distances[:,~visible]=np.inf
        references = distances.copy()
        references[:, ~together] = np.inf
        # A globally closest frame may put a fallen actor's wrist against the
        # bottom of a staff. Use the body's measured reference grip when the
        # prop is visible there; keep that physical point along the shaft.
        if reference_frame is not None and together[reference_frame] and distances[:,reference_frame].min()<12:
            references[:,:]=np.inf
            references[:,reference_frame]=distances[:,reference_frame]
        hand_number, reference = np.unravel_index(np.argmin(references), references.shape)
        hand = hands[hand_number]
        if distances[hand_number, reference] > 12:
            for prop in group: append_prop(model, prop)
            continue
        grip = grips[hand_number][reference]
        actual = sk.matrices(model.frames, model.parents)[:, hand]
        authored=np.tile(np.eye(4),(len(points),1,1))
        # A hidden blade collapses to a point. Fit each visibility pattern
        # against only its visible pieces, so it cannot turn the visible hilt.
        patterns,inverse=np.unique(point_visible,axis=0,return_inverse=True)
        for pattern_index,mask in enumerate(patterns):
            frames=np.flatnonzero(inverse==pattern_index)
            if mask.sum()<3:continue
            authored[frames]=rigid_fit(points[reference,mask],points[frames][:,mask],np.ones(mask.sum()))
        relative=np.linalg.inv(actual)@authored
        # Preserve authored blade rotation, anchored at the actual new wrist.
        relative[:,:3,3]=np.array([1.5,0,-1.8])-np.einsum('fij,j->fi',relative[:,:3,:3],grip)
        held = visible & (distances[hand_number] < 20)
        for prop in group: append_prop(model, prop, attachment=(hand, relative, held, actual), reference=int(reference))
        suffix = model.names[hand][-1]
        for name, axis, angle in ((f'fingers_{suffix}', 1, -1.2), (f'thumb_{suffix}', 0, .7 if suffix == 'l' else -.7)):
            if name in model.names:
                q = np.zeros(4)
                q[axis], q[3] = np.sin(angle/2), np.cos(angle/2)
                model.frames[held, model.names.index(name), 3:7] = q


def closest_surface_point(points,triangles,query,visible):
    """Batched nearest mesh point, including long shafts with sparse vertices."""
    a,b,c=(points[:,triangles[:,i]] for i in range(3))
    ab,ac=b-a,c-a;d=query[:,None]-a
    aa=(ab*ab).sum(-1);bb=(ac*ac).sum(-1);xy=(ab*ac).sum(-1)
    da=(d*ab).sum(-1);db=(d*ac).sum(-1);den=aa*bb-xy*xy
    u=(da*bb-db*xy)/np.maximum(den,1e-12);v=(db*aa-da*xy)/np.maximum(den,1e-12)
    projection=a+u[...,None]*ab+v[...,None]*ac
    candidates=[projection];valid=[visible&(den>1e-12)&(u>=0)&(v>=0)&(u+v<=1)]
    for first,last in ((a,b),(b,c),(c,a)):
        edge=last-first
        t=np.clip(((query[:,None]-first)*edge).sum(-1)/np.maximum((edge*edge).sum(-1),1e-12),0,1)
        candidates.append(first+t[...,None]*edge);valid.append(visible)
    candidates=np.concatenate(candidates,axis=1);valid=np.concatenate(valid,axis=1)
    distance=np.where(valid,((candidates-query[:,None])**2).sum(-1),np.inf)
    return candidates[np.arange(len(points)),distance.argmin(axis=1)]


def prop_visibility(points):
    extent=np.ptp(points,axis=1).max(axis=1)
    return extent>=max(.2,float(extent.max())*.005)


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
        transform[held] = relative[held]
    model.frames[:, index] = sk.channels(transform[:, None], [-1])[:, 0]
    hidden = ~prop_visibility(prop['points'])
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


def build(source, assets, output, meshes=None, characters=CHARACTERS):
    root = (assets / 'current').resolve() if (assets / 'current').exists() else assets.resolve()
    base = root / 'packages/dk3-models.pk3'
    sources, files, report, lines, shader = {}, {}, [], [], []
    provenance, extra_motion = {}, []
    for name in characters:
        directory = source / 'out' / name
        iqm_file = meshes / f'{name}.iqm' if meshes else directory / f'models/players/{name}/{name}.iqm'
        manifest_path = meshes/f'{name}.clips.json' if meshes and (meshes/f'{name}.clips.json').exists() else directory/'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        model = sk.read(iqm_file.read_bytes())
        material = f'models/neural/{name}/body'
        has_head = any(label.endswith('/head') for _, label, *_ in model.meshes)
        head_material = f'models/neural/{name}/head'
        model.meshes = [(n, head_material if label.endswith('/head') else material, *rest)
                        for n, label, *rest in model.meshes]
        sources[name] = model, {c['name']: c for c in manifest['animations']}
        texture = meshes / f'{name}.png' if meshes else directory / f'models/players/{name}/{name}.png'
        provenance[name] = dict(iqm_sha256=hashlib.sha256(iqm_file.read_bytes()).hexdigest(),
                                texture_sha256=hashlib.sha256(texture.read_bytes()).hexdigest())
        if meshes: provenance[name]['mesh'] = json.loads((meshes / f'{name}.json').read_text())
        files.update(texture_files(name, texture))
        if has_head:
            head_texture = meshes / f'{name}.head.png' if meshes else texture.with_name('head.png')
            files[head_material + '.png'] = head_texture.read_bytes()
            provenance[name]['head_texture_sha256'] = hashlib.sha256(head_texture.read_bytes()).hexdigest()
            head_receipt = meshes / f'{name}.head.json' if meshes else texture.with_name('head-reconstruction.json')
            provenance[name]['head_reconstruction'] = json.loads(head_receipt.read_text())
            # Dense head charts retain their painted texels; whole-atlas mip
            # reduction otherwise mixes small skin charts with empty gutters.
            head_stanzas = (f'{head_material}\n{{\n nomipmaps\n cull none\n {{\n'
                            f' map {head_material}.png\n rgbGen lightingDiffuse\n }}\n}}\n')
            head_stanzas += dkm2md3.variant_stanzas(head_material, head_material + '.png', False)
            for suffix in dkm2md3.RENDER_VARIANTS:
                if suffix:
                    head_stanzas = head_stanzas.replace(head_material + suffix + '\n{', head_material + suffix + '\n{\n nomipmaps')
            shader.append(head_stanzas)
        face_report = texture.with_suffix('.face.json')
        if face_report.exists(): provenance[name]['face_repair'] = json.loads(face_report.read_text())
        shader.append(dkm2md3.variant_stanzas(material, material+'.png', False))
        print(f'neural: prepared {name} mesh/materials', flush=True)
    with zipfile.ZipFile(base) as archive:
        for entry in sorted(archive.namelist()):
            if not entry.endswith('.dkm.json'): continue
            metadata = json.loads(archive.read(entry))
            name, path = character(metadata['model'],story=any(n in STORY_CHARACTERS for n in characters)), metadata['model']
            if name is None: continue
            if name == 'mikikofly' and not {'mikiko', 'superfly'} <= sources.keys(): continue
            if name not in sources and name!='mikikofly':continue
            surfaces, tags = read_md3(archive.read(path+'.md3'))
            cinematic_model = '/cinematic/' in path or '/characters/' in path or '/d1_' in path or '/d2_' in path or name == 'mikikofly'
            if name == 'mikikofly':
                model, detail = combined(sources, surfaces, tags,metadata)
            else:
                model, clips = sources[name]
                model = copy.deepcopy(model)
                detail = cinematic(model, surfaces, tags,metadata=metadata) if cinematic_model else gameplay(model, metadata, clips, tags, regenerate_motion=True)
            key = Path(path).stem
            destination = f'models/neural/{key}.iqm'
            if destination in files: raise ValueError('duplicate neural model key')
            files[destination] = sk.write(model)
            lines.append(f'{path} {destination}')
            for variant, suffix in enumerate(dkm2md3.RENDER_VARIANTS):
                files[destination+f'.{variant}.skin'] = ''.join(f'{n},{m}{suffix}\n' for n, m, *_ in model.meshes).encode()
            if path in ('models/global/m_hiro.dkm', 'models/global/m_mikiko.dkm', 'models/global/m_superfly.dkm'):
                for color in range(12):
                    files[f'models/neural/{name}/{color}.skin'] = ''.join(
                        f'{n},{m if m.endswith("/head") else f"models/neural/{name}/color{color}"}\n'
                        for n, m, *_ in model.meshes).encode()
            report.append(dict(source=path, character=name, target=destination, frames=len(model.frames),
                               joints=len(model.names), method='cinematic-fit' if cinematic_model else 'q3-clips', conversion=detail))
            print(f'neural: {path}: {len(model.frames)} skeletal frames', flush=True)
        # The two additional multiplayer appearances use Hiro/Mikiko gameplay
        # rules and timelines. Their model and material selection is cosmetic.
        for name, original in (('mishima', 'hiro'), ('usagi', 'mikiko')):
            if name not in sources: continue
            model, clips = sources[name]
            model = copy.deepcopy(model)
            metadata = json.loads(archive.read(f'models/global/m_{original}.dkm.json'))
            detail = gameplay(model, metadata, clips, regenerate_motion=True)
            extra_motion.append(dict(source='player/'+name, conversion=detail))
            destination = f'models/neural/player_{name}.iqm'
            files[destination] = sk.write(model)
            for color in range(12):
                files[f'models/neural/{name}/{color}.skin'] = ''.join(
                    f'{n},{m if m.endswith("/head") else f"models/neural/{name}/color{color}"}\n'
                    for n, m, *_ in model.meshes).encode()
            lines.append(f'player/{name} {destination}')
    files[MANIFEST] = ('\n'.join(lines)+'\n').encode()
    files['dk3/neural-animations.cfg'] = ''.join(
        f'{row["source"]} {clip["first"]} {clip["last"]} {clip["playback_first"]} {clip["playback_last"]} {clip["rate"]} {clip.get("attack_first", 0)} {clip.get("attack_count", 0)}\n'
        for row in [*[r for r in report if r['method'] == 'q3-clips'], *extra_motion] for clip in row['conversion']).encode()
    if any(name in STORY_CHARACTERS for name in characters):
        files['dk3/neural-physics.cfg']=''.join(f'{row["target"]} humanoid\n' for row in report
                                             if row['character'] in STORY_CHARACTERS).encode()
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
