# SPDX-License-Identifier: GPL-2.0-or-later
"""Bake a repaired orthographic face projection onto the existing Hiro atlas.

Run with Blender --python-exit-code 1 --python this_file -- --mesh ...
The input projection is an independently generated local image, not a runtime
dependency. Geometry, UVs, and texture outside the feathered face stay intact.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dkimg
import skeletal_iqm as sk


def bake(mesh_path, texture_path, projection, output, side_projection=None, eye_projection=None, character='hiro'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    model = sk.read(mesh_path.read_bytes())
    mesh = bpy.data.meshes.new('face projection target')
    mesh.from_pydata(model.arrays[0].tolist(), [], model.triangles[:, [0, 2, 1]].tolist())
    mesh.update()
    obj = bpy.data.objects.new('Hiro', mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    atlas, face = mesh.uv_layers.new(name='atlas'), mesh.uv_layers.new(name='face')
    side = mesh.uv_layers.new(name='side') if side_projection else None
    mask = mesh.color_attributes.new(name='face_mask', type='FLOAT_COLOR', domain='CORNER')
    orbit = mesh.color_attributes.new(name='orbit_mask', type='FLOAT_COLOR', domain='CORNER')
    side_mix = mesh.color_attributes.new(name='side_mix', type='FLOAT_COLOR', domain='CORNER')
    # Adding custom-data layers can invalidate earlier Blender RNA handles.
    # Resolve them after allocation, otherwise two-UV bakes write mixed layers.
    atlas, face = mesh.uv_layers['atlas'], mesh.uv_layers['face']
    if side_projection: side = mesh.uv_layers['side']
    mask = mesh.color_attributes['face_mask']
    orbit = mesh.color_attributes['orbit_mask']
    side_mix = mesh.color_attributes['side_mix']
    for i, loop in enumerate(mesh.loops):
        vertex = loop.vertex_index
        x, y, z = model.arrays[0][vertex]
        u, v = model.arrays[1][vertex]
        atlas.data[i].uv = u, 1-v
        # Place the painted eyes in the sockets, below the brow ridge. The
        # generated projection crowds them against the brows; remap only this
        # vertical band, keeping the nose, mouth and forehead registered.
        eye_shift = .42 * max(0., min((z-26.5)/1.15, (28.5-z)/.85)) if eye_projection else 0.
        if character == 'superfly':
            eye_shift = .45 * max(0., min((z-26.8)/1.35, (29.2-z)/1.05))
        elif character == 'usagi':
            eye_shift = .2 * max(0., min((z-25.8)/.8, (27.5-z)/.9))
        face.data[i].uv = .5+y/15, .5+(z+eye_shift-26)/15
        # Dark old brows are facial features, not hair. Replace their texels
        # inside the orbital surface; lateral hanging locks remain excluded.
        orbital = float(np.clip((z-26.8)/.3, 0, 1)*np.clip((29.05-z)/.3, 0, 1)
                        *np.clip((1.55-abs(y))/.12, 0, 1)
                        *np.clip((x-1.6)/.3, 0, 1))
        orbital = orbital if eye_projection else 0.
        orbit.data[i].color = orbital, orbital, orbital, 1
        if side_projection:
            # The reviewed side projection looks from -60 degrees. Mirror its
            # skin onto the opposite cheek, retaining the original hair/UVs.
            side.data[i].uv = .5+(np.sqrt(3)*x/2-abs(y)/2)/15, .5+(z+(eye_shift if character == 'superfly' else 0)-26)/15
            nx, ny, _ = model.arrays[2][vertex]
            # Front projection owns the eyes/nose. Using the mirrored side
            # there would project its occluding hair across the other cheek.
            blend = float(np.clip((abs(ny)-nx*.5)/.45, 0, 1) * np.clip((26-z)/1.2, 0, 1))
            blend = max(blend, float(np.clip((abs(y)-2.1)/.4, 0, 1)*np.clip((1.5-x)/.5, 0, 1)))
            if character == 'superfly': blend = float(np.clip((abs(y)-1.2)/1.3, 0, 1))
            side_mix.data[i].color = blend, blend, blend, 1
            amount = float(np.clip((z-21.5), 0, 1) * np.clip((31.2-z)/.6, 0, 1)
                           * np.clip((x+1.6)/.8, 0, 1) * np.clip((3.4-abs(y))/.4, 0, 1))
        else:
            radius = np.sqrt((y/3.4)**2 + ((z-27.3)/3.65)**2)
            amount = float(np.clip((1-radius)/.16, 0, 1) * np.clip((model.arrays[2][vertex, 0]-.05)/.45, 0, 1))
        mask.data[i].color = amount, amount, amount, 1
        if character != 'hiro':
            # Per-character admission bounds measured on the fixed orthographic
            # previews. Replace dark eye texels too; Hiro's hair-color exclusion
            # is inappropriate for bald/dark-skinned or helmeted faces.
            low, high, width, front = {
                'mikiko': (21.8, 28.5, 2.5, -.2),
                'superfly': (23.4, 33., 3.5, -3.8 if side_projection else -.4),
                'mishima': (18.5, 24.7, 2.1, 2.),
                'usagi': (21., 28.7, 2.6, .0),
            }[character]
            amount = float(np.clip((z-low)/.7, 0, 1)*np.clip((high-z)/.5, 0, 1)
                           *np.clip((width-abs(y))/.45, 0, 1)*np.clip((x-front)/.6, 0, 1))
            mask.data[i].color = amount, amount, amount, 1
    mesh.uv_layers.active_index = 0
    material = bpy.data.materials.new('projected albedo')
    material.use_nodes = True
    mesh.materials.append(material)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    images = []
    projections = [(texture_path, 'atlas'), (projection, 'face')]
    if side_projection: projections.append((side_projection, 'side'))
    if eye_projection: projections.append((eye_projection, 'face'))
    for path, uv_name in projections:
        uv = nodes.new('ShaderNodeUVMap')
        uv.uv_map = uv_name
        image = nodes.new('ShaderNodeTexImage')
        image.image = bpy.data.images.load(str(path.resolve()))
        image.image.colorspace_settings.name = 'Non-Color'
        links.new(uv.outputs['UV'], image.inputs['Vector'])
        images.append(image)
    factor = nodes.new('ShaderNodeVertexColor')
    factor.layer_name = 'face_mask'
    coverage_factor = factor.outputs['Color']
    if side_projection and character == 'hiro':
        # Evaluate hair exclusion per texel. Vertex-sampled color masks bleed
        # skin across thin hair strips whose edges share nearby face vertices.
        channels = nodes.new('ShaderNodeSeparateColor')
        links.new(images[0].outputs['Color'], channels.inputs['Color'])
        skin = nodes.new('ShaderNodeMapRange')
        skin.inputs['From Min'].default_value = .18
        skin.inputs['From Max'].default_value = .28
        links.new(channels.outputs['Red'], skin.inputs['Value'])
        orbital = nodes.new('ShaderNodeVertexColor')
        orbital.layer_name = 'orbit_mask'
        replace_brows = nodes.new('ShaderNodeMath')
        replace_brows.operation = 'MAXIMUM'
        links.new(skin.outputs['Result'], replace_brows.inputs[0])
        links.new(orbital.outputs['Color'], replace_brows.inputs[1])
        coverage = nodes.new('ShaderNodeMath')
        coverage.operation = 'MULTIPLY'
        links.new(factor.outputs['Color'], coverage.inputs[0])
        links.new(replace_brows.outputs[0], coverage.inputs[1])
        coverage_factor = coverage.outputs[0]
    mix = nodes.new('ShaderNodeMixRGB')
    links.new(coverage_factor, mix.inputs[0])
    links.new(images[0].outputs['Color'], mix.inputs[1])
    face_color = images[1].outputs['Color']
    if eye_projection:
        # Admit only the edited orbital area; generated edits outside it (such
        # as unwanted cheek/stubble detail) must not replace the reviewed skin.
        eye_factor = nodes.new('ShaderNodeVertexColor')
        eye_factor.layer_name = 'orbit_mask'
        eye_mix = nodes.new('ShaderNodeMixRGB')
        links.new(eye_factor.outputs['Color'], eye_mix.inputs[0])
        links.new(face_color, eye_mix.inputs[1])
        links.new(images[-1].outputs['Color'], eye_mix.inputs[2])
        face_color = eye_mix.outputs[0]
    if side_projection:
        factor_side = nodes.new('ShaderNodeVertexColor')
        factor_side.layer_name = 'side_mix'
        blend_side = nodes.new('ShaderNodeMixRGB')
        links.new(factor_side.outputs['Color'], blend_side.inputs[0])
        links.new(face_color, blend_side.inputs[1])
        links.new(images[2].outputs['Color'], blend_side.inputs[2])
        face_color = blend_side.outputs[0]
    links.new(face_color, mix.inputs[2])
    emission = nodes.new('ShaderNodeEmission')
    links.new(mix.outputs[0], emission.inputs['Color'])
    links.new(emission.outputs[0], next(n for n in nodes if n.type == 'OUTPUT_MATERIAL').inputs['Surface'])
    # Dense smart-projected face islands lose entire eyes at the older 2K
    # atlas size. Bake the generated detail at 4K without changing the UVs.
    width, height = (max(4096, int(size)) for size in images[0].image.size)
    baked = bpy.data.images.new('repaired face atlas', width=width, height=height, alpha=False)
    baked.colorspace_settings.name = 'Non-Color'
    destination = nodes.new('ShaderNodeTexImage')
    destination.image = baked
    nodes.active = destination
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device, scene.cycles.samples = 'CPU', 1
    bpy.ops.object.bake(type='EMIT', margin=8)
    pixels = np.empty(len(baked.pixels), np.float32)
    baked.pixels.foreach_get(pixels)
    pixels = np.clip(pixels.reshape(height, width, 4)[::-1, :, :3]*255, 0, 255).astype(np.uint8)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(dkimg.encode_png(pixels))
    # Preserve face colors in multiplayer variants using the same UV coverage.
    links.new(coverage_factor, emission.inputs['Color'])
    protected = bpy.data.images.new('face tint protection', width=width, height=height, alpha=False)
    destination.image = protected
    bpy.ops.object.bake(type='EMIT', margin=8)
    coverage = np.empty(len(protected.pixels), np.float32)
    protected.pixels.foreach_get(coverage)
    coverage = np.clip(coverage.reshape(height, width, 4)[::-1, :, :3]*255, 0, 255).astype(np.uint8)
    mask_path = output.with_suffix('.face-mask.png')
    mask_path.write_bytes(dkimg.encode_png(coverage))
    provenance = dict(
        character=character,
        mesh_sha256=hashlib.sha256(mesh_path.read_bytes()).hexdigest(),
        original_texture_sha256=hashlib.sha256(texture_path.read_bytes()).hexdigest(),
        projection_sha256=hashlib.sha256(projection.read_bytes()).hexdigest(),
        tint_mask_sha256=hashlib.sha256(mask_path.read_bytes()).hexdigest(),
        method='Orthographic face projection, anatomical feather mask, baked to existing UVs')
    if side_projection:
        provenance.update(side_projection_sha256=hashlib.sha256(side_projection.read_bytes()).hexdigest(),
                          method='Frontal and mirrored 60-degree side projections, skin and anatomical masks, existing UVs')
    if eye_projection:
        provenance.update(eye_projection_sha256=hashlib.sha256(eye_projection.read_bytes()).hexdigest(),
                          eye_projection_lowering=.42,
                          method='Front/side skin projections, orbital feature replacement with lowered eyes, hair masks, existing UVs')
    output.with_suffix('.face.json').write_text(json.dumps(provenance, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('mesh', 'texture', 'projection', 'out'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--side-projection', type=Path, help='matching -60 degree orthographic face projection')
    parser.add_argument('--eye-projection', type=Path, help='frontal orbital detail with socket-aligned eye remapping')
    parser.add_argument('--character', choices=('hiro', 'mikiko', 'superfly', 'mishima', 'usagi'), default='hiro')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    bake(args.mesh, args.texture, args.projection, args.out, args.side_projection, args.eye_projection, args.character)
