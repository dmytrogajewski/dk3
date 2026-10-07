#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Agent-operated animation recipes for DK3's current native formats.

Use /usr/bin/python3 -B dkq3/tools/animation_author.py --help. Inputs are
immutable; generated IQMs, manifests, Blender jobs and receipts live in an
explicit output directory. No command installs into the user's launcher.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import sys
import urllib.request
import zipfile

import numpy as np

import animation_manifest as schema
import animation_motion as motion
import cinematic_author
import skeletal_iqm as sk
from neural_package import classic_archive, validate_package


def local(root,value):
    p=Path(value)
    if not p.is_absolute() and '..' in p.parts:raise schema.Error('relative input path escapes recipe root; supply an explicit absolute input', 'ANIM_INVALID_PATH', value)
    return p.resolve() if p.is_absolute() else (root/p).resolve()


def fresh(path,directory=False):
    path=Path(path)
    if path.exists() and (not directory or any(path.iterdir())):raise schema.Error('output already exists: '+str(path))
    if directory:path.mkdir(parents=True,exist_ok=True)
    else:path.parent.mkdir(parents=True,exist_ok=True)
    return path


def tools_identity():
    return {p.name:schema.sha(p) for p in Path(__file__).parent.glob('animation_*.py')} | {'cinematic_author.py':schema.sha(Path(__file__).with_name('cinematic_author.py')),
            'cinematic_reconstruction.py':schema.sha(Path(__file__).with_name('cinematic_reconstruction.py')),
            'cinematic_model.py':schema.sha(Path(__file__).with_name('cinematic_model.py')),
            'skeletal_iqm.py':schema.sha(Path(__file__).with_name('skeletal_iqm.py')),'neural_assets.py':schema.sha(Path(__file__).with_name('neural_assets.py')),
            'neural_head.py':schema.sha(Path(__file__).with_name('neural_head.py'))}


def fetch_sources(catalog,output):
    doc=schema.load(catalog);schema.fields(doc,('version','license','files'),('version','license','files'),'source catalog')
    if doc['version']!=1 or not isinstance(doc['license'],dict) or not isinstance(doc['files'],list):raise schema.Error('invalid motion source catalog')
    directory=fresh(output,True);downloaded=[];names=set()
    for row in doc['files']:
        schema.fields(row,('name','url','sha256'),('name','url','sha256'),'source file')
        name=schema.asset(row['name'])
        if '/' in name or name in names:raise schema.Error('source filenames must be unique basenames')
        names.add(name)
        if not isinstance(row['url'],str) or not row['url'].startswith('https://'):raise schema.Error('source download must use HTTPS')
        if not isinstance(row['sha256'],str) or len(row['sha256'])!=64 or any(c not in '0123456789abcdef' for c in row['sha256']):raise schema.Error('source download needs a pinned SHA-256')
        destination=directory/name;count=0;h=hashlib.sha256()
        with urllib.request.urlopen(row['url'],timeout=25) as stream,destination.open('wb') as output_file:
            for block in iter(lambda:stream.read(65536),b''):
                count+=len(block)
                if count>32*1024*1024:raise schema.Error('source exceeds bounded 32 MiB single-motion download')
                h.update(block);output_file.write(block)
        if h.hexdigest()!=row['sha256']:raise schema.Error('source download hash mismatch: '+name)
        downloaded.append(dict(row,bytes=count))
    result=dict(passed=True,catalog_sha256=schema.sha(catalog),license=doc['license'],files=downloaded)
    schema.write_json(directory/'license.json',result);return result


def blender(job,output,executable='blender'):
    directory=fresh(output,True)
    # Resolve paths before Blender runs; results are tied to the exact JSON job.
    for key in ('input','output','texture','blend','license'):
        if job.get(key):job[key]=str(Path(job[key]).resolve())
    if job.get('textures'):
        if not isinstance(job['textures'],dict):raise schema.Error('textures must be a material/path mapping')
        job['textures']={name:str(Path(path).resolve()) for name,path in job['textures'].items()}
    if 'output' not in job:raise schema.Error('Blender job requires an output')
    fresh(job['output'],job.get('operation')=='render_preview')
    if job.get('blend'):fresh(job['blend'])
    schema.write_json(directory/'job.json',job)
    command=[executable,'-b','--threads','4','--python-exit-code','1','--python',str(Path(__file__).with_name('animation_blender.py').resolve()),
             '--','--job',str((directory/'job.json').resolve()),'--result',str((directory/'result.json').resolve())]
    with (directory/'blender.log').open('w') as log:
        result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=1800)
    if result.returncode or not (directory/'result.json').is_file():raise schema.Error('Blender job failed; see '+str(directory/'blender.log'))
    receipt=json.loads((directory/'result.json').read_text());receipt['tools']=tools_identity()
    schema.write_json(directory/'result.json',receipt)
    return receipt


