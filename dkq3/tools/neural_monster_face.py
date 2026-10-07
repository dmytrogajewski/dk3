#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Admit an image-tool face projection registered to a reviewed new IQM mesh."""
import json
from pathlib import Path
import shutil
import subprocess
import numpy as np
from PIL import Image
import skeletal_iqm as sk


BOUNDS=dict(hiro=(22,30,3.1,-1.8),mikiko=(20.8,28,2.8,-1.8),
            superfly=(23.4,33,3.7,-2.5),mishima=(18.5,26.7,2.6,-3.8),usagi=(21,29,3.1,-1.8),
            garroth=(18.5,28,3.5,-4.5),fatworker=(21,31,3.5,-6.2),psyclaw=(-2,15,14,32))
FACE_IDENTITIES=frozenset('hiro mikiko superfly mishima usagi casseti charon femaleguard garroth warriorguard ninja osaka priest tatsuo toshiro mishimaguard fatworker skinnyworker surgeon'.split())
FACE_IDENTITIES=FACE_IDENTITIES|{'psyclaw'}


def camera(name):
    return dict(center=[0.,0.,6.],ortho_scale=30.,direction='+X') if name=='psyclaw' else dict(center=[0.,0.,26.],ortho_scale=15.,direction='+X')


def geometry_digest(actor):
    import hashlib
    model=sk.read((actor/'model.iqm').read_bytes());h=hashlib.sha256()
    for a in (model.arrays[0],model.arrays[1],model.arrays[2],model.triangles):h.update(a.tobytes())
    return h.hexdigest()


def preview(args):
    from concurrent.futures import ThreadPoolExecutor
    from neural_monsters import digest,save,selected,environment
    root=args.out.resolve();ledger=json.loads((root/'pipeline.json').read_text())
    def render(row):
        actor=root/row['slug'];output=actor/('face-review' if (actor/'face-projection.png').exists() else 'face-source');output.mkdir(exist_ok=True)
        origin,scale=coordinates(actor);plan=dict(origin=origin,scale=scale,camera=camera(actor.name))
        save(output/'camera.json',plan)
        key={n:digest(actor/n) for n in ('model.iqm','body.png')}
        key['geometry']=geometry_digest(actor)
        key['renderer']=digest(Path(__file__).with_name('neural_face_preview.py'))
        receipt=output/'receipt.json'
        if receipt.exists():
            prior=json.loads(receipt.read_text())
            if prior['inputs']==key and all(digest(output/n)==sha for n,sha in prior['outputs'].items()):return
        with (output/'render.log').open('w') as log:
            subprocess.run([args.blender,'-b','--threads','4','--python-exit-code','1','--python',str(Path(__file__).with_name('neural_face_preview.py')),'--',
                            '--mesh',str(actor/'model.iqm'),'--texture',str(actor/'body.png'),'--out',str(output),
                            '--plan',str(output/'camera.json')],stdout=log,stderr=subprocess.STDOUT,env=environment(root),check=True)
        save(receipt,dict(inputs=key,outputs={n:digest(output/n) for n in ('front.png','quarter.png','side.png','other-side.png')}))
        print(row['slug']+': face views complete',flush=True)
    rows=[r for r in selected(ledger,args) if r['slug'] in FACE_IDENTITIES]
    with ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(render,rows))


def coordinates(actor):
    """Reconstruct normalization from the serialized skeleton and its landmarks."""
    source=json.loads((actor/'source.json').read_text())
    report=json.loads((actor/'conversion.json').read_text())
    model=sk.read((actor/'model.iqm').read_bytes())
    if report.get('physics')!='humanoid':return [0.,0.,0.],1.
    if source['actor'].get('kind')=='character':return [0.,0.,0.],1.
    scale=float(np.ptp(model.arrays[0][:,2])/56)
    pelvis=sk.matrices(model.bind,model.parents)[model.names.index('pelvis'),:3,3]
    origin=pelvis-np.asarray(report['landmarks']['torso'][0])*scale
    return origin.tolist(),scale


