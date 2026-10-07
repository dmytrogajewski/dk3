#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Rebuild cinematic fits while retaining an exact admitted material generation."""
import argparse,concurrent.futures,copy,hashlib,json,zipfile
from pathlib import Path
import skeletal_iqm as sk
from neural_assets import cinematic,combined,read_md3,gameplay
from neural_monsters import save
from neural_package import validate_package,classic_archive
import dkm2md3

def sha(data):return hashlib.sha256(data).hexdigest()

def rebuild(root,package,workers=2,human_motion=False):
    builder_path=Path(__file__).with_name('neural_assets.py')
    builder_sha=sha(builder_path.read_bytes())
    tool_sha=sha(Path(__file__).read_bytes())
    rig_sha=sha(Path(__file__).with_name('neural_rig.py').read_bytes())
    ledger=json.loads((root/'pipeline.json').read_text())
    base=Path(ledger['assets'])/'packages/dk3-models.pk3'
    prior=validate_package(package,base)
    sources={}
    for name,record in prior['inputs'].items():
        actor=root/name;raw=(actor/'model.iqm').read_bytes()
        if sha(raw)!=record['iqm_sha256'] or sha((actor/'body.png').read_bytes())!=record['texture_sha256']:
            raise ValueError('Material generation belongs to another master: '+name)
        conversion='conversion-head.json' if (actor/'conversion-head.json').exists() else 'conversion.json'
        if json.loads((actor/conversion).read_text())!=record['mesh']:
            raise ValueError('Master conversion changed: '+name)
        if record.get('head_texture_sha256') and sha((actor/'head.png').read_bytes())!=record['head_texture_sha256']:
            raise ValueError('Head atlas changed: '+name)
        face=actor/'body.face.json'
        if record.get('face_repair')!=(json.loads(face.read_text()) if face.exists() else None):
            raise ValueError('Face protection changed: '+name)
        model=sk.read(raw)
        model.meshes=[(n,'models/neural/'+name+('/head' if label.endswith('/head') else '/body'),*rest) for n,label,*rest in model.meshes]
        clips=actor/'model.clips.json'
        sources[name]=(model,{c['name']:c for c in json.loads(clips.read_text())['animations']} if clips.exists() else {})
    with zipfile.ZipFile(package) as archive:
        files={n:archive.read(n) for n in archive.namelist() if n!='dk3/neural-assets.json'}
    selected=[row for row in prior['models'] if row['method']=='cinematic-fit' or human_motion and row['method']=='q3-clips']
    def fit(row):
        with zipfile.ZipFile(base) as archive:
            surfaces,tags=read_md3(archive.read(row['source']+'.md3'))
            metadata=json.loads(archive.read(row['source']+'.json'))
        if row['character']=='mikikofly':model,detail=combined(sources,surfaces,tags,metadata)
        else:
            model=copy.deepcopy(sources[row['character']][0])
            detail=cinematic(model,surfaces,tags,metadata=metadata) if row['method']=='cinematic-fit' else gameplay(model,metadata,sources[row['character']][1],tags,regenerate_motion=True)
        result=dict(row,conversion=detail,frames=len(model.frames),joints=len(model.names))
        outputs={row['target']:sk.write(model)}
        for variant,suffix in enumerate(dkm2md3.RENDER_VARIANTS):
            outputs[row['target']+f'.{variant}.skin']=''.join(f'{n},{material}{suffix}\n' for n,material,*_ in model.meshes).encode()
        print(row['source']+': rebuilt cinematic and matching skins',flush=True)
        return result,outputs
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:results=list(pool.map(fit,selected))
    rows={r['source']:r for r in prior['models']}
    for row,outputs in results:rows[row['source']]=row;files.update(outputs)
    extra_motion=[]
    if human_motion:
        with zipfile.ZipFile(base) as archive:
            for name,original in (('mishima','hiro'),('usagi','mikiko')):
                model=copy.deepcopy(sources[name][0])
                metadata=json.loads(archive.read(f'models/global/m_{original}.dkm.json'))
                detail=gameplay(model,metadata,sources[name][1],regenerate_motion=True)
                extra_motion.append(dict(source='player/'+name,conversion=detail))
                target=f'models/neural/player_{name}.iqm'
                if target not in files:raise ValueError('Missing admitted player variant: '+name)
                files[target]=sk.write(model)
    document=copy.deepcopy(prior)
    document['models']=[rows[r['source']] for r in prior['models']]
    if human_motion:
        files['dk3/neural-animations.cfg']=''.join(
            f'{row["source"]} {clip["first"]} {clip["last"]} {clip["playback_first"]} {clip["playback_last"]} {clip["rate"]} {clip.get("attack_first",0)} {clip.get("attack_count",0)}\n'
            for row in [*[r for r in document['models'] if r['method']=='q3-clips'],*extra_motion] for clip in row['conversion']).encode()
    document['files']={n:sha(data) for n,data in files.items()}
    if sha(builder_path.read_bytes())!=builder_sha or sha(Path(__file__).read_bytes())!=tool_sha or sha(Path(__file__).with_name('neural_rig.py').read_bytes())!=rig_sha:
        raise ValueError('Cinematic implementation changed during rebuilding; candidate publication stopped')
    document['cinematic_builder_sha256']=builder_sha
    document['cinematic_rebuild_sha256']=tool_sha
    document['human_motion_rig_sha256']=rig_sha
    files['dk3/neural-assets.json']=(json.dumps(document,sort_keys=True,indent=2)+'\n').encode()
    temporary=package.with_suffix('.motion-partial')
    with classic_archive(temporary) as archive:
        for name,data in sorted(files.items()):
            entry=zipfile.ZipInfo(name,(1980,1,1,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(entry,data)
    validate_package(temporary,base)
    temporary.replace(package);save(package.with_suffix('.json'),document)
    return document

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=Path('zig-out/neural-monsters/episode1'))
    parser.add_argument('--package',type=Path);parser.add_argument('--workers',type=int,default=2)
    parser.add_argument('--human-motion',action='store_true',help='regenerate gameplay and multiplayer motion on the admitted bind rigs')
    args=parser.parse_args();rebuild(args.root,args.package or args.root/'dk3-neural-characters.pk3',args.workers,args.human_motion)
