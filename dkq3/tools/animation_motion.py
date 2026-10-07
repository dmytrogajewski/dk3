# SPDX-License-Identifier: GPL-2.0-or-later
"""Reproducible motion interchange, anatomical retargeting and measurable cleanup.

All distances are DK3 model units. Removed root travel is retained alongside an
in-place clip so a planted foot is checked in its virtual moving world, rather
than incorrectly requiring stationary feet in an in-place animation.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation, Slerp

import skeletal_iqm as sk
from animation_manifest import Error, fields, number, span, prop_contacts
from neural_assets import align_vectors, connected_motion


@dataclass
class Motion:
    names: list
    parents: list
    rest: np.ndarray
    world: np.ndarray
    fps: float
    travel: np.ndarray
    metadata: dict


def read(path):
    with np.load(path, allow_pickle=False) as data:
        motion = Motion(data['names'].tolist(), data['parents'].tolist(), data['rest'].copy(),
                        data['world'].copy(), float(data['fps']), data['travel'].copy(),
                        json.loads(str(data['metadata'])))
    validate_motion(motion)
    return motion


def validate_motion(motion):
    n,f = len(motion.names),len(motion.world)
    if not 0<n<=512 or not 0<f<=65536 or len(set(motion.names))!=n or len(motion.parents)!=n:
        raise Error('invalid motion joint/frame counts')
    if any(p < -1 or p>=j for j,p in enumerate(motion.parents)):
        raise Error('motion parents must precede children')
    if motion.world.shape!=(f,n,4,4) or motion.rest.shape!=(n,4,4) or motion.travel.shape!=(f,3):
        raise Error('invalid motion matrix/travel dimensions')
    number(motion.fps, .001, 240, 'motion fps')
    for name, array in (('world',motion.world),('rest',motion.rest),('travel',motion.travel)):
        if not np.isfinite(array).all(): raise Error('nonfinite motion '+name)
    for array in (motion.world,motion.rest):
        if not np.allclose(array[...,3,:], [0,0,0,1],atol=1e-5): raise Error('invalid homogeneous motion transform')
        rotation=array[...,:3,:3]
        if not np.allclose(rotation.swapaxes(-1,-2)@rotation,np.eye(3),atol=2e-4) or not np.allclose(np.linalg.det(rotation),1,atol=2e-4):
            raise Error('motion must have rigid unit-scale transforms; apply source object scale before import')
    for name,channels in motion.metadata.get('auxiliary',{}).items():
        data=np.asarray(channels)
        if name not in motion.names or not name.startswith('prop_') or data.shape!=(f,10) or not np.isfinite(data).all():
            raise Error('invalid auxiliary prop channels')
        if (data[:,7:10]<0).any() or (data[:,7:10]>16).any():raise Error('invalid auxiliary prop scale')
    captured=motion.metadata.get('source_props',{})
    if not isinstance(captured,dict) or len(captured)>16:raise Error('invalid captured prop collection')
    for name,prop in captured.items():
        if not isinstance(name,str) or not name.startswith('prop_'):raise Error('invalid captured prop name')
        fields(prop,('world','visible','reference_frame','surface','rms_max'),('world','visible','reference_frame','surface','rms_max'),'captured prop')
        world=np.asarray(prop['world']);visible=np.asarray(prop['visible'])
        if world.shape!=(f,4,4) or not np.isfinite(world).all() or visible.shape!=(f,) or visible.dtype.kind!='b':
            raise Error('invalid captured prop transforms/visibility', 'ANIM_NONFINITE_TRANSFORM', name)
        r=world[:,:3,:3]
        if not np.allclose(world[:,3,:],[0,0,0,1],atol=1e-5) or not np.allclose(r.swapaxes(-1,-2)@r,np.eye(3),atol=2e-4) or not np.allclose(np.linalg.det(r),1,atol=2e-4):
            raise Error('captured props require rigid transforms', 'ANIM_NONFINITE_TRANSFORM', name)
        number(prop['reference_frame'],0,65535,'prop reference',integer=True)
        number(prop['rms_max'],0,10,'prop residual')


def write(path, motion):
    validate_motion(motion)
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    np.savez_compressed(path,names=np.array(motion.names),parents=np.array(motion.parents),rest=motion.rest,
                        world=motion.world,fps=np.array(motion.fps),travel=motion.travel,
                        metadata=np.array(json.dumps(motion.metadata,allow_nan=False)))


def resample(motion, fps, interval=None, count=None, loop=False):
    number(fps,.001,240,'resample fps')
    a,b=span(interval or [0,len(motion.world)-1])
    if b>=len(motion.world): raise Error('input interval outside motion')
    frames=motion.world[a:b+1];travel=motion.travel[a:b+1]
    duration=(len(frames)-1)/motion.fps
    count=count or max(1,round(duration*fps)+(0 if loop else 1))
    number(count,1,65536,'resample count',integer=True)
    source=np.arange(len(frames))/motion.fps
    target=np.linspace(0,duration,count,endpoint=not loop)
    result=np.broadcast_to(np.eye(4),(count,len(motion.names),4,4)).copy()
    if len(frames)==1:
        result[:]=frames[0];trajectory=np.repeat(travel[:1],count,axis=0)
    else:
        for j in range(len(motion.names)):
            result[:,j,:3,:3]=Slerp(source,Rotation.from_matrix(frames[:,j,:3,:3]))(target).as_matrix()
            for k in range(3):result[:,j,k,3]=np.interp(target,source,frames[:,j,k,3])
        trajectory=np.array([np.interp(target,source,travel[:,k]) for k in range(3)]).T
    # Count-based temporal warping is explicit: the emitted rate defines the
    # output duration, while metadata preserves the consumed source interval.
    metadata=dict(motion.metadata,resample=dict(input_frames=[a,b],input_seconds=duration,output_frames=count,fps=fps,loop=loop))
    if metadata.get('auxiliary'):
        metadata['auxiliary']={n:sample_channels(np.asarray(v)[a:b+1],count,loop).tolist() for n,v in metadata['auxiliary'].items()}
    if metadata.get('source_props'):
        captured={}
        for name,prop in metadata['source_props'].items():
            channels=sk.channels(np.asarray(prop['world'])[a:b+1,None],[-1])[:,0]
            values=sample_channels(channels,count,loop)
            times=np.linspace(a,b,count,endpoint=not loop)
            captured[name]=dict(prop,world=sk.matrices(values[:,None],[-1])[:,0].tolist(),
                               visible=np.asarray(prop['visible'])[np.rint(times).astype(int)].tolist())
        metadata['source_props']=captured
    for key in ('source_hand_points','source_directions'):
        if metadata.get(key):
            metadata[key]={name:np.array([np.interp(target,source,np.asarray(values)[a:b+1,k]) for k in range(3)]).T.tolist() for name,values in metadata[key].items()}
    if metadata.get('source_correctives'):
        metadata['source_correctives']={name:sk.matrices(sample_channels(sk.channels(np.asarray(values)[a:b+1,None],[-1])[:,0],count,loop)[:,None],[-1])[:,0].tolist() for name,values in metadata['source_correctives'].items()}
    return Motion(motion.names,motion.parents,motion.rest,result,float(fps),trajectory,metadata)


def root_policy(sampled,mode):
    """Apply the declared path policy even to already-retargeted motion files."""
    if mode=='preserve':
        if not np.any(sampled.travel):return sampled
        world=sampled.world.copy();world[:,:,:3,3]+=sampled.travel[:,None,:]
        return Motion(sampled.names,sampled.parents,sampled.rest,world,sampled.fps,np.zeros_like(sampled.travel),
                      dict(sampled.metadata,root_motion='preserve'))
    if mode!='in_place':raise Error('invalid root_motion')
    roots=[j for j,p in enumerate(sampled.parents) if p<0 and not sampled.names[j].startswith('prop_')]
    if len(roots)!=1:raise Error('in-place motion needs one body root')
    positions=sampled.world[:,roots[0],:3,3]
    removed=positions-positions[0];removed[:,2]=0
    if np.max(np.abs(removed))<1e-8:return sampled
    world=sampled.world.copy();world[:,:,:3,3]-=removed[:,None,:]
    return Motion(sampled.names,sampled.parents,sampled.rest,world,sampled.fps,sampled.travel+removed,
                  dict(sampled.metadata,root_motion='in_place'))


def constant_travel(sampled,speed=None):
    if len(sampled.world)<2:return sampled,None
    measured=float(sampled.travel[-1,0]-sampled.travel[0,0])*sampled.fps/(len(sampled.world)-1)
    if speed is None and abs(measured)<.001:return sampled,None
    speed=number(speed if speed is not None else measured,.001,2000,'in-place forward speed')
    travel=np.zeros_like(sampled.travel);travel[:,0]=np.arange(len(travel))/sampled.fps*speed
    return Motion(sampled.names,sampled.parents,sampled.rest,sampled.world,sampled.fps,travel,
                  dict(sampled.metadata,movement_speed=speed,trajectory='constant forward DK3 actor travel')),speed


def sample_channels(channels,count,loop=False):
    if len(channels)==1:return np.repeat(channels,count,axis=0)
    t=np.linspace(0,len(channels)-1,count,endpoint=not loop);source=np.arange(len(channels))
    result=np.ones((count,10))
    result[:,:3]=np.array([np.interp(t,source,channels[:,k]) for k in range(3)]).T
    result[:,3:7]=Slerp(source,Rotation.from_quat(channels[:,3:7]))(t).as_quat()
    # Visibility is a discrete authored event, never a half-sized weapon.
    result[:,7:10]=channels[np.rint(t).astype(int),7:10]
    return result


def export_channels(sampled):
    local=sk.channels(sampled.world,sampled.parents)
    for name,data in sampled.metadata.get('auxiliary',{}).items():local[:,sampled.names.index(name)]=np.asarray(data)
    # Matrix inversion leaves platform/alignment-dependent residuals in
    # otherwise constant channels. IQM encodes even a 1e-15 range as a moving
    # uint16 channel. Canonicalize generated channels far below runtime
    # precision before computing those ranges; retained source frames are
    # untouched. Canonical zero also removes an unstable negative-zero bit.
    local=np.round(local,12)
    local[local==0]=0
    return local


def source_prop_orientations(model, recipe, contact, count, sampled=None):
    result={}
    for name in contact['members']:
        policy=recipe.get('props',{}).get(name,{'mode':'inherit'})
        if policy['mode']=='captured':
            captured=(sampled.metadata.get('source_props',{}) if sampled is not None else {}).get(name)
            if captured is None:raise Error('captured prop observations missing', 'ANIM_UNOBSERVABLE_MARKER', name)
            result[name]=np.asarray(captured['world'])[:,:3,:3]
            if len(result[name])!=count:raise Error('captured prop frame count differs', 'ANIM_INVALID_RANGE', name)
            continue
        if policy['mode']!='inherit':raise Error('source-world prop orientation requires inherited source motion', 'ANIM_ATTACHMENT_ERROR',name)
        a,b=span(policy.get('frames',recipe['source_frames']))
        if b>=len(model.frames):raise Error('source prop orientation outside source frames', 'ANIM_INVALID_RANGE',name)
        source=model.frames[a:b+1].copy();source[...,7:10]=1
        j=model.names.index(name);world=sk.matrices(source,model.parents)
        channels=sk.channels(world[:,j:j+1],[-1])[:,0]
        result[name]=sk.matrices(sample_channels(channels,count,recipe.get('loop',False))[:,None],[-1])[:,0,:3,:3]
    return result


def prop_contact_mask(visible: np.ndarray, contact: dict) -> np.ndarray:
    """Restrict a grip to explicit intervals, preserving released prop motion."""
    if 'intervals' not in contact:return visible
    active=np.zeros(len(visible),bool)
    for a,b in contact['intervals']:
        if not 0<=a<=b<len(active):raise Error('prop contact interval beyond sampled clip','ANIM_INVALID_RANGE')
        active[a:b+1]=True
    return visible&active


def prop_policy(model,sampled,recipe):
    local=sk.channels(sampled.world,model.parents);aux={};receipt={}
    declared=recipe.get('props',{})
    if any(name not in model.names for name in declared):raise Error('prop policy names absent model joint')
    for j,name in enumerate(model.names):
        if not name.startswith('prop_'):continue
        policy=declared.get(name,{'mode':'inherit'});mode=policy['mode']
        if mode=='inherit':
            a,b=span(policy.get('frames',recipe['source_frames']))
            if b>=len(model.frames):raise Error('prop inheritance outside source model; choose an explicit prop policy')
            values=sample_channels(model.frames[a:b+1,j],len(local),recipe.get('loop',False))
            receipt[name]=dict(mode=mode,source_frames=[a,b])
        elif mode=='captured':
            target=sampled.metadata.get('retarget',{})
            if target and (target.get('scale')!=1 or target.get('forward')!='x' or target.get('up')!='z'):
                raise Error('captured original props require native unit coordinates')
            captured=sampled.metadata.get('source_props',{}).get(name)
            if captured is None:raise Error('captured prop observations missing', 'ANIM_UNOBSERVABLE_MARKER', name)
            world=np.asarray(captured['world']);parent=model.parents[j]
            relative=np.linalg.inv(sampled.world[:,parent])@world if parent>=0 else world
            values=sk.channels(relative[:,None],[-1])[:,0]
            values[:,7:10]=np.asarray(captured['visible'])[:,None]
            receipt[name]=dict(mode=mode,source_md3_sha256=sampled.metadata.get('source_md3_sha256'),reference_frame=captured['reference_frame'])
        elif mode=='hide':
            values=np.repeat(model.bind[j:j+1],len(local),axis=0);values[:,7:10]=0
            receipt[name]=dict(mode=mode)
        elif mode=='attach':
            parent=policy['parent']
            if parent not in model.names:raise Error('unknown prop attachment parent')
            offset=np.eye(4);offset[:3,3]=policy['position'];offset[:3,:3]=Rotation.from_euler('xyz',policy.get('angles',[0,0,0]),degrees=True).as_matrix()
            world=sampled.world[:,model.names.index(parent)]@offset
            original_parent=model.parents[j]
            relative=np.linalg.inv(sampled.world[:,original_parent])@world if original_parent>=0 else world
            values=sk.channels(relative[:,None],[-1])[:,0]
            receipt[name]=dict(policy)
        else:raise Error('unknown prop policy')
        local[:,j]=values;aux[name]=values.tolist()
    contacts=prop_contacts(recipe.get('prop_contacts',[]));contact_reports=[]
    for contact in contacts:
        for name in [contact['parent'],*contact['members'],*contact.get('finger_pose',{})]:
            if name not in model.names:raise Error('unknown grip bone', 'ANIM_UNKNOWN_BONE', name)
    source_rotations={name:rotation for contact in contacts if contact.get('orientation')=='source_world'
                      for name,rotation in source_prop_orientations(model,recipe,contact,len(local),sampled).items()}
    floors=[contact for contact in contacts if contact.get('floor_contact',{}).get('solve',True) and 'floor_contact' in contact]
    if floors:
        finger_channels={j:local[:,j,3:7].copy() for j,n in enumerate(model.names) if n.startswith(('fingers_','thumb_'))}
        options=solver_options(sampled)
        supports={}
        for bone,intervals in recipe.get('contacts',{}).items():
            if bone.startswith('foot_'):
                mask=np.zeros(len(local),bool)
                for a,b in intervals:mask[a:b+1]=True
                supports[model.names.index(bone)]=mask
        for _ in range(6):
            rigid=local.copy();rigid[...,7:10]=1;fitted=sk.matrices(rigid,model.parents)
            for contact in floors:
                parent=model.names.index(contact['parent']);prop=model.names.index(contact['prop']);floor=contact['floor_contact']
                visible=prop_contact_mask(np.max(local[:,prop,7:10],axis=1)>1e-6,contact)
                grip=grip_target(model,sampled,contact,fitted)
                offset=source_rotations[contact['prop']]@(np.asarray(floor['point'])-contact['pivot'])
                error=floor['height']-(grip+offset)[:,2]
                # Keep the original shaft orientation and floor contact;
                # solve the arm up to the grip instead of burying the staff.
                fitted[visible,parent,2,3]+=error[visible]
            # Arm contact cleanup must retain the already-solved foot goals;
            # feeding its previous IK residual back as the next goal drifts.
            for j,mask in supports.items():fitted[mask,j,:3,3]=sampled.world[mask,j,:3,3]
            local=connected_motion(model,fitted,**options)
            for j,q in finger_channels.items():local[:,j,3:7]=q
            for name,values in aux.items():local[:,model.names.index(name)]=values
    for contact in contacts:
        visible=prop_contact_mask(np.max(local[:,model.names.index(contact['prop']),7:10],axis=1)>1e-6,contact)
        # Constant grip controls are authored only for this declared contact;
        # blend at actual visibility boundaries and retain the other pose.
        count=contact.get('blend_frames',4);blend=np.array([visible[max(0,f-count+1):f+1].mean() for f in range(len(local))])
        for name,angles in contact.get('finger_pose',{}).items():
            j=model.names.index(name);base=Rotation.from_quat(local[:,j,3:7])
            target=Rotation.from_euler('xyz',angles,degrees=True)*Rotation.from_quat(model.bind[j,3:7])
            delta=(target*base.inv()).as_rotvec()*blend[:,None]
            local[:,j,3:7]=(Rotation.from_rotvec(delta)*base).as_quat()
    rigid=local.copy();rigid[...,7:10]=1;world=sk.matrices(rigid,model.parents)
    for contact in contacts:
        if contact.get('orientation')=='source_world':
            for name in contact['members']:
                rotation=source_rotations[name]
                world[:,model.names.index(name),:3,:3]=rotation
        j=model.names.index(contact['prop']);parent=model.names.index(contact['parent'])
        visible=prop_contact_mask(np.max(local[:,j,7:10],axis=1)>1e-6,contact)
        source=world[:,j,:3,:3]@np.asarray(contact['pivot'])+world[:,j,:3,3]
        target=grip_target(model,sampled,contact,world)
        delta=target-source
        for name in contact['members']:world[visible,model.names.index(name),:3,3]+=delta[visible]
        contact_reports.append(dict(prop=contact['prop'],orientation=contact.get('orientation','inherit'),visible_frames=int(visible.sum()),
            maximum_before=float(np.linalg.norm(delta[visible],axis=1).max()) if visible.any() else 0))
    if contacts:
        corrected=sk.channels(world,model.parents)
        for name,values in aux.items():
            data=corrected[:,model.names.index(name)].copy();data[:,7:10]=np.asarray(values)[:,7:10];aux[name]=data.tolist()
    metadata=dict(sampled.metadata,auxiliary=aux,props=receipt)
    if contacts:metadata['prop_contacts']=contact_reports
    return Motion(model.names,model.parents,sampled.rest,world,sampled.fps,sampled.travel,metadata)


def grip_target(model: sk.Model, sampled: Motion, contact: dict, world: np.ndarray) -> np.ndarray:
    parent=model.names.index(contact.get('attachment_bone',contact['parent']))
    if not contact.get('source_grip'):
        return world[:,parent,:3,:3]@np.asarray(contact['position'])+world[:,parent,:3,3]
    captured=sampled.metadata.get('source_props',{}).get(contact['prop'])
    observed=sampled.metadata.get('source_hand_points',{}).get(contact['parent'])
    if captured is None or observed is None:raise Error('source grip requires observed hand and prop trajectories','ANIM_UNOBSERVABLE_MARKER',contact['prop'])
    source=np.asarray(captured['world']);hand=np.asarray(observed)
    if hand.shape!=(len(world),3) or not np.isfinite(hand).all():raise Error('invalid source hand trajectory','ANIM_NONFINITE_TRANSFORM')
    # The original performance can slide a hand along a staff. Preserve that
    # measured world-space relationship instead of imposing a fixed rest grip.
    offset=source[:,:3,:3]@np.asarray(contact['pivot'])+source[:,:3,3]-hand
    return world[:,parent,:3,3]+offset


def apply_correctives(model: sk.Model, sampled: Motion, mapping: dict) -> Motion:
    if sampled.metadata.get('kind')=='authored_cinematic':
        # An independently authored clip has no measured vertex correction to
        # reapply. Its corrective bones must simply follow their named parent;
        # validate() checks the local bind channel after resampling.
        for name,source in mapping.items():
            if name not in model.names or not name.startswith('deform_') or source!=name.removeprefix('deform_') or model.parents[model.names.index(name)]!=model.names.index(source):
                raise Error('authored corrective must follow its anatomical parent','ANIM_UNKNOWN_BONE',name)
        return sampled
    expected=sampled.metadata.get('source_correctives',{});world=sampled.world.copy()
    for name,source in mapping.items():
        if name not in model.names or name not in expected:raise Error('corrective observation missing','ANIM_UNOBSERVABLE_MARKER',name)
        transform=np.asarray(expected[name])
        if transform.shape!=(len(world),4,4) or not np.isfinite(transform).all():raise Error('invalid corrective observations','ANIM_NONFINITE_TRANSFORM',name)
        world[:,model.names.index(name)]=transform
    result=Motion(sampled.names,sampled.parents,sampled.rest,world,sampled.fps,sampled.travel,dict(sampled.metadata))
    validate_motion(result);return result


def basis(forward, up):
    axes={'x':np.array([1.,0,0]),'y':np.array([0.,1,0]),'z':np.array([0.,0,1])}
    def axis(name):
        if name.lstrip('-') not in axes: raise Error('axis must be x/y/z or -x/-y/-z')
        return axes[name.lstrip('-')]*(-1 if name.startswith('-') else 1)
    f,u=axis(forward),axis(up)
    if abs(f@u)>.1:raise Error('forward and up axes must differ')
    return np.stack((f,np.cross(u,f),u))


def orientation_basis(forward, up):
    """Orthonormal semantic +X forward/+Z up frame from measured directions."""
    f=np.array(forward,dtype=float,copy=True);u=np.array(up,dtype=float,copy=True)
    if f.shape!=(3,) or u.shape!=(3,) or not np.isfinite([f,u]).all():
        raise Error('orientation directions must be finite three-vectors', 'ANIM_NONFINITE_TRANSFORM')
    if min(np.linalg.norm(f),np.linalg.norm(u))<1e-6:
        raise Error('zero orientation direction', 'ANIM_UNOBSERVABLE_MARKER')
    f/=np.linalg.norm(f);u-=f*(u@f)
    if np.linalg.norm(u)<1e-6:raise Error('orientation directions are collinear', 'ANIM_UNOBSERVABLE_MARKER')
    u/=np.linalg.norm(u)
    return np.stack((f,np.cross(u,f),u),axis=1)


def share_neck_turn(world: np.ndarray, names: list[str], weight: float) -> None:
    """Share measured head yaw with neck skin without moving any joint origin."""
    weight=number(weight,0,1,'neck_turn_weight')
    if 'head' not in names or 'neck' not in names:raise Error('head/neck turn sharing requires both bones','ANIM_UNKNOWN_BONE')
    neck=names.index('neck');head=names.index('head')
    if world.ndim!=4 or world.shape[1:]!=(len(names),4,4) or not np.isfinite(world).all():
        raise Error('invalid head/neck pose','ANIM_NONFINITE_TRANSFORM')
    axis=world[:,head,:3,3]-world[:,neck,:3,3];length=np.linalg.norm(axis,axis=1)
    if np.any(length<1e-8):raise Error('zero neck length','ANIM_INVALID_BIND')
    axis/=length[:,None]
    current=world[:,neck,:3,0].copy();wanted=world[:,head,:3,0].copy()
    current-=axis*np.sum(current*axis,axis=1)[:,None];wanted-=axis*np.sum(wanted*axis,axis=1)[:,None]
    a=np.linalg.norm(current,axis=1);b=np.linalg.norm(wanted,axis=1)
    if np.any(np.minimum(a,b)<1e-8):raise Error('unobservable head turn','ANIM_UNOBSERVABLE_MARKER')
    current/=a[:,None];wanted/=b[:,None]
    angle=np.unwrap(np.arctan2(np.sum(axis*np.cross(current,wanted),axis=1),np.sum(current*wanted,axis=1)))*weight
    cross=np.zeros((len(world),3,3));x,y,z=axis.T
    cross[:,0,1]=-z;cross[:,0,2]=y;cross[:,1,0]=z;cross[:,1,2]=-x;cross[:,2,0]=-y;cross[:,2,1]=x
    rotation=np.eye(3)+np.sin(angle)[:,None,None]*cross+(1-np.cos(angle))[:,None,None]*(cross@cross)
    world[:,neck,:3,:3]=rotation@world[:,neck,:3,:3]


def retarget(model, motion, recipe, root_motion='in_place'):
    fields(recipe,('bones','forward','up','scale','root_origin','rotation_bones','absolute_rotations','bind_bones','stabilize_poles','preserve_observed_poles','neck_turn_weight'),('bones','forward','up'),'retarget')
    mapping=recipe['bones']
    if not isinstance(mapping,dict):raise Error('retarget bones must map target names to source names')
    required={'pelvis','chest','head'} | {n+'_'+s for s in ('l','r') for n in ('upperarm','forearm','hand','thigh','shin','foot')}
    if not required<=mapping.keys() or not required<=set(model.names):raise Error('retarget requires torso, arms, hands and legs')
    for target,source in mapping.items():
        if target not in model.names or source not in motion.names:raise Error(f'unknown retarget joint {target}: {source}', 'ANIM_UNKNOWN_BONE', target)
    rotation_bones=recipe.get('rotation_bones',[])
    if not isinstance(rotation_bones,list) or any(not isinstance(n,str) for n in rotation_bones) or len(set(rotation_bones))!=len(rotation_bones):raise Error('rotation_bones must be a unique list')
    for name in rotation_bones:
        if name not in mapping:raise Error('rotation transfer needs a mapped bone: '+str(name), 'ANIM_UNKNOWN_BONE', str(name))
    absolute=recipe.get('absolute_rotations',{})
    bind_bones=recipe.get('bind_bones',[])
    if not isinstance(bind_bones,list) or len(bind_bones)>128 or any(not isinstance(n,str) for n in bind_bones) or len(set(bind_bones))!=len(bind_bones):raise Error('bind_bones must be a bounded unique list')
    for name in bind_bones:
        if name not in model.names:raise Error('bind bone missing', 'ANIM_UNKNOWN_BONE',name)
        if name in mapping or not name.startswith(('fingers_','thumb_')):raise Error('bind controls support only unmapped fingers/thumbs',field=name)
    stabilize=recipe.get('stabilize_poles',False)
    if type(stabilize) is not bool:raise Error('stabilize_poles must be boolean')
    preserve=recipe.get('preserve_observed_poles',False)
    if type(preserve) is not bool:raise Error('preserve_observed_poles must be boolean')
    if not isinstance(absolute,dict):raise Error('absolute_rotations must be a bone/frame mapping')
    neck_turn=None
    if 'neck_turn_weight' in recipe:
        neck_turn=number(recipe['neck_turn_weight'],0,1,'neck_turn_weight')
        if 'head' not in absolute or 'neck' not in mapping:raise Error('neck sharing requires measured absolute head rotation and a mapped neck')
    for name,frame in absolute.items():
        if name not in mapping:raise Error('absolute rotation needs a mapped bone', 'ANIM_UNKNOWN_BONE', name)
        if name in rotation_bones:raise Error('bone cannot use both relative and absolute rotation',field=name)
        if mapping[name] not in motion.metadata.get('semantic_frames',{}):
            raise Error('absolute rotation requires measured source semantic axes', 'ANIM_UNOBSERVABLE_MARKER', name)
        fields(frame,('forward','up'),('forward','up'),'target semantic frame '+name)
        orientation_basis(frame['forward'],frame['up'])
    idx={n:i for i,n in enumerate(model.names)};src={n:motion.names.index(s) for n,s in mapping.items()}
    coordinate=basis(recipe['forward'],recipe['up'])
    points=motion.world[..., :3,3]@coordinate.T
    rest=sk.matrices(model.bind,model.parents)
    lengths=[]
    for side in ('l','r'):
        for a,b in (('thigh','shin'),('shin','foot')):
            target_length=np.linalg.norm(rest[idx[a+'_'+side],:3,3]-rest[idx[b+'_'+side],:3,3])
            source_length=np.median(np.linalg.norm(points[:,src[a+'_'+side]]-points[:,src[b+'_'+side]],axis=1))
            if source_length<1e-6:raise Error('zero source limb length')
            lengths.append(target_length/source_length)
    scale=number(recipe.get('scale',float(np.median(lengths))),.00001,1e5,'retarget scale')
    points*=scale
    root=points[:,src['pelvis']].copy()
    origin=recipe.get('root_origin','clip')
    if origin not in ('clip','reference'):raise Error('root_origin must be clip/reference')
    root-=((motion.rest[src['pelvis'],:3,3]@coordinate.T)*scale if origin=='reference' else root[0])-rest[idx['pelvis'],:3,3]
    travel=np.zeros_like(root)
    if root_motion=='in_place':
        travel[:,:2]=root[:,:2]-root[0,:2];root[:,:2]=root[0,:2]
    elif root_motion!='preserve':raise Error('invalid root_motion')
    left=points[:,src['thigh_l']]-points[:,src['thigh_r']]
    up=points[:,src['chest']]-points[:,src['pelvis']]
    up/=np.maximum(np.linalg.norm(up,axis=1,keepdims=True),1e-8)
    left-=up*(up*left).sum(axis=1,keepdims=True)
    left/=np.maximum(np.linalg.norm(left,axis=1,keepdims=True),1e-8)
    forward=np.cross(left,up)
    torso=np.stack((forward,left,up),axis=2)
    fitted=np.broadcast_to(rest,(len(points),*rest.shape)).copy()
    for j,(name,parent) in enumerate(zip(model.names,model.parents)):
        if parent<0:
            fitted[:,j,:3,3]=root;fitted[:,j,:3,:3]=torso@rest[j,:3,:3]
        else:
            fitted[:,j,:3,3]=np.einsum('fij,j->fi',fitted[:,parent,:3,:3],model.bind[j,:3])+fitted[:,parent,:3,3]
            fitted[:,j,:3,:3]=fitted[:,parent,:3,:3]@rest[parent,:3,:3].T@rest[j,:3,:3]
        # Align bone directions rather than multiplying a T-pose delta onto
        # the target's A-pose. This also keeps target segment lengths intact.
        child=next((k for k,p in enumerate(model.parents) if p==j and model.names[k] in src),None)
        if name in src and child is not None and name not in ('pelvis','spine','chest','neck'):
            desired=points[:,src[model.names[child]]]-points[:,src[name]]
            current=np.einsum('fij,j->fi',fitted[:,j,:3,:3],model.bind[child,:3])
            fitted[:,j,:3,:3]=align_vectors(current,desired)@fitted[:,j,:3,:3]
        # Apply measured torso/end-bone rotations before evaluating their
        # children, so arm origins follow the same reconstructed torso.
        if name in rotation_bones:
            source=src[name]
            delta=coordinate@motion.world[:,source,:3,:3]@motion.rest[source,:3,:3].T@coordinate.T
            fitted[:,j,:3,:3]=delta@rest[j,:3,:3]
        if name in absolute:
            source=src[name];frame=absolute[name]
            target_basis=orientation_basis(frame['forward'],frame['up'])
            fitted[:,j,:3,:3]=coordinate@motion.world[:,source,:3,:3]@target_basis.T@rest[j,:3,:3]
        for side in ('l','r'):
            for a,b,c in (('upperarm','forearm','hand'),('thigh','shin','foot')):
                if name!=a+'_'+side:continue
                mid,end=idx[b+'_'+side],idx[c+'_'+side]
                d1=points[:,src[b+'_'+side]]-points[:,src[name]]
                d2=points[:,src[c+'_'+side]]-points[:,src[b+'_'+side]]
                d1/=np.maximum(np.linalg.norm(d1,axis=1,keepdims=True),1e-8)
                d2/=np.maximum(np.linalg.norm(d2,axis=1,keepdims=True),1e-8)
                # Store goals separately: subsequent hierarchy evaluation
                # must not overwrite the elbow and wrist IK targets.
                fitted[:,mid,:3,3]=fitted[:,j,:3,3]+d1*np.linalg.norm(model.bind[mid,:3])
                fitted[:,end,:3,3]=fitted[:,mid,:3,3]+d2*np.linalg.norm(model.bind[end,:3])
    # Rebuild limb endpoint goals after all parent rotations have been fitted.
    for side in ('l','r'):
        for a,b,c in (('upperarm','forearm','hand'),('thigh','shin','foot')):
            ia,ib,ic=(idx[n+'_'+side] for n in (a,b,c))
            vectors=[]
            for x,y,j in ((a,b,ib),(b,c,ic)):
                d=points[:,src[y+'_'+side]]-points[:,src[x+'_'+side]]
                vectors.append(d/np.maximum(np.linalg.norm(d,axis=1,keepdims=True),1e-8)*np.linalg.norm(model.bind[j,:3]))
            fitted[:,ib,:3,3]=fitted[:,ia,:3,3]+vectors[0]
            fitted[:,ic,:3,3]=fitted[:,ib,:3,3]+vectors[1]
    # End bones have no mapped child direction. Explicit captured orientations
    # preserve head performance and hand twist without inventing finger motion.
    # An empty list retains the established mocap retarget contract exactly.
    local=connected_motion(model,fitted,temporal_poles=stabilize,cyclic_poles=motion.metadata.get('resample',{}).get('loop',False),preserve_observed_poles=preserve)
    for name in bind_bones:local[:,idx[name],3:7]=model.bind[idx[name],3:7]
    # Weapon attachment axes are a separate existing game contract. Preserve
    # their parent-relative bind transform; do not infer them from mocap hands.
    world=sk.matrices(local,model.parents)
    if neck_turn is not None:share_neck_turn(world,model.names,neck_turn)
    metadata=dict(motion.metadata,retarget=dict(scale=scale,bones=mapping,forward=recipe['forward'],up=recipe['up'],
                                               root_motion=root_motion,root_origin=origin,rig='existing IQM bind',finger_motion='bind pose'))
    if absolute:metadata['retarget']['absolute_rotations']=absolute
    if bind_bones:metadata['retarget']['bind_bones']=bind_bones
    if stabilize:metadata['retarget']['stabilize_poles']=True
    if preserve:metadata['retarget']['preserve_observed_poles']=True
    if neck_turn is not None:metadata['retarget']['neck_turn_weight']=neck_turn
    metadata['source_directions']={a+'_'+side+':'+b+'_'+side:
        (points[:,src[b+'_'+side]]-points[:,src[a+'_'+side]]).tolist()
        for side in ('l','r') for a,b in (('upperarm','forearm'),('forearm','hand'))}
    metadata['source_hand_points']={name:motion.world[:,src[name],:3,3].tolist() for name in ('hand_l','hand_r')}
    if any(n.startswith('deform_') for n in model.names):
        if recipe['forward']!='x' or recipe['up']!='z' or scale!=1 or root_motion!='preserve':
            raise Error('source-surface correctives require native unit coordinates and preserved motion')
        metadata['source_correctives']={}
        for name in model.names:
            if not name.startswith('deform_'):continue
            source=src.get(name.removeprefix('deform_'))
            if source is None:raise Error('corrective requires mapped source region','ANIM_UNKNOWN_BONE',name)
            transform=motion.world[:,source].copy();region=name.removeprefix('deform_')
            reference=orientation_basis(absolute[region]['forward'],absolute[region]['up']).T if region in absolute else motion.rest[source,:3,:3].T
            transform[:,:3,:3]=transform[:,:3,:3]@reference@rest[idx[name],:3,:3]
            metadata['source_correctives'][name]=transform.tolist()
        if neck_turn is not None:
            head=np.asarray(metadata['source_correctives']['deform_head']);neck=np.asarray(metadata['source_correctives']['deform_neck'])
            pair=np.stack((neck,head),axis=1);share_neck_turn(pair,['neck','head'],neck_turn)
            metadata['source_correctives']['deform_neck']=pair[:,0].tolist()
    metadata.pop('auxiliary',None)
    return Motion(model.names,model.parents,rest,world,motion.fps,travel,metadata)


def solver_options(sampled: Motion) -> dict:
    policy=sampled.metadata.get('retarget',{})
    return dict(temporal_poles=policy.get('stabilize_poles',False),
                cyclic_poles=sampled.metadata.get('resample',{}).get('loop',False),
                preserve_observed_poles=policy.get('preserve_observed_poles',False))


def contacts(motion, bones=('foot_l','foot_r'), height=.8, speed=8, min_frames=2):
    result={}
    for bone in bones:
        if bone not in motion.names:raise Error('unknown contact bone '+bone)
        p=motion.world[:,motion.names.index(bone),:3,3]+motion.travel
        velocity=np.linalg.norm(np.gradient(p,axis=0),axis=1)*motion.fps if len(p)>1 else np.zeros(1)
        mask=(p[:,2]<=np.percentile(p[:,2],10)+height)&(velocity<=speed)
        edges=np.diff(np.r_[False,mask,False].astype(int));starts=np.flatnonzero(edges==1);ends=np.flatnonzero(edges==-1)-1
        result[bone]=[[int(a),int(b)] for a,b in zip(starts,ends) if b-a+1>=min_frames]
    return result


def sole_support(model, bone):
    if bone not in model.names or 'toe_'+bone[-1] not in model.names:
        raise Error('sole contact requires foot and toe bones', 'ANIM_UNKNOWN_BONE',bone)
    foot=model.names.index(bone);toe=model.names.index('toe_'+bone[-1])
    weights=np.sum(model.arrays[5]*((model.arrays[4]==foot)|(model.arrays[4]==toe)),axis=1)
    vertices=np.flatnonzero(weights>=128)
    if not len(vertices):raise Error('planted foot has no sole surface support', 'ANIM_UNOBSERVABLE_MARKER',bone)
    height=float(model.arrays[0][vertices,2].min())
    return vertices[model.arrays[0][vertices,2]<=height+.25],height


def skin_points(model, local, vertices):
    """Skin only inspected support vertices, without frame × whole-body memory."""
    transforms=sk.matrices(local,model.parents)@np.linalg.inv(sk.matrices(model.bind,model.parents))
    points=model.arrays[0][vertices];posed=np.zeros((len(local),len(vertices),3))
    for influence in range(4):
        t=transforms[:,model.arrays[4][vertices,influence]]
        posed+=(np.einsum('fvij,vj->fvi',t[...,:3,:3],points)+t[...,:3,3])*(model.arrays[5][vertices,influence]/255)[None,:,None]
    return posed


def solve_contacts(model,motion,intervals,adjust_root=False,floor_height=None):
    fitted=motion.world.copy()
    targets={};active={}
    bind=sk.matrices(model.bind,model.parents)
    for bone,ranges in intervals.items():
        if bone not in ('foot_l','foot_r','hand_l','hand_r') or bone not in motion.names:
            raise Error('contact solver supports existing two-bone feet and hands: '+bone)
        j=motion.names.index(bone)
        targets[bone]=fitted[:,j,:3,3].copy();active[bone]=np.zeros(len(fitted),bool)
        for interval in ranges:
            a,b=span(interval)
            if b>=len(fitted):raise Error('contact outside motion')
            anchor=np.median(fitted[a:b+1,j,:3,3]+motion.travel[a:b+1],axis=0)
            targets[bone][a:b+1]=anchor-motion.travel[a:b+1];active[bone][a:b+1]=True
        if floor_height is not None and bone.startswith('foot_'):
            _,sole_height=sole_support(model,bone)
            targets[bone][active[bone],2]=floor_height+bind[j,2,3]-sole_height-motion.travel[active[bone],2]
    correction=np.zeros(len(fitted))
    if adjust_root:
        for bone,mask in active.items():
            if not bone.startswith('foot_'):continue
            side=bone[-1];hip=model.names.index('thigh_'+side);shin=model.names.index('shin_'+side);foot=model.names.index(bone)
            l1,l2=np.linalg.norm(model.bind[shin,:3]),np.linalg.norm(model.bind[foot,:3])
            reach=np.sqrt(l1*l1+l2*l2+2*l1*l2*np.cos(np.deg2rad(3)))
            horizontal=np.sum((fitted[:,hip,:2,3]-targets[bone][:,:2])**2,axis=1)
            maximum_z=targets[bone][:,2]+np.sqrt(np.maximum(0,reach*reach-horizontal))
            correction[mask]=np.minimum(correction[mask],maximum_z[mask]-fitted[mask,hip,2,3])
        fitted[:,:,:3,3]+=correction[:,None,None]*np.array([0,0,1])
    for bone,mask in active.items():fitted[mask,model.names.index(bone),:3,3]=targets[bone][mask]
    options=solver_options(motion)
    local=connected_motion(model,fitted,**options)
    if adjust_root:
        # Feet can also fall outside hip direction limits. Move the floating
        # body toward the simultaneous contact residual, instead of stretching
        # bones or loosening the anatomical limits. The requested foot goals
        # stay fixed through these deterministic iterations.
        for _ in range(6):
            solved=sk.matrices(local,model.parents);delta=np.zeros((len(fitted),3));counts=np.zeros(len(fitted))
            for bone,mask in active.items():
                if not bone.startswith('foot_'):continue
                delta[mask]+=targets[bone][mask]-solved[mask,model.names.index(bone),:3,3];counts[mask]+=1
            delta/=np.maximum(counts[:,None],1)
            if np.max(np.linalg.norm(delta,axis=1))<1e-5:break
            fitted[:,:,:3,3]+=delta[:,None,:]
            for bone,mask in active.items():fitted[mask,model.names.index(bone),:3,3]=targets[bone][mask]
            local=connected_motion(model,fitted,**options)
    report=dict(intervals=intervals,solver='fixed-length anatomical two-bone IK')
    if adjust_root:report['root_adjustment']=float(np.max(np.linalg.norm(sk.matrices(local,model.parents)[:,0,:3,3]-motion.world[:,0,:3,3],axis=1)))
    if floor_height is not None:
        for iteration in range(5):
            world=sk.matrices(local,model.parents)
            for bone,mask in active.items():
                if not bone.startswith('foot_'):continue
                j=model.names.index(bone);parent=model.parents[j]
                forward=world[:,j,:3,:3]@bind[j,:3,:3].T@np.array([1.,0,0])
                yaw=np.arctan2(forward[:,1],forward[:,0])
                desired=Rotation.from_euler('z',yaw).as_matrix()@bind[j,:3,:3]
                rotation=world[:,parent,:3,:3].swapaxes(-1,-2)@desired
                local[mask,j,3:7]=Rotation.from_matrix(rotation[mask]).as_quat()
                toe=model.names.index('toe_'+bone[-1]);local[mask,toe,3:7]=model.bind[toe,3:7]
            if iteration==4:break
            # The admitted boots have blended shin influences. Position the
            # actual skinned sole support around the floor, rather than
            # assuming its bind-pose offset stays exact after knee bending.
            fitted=sk.matrices(local,model.parents)
            for bone,mask in active.items():
                if not bone.startswith('foot_'):continue
                vertices,_=sole_support(model,bone);heights=skin_points(model,local,vertices)[:,:,2]+motion.travel[:,2,None]
                center=(heights.min(axis=1)+heights.max(axis=1))*.5
                fitted[mask,model.names.index(bone),2,3]+=floor_height-center[mask]
            local=connected_motion(model,fitted,**options)
        report['floor_height']=floor_height
    return Motion(model.names,model.parents,motion.rest,sk.matrices(local,model.parents),motion.fps,motion.travel,
                  dict(motion.metadata,contact_solve=report))


def angle(a,b):
    relative=a.swapaxes(-1,-2)@b
    return np.rad2deg(np.arccos(np.clip((np.trace(relative,axis1=-2,axis2=-1)-1)/2,-1,1)))


def validate(model,motion,recipe):
    validate_motion(motion)
    if motion.names!=model.names or motion.parents!=model.parents or not np.allclose(motion.rest,sk.matrices(model.bind,model.parents),atol=1e-5):
        raise Error('motion targets another skeleton/bind pose')
    local=sk.channels(motion.world,motion.parents)
    # Relative translations must preserve every admitted segment length.
    # Auxiliary prop joints intentionally translate to hide/reveal carried
    # objects. They are not fixed-length anatomical segments.
    declared=recipe.get('correctives',{})
    corrective_names={n for n in model.names if n.startswith('deform_')}
    if corrective_names!=set(declared):raise Error('every surface corrective must be explicitly declared','ANIM_UNKNOWN_BONE')
    rooted=(np.array(model.parents)>=0)&np.array([not n.startswith('prop_') and n not in declared for n in model.names])
    stretch=np.linalg.norm(local[:,rooted,:3]-model.bind[rooted,:3],axis=-1)
    failures=[];metrics={}
    def check(name,values,limit,bones=None):
        flat=int(np.argmax(values));index=list(np.unravel_index(flat,values.shape));maximum=float(values.flat[flat])
        metrics[name]=dict(maximum=maximum,limit=float(limit),index=[int(v) for v in index])
        if bones is not None:metrics[name]['bone']=bones[index[-1]]
        if maximum>limit+1e-5:
            code='ANIM_MOTION_LIMIT'
            if name=='bone_translation':code='ANIM_BONE_LENGTH_CHANGE'
            elif name=='joint_step_degrees':code='ANIM_ROTATION_DISCONTINUITY'
            elif name.startswith('loop_'):code='ANIM_LOOP_POSE_DISCONTINUITY'
            elif name.startswith('contact:foot_'):code='ANIM_FOOT_SLIDE'
            elif name.startswith('floor_penetration:'):code='ANIM_FLOOR_PENETRATION'
            elif name.startswith(('sole_height:','prop_','attachment_','hand_surface:','contact:hand_')):code='ANIM_ATTACHMENT_ERROR'
            elif name.startswith(('joint_limit:','knee_','elbow_','wrist_','foot_rotation:','toe_rotation:')):code='ANIM_JOINT_LIMIT'
            elif name.startswith('source_corrective_'):code='ANIM_SOURCE_POSE_MISMATCH'
            failures.append(dict(code=code,check=name,**metrics[name]))
    if stretch.size:check('bone_translation',stretch,1e-4,[n for n,selected in zip(model.names,rooted) if selected])
    for name,source in declared.items():
        if motion.metadata.get('kind')=='authored_cinematic':
            j=model.names.index(name)
            if not name.startswith('deform_') or source!=name.removeprefix('deform_') or model.parents[j]!=model.names.index(source):
                raise Error('authored corrective must follow its anatomical parent','ANIM_UNKNOWN_BONE',name)
            check('authored_corrective_translation:'+name,np.linalg.norm(local[:,j,:3]-model.bind[j,:3],axis=1),.002)
            check('authored_corrective_angle:'+name,angle(motion.world[:,j,:3,:3],motion.world[:,model.parents[j],:3,:3]@sk.matrices(model.bind[j:j+1],[-1])[0,:3,:3]),.05)
        else:
            expected=motion.metadata.get('source_correctives',{}).get(name)
            if expected is None:raise Error('corrective observation missing','ANIM_UNOBSERVABLE_MARKER',name)
            expected=np.asarray(expected);actual=motion.world[:,model.names.index(name)]
            if expected.shape!=actual.shape or not np.isfinite(expected).all():raise Error('invalid corrective observations','ANIM_NONFINITE_TRANSFORM',name)
            check('source_corrective_position:'+name,np.linalg.norm(actual[:,:3,3]-expected[:,:3,3],axis=1),.002)
            check('source_corrective_angle:'+name,angle(actual[:,:3,:3],expected[:,:3,:3]),.05)
    step=angle(motion.world[1:,:,:3,:3],motion.world[:-1,:,:3,:3])
    anatomical=np.array([not n.startswith('prop_') for n in model.names])
    if step.size:check('joint_step_degrees',step[:,anatomical],recipe.get('max_joint_step',65),[n for n,selected in zip(model.names,anatomical) if selected])
    if 'source_fidelity' in recipe:
        directions=motion.metadata.get('source_directions',{})
        if not directions:raise Error('source-fidelity validation requires measured motion', 'ANIM_UNOBSERVABLE_MARKER')
        for segment,expected in directions.items():
            a,b=segment.split(':');a,b=motion.names.index(a),motion.names.index(b)
            actual=motion.world[:,b,:3,3]-motion.world[:,a,:3,3];expected=np.asarray(expected)
            if expected.shape!=actual.shape or not np.isfinite(expected).all():raise Error('invalid source directions', 'ANIM_NONFINITE_TRANSFORM')
            cosine=np.sum(actual*expected,axis=1)/np.maximum(np.linalg.norm(actual,axis=1)*np.linalg.norm(expected,axis=1),1e-8)
            name='source_direction:'+segment
            check(name,np.rad2deg(np.arccos(np.clip(cosine,-1,1))),recipe['source_fidelity']['max_direction_degrees'])
            for failure in failures:
                if failure['check']==name:failure['code']='ANIM_SOURCE_POSE_MISMATCH'
    if all(n+'_'+s in model.names for s in ('l','r') for n in ('thigh','shin','foot','upperarm','forearm','hand')):
        for side in ('l','r'):
            for label,names,minimum,maximum in (('knee',('thigh','shin','foot'),2.9,145.1),('elbow',('upperarm','forearm','hand'),0,170)):
                a,b,c=(model.names.index(n+'_'+side) for n in names)
                upper=motion.world[:,b,:3,3]-motion.world[:,a,:3,3];lower=motion.world[:,c,:3,3]-motion.world[:,b,:3,3]
                cosine=np.sum(upper*lower,axis=1)/np.maximum(np.linalg.norm(upper,axis=1)*np.linalg.norm(lower,axis=1),1e-8)
                bend=np.rad2deg(np.arccos(np.clip(cosine,-1,1)))
                check(label+'_bend:'+side,bend,maximum)
                check(label+'_minimum:'+side,np.maximum(0,minimum-bend),0)
            for bone,limit in (('foot',70.1),('toe',35.1)):
                name=bone+'_'+side
                if name not in model.names:continue
                j=model.names.index(name);parent=model.parents[j]
                check(bone+'_rotation:'+side,angle(motion.world[:,parent,:3,:3],motion.world[:,j,:3,:3]),limit)
            hand='hand_'+side;fingers='fingers_'+side
            if fingers in model.names:
                j=model.names.index(hand);parent=model.parents[j];rest=motion.rest
                neutral=motion.world[:,parent,:3,:3]@rest[parent,:3,:3].T@rest[j,:3,:3]
                axis=model.bind[model.names.index(fingers),:3];axis=axis/max(np.linalg.norm(axis),1e-8)
                a=neutral@axis;b=motion.world[:,j,:3,:3]@axis
                bend=np.rad2deg(np.arccos(np.clip(np.sum(a*b,axis=1),-1,1)))
                check('wrist_bend:'+side,bend,35.1)
    for bone,limit in recipe.get('joint_limits',{}).items():
        if bone not in model.names:raise Error('unknown limited joint '+bone)
        j=model.names.index(bone)
        # Explicit limits are rotation magnitude relative to bind; hinge
        # direction is already bounded by the anatomical retarget solver.
        q=local[:,j,3:7];rest=model.bind[j,3:7]
        values=np.rad2deg(2*np.arccos(np.clip(np.abs(q@rest),0,1)))
        check('joint_limit:'+bone,values,limit)
    for bone,ranges in recipe.get('contacts',{}).items():
        if bone not in motion.names:raise Error('unknown contact bone '+bone)
        for a,b in ranges:
            if b>=len(local):raise Error('contact outside selected clip')
            points=motion.world[a:b+1,motion.names.index(bone),:3,3]+motion.travel[a:b+1]
            # A conservative diameter bound is linear in the interval length;
            # an all-pairs matrix would exhaust memory on a long held contact.
            name=f'contact:{bone}:{a}-{b}'
            check(name,np.array([np.linalg.norm(np.ptp(points,axis=0))]),recipe.get('max_foot_slide',.5))
            metrics[name]['measurement']='axis-span upper bound on full plant displacement'
            metrics[name]['extreme_frames']=(a+np.r_[points.argmin(axis=0),points.argmax(axis=0)]).tolist()
    if recipe.get('loop'):
        check('loop_position',np.linalg.norm(local[-1,:,:3]-local[0,:,:3],axis=-1),recipe.get('max_loop_position',2))
        relative=sk.matrices(local,[-1]*len(model.names))
        check('loop_angle',angle(relative[-1,:,:3,:3],relative[0,:,:3,:3]),recipe.get('max_loop_angle',25))
    for attachment in recipe.get('attachments',[]):
        bone=attachment['bone']
        if bone not in model.names:raise Error('missing attachment '+bone)
        j=model.names.index(bone)
        positions=np.linalg.norm(np.diff(motion.world[:,j,:3,3],axis=0),axis=1)
        if positions.size:check('attachment_position:'+bone,positions,attachment.get('max_position_step',10))
        if step.size:check('attachment_angle:'+bone,step[:,j],attachment.get('max_angle_step',65))
    exported=export_channels(motion)
    if 'contact_floor' in recipe:
        floor=recipe['contact_floor']
        for bone,ranges in recipe.get('contacts',{}).items():
            if not bone.startswith('foot_'):continue
            vertices,_=sole_support(model,bone);points=skin_points(model,exported,vertices)
            for a,b in ranges:
                heights=points[a:b+1,:,2]+motion.travel[a:b+1,2,None]
                check(f'sole_height:{bone}:{a}-{b}',np.abs(heights-floor),.5)
                check(f'floor_penetration:{bone}:{a}-{b}',np.maximum(0,floor-heights),.5)
    for contact in prop_contacts(recipe.get('prop_contacts',[])):
        j=model.names.index(contact['prop']);parent=model.names.index(contact['parent'])
        visible=prop_contact_mask(np.max(exported[:,j,7:10],axis=1)>1e-6,contact)
        actual=motion.world[:,j,:3,:3]@np.asarray(contact['pivot'])+motion.world[:,j,:3,3]
        wanted=grip_target(model,motion,contact,motion.world)
        name='prop_contact:'+contact['prop'];error=np.linalg.norm(actual-wanted,axis=1)
        check(name,error[visible] if visible.any() else np.zeros(1),contact.get('max_error',.05))
        metrics[name]['visible_frames']=int(visible.sum())
        if 'max_surface_error' in contact:
            bone=model.names.index(contact.get('attachment_bone',contact['parent']))
            weights=np.sum(model.arrays[5]*(model.arrays[4]==bone),axis=1);vertices=np.flatnonzero(weights>=128)
            if not len(vertices):raise Error('grip has no hand surface support','ANIM_UNOBSERVABLE_MARKER',contact['parent'])
            points=skin_points(model,exported,vertices)
            error=np.linalg.norm(points-actual[:,None,:],axis=2).min(axis=1)
            check('hand_surface:'+contact['prop'],error[visible] if visible.any() else np.zeros(1),contact['max_surface_error'])
        if floor:=contact.get('floor_contact'):
            point=motion.world[:,j,:3,:3]@np.asarray(floor['point'])+motion.world[:,j,:3,3]
            error=np.abs(point[:,2]-floor['height'])
            check('prop_floor:'+contact['prop'],error[visible] if visible.any() else np.zeros(1),floor.get('max_error',.1))
        if contact.get('orientation')=='source_world':
            for member,rotation in source_prop_orientations(model,recipe,contact,len(motion.world),motion).items():
                k=model.names.index(member);mask=np.max(exported[:,k,7:10],axis=1)>1e-6
                error=angle(motion.world[:,k,:3,:3],rotation)
                check('prop_orientation:'+member,error[mask] if mask.any() else np.zeros(1),.05)
        for failure in failures:
            if failure['check']==name:failure['code']='ANIM_ATTACHMENT_ERROR'
    return dict(passed=not failures,frames=len(local),fps=motion.fps,units='DK3 model units',metrics=metrics,failures=failures)


def from_model(model,first,last,fps):
    local=model.frames[first:last+1].copy();aux={}
    for j,name in enumerate(model.names):
        if name.startswith('prop_'):aux[name]=local[:,j].tolist();local[:,j,7:10]=1
    return Motion(model.names,model.parents,sk.matrices(model.bind,model.parents),
                  sk.matrices(local,model.parents),fps,np.zeros((last-first+1,3)),
                  dict(source='existing IQM',input_frames=[first,last],auxiliary=aux))


def attach(model,name,parent,translation,rotation=(0,0,0)):
    if name in model.names or parent not in model.names or len(model.names)>=128:raise Error('invalid new attachment joint')
    pose=np.r_[translation,Rotation.from_euler('xyz',rotation,degrees=True).as_quat(),[1,1,1]]
    model.names.append(name);model.parents.append(model.names.index(parent));model.bind=np.vstack((model.bind,pose))
    model.frames=np.concatenate((model.frames,np.broadcast_to(pose,(len(model.frames),1,10))),axis=1)
    return model


def compose_grid(model,base,attack,upper_bones):
    """Explicit compatibility grid; retain native 30 Hz attack row semantics."""
    if base.fps!=30 or attack.fps!=30:raise Error('native attack grid requires 30 Hz inputs')
    if base.names!=model.names or attack.names!=model.names:raise Error('grid skeleton mismatch')
    rest=sk.matrices(model.bind,model.parents)
    if any(m.parents!=model.parents or not np.allclose(m.rest,rest,atol=1e-5) for m in (base,attack)):raise Error('grid bind/hierarchy mismatch')
    if any(b not in model.names for b in upper_bones):raise Error('unknown upper-body grid bone')
    lower=export_channels(base);upper=export_channels(attack)
    output=np.broadcast_to(lower,(len(upper),*lower.shape)).copy()
    indices=[model.names.index(b) for b in upper_bones]
    output[:,:,indices]=upper[:,None,indices]
    return output.reshape(-1,len(model.names),10)
