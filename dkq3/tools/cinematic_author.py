# SPDX-License-Identifier: GPL-2.0-or-later
"""Human-readable cinematic recipes compiled into dk3_cinematic 1.

Camera curves use seconds and Quake angles (pitch, yaw, roll). Actor actions use
the existing sequential task queue. Concurrent masked/facial layers are rejected.
"""
from __future__ import annotations

import math
import numpy as np

import animation_manifest as schema
from cinematics import numbers
from tables import quoted


def look(origin,target):
    x,y,z=np.array(target)-origin
    return [-math.degrees(math.atan2(z,math.hypot(x,y))),math.degrees(math.atan2(y,x)),0.]


def curves(times,values,velocities=None,angular=False):
    times=np.array(times,float);values=np.array(values,float)
    if len(times)<2:return []
    if angular:values=np.rad2deg(np.unwrap(np.deg2rad(values),axis=0))
    if not np.all(np.diff(times)>0):raise schema.Error('camera/head keys must have strictly increasing times')
    slopes=np.gradient(values,times,axis=0) if velocities is None else np.array(velocities,float)
    result=[]
    for i,h in enumerate(np.diff(times)):
        delta=values[i+1]-values[i];a=values[i];b=slopes[i]
        c=(3*delta/h-2*slopes[i]-slopes[i+1])/h
        d=(slopes[i]+slopes[i+1]-2*delta/h)/(h*h)
        result.append(np.stack((d,c,b,a),axis=1).ravel().tolist())
    return result


def task(kind,when,destination=(0,0,0),angles=(0,0,0),attribute=0,duration=0,animation='',use='',sound='',unique=''):
    return numbers([kind,when,*destination,*angles,attribute,duration])+' '+' '.join(quoted(s) for s in (animation,use,sound,unique))


