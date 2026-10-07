#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Admit newly generated character geometry onto a pinned captured IQM rig.

Original body geometry/UVs are excluded. Only the original prop meshes and the
explicit captured skeleton/performance contract are retained. This offline
command never mutates a source, installed package or runtime selector.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import platform
import shutil
import sys
import zipfile

import numpy as np
from PIL import Image

import animation_manifest as schema
from animation_author import fresh, local
from cinematic_model import source_motion, source_body_rows
import cinematic_reconstruction as capture
from neural_assets import align_vectors, read_md3, source_props, split_hidden_props
from neural_monster_skeleton import skeleton
from neural_head import body_below, split_surfaces, pack_weights
from neural_rig import skin_weights
from neural_surface_quality import topology
import skeletal_iqm as sk


def neutral_rig(config: dict) -> tuple[list, list, np.ndarray]:
    schema.fields(config, ('torso', 'arm_l', 'arm_r', 'leg', 'toe'),
                  ('torso', 'arm_l', 'arm_r', 'leg', 'toe'), 'neutral rig')
    for field, count in (('torso', 5), ('arm_l', 3), ('arm_r', 3), ('leg', 3)):
        values=config[field]
        if not isinstance(values,list) or len(values)!=count:
            raise schema.Error('explicit neutral joint landmarks required',field='rig.'+field)
        for point in values:
            for value in schema.vector(point, 'rig.'+field):schema.number(value,-64,64,'rig.'+field)
    schema.vector(config['toe'],'rig.toe')
    names,parents,world=skeleton(config)
    for j,parent in enumerate(parents):
        if parent>=0 and np.linalg.norm(world[j,:3,3]-world[parent,:3,3])<.1:
            raise schema.Error('degenerate neutral segment','ANIM_INVALID_BIND',names[j])
    return names,parents,world


def segment_transforms(names: list, neutral: np.ndarray, target_names: list,
                       target: np.ndarray) -> np.ndarray:
    """Map measured neutral segments to the captured reference without shearing.

    Bone-local axial scale handles measured length differences. Radial scale
    stays one, so the generated arm/leg thickness is not silently collapsed.
    """
    if not np.isfinite(neutral).all() or not np.isfinite(target).all():
        raise schema.Error('nonfinite reference rig','ANIM_NONFINITE_TRANSFORM')
    if neutral.shape!=(len(names),4,4) or target.shape!=(len(target_names),4,4) or len(set(names))!=len(names) or len(set(target_names))!=len(target_names):
        raise schema.Error('invalid reference hierarchy','ANIM_INVALID_BIND')
    missing=set(names)-set(target_names)
    if missing:raise schema.Error('missing captured joint','ANIM_UNKNOWN_BONE',sorted(missing)[0])
    transforms=np.broadcast_to(np.eye(4),(len(names),4,4)).copy()
    ends=dict(pelvis='spine',spine='chest',chest='neck',neck='head')
    for side in ('l','r'):
        ends.update({a+'_'+side:b+'_'+side for a,b in
                     (('clavicle','upperarm'),('upperarm','forearm'),('forearm','hand'),
                      ('thigh','shin'),('shin','foot'),('foot','toe'))})
    for j,name in enumerate(names):
        if name not in target_names:raise schema.Error('missing captured joint','ANIM_UNKNOWN_BONE',name)
        target_j=target_names.index(name);start=neutral[j,:3,3];finish=target[target_j,:3,3]
        rotation=np.eye(3);stretch=np.eye(3)
        if name in ends:
            child=ends[name]
            old=neutral[names.index(child),:3,3]-start
            new=target[target_names.index(child),:3,3]-finish
            length=np.linalg.norm(old);ratio=np.linalg.norm(new)/max(length,1e-10)
            if length<.1 or not .25<=ratio<=4:
                raise schema.Error('implausible reference segment','ANIM_INVALID_BIND',name)
            direction=old/length
            rotation=align_vectors(old[None],new[None])[0]
            stretch+=(ratio-1)*np.outer(direction,direction)
        elif name=='head':rotation=target[target_j,:3,:3]
        elif name.startswith(('hand_','fingers_','thumb_')):
            side=name[-1];wrist='hand_'+side;forearm='forearm_'+side
            old=neutral[names.index(wrist),:3,3]-neutral[names.index(forearm),:3,3]
            new=target[target_names.index(wrist),:3,3]-target[target_names.index(forearm),:3,3]
            rotation=align_vectors(old[None],new[None])[0]
        transforms[j,:3,:3]=rotation@stretch
        transforms[j,:3,3]=finish-transforms[j,:3,:3]@start
    return transforms


def deform(points: np.ndarray, normals: np.ndarray, joints: np.ndarray,
           weights: np.ndarray, transforms: np.ndarray) -> tuple[np.ndarray,np.ndarray]:
    blended=np.zeros((len(points),3,3));positions=np.zeros_like(points,dtype=float)
    for slot in range(4):
        selected=transforms[joints[:,slot]];amount=weights[:,slot]/255.
        positions+=(np.einsum('vij,vj->vi',selected[:,:3,:3],points)+selected[:,:3,3])*amount[:,None]
        blended+=selected[:,:3,:3]*amount[:,None,None]
    cofactor=np.stack((np.cross(blended[:,:,1],blended[:,:,2]),
                       np.cross(blended[:,:,2],blended[:,:,0]),
                       np.cross(blended[:,:,0],blended[:,:,1])),axis=-1)
    normal=np.einsum('vij,vj->vi',cofactor,normals)
    lengths=np.linalg.norm(normal,axis=1)
    if not np.isfinite(positions).all() or np.any(lengths<1e-8):
        raise schema.Error('degenerate generated deformation','ANIM_NONFINITE_TRANSFORM')
    return positions,normal/lengths[:,None]


