# SPDX-License-Identifier: GPL-2.0-or-later
"""Reviewed humanoid landmarks with source-motion fitting and shared character skinning.

Landmarks are measured in the source reference pose, +X forward, +Y left.
The skeleton keeps parent-relative bind lengths throughout the performance.
"""
import numpy as np
import skeletal_iqm as sk
from neural_rig import skin_weights, CLOTH_MODES

# Source capture review: helmeted guard; suited technician; cap/vest workers;
# restrained prisoners; apron-wearing surgeon. Arms may be asymmetric in bind.
LANDMARKS = {
    'mishimaguard': dict(torso=[(0,0,5),(0,0,10),(-1,0,18),(-1,0,25),(1,0,28)],
        arm_l=[(-1,7,23),(-1,8,13),(0,8,3)], arm_r=[(-1,-7,23),(-9,-9,16),(0,-5,8)],
        leg=[(0,4.5,4),(0,5.5,-8),(0,6.5,-21)],toe=(4,6.5,-24)),
    'fatworker': dict(torso=[(0,0,2),(0,0,7),(-1,0,15),(-1,0,21),(0,0,24)],
        arm_l=[(-1,9,19),(-1,12,9),(0,12,0)],arm_r=[(-1,-9,19),(-1,-11,9),(0,-11,0)],
        leg=[(0,5,1),(0,6,-10),(0,6.5,-21)],toe=(4,6.5,-24)),
    'skinnyworker': dict(torso=[(0,0,5),(0,0,10),(-1,0,18),(-1,0,25),(0,0,28)],
        arm_l=[(-1,6,23),(-1,7,13),(0,7,4)],arm_r=[(-1,-6,23),(-1,-7,13),(0,-7,4)],
        leg=[(0,3,4),(0,3.5,-8),(0,3.5,-21)],toe=(4,3.5,-24)),
    'surgeon': dict(torso=[(0,0,5),(0,0,10),(-1,0,18),(-1,0,25),(1,0,28)],
        arm_l=[(-1,8,23),(-5,12,17),(-3,5,7)],arm_r=[(-1,-8,23),(-5,-12,17),(-3,-5,7)],
        leg=[(0,4,4),(0,5,-8),(0,5,-21)],toe=(3,5,-24)),
    'cryotech': dict(torso=[(0,0,5),(0,0,11),(-1,0,20),(-1,0,27),(0,0,31)],
        arm_l=[(-1,9,25),(0,11,15),(1,10,5)],arm_r=[(-1,-9,25),(-8,-12,14),(-3,-9,6)],
        leg=[(0,5,4),(0,6,-7),(1,6,-21)],toe=(5,6,-24)),
    'prisoner': dict(torso=[(2,0,7),(3,0,13),(4,0,22),(6,0,29),(8,0,32)],
        arm_l=[(4,10,28),(10,13,17),(10,13,5)],arm_r=[(4,-10,28),(10,-13,17),(10,-13,5)],
        leg=[(1,5,6),(0,7,-7),(0,7,-21)],toe=(6,7,-24)),
    'prisonerb': dict(torso=[(-4,0,5),(-3,0,11),(-2,0,20),(-1,0,27),(0,0,31)],
        arm_l=[(-2,9,24),(-7,11,15),(-10,3,7)],arm_r=[(-2,-9,24),(-7,-11,15),(-10,-3,7)],
        leg=[(-5,6,4),(-6,8,-8),(-8,8,-21)],toe=(-2,8,-24)),
}


def skeleton(config):
    names,parents,positions=[],[],[]
    def joint(name,parent,position):
        names.append(name);parents.append(names.index(parent) if parent else -1);positions.append(np.array(position,float))
    for name,parent,p in zip(('pelvis','spine','chest','neck','head'),(None,'pelvis','spine','chest','neck'),config['torso']):joint(name,parent,p)
    for side,sign in (('l',1),('r',-1)):
        arm=config['arm_'+side]
        joint('clavicle_'+side,'chest',np.array(config['torso'][2])+[0,sign*3,2])
        for name,parent,p in zip(('upperarm','forearm','hand'),('clavicle','upperarm','forearm'),arm):joint(name+'_'+side,parent+'_'+side,p)
        wrist=np.array(arm[-1],float);direction=(wrist-np.array(arm[-2],float));direction/=np.linalg.norm(direction)
        joint('fingers_'+side,'hand_'+side,wrist+direction*2)
        joint('thumb_'+side,'hand_'+side,wrist+[1,-sign*.8,-.5])
        mirror=np.array([1,sign,1])
        for name,parent,p in zip(('thigh','shin','foot'),('pelvis','thigh','shin'),config['leg']):joint(name+'_'+side,parent if parent=='pelvis' else parent+'_'+side,np.array(p)*mirror)
        joint('toe_'+side,'foot_'+side,np.array(config['toe'])*mirror)
    bind=np.tile(np.eye(4),(len(names),1,1));bind[:,:3,3]=positions
    return names,parents,bind