def compile_scene(document,clip_aliases=None):
    schema.fields(document,('version','scene','anchors','actors','shots'),('version','scene','actors','shots'),'scene')
    if document['version']!=1:raise schema.Error('cinematic author version must be 1')
    scene=schema.text(document['scene'],'scene',32)
    anchors={name:schema.vector(p,'anchor '+name) for name,p in document.get('anchors',{}).items()}
    actors=document['actors'];shots=document['shots'];clip_aliases=clip_aliases or {}
    if not isinstance(actors,dict) or len(actors)>128 or not isinstance(shots,list) or not 0<len(shots)<=256:raise schema.Error('scene requires at most 128 actors and 1..256 shots')
    def position(value):
        if isinstance(value,str):
            if value not in anchors:raise schema.Error('unknown anchor '+value)
            return anchors[value].copy()
        return schema.vector(value,'position')
    states={}
    for name,actor in actors.items():
        schema.text(name,'actor id',32)
        schema.fields(actor,('class','character','at','angles','look_height','spawn','queue_spawn'),('class','at'),'actor '+name)
        schema.text(actor['class'],'actor class',32)
        if 'spawn' in actor and type(actor['spawn']) is not bool:raise schema.Error('spawn must be boolean')
        if 'queue_spawn' in actor and (type(actor['queue_spawn']) is not bool or not actor.get('spawn',True)):raise schema.Error('queue_spawn requires a spawning actor and a boolean')
        states[name]=dict(position=position(actor['at']),angles=schema.vector(actor.get('angles',[0,0,0])),
                          look_height=schema.number(actor.get('look_height',22),0,256,'actor look height'))
    output=[f'dk3_cinematic 1 {len(shots)}'];receipt=dict(scene=scene,format='dk3_cinematic 1',shots=[],warnings=[])
    total_tracks=total_tasks=total_segments=total_sounds=0
    for shot_index,shot in enumerate(shots):
        schema.fields(shot,('duration','pre','post','fov','camera','tracks','events','target','end_on_actor','sky'),('duration','camera'),'shot')
        duration=schema.number(shot['duration'],.001,3600,'shot duration')
        fov=schema.number(shot.get('fov',90),1,179,'horizontal FOV degrees')
        pre=schema.number(shot.get('pre',0),0,3600);post=schema.number(shot.get('post',0),0,3600)
        target=shot.get('target','');end=shot.get('end_on_actor','')
        for name in (target,end):
            if name and name not in actors:raise schema.Error('unknown shot actor '+name)
        if 'sky' in shot and type(shot['sky']) is not bool:raise schema.Error('sky must be boolean')
        output.append('shot '+numbers([duration,pre,post,int(bool(target)),int(bool(end)),1,fov,int(shot.get('sky',False)),0,0])+' '+quoted(target)+' '+quoted(end))
        camera=shot['camera'];schema.fields(camera,('keys','interpolation'),('keys',),'camera')
        if camera.get('interpolation','cubic') not in ('linear','cubic'):raise schema.Error('camera interpolation must be linear/cubic')
        keys=camera['keys']
        if not isinstance(keys,list) or not 1<=len(keys)<=8192:raise schema.Error('camera requires 1..8192 keys')
        times=[];points=[];angles=[];fovs=[];blends=[]
        for key in keys:
            schema.fields(key,('at','position','angles','look_at','fov','blend'),('at','position'),'camera key')
            if ('angles' in key)==('look_at' in key):raise schema.Error('camera key requires either angles or look_at')
            t=schema.number(key['at'],0,duration,'camera key time')
            p=position(key['position']);a=look(p,position(key['look_at'])) if 'look_at' in key else schema.vector(key['angles'])
            times.append(t);points.append(p);angles.append(a);fovs.append(schema.number(key.get('fov',fov),1,179,'key FOV'))
            blends.append(schema.vector(key.get('blend',[0,0,0,0]),'RGBA blend',4))
            if any(v<0 or v>255 for v in blends[-1]):raise schema.Error('camera blend channels must be 0..255')
        if times[0]!=0 or (len(keys)>1 and abs(times[-1]-duration)>1e-6):raise schema.Error('camera keys must cover shot from 0 through duration')
        pc=curves(times,points);ac=curves(times,angles,angular=True)
        if camera.get('interpolation')=='linear':
            unwrapped=np.rad2deg(np.unwrap(np.deg2rad(angles),axis=0))
            for i,h in enumerate(np.diff(times)):
                pc[i]=np.stack((np.zeros(3),np.zeros(3),(np.array(points[i+1])-points[i])/h,points[i]),axis=1).ravel().tolist()
                ac[i]=np.stack((np.zeros(3),np.zeros(3),(unwrapped[i+1]-unwrapped[i])/h,unwrapped[i]),axis=1).ravel().tolist()
        output.append(f'camera {len(keys)} {len(pc)}');output.append(numbers(points[0]+angles[0]))
        for i in range(len(pc)):
            header=[times[i+1]-times[i],1,1,fovs[i],fovs[i+1],0,0,1,1,1,1,*blends[i],*blends[i+1]]
            output.append('segment '+numbers(header+pc[i]+ac[i]))
        events=shot.get('events',[]);sounds=[]
        if not isinstance(events,list):raise schema.Error('events must be a list')
        for event in events:
            schema.fields(event,('sound','at','loop','channel'),('sound','at'),'event (only sound is supported)')
            path=schema.asset(event['sound'],'sound');when=schema.number(event['at'],0,duration,'sound time')
            channel=schema.number(event.get('channel',2),0,255,'sound channel',integer=True)
            loop=event.get('loop',False)
            if type(loop) is not bool:raise schema.Error('sound loop must be boolean')
            sounds.append(quoted(path)+' '+numbers([int(loop),channel,when]))
        output.append('sounds '+str(len(sounds)));output.extend(sounds)
        tracks=shot.get('tracks',{})
        if not isinstance(tracks,dict) or any(name not in actors for name in tracks):raise schema.Error('tracks must name declared actors')
        tracks=dict(tracks)
        if shot_index==0:
            for name in actors:tracks.setdefault(name,[])
        if len(tracks)>128:raise schema.Error('shot exceeds native 128 tracks')
        compiled=[];timing=[]
        for name,actions in tracks.items():
            if not isinstance(actions,list):raise schema.Error('actor track must be an action list')
            actor=actors[name];state=states[name];rows=[];busy=0.;previous=-1.;pending=False
            if shot_index==0 and actor.get('spawn',True):
                rows.append(task(18,-1 if actor.get('queue_spawn',False) else 0,state['position'],state['angles'],unique=name))
            for action in actions:
                schema.fields(action,('at','queue','enqueue','play','idle','move_to','mode','clip','speed','angles','turn','look_at','duration','wait','use','remove','clear','teleport'),(),'actor action')
                operations=set(action)&{'play','idle','move_to','turn','look_at','wait','use','remove','clear','teleport'}
                if len(operations)!=1:raise schema.Error('actor action requires exactly one operation')
                for flag in ('queue','enqueue'):
                    if flag in action and type(action[flag]) is not bool:raise schema.Error(flag+' must be boolean')
                queued=action.get('queue',False);enqueue=action.get('enqueue',False)
                if queued==('at' in action) or (queued and enqueue):raise schema.Error('action needs either at or queue: true; enqueue applies only to timed actions')
                when=-1 if queued else schema.number(action['at'],0,duration,'actor action time')
                op=next(iter(operations));immediate=op in ('clear','remove');length=0
                if not queued:
                    if when<previous or (not enqueue and not immediate and (pending or when<busy-1e-6)):
                        raise schema.Error(f'{name}: action overlaps sequential tasks; use explicit queue/enqueue for native pending playback')
                    previous=when
                def clip(label):
                    character=actor.get('character',name)
                    if character not in clip_aliases or label not in clip_aliases[character]:raise schema.Error(f'{character}: unknown clip alias {label}')
                    return clip_aliases[character][label]
                if op in ('play','idle'):
                    alias=clip(action[op]);sequence=alias['sequence']
                    if op=='play':
                        length=schema.number(action.get('duration',alias.get('duration')),0,3600 if queued or enqueue else duration,'authoritative clip duration')
                        if alias.get('duration') is not None and abs(length-alias['duration'])>1e-5:
                            raise schema.Error('play duration must match authoritative sequence; change the source mapping rather than retime server events')
                    rows.append(task(15 if op=='play' else 16,when,animation=sequence))
                elif op=='move_to':
                    mode=action.get('mode','walk')
                    if mode not in ('walk','run','inherit'):raise schema.Error('movement mode must be walk/run/inherit')
                    selected=clip(action['clip']) if 'clip' in action else None
                    expected=selected.get('movement_speed') if selected else None
                    if mode=='inherit' and 'speed' in action:raise schema.Error('inherited movement cannot change authoritative speed')
                    speed=schema.number(action.get('speed',expected or (80 if mode in ('walk','inherit') else 160)),.001,2000,'actor speed')
                    if expected and abs(speed-expected)>expected*.01:raise schema.Error('actor speed differs from selected gait; retime/rebuild the motion before movement')
                    dest=position(action[op]);length=schema.number(action.get('duration',float(np.linalg.norm(np.array(dest)-state['position'])/speed)),0,duration,'movement budget')
                    if mode!='inherit':
                        rows.append(task(7 if mode=='walk' else 6,when,attribute=speed));rows.append(task(12 if mode=='walk' else 11,when))
                    rows.append(task(3 if 'angles' in action else 1,when,dest,schema.vector(action.get('angles',state['angles'])),animation=selected['sequence'] if selected else ''))
                    offset=np.array(dest)-state['position']
                    if np.linalg.norm(offset[:2])>1:state['angles'][1]=math.degrees(math.atan2(offset[1],offset[0]))
                    state['position']=dest
                    if 'angles' in action:state['angles'][1]=schema.vector(action['angles'])[1]
                    receipt['warnings'].append(f'{name}: movement duration is a queue budget; native replay must check collision-dependent arrival')
                elif op=='look_at':
                    length=schema.number(action.get('duration',1),.2,duration,'head duration')
                    steps=round(length/.2)
                    if steps>8191:raise schema.Error('head curve exceeds native point capacity')
                    if abs(steps*.2-length)>1e-6:raise schema.Error('head duration must be a multiple of native 0.2s segments')
                    # Native task 14 writes performer angles, not a head bone.
                    # Compile absolute orientation and preserve the live body
                    # heading as the curve's start; relative angles snap actors.
                    desired=np.array(look(np.array(state['position'])+[0,0,state['look_height']],position(action[op])))
                    initial=np.array(state['angles']);desired=initial+(desired-initial+180)%360-180
                    phase=np.linspace(0,1,steps+1);delta=desired-initial;times_head=np.arange(steps+1)*.2
                    points=initial+(3*phase**2-2*phase**3)[:,None]*delta
                    velocities=(6*phase-6*phase**2)[:,None]*delta/length
                    headcurves=curves(times_head,points,velocities=velocities,angular=True)
                    rows.append(task(14,when));rows.append('head '+str(steps+1));rows.append(numbers(initial))
                    rows.extend(numbers(c) for c in headcurves);state['angles']=desired.tolist();length+=.2
                    receipt['warnings'].append(f'{name}: look_at rotates the whole performer through native task 14; independent head/eye layers are unavailable')
                elif op=='turn':
                    a=schema.vector(action[op]);length=schema.number(action.get('duration',1),.001,duration,'turn duration')
                    if a[0]!=0 or a[2]!=0:raise schema.Error('native turn supports yaw only; pitch/roll slots must be zero')
                    # The native performer multiplies yaw speed by ten.
                    yaw=abs((a[1]-state['angles'][1]+180)%360-180)/length/10
                    rows.append(task(8,when,attribute=max(yaw,.001)));rows.append(task(2,when,angles=a));state['angles'][1]=a[1]
                elif op=='wait':
                    length=schema.number(action[op],0,duration,'wait');rows.append(task(9,when,attribute=length))
                elif op=='use':rows.append(task(13,when,use=schema.text(action[op],'use target',32)))
                elif op in ('remove','clear'):
                    if action[op] is not True:raise schema.Error(op+' must be true')
                    rows.append(task(19 if op=='remove' else 20,when,unique=name))
                elif op=='teleport':
                    dest=position(action[op]);a=schema.vector(action.get('angles',state['angles']))
                    rows.append(task(10,when,dest,a));state.update(position=dest,angles=a)
                if queued or enqueue:
                    if not immediate:pending=True
                    receipt['warnings'].append(f'{name}: explicit native queue; completion depends on preceding tasks and may cross camera cuts')
                else:
                    busy=when+length
                    if immediate:pending=False
                    if not immediate and busy>duration+1e-6:raise schema.Error(f'{name}: action exceeds shot duration')
                timing.append(dict(actor=name,operation=op,at=None if queued else when,queued=queued or enqueue,through=None if pending else busy))
            # Head coefficient lines are part of one task, not extra tasks.
            count=sum(1 for row in rows if row and row[0].isdigit() and len(row.split())>=14 and '"' in row)
            if count>128:raise schema.Error('track exceeds bounded native performer queue; split into shots')
            compiled.append(quoted(actor['class'])+' '+quoted(name)+' '+str(count));compiled.extend(rows)
            total_tasks+=count
        output.append('entities '+str(len(tracks)));output.extend(compiled)
        total_tracks+=len(tracks);total_segments+=len(pc);total_sounds+=len(sounds)
        receipt['shots'].append(dict(index=shot_index,duration=duration,actions=timing,camera_segments=len(pc)))
    if total_tracks>8192 or total_tasks>32768 or total_segments>8192 or total_sounds>4096:raise schema.Error('scene exceeds native program capacities')
    encoded=('\n'.join(output)+'\n').encode()
    if len(encoded)>4*1024*1024:raise schema.Error('scene exceeds native 4 MiB capacity')
    return encoded,receipt
