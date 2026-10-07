# SPDX-License-Identifier: GPL-2.0-or-later
"""Measured Venomvermin quadruped with connected limbs and new performances."""
import json
from pathlib import Path
import numpy as np
import skeletal_iqm as sk


def build(model, source):
    names, parents, positions = [], [], []
    def joint(name, parent, point):
        names.append(name); parents.append(names.index(parent) if parent else -1); positions.append(point)
    joint('body', None, [-10,0,6])
    joint('spine','body',[-4,0,9])
    joint('neck','spine',[4,0,6])
    joint('head','neck',[11,0,3])
    chains=[]
    for end,anchors in [('front',[(2,9,2),(7,12,-6),(12,13,-12)]),
                         ('hind',[(-22,10,2),(-28,12,-6),(-25,13,-12)])]:
        for side,sign in [('l',1),('r',-1)]:
            chain=[]
            parent='spine' if end=='front' else 'body'
            for stem,point in zip(('upper','lower','foot'),anchors):
                name=end+'_'+stem+'_'+side
                joint(name,parent,[point[0],point[1]*sign,point[2]])
                chain.append(len(names)-1);parent=name
            chains.append((end,sign,chain))
    absolute=np.tile(np.eye(4),(len(names),1,1));absolute[:,:3,3]=positions
    model.names,model.parents=names,parents
    model.bind=sk.channels(absolute,parents)
    points=model.arrays[0];scores=np.zeros((len(points),len(names)))
    def capsule(j,a,b,radius):
        a,b=np.asarray(a),np.asarray(b);delta=b-a
        t=np.clip((points-a)@delta/max(float(delta@delta),1e-8),0,1)
        square=np.sum((points-a-t[:,None]*delta)**2,axis=1)
        return np.exp(-square/(radius*radius))
    scores[:,0]=capsule(0,[-25,0,6],[2,0,6],9)
    scores[:,1]=capsule(1,[-18,0,10],[2,0,9],8)
    scores[:,2]=capsule(2,[2,0,6],[8,0,4],5)
    scores[:,3]=capsule(3,[8,0,4],[15,0,0],5)
    for end,sign,chain in chains:
        territory=(points[:,1]*sign>0)&((points[:,0]>-10) if end=='front' else (points[:,0]<=-10))
        for first,last in zip(chain[:2],chain[1:]):
            scores[:,first]=capsule(first,positions[first],positions[last],4)*territory
        foot=chain[-1];scores[:,foot]=capsule(foot,np.asarray(positions[foot])+[-1,0,0],np.asarray(positions[foot])+[3,0,-1],2.8)*territory
    indices=np.argsort(-scores,axis=1)[:,:4]
    weights=np.take_along_axis(scores,indices,axis=1)
    weights=np.rint(weights/np.maximum(weights.sum(axis=1,keepdims=True),1e-20)*255).astype(int)
    weights[:,0]+=255-weights.sum(axis=1)
    model.arrays[4],model.arrays[5]=indices.astype('u1'),weights.astype('u1')
    count=len(source['metadata']['frames']);model.frames=np.repeat(model.bind[None],count,axis=0)
    floor=float(points[:,2].min())
    def rotate(frame,j,angle):
        frame[j,3:7]=[0,np.sin(angle/2),0,np.cos(angle/2)]
    for sequence in source['metadata']['sequences']['frame_data']:
        first,last=sequence['first'],sequence['last'];label=sequence['animation_name'];moving=label.startswith(('run','walk'));dying=label.startswith(('die','dead'))
        for i,f in enumerate(range(first,last+1)):
            phase=i/(last-first+1 if moving or label.startswith('amb') else max(last-first,1))
            frame=model.bind.copy()
            rotate(frame,0,.07 if label.startswith('run') else .03 if moving else 0)
            if moving:
                for end,sign,chain in chains:
                    t=phase+(0 if sign>0 else .5)+(0 if end=='front' else .5)
                    angle=(.32 if label.startswith('run') else .2)*np.sin(t*2*np.pi)
                    knee=(.3 if label.startswith('run') else .2)*np.sin(t*2*np.pi+.6)
                    rotate(frame,chain[0],angle);rotate(frame,chain[1],knee)
                    rotate(frame,chain[2],-(angle+knee))
            elif label.startswith(('atak','aatk')):
                strike=np.sin(phase*np.pi)**2
                rotate(frame,3,.16*strike)
                for end,sign,chain in chains:
                    if end=='front':
                        rotate(frame,chain[0],-.55*strike);rotate(frame,chain[1],.25*strike)
            elif label.startswith('hit'):rotate(frame,3,-.12*np.sin(phase*np.pi))
            elif label.startswith('amb'):rotate(frame,3,.015*np.sin(phase*2*np.pi))
            if dying:
                collapse=1. if label.startswith('dead') else phase*phase*(3-2*phase)
                rotate(frame,0,-.9*collapse)
                for end,sign,chain in chains:rotate(frame,chain[0],.45*collapse)
            model.frames[f]=frame
            # Ground the actual paw/body surface throughout authored motion.
            bottom=sk.skin(model,model.frames[f:f+1])[0,:,2].min()
            model.frames[f,0,2]+=floor-bottom
    # The existing generic-body ABI uses contiguous creature_NN labels.
    # Semantic landmarks remain in the conversion receipt.
    model.names=[f'creature_{i:02}' for i in range(len(names))]
    sk.validate(model)
    return model,dict(rig='Measured connected quadruped, capsule-localized weights and independently authored motion',
        physics='articulated',joints=len(names),body_joints=len(names),source_frames=count,output_frames=count,
        rms=None,maximum_residual=None,motion='New quadruped performances; exact source sequence/event intervals retained',
        landmarks=dict(zip(names,positions)),body_bones=dict(zip(names,model.names)),clips=source['metadata']['sequences']['frame_data'],
        limits=['New motion is not an exact reproduction of source vertex poses.','Four-paw contact is approximated by grounded FK; no independent foot IK.'])


def convert(actor):
    actor=Path(actor)
    source=json.loads((actor/'source.json').read_text())
    if source['actor']['slug']!='venomvermin':raise ValueError('Reviewed quadruped landmarks belong to Venomvermin')
    model=sk.read((actor/'model.iqm').read_bytes())
    model,report=build(model,source)
    (actor/'model.iqm').write_bytes(sk.write(model))
    conversion=json.loads((actor/'conversion.json').read_text());conversion.update(report)
    (actor/'conversion.json').write_text(json.dumps(conversion,indent=2,sort_keys=True)+'\n')
