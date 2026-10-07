#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Export exact serialized/source cinematic motion for a paired local WebGL review.

Serve --out with a local HTTP server; no external libraries or original workspace.
The catalog preserves authored clip boundaries and every original frame. Numerical
triage and a review viewer are evidence tools, not visual acceptance by themselves.
"""
import argparse,hashlib,json,shutil,zipfile
from pathlib import Path
import numpy as np
import skeletal_iqm as sk
from neural_assets import read_md3
from neural_monsters import save

def digest(data):return hashlib.sha256(data).hexdigest()
def export(root,packages,out,selected=None,include_gameplay=False):
 ledger=json.loads((root/'pipeline.json').read_text());base=Path(ledger['assets'])/'packages/dk3-models.pk3'
 rows={};payloads={}
 for package in packages:
  with zipfile.ZipFile(package) as z:
   doc=json.loads(z.read('dk3/neural-assets.json'))
   for row in doc['models']:
    if (row['method']!='cinematic-fit' and not include_gameplay) or (selected and Path(row['source']).stem not in selected):continue
    rows[row['source']]=row;payloads[row['source']]=z.read(row['target'])
   if include_gameplay:
    mapping=dict(line.split() for line in z.read('dk3/neural-models.cfg').decode().splitlines() if line.strip())
    for actor in doc.get('actors',[]):
     if actor['slug'] not in doc.get('human_motion',{}).get('models',{}):continue
     path=actor['source'];target=mapping[path]
     if selected and Path(path).stem not in selected:continue
     rows[path]=dict(source=path,target=target,character=actor['slug'],method='human-npc',conversion=doc['human_motion']['models'][actor['slug']]);payloads[path]=z.read(target)
 out.mkdir(parents=True,exist_ok=True);items=[]
 with zipfile.ZipFile(base) as original:
  for path,row in sorted(rows.items()):
   stem=Path(path).stem;c=out/stem;c.mkdir(exist_ok=True)
   data=payloads[path];m=sk.read(data);surfaces,tags=read_md3(original.read(path+'.md3'))
   metadata=json.loads(original.read(path+'.json'))
   # Gameplay appends cosmetic cycles after the authoritative frame ranges.
   # Paired review uses those authoritative ranges, whose resampled poses come
   # from the same cycles; actual appended-clip timing is qualified natively.
   if row['method']!='cinematic-fit':m.frames=m.frames[:len(metadata['frames'])]
   source=[]
   for i,s in enumerate(surfaces):
    if s['material']=='models/dkq3/nodraw':continue
    skin=next(x for x in metadata['skins'] if x['shader']==s['material'])
    texture=original.read(skin['image']);filename='source-'+digest(texture)+'.png'
    if not (out/filename).exists():(out/filename).write_bytes(texture)
    fields={}
    for name,dtype in [('points','<f4'),('normals','<f4'),('uv','<f4'),('tri','<u4')]:
     blob=s[name].astype(dtype).tobytes();file=f'source-{i}-{name}.bin';(c/file).write_bytes(blob)
     fields[name]=dict(path=stem+'/'+file,shape=list(s[name].shape),sha256=digest(blob))
    source.append(dict(texture=filename,material=s['material'],fields=fields))
   fields={}
   for kind,name,dtype in [(0,'points','<f4'),(1,'uv','<f4'),(2,'normals','<f4'),(4,'joints','u1'),(5,'weights','u1')]:
    blob=m.arrays[kind].astype(dtype).tobytes();file=f'target-{name}.bin';(c/file).write_bytes(blob)
    fields[name]=dict(path=stem+'/'+file,shape=list(m.arrays[kind].shape),sha256=digest(blob))
   bone=sk.matrices(m.frames,m.parents)@np.linalg.inv(sk.matrices(m.bind,m.parents))
   for name,array,dtype in [('tri',m.triangles,'<u4'),('bones',bone.swapaxes(-1,-2),'<f4')]:
    blob=array.astype(dtype).tobytes();file=f'target-{name}.bin';(c/file).write_bytes(blob)
    fields[name]=dict(path=stem+'/'+file,shape=list(array.shape),sha256=digest(blob))
   name=row['character'];actor=root/name if name!='mikikofly' else root/'superfly'
   textures={}
   # Combined carried models retain both actors' material labels.
   for _,label,*_ in m.meshes:
    if not label.startswith('models/neural/'):
     skin=next(x for x in metadata['skins'] if x['shader']==label)
     texture=original.read(skin['image']);filename='source-'+digest(texture)+'.png'
     if not (out/filename).exists():(out/filename).write_bytes(texture)
     textures[label]=filename
     continue
    identity=label.split('/')[2] if label.startswith('models/neural/') else name
    source_actor=root/identity
    if not source_actor.exists() and identity.startswith('e1_'):source_actor=root/identity[3:]
    atlas='head.png' if label.endswith('/head') else 'body.png'
    p=source_actor/atlas
    if not p.exists():raise ValueError('Missing reviewed atlas: '+str(p))
    filename=identity+'-'+atlas
    if not (out/filename).exists() or digest((out/filename).read_bytes())!=digest(p.read_bytes()):shutil.copy2(p,out/filename)
    textures[label]=filename
   frame_valid=np.zeros(max(0,len(m.frames)-1),bool)
   clips=metadata['sequences']['frame_data']
   for clip in clips:frame_valid[clip['first']:clip['last']]=True
   world=sk.matrices(m.frames,m.parents);triage={}
   for j,bone_name in enumerate(m.names):
    if not any(bone_name.endswith(s) for s in ('head','hand_l','hand_r','foot_l','foot_r','pelvis','chest')):continue
    rot=world[:,j,:3,:3];relative=np.swapaxes(rot[:-1],-1,-2)@rot[1:]
    degrees=np.degrees(np.arccos(np.clip((np.trace(relative,axis1=-2,axis2=-1)-1)/2,-1,1)))
    degrees=np.where(frame_valid,degrees,0.)
    triage[bone_name]=dict(maximum_step_degrees=float(degrees.max()) if len(degrees) else 0,worst_frame=int(np.argmax(degrees)+1) if len(degrees) else 0)
   item=dict(slug=stem,source=path,character=name,frames=len(m.frames),joints=len(m.names),clips=clips,source_surfaces=source,target=dict(fields=fields,meshes=m.meshes,textures=textures),fit=row['conversion'],triage=triage,inputs=dict(iqm_sha256=digest(data),source_md3_sha256=digest(original.read(path+'.md3')),source_metadata_sha256=digest(original.read(path+'.json'))))
   save(c/'review.json',item);items.append(dict(slug=stem,character=name,frames=len(m.frames),clips=len(clips),manifest=stem+'/review.json',triage=triage))
   print(stem+': every source/serialized frame exported',flush=True)
 save(out/'catalog.json',dict(models=items,frames=sum(x['frames'] for x in items),clips=sum(x['clips'] for x in items),scope='Exact serialized/source geometry and every original clip; per-frame joint angular triage excludes clip boundaries. Viewer uses a diagnostic clock; native scene timing and facial morphs require separate acceptance.'))
 shutil.copy2(Path(__file__).with_name('neural_cinematic_review.html'),out/'index.html')
 return items
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,default=Path('zig-out/neural-monsters/episode1'));p.add_argument('--packages',type=Path,nargs='+',required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--models',nargs='+');p.add_argument('--include-gameplay',action='store_true');a=p.parse_args();export(a.root,a.packages,a.out,a.models,a.include_gameplay)