def head_ownership(model: sk.Model, settings: dict) -> dict:
    """Keep the generated skull coherent while blending only the lower neck.

    Segment distance alone assigns the jaw and hair to neck/clavicle bones.
    Those bones cannot reproduce the captured head's reference yaw. Explicit
    neutral-space regions must be declared by the author; no atlas repainting
    or geometric cutting is involved.
    """
    schema.fields(settings,('neck_min_z','head_min_z','half_width'),
                  ('neck_min_z','head_min_z','half_width'),'head ownership')
    low=schema.number(settings['neck_min_z'],18,26,'neck_min_z')
    high=schema.number(settings['head_min_z'],22,30,'head_min_z')
    width=schema.number(settings['half_width'],1,7,'half_width')
    if high-low<.5:raise schema.Error('head transition must span at least .5 units','ANIM_INVALID_RANGE')
    points=model.arrays[0]
    if points.ndim!=2 or points.shape[1]!=3 or not np.isfinite(points).all():
        raise schema.Error('invalid head region points','ANIM_NONFINITE_TRANSFORM')
    if any(name not in model.names for name in ('head','neck')):
        raise schema.Error('head ownership requires head and neck','ANIM_UNKNOWN_BONE')
    region=(points[:,2]>=high)|((points[:,2]>low)&(np.abs(points[:,1])<width))
    middle=(low+high)*.5
    t=np.clip((points[region,2]-middle)/(high-middle),0,1);t=t*t*(3-2*t)
    lower=np.clip((points[region,2]-low)/(middle-low),0,1);lower=lower*lower*(3-2*lower)
    values=np.column_stack((t,(1-t)*lower,(1-t)*(1-lower),np.zeros(len(t))))
    if 'chest' not in model.names:
        # Small standalone rigs without a chest retain the neck transition.
        values[:,1]+=values[:,2];values[:,2]=0
    weights=np.rint(values*255).astype(int)
    weights[np.arange(len(weights)),weights.argmax(axis=1)]+=255-weights.sum(axis=1)
    weights=weights.astype('u1')
    model.arrays[4][region]=[model.names.index('head'),model.names.index('neck'),model.names.index('chest') if 'chest' in model.names else 0,0]
    model.arrays[5][region]=weights
    return dict(settings=settings,region_vertices=int(region.sum()),rigid_head_vertices=int((weights[:,0]==255).sum()))


def clean_geometry(arrays: dict, triangles: np.ndarray, material: str) -> tuple[dict,list,np.ndarray,dict]:
    """Remove zero-area export remnants and repair their zero corner normals."""
    points=arrays[0];face=-np.cross(points[triangles[:,1]]-points[triangles[:,0]],
                                  points[triangles[:,2]]-points[triangles[:,0]])
    good=np.linalg.norm(face,axis=1)>1e-10
    if not good.any():raise schema.Error('generated surface has no nondegenerate triangles')
    retained=triangles[good];face=face[good]
    normals=arrays[2].copy();missing=np.linalg.norm(normals,axis=1)<1e-8
    summed=np.zeros_like(normals)
    for slot in range(3):np.add.at(summed,retained[:,slot],face)
    _,first,weld=np.unique(np.round(points,6),axis=0,return_index=True,return_inverse=True)
    shared=np.zeros((len(first),3));np.add.at(shared,weld,summed);summed=shared[weld]
    length=np.linalg.norm(summed,axis=1);usable=missing&(length>1e-8)
    normals[usable]=summed[usable]/length[usable,None]
    rows=[]
    for tri,normal in zip(retained,face):
        fallback=normal/np.linalg.norm(normal);row=[]
        for v in tri:
            n=normals[v] if np.linalg.norm(normals[v])>=1e-8 else fallback
            row.append({0:points[v],1:arrays[1][v],2:n,4:np.zeros(4,dtype='u1'),5:np.array([255,0,0,0],dtype='u1')})
        rows.append(row)
    result,tri,meshes=split_surfaces(rows,material,'generated_body')
    return result,meshes,tri,dict(removed_degenerate_triangles=int((~good).sum()),repaired_zero_normals=int(missing.sum()))


def admitted_head_rows(model: sk.Model, material: str, minimum_z: float | None) -> list:
    """Retain the independent head, clipping its old wardrobe collar explicitly."""
    selected=copy.deepcopy(model)
    selected.triangles=np.concatenate([model.triangles[ft:ft+nt] for _,mat,_,_,ft,nt in model.meshes if mat==material])
    selected.arrays[0][:,2]*=-1;selected.arrays[2][:,2]*=-1
    rows=body_below(selected,-minimum_z if minimum_z is not None else 1000,retain_upper_body=False)
    rows=[[{key:value.copy() for key,value in corner.items()} for corner in row] for row in rows]
    for row in rows:
        for corner in row:corner[0][2]*=-1;corner[2][2]*=-1
    return rows


def neutral_admitted_head(model: sk.Model, rotation: np.ndarray, neck_blend: list, translation: list) -> sk.Model:
    """Undo the captured reference orientation without changing facial shape/UVs."""
    if rotation.shape!=(3,3) or not np.isfinite(rotation).all() or not np.allclose(rotation.T@rotation,np.eye(3),atol=1e-6) or np.linalg.det(rotation)<.999:
        raise schema.Error('invalid admitted head reference rotation','ANIM_INVALID_BIND')
    result=copy.deepcopy(model);origin=sk.matrices(model.bind,model.parents)[model.names.index('head'),:3,3]
    result.arrays[0]=(model.arrays[0]-origin)@rotation+origin+np.asarray(schema.vector(translation,'head attachment translation'))
    result.arrays[2]=model.arrays[2]@rotation
    # The approved face is rigid. Only the neck below its jaw blends with the
    # anatomical neck/chest; obsolete vertex-model correctives do not skin it.
    result.arrays[4][:]=[model.names.index('head'),0,0,0];result.arrays[5][:]=[255,0,0,0]
    low,high=schema.vector(neck_blend,'admitted neck blend',2)
    points=result.arrays[0].copy();result.arrays[0][:,1]-=origin[1]
    head_ownership(result,dict(neck_min_z=low,head_min_z=high,half_width=7.))
    result.arrays[0]=points
    return result


