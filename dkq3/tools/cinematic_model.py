#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Reconstruct one source-specific cinematic body from pinned local observations.

This is an explicit mesh/bind/weight rebuild, separate from motion-only builds.
It learns bounded skin weights from original vertex motion, retains the original
costume UVs, and optionally grafts an already admitted detailed head. No network,
runtime scripting, source writes, or claim of artistic acceptance.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import platform
from pathlib import Path
import sys
import zipfile

import numpy as np
import scipy
from scipy.optimize import nnls
from scipy.spatial import cKDTree
from scipy.spatial.transform import Rotation

import animation_manifest as schema
import animation_motion as motion
import cinematic_reconstruction as capture
import skeletal_iqm as sk
from animation_author import fresh, local, tools_identity
from neural_assets import read_md3, source_props, split_hidden_props, append_prop, align_vectors
from neural_head import body_below, split_surfaces, pack_weights
from neural_package import classic_archive, validate_package
from dkm2md3 import variant_stanzas


def source_motion(surface: dict, profile: dict) -> motion.Motion:
    schema.fields(profile,('version','source_model','source_md3_sha256','surface','reference_frame','markers','clips','props','regularization','max_marker_rms','provenance'),
                  ('version','source_model','source_md3_sha256','surface','reference_frame','markers','clips','provenance'),'capture profile')
    if profile['version']!=1 or not isinstance(profile['markers'],dict) or not 1<=len(profile['markers'])<=128:
        raise schema.Error('bounded version 1 marker profile required')
    if not 1<=len(surface['points'])<=4096 or not 4<=surface['points'].shape[1]<=10000:raise schema.Error('cinematic rebuild source exceeds frame/vertex limits')
    schema.number(profile['reference_frame'],0,len(surface['points'])-1,'reference frame',integer=True)
    schema.number(profile.get('regularization',.002),0,.05,'regularization')
    names=list(profile['markers']);parents=[]
    rest=np.broadcast_to(np.eye(4),(len(names),4,4)).copy()
    frames=np.broadcast_to(np.eye(4),(len(surface['points']),len(names),4,4)).copy()
    ref=profile['reference_frame']
    for j,(name,marker) in enumerate(profile['markers'].items()):
        schema.text(name,'marker',32);schema.fields(marker,('parent','anchor','vertices','reference_axes'),('parent','anchor','vertices'),'marker '+name)
        if marker['parent'] is not None and marker['parent'] not in names[:j]:raise schema.Error('marker parent must precede child','ANIM_UNKNOWN_BONE',name)
        schema.vector(marker['anchor'],'marker anchor')
        vertices=marker['vertices']
        if not isinstance(vertices,list) or not 4<=len(vertices)<=256 or len(set(vertices))!=len(vertices):raise schema.Error('marker requires unique bounded vertices',field=name)
        for v in vertices:schema.number(v,0,surface['points'].shape[1]-1,'marker vertex',integer=True)
        parents.append(names.index(marker['parent']) if marker['parent'] else -1)
        rest[j,:3,3]=marker['anchor'];vertices=marker['vertices']
        if 'reference_axes' in marker:rest[j,:3,:3]=capture.landmark_basis(surface['points'][ref],marker['reference_axes'])
        frames[:,j],_=capture.rigid_capture(surface['points'][ref,vertices],surface['points'][:,vertices],rest[j,:3,3],profile.get('regularization',.002))
        frames[:,j,:3,:3]=frames[:,j,:3,:3]@rest[j,:3,:3]
    return motion.Motion(names,parents,rest,frames,10.,np.zeros((len(frames),3)),dict(source_md3_sha256=profile['source_md3_sha256']))


def source_bind(template: sk.Model, observed: motion.Motion) -> sk.Model:
    """Preserve named attachment contracts; declare a new measured bind pose."""
    model=copy.deepcopy(template);old=sk.matrices(model.bind,model.parents)
    rest=np.broadcast_to(np.eye(4),old.shape).copy()
    scale=np.linalg.norm(observed.rest[observed.names.index('foot_l'),:3,3]-observed.rest[observed.names.index('thigh_l'),:3,3])/np.linalg.norm(old[model.names.index('foot_l'),:3,3]-old[model.names.index('thigh_l'),:3,3])
    for j,name in enumerate(model.names):
        parent=model.parents[j]
        if name in observed.names:rest[j,:3,3]=observed.rest[observed.names.index(name),:3,3]
        elif name.startswith('clavicle_'):
            shoulder=observed.rest[observed.names.index('upperarm_'+name[-1]),:3,3]
            rest[j,:3,3]=(rest[parent,:3,3]+shoulder)*.5
        elif name.startswith('prop_'):continue
        elif parent>=0:rest[j,:3,3]=rest[parent,:3,3]+(old[j,:3,3]-old[parent,:3,3])*scale
    # Prop meshes live in their original visible reference coordinates.
    model.bind=sk.channels(rest,model.parents);model.frames=model.bind[None].copy()
    return model


