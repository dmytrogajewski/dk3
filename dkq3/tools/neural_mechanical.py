# SPDX-License-Identifier: GPL-2.0-or-later
"""Rigid mechanical armor regions on the anatomical biped skeleton."""
import numpy as np

ROBOTS = frozenset(('sludgeminion', 'ragemaster'))


def arms(points, slug):
    heights = (21., 11., -6.) if slug == 'sludgeminion' else (21., 13., 3.)
    result = {}
    for side, sign in (('l', 1), ('r', -1)):
        joints = []
        for z, minimum in zip(heights, (12, 15, 18)):
            band = points[(np.abs(points[:, 2]-z)<1.5) & (points[:, 1]*sign>minimum)]
            if len(band)<8:
                raise ValueError(f'{slug}: missing mechanical {side} joint near {z}')
            center = np.median(band, axis=0)
            center[2] = z
            joints.append(center.tolist())
        result['arm_'+side] = joints
    return result


def rigid_panels(model):
    """Split articulation boundaries; every triangle retains its exact shape.

    Armor and claws follow rigid parent segments. The common skeleton retains
    fixed lengths, source event intervals, hardpoints and native humanoid physics.
    """
    remap = np.arange(len(model.names))
    for j, name in enumerate(model.names):
        if name.startswith(('fingers_', 'thumb_')):
            remap[j] = model.names.index('hand_'+name[-1])
        elif name.startswith('toe_'):
            remap[j] = model.names.index('foot_'+name[-1])
    scores = np.zeros((len(model.arrays[0]), len(model.names)))
    for i in range(4):
        np.add.at(scores, (np.arange(len(scores)), remap[model.arrays[4][:, i]]), model.arrays[5][:, i])
    regions = scores[model.triangles].sum(axis=1).argmax(axis=1)
    source_vertices, joints, faces, meshes = [], [], [], []
    for _, material, fv, nv, ft, nt in model.meshes:
        cache = {}
        start_v, start_t = len(source_vertices), len(faces)
        def finish():
            nonlocal cache, start_v, start_t
            if len(faces)>start_t:
                meshes.append((f'mechanical_{len(meshes):03}', material, start_v,
                               len(source_vertices)-start_v, start_t, len(faces)-start_t))
            cache = {}
            start_v, start_t = len(source_vertices), len(faces)
        for t in range(ft, ft+nt):
            keys = [(int(v), int(regions[t])) for v in model.triangles[t]]
            if len(cache)+len(set(keys)-cache.keys())>=1000:
                finish()
            indices = []
            for key in keys:
                if key not in cache:
                    cache[key] = len(source_vertices)
                    source_vertices.append(key[0])
                    joints.append(key[1])
                indices.append(cache[key])
            faces.append(indices)
        finish()
    model.arrays = {k:v[source_vertices].copy() for k,v in model.arrays.items() if k in (0,1,2)}
    model.arrays[4] = np.column_stack((joints, np.zeros((len(joints),3)))).astype('u1')
    model.arrays[5] = np.tile(np.array([255,0,0,0],dtype='u1'),(len(joints),1))
    model.meshes, model.triangles = meshes, np.asarray(faces)


def motion(model, absolute, phase, kind):
    """Heavy free arms and one-arm strikes, without a human weapon grip."""
    from neural_rig import pose
    import skeletal_iqm as sk
    result=pose(model,absolute,phase,kind,'relaxed')
    moving=kind in ('walk','run','back','crouch_walk')
    for side,sign in (('l',1),('r',-1)):
        for stem in ('clavicle','upperarm','forearm','hand','fingers','thumb'):
            j=model.names.index(stem+'_'+side)
            result[j]=model.bind[j]
        swing=.16*np.sin(phase*2*np.pi)*sign if moving else .025*np.sin(phase*2*np.pi)
        strike=np.sin(phase*np.pi)**2 if kind=='attack' else 0.
        shoulder=model.names.index('upperarm_'+side)
        elbow=model.names.index('forearm_'+side)
        angle=swing-strike*(1.05 if side=='r' else .15)
        result[shoulder,3:7]=[0,np.sin(angle/2),0,np.cos(angle/2)]
        angle=-.3*strike if side=='r' else 0.
        result[elbow,3:7]=[0,np.sin(angle/2),0,np.cos(angle/2)]
    if kind in ('death','dead'):
        sample=sk.Model({k:v[::40] for k,v in model.arrays.items()},[],np.empty((0,3),int),
                        model.names,model.parents,model.bind,result[None])
        result[0,2]+=-24-sk.skin(sample)[0,:,2].min()
    return result
