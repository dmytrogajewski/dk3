#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compose reviewed character motion and human NPC clips on frozen bind rigs."""
import argparse, copy, hashlib, json, zipfile
from pathlib import Path
import numpy as np
import skeletal_iqm as sk
from neural_assets import clip_name
from neural_rig import pose
from neural_package import classic_archive, validate_package

HUMANS = {'mishimaguard':'pistol', 'cryotech':'rifle', 'surgeon':'relaxed',
          'fatworker':'relaxed', 'skinnyworker':'relaxed'}
KINDS = {'LEGS_IDLE':('idle',2.), 'LEGS_WALK':('walk',.8), 'LEGS_RUN':('run',.5),
         'LEGS_BACK':('back',.8), 'LEGS_WALKCR':('crouch_walk',.9), 'LEGS_IDLECR':('crouch',2.)}
def sha(data): return hashlib.sha256(data).hexdigest()

def human_clips(master, metadata, landmarks, grip):
    model = copy.deepcopy(master)
    # NPC binds retain original world dimensions. Recover the measured
    # 56-unit authoring frame without resampling geometry or changing weights.
    shin = model.names.index('shin_l')
    scale = np.linalg.norm(model.bind[shin,:3])/np.linalg.norm(np.subtract(landmarks['leg'][1],landmarks['leg'][0]))
    offset = model.bind[0,:3]-np.asarray(landmarks['torso'][0])*scale
    model.arrays[0] = (model.arrays[0]-offset)/scale
    model.bind[:,:3] /= scale
    model.bind[0,:3] -= offset/scale
    bind = sk.matrices(model.bind, model.parents)
    blocks, mapping, cache = [], [], {}
    frames = master.frames.copy()
    appended = len(frames)
    for sequence in metadata['sequences']['frame_data']:
        family = clip_name(sequence['animation_name'])
        if family not in KINDS: continue
        kind, seconds = KINDS[family]
        if kind not in cache:
            count = round(seconds*30)
            block = np.array([pose(model,bind,f/count,kind,grip) for f in range(count)])
            block[:,:,:3] *= scale
            block[:,0,:3] += offset
            cache[kind] = (appended, block)
            blocks.append(block); appended += len(block)
        first, block = cache[kind]
        count = sequence['last']-sequence['first']+1
        indices = np.linspace(0,len(block)-1,count)
        lo, hi = np.floor(indices).astype(int), np.ceil(indices).astype(int)
        fraction = (indices-lo)[:,None,None]
        frames[sequence['first']:sequence['last']+1] = block[lo]*(1-fraction)+block[hi]*fraction
        mapping.append(dict(sequence=sequence['animation_name'],first=sequence['first'],last=sequence['last'],
                            playback_first=first,playback_last=first+len(block)-1,rate=30))
    result = copy.deepcopy(master)
    result.frames = np.concatenate([frames,*blocks])
    return result, mapping

def compose(root, before, characters, output):
    ledger = json.loads((root/'pipeline.json').read_text())
    base = Path(ledger['assets'])/'packages/dk3-models.pk3'
    previous, character = validate_package(before,base), validate_package(characters,base)
    with zipfile.ZipFile(before) as archive:
        files = {n:archive.read(n) for n in archive.namelist() if n!='dk3/neural-assets.json'}
    with zipfile.ZipFile(characters) as archive:
        files.update({n:archive.read(n) for n in archive.namelist()
                      if n not in ('dk3/neural-assets.json','dk3/neural-models.cfg','dk3/neural-physics.cfg','scripts/dk3-neural.shader')})
    report = copy.deepcopy(previous)
    report.update({k:v for k,v in character.items() if k not in ('files','losses')})
    report['actors'] = previous['actors']
    mappings, proofs = [], {}
    for row in previous['actors']:
        name = row['slug']
        if name not in HUMANS: continue
        target = f'models/neural/e{ledger["episode"]}_{name}.iqm'
        raw = (root/name/'model.iqm').read_bytes()
        if raw != files[target]: raise ValueError('NPC master differs from installed model: '+name)
        source = json.loads((root/name/'source.json').read_text())
        conversion = json.loads((root/name/'conversion.json').read_text())
        master = sk.read(raw)
        model, clips = human_clips(master,source['metadata'],conversion['landmarks'],HUMANS[name])
        payload = sk.write(model)
        files[target] = payload
        mappings += [f'{row["source"]} {c["first"]} {c["last"]} {c["playback_first"]} {c["playback_last"]} {c["rate"]} 0 0\n' for c in clips]
        proofs[name] = dict(master_sha256=sha(raw),output_sha256=sha(payload),clips=clips)
        print(name+': refreshed human motion on the admitted bind rig',flush=True)
    files['dk3/neural-animations.cfg'] += ''.join(mappings).encode()
    report['human_motion'] = dict(tool_sha256=sha(Path(__file__).read_bytes()),models=proofs,
                                  geometry_bind_weights_atlases='unchanged',native_acceptance='unverified')
    report['files'] = {n:sha(data) for n,data in files.items()}
    files['dk3/neural-assets.json'] = (json.dumps(report,sort_keys=True,indent=2)+'\n').encode()
    temporary = output.with_suffix('.partial')
    with classic_archive(temporary) as archive:
        for name,data in sorted(files.items()):
            entry=zipfile.ZipInfo(name,(1980,1,1,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(entry,data)
    validate_package(temporary,base)
    temporary.replace(output)
    output.with_suffix('.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,default=Path('zig-out/neural-monsters/episode1'))
    p.add_argument('--before',type=Path,required=True);p.add_argument('--characters',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();compose(a.root,a.before,a.characters,a.output)