def learn_weights(model: sk.Model, rest_points: np.ndarray, observations: np.ndarray,
                  world: np.ndarray, source_frames: np.ndarray) -> tuple[np.ndarray, dict]:
    """Nonnegative, normalized, at most four local anatomical influences."""
    bind=sk.matrices(model.bind,model.parents);transforms=world[source_frames]@np.linalg.inv(bind)
    corrected={n.removeprefix('deform_') for n in model.names if n.startswith('deform_')}
    usable=[j for j,n in enumerate(model.names) if n not in corrected and not n.startswith(('prop_','tag_','clavicle_','fingers_','thumb_'))]
    weights=np.zeros((len(rest_points),len(model.names)));errors=[]
    for v,point in enumerate(rest_points):
        distance=[]
        for j in usable:
            children=[c for c,p in enumerate(model.parents) if p==j and c in usable]
            a=bind[j,:3,3];b=bind[children[0],:3,3] if children else a
            delta=b-a;t=np.clip((point-a)@delta/max(delta@delta,1e-8),0,1)
            distance.append(np.linalg.norm(point-a-delta*t))
        candidates=np.asarray(usable)[np.argsort(distance,kind='stable')[:8]]
        # Include the source hand for its nearby glove, never the other arm.
        selected_transforms=transforms[:,candidates]
        predicted=np.einsum('fjik,k->fji',selected_transforms[...,:3,:3],point)+selected_transforms[...,:3,3]
        wanted=observations[source_frames,v]
        matrix=predicted.transpose(0,2,1).reshape(-1,len(candidates))
        # Normalization is strongly constrained in the fit and exact on export.
        fitted,_=nnls(np.vstack((matrix,np.ones((1,len(candidates)))*100)),np.r_[wanted.ravel(),100],maxiter=100)
        keep=np.argsort(-fitted,kind='stable')[:4];selected=candidates[keep]
        reduced,_=nnls(np.vstack((matrix[:,keep],np.ones((1,len(keep)))*100)),np.r_[wanted.ravel(),100],maxiter=100)
        if reduced.sum()<1e-8:raise schema.Error('unweighted fitted vertex', 'ANIM_INVALID_WEIGHTS',str(v))
        reduced/=reduced.sum();weights[v,selected]=reduced
        errors.append(float(np.sqrt(np.mean((np.einsum('fji,j->fi',predicted[:,keep],reduced)-wanted)**2))))
    return weights,dict(training_frames=source_frames.tolist(),vertex_rms_max=max(errors),vertex_rms_median=float(np.median(errors)),method='local nonnegative source-motion fit; normalized four influences')


def subdivide(model: sk.Model, levels: int) -> sk.Model:
    """Welded Loop subdivision with UV seams and normalized weights preserved."""
    result=copy.deepcopy(model)
    dense=np.zeros((len(result.arrays[0]),len(result.names)))
    for slot in range(4):np.add.at(dense,(np.arange(len(dense)),result.arrays[4][:,slot]),result.arrays[5][:,slot]/255.)
    values={k:result.arrays[k].astype(float) for k in (0,1,2)};values[6]=dense
    tri=result.triangles.copy()
    for _ in range(levels):
        positions,first,weld=np.unique(np.round(values[0],6),axis=0,return_index=True,return_inverse=True)
        adjacency=[set() for _ in positions];opposites={}
        for a,b,c in weld[tri]:
            for x,y,z in ((a,b,c),(b,c,a),(c,a,b)):
                if x==y:continue
                adjacency[x].add(y);adjacency[y].add(x);opposites.setdefault(tuple(sorted((int(x),int(y)))),[]).append(z)
        boundary=[set() for _ in positions]
        for (a,b),other in opposites.items():
            if len(other)==1:boundary[a].add(b);boundary[b].add(a)
        smoothed=positions.copy()
        for j,neighbors in enumerate(adjacency):
            if len(boundary[j])==2:smoothed[j]=.75*positions[j]+.125*positions[list(boundary[j])].sum(axis=0)
            elif neighbors and not boundary[j]:
                beta=3/16 if len(neighbors)==3 else 3/(8*len(neighbors))
                smoothed[j]=(1-len(neighbors)*beta)*positions[j]+beta*positions[list(neighbors)].sum(axis=0)
        updated={k:list(v) for k,v in values.items()};updated[0]=list(smoothed[weld]);edges={};faces=[]
        def edge(a: int,b: int) -> int:
            key=tuple(sorted((int(a),int(b))))
            if key not in edges:
                edges[key]=len(updated[0]);geometric=tuple(sorted((int(weld[a]),int(weld[b]))));others=opposites[geometric]
                pos=(positions[weld[a]]+positions[weld[b]])*.5
                if len(others)==2:pos=.375*(positions[weld[a]]+positions[weld[b]])+.125*positions[others].sum(axis=0)
                for k,v in values.items():updated[k].append(pos if k==0 else (v[a]+v[b])*.5)
            return edges[key]
        for a,b,c in tri:
            ab,bc,ca=edge(a,b),edge(b,c),edge(c,a)
            faces.extend(((a,ab,ca),(ab,b,bc),(ca,bc,c),(ab,bc,ca)))
        values={k:np.asarray(v) for k,v in updated.items()};tri=np.asarray(faces,dtype='u4')
    # Normals follow the regenerated surface, shared across UV seams.
    normals=np.zeros_like(values[0]);face=np.cross(values[0][tri[:,1]]-values[0][tri[:,0]],values[0][tri[:,2]]-values[0][tri[:,0]])
    for slot in range(3):np.add.at(normals,tri[:,slot],face)
    _,first,weld=np.unique(np.round(values[0],6),axis=0,return_index=True,return_inverse=True)
    smooth=np.zeros((len(first),3));np.add.at(smooth,weld,normals);normals=smooth[weld];normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-8)
    packed=[pack_weights(w) for w in values[6]]
    result.arrays={0:values[0],1:values[1],2:normals,4:np.asarray([p[0] for p in packed]),5:np.asarray([p[1] for p in packed])};result.triangles=tri
    rows=[[{k:result.arrays[k][v] for k in result.arrays} for v in face] for face in tri]
    result.arrays,result.triangles,result.meshes=split_surfaces(rows,model.meshes[0][1],'dojo_body')
    return result