def admit(args):
    from neural_monsters import digest,save,run_stage
    actor=args.out.resolve()/args.model
    ledger=json.loads((actor.parent/'pipeline.json').read_text())
    row=next(r for r in ledger['actors'] if r['slug']==args.model)
    if row['slug'] in ('prisoner','prisonerb'):raise ValueError('Prisoners are protected')
    if row['stages'].get('convert',{}).get('state')!='complete':raise ValueError('Complete conversion before reviewing a face')
    im=Image.open(args.image);im.verify();im=Image.open(args.image)
    if im.width!=im.height or im.width<768:raise ValueError('A registered face projection must be square and at least 768 pixels')
    destination=actor/'face-projection.png'
    if destination.exists() and digest(destination)!=digest(args.image):
        shutil.copy2(destination,actor/('face-projection-'+digest(destination)[:12]+'.png'))
    shutil.copy2(args.image,destination)
    origin,scale=coordinates(actor)
    plan=dict(character=args.model,mesh_sha256=digest(actor/'model.iqm'),geometry_sha256=geometry_digest(actor),origin=origin,scale=scale,
              bounds=BOUNDS.get(args.model,(21.,31.,3.5,-1.8)),
              camera=camera(args.model),
              projection_sha256=digest(destination),concept_sha256=digest(actor/'concept.png'),
              method='Built-in image edit of the fixed orthographic new-mesh face render; bounded atlas bake')
    source=actor/'face-source'
    if (source/'receipt.json').is_file():
        prior=json.loads((source/'receipt.json').read_text())
        if prior['inputs']['model.iqm']!=plan['mesh_sha256'] and prior['inputs'].get('geometry')!=plan['geometry_sha256']:raise ValueError('Review belongs to a different mesh')
        plan['reference_front_sha256']=digest(source/'front.png')
    if (actor/'face-prompt.txt').exists():plan['prompt_sha256']=digest(actor/'face-prompt.txt')
    save(actor/'face-plan.json',plan)
    args.command='convert';args.models=[args.model]
    run_stage(args)


def admit_quality(args):
    """Admit reviewed closed-surface art; reproduce the mesh through conversion."""
    from neural_monsters import digest,save,run_stage
    from neural_surface_quality import topology,uv_quality,animation_preservation
    actor=args.out.resolve()/args.model
    candidate=args.candidate.resolve()
    if actor.name in ('prisoner','prisonerb'):
        raise ValueError('Both chained prisoners are protected')
    plan=json.loads((candidate/'face-plan-quality.json').read_text())
    if plan['character']!=actor.name or geometry_digest(candidate)!=plan['geometry_sha256']:
        raise ValueError('Reviewed quality plan belongs to another candidate mesh')
    if plan['concept_sha256']!=digest(actor/'concept.png'):
        raise ValueError('Candidate belongs to another character concept')
    quality=topology(sk.read((candidate/'model.iqm').read_bytes()))
    if any(quality.values()):raise ValueError('Candidate surface is not closed: '+str(quality))
    atlas=uv_quality(sk.read((candidate/'model.iqm').read_bytes()))
    if any(atlas.values()):raise ValueError('Candidate has overlapping or collapsed atlas faces: '+str(atlas))
    animation_preservation(sk.read((actor/'model.iqm').read_bytes()),sk.read((candidate/'model.iqm').read_bytes()))
    if plan.get('reference_front_sha256')!=digest(candidate/'source/front.png'):
        raise ValueError('Quality camera reference changed')
    baked=json.loads((candidate/'body-quality.face.json').read_text())
    if (baked['mesh_sha256']!=digest(candidate/'model.iqm') or
        baked['original_texture_sha256']!=digest(candidate/'body.png') or
        baked['reviewed_projection']!=plan):
        raise ValueError('Reviewed candidate bake is stale')
    if baked['changed_uncovered_texels']!=0:
        raise ValueError('Candidate changed pixels outside the admitted repair')
    if set(v['angle'] for v in plan['projections'])-{-60,0,60} or len(set(v['angle'] for v in plan['projections']))!=len(plan['projections']) or not any(v['angle']==0 for v in plan['projections']):
        raise ValueError('Quality views need one front and unique supported side angles')
    for name,sha in baked.get('depth_maps',{}).items():
        if Path(name).name!=name or digest(candidate/name)!=sha:
            raise ValueError('Reviewed first-surface depth changed')
    for view in plan['projections']:
        name=view['path']
        if Path(name).name!=name or digest(candidate/name)!=view['sha256']:
            raise ValueError('Reviewed independent projection changed: '+name)
        im=Image.open(candidate/name);im.verify()
        im=Image.open(candidate/name)
        if im.width!=im.height or im.width<768:raise ValueError('Face view must be square and at least 768 pixels')
    previous=actor/('face-before-quality-'+digest(actor/'face-plan.json')[:12])
    previous.mkdir(exist_ok=True)
    for name in ('face-plan.json','face-projection.png','face-prompt.txt'):
        if (actor/name).is_file():shutil.copy2(actor/name,previous/name)
    for view in plan['projections']:shutil.copy2(candidate/view['path'],actor/view['path'])
    reference=actor/'face-quality-source';reference.mkdir(exist_ok=True)
    for view in ('front','quarter','side','other-side'):
        shutil.copy2(candidate/'source'/f'{view}.png',reference/f'{view}.png')
    plan.pop('seam_repair',None)
    plan.pop('prompt_sha256',None)
    plan['reference_front_path']='face-quality-source/front.png'
    save(actor/'face-plan.json',plan)
    closure=json.loads((candidate/'surface-closure.json').read_text())
    save(actor/'surface-quality.json',dict(voxel=closure['voxel'],thickness=closure['thickness'],
         triangles=closure.get('triangle_budget',closure['triangles'])))
    save(reference/'review.json',dict(candidate_geometry_sha256=geometry_digest(candidate),
        candidate_texture_sha256=digest(candidate/'body-quality.png'),topology=quality,uv_quality=atlas,
        views={n:digest(candidate/'quality-lit'/f'{n}.png') for n in ('front','quarter','side','other-side')}))
    args.command='convert';args.models=[args.model]
    run_stage(args)


