#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Capture supplied 3D vertex performances and package bounded scene retakes.

This offline adapter reads local admitted data, never the original game's code.
Surface correspondences are measured observations, not synthesized bone keys.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shlex
import re
import struct
import sys
import zipfile

import numpy as np

import animation_manifest as schema
import animation_motion as motion
from animation_author import fresh
from cinematics import numbers
from tables import quoted

KINDS = ('none','move','turn','move_turn','backup','restore','run_speed',
         'walk_speed','yaw_speed','wait','teleport','run','walk','use','head',
         'animation','idle','sound','spawn','remove','clear')


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def filename_token(value: str, field: str) -> str:
    schema.text(value,field,32)
    if not re.fullmatch(r'[a-z0-9_][a-z0-9_-]*',value):
        raise schema.Error('expected a lowercase basename without path separators', 'ANIM_INVALID_PATH', field)
    return value


def parse_program(data: bytes, source: str = 'program') -> list[dict]:
    """Read the existing text contract, including original negative queue times."""
    if not 0 < len(data) <= 4*1024*1024:
        raise schema.Error('cinematic exceeds 4 MiB', 'CINE_INVALID_SIZE', source)
    tokens=iter(shlex.split(data.decode('utf-8'),comments=False));offset=0
    def word():
        nonlocal offset
        offset+=1
        try:return next(tokens)
        except StopIteration:raise schema.Error(f'{source}: truncated at token {offset}', 'CINE_TRUNCATED', source)
    def expect(value):
        if word()!=value:raise schema.Error(f'{source}: expected {value} at token {offset}', 'CINE_INVALID_RECORD', source)
    def scalar():return schema.number(float(word()),where=source)
    def count(limit):return schema.number(int(word()),0,limit,source,integer=True)
    def vector(n=3):return [scalar() for _ in range(n)]
    def flag():return count(1)
    expect('dk3_cinematic');expect('1');shots=[];total_tasks=0
    for index in range(count(256)):
        expect('shot');duration,pre,post=vector();target,end,has_fov=flag(),flag(),flag();fov=scalar();sky=flag()
        modes=[count(2),count(2)];target_name,end_name=word(),word()
        if min(duration,pre,post)<0 or duration+pre+post>3600:raise schema.Error('invalid shot time', 'CINE_INVALID_TIME', source)
        expect('camera');points,segments=count(8192),count(8192);initial=vector(6);curves=[]
        if segments<max(0,points-1):raise schema.Error('camera point/segment disagreement')
        for _ in range(segments):
            expect('segment');seconds=scalar()
            if not 0<=seconds<=3600:raise schema.Error('invalid camera segment time')
            curves.append(dict(seconds=seconds,fov_flags=[flag(),flag()],fov=vector(2),
                speed_flags=[flag(),flag()],speed=vector(2),blend_flags=[flag(),flag()],
                blend=vector(8),position=vector(12),angles=vector(12)))
        expect('sounds');sounds=[]
        for _ in range(count(4096)):
            path=word();loop=flag();channel=count(255);when=scalar()
            if path:schema.asset(path,'cinematic sound')
            sounds.append(dict(path=path,loop=loop,channel=channel,when=when))
        expect('entities');tracks=[]
        for _ in range(count(128)):
            classname,unique=word(),word();schema.text(classname,'actor class',32)
            if unique:schema.text(unique,'actor id',32)
            tasks=[]
            for _ in range(count(32768)):
                kind=count(20);when=scalar();destination=vector();angles=vector();attribute=scalar();length=scalar()
                animation,use,sound,task_id=[word() for _ in range(4)]
                task=dict(kind=KINDS[kind],when=when,destination=destination,angles=angles,
                          attribute=attribute,duration=length,animation=animation,use=use,sound=sound,unique=task_id)
                if kind==14:
                    expect('head');parts=count(8192);task['head_initial']=vector()
                    task['head']=[vector(12) for _ in range(max(0,parts-1))]
                    task['head_points']=parts
                tasks.append(task);total_tasks+=1
                if total_tasks>65535:raise schema.Error('cinematic exceeds native task capacity')
            tracks.append(dict(classname=classname,unique=unique,tasks=tasks))
        shots.append(dict(index=index,duration=duration,pre=pre,post=post,target=target,
                          end_on_actor=end,has_fov=has_fov,fov=fov,sky=sky,velocity_modes=modes,
                          target_name=target_name,end_name=end_name,points=points,initial=initial,
                          segments=curves,sounds=sounds,tracks=tracks))
    if next(tokens,None) is not None:raise schema.Error('trailing cinematic data', 'CINE_TRAILING_DATA', source)
    return shots


