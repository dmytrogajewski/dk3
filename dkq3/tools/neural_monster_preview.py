#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Sample converted IQM performances for a Blender CPU visual review."""
import argparse
import json
from pathlib import Path
import subprocess
import numpy as np
import skeletal_iqm as sk
from neural_monsters import environment, digest, save


def skin_normals(model, frames):
    transforms = sk.matrices(frames, model.parents) @ np.linalg.inv(sk.matrices(model.bind, model.parents))
    blended = np.zeros((len(frames), len(model.arrays[0]), 3, 3))
    for influence in range(4):
        blended += transforms[:, model.arrays[4][:, influence], :3, :3] * (model.arrays[5][:, influence]/255)[None, :, None, None]
    cofactors = np.stack([np.cross(blended[..., :, 1], blended[..., :, 2]),
                          np.cross(blended[..., :, 2], blended[..., :, 0]),
                          np.cross(blended[..., :, 0], blended[..., :, 1])], axis=-1)
    normals = np.einsum('fvij,vj->fvi', cofactors, model.arrays[2])
    return normals / np.maximum(np.linalg.norm(normals, axis=-1, keepdims=True), 1e-9)


def preview(actor, blender):
    model = sk.read((actor/'model.iqm').read_bytes())
    source = json.loads((actor/'source.json').read_text())
    sequences = source['metadata']['sequences']['frame_data']
    reference=source['actor']['reference_frame']
    chosen = [dict(name='bind', frame=0, bind=True, source_frame=reference),
              dict(name='reference', frame=min(reference,len(model.frames)-1),source_frame=reference)]
    if source['actor'].get('kind') == 'character':
        clips=json.loads((actor/'model.clips.json').read_text())['animations']
        chosen=chosen[:1]
        for label,family in (('LEGS_IDLE','amb'),('LEGS_RUN','run'),('LEGS_WALK','walk'),
                             ('TORSO_ATTACK_PISTOL','atak'),('BOTH_DEATH1','die')):
            clip=next(r for r in clips if r['name']==label)
            original=next((r for r in sequences if r['animation_name'].startswith(family)),None)
            chosen.append(dict(name=label,frame=clip['first']+clip['count']//2,
                               source_frame=(original['first']+original['last'])//2 if original else reference))
    else:
        for family in ('amb', 'run', 'walk', 'atak', 'aatk', 'hatch', 'die'):
            clip = next((r for r in sequences if r['animation_name'].startswith(family)), None)
            if clip:
                chosen.append(dict(name=clip['animation_name'], frame=(clip['first']+clip['last'])//2))
    for row in chosen:
        row['image'] = f'preview-{row["name"]}-{row["frame"]:04}.png'
        row['source_image'] = f'preview-source-{row["name"]}-{row["frame"]:04}.png'
    key = dict(iqm=digest(actor/'model.iqm'), atlas=digest(actor/'body.png'),
               source=digest(actor/'source.npz'),metadata=digest(actor/'source.json'),
               sampler=digest(Path(__file__)),renderer=digest(Path(__file__).with_name('neural_monster_preview_blender.py')),
               studio=digest(Path(__file__).with_name('neural_monster_blender.py')))
    if any(material.endswith('/head') for _,material,*_ in model.meshes):
        key['head_atlas']=digest(actor/'head.png')
    prior = actor/'preview.json'
    if prior.is_file():
        receipt = json.loads(prior.read_text())
        if receipt.get('inputs') == key and all((actor/n).is_file() and digest(actor/n)==sha for n,sha in receipt.get('outputs',{}).items()) and receipt.get('outputs'):
            return receipt
    frames = np.asarray([model.bind if r.get('bind') else model.frames[r['frame']] for r in chosen])
    points = sk.skin(model, frames)
    if not np.isfinite(points).all(): raise ValueError('Nonfinite skinned pose')
    np.savez_compressed(actor/'preview.npz', points=points, normals=skin_normals(model,frames), triangles=model.triangles, uv=model.arrays[1])
    receipt = dict(inputs=key, poses=chosen, meshes=[list(row) for row in model.meshes])
    save(prior, receipt)
    with (actor/'preview.log').open('w') as log:
        subprocess.run([blender,'-b','--threads','4','--python-exit-code','1','--python',
                        str(Path(__file__).with_name('neural_monster_preview_blender.py')),'--','--actor',str(actor.resolve())],
                       stdout=log, stderr=subprocess.STDOUT, env=environment(actor.parent), check=True)
    receipt['outputs'] = {r[key]: digest(actor/r[key]) for r in chosen for key in ('image','source_image')}
    save(prior, receipt)
    print(actor.name, len(chosen), 'sampled poses', flush=True)
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor', type=Path, required=True)
    parser.add_argument('--blender', default='blender')
    args = parser.parse_args()
    preview(args.actor, args.blender)
