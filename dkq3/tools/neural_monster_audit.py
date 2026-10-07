#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Audit serialized masters across every frame; retain evidence separate from review."""
import argparse
import json
from pathlib import Path
import numpy as np
import skeletal_iqm as sk
from neural_monsters import digest,save
from neural_package import physics_rig


def audit(actor):
    source=json.loads((actor/'source.json').read_text())
    conversion='conversion-head.json' if (actor/'conversion-head.json').is_file() else 'conversion.json'
    report=json.loads((actor/conversion).read_text())
    model=sk.read((actor/'model.iqm').read_bytes())
    mode=report.get('physics',source['actor']['physics'])
    physics_rig((actor/'model.iqm').read_bytes(),mode)
    if source['actor'].get('kind')!='character' and len(model.frames)!=len(source['metadata']['frames']):
        raise ValueError(actor.name+': source event/frame contract changed')
    missing=set(source['tags'])-set(model.names)
    if missing:raise ValueError(actor.name+': missing original hardpoints '+str(missing))
    products=['model.iqm','body.png','source.json',conversion]
    if (actor/'head.png').is_file():products.append('head.png')
    result=dict(actor=actor.name,inputs={n:digest(actor/n) for n in products},
                tool_sha256=digest(Path(__file__)),frames=len(model.frames),joints=len(model.names),
                vertices=len(model.arrays[0]),triangles=len(model.triangles),physics=mode)
    if mode=='humanoid':
        body=[i for i,n in enumerate(model.names) if not n.startswith(('tag_','cloth_'))][:25]
        lengths=np.linalg.norm(model.bind[body,:3],axis=-1)
        errors=np.abs(np.linalg.norm(model.frames[:,body,:3],axis=-1)-lengths)
        # Root movement is intentional; all body segments remain fixed length.
        errors[:,[i for i,j in enumerate(body) if model.parents[j]<0]]=0
        result['maximum_bone_length_error']=float(errors.max())
        tolerance=max(.005,float(np.ptp(model.arrays[0][:,2]))*.0001)
        if errors.max()>tolerance:raise ValueError(actor.name+': changing anatomical bone length')
    p=model.arrays[0];tri=model.triangles
    edges=np.concatenate([tri[:,[0,1]],tri[:,[1,2]],tri[:,[2,0]]])
    edges=np.unique(np.sort(edges,axis=1),axis=0)
    lengths=np.linalg.norm(p[edges[:,0]]-p[edges[:,1]],axis=-1)
    # Tiny decimation edges magnify harmless quantization; record meaningful edges.
    edges=edges[lengths>np.ptp(p[:,2])*.0001];lengths=lengths[lengths>np.ptp(p[:,2])*.0001]
    minimum=np.full(3,np.inf);maximum=np.full(3,-np.inf);stretch=0.
    for first in range(0,len(model.frames),8):
        points=sk.skin(model,model.frames[first:first+8])
        if not np.isfinite(points).all():raise ValueError(actor.name+': nonfinite skinned geometry')
        minimum=np.minimum(minimum,points.min(axis=(0,1)));maximum=np.maximum(maximum,points.max(axis=(0,1)))
        ratios=np.linalg.norm(points[:,edges[:,0]]-points[:,edges[:,1]],axis=-1)/lengths
        stretch=max(stretch,float(np.quantile(ratios,.99,axis=1).max()))
    result.update(skinned_frames_checked=len(model.frames),motion_bounds=[minimum.tolist(),maximum.tolist()],
                  maximum_frame_edge_stretch_p99=stretch,
                  scope='Serialized structure, hardpoints, finite skinning of every frame and fixed anatomical lengths. Edge stretch is review evidence, not an automatic visual quality verdict.')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=Path('zig-out/neural-monsters/episode1'))
    parser.add_argument('--models',nargs='+')
    args=parser.parse_args();root=args.out.resolve()
    ledger=json.loads((root/'pipeline.json').read_text());results=[]
    for row in ledger['actors']:
        if args.models and row['slug'] not in args.models:continue
        if row['stages'].get('convert',{}).get('state')!='complete':raise ValueError('Incomplete conversion: '+row['slug'])
        results.append(audit(root/row['slug']))
        print(row['slug']+': all-frame structural audit passed',flush=True)
    save(root/'quality-audit.json',dict(actors=results,total_frames=sum(r['frames'] for r in results)))


if __name__=='__main__':main()