BIPEDS=frozenset(('cryotech','fatworker','mishimaguard','skinnyworker','surgeon','inmater','ragemaster','sludgeminion','hiro','mikiko','superfly','mishima','usagi'))
from neural_assets import STORY_CHARACTERS
BIPEDS=BIPEDS|STORY_CHARACTERS.keys()


def measured_landmarks(points,slug):
    """Measure the neutral mesh, retaining per-identity torso/cloth landmarks."""
    from neural_rig import LANDMARKS as characters
    base=characters.get(slug,characters['hiro'])
    config=dict(torso=base['torso'],leg=base['leg'],toe=base['toe'])
    torso=np.asarray(config['torso'],float);torso[:,0]=0;config['torso']=torso.tolist()
    # The distal arm stays outside the torso even for heavy shoulder armor.
    for side,sign in (('l',1),('r',-1)):
        arm=[]
        heights=[p[2] for p in base['arm']]
        for z,minimum,maximum in zip(heights,(5,8,10),(14,20,25)):
            band=points[(np.abs(points[:,2]-z)<2.0)&(points[:,1]*sign>minimum)&(points[:,1]*sign<maximum)]
            if len(band)<8:raise ValueError(f'{slug}: no clear A-pose {side} arm at height {z}; review neutral geometry')
            cutoff=np.quantile(band[:,1]*sign,.7)
            center=band[band[:,1]*sign>=cutoff].mean(axis=0)
            center[2]=z
            if z==heights[0]:center[1]-=sign*1.5
            arm.append(center.tolist())
        config['arm_'+side]=arm
    feet=points[(points[:,2]<-19)&(points[:,2]>-24.1)]
    spread=[]
    for sign in (1,-1):
        selected=feet[feet[:,1]*sign>1]
        if len(selected):spread.append(np.median(selected[:,1]*sign))
    width=float(np.mean(spread)) if spread else 7.
    config['leg']=[(0,width*.7,5),(0,width*.9,-8),(0,width,-21)]
    config['toe']=(4,width,-23)
    from neural_mechanical import ROBOTS,arms
    if slug in ROBOTS:
        config.update(arms(points,slug))
    return config


def append_attachment(names,parents,bind,name,parent,offset):
    if name in names:return bind
    names.append(name);parents.append(names.index(parent));row=np.eye(4);row[:3,3]=bind[parents[-1],:3,3]+offset
    return np.concatenate((bind,row[None]))