def encode_program(shots: list[dict]) -> bytes:
    """Readable deterministic debug output, retaining existing field meanings."""
    rows=[f'dk3_cinematic 1 {len(shots)}']
    for shot in shots:
        rows.append('shot '+numbers([shot[k] for k in ('duration','pre','post','target','end_on_actor','has_fov','fov','sky')]+shot['velocity_modes'])+' '+quoted(shot['target_name'])+' '+quoted(shot['end_name']))
        rows += [f'camera {shot["points"]} {len(shot["segments"])}',numbers(shot['initial'])]
        for segment in shot['segments']:
            values=[segment['seconds']]
            for k in ('fov_flags','fov','speed_flags','speed','blend_flags','blend','position','angles'):values+=segment[k]
            rows.append('segment '+numbers(values))
        rows.append('sounds '+str(len(shot['sounds'])))
        rows += [quoted(s['path'])+' '+numbers([s['loop'],s['channel'],s['when']]) for s in shot['sounds']]
        rows.append('entities '+str(len(shot['tracks'])))
        for track in shot['tracks']:
            rows.append(quoted(track['classname'])+' '+quoted(track['unique'])+' '+str(len(track['tasks'])))
            for task in track['tasks']:
                rows.append(numbers([KINDS.index(task['kind']),task['when'],*task['destination'],*task['angles'],task['attribute'],task['duration']])+' '+' '.join(quoted(task[k]) for k in ('animation','use','sound','unique')))
                if task['kind']=='head':rows += ['head '+str(task['head_points']),numbers(task['head_initial']),*[numbers(c) for c in task['head']]]
    data=('\n'.join(rows)+'\n').encode('utf-8');parse_program(data)
    return data


def performance_contract(shots: list[dict]) -> list[dict]:
    """Observable native actor/audio/scene contract, independent of cameras.

    Follow server/cinematics.zig's readers: spawn ignores animation/use hints;
    queued animation uses source metadata duration. An empty queued sequence is
    ignored; a timed empty sequence still gates admission of following tasks.
    Actor identity defaults to the track ID. Keep all consumed fields explicit.
    This is a compatibility check, never artistic acceptance.
    """
    result=[]
    for shot in shots:
        tracks=[]
        for track in shot['tracks']:
            tasks=[]
            for task in track['tasks']:
                kind=task['kind']
                if kind=='animation' and not task['animation'] and task['when']<0:continue
                row=dict(kind=kind,when=task['when'],actor=task['unique'] or track['unique'])
                if kind in ('spawn','teleport','move','move_turn'):row['destination']=task['destination']
                if kind in ('spawn','teleport'):row['angles']=task['angles']
                if kind in ('turn','move_turn'):row['yaw']=task['angles'][1]
                if kind in ('animation','idle','move','move_turn'):row['animation']=task['animation']
                if kind in ('wait','run_speed','walk_speed','yaw_speed'):row['attribute']=task['attribute']
                if kind=='use':row['use']=task['use']
                if kind=='sound':row['sound']=task['sound']
                if kind=='head':
                    for field in ('head_points','head_initial','head'):row[field]=task[field]
                tasks.append(row)
            tracks.append(dict(classname=track['classname'],unique=track['unique'],tasks=tasks))
        result.append(dict(duration=shot['duration'],pre=shot['pre'],post=shot['post'],
            target=shot['target'],target_name=shot['target_name'],end_on_actor=shot['end_on_actor'],
            end_name=shot['end_name'],sounds=shot['sounds'],tracks=tracks))
    return result


def compare_performance(original: Path, candidate: Path, output: Path) -> dict:
    if output.resolve() in (original.resolve(),candidate.resolve()):
        raise schema.Error('comparison report would overwrite a cinematic input', 'ANIM_INVALID_PATH',str(output))
    before=performance_contract(parse_program(original.read_bytes(),str(original)))
    after=performance_contract(parse_program(candidate.read_bytes(),str(candidate)))
    differences=[]
    def compare(a,b,field):
        if type(a) is not type(b):differences.append(field);return
        if isinstance(a,dict):
            if a.keys()!=b.keys():differences.append(field);return
            for k in a:compare(a[k],b[k],field+'.'+k)
        elif isinstance(a,list):
            if len(a)!=len(b):differences.append(field+'.count');return
            for i,(x,y) in enumerate(zip(a,b)):compare(x,y,f'{field}[{i}]')
        elif a!=b:differences.append(field)
    compare(before,after,'shots')
    result=dict(passed=not differences,original_sha256=schema.sha(original),candidate_sha256=schema.sha(candidate),
        differences=differences,shots=len(before),scope='Consumed native actor queues, transforms, dialogue, uses, timing and completion; camera curves deliberately excluded')
    schema.write_json(output,result)
    if differences:raise schema.Error('performance contract changed: '+', '.join(differences[:8]), 'CINE_PERFORMANCE_CHANGED',differences[0])
    return result