def inspect(path):
    model=sk.read(Path(path).read_bytes());world=sk.matrices(model.bind,model.parents)
    return dict(sha256=schema.sha(path),joints=[dict(name=n,parent=model.names[p] if p>=0 else None,
                bind_position=world[i,:3,3].tolist()) for i,(n,p) in enumerate(zip(model.names,model.parents))],
                frames=len(model.frames),vertices=len(model.arrays[0]),meshes=len(model.meshes),
                limits=dict(joints=128,frames=65536,mapping_entries=2048,character_entries=160))


def fit_legacy(model_path,md3_path,metadata_path,interval,fps):
    from neural_assets import read_md3,cinematic
    master=sk.read(Path(model_path).read_bytes());fitted=copy.deepcopy(master)
    surfaces,tags=read_md3(Path(md3_path).read_bytes());metadata=json.loads(Path(metadata_path).read_text())
    fit=cinematic(fitted,surfaces,tags,calibrate=False,metadata=metadata)
    first,last=schema.span(interval)
    if last>=len(fitted.frames):raise schema.Error('legacy fit interval outside source frames')
    sampled=motion.from_model(fitted,first,last,fps)
    bones={n:n for n in master.names if n in fitted.names and not n.startswith(('prop_','tag_','hp_','ctf_','fingers_','thumb_','clavicle_'))}
    result=motion.retarget(master,sampled,dict(bones=bones,forward='x',up='z'),root_motion='preserve')
    result.metadata.update(legacy_fit=fit,source_md3_sha256=schema.sha(md3_path),source_metadata_sha256=schema.sha(metadata_path),
                           model_sha256=schema.sha(model_path),performance='approximate baked vertex fitting; review required')
    return result


def authoritative(document,base):
    """Validate actual sequence names/ranges/rates against admitted source .anim."""
    with zipfile.ZipFile(base) as archive:
        for character in document['characters']:
            path=character['source_model']+'.anim'
            lines=archive.read(path).decode().splitlines()
            table={}
            for line in lines[1:]:
                row=shlex.split(line)
                if len(row)>=4:table[row[0]]=row[1:]
            for label,clip in character['clips'].items():
                row=table.get(clip['sequence'])
                if row is None:raise schema.Error(f'{character["character"]}.{label}: absent authoritative sequence')
                if list(map(int,row[:2]))!=clip['source_frames']:raise schema.Error('manifest differs from authoritative frame range: '+label)
                rate=float(row[2])
                if clip.get('authority_fps',rate)!=rate:raise schema.Error('manifest differs from authoritative sequence rate: '+label)
                clip['authority_fps']=rate
    return document


def compile_manifest(path,output=None,base=None,check_only=False):
    doc=schema.validate(schema.load(path));root=Path(path).resolve().parent
    if base:authoritative(doc,base)
    models={c['target_model']:sk.read(local(root,c['iqm']).read_bytes()) for c in doc['characters']}
    for character in doc['characters']:
        schema.validate_rig(character,models[character['target_model']])
    encoded=schema.compile_manifest(doc,{n:len(m.frames) for n,m in models.items()})
    if not check_only and output is None:raise schema.Error('compile-manifest requires --out or --check-only')
    inputs={Path(path).resolve(),*[local(root,c['iqm']) for c in doc['characters']]}
    if base:inputs.add(Path(base).resolve())
    if not check_only and Path(output).resolve() in inputs:raise schema.Error('compiled output would overwrite an input', 'ANIM_INVALID_PATH', str(output))
    changed=False if check_only else schema.write_if_changed(output,encoded)
    return dict(output=str(output) if output else None,check_only=check_only,changed=changed,
                sha256=hashlib.sha256(encoded).hexdigest(),aliases=schema.aliases(doc),
                inputs={str(path):schema.sha(path)},tools=tools_identity())


