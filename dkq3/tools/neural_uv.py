#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Use the pinned local xatlas installation for a head-weighted runtime atlas."""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import xatlas
from neural_surface_quality import uv_quality


def unwrap(source,output,resolution=4096,partition_orientations=False):
    version=importlib.metadata.version('xatlas')
    if version!='0.0.11':raise ValueError('Qualify a new xatlas version before changing the pinned atlas producer')
    data=np.load(source);points=data['points'];triangles=data['triangles'];head=data['head']
    regions_key=head.astype(int)
    if partition_orientations:
        # Closed hair/cloth shells can have thousands of tiny handles. Bound
        # each chart search to one cube-facing surface region while retaining
        # every triangle and the existing head texel-density policy.
        corners=points[triangles]
        normals=np.cross(corners[:,1]-corners[:,0],corners[:,2]-corners[:,0])
        axes=np.abs(normals).argmax(axis=1)
        signs=np.take_along_axis(normals,axes[:,None],axis=1)[:,0]<0
        regions_key=head.astype(int)*6+axes*2+signs
    charts=xatlas.ChartOptions();charts.max_iterations=4
    packing=xatlas.PackOptions();packing.resolution=resolution;packing.padding=8
    packing.bilinear=True;packing.blockAlign=True
    isolated=set();attempts=[]
    # Every unsuccessful pass must isolate at least one new face. This gives
    # a finite bound without an arbitrary retry limit for more complex robes.
    for attempt in range(len(triangles)+1):
        atlas=xatlas.Atlas();regions=[]
        ordinary=np.ones(len(triangles),bool);ordinary[list(isolated)]=False
        groups=[np.flatnonzero((regions_key==region)&ordinary) for region in np.unique(regions_key)]
        groups+=[np.asarray([i]) for i in sorted(isolated)]
        for faces in groups:
            if not len(faces):continue
            used,inverse=np.unique(triangles[faces],return_inverse=True)
            local=inverse.reshape(-1,3).astype('u4')
            # Scale only the UV input. Runtime geometry is untouched.
            positions=(points[used]*(2.5 if head[faces[0]] else 1.)).astype('f4')
            if len(faces)==1 and int(faces[0]) in isolated:
                # Microscopic slivers can collapse to zero area in xatlas's
                # pixel quantization even as independent charts. Parameterize
                # just those faces with a regular chart and minimum footprint.
                # Runtime positions and triangle order remain exact.
                corner=positions[local[0]]
                area=float(np.linalg.norm(np.cross(corner[1]-corner[0],corner[2]-corner[0])))*.5
                if not area>0:raise ValueError('Cannot unwrap a zero-area surface triangle')
                minimum=float(np.ptp(points,axis=0).max())*(2.5 if head[faces[0]] else 1.)*.002
                length=max(float(np.sqrt(4*area/np.sqrt(3))),minimum)
                positions=positions.copy()
                positions[local[0]]=np.asarray([[0,0,0],[length,0,0],[length*.5,length*np.sqrt(3)*.5,0]],dtype='f4')
            atlas.add_mesh(positions,local);regions.append((faces,local))
        atlas.generate(chart_options=charts,pack_options=packing)
        uv=np.zeros((len(triangles),3,2),dtype='f4')
        for i,(faces,local) in enumerate(regions):
            mapping,indices,coordinates=atlas[i]
            if not np.array_equal(mapping[indices],local):raise ValueError('Atlas changed triangle order or winding')
            assigned=atlas.get_mesh_vertex_assignment(i)[0][indices]
            orphan=assigned==np.iinfo(np.uint32).max
            if np.any((assigned!=0)&~orphan):
                raise ValueError('Runtime requires every triangle in one atlas: '+str(np.unique(assigned,return_counts=True)))
            uv[faces]=coordinates[indices]
            # xatlas leaves quantized slivers unassigned. Their zero-area
            # placeholder is handled by the same explicit conflict isolation
            # and regular-chart qualification as collapsed UV triangles.
            uv[faces[np.any(orphan,axis=1)]]=0.
        quality=uv_quality(SimpleNamespace(arrays={1:uv.reshape(-1,2)},triangles=np.arange(len(uv)*3).reshape(-1,3)),details=True)
        conflicts=set(quality.pop('conflicting_triangles'));attempts.append(quality)
        print('Atlas qualification',attempt,quality,flush=True)
        if not conflicts:break
        # Rare folded chart slivers get independent charts, preserving all
        # actual geometry and letting xatlas pack them with the same density.
        if conflicts<=isolated:raise ValueError('Independent atlas charts are still invalid: '+str(quality))
        isolated.update(conflicts)
    else:raise ValueError('xatlas could not remove atlas conflicts: '+str(quality))
    np.savez_compressed(output,uv=uv)
    distribution=importlib.metadata.distribution('xatlas')
    license_file=next(distribution.locate_file(f) for f in distribution.files if str(f).endswith('licenses/LICENSE'))
    license_path=output.with_suffix('.LICENSE.txt');license_path.write_bytes(license_file.read_bytes())
    report=dict(producer='xatlas',version=version,source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                output_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                atlas_width=atlas.width,atlas_height=atlas.height,utilization=atlas.utilization,
                resolution=resolution,padding=8,head_density_multiplier=2.5,uv_quality=quality,
                qualifications=attempts,independent_conflict_charts=len(isolated),
                isolated_chart_parameterization='Regular minimum-footprint triangle charts for quantized slivers; exact runtime geometry',
                license=dict(path=license_path.name,sha256=hashlib.sha256(license_path.read_bytes()).hexdigest(),name='MIT'))
    if partition_orientations:report['chart_regions']='Six dominant normal orientations per density region; exact geometry retained'
    output.with_suffix('.json').write_text(json.dumps(report,indent=2)+'\n')
    print('xatlas qualified:',quality,'size',atlas.width,atlas.height,flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True);parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--resolution',type=int,default=4096)
    parser.add_argument('--partition-orientations',action='store_true')
    args=parser.parse_args();unwrap(args.source,args.out,args.resolution,args.partition_orientations)