def archive_read(archive: zipfile.ZipFile, name: str, limit: int) -> bytes:
    schema.asset(name,'archive entry')
    matches=[row for row in archive.infolist() if row.filename==name]
    if len(matches)!=1 or matches[0].file_size>limit:
        raise schema.Error('missing, duplicated or oversized archive entry: '+name, 'ANIM_INVALID_SOURCE', name)
    return archive.read(name)


def inventory(data_package: Path, output: Path) -> dict:
    root=fresh(output,True);programs={}
    with zipfile.ZipFile(data_package) as archive:
        for name in sorted(archive.namelist()):
            if not name.startswith('dk3/cinematics/') or not name.endswith('.cfg'):continue
            data=archive_read(archive,name,4*1024*1024);shots=parse_program(data,name);elapsed=0;rows=[]
            for shot in shots:
                clips=[dict(classname=t['classname'],unique=t['unique'],sequence=a['animation'],kind=a['kind'],when=a['when'])
                       for t in shot['tracks'] for a in t['tasks'] if a['animation']]
                rows.append(dict(index=shot['index'],at=elapsed,duration=shot['duration']+shot['pre']+shot['post'],
                                 actors=sorted({t['classname'] for t in shot['tracks']}),clips=clips,
                                 sounds=shot['sounds'],uses=[a['use'] for t in shot['tracks'] for a in t['tasks'] if a['kind']=='use']))
                elapsed+=rows[-1]['duration']
            programs[name]=dict(sha256=digest(data),shots=rows,duration=elapsed,
                                roundtrip_exact=encode_program(shots)==data)
    result=dict(passed=True,package_sha256=schema.sha(data_package),programs=programs,
                scope='Source shot/actor/clip/audio/use inventory; playback and visual review pending')
    schema.write_json(root/'inventory.json',result);return result


def reference(data_package: Path, recipe_path: Path, output: Path) -> dict:
    """Extract a source shot block with explicitly checked initial actors."""
    import copy
    recipe=schema.load(recipe_path)
    schema.fields(recipe,('version','source_program','source_shots','actors','scene'),
                  ('version','source_program','source_shots','actors','scene'),'reference recipe')
    if recipe['version']!=1:raise schema.Error('reference recipe requires version 1')
    source=schema.asset(recipe['source_program'],'source program','.cfg');scene=filename_token(recipe['scene'],'reference scene')
    with zipfile.ZipFile(data_package) as archive:data=archive_read(archive,source,4*1024*1024)
    shots=parse_program(data,source);selected=recipe['source_shots'];actors=recipe['actors']
    if not isinstance(selected,list) or not selected or len(selected)>256 or not isinstance(actors,list) or not 1<=len(actors)<=128:raise schema.Error('reference needs bounded shot indices and 1..128 initial actor IDs')
    for index in selected:schema.number(index,0,len(shots)-1,'reference shot',integer=True)
    if selected!=list(range(selected[0],selected[-1]+1)):raise schema.Error('reference shot block must be consecutive')
    for unique in actors:schema.text(unique,'reference actor',32)
    if len(set(actors))!=len(actors):raise schema.Error('duplicate reference actor')
    block=copy.deepcopy([shots[i] for i in selected]);initial=[]
    for unique in actors:
        schema.text(unique,'reference actor',32);spawn=None;classname=None
        tracks=[t for t in block[0]['tracks'] if t['unique']==unique]
        if len(tracks)!=1:raise schema.Error('reference first shot must retain exactly one declared actor track')
        first=tracks[0]['tasks']
        if first and first[0]['kind']=='spawn' and first[0]['when']<=0:
            # Initialization belongs to this block already. Keep the original
            # task rather than adding a second spawn or guessing earlier state.
            initial.append(copy.deepcopy(first[0]));continue
        for shot in shots[:selected[0]]:
            for track in shot['tracks']:
                if track['unique']!=unique:continue
                for task in track['tasks']:
                    if task['kind']=='spawn':spawn=task;classname=track['classname']
                    elif task['kind'] in ('move','move_turn','turn','teleport','head','remove'):
                        spawn=None
        if spawn is None:raise schema.Error('actor initial transform needs a recorded state: '+unique, 'CINE_REFERENCE_STATE', unique)
        if len(tracks)!=1 or tracks[0]['classname']!=classname:raise schema.Error('reference first shot must retain declared actor track')
        task=copy.deepcopy(spawn);task['when']=-1.;tracks[0]['tasks'].insert(0,task);initial.append(task)
    root=fresh(output,True);path=root/(scene+'.cfg');encoded=encode_program(block);schema.write_if_changed(path,encoded)
    result=dict(passed=True,source_program=source,source_sha256=digest(data),source_shots=selected,
                recipe_sha256=schema.sha(recipe_path),initial=initial,program=path.name,sha256=digest(encoded),
                scope='Original shot block, curves, audio and tasks; checked original initialization for independent native recording')
    schema.write_json(root/'reference.json',result);return result


