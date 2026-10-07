# SPDX-License-Identifier: GPL-2.0-or-later
"""Blender CPU capture and textured TRELLIS mesh conversion; invoked by neural_monsters."""
import argparse
import faulthandler
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import skeletal_iqm as sk


def source(directory):
    document = json.loads((directory / 'source.json').read_text())
    arrays = np.load(directory / 'source.npz')
    return document, arrays


def material(texture):
    mat = bpy.data.materials.new('source albedo')
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    image = nodes.new('ShaderNodeTexImage')
    image.image = bpy.data.images.load(str(texture.resolve()))
    shader = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    links.new(image.outputs['Color'], shader.inputs['Base Color'])
    shader.inputs['Roughness'].default_value = .8
    return mat


def studio(points, resolution=1024):
    low, high = points.min(axis=0), points.max(axis=0)
    center, extent = (low+high)/2, float(np.max(high-low))
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device, scene.cycles.samples = 'CPU', 16
    scene.render.resolution_x = scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'Standard'
    scene.world = bpy.data.worlds.new('Studio')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.5, .5, .5, 1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value = .6
    for label, offset, energy in [('key', (2, -1, 3), 1000), ('fill', (1, 2, 1), 500)]:
        light = bpy.data.objects.new(label, bpy.data.lights.new(label, 'AREA'))
        bpy.context.collection.objects.link(light)
        light.location = Vector(center) + Vector(offset)*extent
        light.rotation_euler = (Vector(center)-light.location).to_track_quat('-Z', 'Y').to_euler()
        light.data.energy, light.data.size = energy*(extent/56)**2, extent*1.5
    camera = bpy.data.objects.new('Camera', bpy.data.cameras.new('Camera'))
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type, camera.data.ortho_scale = 'ORTHO', extent*1.35
    return scene, camera, center, extent


def surface(name, points, triangles, texcoords, texture):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(points.tolist(), [], triangles.tolist())
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    uv = mesh.uv_layers.new()
    for j, loop in enumerate(mesh.loops):
        u, v = texcoords[loop.vertex_index]
        uv.data[j].uv = u, 1-v
    mesh.materials.append(material(texture))
    return obj


