# SPDX-License-Identifier: GPL-2.0-or-later
"""Anatomically reviewed character rigs and independently authored motion clips.

Consumes local detailed IQMs as geometry, UVs and materials only. Replaces the
experimental skeleton, skin weights and animations; no experiment code is used.
Coordinates are +X forward, +Y left, feet at -24, crown at 32.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

import numpy as np

import skeletal_iqm as sk
from neural_assets import connected_motion


# Measured on frontal and side orthographic mesh views, including the actual
# knee plates and shoulder pivots, rather than bounding-box body fractions.
LANDMARKS = {
    'hiro': dict(torso=[(0, 0, 8), (.3, 0, 12.5), (-1, 0, 19), (-2, 0, 24), (-1.6, 0, 27.5)],
                 arm=[(-1.8, 8.2, 21), (-.2, 11.5, 13), (2.7, 14.4, 6)],
                 leg=[(-.3, 4.2, 6), (-1, 5.8, -4.5), (-1.7, 8.3, -20.5)], toe=(5.4, 9.1, -23)),
    'mikiko': dict(torso=[(.5, 0, 7), (.8, 0, 12), (.2, 0, 17.5), (-1.3, 0, 22), (-1.8, 0, 26)],
                   arm=[(.2, 6.5, 19), (.7, 9.5, 12), (3, 11.7, 6)],
                   leg=[(.4, 4.6, 5), (-.8, 5.8, -6.5), (-.5, 7.4, -20.5)], toe=(5.4, 8.2, -23)),
    'superfly': dict(torso=[(.8, 0, 7), (.5, 0, 12), (-1, 0, 18.8), (-.5, 0, 24), (0, 0, 28)],
                     arm=[(-2.2, 8.5, 21), (-1.5, 11.8, 13), (2.4, 14.5, 5)],
                     leg=[(1.5, 4.8, 5), (1.4, 6.2, -5), (-.8, 8.4, -20)], toe=(6.5, 9.5, -23)),
    'mishima': dict(torso=[(1, 0, 7), (1, 0, 11), (.8, 0, 16), (2.5, 0, 21), (2.8, 0, 24)],
                    arm=[(1.5, 8.4, 17.5), (2, 11.8, 10), (3.6, 14.1, 3.3)],
                    leg=[(.6, 4.6, 4.5), (1.2, 6.8, -8), (.5, 8.7, -21)], toe=(7.3, 9.5, -23)),
    'usagi': dict(torso=[(.3, 0, 6), (.1, 0, 11), (-.5, 0, 17), (-.5, 0, 22), (-.9, 0, 26)],
                  arm=[(-1.2, 6.8, 18.5), (-.9, 9.8, 11.5), (-.5, 11.7, 5.5)],
                  leg=[(-.5, 4.6, 4), (-.7, 6.1, -9), (-1.6, 7.5, -21)], toe=(4.5, 8.3, -23)),
}


def rotation(axis, angle):
    c, s = np.cos(angle), np.sin(angle)
    result = np.eye(3)
    a, b = ((1, 2), (2, 0), (0, 1))[axis]
    result[a, a] = result[b, b] = c
    result[a, b], result[b, a] = -s, s
    return result


def skeleton(model, name):
    config = LANDMARKS[name]
    names, parents, positions = [], [], []
    def joint(name, parent, position):
        parents.append(names.index(parent) if parent else -1)
        names.append(name)
        positions.append(np.array(position, float))
    for n, p, pos in zip(('pelvis', 'spine', 'chest', 'neck', 'head'),
                         (None, 'pelvis', 'spine', 'chest', 'neck'), config['torso']):
        joint(n, p, pos)
    for side, sign in (('l', 1), ('r', -1)):
        mirror = np.array([1., sign, 1])
        joint('clavicle_'+side, 'chest', np.array(config['torso'][2])+[0, sign*3, 1.5])
        for n, p, pos in zip(('upperarm', 'forearm', 'hand'), ('clavicle', 'upperarm', 'forearm'), config['arm']):
            joint(n+'_'+side, p+'_'+side, np.array(pos)*mirror)
        wrist = np.array(config['arm'][-1])*mirror
        joint('fingers_'+side, 'hand_'+side, wrist+[.5, sign*.4, -2.2])
        joint('thumb_'+side, 'hand_'+side, wrist+[1.3, -sign*.9, -.5])
        for n, p, pos in zip(('thigh', 'shin', 'foot'), ('pelvis', 'thigh', 'shin'), config['leg']):
            joint(n+'_'+side, p if p == 'pelvis' else p+'_'+side, np.array(pos)*mirror)
        joint('toe_'+side, 'foot_'+side, np.array(config['toe'])*mirror)
    if name == 'mishima':
        joint('cloth_front', 'pelvis', [4, 0, 5])
        joint('cloth_back', 'pelvis', [-3, 0, 5])
    for n, p, offset in (('tag_torso', 'spine', [0, 0, 0]), ('tag_head', 'head', [0, 0, 0]),
                         ('tag_weapon', 'hand_r', [1.5, 0, -1.8])):
        joint(n, p, positions[names.index(p)]+offset)
    absolute = np.tile(np.eye(4), (len(names), 1, 1))
    absolute[:, :3, 3] = positions
    model.names, model.parents = names, parents
    model.bind = sk.channels(absolute, parents)
    model.frames = model.bind[None].copy()
    return absolute


def skin_weights(model, name, absolute):
    points = model.arrays[0]
    # Share weights across UV seams before smoothing over the actual surface.
    positions, indices, inverse = np.unique(np.round(points, 4), axis=0, return_index=True, return_inverse=True)
    scores = np.zeros((len(positions), len(model.names)))
    endpoints = {'pelvis': 'spine', 'spine': 'chest', 'chest': 'neck', 'neck': 'head'}
    for side in ('l', 'r'):
        endpoints.update({a+'_'+side: b+'_'+side for a, b in
                          (('clavicle', 'upperarm'), ('upperarm', 'forearm'), ('forearm', 'hand'),
                           ('hand', 'fingers'), ('thigh', 'shin'), ('shin', 'foot'), ('foot', 'toe'))})
    for j, bone in enumerate(model.names):
        if bone.startswith(('tag_', 'cloth_')): continue
        a = absolute[j, :3, 3]
        if bone in endpoints:
            b = absolute[model.names.index(endpoints[bone]), :3, 3]
        elif bone == 'head': b = a+[0, 0, 6]
        elif bone.startswith('toe_'): b = a+[2, 0, 0]
        else: b = a+[0, 0, -2]
        delta = b-a
        amount = np.clip((positions-a)@delta / max(delta@delta, 1e-8), 0, 1)
        distance = ((positions-a-amount[:, None]*delta)**2).sum(axis=1)
        score = np.exp(-distance/8)
        if bone.endswith(('_l', '_r')):
            sign = 1 if bone.endswith('_l') else -1
            score *= np.clip(positions[:, 1]*sign/.8, 0, 1)
        if bone.startswith(('thigh_', 'shin_', 'foot_', 'toe_')):
            score *= np.clip((LANDMARKS[name]['leg'][0][2]+4-positions[:, 2])/4, 0, 1)
        if bone.startswith(('upperarm_', 'forearm_', 'hand_', 'fingers_', 'thumb_')):
            score *= np.clip((np.abs(positions[:, 1])-4)/2, 0, 1)
        scores[:, j] = score
    if name == 'mishima':
        # The long central tabard must not acquire weights from both legs.
        cloth = (positions[:, 2] < 5) & ((np.abs(positions[:, 1]) < 2.8) | (positions[:, 0] < -3.2))
        for side, condition in (('front', positions[:, 0] >= 0), ('back', positions[:, 0] < 0)):
            selected = cloth & condition
            scores[selected] = 0
            scores[selected, model.names.index('cloth_'+side)] = 1
    # Gaussian underflow is possible only far outside an anatomical segment;
    # admit the nearest real bone explicitly instead of generating zero weights.
    missing = scores.sum(axis=1) < 1e-20
    if missing.any():
        nearest = ((positions[missing, None]-absolute[None, :len(model.names)-3, :3, 3])**2).sum(axis=-1).argmin(axis=1)
        scores[np.flatnonzero(missing), nearest] = 1
    scores /= scores.sum(axis=1, keepdims=True)
    triangles = inverse[model.triangles]
    edges = np.concatenate([triangles[:, [0, 1]], triangles[:, [1, 2]], triangles[:, [2, 0]]])
    edges = np.unique(np.sort(edges, axis=1), axis=0)
    counts = np.bincount(edges.ravel(), minlength=len(positions))
    for _ in range(5):
        neighbors = np.zeros_like(scores)
        np.add.at(neighbors, edges[:, 0], scores[edges[:, 1]])
        np.add.at(neighbors, edges[:, 1], scores[edges[:, 0]])
        scores = .7*scores + .3*neighbors/np.maximum(counts[:, None], 1)
    joints = np.argsort(-scores, axis=1)[:, :4]
    weights = np.take_along_axis(scores, joints, axis=1)
    weights = np.rint(weights/weights.sum(axis=1, keepdims=True)*255).astype(int)
    weights[:, 0] += 255-weights.sum(axis=1)
    model.arrays[4], model.arrays[5] = joints[inverse], weights[inverse]


def pose(model, absolute, phase, kind='idle', grip='rifle'):
    fitted = absolute.copy()
    index = {n: i for i, n in enumerate(model.names)}
    moving = kind in ('walk', 'run', 'back', 'crouch_walk')
    crouch = kind in ('crouch', 'crouch_walk')
    root = np.array([0., 0, -8. if crouch else 0])
    if moving: root[2] += .45*np.cos(phase*4*np.pi) - (2 if kind == 'run' else .5)
    if kind == 'idle': root[2] += .12*np.sin(phase*2*np.pi)
    dying = kind in ('death', 'dead')
    collapse = 1. if kind == 'dead' else phase*phase*(3-2*phase) if dying else 0.
    if dying: root[2] -= 7*np.sin(collapse*np.pi*.75)
    lean = .13 if kind == 'run' else .06 if moving else 0
    fitted[index['pelvis'], :3, 3] += root
    for bone in ('spine', 'chest'):
        fitted[index[bone], :3, :3] = rotation(1, lean)
    for side, sign in (('l', 1), ('r', -1)):
        ankle = absolute[index['foot_'+side], :3, 3].copy()
        ankle[1] *= .85
        foot_rotation = np.eye(3)
        if moving:
            t = (phase+(0 if side == 'l' else .5)) % 1
            stance = .5 if kind == 'run' else .62
            stride = 27 if kind == 'run' else 17
            if t < stance:
                ankle[0] += stride*(.5-t/stance)
            else:
                swing = (t-stance)/(1-stance)
                ankle[0] += stride*(-.5+swing*swing*(3-2*swing))
                ankle[2] += (5 if kind == 'run' else 3)*np.sin(swing*np.pi)
                foot_rotation = rotation(1, -.18*np.sin(swing*np.pi))
            if kind == 'back': ankle[0] = -ankle[0]
        elif kind in ('jump', 'land'):
            tuck = np.sin(np.pi*phase) if kind == 'jump' else (1-phase)**2
            ankle[0] += 4*tuck
            ankle[2] += 6*tuck if kind == 'jump' else 0
            if kind == 'land': fitted[index['pelvis'], 2, 3] -= 4*tuck
        fitted[index['foot_'+side], :3, 3] = ankle
        fitted[index['foot_'+side], :3, :3] = foot_rotation
        fitted[index['shin_'+side], :3, 3] = ankle+[10, -sign*1.5, 12]
        if grip == 'pistol':
            hand = np.array([11.5, sign*(4 if side == 'r' else 7), 15 if side == 'r' else 9])
        elif grip == 'glove': hand = np.array([8.5, sign*6.2, 14.5])
        else: hand = np.array([12 if side == 'r' else 13, sign*(4 if side == 'r' else 3), 14.5])
        if kind == 'attack':
            impulse = np.sin(np.pi*phase)**2
            if grip == 'glove' and side == 'r': hand += [8*impulse, 8*np.sin(phase*2*np.pi), 5*np.sin(phase*2*np.pi)]
            elif grip != 'glove':
                recoil = np.sin(min(1, phase*2.5)*np.pi)
                hand += [-3*recoil, 0, 1.4*recoil]
        if dying:
            hand = hand*(1-collapse)+np.array([1, sign*12, 5])*collapse
        hand += root
        fitted[index['hand_'+side], :3, 3] = hand
        fitted[index['forearm_'+side], :3, 3] = hand+[-8, sign*6, -5]
        fitted[index['hand_'+side], :3, :3] = rotation(1, .12*np.sin(phase*2*np.pi) if kind == 'attack' else 0)
    # Lower the pelvis just enough to reach both planted feet. Clamping an
    # overextended leg in IK would lift its foot during the contact interval.
    drop = 0.
    for side in ('l', 'r'):
        thigh, shin, foot = (index[n+'_'+side] for n in ('thigh', 'shin', 'foot'))
        hip = absolute[thigh, :3, 3]+root
        ankle = fitted[foot, :3, 3]
        reach = np.linalg.norm(model.bind[shin, :3])+np.linalg.norm(model.bind[foot, :3])-.25
        height = np.sqrt(max(0., reach*reach-np.sum((hip[:2]-ankle[:2])**2)))
        drop = max(drop, hip[2]-ankle[2]-height)
    fitted[index['pelvis'], 2, 3] -= drop
    for side in ('l', 'r'):
        fitted[index['hand_'+side], 2, 3] -= drop
        fitted[index['forearm_'+side], 2, 3] -= drop
    result = connected_motion(model, fitted[None])[0]
    # Curl the real finger region; the wrist remains the weapon grip's parent.
    for side in ('l', 'r'):
        curl = -.6*(1-collapse)
        result[index['fingers_'+side], 3:7] = [0, np.sin(curl), 0, np.cos(curl)]
        result[index['thumb_'+side], 3:7] = [np.sin(.35 if side == 'l' else -.35), 0, 0, np.cos(.35)]
    if kind in ('death', 'dead'):
        t = 1 if kind == 'dead' else phase*phase*(3-2*phase)
        result[0, 3:7] = [0, np.sin(-np.pi*t/4), 0, np.cos(-np.pi*t/4)]
        result[0, 0] -= 8*t
        # Position the falling/lying mesh on its actual lowest surface.
        sample = sk.Model({k: a[::40] for k, a in model.arrays.items()}, [], np.empty((0, 3), int),
                          model.names, model.parents, model.bind, result[None])
        result[0, 2] += -24-sk.skin(sample)[0, :, 2].min()
    if kind == 'swim':
        result[0, 3:7] = [0, np.sin(np.pi*.23), 0, np.cos(np.pi*.23)]
        for side, sign in (('l', 1), ('r', -1)):
            angle = .22*np.sin(phase*2*np.pi)*sign
            result[index['thigh_'+side], 3:7] = [0, np.sin(angle/2), 0, np.cos(angle/2)]
    return result


def clips(model, absolute):
    frames, definitions = [], []
    specs = [('LEGS_IDLE', 'idle', 2., True), ('LEGS_WALK', 'walk', .8, True),
             ('LEGS_RUN', 'run', .5, True), ('LEGS_BACK', 'back', .8, True),
             ('LEGS_WALKCR', 'crouch_walk', .9, True), ('LEGS_IDLECR', 'crouch', 2., True),
             ('LEGS_JUMP', 'jump', .6, False), ('LEGS_LAND', 'land', .25, False),
             ('LEGS_SWIM', 'swim', 1., True), ('BOTH_DEATH1', 'death', .9, False),
             ('BOTH_DEAD1', 'dead', 1/30, False)]
    for label, kind, seconds, loop in specs:
        count = max(1, round(seconds*30))
        start = len(frames)
        frames += [pose(model, absolute, f/(count if loop else max(1, count-1)), kind) for f in range(count)]
        definitions.append(dict(name=label, first=start, count=count, fps=30, loop=count if loop else 0))
    for grip in ('glove', 'pistol', 'rifle'):
        for label, kind, count in (('STAND', 'idle', 1), ('ATTACK', 'attack', 12)):
            start = len(frames)
            frames += [pose(model, absolute, f/max(1, count-1), kind, grip) for f in range(count)]
            definitions.append(dict(name=f'TORSO_{label}_{grip.upper()}', first=start, count=count, fps=30, loop=0))
    for alias, target in (('TORSO_STAND', 'TORSO_STAND_RIFLE'), ('TORSO_ATTACK', 'TORSO_ATTACK_PISTOL'),
                           ('TORSO_ATTACK2', 'TORSO_ATTACK_GLOVE')):
        definitions.append(dict(next(c for c in definitions if c['name'] == target), name=alias))
    model.frames = np.array(frames)
    return definitions


def build(source, output, name):
    model_path = source/f'{name}.iqm'
    model = sk.read(model_path.read_bytes())
    absolute = skeleton(model, name)
    skin_weights(model, name, absolute)
    definitions = clips(model, absolute)
    output.mkdir(parents=True, exist_ok=True)
    (output/f'{name}.iqm').write_bytes(sk.write(model))
    # A separately baked face repair can already occupy the destination.
    if not (output/f'{name}.png').exists(): shutil.copy2(source/f'{name}.png', output/f'{name}.png')
    provenance = json.loads((source/f'{name}.json').read_text())
    provenance.update(rig_source_sha256=hashlib.sha256(model_path.read_bytes()).hexdigest(),
                      rig='Anatomical landmarks, surface-smoothed weights, fixed-length IK with pelvis-relative knee planes and joint limits',
                      leg_limits=dict(knee_flexion=[3, 145], hip_pitch=[-50, 110], hip_spread=[-12, 55], ankle_cone=70, toe_cone=35),
                      rig_landmarks=LANDMARKS[name], bones=len(model.names))
    face = output/f'{name}.face.json'
    if face.exists(): provenance['face_repair'] = json.loads(face.read_text())
    (output/f'{name}.json').write_text(json.dumps(provenance, indent=2)+'\n')
    (output/f'{name}.clips.json').write_text(json.dumps(dict(animations=definitions), indent=2)+'\n')
    print('rigged', name, len(model.names), 'bones', len(model.frames), 'frames', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--models', nargs='+', default=list(LANDMARKS))
    args = parser.parse_args()
    for name in args.models: build(args.source, args.out, name)