def collar_ownership(body: sk.Model, colors: np.ndarray, interval: list) -> dict:
    """Keep the cut gi's cotton/lapels on the torso, before adding the head."""
    low,high=schema.vector(interval,'collar blend heights',2)
    if not 15<=low<high<=23:raise schema.Error('collar ownership needs bounded torso heights')
    if colors.shape!=(len(body.arrays[0]),3) or not np.isfinite(colors).all() or np.any((colors<0)|(colors>1)):
        raise schema.Error('invalid collar material samples')
    skin=((colors[:,0]-colors[:,1])>.05)&((colors[:,0]-colors[:,2])>.1)
    factor=np.clip((body.arrays[0][:,2]-low)/(high-low),0,1);factor=factor*factor*(3-2*factor)
    head=body.names.index('head');neck=body.names.index('neck');chest=body.names.index('chest')
    weight=np.sum(body.arrays[5]*np.isin(body.arrays[4],[head,neck]),axis=1)
    selected=np.flatnonzero((~skin)&(factor>0)&(weight>0))
    for v in selected:
        full=np.zeros(len(body.names));np.add.at(full,body.arrays[4][v],body.arrays[5][v]/255.)
        amount=full[[head,neck]].sum()*factor[v];full[[head,neck]]*=1-factor[v];full[chest]+=amount
        body.arrays[4][v],body.arrays[5][v]=pack_weights(full)
    return dict(vertices=int(len(selected)),blend_heights=interval,scope='cut generated body only; approved head excluded')


def neck_boundary(model: sk.Model, height: float, center: np.ndarray) -> list[dict]:
    """Select a closed cut boundary by an explicit, pinned anatomical landmark."""
    points=model.arrays[0]
    unique,first,inverse=np.unique(np.round(points,4),axis=0,return_index=True,return_inverse=True)
    triangles=inverse[model.triangles]
    edges=np.sort(np.concatenate((triangles[:,[0,1]],triangles[:,[1,2]],triangles[:,[2,0]])),axis=1)
    edges,count=np.unique(edges,axis=0,return_counts=True)
    edges=edges[(count==1)&np.all(np.abs(unique[edges,2]-height)<.001,axis=1)]
    graph={}
    for a,b in edges:
        graph.setdefault(int(a),set()).add(int(b));graph.setdefault(int(b),set()).add(int(a))
    seen=set();loops=[]
    for start in sorted(graph):
        if start in seen:continue
        pending=[start];component=set()
        while pending:
            vertex=pending.pop()
            if vertex in component:continue
            component.add(vertex);pending.extend(graph[vertex]-component)
        seen.update(component)
        if not 8<=len(component)<=4096 or any(len(graph[v])!=2 for v in component):continue
        order=[min(component)];previous=None
        while True:
            following=min(graph[order[-1]]-({previous} if previous is not None else set()))
            if following==order[0]:break
            if following in order:raise schema.Error('invalid neck boundary cycle')
            previous=order[-1];order.append(following)
        if len(order)!=len(component):raise schema.Error('incomplete neck boundary')
        distance=float(np.linalg.norm(unique[order,:2].mean(axis=0)-center))
        loops.append((distance,order))
    if not loops or min(row[0] for row in loops)>.5:raise schema.Error('declared neck opening has no nearby closed boundary','ANIM_ATTACHMENT_ERROR')
    _,order=min(loops,key=lambda row:row[0])
    p=unique[order,:2];q=np.roll(p,-1,axis=0)
    if np.sum(p[:,0]*q[:,1]-p[:,1]*q[:,0])<0:order=order[::-1]
    angle=np.mod(np.arctan2(unique[order,1]-center[1],unique[order,0]-center[0]),2*np.pi)
    start=int(np.argmin(angle));order=order[start:]+order[:start]
    return [{key:model.arrays[key][first[v]].copy() for key in (0,1,2,4,5)} for v in order]


def join_neck(body: sk.Model, head: sk.Model, lower: float, upper: float, center: list) -> tuple[list,dict]:
    """Bridge both complete boundaries; preserve existing geometry and weights."""
    origin=np.asarray(schema.vector(center,'neck join center',2))
    if not .05<=upper-lower<=2:raise schema.Error('neck join must span .05..2 units')
    bottom=neck_boundary(body,lower,origin);top=neck_boundary(head,upper,origin)
    def parameters(loop):
        p=np.array([corner[0] for corner in loop]);length=np.linalg.norm(np.roll(p,-1,axis=0)-p,axis=1)
        if np.any(length<1e-7):raise schema.Error('collapsed neck boundary edge')
        return np.r_[0,np.cumsum(length)]/length.sum()
    ba,ta=parameters(bottom),parameters(top)
    # The narrow bridge uses the approved neck atlas. Its lower edge inherits
    # body positions/weights exactly, with the nearest approved neck texel.
    for b in bottom:
        nearest=min(top,key=lambda t:np.linalg.norm(t[0][:2]-b[0][:2]));b[1]=nearest[1].copy()
    rows=[];i=j=0
    while i<len(bottom) or j<len(top):
        b=bottom[i%len(bottom)];t=top[j%len(top)]
        if i<len(bottom) and (j==len(top) or ba[i+1]<ta[j+1]):
            row=[b,bottom[(i+1)%len(bottom)],t];i+=1
        else:row=[b,top[(j+1)%len(top)],t];j+=1
        normal=np.cross(row[1][0]-row[0][0],row[2][0]-row[0][0]);radial=np.mean([c[0][:2] for c in row],axis=0)-origin
        if np.linalg.norm(normal)<1e-8:raise schema.Error('degenerate neck bridge','ANIM_ATTACHMENT_ERROR')
        if normal[:2]@radial>0:row=[row[0],row[2],row[1]] # IQM is clockwise.
        rows.append(row)
    return rows,dict(body_boundary_vertices=len(bottom),head_boundary_vertices=len(top),triangles=len(rows),center=center,lower=lower,upper=upper)