def capture(directory):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    document, arrays = source(directory)
    frame = document['actor']['reference_frame']
    points = np.concatenate([arrays[f'{i}_points'][frame] for i in range(len(document['surfaces']))])
    for i, descriptor in enumerate(document['surfaces']):
        surface(descriptor['name'], arrays[f'{i}_points'][frame], arrays[f'{i}_tri'], arrays[f'{i}_uv'], directory/descriptor['texture'])
    scene, camera, center, extent = studio(points)
    for label, offset in [('photo', (3, -1.25, .65)), ('side', (0, -3, .25))]:
        camera.location = Vector(center)+Vector(offset)*extent
        camera.rotation_euler = (Vector(center)-camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(directory / f'{label}.png')
        bpy.ops.render.render(write_still=True)


def preview(directory):
    """Render fitted poses produced by the isolated Python fitter, using CPU only."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    arrays = np.load(directory/'preview.npz')
    document = json.loads((directory/'preview.json').read_text())
    # IQM triangles face clockwise; restore Blender's counterclockwise winding.
    obj = surface('fitted creature', arrays['points'][0], arrays['triangles'][:, [0,2,1]], arrays['uv'], directory/'body.png')
    for polygon in obj.data.polygons: polygon.use_smooth = True
    original,authored=source(directory)
    originals=[]
    for i,descriptor in enumerate(original['surfaces']):
        item=surface('original '+descriptor['name'],authored[f'{i}_points'][0],authored[f'{i}_tri'],authored[f'{i}_uv'],directory/descriptor['texture'])
        item.hide_render=True
        originals.append(item)
    scene, camera, center, extent = studio(arrays['points'][0], resolution=768)
    scene.view_settings.exposure=.8
    camera.location = Vector(center)+Vector((3,-1.25,.65))*extent
    camera.rotation_euler = (Vector(center)-camera.location).to_track_quat('-Z','Y').to_euler()
    for points, row in zip(arrays['points'], document['poses']):
        obj.hide_render=False
        for item in originals: item.hide_render=True
        obj.data.vertices.foreach_set('co', points.astype(np.float32).ravel())
        obj.data.update()
        scene.render.filepath = str(directory/row['image'])
        bpy.ops.render.render(write_still=True)
        obj.hide_render=True
        for i,item in enumerate(originals):
            item.hide_render=False
            item.data.vertices.foreach_set('co',authored[f'{i}_points'][row.get('source_frame',row['frame'])].astype(np.float32).ravel())
            item.data.update()
        scene.render.filepath=str(directory/row['source_image'])
        bpy.ops.render.render(write_still=True)


def convert(directory, triangles, preserve_topology=False):
    # Fit outside Blender: its system OpenMP BLAS currently traps in DGESDD.
    faulthandler.enable()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    document, arrays = source(directory)
    bpy.ops.import_scene.gltf(filepath=str(directory / 'model.glb'))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if not meshes: raise ValueError('TRELLIS GLB contains no mesh')
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes: obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    print('Neural conversion: imported geometry', flush=True)
    if len(obj.data.materials) != 1: raise ValueError('Expected a single TRELLIS texture atlas')
    shader = next(n for n in obj.data.materials[0].node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    color = shader.inputs['Base Color'].links
    if len(color) != 1 or color[0].from_node.type != 'TEX_IMAGE': raise ValueError('Missing TRELLIS base color atlas')
    texture = color[0].from_node.image
    # TRELLIS and glTF use Y up and Z forward; Blender imports Z up/-Y forward.
    source_normals=np.array([n.vector[:] for n in obj.data.corner_normals])
    points = np.array([v.co[:] for v in obj.data.vertices])[:, [1, 0, 2]] * [-1, 1, 1]
    reference = np.concatenate([arrays[f'{i}_points'][document['actor']['reference_frame']] for i in range(len(document['surfaces']))])
    low, high = reference.min(axis=0), reference.max(axis=0)
    # A single isotropic scale retains inferred proportions, with source center.
    scale = np.max(high-low) / np.max(np.ptp(points, axis=0))
    points = (points-(points.min(axis=0)+points.max(axis=0))/2)*scale+(low+high)/2
    obj.data.vertices.foreach_set('co', points.astype(np.float32).ravel())
    obj.data.update()
    print('Neural conversion: aligned geometry', flush=True)
    if obj.data.has_custom_normals and not preserve_topology:
        obj.data.normals_split_custom_set([(0., 0., 0.)]*len(obj.data.loops))
    # glTF duplicates vertices at UV seams. Decimating those disconnected
    # borders independently opens cracks through faces and armor. UVs live on
    # corners in Blender, so welding positions preserves the texture mapping.
    before_weld = len(obj.data.vertices)
    if not preserve_topology:
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.remove_doubles(threshold=.0001)
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode='OBJECT')
    welded_vertices = before_weld - len(obj.data.vertices)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.data.calc_loop_triangles()
    if preserve_topology:
        if len(obj.data.loop_triangles)>triangles:raise ValueError('Preserved source exceeds triangle budget; re-export offline')
        obj.data.normals_split_custom_set((source_normals[:,[1,0,2]]*[-1,1,1]).tolist())
    if len(obj.data.loop_triangles)>triangles:
        modifier = obj.modifiers.new('Game surface budget', 'DECIMATE')
        modifier.ratio, modifier.use_collapse_triangulate = triangles/len(obj.data.loop_triangles), True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    print('Neural conversion: decimated geometry', flush=True)
    mesh = obj.data
    mesh.calc_loop_triangles()
    uv = mesh.uv_layers.active.data
    geometry, faces, surfaces, lookup = {k: [] for k in (0, 1, 2)}, [], [], {}
    fv = ft = 0
    episode = document['actor']['source'].split('/')[1]
    slug=document['actor']['slug']
    material_name = f'models/neural/{slug}/body' if document['actor'].get('kind')=='character' else f'models/neural/{episode}_{slug}/body'
    def finish():
        nonlocal fv, ft, lookup
        if len(faces)==ft: return
        surfaces.append((f'body_{len(surfaces)}', material_name, fv, len(geometry[0])-fv, ft, len(faces)-ft))
        fv, ft, lookup = len(geometry[0]), len(faces), {}
    for tri in mesh.loop_triangles:
        if len(lookup)+3>990 or len(faces)-ft>=1900: finish()
        face = []
        for loop in tri.loops:
            index = mesh.loops[loop].vertex_index
            texcoord, normal = uv[loop].uv[:], mesh.corner_normals[loop].vector[:]
            key = (index, *texcoord, *normal)
            if key not in lookup:
                lookup[key]=len(geometry[0])
                geometry[0].append(mesh.vertices[index].co[:])
                geometry[1].append((texcoord[0], 1-texcoord[1]))
                geometry[2].append(normal)
            face.append(lookup[key])
        faces.append([face[0], face[2], face[1]])
    finish()
    print('Neural conversion: split geometry; fitting performance', flush=True)
    np.savez_compressed(directory/'geometry.npz', **{str(k): np.array(v) for k,v in geometry.items()}, triangles=np.asarray(faces))
    texture.filepath_raw = str(directory / 'body.png')
    texture.file_format = 'PNG'
    # Image.save may copy a packed WebP buffer verbatim despite the new suffix.
    scene=bpy.context.scene
    scene.view_settings.view_transform='Standard'
    scene.render.image_settings.file_format='PNG'
    scene.render.image_settings.color_mode='RGBA'
    scene.render.image_settings.color_depth='8'
    texture.save_render(str(directory/'body.png'),scene=scene)
    if (directory/'body.png').read_bytes()[:8]!=b'\x89PNG\r\n\x1a\n': raise ValueError('Atlas export is not PNG')
    report = dict(surfaces=surfaces, triangles=len(faces), texture=list(texture.size), alignment_scale=float(scale))
    import hashlib
    report['topology'] = dict(method=('Preserve generated topology, corner UVs and rotated normals; no weld or decimation' if preserve_topology else 'Weld coincident glTF UV seams before decimation; preserve corner UVs and orient connected faces'),
        weld_distance=.0001, welded_vertices=welded_vertices,
        source_glb_sha256=hashlib.sha256((directory/'model.glb').read_bytes()).hexdigest())
    report['topology']['preserve_topology']=preserve_topology
    (directory / 'geometry.json').write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', choices=('capture', 'convert', 'preview'), required=True)
    parser.add_argument('--actor', type=Path, required=True)
    parser.add_argument('--triangles', type=int, default=36000)
    parser.add_argument('--preserve-topology', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if args.stage == 'capture': capture(args.actor)
    elif args.stage == 'preview': preview(args.actor)
    else: convert(args.actor, args.triangles,args.preserve_topology)
