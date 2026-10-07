#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Export a coherent character surface and per-texel PBR colour from TRELLIS.

Uses an existing local, weights-only generator checkpoint. No inference,
network, atlas painting, source modification or runtime scripting occurs.
The reviewed upstream extractor is read-only; its final local topology cleanup
runs before UV creation and texture sampling.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import time

POSTPROCESS_SHA256='ef51a1ba0f2748ffb4c265b47d382cee956f23c6a52d0f3587e6d8beccb7e54a'


def digest(path: Path) -> str:
    result=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):result.update(block)
    return result.hexdigest()


def validate_settings(band: float, projection: float, triangles: int) -> None:
    import math
    if not math.isfinite(band) or not .1<=band<=8:
        raise ValueError('surface band must be finite and in [.1, 8] voxels')
    if not math.isfinite(projection) or not 0<=projection<=1:
        raise ValueError('projection must be finite and in [0, 1]')
    if type(triangles) is not int or not 1000<=triangles<=100000:
        raise ValueError('triangle budget must be an integer in [1000, 100000]')


def export(source: Path, actor: Path, output: Path, band: float,
           projection: float, triangles: int) -> dict:
    validate_settings(band,projection,triangles)
    source=source.resolve(strict=True);actor=actor.resolve(strict=True)
    output=output.resolve()
    if output.exists():raise ValueError('output must be a fresh directory')
    postprocess=source/'o-voxel/o_voxel/postprocess.py'
    if digest(postprocess)!=POSTPROCESS_SHA256:raise ValueError('unreviewed upstream surface extractor')
    files={name:actor/name for name in ('concept.png','source.json','source.npz','generated-mesh.pt','generated-mesh.json','trellis.json')}
    for name,path in files.items():
        limit=1024*1024*1024 if name.endswith('.pt') else 512*1024*1024 if name.endswith('.npz') else 64*1024*1024
        if not path.is_file() or path.stat().st_size>limit:raise ValueError('missing or oversized input: '+name)
    for name in ('source.json','generated-mesh.json','trellis.json'):
        if files[name].stat().st_size>1024*1024:raise ValueError('oversized receipt: '+name)
    receipt=json.loads(files['trellis.json'].read_text(encoding='utf-8'))
    sampled=json.loads(files['generated-mesh.json'].read_text(encoding='utf-8'))
    image_sha=digest(files['concept.png'])
    if receipt.get('generator')!='microsoft/TRELLIS.2-4B' or receipt.get('input_sha256')!=image_sha or sampled.get('image')!=image_sha or sampled.get('resolution')!=receipt.get('resolution') or sampled.get('seed')!=receipt.get('seed'):
        raise ValueError('checkpoint/image/generator receipts disagree')
    sys.path.insert(0,str(source))
    import torch
    import cumesh
    import o_voxel
    saved=torch.load(files['generated-mesh.pt'],map_location='cpu',weights_only=True)
    keys={'vertices','faces','coords','attrs','origin','voxel_size','voxel_shape','layout'}
    if not isinstance(saved,dict) or set(saved)!=keys:raise ValueError('unexpected checkpoint schema')
    for name,width,count in (('vertices',3,8000000),('faces',3,16000000),('coords',3,8000000),('attrs',6,8000000)):
        value=saved[name]
        if not isinstance(value,torch.Tensor) or value.ndim!=2 or value.shape[1]!=width or not 1<=len(value)<=count:
            raise ValueError('oversized or malformed checkpoint tensor: '+name)
        if not torch.isfinite(value).all():raise ValueError('nonfinite checkpoint tensor: '+name)
    if saved['faces'].dtype not in (torch.int32,torch.int64) or saved['coords'].dtype not in (torch.int32,torch.int64):raise ValueError('integer indices required')
    if saved['faces'].min()<0 or saved['faces'].max()>=len(saved['vertices']):raise ValueError('invalid checkpoint faces')
    if len(saved['coords'])!=len(saved['attrs']) or saved['coords'].min()<0 or saved['coords'].max()>=1536:raise ValueError('invalid voxel attributes')
    if saved['origin']!=[-.5,-.5,-.5] or not 1/1536<=saved['voxel_size']<=1/512:raise ValueError('unsupported voxel coordinates')
    if saved['layout']!={'base_color':[0,3,None],'metallic':[3,4,None],'roughness':[4,5,None],'alpha':[5,6,None]}:raise ValueError('unsupported PBR channels')
    if not torch.cuda.is_available():raise RuntimeError('local CUDA device required')
    cleanup=[];original_unwrap=cumesh.CuMesh.uv_unwrap
    def unwrap(mesh, *args, **kwargs):
        before=[mesh.num_vertices,mesh.num_faces]
        mesh.remove_duplicate_faces()
        mesh.repair_non_manifold_edges()
        mesh.fill_holes(max_hole_perimeter=.03)
        mesh.unify_face_orientations()
        cleanup.append(dict(before=before,after=[mesh.num_vertices,mesh.num_faces],hole_perimeter_limit=.03))
        return original_unwrap(mesh,*args,**kwargs)
    cumesh.CuMesh.uv_unwrap=unwrap
    started=time.monotonic()
    try:
        glb=o_voxel.postprocess.to_glb(vertices=saved['vertices'].cuda(),faces=saved['faces'].cuda(),
            attr_volume=saved['attrs'].cuda(),coords=saved['coords'].cuda(),
            attr_layout={key:slice(*value) for key,value in saved['layout'].items()},voxel_size=saved['voxel_size'],
            aabb=[[-.5,-.5,-.5],[.5,.5,.5]],decimation_target=triangles,texture_size=4096,
            remesh=True,remesh_band=band,remesh_project=projection,verbose=False,use_tqdm=False)
    finally: cumesh.CuMesh.uv_unwrap=original_unwrap
    output.mkdir(parents=True)
    for name in ('concept.png','source.json','source.npz'):shutil.copy2(files[name],output/name)
    temporary=output/'model.pending.glb';glb.export(str(temporary),extension_webp=True);temporary.replace(output/'model.glb')
    receipt['glb_sha256']=digest(output/'model.glb')
    receipt['extraction']=dict(checkpoint_sha256=digest(files['generated-mesh.pt']),
        source_sha256=POSTPROCESS_SHA256,tool_sha256=digest(Path(__file__)),band=band,projection=projection,
        triangles=triangles,texture_size=4096,texture_method='Per-texel sparse PBR volume sampling',
        local_topology_cleanup=cleanup,seconds=time.monotonic()-started,torch=torch.__version__,device=torch.cuda.get_device_name())
    (output/'trellis.json').write_text(json.dumps(receipt,sort_keys=True,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    return dict(passed=True,output=str(output),glb_sha256=receipt['glb_sha256'],extraction=receipt['extraction'],visual_acceptance='unverified')


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True);parser.add_argument('--actor',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True);parser.add_argument('--band',type=float,default=3.)
    parser.add_argument('--projection',type=float,default=0.);parser.add_argument('--triangles',type=int,default=100000)
    args=parser.parse_args()
    try:print(json.dumps(export(args.source,args.actor,args.out,args.band,args.projection,args.triangles),sort_keys=True,allow_nan=False))
    except (OSError,ValueError,RuntimeError,KeyError) as error:
        print(json.dumps(dict(passed=False,diagnostics=[dict(code='ANIM_CHARACTER_EXPORT',message=str(error))])),file=sys.stderr)
        raise SystemExit(1)


if __name__=='__main__':main()