def rigid_capture(rest: np.ndarray, frames: np.ndarray, anchor: np.ndarray,
                  regularization: float) -> tuple[np.ndarray, dict]:
    """Correspondence Kabsch fit with a small previous-orientation prior.

    Covariance rank and fit error stay visible. The prior resolves ambiguous
    surface twist; it does not replace measured endpoint displacement.
    """
    center=rest.mean(axis=0);reference=rest-center;cov=reference.T@reference
    spectrum=np.linalg.eigvalsh(cov);scale=max(float(np.trace(cov)),1e-12)
    if spectrum[1]<scale*1e-6:raise schema.Error('marker support is collinear', 'ANIM_UNOBSERVABLE_MARKER')
    previous=np.eye(3);result=[];errors=[];regularized=[]
    for points in frames:
        current=points.mean(axis=0);posed=points-current
        covariance=reference.T@posed
        # Objective: minimize surface error plus a bounded prior to the
        # previous proper rotation. Row convention is reference @ R.T.
        u,s,vh=np.linalg.svd(covariance+regularization*scale*previous.T)
        rotation=vh.T@np.diag([1.,1.,np.linalg.det(vh.T@u.T)])@u.T
        matrix=np.eye(4);matrix[:3,:3]=rotation;matrix[:3,3]=current+rotation@(anchor-center)
        predicted=reference@rotation.T+current;error=float(np.sqrt(np.mean(np.sum((predicted-points)**2,axis=1))))
        result.append(matrix);errors.append(error);regularized.append(float(s[-1]/max(s[0],1e-12)));previous=rotation
    return np.array(result),dict(rms_mean=float(np.mean(errors)),rms_max=float(max(errors)),
        worst_frame=int(np.argmax(errors)),reference_spectrum=spectrum.tolist(),
        min_condition_ratio=min(regularized),regularization=regularization,vertices=len(rest))


def landmark_basis(points: np.ndarray, axes: dict) -> np.ndarray:
    """Semantic face axes from explicit, hash-pinned source landmark groups."""
    schema.fields(axes,('left','up'),('left','up'),'reference axes')
    def direction(groups,field):
        if not isinstance(groups,list) or len(groups)!=2:raise schema.Error('axis requires start/end vertex groups',field=field)
        for group in groups:
            if not isinstance(group,list) or not 1<=len(group)<=128:
                raise schema.Error('axis groups require 1..128 unique vertices',field=field)
            for index in group:schema.number(index,0,len(points)-1,field,integer=True)
            if len(set(group))!=len(group):raise schema.Error('axis vertices must be unique',field=field)
        return points[groups[1]].mean(0)-points[groups[0]].mean(0)
    left=direction(axes['left'],'left axis');up=direction(axes['up'],'up axis')
    return motion.orientation_basis(np.cross(left,up),up)