def generated_geometry(actor: Path, material: str) -> tuple[dict,list,np.ndarray,dict]:
    paths=[actor/name for name in ('concept.png','model.glb','trellis.json','geometry.npz','geometry.json','body.png')]
    if any(not p.is_file() or p.stat().st_size>64*1024*1024 for p in paths):
        raise schema.Error('generated input missing or exceeds 64 MiB')
    receipt=schema.load(actor/'trellis.json');geometry=schema.load(actor/'geometry.json')
    if receipt.get('generator')!='microsoft/TRELLIS.2-4B' or receipt.get('input_sha256')!=schema.sha(actor/'concept.png') or receipt.get('glb_sha256')!=schema.sha(actor/'model.glb'):
        raise schema.Error('generated image/mesh provenance mismatch','ANIM_SOURCE_HASH_MISMATCH')
    if geometry.get('topology',{}).get('source_glb_sha256')!=schema.sha(actor/'model.glb'):
        raise schema.Error('conversion refers to another mesh','ANIM_SOURCE_HASH_MISMATCH')
    with Image.open(actor/'body.png') as image:
        if image.format!='PNG' or image.size!=(4096,4096):raise schema.Error('4096px generated PNG atlas required')
    with zipfile.ZipFile(actor/'geometry.npz') as archive:
        if len(archive.infolist())!=4 or sum(row.file_size for row in archive.infolist())>64*1024*1024:
            raise schema.Error('generated geometry archive exceeds limits')
    with np.load(actor/'geometry.npz',allow_pickle=False) as data:
        if set(data.files)!={'0','1','2','triangles'}:raise schema.Error('unexpected generated arrays')
        arrays={k:data[str(k)].copy() for k in (0,1,2)};tri=data['triangles'].copy()
    count=len(arrays[0])
    if not 4<=count<=250000 or not 1<=len(tri)<=100000 or tri.shape!=(len(tri),3) or tri.dtype.kind not in 'iu' or tri.min()<0 or tri.max()>=count:
        raise schema.Error('generated geometry exceeds structural limits')
    for k,width in ((0,3),(1,2),(2,3)):
        if arrays[k].shape!=(count,width) or arrays[k].dtype.kind not in 'fi' or not np.isfinite(arrays[k]).all():
            raise schema.Error('invalid generated vertex array','ANIM_NONFINITE_TRANSFORM',str(k))
    surfaces=geometry.get('surfaces')
    if not isinstance(surfaces,list) or not 1<=len(surfaces)<=1024:raise schema.Error('bounded generated surfaces required')
    meshes=[];fv=ft=0
    for row in surfaces:
        if not isinstance(row,list) or len(row)!=6:raise schema.Error('invalid converted surface')
        name,_,first,nv,start,nt=row;schema.text(name,'surface')
        for value in (first,nv,start,nt):schema.number(value,0,250000,'surface extent',integer=True)
        if first!=fv or start!=ft or not 1<=nv<1000 or not 1<=nt<2000:raise schema.Error('noncontiguous or oversized converted surface')
        meshes.append((name,material,first,nv,start,nt));fv+=nv;ft+=nt
    if fv!=count or ft!=len(tri):raise schema.Error('converted surfaces do not cover geometry')
    return arrays,meshes,tri,{p.name:schema.sha(p) for p in paths}


def neutral_geometry_sha(arrays: dict, meshes: list, triangles: np.ndarray) -> str:
    """Hash the material input without letting tangent serialization mutate it."""
    import hashlib
    bind=np.array([[0.,0,0,0,0,0,1,1,1,1]])
    scratch={key:value.copy() for key,value in arrays.items()}
    return hashlib.sha256(sk.write(sk.Model(scratch,meshes,triangles,['pelvis'],[-1],bind,bind[None]))).hexdigest()


def closed_geometry(directory: Path, raw: dict, meshes: list, triangles: np.ndarray,
                    inputs: dict, material: str, settings: dict) -> tuple[dict,list,np.ndarray,dict]:
    """Admit a surface repair only when its source is this exact generated mesh."""
    receipt=schema.load(directory/'surface-closure.json')
    bind=np.array([[0.,0,0,0,0,0,1,1,1,1]])
    expected=sk.write(sk.Model(raw,meshes,triangles,['pelvis'],[-1],bind,bind[None]))
    import hashlib
    if receipt.get('source_iqm_sha256')!=hashlib.sha256(expected).hexdigest() or receipt.get('source_texture_sha256')!=inputs['body.png']:
        raise schema.Error('surface repair belongs to another generated body','ANIM_SOURCE_HASH_MISMATCH')
    path=directory/'model.iqm'
    if path.stat().st_size>32*1024*1024 or schema.sha(path)!=receipt.get('output_iqm_sha256') or schema.sha(directory/'body.png')!=receipt.get('output_texture_sha256'):
        raise schema.Error('surface repair output changed','ANIM_SOURCE_HASH_MISMATCH')
    schema.fields(settings,('voxel','thickness','seal_radius','triangles','fill_volumes'),('voxel','thickness','seal_radius','triangles'),'surface closure')
    if any(receipt.get(k)!=settings[k] for k in ('voxel','thickness')) or receipt.get('triangle_budget')!=settings['triangles'] or receipt.get('surface_sealing',{}).get('radius')!=settings['seal_radius']:
        raise schema.Error('surface repair differs from declared settings')
    if settings.get('fill_volumes') and receipt.get('local_anatomy_volumes',{}).get('volumes')!=anatomy_volumes(raw[0],settings['fill_volumes']):
        raise schema.Error('surface repair anatomy differs from recipe')
    model=sk.read(path.read_bytes())
    if model.names!=['pelvis'] or model.parents!=[-1] or not np.array_equal(model.bind,bind) or not np.array_equal(model.frames,bind[None]):
        raise schema.Error('generated geometry repair changed its neutral rig')
    quality=topology(model)
    if any(quality.values()):raise schema.Error('generated surface is not closed: '+str(quality),'ANIM_INVALID_TOPOLOGY')
    with Image.open(directory/'body.png') as image:
        if image.format!='PNG' or image.size!=(4096,4096):raise schema.Error('closed body requires 4096px PNG')
    arrays={k:model.arrays[k].copy() for k in (0,1,2)}
    arrays[4]=np.zeros((len(arrays[0]),4),dtype='u1');arrays[5]=np.tile([255,0,0,0],(len(arrays[0]),1))
    meshes=[(name,material,*extent) for name,_,*extent in model.meshes]
    evidence=dict(receipt_sha256=schema.sha(directory/'surface-closure.json'),model_sha256=schema.sha(path),
                  source_iqm_sha256=receipt['source_iqm_sha256'],texture_sha256=schema.sha(directory/'body.png'),topology=quality,settings=settings)
    return arrays,meshes,model.triangles.copy(),evidence


