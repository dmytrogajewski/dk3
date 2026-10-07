# SPDX-License-Identifier: GPL-2.0-or-later
"""Render the actual face mesh/atlas from fixed projection and review angles."""
import argparse
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import skeletal_iqm as sk


def render(mesh_path, texture, output, frame=None,plan=None,lit=False,clay=False,resolution=768):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    model = sk.read(mesh_path.read_bytes())
    mesh = bpy.data.meshes.new('Hiro')
    points = model.arrays[0] if frame is None else sk.skin(model, model.frames[frame:frame+1])[0]
    mesh.from_pydata(points.tolist(), [], model.triangles[:, [0, 2, 1]].tolist())
    mesh.update()
    if lit and frame is None:
        for polygon in mesh.polygons:polygon.use_smooth=True
        mesh.normals_split_custom_set([model.arrays[2][loop.vertex_index].tolist() for loop in mesh.loops])
    obj = bpy.data.objects.new('Hiro', mesh)
    bpy.context.collection.objects.link(obj)
    uv = mesh.uv_layers.new()
    for i, loop in enumerate(mesh.loops):
        u, v = model.arrays[1][loop.vertex_index]
        uv.data[i].uv = u, 1-v
    materials = {}
    for _, label, _, _, first, count in model.meshes:
        selected = texture.with_name('head.png') if label.endswith('/head') else texture
        if selected not in materials:
            material = bpy.data.materials.new(selected.stem + ' albedo')
            material.use_nodes = True
            materials[selected] = len(mesh.materials)
            mesh.materials.append(material)
            nodes, links = material.node_tree.nodes, material.node_tree.links
            image = nodes.new('ShaderNodeTexImage')
            image.image = bpy.data.images.load(str(selected.resolve()))
            if lit:
                shader = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
                if clay: shader.inputs['Base Color'].default_value = (.55,.55,.55,1)
                else: links.new(image.outputs['Color'], shader.inputs['Base Color'])
                shader.inputs['Roughness'].default_value = .8
            else:
                emission = nodes.new('ShaderNodeEmission')
                links.new(image.outputs['Color'], emission.inputs['Color'])
                links.new(emission.outputs[0], next(n for n in nodes if n.type == 'OUTPUT_MATERIAL').inputs['Surface'])
        for polygon in mesh.polygons[first:first + count]:
            polygon.material_index = materials[selected]
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device, scene.cycles.samples = 'CPU', 4
    scene.render.resolution_x = scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'Standard'
    scene.world = bpy.data.worlds.new('gray')
    scene.world.color = (.07, .07, .07)
    camera = bpy.data.objects.new('camera', bpy.data.cameras.new('camera'))
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    projection_scale=plan['scale'] if plan else 1.
    projection_origin=np.asarray(plan['origin']) if plan else np.zeros(3)
    registered=plan.get('camera',{}) if plan and frame is None else {}
    if lit:
        scene.world.use_nodes=True
        scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.5,.5,.5,1)
        scene.world.node_tree.nodes['Background'].inputs[1].default_value=.6
        center=projection_origin+np.array(registered.get('center',[0,0,26]))*projection_scale
        for name,offset,energy in [('key',[25,-15,30],18000),('fill',[20,25,10],7000)]:
            light=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'))
            bpy.context.collection.objects.link(light)
            light.location=center+np.asarray(offset)*projection_scale
            light.rotation_euler=(Vector(center)-light.location).to_track_quat('-Z','Y').to_euler()
            light.data.energy=energy*projection_scale**2
            light.data.size=20*projection_scale
    camera.data.type, camera.data.ortho_scale = 'ORTHO', registered.get('ortho_scale',15 if frame is None else 72)*projection_scale
    output.mkdir(parents=True, exist_ok=True)
    angles = (plan.get('review_angles') if plan else None) or [('front', 0), ('quarter', -30), ('side', -60), ('other-side', 60)]
    for label, angle in angles:
        if label not in ('front', 'quarter', 'other-quarter', 'side', 'other-side') or not -90 <= angle <= 90:
            raise ValueError('Invalid character review camera')
        theta = np.deg2rad(angle)
        height = 26 if frame is None else 4
        center=projection_origin+np.array(registered.get('center',[0,0,height]))*projection_scale
        camera.location = center+np.array([100*np.cos(theta),100*np.sin(theta),0])*projection_scale
        camera.rotation_euler = (Vector(center)-camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(output/f'{label}.png')
        bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('mesh', 'texture', 'out'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--frame', type=int, help='render the skinned full body at this IQM frame')
    parser.add_argument('--plan',type=Path,help='normalized projection camera for a monster in source coordinates')
    parser.add_argument('--lit',action='store_true',help='review actual serialized normals under studio lighting')
    parser.add_argument('--clay',action='store_true',help='inspect actual eye sockets and surface structure without texture')
    parser.add_argument('--resolution',type=int,default=768,help='square review image size')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    render(args.mesh, args.texture, args.out, args.frame,json.loads(args.plan.read_text()) if args.plan else None,args.lit or args.clay,args.clay,args.resolution)