def build(path,output,base=None):
    document=schema.validate(schema.load(path));root=Path(path).resolve().parent
    if base:authoritative(document,base)
    directory=fresh(output,True);result=dict(format=1,manifest_sha256=schema.sha(path),tools=tools_identity(),models={},validation={},inputs={},source_licenses={})
    emitted=copy.deepcopy(document)
    for character,exported in zip(document['characters'],emitted['characters']):
        source=local(root,character['iqm']);master=sk.read(source.read_bytes());model=copy.deepcopy(master)
        schema.validate_rig(character,master)
        result['inputs'][str(source)]=schema.sha(source);name=character['character'];written=set()
        maximum=max(c['target_frames'][1] for c in character['clips'].values())+1
        if maximum>len(model.frames):model.frames=np.concatenate((model.frames,np.repeat(model.bind[None],maximum-len(model.frames),axis=0)))
        result['validation'][name]={};samples={}
        for label,clip in character['clips'].items():
            start,end=clip['target_frames'];rate=schema.effective_rate(clip)
            if clip.get('motion'):
                raw=local(root,clip['motion']);result['inputs'][str(raw)]=schema.sha(raw)
                source_motion=motion.read(raw)
                if source_motion.metadata.get('kind')=='authored_cinematic':
                    # Preserve exact authored keys. World-space resampling can
                    # shorten IK limbs between keys even when both endpoints
                    # are valid. Authors must export at the target rate/count.
                    if clip.get('input_frames') or len(source_motion.world)!=end-start+1 or abs(source_motion.fps-rate)>1e-6 or clip.get('retarget') or clip.get('source_fidelity'):
                        raise schema.Error('authored cinematic motion must match target frames/rate and omit source retarget/fidelity','ANIM_INVALID_RANGE',label)
                    sampled=source_motion
                else:
                    sampled=motion.resample(source_motion,rate,clip.get('input_frames'),end-start+1,clip['loop'])
                if sampled.metadata.get('license'): result['source_licenses'][str(raw)]=sampled.metadata['license']
                if clip.get('retarget'):
                    recipe=clip['retarget']
                    if isinstance(recipe,str):
                        recipe_path=local(root,recipe);result['inputs'][str(recipe_path)]=schema.sha(recipe_path);recipe=schema.load(recipe_path)
                    sampled=motion.retarget(master,sampled,recipe,clip['root_motion'])
                sampled=motion.root_policy(sampled,clip['root_motion'])
                if clip['root_motion']=='in_place':
                    sampled,speed=motion.constant_travel(sampled,clip.get('movement_speed'))
                    if speed is not None:exported['clips'][label]['movement_speed']=speed
                if clip.get('solve_contacts'):sampled=motion.solve_contacts(master,sampled,clip.get('contacts',{}),clip.get('solve_contact_root',False),clip.get('contact_floor'))
                if clip.get('correctives'):sampled=motion.apply_correctives(master,sampled,clip['correctives'])
                sampled=motion.prop_policy(master,sampled,clip)
                indices=set(range(start,end+1))
                if indices&written:raise schema.Error('two motion recipes write overlapping target frames')
                written|=indices
                model.frames[start:end+1]=motion.export_channels(sampled)
            else:
                sampled=motion.from_model(model,start,end,rate)
            report=motion.validate(master,sampled,clip)
            result['validation'][name][label]=report
            samples[label]=sampled
        destination=directory/(name+'.iqm');destination.write_bytes(sk.write(model))
        admitted=sk.read(destination.read_bytes())
        # Motion-only builds preserve the geometry, skeleton and weights; an
        # unexpected mesh/rig mutation is an export failure, even if playable.
        if admitted.names!=master.names or admitted.parents!=master.parents or admitted.meshes!=master.meshes:raise schema.Error('export changed frozen rig/mesh contract')
        for key in (0,1,2,4,5):
            if not np.array_equal(admitted.arrays[key],master.arrays[key]):raise schema.Error('export changed frozen vertex data')
        if not np.array_equal(admitted.bind,master.bind) or not np.array_equal(admitted.triangles,master.triangles):raise schema.Error('export changed frozen bind/topology')
        for label,clip in character['clips'].items():
            start,end=clip['target_frames'];original=samples[label]
            serialized=motion.from_model(admitted,start,end,original.fps)
            serialized.travel=original.travel
            serialized.metadata={**original.metadata,'auxiliary':serialized.metadata.get('auxiliary',{}),'serialized_iqm_sha256':schema.sha(destination)}
            result['validation'][name][label]=motion.validate(master,serialized,clip)
            motion.write(directory/f'{name}-{label}.npz',serialized)
        exported['iqm']=destination.name
        result['models'][character['target_model']]=dict(path=destination.name,sha256=schema.sha(destination),source_sha256=schema.sha(source),frames=len(model.frames))
    counts={n:row['frames'] for n,row in result['models'].items()}
    (directory/'neural-animations.cfg').write_bytes(schema.compile_manifest(emitted,counts))
    (directory/'animation-manifest.yaml').write_text(__import__('yaml').safe_dump(emitted,sort_keys=False))
    result['passed']=all(r['passed'] for clips in result['validation'].values() for r in clips.values())
    result['outputs']={p.name:schema.sha(p) for p in directory.iterdir() if p.is_file()}
    schema.write_json(directory/'build.json',result)
    if not result['passed']:raise schema.Error('motion validators failed; inspect '+str(directory/'build.json'))
    return result