def source_body_rows(model: sk.Model, height: float) -> list:
    """Replace the head at its skin boundary, retaining higher sleeves."""
    cutting=copy.copy(model)
    corrected={n.removeprefix('deform_') for n in model.names if n.startswith('deform_')}
    cutting.names=[('control_'+n if n in ('head','neck') and n in corrected else
                    n.removeprefix('deform_') if n in ('deform_head','deform_neck') else n) for n in model.names]
    return body_below(cutting,height,retain_upper_body=True)


def rebuild(recipe_path: Path, base_models: Path, output: Path) -> dict:
    recipe=schema.load(recipe_path);root=recipe_path.resolve().parent
    schema.fields(recipe,('version','profile','template','template_sha256','head_material','body_material','neck_cut','subdivision','head_scale','surface_correctives','provenance'),
                  ('version','profile','template','template_sha256','head_material','body_material','neck_cut','subdivision','head_scale','provenance'),'cinematic model')
    if recipe['version']!=1:raise schema.Error('cinematic model requires version 1')
    if type(recipe.get('surface_correctives',False)) is not bool:raise schema.Error('surface_correctives must be boolean')
    profile_path=local(root,recipe['profile']);profile=schema.load(profile_path)
    template_path=local(root,recipe['template'])
    if template_path.stat().st_size>32*1024*1024:raise schema.Error('template exceeds 32 MiB limit')
    payload=template_path.read_bytes()
    if hashlib.sha256(payload).hexdigest()!=recipe['template_sha256']:raise schema.Error('admitted head/template hash changed','ANIM_SOURCE_HASH_MISMATCH')
    schema.fields(recipe['provenance'],('origin','license','redistribution','credit'),('origin','license','redistribution','credit'),'model provenance')
    if any(not isinstance(v,str) or not v or len(v)>4096 for v in recipe['provenance'].values()):raise schema.Error('explicit model provenance required')
    template=sk.read(payload);source=schema.asset(profile['source_model'],'source model','.dkm')
    levels=schema.number(recipe['subdivision'],0,2,'subdivision',integer=True);cut=schema.number(recipe['neck_cut'],15,30,'neck cut');scale=schema.number(recipe['head_scale'],.5,1.5,'head scale')
    material=schema.asset(recipe['body_material'],'body material');head_material=schema.asset(recipe['head_material'],'head material')
    with zipfile.ZipFile(base_models) as archive:
        blob=capture.archive_read(archive,source+'.md3',32*1024*1024)
        metadata=json.loads(capture.archive_read(archive,source+'.json',4*1024*1024))
    if capture.digest(blob)!=profile['source_md3_sha256']:raise schema.Error('original source hash changed','ANIM_SOURCE_HASH_MISMATCH')
    surfaces=split_hidden_props(source_props(read_md3(blob)[0],metadata));surface=next(s for s in surfaces if s['name']==profile['surface'] and not s.get('prop'))
    observed=source_motion(surface,profile);model=source_bind(template,observed)
    recipe_motion=dict(bones={n:n for n in observed.names},forward='x',up='z',scale=1.,root_origin='reference',
        rotation_bones=['spine','chest','neck','head','hand_l','hand_r'],preserve_observed_poles=True,stabilize_poles=True,
        bind_bones=[n for n in model.names if n.startswith(('fingers_','thumb_'))])
    posed=motion.retarget(model,observed,recipe_motion,'preserve');model.frames=motion.export_channels(posed)
    retained_joints=len(model.names);correctives={}
    if recipe.get('surface_correctives'):
        # Directions alone cannot reproduce moving shoulder pivots or changing
        # distances in the original vertex performance. Fit this source body to
        # declared measured surface frames, while canonical bones stay fixed.
        canonical_world=sk.matrices(model.frames,model.parents)
        regions=['pelvis','spine','chest','neck','head']+[region+'_'+side for side in ('l','r') for region in ('upperarm','forearm','hand')]
        for source_bone in regions:
            name='deform_'+source_bone;parent=model.names.index(source_bone)
            motion.attach(model,name,source_bone,[0,0,0]);j=model.names.index(name);source_j=observed.names.index(source_bone)
            transform=observed.world[:,source_j].copy();transform[:,:3,:3]=transform[:,:3,:3]@observed.rest[source_j,:3,:3].T
            model.frames[:,j]=sk.channels((np.linalg.inv(canonical_world[:,parent])@transform)[:,None],[-1])[:,0]
            correctives[name]=source_bone
        posed.world=sk.matrices(model.frames,model.parents)
    points=surface['points'][profile['reference_frame']]
    # Fit the explicitly declared performance block, not unrelated jumping or
    # kneeling sequences with a different observable marker contract. Other
    # retained frame numbers remain available but require separate acceptance.
    if not isinstance(profile['clips'],dict) or not 1<=len(profile['clips'])<=128:raise schema.Error('bounded source clip mapping required')
    intervals=[schema.span(c['source_frames']) for c in profile['clips'].values()]
    if any(b>=len(observed.world) for a,b in intervals):raise schema.Error('training interval outside source','ANIM_INVALID_RANGE')
    frames=np.unique(np.concatenate([np.r_[np.arange(a,b+1,2),b] for a,b in intervals]))
    weights,metrics=learn_weights(model,points,surface['points'],posed.world,frames)
    packed=[pack_weights(w) for w in weights]
    model.arrays={0:points,1:surface['uv'],2:surface['normals'][profile['reference_frame']],4:np.asarray([p[0] for p in packed]),5:np.asarray([p[1] for p in packed])}
    model.triangles=surface['tri'];model.meshes=[('dojo',material,0,len(points),0,len(model.triangles))]
    # A height-only cut also removes sleeves above the neck plane. Use the
    # learned neck/head ownership to retain those original costume surfaces.
    body_rows=source_body_rows(model,cut)
    body_rows=[row for row in body_rows if np.linalg.norm(np.cross(row[1][0]-row[0][0],row[2][0]-row[0][0]))>1e-8]
    model.arrays,model.triangles,model.meshes=split_surfaces(body_rows,material,'dojo_body');model=subdivide(model,levels)
    # Align the admitted head to the original reference performance, using the
    # measured face basis and original crown. The body owns the neck below cut.
    head_faces=np.concatenate([template.triangles[ft:ft+nt] for _,mat,_,_,ft,nt in template.meshes if mat==head_material])
    head_vertices=np.unique(head_faces);bind=sk.matrices(template.bind,template.parents)
    origin=bind[template.names.index('head'),:3,3];j=observed.names.index('head');rotation=observed.rest[j,:3,:3]
    hp=(template.arrays[0]-origin)@rotation.T*scale+observed.rest[j,:3,3]
    hp[:,2]+=points[:,2].max()-hp[head_vertices,2].max()
    hn=template.arrays[2]@rotation.T
    nearest=cKDTree(points).query(hp[head_vertices],k=3)[1]
    distance=np.linalg.norm(hp[head_vertices,None]-points[nearest],axis=2);amount=1/np.maximum(distance,.1)**2;amount/=amount.sum(axis=1,keepdims=True)
    head_weights=np.sum(weights[nearest]*amount[:,:,None],axis=1)
    # The face is rigid; only the continuous neck connection blends with torso.
    face=np.clip((hp[head_vertices,2]-cut)/2,0,1)
    rigid=np.zeros_like(head_weights);rigid[:,model.names.index('deform_head' if correctives else 'head')]=1
    head_weights=(1-face[:,None])*head_weights+face[:,None]*rigid
    lookup={int(v):i for i,v in enumerate(head_vertices)};head_rows=[]
    for tri in head_faces:
        row=[]
        for v in tri:
            joint,weight=pack_weights(head_weights[lookup[int(v)]])
            row.append({0:hp[v],1:template.arrays[1][v],2:hn[v],4:joint,5:weight})
        head_rows.append(row)
    arrays,triangles,meshes=split_surfaces(head_rows,head_material,'dojo_head');fv=len(model.arrays[0]);ft=len(model.triangles)
    for k in model.arrays:model.arrays[k]=np.concatenate((model.arrays[k],arrays[k]))
    model.triangles=np.concatenate((model.triangles,triangles+fv));model.meshes.extend((a,b,c+fv,d,e+ft,f) for a,b,c,d,e,f in meshes)
    # Remove old prop joints before appending original surfaces, preserving
    # their reviewed names, group ordering and rigid source trajectory.
    count=next((i for i,n in enumerate(model.names) if n.startswith('prop_')),len(model.names))
    auxiliary=(model.names[retained_joints:],model.parents[retained_joints:],model.bind[retained_joints:].copy(),model.frames[:,retained_joints:].copy())
    model.names=model.names[:count];model.parents=model.parents[:count];model.bind=model.bind[:count];model.frames=model.frames[:,:count]
    for prop in surfaces:
        if prop.get('prop'):
            append_prop(model,prop,reference=0)
            visible=np.ptp(prop['points'],axis=1).max(axis=1)>=np.ptp(prop['points'][0],axis=0).max()*.05
            model.frames[:,model.names.index(model.meshes[-1][0]),7:10]=visible[:,None]
    if correctives:
        if len(model.names)!=retained_joints:raise schema.Error('source prop/corrective joint contract changed','ANIM_INCOMPATIBLE_SKELETON')
        model.names+=auxiliary[0];model.parents+=auxiliary[1]
        model.bind=np.concatenate((model.bind,auxiliary[2]));model.frames=np.concatenate((model.frames,auxiliary[3]),axis=1)
    sk.validate(model);directory=fresh(output,True);destination=directory/'hiro-dojo.iqm';destination.write_bytes(sk.write(model));admitted=sk.read(destination.read_bytes())
    schema.write_json(directory/'retarget.json',recipe_motion)
    motion.write(directory/'observed.npz',observed)
    report=dict(version=1,passed=True,kind='explicit source-specific model rebuild',source_model=source,source_md3_sha256=capture.digest(blob),
        recipe_sha256=schema.sha(recipe_path),profile_sha256=schema.sha(profile_path),template_sha256=schema.sha(template_path),tool_sha256=schema.sha(Path(__file__)),tools=tools_identity(),
        provenance=recipe['provenance'],versions=dict(python=platform.python_version(),numpy=np.__version__,scipy=scipy.__version__),model_file=destination.name,body_material=material,vertices=len(admitted.arrays[0]),triangles=len(admitted.triangles),frames=len(admitted.frames),bones=admitted.names,
        output_sha256=schema.sha(destination),bind_pose_sha256=schema.bind_identity(admitted),weight_fit=metrics,correctives=correctives,visual_acceptance='unverified',
        changes=['source-proportioned bind','white dojo gi body/UVs','source-motion fitted weights','skin-aware neck cut preserving sleeves','welded body subdivision','measured detailed-head placement','original rigid prop motion',
                 'explicit measured torso/head/arm surface correctives' if correctives else 'canonical torso and arms'])
    schema.write_json(directory/'model.json',report);return report


