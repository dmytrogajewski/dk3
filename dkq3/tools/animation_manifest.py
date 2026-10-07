# SPDX-License-Identifier: GPL-2.0-or-later
"""Strict, editable source manifests for the existing native IQM clip table."""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import os
import tempfile

import yaml


class Error(ValueError):
    def __init__(self, message, code='ANIM_INVALID_SOURCE', field='source'):
        super().__init__(message)
        self.code, self.field = code, field

    def diagnostic(self, source=None):
        return dict(code=self.code, field=self.field, source=str(source) if source else None,
                    message=str(self), severity='error')


class Loader(yaml.SafeLoader):
    pass


def _mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if not isinstance(key, str) or key in result:
            raise Error(f"line {key_node.start_mark.line+1}: duplicate or non-string key {key!r}", 'ANIM_DUPLICATE_KEY')
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


Loader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _mapping)


def load(path):
    path = Path(path)
    if path.stat().st_size > 4*1024*1024:
        raise Error('authoring source exceeds 4 MiB')
    try:
        value = yaml.load(path.read_text(encoding='utf-8'), Loader=Loader)
    except yaml.YAMLError as error:
        raise Error(f'{path}: {error}', 'ANIM_INVALID_SOURCE', str(path)) from error
    if not isinstance(value, dict):
        raise Error('authoring source must be a mapping')
    return value


def fields(value, allowed, required=(), where='source'):
    if not isinstance(value, dict):
        raise Error(f'{where}: expected a mapping')
    extra, missing = set(value)-set(allowed), set(required)-set(value)
    if extra or missing:
        raise Error(f'{where}: unknown fields {sorted(extra)}; missing fields {sorted(missing)}')
    return value


def number(value, low=-math.inf, high=math.inf, where='number', integer=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise Error(f'{where}: expected a finite number', 'ANIM_NONFINITE_TRANSFORM', where)
    if not low <= value <= high or (integer and not isinstance(value, int)):
        raise Error(f'{where}: expected {"integer " if integer else ""}in [{low}, {high}]', 'ANIM_INVALID_RANGE', where)
    return value


def vector(value, where='vector', width=3):
    if not isinstance(value, list) or len(value) != width:
        raise Error(f'{where}: expected {width} numbers')
    return [number(v, where=where) for v in value]


def text(value, where='name', limit=64):
    if not isinstance(value, str) or not value or len(value.encode('utf-8')) >= limit or any(c.isspace() or ord(c)<32 for c in value) or any(c in value for c in '\\"'):
        raise Error(f'{where}: expected a nonempty token shorter than {limit} bytes')
    return value


def asset(value, where='asset', suffix=None):
    text(value, where, 128)
    path = PurePosixPath(value)
    if path.is_absolute() or '..' in path.parts or value != str(path) or (suffix and path.suffix != suffix):
        raise Error(f'{where}: expected a normalized relative asset path', 'ANIM_INVALID_PATH', where)
    return value


def span(value, where='frame range'):
    result = vector(value, where, 2)
    for v in result:
        number(v, 0, 65535, where, integer=True)
    if result[1] < result[0]:
        raise Error(f'{where}: reversed range', 'ANIM_INVALID_RANGE', where)
    return result


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''):
            h.update(block)
    return h.hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    write_if_changed(path, (json.dumps(value, indent=2, allow_nan=False)+'\n').encode('utf-8'))


def write_if_changed(path, encoded):
    """Atomic publication; identical output retains its inode and timestamp."""
    path = Path(path)
    if path.is_file() and path.read_bytes() == encoded:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.'+path.name+'.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(encoded)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    return True