def package(base_overlay,base_models,build_directory,output):
    root=Path(build_directory);receipt=json.loads((root/'build.json').read_text())
    if not receipt.get('passed'):raise schema.Error('refusing package with failed motion validation')
    for name,digest in receipt['outputs'].items():
        if schema.sha(root/name)!=digest:raise schema.Error('build output changed after validation: '+name)
    previous=validate_package(Path(base_overlay),Path(base_models))
    document=schema.load(root/'animation-manifest.yaml');authoritative(document,base_models)
    with zipfile.ZipFile(base_overlay) as archive:
        files={n:archive.read(n) for n in archive.namelist() if n!='dk3/neural-assets.json'}
    mapping=dict(line.split() for line in files['dk3/neural-models.cfg'].decode().splitlines() if line.strip())
    changed={}
    for c in document['characters']:
        if mapping.get(c['source_model'])!=c['target_model']:raise schema.Error('recipe targets another admitted model mapping')
        row=receipt['models'][c['target_model']]
        if hashlib.sha256(files[c['target_model']]).hexdigest()!=row['source_sha256']:raise schema.Error('overlay IQM differs from build master')
        if Path(row['path']).name!=row['path'] or receipt['outputs'].get(row['path'])!=row['sha256']:raise schema.Error('unregistered model build output')
        payload=(root/row['path']).read_bytes()
        if hashlib.sha256(payload).hexdigest()!=row['sha256']:raise schema.Error('changed model build output')
        before,after=sk.read(files[c['target_model']]),sk.read(payload)
        if before.names!=after.names or before.parents!=after.parents or before.meshes!=after.meshes or not np.array_equal(before.bind,after.bind) or not np.array_equal(before.triangles,after.triangles):raise schema.Error('package changed frozen rig/topology')
        if any(not np.array_equal(before.arrays[k],after.arrays[k]) for k in (0,1,2,4,5)):raise schema.Error('package changed frozen vertex data')
        files[c['target_model']]=payload;changed[c['target_model']]=row['sha256']
    replacing={(c.get('mapping_key',c['source_model']),*clip['source_frames']) for c in document['characters'] for clip in c['clips'].values()}
    rows=[]
    for line in files.get('dk3/neural-animations.cfg',b'').decode().splitlines():
        if not line.strip():continue
        parts=line.split()
        if (parts[0],int(parts[1]),int(parts[2])) not in replacing:rows.append(line)
    compiled=(root/'neural-animations.cfg').read_text().splitlines();rows.extend(compiled)
    if len(rows)>2048:raise schema.Error('merged table exceeds native 2048 mappings')
    files['dk3/neural-animations.cfg']=('\n'.join(rows)+'\n').encode()
    if len(files['dk3/neural-animations.cfg'])>256*1024:raise schema.Error('merged table exceeds native byte capacity')
    report=copy.deepcopy(previous);report['animation_authoring']=dict(build_sha256=schema.sha(root/'build.json'),manifest_sha256=receipt['manifest_sha256'],
        base_overlay_sha256=schema.sha(base_overlay),changed_models=changed,tools=receipt['tools'],native_acceptance='unverified',source_inputs=receipt['inputs'],source_licenses=receipt.get('source_licenses',{}))
    report['files']={n:hashlib.sha256(data).hexdigest() for n,data in files.items()}
    files['dk3/neural-assets.json']=(json.dumps(report,sort_keys=True,indent=2)+'\n').encode()
    destination=fresh(output);temporary=destination.with_suffix('.partial')
    with classic_archive(temporary) as archive:
        for name,data in sorted(files.items()):
            entry=zipfile.ZipInfo(name,(1980,1,1,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED;archive.writestr(entry,data)
    validate_package(temporary,Path(base_models));temporary.replace(destination)
    return dict(output=str(destination),sha256=schema.sha(destination),changed_models=changed)


def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='operation',required=True)
    p=sub.add_parser('inspect');p.add_argument('input',type=Path)
    p=sub.add_parser('fetch-source');p.add_argument('catalog',type=Path);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('fit-legacy');p.add_argument('--model',type=Path,required=True);p.add_argument('--md3',type=Path,required=True)
    p.add_argument('--metadata',type=Path,required=True);p.add_argument('--frames',nargs=2,type=int,required=True);p.add_argument('--fps',type=float,default=10);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('audit');p.add_argument('input',type=Path);p.add_argument('--metadata',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('procedural');p.add_argument('input',type=Path);p.add_argument('--kind',choices=('idle','walk','run','back','crouch','crouch_walk'),required=True)
    p.add_argument('--frames',type=int,required=True);p.add_argument('--fps',type=float,default=30);p.add_argument('--grip',choices=('relaxed','pistol','rifle','shoulder'),default='relaxed');p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('blender');p.add_argument('job',type=Path);p.add_argument('--out',type=Path,required=True);p.add_argument('--blender',default='blender')
    for op in ('compile-manifest','build'):
        p=sub.add_parser(op);p.add_argument('manifest',type=Path);p.add_argument('--out',type=Path,required=op=='build');p.add_argument('--base-models',type=Path)
        if op=='compile-manifest':p.add_argument('--check-only',action='store_true')
    p=sub.add_parser('compile-scene');p.add_argument('scene',type=Path);p.add_argument('--manifest',type=Path);p.add_argument('--base-models',type=Path);p.add_argument('--out',type=Path,required=True)
    for op in ('retarget','solve-contacts','validate'):
        p=sub.add_parser(op);p.add_argument('input',type=Path);p.add_argument('--model',type=Path,required=True);p.add_argument('--recipe',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('contacts');p.add_argument('input',type=Path);p.add_argument('--height',type=float,default=.8);p.add_argument('--speed',type=float,default=8);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('package');p.add_argument('--overlay',type=Path,required=True);p.add_argument('--base-models',type=Path,required=True);p.add_argument('--build',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('attach');p.add_argument('input',type=Path);p.add_argument('--name',required=True);p.add_argument('--parent',required=True);p.add_argument('--position',nargs=3,type=float,required=True);p.add_argument('--angles',nargs=3,type=float,default=[0,0,0]);p.add_argument('--out',type=Path,required=True)
    p=sub.add_parser('grid');p.add_argument('--model',type=Path,required=True);p.add_argument('--base',type=Path,required=True);p.add_argument('--attack',type=Path,required=True);p.add_argument('--bones',nargs='+',required=True);p.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();op=args.operation
    try:
        if op=='inspect':result=inspect(args.input)
        elif op=='fetch-source':result=fetch_sources(args.catalog,args.out)
        elif op=='fit-legacy':
            sampled=fit_legacy(args.model,args.md3,args.metadata,args.frames,args.fps);motion.write(fresh(args.out),sampled)
            result=dict(output=str(args.out),sha256=schema.sha(args.out),metadata=sampled.metadata)
        elif op=='audit':
            model=sk.read(args.input.read_bytes());metadata=json.loads(args.metadata.read_text());clips={}
            for row in metadata['sequences']['frame_data']:
                first,last=row['first'],row['last']
                if last>=len(model.frames):raise schema.Error('audit source interval exceeds IQM')
                sampled=motion.from_model(model,first,last,10)
                clips[row['animation_name']]=motion.validate(model,sampled,dict(max_joint_step=65))
            result=dict(model_sha256=schema.sha(args.input),metadata_sha256=schema.sha(args.metadata),clips=clips,
                        passed=all(c['passed'] for c in clips.values()),scope='Source-frame deformation audit; no automatic repairs or artistic acceptance')
            schema.write_json(fresh(args.out),result)
        elif op=='procedural':
            from neural_rig import pose
            schema.number(args.frames,1,65536,'procedural frames',integer=True);schema.number(args.fps,.001,240,'procedural fps')
            model=sk.read(args.input.read_bytes());bind=sk.matrices(model.bind,model.parents)
            model.frames=np.array([pose(model,bind,f/args.frames,args.kind,args.grip) for f in range(args.frames)])
            sampled=motion.from_model(model,0,args.frames-1,args.fps);sampled.metadata.update(source_sha256=schema.sha(args.input),kind=args.kind,grip=args.grip,performance='procedural fallback')
            motion.write(fresh(args.out),sampled);result=dict(output=str(args.out),sha256=schema.sha(args.out),scope='Procedural fallback, not captured performance')
        elif op=='blender':result=blender(json.loads(args.job.read_text()),args.out,args.blender)
        elif op=='compile-manifest':result=compile_manifest(args.manifest,args.out,args.base_models,args.check_only)
        elif op=='build':result=build(args.manifest,args.out,args.base_models)
        elif op=='compile-scene':
            aliases={}
            if args.manifest:
                doc=schema.load(args.manifest)
                if args.base_models:authoritative(doc,args.base_models)
                aliases=schema.aliases(doc)
            encoded,result=cinematic_author.compile_scene(schema.load(args.scene),aliases)
            fresh(args.out).write_bytes(encoded);result.update(sha256=schema.sha(args.out),source_sha256=schema.sha(args.scene),tools=tools_identity())
            schema.write_json(fresh(args.out.with_suffix('.json')),result)
        elif op in ('retarget','solve-contacts','validate'):
            model=sk.read(args.model.read_bytes());sampled=motion.read(args.input);recipe=schema.load(args.recipe)
            if op=='retarget':sampled=motion.retarget(model,sampled,recipe)
            elif op=='solve-contacts':sampled=motion.solve_contacts(model,sampled,recipe.get('contacts',recipe))
            if op=='validate':
                result=motion.validate(model,sampled,recipe);schema.write_json(fresh(args.out),result)
                if not result['passed']:raise schema.Error('motion validation failed; see '+str(args.out))
            else:
                motion.write(fresh(args.out),sampled);result=dict(output=str(args.out),sha256=schema.sha(args.out),metadata=sampled.metadata)
        elif op=='contacts':result=motion.contacts(motion.read(args.input),height=args.height,speed=args.speed);schema.write_json(fresh(args.out),dict(contacts=result))
        elif op=='package':result=package(args.overlay,args.base_models,args.build,args.out)
        elif op=='attach':
            model=motion.attach(sk.read(args.input.read_bytes()),args.name,args.parent,args.position,args.angles)
            fresh(args.out).write_bytes(sk.write(model));result=dict(output=str(args.out),sha256=schema.sha(args.out))
        elif op=='grid':
            model=sk.read(args.model.read_bytes());frames=motion.compose_grid(model,motion.read(args.base),motion.read(args.attack),args.bones)
            first=len(model.frames)
            if first+len(frames)>65536:raise schema.Error('grid exceeds native u16 frames')
            model.frames=np.concatenate((model.frames,frames));fresh(args.out).write_bytes(sk.write(model))
            result=dict(output=str(args.out),first=first,count=len(motion.read(args.attack).world),base_count=len(motion.read(args.base).world),rate=30,sha256=schema.sha(args.out))
        print(json.dumps(dict(passed=True,operation=op,result=result),indent=2,allow_nan=False))
    except (schema.Error,ValueError,KeyError,FileNotFoundError) as error:
        diagnostic=error.diagnostic(getattr(args,'manifest',None)) if isinstance(error,schema.Error) else dict(code='ANIM_INVALID_SOURCE',message=str(error),severity='error')
        print(json.dumps(dict(passed=False,operation=op,error=str(error),diagnostics=[diagnostic])),file=sys.stderr);sys.exit(1)


if __name__=='__main__':main()
