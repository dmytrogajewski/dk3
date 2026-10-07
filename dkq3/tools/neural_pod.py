# SPDX-License-Identifier: GPL-2.0-or-later
"""Rigid egg-shell petals on hinges; preserve the original hatch frame interval."""
import numpy as np
import skeletal_iqm as sk


def fit_pod(document,geometry,surfaces,triangles):
    points=geometry[0];low=points.min(axis=0);high=points.max(axis=0)
    center=(low+high)/2;height=high[2]-low[2];split=low[2]+height*.28
    centroids=points[triangles].mean(axis=1)
    angle=np.arctan2(centroids[:,1]-center[1],centroids[:,0]-center[0])
    regions=1+np.floor((angle+np.pi/4)%(2*np.pi)/(np.pi/2)).astype(int)
    regions[centroids[:,2]<split]=0
    # Each panel owns its boundary vertices. No triangle is stretched across
    # two independently opening rigid shell sections.
    vertices=[];joints=[];faces=[];meshes=[]
    for name,material,fv,nv,ft,nt in surfaces:
        cache={};start_v=len(vertices);start_t=len(faces)
        def finish():
            nonlocal cache,start_v,start_t
            if len(faces)>start_t:
                meshes.append((f'pod_{len(meshes):03}',material,start_v,len(vertices)-start_v,start_t,len(faces)-start_t))
            cache={};start_v=len(vertices);start_t=len(faces)
        for t in range(ft,ft+nt):
            keys=[(int(v),int(regions[t])) for v in triangles[t]]
            if len(cache)+len(set(keys)-cache.keys())>=1000:finish()
            indices=[]
            for v,region in keys:
                if (v,region) not in cache:
                    cache[v,region]=len(vertices);vertices.append(v);joints.append(region)
                indices.append(cache[v,region])
            faces.append(indices)
        finish()
    arrays={k:v[vertices].copy() for k,v in geometry.items() if k in (0,1,2)}
    arrays[4]=np.column_stack((joints,np.zeros((len(joints),3)))).astype('u1')
    arrays[5]=np.tile(np.array([255,0,0,0],dtype='u1'),(len(vertices),1))
    names=[f'creature_{i:02}' for i in range(5)];parents=[-1,0,0,0,0]
    bind=np.tile(np.eye(4),(5,1,1));bind[0,:3,3]=[center[0],center[1],low[2]]
    for i in range(4):
        theta=i*np.pi/2
        radial=np.array([np.cos(theta),np.sin(theta),0.])
        bind[i+1,:3,3]=[center[0],center[1],split]
        bind[i+1,:3,3]+=radial*np.ptp(points[:,:2],axis=0).min()*.32
    frames=np.repeat(bind[None],len(document['metadata']['frames']),axis=0)
    for clip in document['metadata']['sequences']['frame_data']:
        if not clip['animation_name'].startswith('hatch'):continue
        first,last=clip['first'],clip['last']
        for f in range(first,last+1):
            progress=(f-first)/max(1,last-first);progress=progress*progress*(3-2*progress)
            opening=progress*np.deg2rad(78)
            for i in range(4):
                theta=i*np.pi/2;axis=np.array([-np.sin(theta),np.cos(theta),0.])
                cross=np.array([[0,-axis[2],axis[1]],[axis[2],0,-axis[0]],[-axis[1],axis[0],0]])
                frames[f,i+1,:3,:3]=np.eye(3)+np.sin(opening)*cross+(1-np.cos(opening))*(cross@cross)
    model=sk.Model(arrays,meshes,np.asarray(faces),names,parents,sk.channels(bind,parents),sk.channels(frames,parents))
    sk.validate(model)
    return model,dict(format=2,rig='Four rigid shell petals and fixed base; independent hinge opening',physics='anchored',
        source_frames=len(frames),output_frames=len(frames),joints=5,body_joints=5,hardpoints=[],rms=None,maximum_residual=None,
        motion='New rigid petal opening; original hatch interval and separate mosquito spawn retained',
        clips=document['metadata']['sequences']['frame_data'],
        limits=['Panel boundaries follow triangle centroids; shell thickness is reconstructed from one image.'])