def prop_contacts(value):
    """Bounded offline grip constraints; no additional runtime data fields."""
    if not isinstance(value,list) or len(value)>16:raise Error('prop_contacts requires at most 16 constraints')
    used=set()
    for contact in value:
        fields(contact,('prop','members','pivot','parent','attachment_bone','position','source_grip','intervals','max_error','max_surface_error','finger_pose','blend_frames','orientation','floor_contact'),
               ('prop','members','pivot','parent','position'),'prop contact')
        text(contact['prop']);text(contact['parent'])
        if not contact['prop'].startswith('prop_') or contact['parent'] not in ('hand_l','hand_r'):
            raise Error('prop contact requires a prop and an anatomical hand')
        members=contact['members']
        if not isinstance(members,list) or not 1<=len(members)<=8:raise Error('prop contact needs 1..8 group members')
        for name in members:
            text(name)
            if not name.startswith('prop_') or name in used:raise Error('prop contact groups must be disjoint prop bones')
            used.add(name)
        if contact['prop'] not in members:raise Error('contact prop must belong to its group')
        vector(contact['pivot'],'prop contact pivot');vector(contact['position'],'hand grip position')
        if 'source_grip' in contact and type(contact['source_grip']) is not bool:raise Error('source_grip must be boolean')
        if 'attachment_bone' in contact:
            text(contact['attachment_bone'])
            # Newly authored meshes can bind directly to the anatomical hand;
            # legacy fitted meshes use its measured surface corrective. Both
            # retain the same source-grip and visible-surface validation.
            if contact['attachment_bone'] not in (contact['parent'],'deform_'+contact['parent']) or not contact.get('source_grip'):raise Error('grip surface must use its declared source hand or hand corrective')
        number(contact.get('max_error',.05),.0001,1,'prop contact maximum error')
        if 'max_surface_error' in contact:number(contact['max_surface_error'],.01,2,'hand surface maximum error')
        if 'intervals' in contact:
            if not isinstance(contact['intervals'],list) or not 1<=len(contact['intervals'])<=64:raise Error('prop contact needs 1..64 local intervals')
            previous=-1
            for interval in contact['intervals']:
                a,b=span(interval,'prop contact interval')
                if a<=previous:raise Error('prop contact intervals must be ordered and disjoint')
                previous=b
        number(contact.get('blend_frames',4),1,60,'finger grip blend',integer=True)
        if contact.get('orientation','inherit') not in ('inherit','source_world'):raise Error('grip orientation must be inherit/source_world')
        if 'floor_contact' in contact:
            floor=contact['floor_contact'];fields(floor,('point','height','max_error','solve'),('point','height'),'prop floor contact')
            vector(floor['point'],'prop floor point');number(floor['height'],-1e5,1e5,'prop floor height')
            number(floor.get('max_error',.1),.0001,1,'prop floor error')
            if 'solve' in floor and type(floor['solve']) is not bool:raise Error('floor solve must be boolean')
            if contact.get('orientation')!='source_world':raise Error('floor contact requires measured source-world prop orientation')
        fingers=contact.get('finger_pose',{})
        if not isinstance(fingers,dict) or len(fingers)>2:raise Error('finger_pose supports the finger/thumb pair')
        for name,angles in fingers.items():
            text(name)
            if not name.startswith(('fingers_','thumb_')):raise Error('grip pose requires finger/thumb bones')
            vector(angles,'finger pose angles')
            for angle in angles:number(angle,-90,90,'finger pose angle')
    return value


