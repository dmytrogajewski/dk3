# SPDX-License-Identifier: GPL-2.0-or-later
"""Render the actual face mesh/atlas from fixed projection and review angles."""
import argparse
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import skeletal_iqm as sk


def render(mesh_path, texture, output, frame=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    model = sk.read(mesh_path.read_bytes())
    mesh = bpy.data.meshes.new('Hiro')
    points = model.arrays[0] if frame is None else sk.skin(model, model.frames[frame:frame+1])[0]
    mesh.from_pydata(points.tolist(), [], model.triangles[:, [0, 2, 1]].tolist())
    mesh.update()
    obj = bpy.data.objects.new('Hiro', mesh)
    bpy.context.collection.objects.link(obj)
    uv = mesh.uv_layers.new()
    for i, loop in enumerate(mesh.loops):
        u, v = model.arrays[1][loop.vertex_index]
        uv.data[i].uv = u, 1-v
    material = bpy.data.materials.new('albedo')
    material.use_nodes = True
    mesh.materials.append(material)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    image = nodes.new('ShaderNodeTexImage')
    image.image = bpy.data.images.load(str(texture.resolve()))
    emission = nodes.new('ShaderNodeEmission')
    links.new(image.outputs['Color'], emission.inputs['Color'])
    links.new(emission.outputs[0], next(n for n in nodes if n.type == 'OUTPUT_MATERIAL').inputs['Surface'])
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device, scene.cycles.samples = 'CPU', 4
    scene.render.resolution_x = scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'Standard'
    scene.world = bpy.data.worlds.new('gray')
    scene.world.color = (.07, .07, .07)
    camera = bpy.data.objects.new('camera', bpy.data.cameras.new('camera'))
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type, camera.data.ortho_scale = 'ORTHO', 15 if frame is None else 72
    output.mkdir(parents=True, exist_ok=True)
    for label, angle in [('front', 0), ('quarter', -30), ('side', -60), ('other-side', 60)]:
        theta = np.deg2rad(angle)
        height = 26 if frame is None else 4
        camera.location = (100*np.cos(theta), 100*np.sin(theta), height)
        camera.rotation_euler = (Vector((0, 0, height))-camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(output/f'{label}.png')
        bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('mesh', 'texture', 'out'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--frame', type=int, help='render the skinned full body at this IQM frame')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    render(args.mesh, args.texture, args.out, args.frame)