def quality_preview(args):
    """Prepare closed meshes and actual albedo/clay references without admission."""
    from concurrent.futures import ThreadPoolExecutor
    from neural_monsters import digest,save,selected,environment
    root=args.out.resolve()
    destination=(args.candidate or root/'surface-candidates').resolve()
    ledger=json.loads((root/'pipeline.json').read_text())
    rows=[r for r in selected(ledger,args) if r['slug'] in FACE_IDENTITIES and r['slug']!='psyclaw']

    def render(row):
        actor=root/row['slug'];candidate=destination/row['slug'];candidate.mkdir(parents=True,exist_ok=True)
        source_actor=actor
        texture=actor/'body.png'
        model_path=actor/'model.iqm'
        if (actor/'surface-closure.json').exists():
            closure=json.loads((actor/'surface-closure.json').read_text())
            model_path=actor/closure['input_file']
            texture=actor/'body-before-closure.png'
            if digest(model_path)!=closure['source_iqm_sha256'] or digest(texture)!=closure['source_texture_sha256']:
                raise ValueError('Original closed-surface inputs changed: '+row['slug'])
            source_actor=candidate/'input';source_actor.mkdir(exist_ok=True)
            shutil.copy2(model_path,source_actor/'model.iqm')
        elif (actor/'body.face.json').exists():
            face=json.loads((actor/'body.face.json').read_text())
            texture=actor/'body-before-face.png'
            if digest(texture)!=face['original_texture_sha256']:
                raise ValueError('Original projection atlas changed: '+row['slug'])
        origin,scale=coordinates(actor)
        if (actor/'face-plan.json').exists():
            old=json.loads((actor/'face-plan.json').read_text());origin,scale=old['origin'],old['scale']
        plan=dict(character=row['slug'],origin=origin,scale=scale,camera=camera(row['slug']))
        for name in ('source.json','conversion.json'):shutil.copy2(actor/name,candidate/name)
        save(candidate/'camera.json',plan)
        inputs=dict(model=digest(model_path),texture=digest(texture),
                    closure=digest(Path(__file__).with_name('neural_surface_close.py')),
                    atlas_validation=digest(Path(__file__).with_name('neural_surface_quality.py')),
                    atlas_producer=digest(Path(__file__).with_name('neural_uv.py')),
                    renderer=digest(Path(__file__).with_name('neural_face_preview.py')),camera=plan,
                    triangles=args.triangles)
        receipt=candidate/'surface-preview.json'
        if receipt.exists():
            previous=json.loads(receipt.read_text())
            if previous['inputs']==inputs and all(digest(candidate/n)==sha for n,sha in previous['outputs'].items()):
                print(row['slug']+': quality surface reference retained',flush=True);return
        commands=[('neural_surface_close.py',['--source',str(source_actor),'--out',str(candidate),
                    '--texture',str(texture),'--triangles',str(args.triangles)])]
        for folder,extra in (('source',[]),('clay',['--clay']),('lit',['--lit'])):
            commands.append(('neural_face_preview.py',['--mesh',str(candidate/'model.iqm'),
                '--texture',str(candidate/'body.png'),'--out',str(candidate/folder),
                '--plan',str(candidate/'camera.json'),*extra]))
        for i,(tool,options) in enumerate(commands):
            with (candidate/f'quality-preview-{i}.log').open('w') as log:
                subprocess.run([args.blender,'-b','--threads','4','--python-exit-code','1','--python',
                    str(Path(__file__).with_name(tool)),'--',*options],env=environment(root),
                    stdout=log,stderr=subprocess.STDOUT,check=True)
        outputs=['model.iqm','body.png','surface-closure.json']+[f'{folder}/{view}.png'
            for folder in ('source','clay','lit') for view in ('front','quarter','side','other-side')]
        save(receipt,dict(inputs=inputs,outputs={n:digest(candidate/n) for n in outputs}))
        print(row['slug']+': closed surface and measured face references ready',flush=True)
    with ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(render,rows))


