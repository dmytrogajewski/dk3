# SPDX-License-Identifier: GPL-2.0-or-later
"""Deterministic skeletal segmentation and performance fitting for arbitrary creatures.

Source vertex trajectories define rigid motion regions. This is a fitted skeletal
approximation, with measured errors, not a recovered anatomical source skeleton.
"""
import numpy as np

import skeletal_iqm as sk


def align(document, arrays, geometry):
    """Recover upright yaw from the source surface rather than assumed GLB axes."""
    from neural_monster_skeleton import BIPEDS
    if document['actor'].get('slug') in BIPEDS:
        # A-pose limbs cannot be matched against an asymmetric gameplay pose:
        # the old full-body Chamfer search can incorrectly turn the face away.
        # TRELLIS can rotate a reconstruction by a quarter turn. The separated
        # neutral arms identify the lateral axis independently of source motion.
        points=np.unique(np.round(geometry[0],5),axis=0)
        height=np.ptp(points[:,2]);z=(points[:,2]-points[:,2].min())*56/max(height,1e-6)-24
        arms=points[(z>5)&(z<20),:2]
        if len(arms)<20:arms=points[:,:2]
        lateral=np.linalg.eigh(np.cov(arms.T))[1][:,-1]
        angle=float(np.rad2deg(np.arctan2(lateral[0],lateral[1])))
        angle=(angle+90)%180-90
        if abs(angle)<2:angle=0.
        radians=np.deg2rad(angle)
        rotation=np.array([[np.cos(radians),-np.sin(radians),0],[np.sin(radians),np.cos(radians),0],[0,0,1]])
        geometry[0]=geometry[0]@rotation.T
        geometry[2]=geometry[2]@rotation.T
        return dict(yaw_degrees=angle, scale=1.,
                    method='neutral arm lateral axis; source gameplay pose excluded; frontal polarity visually reviewed')
    from scipy.spatial import cKDTree
    frame=document['actor']['reference_frame']
    reference=np.concatenate([arrays[f'{i}_points'][frame] for i in range(len(document['surfaces']))])
    faces=[]
    offset=0
    for i in range(len(document['surfaces'])):
        faces.extend((arrays[f'{i}_tri']+offset).tolist())
        offset+=len(arrays[f'{i}_points'][frame])
    triangles=reference[np.asarray(faces)]
    areas=np.linalg.norm(np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]),axis=1)
    random=np.random.default_rng(0)
    chosen=random.choice(len(triangles),4096,p=areas/areas.sum())
    uv=random.random((4096,2));uv[uv.sum(axis=1)>1]=1-uv[uv.sum(axis=1)>1]
    sampled=triangles[chosen,0]+uv[:,:1]*(triangles[chosen,1]-triangles[chosen,0])+uv[:,1:]*(triangles[chosen,2]-triangles[chosen,0])
    tree=cKDTree(sampled)
    points=np.unique(np.round(geometry[0],5),axis=0)
    points=points[np.linspace(0,len(points)-1,min(len(points),4096),dtype=int)]
    center=(reference.min(axis=0)+reference.max(axis=0))/2
    extent=float(np.max(np.ptp(reference,axis=0)))
    origin=(geometry[0].min(axis=0)+geometry[0].max(axis=0))/2
    points-=origin
    def candidate(angle):
        radians=np.deg2rad(angle)
        rotation=np.array([[np.cos(radians),-np.sin(radians),0],[np.sin(radians),np.cos(radians),0],[0,0,1]])
        rotated=points@rotation.T
        scale=extent/np.max(np.ptp(rotated,axis=0))
        translation=center-(rotated.min(axis=0)+rotated.max(axis=0))/2*scale
        moved=rotated*scale+translation
        outward=tree.query(moved)[0]
        inward=cKDTree(moved).query(sampled)[0]
        score=(np.mean(np.minimum(outward,np.quantile(outward,.95))**2)+np.mean(np.minimum(inward,np.quantile(inward,.95))**2))/extent**2
        return float(score),angle,rotation,scale,translation
    choices=[candidate(angle) for angle in range(-180,180,15)]
    best=min(choices,key=lambda r:r[0])
    choices+=[candidate(best[1]+delta) for delta in range(-14,15,2)]
    best=min(choices,key=lambda r:r[0])
    choices+=[candidate(best[1]+delta) for delta in (-1,1)]
    best=min(choices,key=lambda r:r[0])
    original=candidate(0)
    if original[0]<=best[0]*1.02: best=original
    score,angle,rotation,scale,translation=best
    geometry[0]=(geometry[0]-origin)@rotation.T*scale+translation
    geometry[2]=geometry[2]@rotation.T
    return dict(yaw_degrees=float(angle),surface_score=score,scale=float(scale),
                method='upright yaw search against area-sampled source surfaces; visual review required')