def anatomy_volumes(points: np.ndarray, volumes: list) -> list:
    if not isinstance(volumes,list) or not 1<=len(volumes)<=16:raise schema.Error('bounded local anatomy volumes required')
    height=np.ptp(points[:,2]);low=points[:,2].min();cy=(points[:,1].min()+points[:,1].max())*.5
    if not 10<=height<=200:raise schema.Error('implausible generated height')
    z=(points[:,2]-low)*56/height-24;torso=points[(z>8)&(z<20)&(np.abs(points[:,1]-cy)<height/10)]
    if len(torso)<8:raise schema.Error('neutral torso is unobservable')
    origin=np.array([np.median(torso[:,0]),cy,low+24*height/56]);result=[]
    for volume in volumes:
        schema.fields(volume,('center','radii'),('center','radii'),'local anatomy volume')
        center=schema.vector(volume['center'],'volume center');radii=schema.vector(volume['radii'],'volume radii')
        for value in center:schema.number(value,-32,32,'volume center')
        for value in radii:schema.number(value,.1,12,'volume radius')
        result.append(dict(center=(np.array(center)*height/56+origin).tolist(),radii=(np.array(radii)*height/56).tolist()))
    return result


def prepare_closure(recipe_path: Path, actor: Path, output: Path) -> dict:
    """Create an immutable, geometry-only input for the existing Blender closer."""
    recipe=schema.load(recipe_path)
    if recipe.get('version')!=1:raise schema.Error('generated character version must be 1')
    material=schema.asset(recipe['body_material'],'body material')
    if not material.startswith('models/neural/'):raise schema.Error('body outside cosmetic namespace','ANIM_INVALID_PATH')
    arrays,meshes,tri,inputs=generated_geometry(actor,material)
    arrays,meshes,tri,cleanup=clean_geometry(arrays,tri,material)
    bind=np.array([[0.,0,0,0,0,0,1,1,1,1]])
    model=sk.Model(arrays,meshes,tri,['pelvis'],[-1],bind,bind[None])
    directory=fresh(output,True);destination=directory/'model.iqm'
    destination.write_bytes(sk.write(model));shutil.copy2(actor/'body.png',directory/'body.png')
    schema.write_json(directory/'source.json',dict(actor=dict(kind='character',slug=recipe['character'])))
    if volumes:=recipe.get('surface_closure',{}).get('fill_volumes'):
        schema.write_json(directory/'anatomy-volumes.json',anatomy_volumes(arrays[0],volumes))
    result=dict(passed=True,recipe_sha256=schema.sha(recipe_path),generated_inputs=inputs,surface_cleanup=cleanup,
                output_sha256=schema.sha(destination),texture_sha256=schema.sha(directory/'body.png'),
                tool_sha256=schema.sha(Path(__file__)))
    schema.write_json(directory/'preparation.json',result);return result