def validate(document, counts=None):
    fields(document, ('version', 'characters'), ('version', 'characters'))
    if document['version'] != 1 or not isinstance(document['characters'], list) or not document['characters']:
        raise Error('manifest requires version 1 and a nonempty characters list')
    keys, targets, names, ranges, total = set(), set(), set(), set(), 0
    for character in document['characters']:
        fields(character, ('character','source_model','mapping_key','target_model','iqm','skeleton','units_per_meter','bind_pose_sha256','provenance','clips'),
               ('character','source_model','target_model','iqm','skeleton','clips'), 'character')
        name = text(character['character'])
        if not re.fullmatch('[A-Za-z0-9_-]+',name):raise Error('character must be a basename', 'ANIM_INVALID_PATH', name)
        if name in names:raise Error('duplicate character name', 'ANIM_DUPLICATE_CHARACTER', name)
        names.add(name)
        source = asset(character['source_model'], name+'.source_model', '.dkm')
        key = text(character.get('mapping_key', source), name+'.mapping_key')
        target = asset(character['target_model'], name+'.target_model', '.iqm')
        if not target.startswith('models/neural/') or key in keys or target in targets:
            raise Error('duplicate character/mapping or target outside models/neural/')
        keys.add(key); targets.add(target)
        text(character['skeleton'])
        if 'bind_pose_sha256' in character:
            value=character['bind_pose_sha256']
            if not isinstance(value,str) or not re.fullmatch('[a-f0-9]{64}',value):raise Error('bind_pose_sha256 requires a SHA-256', 'ANIM_INCOMPATIBLE_SKELETON', name)
        if 'provenance' in character:
            fields(character['provenance'],('origin','license','redistribution','credit','capture_profile_sha256'),
                   ('origin','license','redistribution','credit'),'character provenance')
            if any(not isinstance(value,str) or not value or len(value)>4096 for value in character['provenance'].values()):raise Error('provenance values require bounded text')
        if 'units_per_meter' in character:
            number(character['units_per_meter'], .001, 1e6, 'units_per_meter')
        if not isinstance(character['iqm'], str) or not isinstance(character['clips'], dict) or not character['clips']:
            raise Error(name+': expected iqm path and nonempty clips mapping')
        for label, clip in character['clips'].items():
            text(label)
            if not re.fullmatch('[A-Za-z0-9_-]+',label):raise Error('clip must be a basename', 'ANIM_INVALID_PATH', name+'.'+label)
            fields(clip, ('source_frames','target_frames','sequence','authority_fps','fps','loop','root_motion','contacts',
                          'max_foot_slide','max_loop_position','max_loop_angle','max_joint_step','joint_limits',
                          'attachments','props','prop_contacts','correctives','source_fidelity','movement_speed','attack_grid','motion','input_frames','retarget','solve_contacts','solve_contact_root','contact_floor'),
                   ('source_frames','target_frames','sequence','fps','loop','root_motion'), name+'.'+label)
            first,last = span(clip['source_frames'])
            start,end = span(clip['target_frames'])
            if (key,first,last) in ranges:
                raise Error(f'{name}.{label}: duplicate authoritative frame range', 'ANIM_DUPLICATE_CLIP', name+'.'+label)
            ranges.add((key,first,last)); total += 1
            text(clip['sequence'], 'authoritative sequence', 32)
            number(clip['fps'], 0, 240, 'native clip fps',integer=True)
            if 'authority_fps' in clip: number(clip['authority_fps'], .001, 240, 'authoritative fps')
            if 'movement_speed' in clip:number(clip['movement_speed'],.001,2000,'movement speed')
            if type(clip['loop']) is not bool or clip['root_motion'] not in ('in_place','preserve'):
                raise Error('clip needs a boolean loop and root_motion in_place/preserve')
            if counts is not None and (target not in counts or end >= counts[target]):
                raise Error(f'{name}.{label}: target range outside IQM frames')
            for threshold in ('max_foot_slide','max_loop_position','max_loop_angle','max_joint_step'):
                if threshold in clip: number(clip[threshold], 0, where=threshold)
            for mapping in ('contacts','joint_limits','props'):
                if mapping in clip and not isinstance(clip[mapping],dict):raise Error(mapping+' must be a mapping')
            if 'attachments' in clip and not isinstance(clip['attachments'],list):raise Error('attachments must be a list')
            if 'motion' in clip and (not isinstance(clip['motion'],str) or not clip['motion']):raise Error('motion must be a local path')
            if 'retarget' in clip and not isinstance(clip['retarget'],(str,dict)):raise Error('retarget must be a local recipe path or mapping')
            for bone, intervals in clip.get('contacts', {}).items():
                text(bone)
                if not isinstance(intervals, list): raise Error('contacts must be lists of inclusive local intervals')
                previous = -1
                for interval in intervals:
                    a,b = span(interval, 'contact interval')
                    if a <= previous or b >= end-start+1:
                        raise Error('overlapping/unsorted contact interval or contact beyond clip')
                    previous = b
            for bone, limit in clip.get('joint_limits', {}).items():
                text(bone); number(limit, 0, 180, 'joint angular limit')
            for attachment in clip.get('attachments', []):
                fields(attachment, ('bone','max_position_step','max_angle_step'), ('bone',), 'attachment')
                text(attachment['bone'])
                for limit in ('max_position_step','max_angle_step'):
                    if limit in attachment: number(attachment[limit], 0, where=limit)
            for bone,prop in clip.get('props',{}).items():
                if not bone.startswith('prop_'):raise Error('prop policy must name an existing prop joint')
                fields(prop,('mode','frames','parent','position','angles'),('mode',),'prop policy')
                if prop['mode'] not in ('inherit','hide','attach','captured'):raise Error('prop mode must be inherit/hide/attach/captured')
                if prop['mode']=='captured' and set(prop)!={'mode'}:raise Error('captured prop policy accepts only mode')
                if 'frames' in prop:span(prop['frames'])
                if prop['mode']=='attach':
                    text(prop.get('parent'),'prop attachment parent');vector(prop.get('position'),'prop attachment position')
                    vector(prop.get('angles',[0,0,0]),'prop attachment angles')
            prop_contacts(clip.get('prop_contacts',[]))
            correctives=clip.get('correctives',{})
            if not isinstance(correctives,dict) or len(correctives)>16:raise Error('correctives require a bounded mapping')
            for contact in clip.get('prop_contacts',[]):
                if any(b>=end-start+1 for a,b in contact.get('intervals',[])):raise Error('prop contact interval beyond clip','ANIM_INVALID_RANGE')
                if contact.get('source_grip') and any(clip.get('props',{}).get(n,{}).get('mode')!='captured' for n in contact['members']):
                    raise Error('source grip requires captured original prop observations')
                if contact.get('attachment_bone') not in (None,contact['parent'],*clip.get('correctives',{})):
                    raise Error('grip corrective is not declared by this clip', 'ANIM_UNKNOWN_BONE',contact['attachment_bone'])
            for target_bone,source_bone in correctives.items():
                text(target_bone);text(source_bone)
                if target_bone!='deform_'+source_bone or (source_bone not in ('pelvis','spine','chest','neck','head') and not source_bone.startswith(('upperarm_','forearm_','hand_'))):
                    raise Error('correctives support explicit torso/head/arm surface regions')
            if 'source_fidelity' in clip:
                fields(clip['source_fidelity'],('max_direction_degrees',),('max_direction_degrees',),'source fidelity')
                number(clip['source_fidelity']['max_direction_degrees'],.01,15,'source direction error')
            if 'input_frames' in clip: span(clip['input_frames'])
            if 'solve_contacts' in clip and type(clip['solve_contacts']) is not bool:
                raise Error('solve_contacts must be boolean')
            if 'solve_contact_root' in clip and (type(clip['solve_contact_root']) is not bool or not clip.get('solve_contacts')):
                raise Error('solve_contact_root requires contact solving and a boolean')
            if 'contact_floor' in clip:
                number(clip['contact_floor'],-1e5,1e5,'contact floor')
                if not clip.get('solve_contacts') or not clip.get('contacts'):raise Error('contact_floor requires declared solved contacts')
            grid = clip.get('attack_grid')
            if grid:
                fields(grid, ('first','count'), ('first','count'), 'attack_grid')
                number(grid['first'],0,65535,integer=True); number(grid['count'],1,65535,integer=True)
                bound = grid['first']+(end-start+1)*grid['count']
                if bound>65536 or (counts is not None and bound>counts[target]):
                    raise Error('attack grid outside IQM/u16 frames')
    if len(keys)>160 or total>2048:
        raise Error('manifest exceeds native character/clip capacities')
    return document