def nearest_points(points, query, count):
    try:
        from scipy.spatial import cKDTree
        return cKDTree(points).query(query, k=count)
    except ImportError:
        # Blender ships its own KD tree, keeping the converter independent of
        # site-packages belonging to a different Python ABI.
        try:
            from mathutils.kdtree import KDTree
        except ImportError:
            distances,indices=[],[]
            for start in range(0,len(query),128):
                square=np.sum((query[start:start+128,None]-points[None])**2,axis=2)
                closest=np.argsort(square,axis=1)[:,:count]
                indices.append(closest)
                distances.append(np.sqrt(np.take_along_axis(square,closest,axis=1)))
            return np.concatenate(distances),np.concatenate(indices)
        tree = KDTree(len(points))
        for i, point in enumerate(points): tree.insert(point, i)
        tree.balance()
        rows = [tree.find_n(point, count) for point in query]
        return (np.array([[hit[2] for hit in row] for row in rows]),
                np.array([[hit[1] for hit in row] for row in rows]))


def rigid(rest, poses):
    center = rest.mean(axis=0)
    moving = poses.mean(axis=1)
    covariance = np.einsum('vi,fvj->fij', rest-center, poses-moving[:, None])
    u, _, vt = np.linalg.svd(covariance)
    correction = np.tile(np.eye(3), (len(poses), 1, 1))
    correction[:, 2, 2] = np.linalg.det(np.einsum('fij,fjk->fik', u, vt))
    rotations = np.einsum('fij,fjk,fkl->fil', vt.transpose(0, 2, 1), correction, u.transpose(0, 2, 1))
    translations = moving - np.einsum('fij,j->fi', rotations, center)
    return rotations, translations


def clusters(reference, motion, count):
    scale = max(float(np.max(np.ptp(reference, axis=0))), 1)
    sample = motion[np.linspace(0, len(motion)-1, min(64, len(motion)), dtype=int)]
    displacement = sample-reference
    displacement -= displacement.mean(axis=1, keepdims=True)
    trajectories = displacement.transpose(1, 0, 2).reshape(len(reference), -1)/scale
    # Motion information distinguishes adjacent but independently moving limbs.
    u, singular, _ = np.linalg.svd(trajectories, full_matrices=False)
    dimensions = min(12, len(singular))
    features = np.concatenate(((reference-reference.mean(axis=0))/scale,
                               u[:, :dimensions]*singular[:dimensions]*.7), axis=1)
    seeds = [int(np.argmin(np.linalg.norm(reference-reference.mean(axis=0), axis=1)))]
    distances = np.full(len(reference), np.inf)
    for _ in range(count-1):
        distances = np.minimum(distances, np.sum((features-features[seeds[-1]])**2, axis=1))
        candidate = int(np.argmax(distances))
        if candidate in seeds: break
        seeds.append(candidate)
    centers = features[seeds].copy()
    assignment = np.zeros(len(reference), int)
    for _ in range(40):
        following = np.argmin(np.sum((features[:, None]-centers[None])**2, axis=2), axis=1)
        if np.array_equal(following, assignment) and _: break
        assignment = following
        for j in range(len(centers)):
            group = assignment == j
            if group.any(): centers[j] = features[group].mean(axis=0)
    # Tiny regions cannot constrain a full rigid transform reliably.
    retained = [j for j in range(len(centers)) if np.count_nonzero(assignment == j) >= 6]
    if not retained: retained = [int(np.argmax(np.bincount(assignment)))]
    result = np.argmin(np.sum((features[:, None]-centers[retained][None])**2, axis=2), axis=1)
    return result


def hierarchy(centers):
    root = int(np.argmin(np.linalg.norm(centers-centers.mean(axis=0), axis=1)))
    order, parents = [root], [-1]
    pending = set(range(len(centers)))-{root}
    while pending:
        _, child, parent = min((float(np.linalg.norm(centers[c]-centers[p])), c, i)
                               for c in pending for i,p in enumerate(order))
        order.append(child)
        parents.append(parent)
        pending.remove(child)
    return order, parents