def fit_humanoid(document,arrays,geometry,surfaces,triangles,rigid=None):
    """Author new anatomical performances; preserve original event intervals."""
    from neural_rig import pose,clips
    from neural_assets import clip_name
    slug=document['actor']['slug'];character=document['actor'].get('kind')=='character'
    points=geometry[0];low=points[:,2].min();scale=(points[:,2].max()-low)/56
    center_y=(points[:,1].min()+points[:,1].max())/2
    height=(points[:,2]-low)/scale-24
    torso=points[(height>8)&(height<22)&(np.abs(points[:,1]-center_y)<5*scale)]
    center_x=float(np.median(torso[:,0])) if len(torso) else float(np.median(points[:,0]))
    offset=np.array([center_x,center_y,low+24*scale]);geometry[0]=(points-offset)/scale
    config=measured_landmarks(geometry[0],slug)
    names,parents,bind=skeleton(config)
    # Preserve the existing character attachment contract.
    for name,parent,delta in (('tag_torso','spine',[0,0,0]),('tag_head','head',[0,0,0]),('tag_weapon','hand_r',[1.5,0,-1.8])):
        bind=append_attachment(names,parents,bind,name,parent,np.asarray(delta))
    if slug in CLOTH_MODES:
        for name,delta in (('cloth_front',[4,0,5]),('cloth_back',[-3,0,5])):
            names.append(name);parents.append(0);row=np.eye(4);row[:3,3]=delta;bind=np.concatenate((bind,row[None]))
    for name in document['tags']:
        parent='head' if 'head' in name or name.startswith('eye') else 'hand_l' if name=='sword1' else 'tag_weapon'
        delta=np.array([4.,2 if name=='eye1' else -2,0]) if name.startswith('eye') else np.zeros(3)
        bind=append_attachment(names,parents,bind,name,parent,delta)
    model=sk.Model(geometry,surfaces,triangles,names,parents,sk.channels(bind,parents),sk.channels(bind,parents)[None])
    skin_weights(model,slug,bind,landmarks=config)
    from neural_mechanical import ROBOTS,rigid_panels
    if slug in ROBOTS:
        rigid_panels(model)
    # Protect the long Cryotech rifle from leg influences. This geometric band
    # covers its outward barrel beyond the wrist; the grip stays hand-owned.
    if slug=='cryotech':
        hand=names.index('hand_r');wrist=bind[hand,:3,3];direction=np.array([0.,-1.,-1.]);direction/=np.linalg.norm(direction)
        delta=geometry[0]-wrist;along=delta@direction;distance=np.linalg.norm(delta-along[:,None]*direction,axis=1)
        gun=(along>1)&(distance<2.5)&(geometry[0][:,1]<wrist[1]-1)
        model.arrays[4][gun]=hand;model.arrays[5][gun]=[255,0,0,0]
    definitions=None
    if character:
        definitions=clips(model,bind)
    else:
        frames=len(document['metadata']['frames']);model.frames=np.repeat(model.bind[None],frames,axis=0)
        grip='relaxed' if slug in ('fatworker','skinnyworker') else 'pistol' if slug=='mishimaguard' else 'rifle' if slug=='cryotech' else 'glove'
        kinds={'LEGS_IDLE':'idle','LEGS_WALK':'walk','LEGS_RUN':'run','LEGS_BACK':'back','LEGS_WALKCR':'crouch_walk','LEGS_IDLECR':'crouch','LEGS_JUMP':'jump','LEGS_LAND':'land','LEGS_SWIM':'swim','BOTH_DEATH1':'death','BOTH_DEAD1':'dead','TORSO_ATTACK':'attack','TORSO_ATTACK2':'attack'}
        for sequence in document['metadata']['sequences']['frame_data']:
            first,last=sequence['first'],sequence['last'];kind=kinds.get(clip_name(sequence['animation_name']),'idle');count=last-first+1
            loop=kind in ('idle','walk','run','back','crouch_walk','crouch','swim')
            for frame in range(count):
                phase=frame/(count if loop else max(1,count-1))
                if slug in ROBOTS:
                    from neural_mechanical import motion
                    model.frames[first+frame]=motion(model,bind,phase,kind)
                else:model.frames[first+frame]=pose(model,bind,phase,kind,grip)
    # Masters use the existing 56-unit character contract. Monster assets retain
    # their source dimensions; collision/render-scale metadata stays authoritative.
    if not character:
        model.arrays[0]=model.arrays[0]*scale+offset
        model.bind[:,:3]*=scale;model.frames[:,:,:3]*=scale
        model.bind[0,:3]+=offset;model.frames[:,0,:3]+=offset
    sk.validate(model)
    report=dict(format=2,rig='Anatomical A-pose skeleton; shared Hiro/Mikiko localized welded weights, fixed-length IK and independently authored motion',
        physics='humanoid',source_frames=len(document['metadata']['frames']),output_frames=len(model.frames),joints=len(names),body_joints=len(names),hardpoints=document['tags'],landmarks=config,
        rms=None,maximum_residual=None,clips=definitions if character else document['metadata']['sequences']['frame_data'],
        motion='New skeletal performances; source sequence names and event intervals retained',
        limits=['Anatomical landmarks and extreme joint folds require mesh review.','New body motion is not an exact reproduction of the original vertex poses.'])
    if slug in ROBOTS:
        report['rig']='Measured mechanical joints and rigid armor triangles; shared fixed-length biped motion and physics'
        report['limits'].append('Armor articulation boundaries are triangle regions; closed claws follow their hand segment.')
    return model,report