def rebase(recipe_path: Path, base_models: Path, output: Path) -> dict:
    """Repose an admitted costume onto measured source-specific limb lengths."""
    recipe=schema.load(recipe_path);root=recipe_path.resolve().parent
    schema.fields(recipe,('version','profile','template','template_sha256','surface_correctives','provenance'),('version','profile','template','template_sha256','provenance'),'source rig rebase')
    if recipe['version']!=1:raise schema.Error('source rig rebase requires version 1')
    if type(recipe.get('surface_correctives',False)) is not bool:raise schema.Error('surface_correctives must be boolean')
    profile_path=local(root,recipe['profile']);profile=schema.load(profile_path);template_path=local(root,recipe['template'])
    if template_path.stat().st_size>32*1024*1024 or schema.sha(template_path)!=recipe['template_sha256']:raise schema.Error('template hash/size differs','ANIM_SOURCE_HASH_MISMATCH')
    schema.fields(recipe['provenance'],('origin','license','redistribution','credit'),('origin','license','redistribution','credit'),'model provenance')
    if any(not isinstance(v,str) or not v or len(v)>4096 for v in recipe['provenance'].values()):raise schema.Error('explicit model provenance required')
    source=schema.asset(profile['source_model'],'source model','.dkm')
    with zipfile.ZipFile(base_models) as archive:
        blob=capture.archive_read(archive,source+'.md3',32*1024*1024);metadata=json.loads(capture.archive_read(archive,source+'.json',4*1024*1024))
    if capture.digest(blob)!=profile['source_md3_sha256']:raise schema.Error('source model hash changed','ANIM_SOURCE_HASH_MISMATCH')
    surfaces=split_hidden_props(source_props(read_md3(blob)[0],metadata));surface=next(s for s in surfaces if s['name']==profile['surface'] and not s.get('prop'))
    original=sk.read(template_path.read_bytes());observed=source_motion(surface,profile);model=source_bind(original,observed)
    rest=sk.matrices(model.bind,model.parents);pose=rest.copy();j=model.names.index('head')
    pose[j,:3,:3]=observed.rest[observed.names.index('head'),:3,:3]
    if recipe.get('surface_correctives'):
        # The old open, downward fingers are not the captured closed gloves.
        # Bake a closed reference before transferring the measured palm frame.
        for side in ('l','r'):
            for name,angles in [('fingers_'+side,[0,-40,0]),('thumb_'+side,[0,-15,10])]:
                child=model.names.index(name);pose[child,:3,:3]=Rotation.from_euler('xyz',angles,degrees=True).as_matrix()
    model.arrays[0]=sk.skin(original,sk.channels(pose[None],model.parents))[0]
    hand_alignment={};hand_rotations=[]
    if recipe.get('surface_correctives'):
        for side in ('l','r'):
            name='hand_'+side;j=model.names.index(name);group=[j,model.names.index('fingers_'+side),model.names.index('thumb_'+side)]
            ownership=np.sum(original.arrays[5]*np.isin(original.arrays[4],group),axis=1)/255.
            selected=ownership>=.75
            if not selected.any():raise schema.Error('hand has no surface support','ANIM_UNOBSERVABLE_MARKER',name)
            anchor=rest[j,:3,3];center=model.arrays[0][selected].mean(axis=0)
            target=surface['points'][profile['reference_frame'],profile['markers'][name]['vertices']].mean(axis=0)
            rotation=align_vectors((center-anchor)[None],(target-anchor)[None])[0]
            posed_hand=(model.arrays[0]-anchor)@rotation.T+anchor
            shift=target-posed_hand[selected].mean(axis=0)
            blend=np.clip((ownership-.1)/.65,0,1)
            model.arrays[0]+=(posed_hand+shift-model.arrays[0])*blend[:,None]
            hand_alignment[name]=dict(source_center=target.tolist(),previous_center=center.tolist(),translation=shift.tolist(),rotation=rotation.tolist(),reference='pinned original hand-region vertices')
            hand_rotations.append((rotation,blend))
    # Reposing an ankle alone retains the old boot's sole-to-ankle offset.
    # Match the observed shoes locally, instead of lowering the entire actor
    # to reach the floor and subsequently bending the staff arm to compensate.
    soles={}
    for side in ('l','r'):
        indices=[model.names.index('foot_'+side),model.names.index('toe_'+side)]
        ownership=np.sum(original.arrays[5]*np.isin(original.arrays[4],indices),axis=1)/255.
        selected=ownership>=.5
        if not selected.any():raise schema.Error('rebase foot has no sole support','ANIM_UNOBSERVABLE_MARKER',side)
        vertices=profile['markers']['foot_'+side]['vertices']+profile['markers']['toe_'+side]['vertices']
        wanted=float(surface['points'][profile['reference_frame'],vertices,2].min());current=float(model.arrays[0][selected,2].min())
        ankle=rest[indices[0],2,3];blend=np.clip((ankle-model.arrays[0][:,2])/max(ankle-current,.1),0,1)
        model.arrays[0][selected,2]+=(wanted-current)*blend[selected]
        rigid=selected&(model.arrays[0][:,2]<ankle-.8)
        model.arrays[4][rigid]=[indices[0],0,0,0];model.arrays[5][rigid]=[255,0,0,0]
        soles[side]=dict(original_height=current,observed_height=wanted,maximum_correction=wanted-current)
    transforms=pose@np.linalg.inv(sk.matrices(original.bind,original.parents));normals=np.zeros_like(original.arrays[2])
    for slot in range(4):normals+=np.einsum('vij,vj->vi',transforms[original.arrays[4][:,slot],:3,:3],original.arrays[2])*(original.arrays[5][:,slot]/255.)[:,None]
    for rotation,blend in hand_rotations:normals+=(normals@rotation.T-normals)*blend[:,None]
    normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-8);model.arrays[2]=normals
    recipe_motion=dict(bones={n:n for n in observed.names},forward='x',up='z',scale=1.,root_origin='reference',rotation_bones=['spine','chest','neck','head','hand_l','hand_r'],
                       preserve_observed_poles=True,stabilize_poles=True,bind_bones=[n for n in model.names if n.startswith(('fingers_','thumb_'))])
    posed=motion.retarget(model,observed,recipe_motion,'preserve');model.frames=motion.export_channels(posed)
    # Exclude old prop surfaces, which have not been reposed as body geometry.
    body=[mesh for mesh in model.meshes if not mesh[0].startswith('prop_')]
    vertices=max(fv+nv for _,_,fv,nv,_,_ in body);triangles=max(ft+nt for _,_,_,_,ft,nt in body)
    model.arrays={k:v[:vertices] for k,v in model.arrays.items()};model.triangles=model.triangles[:triangles];model.meshes=body
    count=next(i for i,n in enumerate(model.names) if n.startswith('prop_'))
    model.names=model.names[:count];model.parents=model.parents[:count];model.bind=model.bind[:count];model.frames=model.frames[:,:count]
    for prop in surfaces:
        if prop.get('prop'):
            name='prop_'+str(len(model.names));ref=profile['props'][name]['reference_frame'];append_prop(model,prop,reference=ref)
            visible=np.ptp(prop['points'],axis=1).max(axis=1)>=np.ptp(prop['points'][ref],axis=0).max()*.05
            model.frames[:,model.names.index(name),7:10]=visible[:,None]
    correctives={}
    if recipe.get('surface_correctives'):
        canonical_world=sk.matrices(model.frames,model.parents)
        # The loose cloak is not a rigid pelvis/chest surface. Keep its
        # canonical cloth/leg ownership; transfer observed neck/head and arms.
        regions=['neck','head']+[region+'_'+side for side in ('l','r') for region in ('upperarm','forearm','hand')]
        for source_bone in regions:
            name='deform_'+source_bone;parent=model.names.index(source_bone)
            motion.attach(model,name,source_bone,[0,0,0]);j=model.names.index(name);source_j=observed.names.index(source_bone)
            transform=observed.world[:,source_j].copy();transform[:,:3,:3]=transform[:,:3,:3]@observed.rest[source_j,:3,:3].T
            local_pose=np.linalg.inv(canonical_world[:,parent])@transform
            model.frames[:,j]=sk.channels(local_pose[:,None],[-1])[:,0]
            model.arrays[4][model.arrays[4]==parent]=j
            if source_bone.startswith('hand_'):
                for digit in ('fingers_','thumb_'):
                    model.arrays[4][model.arrays[4]==model.names.index(digit+source_bone[-1])]=j
            if source_bone=='pelvis':
                for cloth in ('cloth_front','cloth_back'):
                    if cloth in model.names:model.arrays[4][model.arrays[4]==model.names.index(cloth)]=j
            correctives[name]=source_bone
    sk.validate(model);directory=fresh(output,True);destination=directory/'rebased.iqm';destination.write_bytes(sk.write(model));admitted=sk.read(destination.read_bytes())
    schema.write_json(directory/'retarget.json',recipe_motion)
    report=dict(version=1,passed=True,kind='explicit source-proportioned rig rebase',source_model=source,source_md3_sha256=capture.digest(blob),
                recipe_sha256=schema.sha(recipe_path),profile_sha256=schema.sha(profile_path),template_sha256=schema.sha(template_path),tool_sha256=schema.sha(Path(__file__)),tools=tools_identity(),
                model_file=destination.name,output_sha256=schema.sha(destination),bind_pose_sha256=schema.bind_identity(admitted),provenance=recipe['provenance'],versions=dict(python=platform.python_version(),numpy=np.__version__,scipy=scipy.__version__),
                vertices=len(admitted.arrays[0]),triangles=len(admitted.triangles),frames=len(admitted.frames),sole_reconstruction=soles,hand_alignment=hand_alignment,correctives=correctives,visual_acceptance='unverified',
                changes=['measured limb lengths and pivots','costume reposed using existing weights','observed shoe height and rigid sole weights','original rigid prop geometry and motion','measured reference head orientation','explicit measured arm-surface correctives' if correctives else 'canonical arms'])
    schema.write_json(directory/'model.json',report);return report