def fit(document, arrays, geometry, surfaces, triangles):
    if document['actor'].get('slug')=='protopod':
        from neural_pod import fit_pod
        return fit_pod(document,geometry,surfaces,triangles)
    from neural_monster_skeleton import BIPEDS,fit_humanoid
    if document['actor'].get('slug') in BIPEDS:
        return fit_humanoid(document,arrays,geometry,surfaces,triangles)
    poses = np.concatenate([arrays[f'{i}_points'] for i in range(len(document['surfaces']))], axis=1)
    reference = poses[document['actor']['reference_frame']]
    # Coincident UV/surface seams share their source influences.
    _, unique, inverse = np.unique(np.round(reference, 4), axis=0, return_index=True, return_inverse=True)
    points, motion = reference[unique], poses[:, unique]
    assignments = clusters(points, motion, min(28, max(4, len(points)//24)))
    count = int(assignments.max())+1
    centers = np.array([points[assignments==j].mean(axis=0) for j in range(count)])
    order, parents = hierarchy(centers)
    remap = np.argsort(order)
    assignments = remap[assignments]
    centers = centers[order]
    bind_absolute = np.tile(np.eye(4), (count, 1, 1))
    bind_absolute[:, :3, 3] = centers
    absolute = np.tile(np.eye(4), (len(poses), count, 1, 1))
    residual = np.empty_like(motion)
    for j in range(count):
        group = assignments == j
        rotation, translation = rigid(points[group], motion[:, group])
        absolute[:, j, :3, :3] = rotation
        absolute[:, j, :3, 3] = np.einsum('fij,j->fi', rotation, centers[j])+translation
        reconstructed = np.einsum('fij,vj->fvi', rotation, points[group])+translation[:, None]
        residual[:, group] = reconstructed-motion[:, group]
    names = [f'creature_{j:02}' for j in range(count)]
    # Hardpoints keep their authored frame-by-frame translations and exact names.
    # They are attachment bones, excluded from the corpse's particle solver.
    for name in document['tags']:
        if name in names: raise ValueError('Duplicate source attachment')
        bind = np.eye(4)
        bind[:3, 3] = arrays['tag_'+name][document['actor']['reference_frame']]
        posed = np.tile(np.eye(4), (len(poses), 1, 1))
        posed[:, :3, 3] = arrays['tag_'+name]
        bind_absolute = np.concatenate((bind_absolute, bind[None]))
        absolute = np.concatenate((absolute, posed[:, None]), axis=1)
        names.append(name)
        parents.append(0)
    if len(names)>64: raise ValueError('Creature rig exceeds native live-bone capacity')
    distances, nearest = nearest_points(points, geometry[0], min(8, len(points)))
    proximity = 1/np.maximum(distances, .1)**2
    influence = np.zeros((len(geometry[0]), len(names)))
    for i in range(nearest.shape[1]):
        np.add.at(influence, (np.arange(len(influence)), assignments[nearest[:, i]]), proximity[:, i])
    indices = np.argsort(-influence, axis=1)[:, :4]
    weights = np.take_along_axis(influence, indices, axis=1)
    weights = np.rint(weights/weights.sum(axis=1, keepdims=True)*255).astype(int)
    weights[:, 0] += 255-weights.sum(axis=1)
    if indices.shape[1]<4:
        missing=4-indices.shape[1]
        indices=np.pad(indices,((0,0),(0,missing)))
        weights=np.pad(weights,((0,0),(0,missing)))
    geometry[4], geometry[5] = indices.astype('u1'), weights.astype('u1')
    model = sk.Model(geometry, surfaces, triangles, names, parents,
                     sk.channels(bind_absolute, parents), sk.channels(absolute, parents))
    sk.validate(model)
    errors = np.linalg.norm(residual, axis=2)
    clips = []
    for sequence in document['metadata']['sequences']['frame_data']:
        first, last = sequence['first'], sequence['last']
        if not 0 <= first <= last < len(model.frames): raise ValueError('Invalid source animation interval')
        clips.append(dict(name=sequence['animation_name'], first=first, last=last,
                          rms=float(np.sqrt(np.mean(errors[first:last+1]**2)))))
    return model, dict(format=1, rig='trajectory regions, rigid fits and spatial minimum spanning hierarchy',
        source_frames=len(poses), output_frames=len(model.frames), joints=len(names), body_joints=count,
        hardpoints=document['tags'], rms=float(np.sqrt(np.mean(errors**2))),
        maximum_residual=float(errors.max()), clips=clips,
        limits=['Segmentation is automatic; anatomical pivot review and extreme poses may require refinement.',
                'Generated topology and single-image proportions differ from the source mesh.'])


if __name__ == '__main__':
    import argparse
    import json
    from pathlib import Path
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor', type=Path, required=True)
    args = parser.parse_args()
    document = json.loads((args.actor/'source.json').read_text())
    source = np.load(args.actor/'source.npz')
    mesh = np.load(args.actor/'geometry.npz')
    geometry = json.loads((args.actor/'geometry.json').read_text())
    arrays={int(k):mesh[k] for k in mesh.files if k!='triangles'}
    alignment=align(document,source,arrays)
    reviewed=args.actor/'alignment.json'
    if reviewed.is_file():
        override=json.loads(reviewed.read_text());angle=float(override['yaw_add_degrees'])
        if not np.isfinite(angle):raise ValueError('Nonfinite reviewed yaw')
        a=np.deg2rad(angle);r=np.array([[np.cos(a),-np.sin(a),0],[np.sin(a),np.cos(a),0],[0,0,1]])
        arrays[0]=arrays[0]@r.T;arrays[2]=arrays[2]@r.T
        alignment['reviewed_yaw_add_degrees']=angle;alignment['review']=override
    model, report = fit(document, source, arrays,
                        geometry['surfaces'], mesh['triangles'])
    report.update({k: value for k,value in geometry.items() if k != 'surfaces'})
    report['alignment']=alignment
    (args.actor/'model.iqm').write_bytes(sk.write(model))
    (args.actor/'conversion.json').write_text(json.dumps(report, indent=2)+'\n')
    if document['actor'].get('kind')=='character':
        (args.actor/'model.clips.json').write_text(json.dumps(dict(animations=report['clips']),indent=2)+'\n')
    print(f'Built {len(model.frames)} frames, {len(model.names)} joints; motion {report.get("motion", "source fit")}', flush=True)
