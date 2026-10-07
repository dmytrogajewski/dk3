# SPDX-License-Identifier: GPL-2.0-or-later
"""Narrow JSON-job Blender adapter. Run through animation_author.py blender.

Importers/exporters belong to Blender. No downloaded executable plugins, arbitrary
Python expressions or paid-service credentials form part of this adapter.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))

import numpy as np

import animation_manifest as schema


def import_armature(bpy,job):
    source=Path(job['input']).resolve()
    before=set(bpy.data.objects)
    if source.suffix.lower()=='.bvh':
        bpy.ops.import_anim.bvh(filepath=str(source),axis_forward='-Z',axis_up='Y',
                                use_fps_scale=False,update_scene_fps=True,update_scene_duration=True)
    elif source.suffix.lower()=='.fbx':
        bpy.ops.import_scene.fbx(filepath=str(source),use_anim=True,anim_offset=0,automatic_bone_orientation=False)
    else:raise schema.Error('motion input must be BVH or FBX')
    rigs=[o for o in bpy.data.objects if o not in before and o.type=='ARMATURE']
    selected=job.get('armature')
    rigs=[o for o in rigs if selected is None or o.name==selected]
    if len(rigs)!=1:raise schema.Error('choose exactly one imported armature: '+str([o.name for o in rigs]))
    rig=rigs[0]
    # Pose matrices are sampled in scene coordinates. Uniform scale is applied
    # to translations only; rotation channels must remain proper unit matrices.
    return rig


def extract(bpy,rig,job):
    bones=[]
    def visit(bone):
        bones.append(bone)
        for child in bone.children:visit(child)
    for bone in rig.data.bones:
        if bone.parent is None:visit(bone)
    names=[b.name for b in bones];parents=[names.index(b.parent.name) if b.parent else -1 for b in bones]
    scene=bpy.context.scene
    action=rig.animation_data.action if rig.animation_data else None
    if action is None:raise schema.Error('source armature has no active animation action')
    low,high=action.frame_range
    # FBX stores integer ticks and may round a fractional FPS. Its imported
    # boundary can be 316.9987 instead of 317; admit nearby integer samples,
    # without adding an unanimated frame before or after the action.
    bounds=[math.ceil(low-.01),math.floor(high+.01)]
    first,last=job.get('frames',bounds)
    schema.number(first,0,100000,'first frame',integer=True);schema.number(last,first,100000,'last frame',integer=True)
    if first<bounds[0] or last>bounds[1]:raise schema.Error('requested frames exceed imported action; refusing padded holds')
    fps=float(scene.render.fps/scene.render.fps_base)
    def matrix(value):
        transform=np.array(value,dtype=float)
        scale=np.linalg.norm(transform[:3,:3],axis=0)
        if np.max(scale)-np.min(scale)>1e-4:raise schema.Error('nonuniform source scale is unsupported')
        transform[:3,:3]/=scale
        return transform
    rest=np.array([matrix(rig.matrix_world@b.matrix_local) for b in bones])
    frames=[]
    for f in range(first,last+1):
        scene.frame_set(f)
        frames.append([matrix(rig.matrix_world@rig.pose.bones[n].matrix) for n in names])
    source=Path(job['input'])
    metadata=dict(format=1,source=str(source.resolve()),source_sha256=schema.sha(source),
                  blender=bpy.app.version_string,armature=rig.name,frames=[first,last],
                  action_frames=bounds,
                  action_subframes=[float(low),float(high)],
                  coordinates='Blender scene: Z up; forward must be specified in retarget recipe')
    if job.get('license'):
        license_path=Path(job['license'])
        metadata['license']=dict(source=json.loads(license_path.read_text()),receipt_sha256=schema.sha(license_path))
    # Keep Blender's embedded Python independent of the host SciPy ABI.
    # The host validates these rigid samples before retargeting/resampling.
    destination=Path(job['output']);destination.parent.mkdir(parents=True,exist_ok=True)
    np.savez_compressed(destination,names=np.array(names),parents=np.array(parents),rest=rest,
                        world=np.array(frames),fps=np.array(fps),travel=np.zeros((len(frames),3)),
                        metadata=np.array(json.dumps(metadata,allow_nan=False)))
    return dict(**metadata,output=str(Path(job['output']).resolve()),output_sha256=schema.sha(job['output']),
                fps=fps,joints=len(names),frame_count=len(frames),bones=names)


def texture_assignments(model,job):
    declared=job.get('textures',{})
    if not isinstance(declared,dict) or any(not isinstance(k,str) or not isinstance(v,str) or not v for k,v in declared.items()):
        raise schema.Error('textures must map IQM material names to local image paths')
    materials={row[1] for row in model.meshes}
    if set(declared)-materials:raise schema.Error('texture mapping names absent IQM material')
    if job.get('texture') and len(materials)>1 and not declared:
        raise schema.Error('multi-material IQM requires explicit textures; refusing one atlas across body/head/props')
    assignments={name:declared.get(name,job.get('texture')) for name in materials}
    if declared and any(path is None for path in assignments.values()):raise schema.Error('missing IQM material texture')
    return {name:Path(path).resolve() if path else None for name,path in assignments.items()}


def preview(bpy,job):
    import skeletal_iqm as sk
    from mathutils import Vector
    model=sk.read(Path(job['input']).read_bytes())
    frames=job.get('frames',[0]);views=job.get('views',['front','side'])
    if not isinstance(frames,list) or not frames or len(frames)>240:raise schema.Error('preview needs 1..240 frame indices')
    if not isinstance(views,list) or not views or len(views)>4 or len(set(views))!=len(views):raise schema.Error('preview needs 1..4 unique views')
    for frame in frames:schema.number(frame,0,len(model.frames)-1,'preview frame',integer=True)
    if any(v not in ('front','side','back','three_quarter') for v in views):raise schema.Error('unknown preview view')
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8
    size=schema.vector(job.get('size',[640,640]),'preview size',2)
    for value in size:schema.number(value,64,2048,'preview resolution',integer=True)
    scene.render.resolution_x,scene.render.resolution_y=size
    scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
    scene.world=bpy.data.worlds.new('review-world');scene.world.color=(.12,.12,.12)
    scene.view_settings.view_transform='Standard'
    meshes=[]
    assignments=texture_assignments(model,job);materials={}
    for name,texture in assignments.items():
        material=bpy.data.materials.new(name);material.use_nodes=True
        shader=material.node_tree.nodes.get('Principled BSDF');shader.inputs['Roughness'].default_value=.8
        if texture:
            node=material.node_tree.nodes.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(texture))
            material.node_tree.links.new(node.outputs['Color'],shader.inputs['Base Color'])
        else:shader.inputs['Base Color'].default_value=(.45,.48,.5,1)
        materials[name]=material
    for name,material_name,fv,nv,ft,nt in model.meshes:
        mesh=bpy.data.meshes.new(name)
        mesh.from_pydata(model.arrays[0][fv:fv+nv].tolist(),[],(model.triangles[ft:ft+nt]-fv).tolist())
        uv=mesh.uv_layers.new(name='UVMap')
        for loop in mesh.loops:
            u,v=model.arrays[1][fv+loop.vertex_index];uv.data[loop.index].uv=(u,1-v)
        obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj);mesh.materials.append(materials[material_name])
        for polygon in mesh.polygons:polygon.use_smooth=True
        meshes.append((mesh,fv,nv))
    rest=model.arrays[0];lo,hi=rest.min(axis=0),rest.max(axis=0)
    height=max(hi[2]-lo[2],1);center=(lo+hi)/2
    bpy.ops.mesh.primitive_plane_add(size=height*10,location=(0,0,lo[2]-.5))
    for location,power in (((height,-height,height*2),height*height*50),((-height,height,height),height*height*20)):
        data=bpy.data.lights.new('review-area','AREA');data.energy=power;data.shape='DISK';data.size=height*2
        obj=bpy.data.objects.new('review-area',data);scene.collection.objects.link(obj);obj.location=location
        obj.rotation_euler=(Vector(center)-obj.location).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('review-camera');data.type='ORTHO';data.ortho_scale=height*1.3
    camera=bpy.data.objects.new('review-camera',data);scene.collection.objects.link(camera);scene.camera=camera
    directions={'front':(1,0,.12),'back':(-1,0,.12),'side':(0,-1,.12),'three_quarter':(1,-1,.18)}
    output=Path(job['output']);output.mkdir(parents=True,exist_ok=True);rendered=[]
    for f in frames:
        points=sk.skin(model,model.frames[f:f+1])[0]
        for mesh,start,count in meshes:
            mesh.vertices.foreach_set('co',points[start:start+count].ravel());mesh.update()
        for view in views:
            camera.location=Vector(center)+Vector(directions[view])*height*2
            camera.rotation_euler=(Vector(center)-camera.location).to_track_quat('-Z','Y').to_euler()
            destination=output/f'{view}-{f:05}.png';scene.render.filepath=str(destination.resolve())
            bpy.ops.render.render(write_still=True)
            rendered.append(dict(frame=f,view=view,path=str(destination),sha256=schema.sha(destination)))
    if job.get('blend'):bpy.ops.wm.save_as_mainfile(filepath=str(Path(job['blend']).resolve()))
    return dict(input_sha256=schema.sha(job['input']),textures={name:dict(path=str(path),sha256=schema.sha(path)) if path else None for name,path in assignments.items()},
                blender=bpy.app.version_string,rendered=rendered,scope='CPU Blender preview of exported IQM skin; native replay is a separate check')


def dispatch(job):
    import bpy
    op=job.get('operation')
    allowed={'import_motion':('operation','input','output','armature','frames','license'),
             'convert_fbx':('operation','input','output','armature'),
             'render_preview':('operation','input','output','texture','textures','frames','views','size','blend')}
    if op not in allowed:raise schema.Error('unsupported Blender operation '+str(op))
    schema.fields(job,allowed[op],('operation','input','output'),'Blender job')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if op=='render_preview':return preview(bpy,job)
    rig=import_armature(bpy,job)
    if op=='import_motion':return extract(bpy,rig,job)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
    if rig.animation_data and rig.animation_data.action:
        low,high=rig.animation_data.action.frame_range
        bpy.context.scene.frame_start=math.floor(low);bpy.context.scene.frame_end=math.ceil(high)
    destination=Path(job['output']).resolve();destination.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=str(destination),use_selection=True,object_types={'ARMATURE'},
                             bake_anim=True,bake_anim_use_all_actions=False,bake_anim_use_nla_strips=False,
                             add_leaf_bones=False,axis_forward='-Z',axis_up='Y')
    return dict(output=str(destination),sha256=schema.sha(destination),blender=bpy.app.version_string)


def main():
    argv=sys.argv[sys.argv.index('--')+1:]
    parser=argparse.ArgumentParser();parser.add_argument('--job',type=Path,required=True);parser.add_argument('--result',type=Path,required=True)
    args=parser.parse_args(argv)
    result=dispatch(json.loads(args.job.read_text()))
    schema.write_json(args.result,dict(passed=True,job_sha256=schema.sha(args.job),result=result))


if __name__=='__main__':main()