def capture(profile_path: Path, base_models: Path, output: Path) -> dict:
    from neural_assets import read_md3,source_props,split_hidden_props
    profile=schema.load(profile_path)
    schema.fields(profile,('version','source_model','source_md3_sha256','surface','reference_frame','markers','clips','props','regularization','max_marker_rms','provenance'),
                  ('version','source_model','source_md3_sha256','surface','reference_frame','markers','clips','provenance'),'capture profile')
    if profile['version']!=1:raise schema.Error('capture profile requires version 1')
    source=schema.asset(profile['source_model'],'source model','.dkm');markers=profile['markers'];clips=profile['clips']
    if not isinstance(markers,dict) or not 0<len(markers)<=128 or not isinstance(clips,dict) or not 0<len(clips)<=128:raise schema.Error('bounded markers/clips mappings required')
    schema.fields(profile['provenance'],('origin','license','redistribution','credit'),('origin','license','redistribution','credit'),'provenance')
    if any(not isinstance(value,str) or not value for value in profile['provenance'].values()):raise schema.Error('capture provenance needs explicit text')
    regularization=schema.number(profile.get('regularization',.002),0,.05,'rotation regularization')
    residual_limit=schema.number(profile.get('max_marker_rms',1),.001,10,'marker residual limit')
    with zipfile.ZipFile(base_models) as archive:
        blob=archive_read(archive,source+'.md3',32*1024*1024)
        if digest(blob)!=profile['source_md3_sha256']:raise schema.Error('original vertex source hash changed', 'ANIM_SOURCE_HASH_MISMATCH', source)
        metadata_raw=archive_read(archive,source+'.json',4*1024*1024);metadata=json.loads(metadata_raw)
        animation=archive_read(archive,source+'.anim',1024*1024).decode('utf-8')
    table={}
    for line in animation.splitlines()[2:]:
        row=shlex.split(line)
        if len(row)!=4 or row[0] in table:raise schema.Error('invalid authoritative animation table')
        table[row[0]]=[int(v) for v in row[1:]]
    surfaces,_=read_md3(blob);body=split_hidden_props(source_props(surfaces,metadata))
    selected=[s for s in body if s['name']==profile['surface'] and not s.get('prop')]
    if len(selected)!=1:raise schema.Error('capture surface missing or identifies a prop')
    surface=selected[0];points=surface['points'];reference=schema.number(profile['reference_frame'],0,len(points)-1,'reference frame',integer=True)
    props=profile.get('props',{})
    if not isinstance(props,dict) or len(props)>16:raise schema.Error('capture props must be a bounded mapping')
    prop_sources={}
    for name,prop in props.items():
        schema.text(name,'prop bone',32)
        if not name.startswith('prop_'):raise schema.Error('capture requires prop bone names')
        schema.fields(prop,('surface','reference_frame','visibility_scale'),('surface','reference_frame'),'captured prop '+name)
        matching=[s for s in body if s['name']==prop['surface'] and s.get('prop')]
        if len(matching)!=1:raise schema.Error('captured prop surface missing', 'ANIM_UNOBSERVABLE_MARKER',name)
        ref=schema.number(prop['reference_frame'],0,len(points)-1,'prop reference frame',integer=True)
        from neural_assets import prop_visibility
        visible=prop_visibility(matching[0]['points'])
        if not visible[ref]:raise schema.Error('prop reference must be visible', 'ANIM_UNOBSERVABLE_MARKER',name)
        # Retail hiding can retain a uniformly shrunken blade ~0.3 units
        # long. An absolute extent test alone mistakes that for a rigid,
        # full-size sword. Compare against this pinned visible reference.
        ratio=schema.number(prop.get('visibility_scale',.05),.001,.1,'prop visibility scale')
        extent=np.ptp(matching[0]['points'],axis=1).max(axis=1)
        visible &= extent>=extent[ref]*ratio
        prop_sources[name]=(matching[0],ref,visible)
    names=list(markers);parents=[];rest=np.broadcast_to(np.eye(4),(len(names),4,4)).copy();supports=[];semantic={}
    for j,(name,marker) in enumerate(markers.items()):
        schema.text(name,'marker bone',32);schema.fields(marker,('parent','anchor','vertices','reference_axes'),('parent','anchor','vertices'),'marker '+name)
        parent=marker['parent']
        if parent is not None and parent not in names[:j]:raise schema.Error('marker parent must precede child', 'ANIM_UNKNOWN_BONE', name)
        parents.append(names.index(parent) if parent is not None else -1)
        rest[j,:3,3]=schema.vector(marker['anchor'],'marker '+name+'.anchor');vertices=marker['vertices']
        if not isinstance(vertices,list) or not 4<=len(vertices)<=256:raise schema.Error('marker requires 4..256 explicit vertices',field=name)
        for v in vertices:schema.number(v,0,points.shape[1]-1,'marker vertex',integer=True)
        if len(set(vertices))!=len(vertices):raise schema.Error('duplicate marker vertex',field=name)
        supports.append(vertices)
        if 'reference_axes' in marker:
            rest[j,:3,:3]=landmark_basis(points[reference],marker['reference_axes'])
            semantic[name]=dict(landmarks=marker['reference_axes'],basis=rest[j,:3,:3].tolist(),reference_frame=reference)
    validated=[]
    for name,clip in clips.items():
        filename_token(name,'clip');schema.fields(clip,('sequence','source_frames'),('sequence','source_frames'),'capture clip')
        sequence=schema.text(clip['sequence'],'sequence',32);a,b=schema.span(clip['source_frames'])
        if sequence not in table or table[sequence][:2]!=[a,b] or b>=len(points):raise schema.Error('capture clip differs from source sequence', 'ANIM_INVALID_RANGE', name)
        validated.append((name,a,b,table[sequence][2]))
    root=fresh(output,True);reports={}
    for name,a,b,fps in validated:
        world=np.broadcast_to(np.eye(4),(b-a+1,len(names),4,4)).copy();metrics={}
        for j,bone in enumerate(names):
            vertices=supports[j];world[:,j],metrics[bone]=rigid_capture(points[reference,vertices],points[a:b+1][:,vertices],rest[j,:3,3],regularization)
            world[:,j,:3,:3]=world[:,j,:3,:3]@rest[j,:3,:3]
            metrics[bone]['worst_source_frame']=a+metrics[bone]['worst_frame']
        failures=[dict(code='ANIM_MARKER_FIT_ERROR',bone=bone,**metric,limit=residual_limit)
                  for bone,metric in metrics.items() if metric['rms_max']>residual_limit]
        if failures:
            schema.write_json(root/'capture.json',dict(passed=False,clip=name,source_model=source,
                source_md3_sha256=digest(blob),profile_sha256=schema.sha(profile_path),failures=failures))
            raise schema.Error('source regions are not rigid enough; inspect capture.json before retargeting', 'ANIM_MARKER_FIT_ERROR', name)
        # Retain exact original observations as data, not just fitted output.
        raw=root/(name+'-surface.npz')
        np.savez_compressed(raw,points=points[a:b+1],tri=surface['tri'],uv=surface['uv'],source_frames=np.arange(a,b+1))
        sampled=motion.Motion(names,parents,rest,world,float(fps),np.zeros((b-a+1,3)),dict(
            performance='3D surface motion reconstructed from original local vertex animation; visual review required',
            source_md3_sha256=digest(blob),profile_sha256=schema.sha(profile_path),source_frames=[a,b],
            license=profile['provenance'],marker_metrics=metrics,observation_sha256=schema.sha(raw)))
        if semantic:sampled.metadata['semantic_frames']=semantic
        if prop_sources:
            captured={}
            for prop_name,(prop,ref,visibility) in prop_sources.items():
                observed=prop['points'][a:b+1];mask=visibility[a:b+1]
                transforms=np.broadcast_to(np.eye(4),(len(observed),4,4)).copy();rms=0.
                if mask.any():
                    fitted,fit=rigid_capture(prop['points'][ref],observed[mask],np.zeros(3),0)
                    transforms[mask]=fitted;rms=fit['rms_max']
                    if rms>.08:raise schema.Error('prop is not rigid; inspect original geometry', 'ANIM_MARKER_FIT_ERROR',prop_name)
                    # Hidden frames have no observable orientation. Carry the
                    # nearest visible pose; visibility remains a discrete event.
                    indices=np.flatnonzero(mask)
                    for frame in np.flatnonzero(~mask):transforms[frame]=transforms[indices[np.argmin(np.abs(indices-frame))]]
                captured[prop_name]=dict(world=transforms.tolist(),visible=mask.tolist(),reference_frame=ref,surface=prop['name'],rms_max=rms)
            sampled.metadata['source_props']=captured
        sampled.metadata['marker_validation']=dict(passed=True,max_rms=residual_limit)
        destination=root/(name+'.npz');motion.write(destination,sampled)
        reports[name]=dict(sequence=clips[name]['sequence'],frames=[a,b],fps=fps,motion=destination.name,
            sha256=schema.sha(destination),observation=raw.name,observation_sha256=schema.sha(raw),markers=metrics,
            source_floor=points[a:b+1,:,2].min(axis=1).tolist())
    result=dict(passed=True,version=1,source_model=source,source_md3_sha256=digest(blob),source_metadata_sha256=digest(metadata_raw),
                profile_sha256=schema.sha(profile_path),surface=profile['surface'],reference_frame=reference,
                provenance=profile['provenance'],max_marker_rms=residual_limit,clips=reports,tool_sha256=schema.sha(Path(__file__)),
                scope='Exact original surface observations and fitted anatomical markers; no claim of new camera mocap or artistic quality')
    schema.write_json(root/'capture.json',result);return result


