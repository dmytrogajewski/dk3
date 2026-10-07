# SPDX-License-Identifier: GPL-2.0-or-later
"""Surface topology and animation-preservation evidence for neural repairs."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from itertools import combinations

import numpy as np
import skeletal_iqm as sk


def topology(model):
    _, inverse = np.unique(model.arrays[0], axis=0, return_inverse=True)
    triangles = inverse[model.triangles]
    edges = np.sort(np.concatenate((triangles[:, :2], triangles[:, 1:],
                                    triangles[:, [2, 0]])), axis=1)
    _, counts = np.unique(edges, axis=0, return_counts=True)
    return dict(boundary_edges=int(np.sum(counts == 1)),
                nonmanifold_edges=int(np.sum(counts > 2)),
                degenerate_triangles=int(np.sum(np.any(np.diff(np.sort(triangles, axis=1), axis=1) == 0, axis=1))))


def uv_quality(model,details=False):
    """Find positive-area atlas overlaps, including crossing skinny triangles."""
    triangles=np.asarray(model.arrays[1][model.triangles],float)
    edges=triangles[:,1:]-triangles[:,:1]
    area=edges[:,0,0]*edges[:,1,1]-edges[:,0,1]*edges[:,1,0]
    cells={};count=len(triangles);bins=128
    low=np.floor(triangles.min(axis=1)*bins).astype(int)
    high=np.floor(triangles.max(axis=1)*bins).astype(int)
    for i,(a,b) in enumerate(zip(low,high)):
        for x in range(a[0],b[0]+1):
            for y in range(a[1],b[1]+1):cells.setdefault((x,y),[]).append(i)
    pairs=set()
    for members in cells.values():
        pairs.update(a*count+b for a,b in combinations(members,2))
    candidates=np.fromiter(pairs,dtype=np.int64)
    conflicts=[]
    for first in range(0,len(candidates),8192):
        values=candidates[first:first+8192]
        a,b=triangles[values//count],triangles[values%count]
        edges=np.concatenate((np.roll(a,-1,axis=1)-a,np.roll(b,-1,axis=1)-b),axis=1)
        axes=np.stack((-edges[:,:,1],edges[:,:,0]),axis=-1)
        axes/=np.maximum(np.linalg.norm(axes,axis=-1,keepdims=True),1e-20)
        pa=np.einsum('nvi,nai->nav',a,axes);pb=np.einsum('nvi,nai->nav',b,axes)
        depth=np.minimum(pa.max(axis=-1),pb.max(axis=-1))-np.maximum(pa.min(axis=-1),pb.min(axis=-1))
        conflicts.extend(values[np.all(depth>1e-8,axis=1)].tolist())
    degenerate=np.flatnonzero(np.abs(area)<1e-12)
    result=dict(overlapping_triangle_pairs=len(conflicts),degenerate_uv_triangles=len(degenerate))
    if details:
        result['conflicting_triangles']=sorted(set(degenerate.tolist()+[i for pair in conflicts for i in (pair//count,pair%count)]))
    return result


def animation_preservation(before, after):
    if before.names != after.names or list(before.parents) != list(after.parents):
        raise ValueError('Surface repair changed skeleton or attachment names')
    if before.frames.shape != after.frames.shape or before.bind.shape != after.bind.shape:
        raise ValueError('Surface repair changed animation frame channels')
    bind_error = float(np.max(np.abs(before.bind-after.bind)))
    frame_error = float(np.max(np.abs(before.frames-after.frames)))
    if bind_error > 1e-5 or frame_error > .002:
        raise ValueError('Surface repair changed retained animation transforms')
    if not np.all(after.arrays[5].sum(axis=1) == 255):
        raise ValueError('Transferred skin influences do not sum to 255')
    return dict(joint_names_and_parents='identical', joint_count=len(after.names),
                frames=len(after.frames), maximum_bind_error=bind_error,
                maximum_frame_error=frame_error, unit='serialized IQM channels')


def close_actor(actor, blender, env):
    actor = Path(actor)
    if actor.name in ('prisoner', 'prisonerb'):
        raise ValueError('Protected prisoners cannot receive surface repairs')
    config = json.loads((actor/'surface-quality.json').read_text())
    allowed = {'voxel', 'thickness', 'triangles'}
    if set(config) - allowed:
        raise ValueError('Unknown surface repair setting')
    data = (actor/'model.iqm').read_bytes()
    source = 'model-before-closure-'+hashlib.sha256(data).hexdigest()[:12]+'.iqm'
    (actor/source).write_bytes(data)
    shutil.copy2(actor/'body.png', actor/'body-before-closure.png')
    command = [blender, '-b', '--threads', '4', '--python-exit-code', '1', '--python',
               str(Path(__file__).with_name('neural_surface_close.py')), '--',
               '--source', str(actor), '--out', str(actor), '--texture', str(actor/'body.png')]
    for key, value in config.items():
        command.extend(['--'+key, str(value)])
    with (actor/'surface-closure.log').open('w') as log:
        subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    before, after = sk.read(data), sk.read((actor/'model.iqm').read_bytes())
    quality = topology(after)
    if any(quality.values()):
        raise ValueError('Closed runtime surface is not manifold: '+str(quality))
    atlas=uv_quality(after)
    if any(atlas.values()):raise ValueError('Repaired atlas has UV overlap or collapsed faces: '+str(atlas))
    report = json.loads((actor/'surface-closure.json').read_text())
    report.update(input_file=source, topology=quality,uv_quality=atlas,
                  animation_preservation=animation_preservation(before, after),
                  coordinator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (actor/'surface-closure.json').write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')
    conversion = json.loads((actor/'conversion.json').read_text())
    conversion['surface_closure'] = report
    conversion['vertices'], conversion['triangles'] = len(after.arrays[0]), len(after.triangles)
    (actor/'conversion.json').write_text(json.dumps(conversion, indent=2, sort_keys=True)+'\n')
