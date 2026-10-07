# SPDX-License-Identifier: GPL-2.0-or-later
"""Extract a dedicated close-up TRELLIS head without whole-body decimation."""
import argparse
import json
from pathlib import Path
import sys

import bpy
import numpy as np


def extract(directory, budget):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(directory / 'model.glb'))
    objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    if not objects:
        raise ValueError('Head reconstruction contains no mesh')
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(obj.data.materials) != 1:
        raise ValueError('Expected one head atlas')
    shader = next(node for node in obj.data.materials[0].node_tree.nodes if node.type == 'BSDF_PRINCIPLED')
    texture = shader.inputs['Base Color'].links[0].from_node.image
    points = np.array([vertex.co[:] for vertex in obj.data.vertices])[:, [1, 0, 2]] * [-1, 1, 1]
    obj.data.vertices.foreach_set('co', points.astype('f4').ravel())
    obj.data.update()
    if obj.data.has_custom_normals:
        obj.data.normals_split_custom_set([(0., 0., 0.)] * len(obj.data.loops))
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=.000001)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.data.calc_loop_triangles()
    original = len(obj.data.loop_triangles)
    if original > budget:
        modifier = obj.modifiers.new('Dedicated head budget', 'DECIMATE')
        modifier.ratio = budget / original
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    mesh = obj.data
    mesh.calc_loop_triangles()
    vertices, uv, normals, triangles, lookup = [], [], [], [], {}
    for tri in mesh.loop_triangles:
        face = []
        for loop_index in tri.loops:
            loop = mesh.loops[loop_index]
            point = mesh.vertices[loop.vertex_index].co[:]
            coord = mesh.uv_layers.active.data[loop_index].uv[:]
            normal = mesh.corner_normals[loop_index].vector[:]
            key = (loop.vertex_index, tuple(coord), tuple(normal))
            if key not in lookup:
                lookup[key] = len(vertices)
                vertices.append(point)
                uv.append((coord[0], 1 - coord[1]))
                normals.append(normal)
            face.append(lookup[key])
        triangles.append(face[::-1])
    np.savez_compressed(directory / 'head-geometry.npz', points=np.asarray(vertices, dtype='f4'),
                        uv=np.asarray(uv, dtype='f4'), normals=np.asarray(normals, dtype='f4'),
                        triangles=np.asarray(triangles, dtype='u4'))
    scene = bpy.context.scene
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    texture.save_render(str(directory / 'head.png'), scene=scene)
    if (directory / 'head.png').read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Invalid head atlas encoding')
    (directory / 'head-geometry.json').write_text(json.dumps(dict(
        source_triangles=original, triangles=len(triangles), vertices=len(vertices),
        dedicated_head_budget=budget, texture_size=list(texture.size)), indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--head', type=Path, required=True)
    parser.add_argument('--triangles', type=int, default=100000)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    extract(args.head, args.triangles)