def compile_manifest(document, counts=None):
    validate(document, counts)
    lines = []
    for character in document['characters']:
        key = character.get('mapping_key', character['source_model'])
        for label, clip in character['clips'].items():
            grid = clip.get('attack_grid', {})
            lines.append(' '.join(map(str, [key, *clip['source_frames'], *clip['target_frames'],
                                           clip['fps'], grid.get('first',0),grid.get('count',0)])))
    result = ('\n'.join(lines)+'\n').encode()
    if len(result)>256*1024: raise Error('compiled table exceeds native 256 KiB capacity')
    return result


def effective_rate(clip):
    if clip['fps']:return clip['fps']
    if 'authority_fps' not in clip:raise Error('fps zero build needs the actual authoritative sequence rate')
    source_count=clip['source_frames'][1]-clip['source_frames'][0]+1
    target_count=clip['target_frames'][1]-clip['target_frames'][0]+1
    return target_count*clip['authority_fps']/source_count


def bind_identity(model):
    """Canonical skeleton contract; independent of animation channel quantization."""
    import numpy as np
    names=json.dumps([model.names,model.parents],ensure_ascii=True,separators=(',',':')).encode('ascii')
    return hashlib.sha256(names+np.asarray(model.bind,dtype='<f4').tobytes()).hexdigest()


def validate_rig(character,model):
    if character.get('bind_pose_sha256',bind_identity(model))!=bind_identity(model):
        raise Error('manifest targets another bind pose or hierarchy', 'ANIM_INCOMPATIBLE_SKELETON', character['character'])
    for label,clip in character['clips'].items():
        referenced=set(clip.get('contacts',{}))|set(clip.get('joint_limits',{}))|set(clip.get('props',{}))|set(clip.get('correctives',{}))|{a['bone'] for a in clip.get('attachments',[])}
        for contact in clip.get('prop_contacts',[]):
            referenced|=set(contact['members'])|{contact['parent'],contact['prop']}|set(contact.get('finger_pose',{}))
            if contact.get('attachment_bone'):referenced.add(contact['attachment_bone'])
        referenced|=set(clip.get('correctives',{}).values())
        missing=referenced-set(model.names)
        if missing:raise Error('unknown rig bones: '+', '.join(sorted(missing)), 'ANIM_UNKNOWN_BONE', character['character']+'.'+label)
        for target_bone,source_bone in clip.get('correctives',{}).items():
            parent=model.parents[model.names.index(target_bone)]
            if parent<0 or model.names[parent]!=source_bone:raise Error('surface corrective must descend directly from its canonical bone','ANIM_INCOMPATIBLE_SKELETON',target_bone)
        for contact in clip.get('prop_contacts',[]):
            parent=model.names.index(contact['parent'])
            for name in contact.get('finger_pose',{}):
                ancestor=model.parents[model.names.index(name)]
                while ancestor>=0 and ancestor!=parent:ancestor=model.parents[ancestor]
                if ancestor!=parent:raise Error('grip finger must descend from the contact hand', 'ANIM_ATTACHMENT_ERROR', name)


def aliases(document):
    validate(document)
    return {c['character']:{name:dict(sequence=clip['sequence'], duration=(clip['source_frames'][1]-clip['source_frames'][0]+1)/clip['authority_fps'] if 'authority_fps' in clip else None,
                                    target_frames=clip['target_frames'], fps=clip['fps'],movement_speed=clip.get('movement_speed'))
                            for name,clip in c['clips'].items()} for c in document['characters']}