def bake(actor,blender,env):
    from neural_monsters import digest
    plan=json.loads((actor/'face-plan.json').read_text())
    if plan.get('geometry_sha256'):
        if plan['geometry_sha256']!=geometry_digest(actor):raise ValueError('Face projection belongs to different geometry; review the new face')
    elif plan['mesh_sha256']!=digest(actor/'model.iqm'):raise ValueError('Face projection belongs to a different IQM; review the new face geometry')
    reference=plan.get('reference_front_path','face-source/front.png')
    if reference not in ('face-source/front.png','face-seam-source/front.png','face-quality-source/front.png'):
        raise ValueError('Invalid registered face reference path')
    for key,name in (('projection_sha256','face-projection.png'),('concept_sha256','concept.png'),
                     ('reference_front_sha256',reference),('prompt_sha256','face-prompt.txt')):
        if key in plan and digest(actor/name)!=plan[key]:raise ValueError('Reviewed face input changed: '+name)
    for view in plan.get('projections',[]):
        name=view['path']
        if Path(name).name!=name or not name.endswith('.png'):
            raise ValueError('Invalid independent projection path')
        if digest(actor/name)!=view['sha256']:
            raise ValueError('Reviewed independent projection changed: '+name)
    original=actor/'body-before-face.png';shutil.copy2(actor/'body.png',original)
    tool=Path(__file__).with_name('neural_face.py')
    with (actor/'face.log').open('w') as log:
        subprocess.run([blender,'-b','--threads','4','--python-exit-code','1','--python',str(tool),'--',
                        '--mesh',str(actor/'model.iqm'),'--texture',str(original),
                        '--projection',str(actor/'face-projection.png'),'--out',str(actor/'body.png'),
                        '--plan',str(actor/'face-plan.json')],stdout=log,stderr=subprocess.STDOUT,env=env,check=True)
    conversion=json.loads((actor/'conversion.json').read_text())
    conversion['face_refinement']=json.loads((actor/'body.face.json').read_text())
    (actor/'conversion.json').write_text(json.dumps(conversion,indent=2,sort_keys=True)+'\n')