def rig(recipe_path: Path, actor: Path, template_path: Path, base: Path, output: Path,
        closed: Path | None = None, materials: Path | None = None) -> dict:
    recipe=schema.load(recipe_path)
    schema.fields(recipe,('version','character','body_material','template_sha256','rig','generation','references','motion','provenance','review','head','surface_closure','material_authoring','head_ownership','texture_policy','head_reference_basis','skin_transform_policy','closed_fists'),
                  ('version','character','body_material','template_sha256','rig','generation','references','motion','provenance','review'),'generated character')
    if recipe['version']!=1:raise schema.Error('generated character version must be 1')
    schema.text(recipe['character'],'character');material=schema.asset(recipe['body_material'],'body material')
    if not material.startswith('models/neural/'):raise schema.Error('generated body outside cosmetic namespace','ANIM_INVALID_PATH')
    if template_path.stat().st_size>32*1024*1024 or schema.sha(template_path)!=recipe['template_sha256']:
        raise schema.Error('captured template differs','ANIM_SOURCE_HASH_MISMATCH')
    source=sk.read(template_path.read_bytes());arrays,meshes,tri,inputs=generated_geometry(actor,material)
    arrays,meshes,tri,cleanup=clean_geometry(arrays,tri,material)
    closure=None
    if closed:
        if 'surface_closure' not in recipe:raise schema.Error('surface repair needs declared settings')
        arrays,meshes,tri,closure=closed_geometry(closed,arrays,meshes,tri,inputs,material,recipe['surface_closure'])
    elif 'surface_closure' in recipe:raise schema.Error('recipe requires its closed body input')
    authored_materials=None
    if materials:
        policy=recipe.get('material_authoring')
        if policy not in ('direct_semantic_surface_bake','generated_surface_transfer','per_texel_generated_atlas') or (policy!='per_texel_generated_atlas' and not closure):raise schema.Error('materials need declared surface authoring')
        if policy=='per_texel_generated_atlas' and closure:raise schema.Error('per-texel source bake must retain source UVs')
        receipt=schema.load(materials/'materials.json')
        if policy=='per_texel_generated_atlas':
            expected_input=neutral_geometry_sha(arrays,meshes,tri)
            tool=Path(__file__).with_name('generated_atlas_bake.py')
            if receipt.get('method')!=policy or receipt.get('source_texture_sha256')!=inputs['body.png'] or receipt.get('vertex_colour_bake') is not False:
                raise schema.Error('per-texel material differs from generated atlas','ANIM_SOURCE_HASH_MISMATCH')
        else:expected_input=closure['model_sha256'];tool=Path(__file__).with_name('generated_materials.py')
        if not receipt.get('passed') or receipt.get('input_sha256')!=expected_input or receipt.get('output_sha256')!=schema.sha(materials/'body.png') or receipt.get('tool_sha256')!=schema.sha(tool):
            raise schema.Error('authored material source/output/tool mismatch','ANIM_SOURCE_HASH_MISMATCH')
        if policy=='generated_surface_transfer' and (receipt.get('method')!=policy or receipt.get('source_iqm_sha256')!=closure['source_iqm_sha256'] or receipt.get('source_texture_sha256')!=inputs['body.png']):
            raise schema.Error('material transfer differs from generated source','ANIM_SOURCE_HASH_MISMATCH')
        with Image.open(materials/'body.png') as image:
            if image.format!='PNG' or image.size!=(4096,4096):raise schema.Error('authored materials require 4096px PNG')
        authored_materials=dict(receipt,receipt_sha256=schema.sha(materials/'materials.json'))
    elif recipe.get('material_authoring'):raise schema.Error('recipe requires its authored materials')
    if policy:=recipe.get('texture_policy'):
        if policy not in ('generated_atlas','per_texel_generated_atlas'):
            raise schema.Error('generated_atlas policy requires the unchanged generated texture')
        if closure:raise schema.Error('generated_atlas policy cannot use remeshed UVs')
        if policy=='generated_atlas':
            if materials:raise schema.Error('generated_atlas policy requires unchanged source texture')
            authored_materials=dict(method='preserved_generated_atlas',output_sha256=inputs['body.png'],
                                   source_glb_sha256=inputs['model.glb'],source_texture_sha256=inputs['body.png'])
        elif not materials or recipe.get('material_authoring')!=policy:
            raise schema.Error('per_texel_generated_atlas requires its admitted bake')
    if not isinstance(recipe['generation'],dict):raise schema.Error('generation must be an object')
    if expected:=recipe['generation'].get('surface_extraction'):
        schema.fields(expected,('band','projection','triangles','texture_size','source_sha256','checkpoint_sha256'),
                      ('band','projection','triangles','texture_size','source_sha256','checkpoint_sha256'),'surface extraction')
        actual=schema.load(actor/'trellis.json').get('extraction',{})
        if any(actual.get(key)!=value for key,value in expected.items()) or actual.get('tool_sha256')!=schema.sha(Path(__file__).with_name('neural_character_export.py')):
            raise schema.Error('generated surface extraction differs from recipe','ANIM_SOURCE_HASH_MISMATCH')
        if not schema.load(actor/'geometry.json').get('topology',{}).get('preserve_topology'):
            raise schema.Error('converted surface must preserve generator topology')
    names,parents,neutral=neutral_rig(recipe['rig'])
    height=np.ptp(arrays[0][:,2]);minimum=arrays[0][:,2].min()
    if not 10<=height<=200:raise schema.Error('implausible generated height')
    # Normalize once to the declared rig convention, preserving all proportions.
    center_y=(arrays[0][:,1].min()+arrays[0][:,1].max())*.5
    height_z=(arrays[0][:,2]-minimum)*56/height-24
    torso=arrays[0][(height_z>8)&(height_z<20)&(np.abs(arrays[0][:,1]-center_y)<height/10)]
    if len(torso)<8:raise schema.Error('generated torso is unobservable','ANIM_UNOBSERVABLE_MARKER')
    offset=np.array([np.median(torso[:,0]),center_y,minimum+24*height/56])
    arrays[0]=(arrays[0]-offset)*56/height
    neutral_model=sk.Model(arrays,meshes,tri,names,parents,sk.channels(neutral,parents),sk.channels(neutral,parents)[None])
    skin_weights(neutral_model,'hiro',neutral,landmarks=recipe['rig'])
    head_weights=head_ownership(neutral_model,recipe['head_ownership']) if recipe.get('head_ownership') else None
    target=sk.matrices(source.bind,source.parents)
    profile_path=local(recipe_path.resolve().parent,recipe['motion']['capture_profile']);profile=schema.load(profile_path)
    legacy=schema.asset(profile['source_model'],'source model','.dkm')
    with zipfile.ZipFile(base) as archive:
        blob=capture.archive_read(archive,legacy+'.md3',32*1024*1024)
        metadata=json.loads(capture.archive_read(archive,legacy+'.json',4*1024*1024))
    if capture.digest(blob)!=profile['source_md3_sha256']:raise schema.Error('capture source differs','ANIM_SOURCE_HASH_MISMATCH')
    surfaces=split_hidden_props(source_props(read_md3(blob)[0],metadata))
    surface=next(s for s in surfaces if s['name']==profile['surface'] and not s.get('prop'))
    observed=source_motion(surface,profile)
    reference=target.copy()
    reference_basis=recipe.get('head_reference_basis','source')
    if reference_basis not in ('source','neutral'):raise schema.Error('head reference must be source or neutral')
    if reference_basis=='source':reference[source.names.index('head'),:3,:3]=observed.rest[observed.names.index('head'),:3,:3]
    transform=segment_transforms(names,neutral,source.names,reference)
    arrays[0],arrays[2]=deform(arrays[0],arrays[2],arrays[4],arrays[5],transform)
    # Transfer the whole generated hand to its measured source palm center.
    # The old body is used as neither a vertex target nor a texture source.
    hand_alignment={}
    for side in ('l','r'):
        name='hand_'+side;group=[names.index(n+side) for n in ('hand_','fingers_','thumb_')]
        ownership=np.sum(arrays[5]*np.isin(arrays[4],group),axis=1)/255.
        selected=ownership>=.75
        if not selected.any():raise schema.Error('generated hand unobservable','ANIM_UNOBSERVABLE_MARKER',name)
        anchor=target[source.names.index(name),:3,3]
        current=arrays[0][selected].mean(axis=0)
        wanted=surface['points'][profile['reference_frame'],profile['markers'][name]['vertices']].mean(axis=0)
        rotation=align_vectors((current-anchor)[None],(wanted-anchor)[None])[0]
        posed=(arrays[0]-anchor)@rotation.T+anchor
        shift=wanted-posed[selected].mean(axis=0);blend=np.clip((ownership-.1)/.65,0,1)
        arrays[0]+=(posed+shift-arrays[0])*blend[:,None]
        arrays[2]+=(arrays[2]@rotation.T-arrays[2])*blend[:,None]
        arrays[2]/=np.linalg.norm(arrays[2],axis=1,keepdims=True)
        hand_alignment[name]=dict(source_center=wanted.tolist(),neutral_center=current.tolist(),translation=shift.tolist())
    soles={}
    for side in ('l','r'):
        foot='foot_'+side;group=[names.index(foot),names.index('toe_'+side)]
        ownership=np.sum(arrays[5]*np.isin(arrays[4],group),axis=1)/255.
        selected=ownership>=.5
        if not selected.any():raise schema.Error('generated foot unobservable','ANIM_UNOBSERVABLE_MARKER',foot)
        vertices=profile['markers'][foot]['vertices']+profile['markers']['toe_'+side]['vertices']
        wanted=float(surface['points'][profile['reference_frame'],vertices,2].min())
        current=float(arrays[0][selected,2].min());ankle=target[source.names.index(foot),2,3]
        blend=np.clip((ankle-arrays[0][:,2])/max(ankle-current,.1),0,1)
        arrays[0][selected,2]+=(wanted-current)*blend[selected]
        rigid=selected&(arrays[0][:,2]<ankle-.8)
        arrays[4][rigid]=[names.index(foot),0,0,0];arrays[5][rigid]=[255,0,0,0]
        soles[side]=dict(generated_height=current,observed_height=wanted,maximum_correction=wanted-current)
    # Generated surface regions use the explicitly observed corrective channels.
    skin_policy=recipe.get('skin_transform_policy','source_correctives')
    if skin_policy not in ('source_correctives','anatomical'):raise schema.Error('unknown skin transform policy')
    closed_fists=recipe.get('closed_fists',False)
    if type(closed_fists) is not bool:raise schema.Error('closed_fists must be boolean')
    mapping=[]
    for name in names:
        corrected='deform_'+name
        if name.startswith(('fingers_','thumb_')):corrected='deform_hand_'+name[-1]
        anatomical='hand_'+name[-1] if closed_fists and name.startswith(('fingers_','thumb_')) else name
        mapping.append(source.names.index(corrected if skin_policy=='source_correctives' and corrected in source.names else anatomical))
    arrays[4]=np.asarray(mapping)[arrays[4]]
    candidate=copy.deepcopy(source);candidate.arrays=arrays;candidate.meshes=meshes;candidate.triangles=tri
    if reference_basis=='neutral':
        from animation_motion import share_neck_turn
        motion_recipe=schema.load(local(recipe_path.resolve().parent,recipe['motion']['retarget_profile']))
        if motion_recipe.get('absolute_rotations',{}).get('head')!={'forward':[1,0,0],'up':[0,0,1]}:
            raise schema.Error('neutral head requires measured absolute +X-forward/+Z-up retargeting')
        poses=sk.matrices(source.frames,source.parents)
        for bone in ('head','deform_head'):
            if bone in source.names:poses[:,source.names.index(bone),:3,:3]=poses[:,source.names.index(bone),:3,:3]@observed.rest[observed.names.index('head'),:3,:3]
        amount=motion_recipe.get('neck_turn_weight',0.)
        share_neck_turn(poses,source.names,amount)
        if all(n in source.names for n in ('deform_neck','deform_head')):
            pair=poses[:,[source.names.index('deform_neck'),source.names.index('deform_head')]].copy()
            share_neck_turn(pair,['neck','head'],amount);poses[:,source.names.index('deform_neck')]=pair[:,0]
        candidate.frames=sk.channels(poses,source.parents)
    head_receipt=None
    if 'head' in recipe:
        head=recipe['head'];schema.fields(head,('material','neck_cut','minimum_z','neck_blend','texture_sha256','translation','join_center','collar_blend'),('material','neck_cut'),'admitted head')
        head_material=schema.asset(head['material'],'head material');cut=schema.number(head['neck_cut'],18,26,'neck cut')
        if head_material==material:raise schema.Error('head material must differ from new body material')
        head_meshes=[row for row in source.meshes if row[1]==head_material]
        if not head_meshes or any(row[0].startswith('prop_') for row in head_meshes):raise schema.Error('pinned template has no admitted head')
        rows=body_below(candidate,cut,retain_upper_body=True) if skin_policy=='anatomical' else source_body_rows(candidate,cut)
        candidate.arrays,candidate.triangles,candidate.meshes=split_surfaces(rows,material,'generated_gi')
        collar=None
        if 'collar_blend' in head:
            from generated_materials import sample_uv_rgb
            texture=materials/'body.png' if materials else actor/'body.png'
            with Image.open(texture) as image:colors=sample_uv_rgb(np.asarray(image.convert('RGB')),candidate.arrays[1])
            collar=collar_ownership(candidate,colors,head['collar_blend'])
        lower=schema.number(head['minimum_z'],20,24,'head minimum_z') if 'minimum_z' in head else None
        if reference_basis=='neutral' and 'neck_blend' not in head:raise schema.Error('neutral admitted head requires explicit neck blend bounds')
        if 'texture_sha256' in head and (not isinstance(head['texture_sha256'],str) or len(head['texture_sha256'])!=64 or any(c not in '0123456789abcdef' for c in head['texture_sha256'])):raise schema.Error('admitted head requires a valid texture SHA-256')
        translation=head.get('translation',[0,0,0])
        for value in schema.vector(translation,'head translation'):schema.number(value,-5,5,'head translation')
        admitted_source=neutral_admitted_head(source,observed.rest[observed.names.index('head'),:3,:3],head['neck_blend'],translation) if reference_basis=='neutral' else source
        head_rows=admitted_head_rows(admitted_source,head_material,lower)
        head_arrays,head_triangles,retained=split_surfaces(head_rows,head_material,'admitted_head')
        connection=None
        if 'join_center' in head:
            if lower is None or reference_basis!='neutral':raise schema.Error('neck bridge requires a neutral head and explicit lower cut')
            head_model=sk.Model(head_arrays,retained,head_triangles,source.names,source.parents,source.bind,source.frames)
            bridge,connection=join_neck(candidate,head_model,cut,lower,head['join_center'])
            head_arrays,head_triangles,retained=split_surfaces(head_rows+bridge,head_material,'admitted_head')
        start=len(candidate.arrays[0]);first=len(candidate.triangles)
        for k in candidate.arrays:candidate.arrays[k]=np.concatenate((candidate.arrays[k],head_arrays[k]))
        candidate.triangles=np.concatenate((candidate.triangles,head_triangles+start))
        candidate.meshes.extend((name,mat,fv+start,nv,ft+first,nt) for name,mat,fv,nv,ft,nt in retained)
        head_receipt=dict(material=head_material,template_sha256=schema.sha(template_path),triangles=sum(row[-1] for row in head_meshes),
                          retained_triangles=len(head_triangles),minimum_z=lower,
                          reference_basis=reference_basis,face_geometry='rigid reference transform only; original facial vertices and UVs retained',
                          texture_sha256=head.get('texture_sha256'),neck_blend=head.get('neck_blend'),
                          translation=translation,neck_connection=connection,
                          collar_ownership=collar,
                          origin='Previously admitted independently generated Hiro head; explicit wardrobe-collar clipping; no original body geometry')
    # Include only explicitly prop-owned original surfaces; not one old body triangle.
    for name,mat,fv,nv,ft,nt in source.meshes:
        if not name.startswith('prop_'):continue
        j=source.names.index(name)
        if not np.all(source.arrays[4][fv:fv+nv,0]==j) or not np.all(source.arrays[5][fv:fv+nv,0]==255):
            raise schema.Error('source prop is not rigidly owned','ANIM_INVALID_WEIGHTS',name)
        start=len(candidate.arrays[0]);first=len(candidate.triangles)
        for k in candidate.arrays:candidate.arrays[k]=np.concatenate((candidate.arrays[k],source.arrays[k][fv:fv+nv]))
        candidate.triangles=np.concatenate((candidate.triangles,source.triangles[ft:ft+nt]-fv+start))
        candidate.meshes.append((name,mat,start,nv,first,nt))
    sk.validate(candidate);directory=fresh(output,True);destination=directory/'generated.iqm'
    temporary=directory/'generated.partial';temporary.write_bytes(sk.write(candidate));temporary.replace(destination)
    admitted=sk.read(destination.read_bytes())
    if not np.array_equal(admitted.bind,source.bind):raise schema.Error('generated body changed captured bind')
    report=dict(version=1,passed=True,kind='newly generated full-body character on captured source rig',
                source_model=legacy,source_md3_sha256=profile['source_md3_sha256'],recipe_sha256=schema.sha(recipe_path),
                profile_sha256=schema.sha(profile_path),template_sha256=schema.sha(template_path),tool_sha256=schema.sha(Path(__file__)),
                model_file=destination.name,output_sha256=schema.sha(destination),body_material=material,
                bind_pose_sha256=schema.bind_identity(admitted),provenance=recipe['provenance'],generated_inputs=inputs,
                versions=dict(python=platform.python_version(),numpy=np.__version__),
                vertices=len(admitted.arrays[0]),triangles=len(admitted.triangles),bones=admitted.names,frames=len(admitted.frames),
                hand_alignment=hand_alignment,original_body_triangles=0,original_body_uvs=False,visual_acceptance='unverified')
    report['surface_cleanup']=cleanup
    report['admitted_head']=head_receipt
    report['head_ownership']=head_weights
    report['head_reference_basis']=reference_basis
    report['skin_transform_policy']=skin_policy
    report['closed_fists']=closed_fists
    report['sole_alignment']=soles
    report['surface_closure']=closure
    report['material_authoring']=authored_materials
    schema.write_json(directory/'model.json',report);return report


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recipe',type=Path);parser.add_argument('--actor',type=Path,required=True)
    parser.add_argument('--template',type=Path);parser.add_argument('--base-models',type=Path)
    parser.add_argument('--out',type=Path,required=True);parser.add_argument('--closed-body',type=Path)
    parser.add_argument('--materials',type=Path)
    parser.add_argument('--prepare-closure','--prepare-geometry',dest='prepare_closure',action='store_true');args=parser.parse_args()
    if not args.prepare_closure and (args.template is None or args.base_models is None):parser.error('rigging requires --template and --base-models')
    try:
        result=prepare_closure(args.recipe,args.actor,args.out) if args.prepare_closure else rig(args.recipe,args.actor,args.template,args.base_models,args.out,args.closed_body,args.materials)
        print(json.dumps(result,sort_keys=True,allow_nan=False))
    except (schema.Error,ValueError,OSError,KeyError,StopIteration) as error:
        diagnostic=error.diagnostic(args.recipe) if isinstance(error,schema.Error) else dict(code='ANIM_GENERATED_MODEL',message=str(error))
        print(json.dumps(dict(passed=False,diagnostics=[diagnostic])),file=sys.stderr);raise SystemExit(1)


if __name__=='__main__':main()