def scene_package(program: Path, dependencies: list[Path], output: Path,
                  source: Path | None = None, manifest: Path | None = None) -> dict:
    """Separate cinematic-only PK3. Never replace an admitted campaign program."""
    filename_token(program.stem,'scene name');entry=f'dk3/cinematics/{program.stem}.cfg';data=program.read_bytes();shots=parse_program(data,str(program))
    sounds=set();models=set()
    for shot in shots:
        sounds.update(s['path'] for s in shot['sounds'] if s['path'])
        sounds.update(t['sound'] for a in shot['tracks'] for t in a['tasks'] if t['sound'])
    for path in sounds:schema.asset(path,'sound')
    if any(shot['tracks'] for shot in shots):
        if not source or not manifest:raise schema.Error('authored actor package needs source recipe and animation manifest')
        recipe=schema.load(source);document=schema.validate(schema.load(manifest));characters={c['character']:c for c in document['characters']}
        import cinematic_author
        rebuilt,_=cinematic_author.compile_scene(recipe,schema.aliases(document))
        if rebuilt!=data:raise schema.Error('compiled program differs from source recipe', 'CINE_SOURCE_HASH_MISMATCH')
        actors=recipe.get('actors',{})
        for shot in shots:
            for track in shot['tracks']:
                actor=actors.get(track['unique'])
                if actor is None or actor.get('class')!=track['classname'] or actor.get('character') not in characters:raise schema.Error('compiled actor differs from authoring source')
                character=characters[actor['character']];model=character['source_model'];models|={model+'.anim',model+'.md3'}
                sequences={c['sequence'] for c in character['clips'].values()}
                for task in track['tasks']:
                    if task['kind'] in ('animation','idle','move','move_turn') and task['animation'] and task['animation'] not in sequences:raise schema.Error('compiled sequence absent from manifest', 'CINE_UNKNOWN_ANIMATION', task['animation'])
    assets={}
    needed=sounds|models
    for package in dependencies:
        package_sha=schema.sha(package)
        with zipfile.ZipFile(package) as archive:
            if entry in archive.namelist():raise schema.Error('retake name already exists in admitted assets', 'CINE_REPLACEMENT_CONFLICT', entry)
            for path in sorted(needed-assets.keys()):
                if path in sounds:
                    relative=path[7:] if path.startswith('sounds/') else path
                    candidates=['sounds/'+relative,'sounds/'+relative+'.ogg']
                else:candidates=[path]
                for candidate in candidates:
                    if candidate in archive.namelist():
                        assets[path]=dict(package_sha256=package_sha,entry=candidate,sha256=digest(archive_read(archive,candidate,32*1024*1024)));break
    if missing:=needed-assets.keys():raise schema.Error('missing cinematic assets: '+', '.join(sorted(missing)), 'CINE_MISSING_ASSET')
    receipt=dict(version=1,passed=True,scene=program.stem,format='dk3_cinematic 1',program_sha256=digest(data),
        source_sha256=schema.sha(source) if source else None,manifest_sha256=schema.sha(manifest) if manifest else None,dependencies=assets,shots=len(shots),
        required_presentation='original source models; optional IQM clip mappings',
        scope='Separate authored scene; no automatic campaign replacement',tool_sha256=schema.sha(Path(__file__)))
    manifest=f'dk3/authoring/{program.stem}.json';fresh(output)
    payloads={entry:data,manifest:(json.dumps(receipt,sort_keys=True,indent=2)+'\n').encode('utf-8')}
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED) as archive:
        for path,encoded in sorted(payloads.items()):
            info=zipfile.ZipInfo(path,(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;archive.writestr(info,encoded)
    receipt.update(package_sha256=schema.sha(output),entries={p:digest(v) for p,v in payloads.items()});schema.write_json(output.with_suffix('.json'),receipt);return receipt


def fixture_controls(authored: list[dict], shots: list[dict]) -> list[dict]:
    """Retain reviewed original map controls used by the selected performance.

    Follow named target chains, never bring in ambient actors or automatic
    campaign triggers. Preserve brush model and unique ID strings verbatim.
    """
    pending=sorted({t['use'] for s in shots for a in s['tracks'] for t in a['tasks'] if t['kind']=='use'})
    retained=set();visited=set()
    allowed={'func_door','func_door_rotating','func_button','func_rotating','func_train',
             'path_corner','target_relay','target_delay','target_speaker','target_counter'}
    while pending:
        name=pending.pop(0)
        schema.text(name,'fixture use target',32)
        if name in visited:continue
        visited.add(name)
        matches=[i for i,row in enumerate(authored) if name in (row.get('uniqueid'),row.get('targetname'))]
        if not matches:raise schema.Error('original map use target missing: '+name, 'CINE_MISSING_USE_TARGET',name)
        for i in matches:
            row=authored[i]
            if row.get('classname') not in allowed:
                raise schema.Error('map control requires explicit review: '+str(row.get('classname')), 'CINE_UNREVIEWED_CONTROL',name)
            retained.add(i)
            if len(retained)>128:raise schema.Error('fixture exceeds 128 map controls')
            pending.extend(row[k] for k in ('target','killtarget') if row.get(k))
    return [dict(authored[i]) for i in sorted(retained)]


def fixture(maps: Path, navigation: Path, program: Path, map_name: str,
            source_map: str, output: Path, prefix: Path = Path('zig-out/native-dev')) -> dict:
    """Use the original set, collision and lighting with a disposable trigger.

    Only the BSP entity lump is rebuilt. Every geometric lump stays byte-exact.
    Original map programs and completion targets remain in the source package.
    """
    import entities
    filename_token(map_name,'preview map');filename_token(source_map,'source map')
    if not map_name.startswith('intr_'):raise schema.Error('this slice requires an intr_ map for opening model-family selection')
    shots=parse_program(program.read_bytes(),str(program))
    with zipfile.ZipFile(maps) as archive:blob=archive_read(archive,f'maps/{source_map}.bsp',64*1024*1024)
    if blob[:4]!=b'IBSP' or struct.unpack_from('<i',blob,4)[0]!=46:raise schema.Error('invalid source BSP')
    if len(blob)<8+17*8:raise schema.Error('truncated source BSP')
    for index in range(17):
        at,length=struct.unpack_from('<ii',blob,8+index*8)
        if at<0 or length<0 or at+length>len(blob):raise schema.Error('BSP lump outside source file')
    start,size=struct.unpack_from('<ii',blob,8)
    authored=[dict(row) for row in entities.parse(blob[start:start+size])]
    controls=fixture_controls(authored,shots)
    root=fresh(output,True)
    world={k:v for k,v in authored[0].items() if k not in ('cinematic_intro','target','nextmap')}
    initial=shots[0]['initial'][:3]
    body=[world,dict(classname='info_player_start',origin=' '.join(map(str,initial))),*controls,
          dict(classname='target_script',targetname='reconstruction_preview',cinescript=program.stem)]
    # target_script is not a cinematic trigger in this runtime. Use a point
    # trigger_script: diagnostic activation is explicit, with no touch volume.
    body[-1]['classname']='trigger_script'
    encoded=('\n'.join('{\n'+'\n'.join(quoted(k)+' '+quoted(str(v)) for k,v in row.items())+'\n}' for row in body)+'\n\0').encode('utf-8')
    padded=blob+b'\0'*((-len(blob))%4);new=bytearray(padded+encoded);struct.pack_into('<ii',new,8,len(padded),len(encoded))
    unchanged=[]
    for index in range(1,17):
        at,length=struct.unpack_from('<ii',blob,8+index*8)
        if new[at:at+length]!=blob[at:at+length]:raise schema.Error('fixture changed a geometric BSP lump')
        unchanged.append(dict(lump=index,sha256=digest(blob[at:at+length])))
    payloads={f'maps/{map_name}.bsp':bytes(new),f'dk3/cinematics/{program.stem}.cfg':program.read_bytes()}
    with zipfile.ZipFile(navigation) as archive:
        original_nav=archive_read(archive,f'dk3/navigation/{source_map}.cfg',4096)
    # The BSP checksum includes entities. Recompile navigation for this exact
    # fixture instead of changing a source AAS checksum or disabling admission.
    import map_build
    bsp=root/(map_name+'.bsp');bsp.write_bytes(bytes(new))
    rebuilt=map_build.bot_navigation(prefix.resolve(),bsp,root,map_name)
    payloads[f'dk3/navigation/{map_name}.cfg']=rebuilt['selection'].read_bytes()
    payloads.update({f'maps/{stem}.aas':path.read_bytes() for stem,path in rebuilt['aas'].items()})
    destination=root/'zzz-dk3-reconstruction-set.pk3'
    with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED) as archive:
        for name,value in sorted(payloads.items()):
            info=zipfile.ZipInfo(name,(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;archive.writestr(info,value)
    result=dict(passed=True,map=map_name,source_map=source_map,program=program.stem,trigger_id=len(body),controls=controls,
        package=destination.name,sha256=schema.sha(destination),original_bsp_sha256=digest(blob),
        geometric_lumps=unchanged,navigation=rebuilt['variants'],original_navigation_sha256=digest(original_nav),
        scope='Original set in isolated entity fixture; exact rebuilt navigation; no campaign completion targets')
    schema.write_json(root/'fixture.json',result);return result


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='operation',required=True)
    p=sub.add_parser('inventory');p.add_argument('--data',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('capture');p.add_argument('profile',type=Path);p.add_argument('--base-models',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('reference');p.add_argument('recipe',type=Path);p.add_argument('--data',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('compare');p.add_argument('original',type=Path);p.add_argument('candidate',type=Path);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('package');p.add_argument('program',type=Path);p.add_argument('--assets',type=Path,action='append',default=[]);p.add_argument('--source',type=Path);p.add_argument('--manifest',type=Path);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('fixture');p.add_argument('program',type=Path);p.add_argument('--maps',type=Path,required=True);p.add_argument('--navigation',type=Path,required=True)
    p.add_argument('--map',default='intr_retake');p.add_argument('--source-map',default='intro');p.add_argument('--out',type=Path,required=True);p.add_argument('--prefix',type=Path,default=Path('zig-out/native-dev'))
    args=parser.parse_args()
    try:
        if args.operation=='inventory':result=inventory(args.data,args.out)
        elif args.operation=='capture':result=capture(args.profile,args.base_models,args.out)
        elif args.operation=='reference':result=reference(args.data,args.recipe,args.out)
        elif args.operation=='compare':result=compare_performance(args.original,args.candidate,args.out)
        elif args.operation=='package':result=scene_package(args.program,args.assets,args.out,args.source,args.manifest)
        else:result=fixture(args.maps,args.navigation,args.program,args.map,args.source_map,args.out,args.prefix)
        # Large inventories and marker tables live in explicit report files.
        print(json.dumps(dict(passed=True,operation=args.operation,output=str(args.out)),indent=2))
    except (schema.Error,ValueError,KeyError,OSError,struct.error) as error:
        diagnostic=error.diagnostic(getattr(args,'profile',None)) if isinstance(error,schema.Error) else dict(code='CINE_INVALID_SOURCE',message=str(error),severity='error')
        print(json.dumps(dict(passed=False,diagnostics=[diagnostic])),file=sys.stderr);raise SystemExit(1)


if __name__=='__main__':main()
