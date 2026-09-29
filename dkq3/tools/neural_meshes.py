# SPDX-License-Identifier: GPL-2.0-or-later
"""Blender stage: prepare detailed neural GLB meshes and transfer the reviewed rig.

blender -b --python dkq3/tools/neural_meshes.py -- --source DIR --out DIR --closed
No experiment implementation is imported. The full-body IQM supplies skeleton,
weights and procedural clips as data. Original GLBs supply the rendered mesh.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys

import bpy
import bmesh
from mathutils.kdtree import KDTree
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import skeletal_iqm as sk
import dkimg


def stage(source, output, name, triangles, closed=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    original = source / f'{name}.glb'
    rig_path = source / f'out/{name}/models/players/{name}/{name}.iqm'
    rig = sk.read(rig_path.read_bytes())
    manifest = json.loads((source / f'out/{name}/manifest.json').read_text())
    bpy.ops.import_scene.gltf(filepath=str(original))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if len(meshes) != 1 or len(meshes[0].data.materials) != 1:
        raise ValueError('Expected a single reviewed character mesh/material')
    obj = meshes[0]
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    material = obj.data.materials[0]
    shader = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    link = shader.inputs['Base Color'].links
    if len(link) != 1 or link[0].from_node.type != 'TEX_IMAGE':
        raise ValueError('Expected the original base-color texture')
    texture = link[0].from_node.image
    # Blender imports glTF into Z-up, -Y-forward. Match the admitted rig's
    # +X-forward, +Y-left coordinate frame and its -24..32 vertical interval.
    coords = np.array([v.co[:] for v in obj.data.vertices])
    coords = coords[:, [1, 0, 2]] * [-1, 1, 1]
    scale = 56 / np.ptp(coords[:, 2])
    coords *= scale
    coords[:, 2] += -24 - coords[:, 2].min()
    if manifest['source']['turned_around']: coords[:, :2] *= -1
    obj.data.vertices.foreach_set('co', coords.astype(np.float32).ravel())
    obj.data.update()
    # Imported split normals are in the old axes. Recompute them from the
    # retained surface after rotation and reduction.
    if obj.data.has_custom_normals:
        obj.data.normals_split_custom_set([(0., 0., 0.)] * len(obj.data.loops))
    # Weld coincident seams before optional closure. The fine voxel interval
    # below closes disconnected neural shells without coarse armor inflation.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.0001)
    bm.to_mesh(obj.data)
    bm.free()
    original_object = obj
    if closed:
        obj = original_object.copy()
        obj.data = original_object.data.copy()
        bpy.context.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        original_object.select_set(False)
        obj.select_set(True)
        solid = obj.modifiers.new('Close neural surfaces', 'SOLIDIFY')
        solid.thickness, solid.offset = .2, 0
        bpy.ops.object.modifier_apply(modifier=solid.name)
        remesh = obj.modifiers.new('Continuous animation surface', 'REMESH')
        remesh.mode, remesh.voxel_size, remesh.use_smooth_shade = 'VOXEL', .15, True
        bpy.ops.object.modifier_apply(modifier=remesh.name)
    obj.data.calc_loop_triangles()
    count = len(obj.data.loop_triangles)
    if count > triangles:
        decimate = obj.modifiers.new('Game detail', 'DECIMATE')
        decimate.ratio = triangles / count
        decimate.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=decimate.name)
    mesh = obj.data
    mesh.calc_loop_triangles()
    baked = None
    if closed:
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=.006)
        bpy.ops.object.mode_set(mode='OBJECT')
        texture.colorspace_settings.name = 'Non-Color'
        source_nodes = material.node_tree.nodes
        emission = source_nodes.new('ShaderNodeEmission')
        material.node_tree.links.new(link[0].from_socket, emission.inputs['Color'])
        material.node_tree.links.new(emission.outputs[0], next(n for n in source_nodes if n.type == 'OUTPUT_MATERIAL').inputs['Surface'])
        size = max(texture.size)
        baked = bpy.data.images.new(name+' game atlas', width=size, height=size, alpha=False)
        baked.colorspace_settings.name = 'Non-Color'
        target_material = bpy.data.materials.new('Game atlas')
        target_material.use_nodes = True
        image_node = target_material.node_tree.nodes.new('ShaderNodeTexImage')
        image_node.image = baked
        target_material.node_tree.nodes.active = image_node
        mesh.materials.clear()
        mesh.materials.append(target_material)
        bpy.context.scene.render.engine = 'CYCLES'
        bpy.context.scene.cycles.device = 'CPU'
        bpy.context.scene.cycles.samples = 1
        bpy.ops.object.select_all(action='DESELECT')
        original_object.select_set(True)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.bake(type='EMIT', use_selected_to_active=True, cage_extrusion=.4, max_ray_distance=1.2, margin=8)
    # Interpolate the proxy's skin influences onto the retained surfaces.
    tree = KDTree(len(rig.arrays[0]))
    for i, p in enumerate(rig.arrays[0]): tree.insert(p, i)
    tree.balance()
    influences = np.zeros((len(mesh.vertices), len(rig.names)))
    for i, vertex in enumerate(mesh.vertices):
        neighbors = tree.find_n(vertex.co, 4)
        proximity = np.array([1/max(distance, .02)**2 for _, _, distance in neighbors])
        proximity /= proximity.sum()
        for blend, (_, index, _) in zip(proximity, neighbors):
            for joint, weight in zip(rig.arrays[4][index], rig.arrays[5][index]):
                influences[i, joint] += blend * weight
    indices = np.argsort(-influences, axis=1)[:, :4]
    weights = np.take_along_axis(influences, indices, axis=1)
    weights = np.rint(weights / weights.sum(axis=1, keepdims=True) * 255).astype(int)
    weights[:, 0] += 255 - weights.sum(axis=1)
    arrays = {k: [] for k in (0, 1, 2, 4, 5)}
    surfaces, faces, lookup = [], [], {}
    first_vertex = first_triangle = 0
    uv = mesh.uv_layers.active.data

    def finish():
        nonlocal first_vertex, first_triangle, lookup
        if len(faces) == first_triangle: return
        surfaces.append((f'body_{len(surfaces)}', f'models/neural/{name}/body', first_vertex,
                         len(arrays[0])-first_vertex, first_triangle, len(faces)-first_triangle))
        first_vertex, first_triangle, lookup = len(arrays[0]), len(faces), {}

    for triangle in mesh.loop_triangles:
        if len(lookup) + 3 > 990 or len(faces)-first_triangle >= 1900: finish()
        face = []
        for loop in triangle.loops:
            vertex = mesh.loops[loop].vertex_index
            normal = mesh.corner_normals[loop].vector[:]
            texcoord = uv[loop].uv[:]
            key = (vertex, *texcoord, *normal)
            if key not in lookup:
                lookup[key] = len(arrays[0])
                arrays[0].append(mesh.vertices[vertex].co[:])
                arrays[1].append((texcoord[0], 1-texcoord[1]))
                arrays[2].append(normal)
                arrays[4].append(indices[vertex])
                arrays[5].append(weights[vertex])
            face.append(lookup[key])
        # ioquake3's IQM path uses clockwise front faces.
        faces.append([face[0], face[2], face[1]])
    finish()
    rig.arrays = {k: np.array(v) for k, v in arrays.items()}
    rig.meshes, rig.triangles = surfaces, np.array(faces)
    output.mkdir(parents=True, exist_ok=True)
    (output / f'{name}.iqm').write_bytes(sk.write(rig))
    # Decode the embedded image directly; Blender's display color transform
    # must not alter an authored base-color texture when exporting it.
    raw = original.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20+length])
    material_data = document['materials'][0]['pbrMetallicRoughness']
    texture_data = document['textures'][material_data['baseColorTexture']['index']]
    image_index = texture_data.get('extensions', {}).get('EXT_texture_webp', {}).get('source', texture_data.get('source'))
    view = document['bufferViews'][document['images'][image_index]['bufferView']]
    start = 28 + length + view.get('byteOffset', 0)
    image_data = raw[start:start+view['byteLength']]
    if baked:
        pixels = np.empty(len(baked.pixels), np.float32)
        baked.pixels.foreach_get(pixels)
        pixels = np.clip(pixels.reshape(size, size, 4)[::-1, :, :3]*255, 0, 255).astype(np.uint8)
        png = dkimg.encode_png(pixels)
    else:
        png = subprocess.run(['ffmpeg', '-v', 'error', '-i', 'pipe:0', '-frames:v', '1',
                              '-f', 'image2pipe', '-c:v', 'png', 'pipe:1'], input=image_data,
                             stdout=subprocess.PIPE, check=True).stdout
    (output / f'{name}.png').write_bytes(png)
    report = dict(glb_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),
                  rig_sha256=hashlib.sha256(rig_path.read_bytes()).hexdigest(),
                  triangles=len(faces), vertices=len(arrays[0]), texture=list(texture.size),
                  method='Closed detail surface, base-color atlas, transferred skin weights' if closed else
                         'Original UV surfaces, seam welding, edge-collapse reduction, transferred skin weights')
    (output / f'{name}.json').write_text(json.dumps(report, indent=2)+'\n')
    print('neural mesh:', name, report, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--models', nargs='+', default=['hiro', 'mikiko', 'superfly', 'mishima', 'usagi'])
    parser.add_argument('--triangles', type=int, default=36000)
    parser.add_argument('--closed', action='store_true', help='close neural shells for animation and bake a source-resolution atlas')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    for name in args.models: stage(args.source, args.out, name, args.triangles, args.closed)