def package_model(overlay: Path, base_models: Path, rebuilt: Path, texture: Path | None,
                  target: str, output: Path) -> dict:
    """Admit a changed model as a new baseline; never bypass frozen motion checks."""
    return package_models(overlay,base_models,[dict(directory=rebuilt,target=target,texture=texture)],output)


def package_models(overlay: Path, base_models: Path, repairs: list[dict], output: Path) -> dict:
    if not 1<=len(repairs)<=16:raise schema.Error('bounded model repair list required')
    previous=validate_package(overlay,base_models)
    with zipfile.ZipFile(overlay) as archive:files={n:archive.read(n) for n in archive.namelist() if n!='dk3/neural-assets.json'}
    mapping=dict(line.split() for line in files['dk3/neural-models.cfg'].decode().splitlines() if line.strip());changed={};overlay_sha=schema.sha(overlay)
    for repair in repairs:
        target=repair['target'];schema.asset(target,'target model','.iqm')
        if target in changed:raise schema.Error('duplicate model repair','ANIM_DUPLICATE_CLIP',target)
        directory=Path(repair['directory']).resolve();texture=repair.get('texture')
        report=json.loads((directory/'model.json').read_text())
        source=schema.asset(report['source_model'],'source model','.dkm')
        with zipfile.ZipFile(base_models) as archive:
            if capture.digest(capture.archive_read(archive,source+'.md3',32*1024*1024))!=report['source_md3_sha256']:raise schema.Error('repair source differs from admitted base','ANIM_SOURCE_HASH_MISMATCH',source)
        admit_repair(files,mapping,previous,directory,texture,target,report,overlay_sha)
        changed[target]=report['output_sha256']
    previous['files']={n:capture.digest(v) for n,v in files.items()};files['dk3/neural-assets.json']=(json.dumps(previous,sort_keys=True,indent=2)+'\n').encode()
    destination=fresh(output);temporary=fresh(destination.with_suffix('.partial'))
    try:
        with classic_archive(temporary) as archive:
            for name,data in sorted(files.items()):
                entry=zipfile.ZipInfo(name,(1980,1,1,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED;archive.writestr(entry,data)
        validate_package(temporary,base_models);temporary.replace(destination)
    finally:
        if temporary.exists():temporary.unlink()
    return dict(passed=True,output=str(destination),sha256=schema.sha(destination),changed_models=changed)


def admit_repair(files: dict, mapping: dict, previous: dict, directory: Path,
                 texture: Path | None, target: str, report: dict, overlay_sha: str) -> None:
    filename=report.get('model_file','hiro-dojo.iqm')
    if Path(filename).name!=filename:raise schema.Error('invalid rebuilt model file')
    if not report.get('passed') or schema.sha(directory/filename)!=report['output_sha256']:raise schema.Error('rebuild receipt/model mismatch')
    candidate=(directory/filename).read_bytes();sk.read(candidate);schema.asset(target,'target model','.iqm')
    if mapping.get(report['source_model'])!=target:raise schema.Error('model repair changes source mapping')
    expected_texture=report.get('material_authoring',{}).get('output_sha256') if report.get('material_authoring') else None
    if expected_texture and (texture is None or schema.sha(texture)!=expected_texture):
        raise schema.Error('authored body texture differs from its model receipt','ANIM_SOURCE_HASH_MISMATCH')
    if approved:=report.get('admitted_head'):
        if expected:=approved.get('texture_sha256'):
            path=schema.asset(approved['material'],'admitted head material')+'.png'
            if path not in files or capture.digest(files[path])!=expected:
                raise schema.Error('approved Hiro head texture changed','ANIM_SOURCE_HASH_MISMATCH',path)
    old_sha=capture.digest(files[target]);files[target]=candidate
    if material:=report.get('body_material'):
        if texture is None:raise schema.Error('rebuilt body requires its explicit texture')
        schema.asset(material,'rebuilt body material');files[material+'.png']=texture.read_bytes()
        shader=files['scripts/dk3-neural.shader'].decode('utf-8')
        definitions=[material+suffix+'\n{' in shader for suffix in ('@alpha','@bright','@alphabright')]
        if any(definitions) and not all(definitions):raise schema.Error('rebuilt material has incomplete presentation variants')
        if not any(definitions):files['scripts/dk3-neural.shader']=(shader+'\n'+variant_stanzas(material,material+'.png',False)).encode('utf-8')
    model=sk.read(candidate)
    for variant in range(4):
        path=target+f'.{variant}.skin'
        if path in files:
            suffix=('','@alpha','@bright','@alphabright')[variant]
            files[path]=(''.join(name+','+material+suffix+'\n' for name,material,*_ in model.meshes)).encode('utf-8')
    previous.setdefault('cinematic_model_rebuilds',{})[target]=dict(report,previous_model_sha256=old_sha,base_overlay_sha256=overlay_sha,texture_sha256=schema.sha(texture) if texture else None,
        admission_tools={name:schema.sha(Path(__file__).with_name(name)) for name in ('cinematic_model.py','dkm2md3.py')})


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='operation',required=True)
    p=sub.add_parser('rebuild');p.add_argument('recipe',type=Path);p.add_argument('--base-models',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('rebase');p.add_argument('recipe',type=Path);p.add_argument('--base-models',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('package');p.add_argument('--overlay',type=Path,required=True);p.add_argument('--base-models',type=Path,required=True);p.add_argument('--rebuild',type=Path,required=True);p.add_argument('--texture',type=Path);p.add_argument('--target',required=True);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('package-set');p.add_argument('recipe',type=Path);p.add_argument('--overlay',type=Path,required=True);p.add_argument('--base-models',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    args=parser.parse_args()
    try:
        if args.operation=='rebuild':result=rebuild(args.recipe,args.base_models,args.out)
        elif args.operation=='rebase':result=rebase(args.recipe,args.base_models,args.out)
        elif args.operation=='package-set':
            job=schema.load(args.recipe);schema.fields(job,('version','repairs'),('version','repairs'),'model package')
            if job['version']!=1 or not isinstance(job['repairs'],list) or not 1<=len(job['repairs'])<=16:raise schema.Error('bounded version 1 repair set required')
            repairs=[]
            for row in job['repairs']:
                schema.fields(row,('directory','target','texture'),('directory','target'),'model repair')
                repairs.append(dict(directory=local(args.recipe.resolve().parent,row['directory']),target=row['target'],texture=local(args.recipe.resolve().parent,row['texture']) if row.get('texture') else None))
            result=package_models(args.overlay,args.base_models,repairs,args.out)
        else:result=package_model(args.overlay,args.base_models,args.rebuild,args.texture,args.target,args.out)
        print(json.dumps(result,sort_keys=True,allow_nan=False))
    except (schema.Error,ValueError,OSError,KeyError) as error:
        print(json.dumps(dict(passed=False,code=getattr(error,'code','ANIM_MODEL_REBUILD'),message=str(error))),file=sys.stderr);raise SystemExit(1)


if __name__=='__main__':main()
