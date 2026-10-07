# SPDX-License-Identifier: GPL-2.0-or-later
"""Bake measured independent face views onto visible surfaces of a closed mesh."""
import hashlib
import inspect
import json
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

import dkimg
import skeletal_iqm as sk
from neural_face_registration import fit, project, validate


def depth_views(obj, views, origin, scale, center, span, directory,geometry_sha256):
    """Render first-surface depth in the exact unwarped projection cameras."""
    paths=[directory/f'face-depth-{i}.exr' for i in range(len(views))]
    key=dict(geometry=geometry_sha256,origin=origin.tolist(),scale=scale,
             center=center.tolist(),span=span,angles=[v['angle'] for v in views],
             renderer=hashlib.sha256(inspect.getsource(depth_views).encode()).hexdigest(),
             blender=bpy.app.version_string)
    receipt=directory/'face-depth-cache.json'
    if receipt.exists():
        prior=json.loads(receipt.read_text())
        if prior['inputs']==key and all(p.exists() and hashlib.sha256(p.read_bytes()).hexdigest()==prior['outputs'].get(p.name) for p in paths):return paths
    material=bpy.data.materials.new('projection depth');material.use_nodes=True
    nodes,links=material.node_tree.nodes,material.node_tree.links
    emission=nodes.new('ShaderNodeEmission')
    links.new(emission.outputs[0],next(n for n in nodes if n.type=='OUTPUT_MATERIAL').inputs['Surface'])
    obj.data.materials.append(material)
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
    scene.cycles.filter_width=.01
    scene.render.resolution_x=scene.render.resolution_y=2048;scene.render.resolution_percentage=100
    scene.render.film_transparent=True
    scene.render.image_settings.file_format='OPEN_EXR';scene.render.image_settings.color_depth='32'
    scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.exr_codec='ZIP'
    scene.render.image_settings.color_management='OVERRIDE'
    scene.render.image_settings.linear_colorspace_settings.name='Non-Color'
    scene.view_layers[0].use_pass_z=True
    compositor=bpy.data.node_groups.new('first-surface depth','CompositorNodeTree')
    scene.compositing_node_group=compositor
    compositor.interface.new_socket(name='Image',in_out='OUTPUT',socket_type='NodeSocketColor')
    layers=compositor.nodes.new('CompositorNodeRLayers');layers.scene=scene
    encoded=compositor.nodes.new('ShaderNodeMath');encoded.operation='MULTIPLY_ADD'
    encoded.inputs[1].default_value=-1/(200*scale)
    compositor.links.new(layers.outputs['Depth'],encoded.inputs[0])
    positive=compositor.nodes.new('ShaderNodeMath');positive.operation='MAXIMUM'
    positive.inputs[1].default_value=0
    compositor.links.new(encoded.outputs[0],positive.inputs[0])
    alpha=compositor.nodes.new('CompositorNodeSetAlpha')
    alpha.inputs['Type'].default_value='Replace Alpha'
    alpha.inputs['Image'].default_value=(0,0,0,1)
    compositor.links.new(positive.outputs[0],alpha.inputs['Alpha'])
    final=compositor.nodes.new('NodeGroupOutput')
    compositor.links.new(alpha.outputs['Image'],final.inputs['Image'])
    camera=bpy.data.objects.new('projection camera',bpy.data.cameras.new('projection camera'))
    bpy.context.collection.objects.link(camera);scene.camera=camera
    camera.data.type='ORTHO';camera.data.ortho_scale=span*scale
    target=origin+center*scale;result=[]
    for i,view in enumerate(views):
        theta=np.deg2rad(view['angle']);direction=np.array([np.cos(theta),np.sin(theta),0.])
        encoded.inputs[2].default_value=1+float(center@direction)/200
        camera.location=target+direction*100*scale
        camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
        path=directory/f'face-depth-{i}.exr';scene.render.filepath=str(path)
        bpy.ops.render.render(write_still=True);result.append(path)
    obj.data.materials.clear()
    scene.compositing_node_group=None
    receipt.write_text(json.dumps(dict(inputs=key,outputs={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in result}),indent=2)+'\n')
    return result


def bake(mesh_path, texture_path, projection, output, plan):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    model = sk.read(mesh_path.read_bytes())
    points = model.arrays[0]
    origin, scale = np.asarray(plan['origin']), plan['scale']
    center, span = np.asarray(plan['camera']['center']), plan['camera']['ortho_scale']
    views = plan.get('projections', [dict(path=projection.name, angle=0,
                                       registration=plan.get('registration', []))])
    if 1 + len(views) + sum(bool(view.get('registration')) for view in views) > 8:
        raise ValueError('Projection requires more than Blender\'s eight UV layers')
    mesh = bpy.data.meshes.new('registered surface')
    mesh.from_pydata(points.tolist(), [], model.triangles[:, [0, 2, 1]].tolist())
    mesh.update()
    obj = bpy.data.objects.new('registered face', mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    mesh.uv_layers.new(name='atlas')
    mesh.color_attributes.new(name='coverage', type='FLOAT_COLOR', domain='CORNER')
    protect_dark=plan.get('protect_dark_hair',False)
    if not isinstance(protect_dark,bool):raise ValueError('Dark hair protection must be boolean')
    if protect_dark:mesh.color_attributes.new(name='eye_region',type='FLOAT_COLOR',domain='CORNER')
    for i in range(len(views)):
        mesh.uv_layers.new(name=f'view{i}')
        if views[i].get('registration'):
            mesh.uv_layers.new(name=f'depth{i}')
        mesh.color_attributes.new(name=f'weight{i}', type='FLOAT_COLOR', domain='CORNER')
    loop_vertices = np.asarray([loop.vertex_index for loop in mesh.loops])
    surface = points[loop_vertices]
    normalized = (surface-origin)/scale
    frontal_view = next((v for v in views if v['angle'] == 0), {})
    eye_anchors = plan.get('eye_centers', [a['target'] for a in (frontal_view.get('registration') or []) if 'eye' in a.get('name', '')])
    eyes = [a[1] for a in eye_anchors]
    orbital_height = center[2] + (float(np.mean(eyes))-.5)*span if eyes else 27.5
    eye_sides=[(a[0]-.5)*span+center[1] for a in eye_anchors]
    eye_low,eye_high=(min(eye_sides)-.25,max(eye_sides)+.25) if eye_sides else (-1.3,1.3)
    orbital=(bool(eyes)&(normalized[:,0]>float(plan.get('orbital_front',1.)))&(normalized[:,1]>eye_low)&(normalized[:,1]<eye_high)&
             (normalized[:,2]>orbital_height-.8)&(normalized[:,2]<orbital_height+.8))
    low, high, width, front = plan['bounds']
    feather = (np.clip((normalized[:, 2]-low)/.7, 0, 1) *
               np.clip((high-normalized[:, 2])/.5, 0, 1) *
               np.clip((width-np.abs(normalized[:, 1]))/.45, 0, 1) *
               np.clip((normalized[:, 0]-front)/.6, 0, 1))
    weights = np.zeros((len(mesh.loops), len(views)))
    coordinates = []
    depth_coordinates=[]
    registrations=[]
    for v, view in enumerate(views):
        theta = np.deg2rad(view['angle'])
        direction = np.array([np.cos(theta), np.sin(theta), 0.])
        right = np.array([-np.sin(theta), np.cos(theta), 0.])
        uv = np.column_stack((.5+((normalized-center)@right)/span,
                              .5+(normalized[:, 2]-center[2])/span))
        depth_coordinates.append(uv.copy())
        if view.get('registration'):
            transform=fit(view['registration'])
            registrations.append(validate(transform))
            uv = project(uv,transform)
        else:
            registrations.append(None)
        coordinates.append(uv)
        facing=model.arrays[2][loop_vertices]@direction
        incidence=np.where(facing>0,np.maximum(np.clip(facing,0,1)**4,.02),0.)
        if plan.get('two_sided_collar'):
            # Retained garment interiors are rendered two-sided by the game.
            # Their inward normals must not keep obsolete skin texels. This
            # exception is bounded below the jaw and still uses full-model
            # depth visibility; facial projection retains its usual rules.
            region=plan['two_sided_collar']
            inside=((normalized[:,2]>=region['bottom_z']) & (normalized[:,2]<=region['top_z']) &
                    (normalized[:,0]>=region['front_x']) & (np.abs(normalized[:,1])<=region['half_width']))
            incidence[inside]=np.maximum(np.abs(facing[inside])**4,.02)
        if plan.get('single_view_visibility') and len(views) == 1:
            # The depth test below owns visibility. This also admits tiny
            # reversed facets in reconstructed wrinkles and overlapping lids.
            incidence[:]=1.
        if view['angle'] == 0:
            # Sculpted eyelids can face down or sideways. The measured front
            # image owns the orbital features, regardless of lid incidence.
            incidence[orbital] = np.maximum(incidence[orbital], .2)
        weights[:,v]=incidence
    if len(views) > 1:
        frontal = next((i for i, v in enumerate(views) if v['angle'] == 0), None)
        if frontal is not None:
            owns_front=orbital&(weights[:,frontal]>0)
            weights[owns_front, frontal] = 50
    sums = weights.sum(axis=1)
    coverage = feather*(sums > 1e-8)
    weights /= np.maximum(sums[:, None], 1e-20)
    for i, loop in enumerate(mesh.loops):
        u, v = model.arrays[1][loop.vertex_index]
        mesh.uv_layers['atlas'].data[i].uv = u, 1-v
        mesh.color_attributes['coverage'].data[i].color = (coverage[i],)*3+(1,)
        if protect_dark:mesh.color_attributes['eye_region'].data[i].color=(float(orbital[i]),)*3+(1,)
        for j in range(len(views)):
            mesh.uv_layers[f'view{j}'].data[i].uv = coordinates[j][i]
            if views[j].get('registration'):
                mesh.uv_layers[f'depth{j}'].data[i].uv = depth_coordinates[j][i]
            mesh.color_attributes[f'weight{j}'].data[i].color = (weights[i, j],)*3+(1,)
    mesh.uv_layers.active_index = 0
    occlusion_receipt=None
    depth_obj=obj;depth_geometry=points[model.triangles]
    if plan.get('occlusion_mesh'):
        occlusion_path=output.parent/plan['occlusion_mesh']
        occluder=sk.read(occlusion_path.read_bytes())
        occlusion_mesh=bpy.data.meshes.new('complete projection surface')
        occlusion_mesh.from_pydata(occluder.arrays[0].tolist(),[],occluder.triangles[:,[0,2,1]].tolist())
        occlusion_mesh.update()
        depth_obj=bpy.data.objects.new('complete projection occluder',occlusion_mesh)
        bpy.context.collection.objects.link(depth_obj)
        obj.hide_render=True
        depth_geometry=occluder.arrays[0][occluder.triangles]
        occlusion_receipt=dict(path=plan['occlusion_mesh'],sha256=hashlib.sha256(occlusion_path.read_bytes()).hexdigest())
    depth_paths=depth_views(depth_obj,views,origin,scale,center,span,output.parent,
                           hashlib.sha256(depth_geometry.tobytes()).hexdigest())
    if depth_obj!=obj:
        bpy.data.objects.remove(depth_obj,do_unlink=True)
        obj.hide_render=False
    material = bpy.data.materials.new('visible registered albedo')
    material.use_nodes = True
    mesh.materials.append(material)
    nodes, links = material.node_tree.nodes, material.node_tree.links

    def image_node(path, uv_name):
        mapping = nodes.new('ShaderNodeUVMap')
        mapping.uv_map = uv_name
        image = nodes.new('ShaderNodeTexImage')
        image.image = bpy.data.images.load(str(path.resolve()))
        image.image.colorspace_settings.name = 'Non-Color'
        image.extension = 'CLIP'
        links.new(mapping.outputs['UV'], image.inputs['Vector'])
        return image

    original = image_node(texture_path, 'atlas')
    def value(color):
        separate=nodes.new('ShaderNodeSeparateXYZ');links.new(color,separate.inputs[0])
        rg=nodes.new('ShaderNodeMath');rg.operation='MAXIMUM'
        links.new(separate.outputs[0],rg.inputs[0]);links.new(separate.outputs[1],rg.inputs[1])
        rgb=nodes.new('ShaderNodeMath');rgb.operation='MAXIMUM'
        links.new(rg.outputs[0],rgb.inputs[0]);links.new(separate.outputs[2],rgb.inputs[1])
        return rgb.outputs[0]
    if protect_dark:
        dark=nodes.new('ShaderNodeMath');dark.operation='LESS_THAN';dark.inputs[1].default_value=.08
        links.new(value(original.outputs['Color']),dark.inputs[0])
        features=nodes.new('ShaderNodeVertexColor');features.layer_name='eye_region'
        outside=nodes.new('ShaderNodeMath');outside.operation='SUBTRACT';outside.inputs[0].default_value=1
        links.new(features.outputs['Color'],outside.inputs[1])
        hair=nodes.new('ShaderNodeMath');hair.operation='MULTIPLY'
        links.new(dark.outputs[0],hair.inputs[0]);links.new(outside.outputs[0],hair.inputs[1])
        skin=nodes.new('ShaderNodeMath');skin.operation='SUBTRACT';skin.inputs[0].default_value=1
        links.new(hair.outputs[0],skin.inputs[1])
    geometry=nodes.new('ShaderNodeNewGeometry')
    relative=nodes.new('ShaderNodeVectorMath');relative.operation='SUBTRACT'
    relative.inputs[1].default_value=origin.tolist()
    links.new(geometry.outputs['Position'],relative.inputs[0])
    combined = None
    weight_sum = None
    hashes = []
    for i, view in enumerate(views):
        path = projection.parent/view['path']
        if path.parent != projection.parent or not path.is_file():
            raise ValueError('Projection must be an admitted sibling image')
        projected = image_node(path, f'view{i}')
        factor = nodes.new('ShaderNodeVertexColor')
        factor.layer_name = f'weight{i}'
        # Key this image's actual backdrop, rather than rejecting all gray
        # pixels: gray beard strands, skull bone and cloth remain useful art.
        # Upper corner samples avoid the shoulders at the bottom of a crop.
        sw,sh=projected.image.size
        samples=np.empty(len(projected.image.pixels),np.float32)
        projected.image.pixels.foreach_get(samples);samples=samples.reshape(sh,sw,4)
        backdrop=np.median([samples[int(sh*y),int(sw*x),:3] for x,y in
                            ((.04,.96),(.96,.96),(.04,.75),(.96,.75))],axis=0)
        distance=nodes.new('ShaderNodeVectorMath');distance.operation='DISTANCE'
        links.new(projected.outputs['Color'],distance.inputs[0])
        distance.inputs[1].default_value=backdrop.tolist()
        foreground=nodes.new('ShaderNodeMapRange');foreground.clamp=True
        foreground.interpolation_type='SMOOTHSTEP'
        foreground.inputs['From Min'].default_value=.045
        foreground.inputs['From Max'].default_value=.085
        links.new(distance.outputs['Value'],foreground.inputs['Value'])
        valid_weight = nodes.new('ShaderNodeMath')
        valid_weight.operation = 'MULTIPLY'
        depth=image_node(depth_paths[i],f'depth{i}' if view.get('registration') else f'view{i}')
        depth.interpolation='Closest'
        theta=np.deg2rad(view['angle'])
        dot=nodes.new('ShaderNodeVectorMath');dot.operation='DOT_PRODUCT'
        dot.inputs[1].default_value=(float(np.cos(theta)),float(np.sin(theta)),0.)
        links.new(relative.outputs[0],dot.inputs[0])
        encoded=nodes.new('ShaderNodeMath');encoded.operation='MULTIPLY_ADD'
        encoded.inputs[1].default_value=1/(200*scale);encoded.inputs[2].default_value=.5
        links.new(dot.outputs['Value'],encoded.inputs[0])
        difference=nodes.new('ShaderNodeMath');difference.operation='SUBTRACT'
        links.new(depth.outputs['Alpha'],difference.inputs[0]);links.new(encoded.outputs[0],difference.inputs[1])
        absolute=nodes.new('ShaderNodeMath');absolute.operation='ABSOLUTE'
        links.new(difference.outputs[0],absolute.inputs[0])
        visible=nodes.new('ShaderNodeMath');visible.operation='LESS_THAN';visible.inputs[1].default_value=.08/200
        links.new(absolute.outputs[0],visible.inputs[0])
        surface_weight=nodes.new('ShaderNodeMath');surface_weight.operation='MULTIPLY'
        links.new(factor.outputs['Color'],surface_weight.inputs[0]);links.new(visible.outputs[0],surface_weight.inputs[1])
        surface_factor=surface_weight.outputs[0]
        if protect_dark:
            allowed=skin.outputs[0]
            if view['angle']==0:
                dark_paint=nodes.new('ShaderNodeMath');dark_paint.operation='LESS_THAN';dark_paint.inputs[1].default_value=.16
                links.new(value(projected.outputs['Color']),dark_paint.inputs[0])
                admits_hair=nodes.new('ShaderNodeMath');admits_hair.operation='MAXIMUM'
                links.new(allowed,admits_hair.inputs[0]);links.new(dark_paint.outputs[0],admits_hair.inputs[1])
                allowed=admits_hair.outputs[0]
            protected=nodes.new('ShaderNodeMath');protected.operation='MULTIPLY'
            links.new(surface_factor,protected.inputs[0]);links.new(allowed,protected.inputs[1])
            surface_factor=protected.outputs[0]
        links.new(surface_factor, valid_weight.inputs[0])
        links.new(foreground.outputs['Result'], valid_weight.inputs[1])
        if weight_sum is None:
            weight_sum = valid_weight.outputs[0]
        else:
            add_weight = nodes.new('ShaderNodeMath')
            add_weight.operation = 'ADD'
            links.new(weight_sum, add_weight.inputs[0])
            links.new(valid_weight.outputs[0], add_weight.inputs[1])
            weight_sum = add_weight.outputs[0]
        weighted = nodes.new('ShaderNodeMixRGB')
        weighted.blend_type = 'MULTIPLY'
        weighted.inputs[0].default_value = 1
        links.new(valid_weight.outputs[0], weighted.inputs[1])
        links.new(projected.outputs['Color'], weighted.inputs[2])
        if combined is None:
            combined = weighted.outputs[0]
        else:
            add = nodes.new('ShaderNodeMixRGB')
            add.blend_type = 'ADD'
            add.inputs[0].default_value = 1
            links.new(combined, add.inputs[1])
            links.new(weighted.outputs[0], add.inputs[2])
            combined = add.outputs[0]
        hashes.append(dict(path=view['path'], sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                           angle=view['angle'],registration=registrations[i],backdrop_color=backdrop.tolist(),
                           backdrop_distance_fade=[.045,.085]))
    # Corner visibility is interpolated across a triangle. Normalize again
    # per texel to prevent dark lines where a view stops covering the surface.
    denominator = nodes.new('ShaderNodeMath')
    denominator.operation = 'MAXIMUM'
    denominator.inputs[1].default_value = .0001
    links.new(weight_sum, denominator.inputs[0])
    inverse = nodes.new('ShaderNodeMath')
    inverse.operation = 'DIVIDE'
    inverse.inputs[0].default_value = 1
    links.new(denominator.outputs[0], inverse.inputs[1])
    normalize = nodes.new('ShaderNodeMixRGB')
    normalize.blend_type = 'MULTIPLY'
    normalize.inputs[0].default_value = 1
    links.new(combined, normalize.inputs[1])
    links.new(inverse.outputs[0], normalize.inputs[2])
    combined = normalize.outputs[0]
    mask = nodes.new('ShaderNodeVertexColor')
    mask.layer_name = 'coverage'
    available = nodes.new('ShaderNodeMath')
    available.operation = 'GREATER_THAN'
    available.inputs[1].default_value = .00001
    links.new(weight_sum, available.inputs[0])
    admitted = nodes.new('ShaderNodeMath')
    admitted.operation = 'MULTIPLY'
    links.new(mask.outputs['Color'], admitted.inputs[0])
    links.new(available.outputs[0], admitted.inputs[1])
    mix = nodes.new('ShaderNodeMixRGB')
    links.new(admitted.outputs[0], mix.inputs[0])
    links.new(original.outputs['Color'], mix.inputs[1])
    links.new(combined, mix.inputs[2])
    emission = nodes.new('ShaderNodeEmission')
    links.new(mix.outputs[0], emission.inputs['Color'])
    links.new(emission.outputs[0], next(n for n in nodes if n.type == 'OUTPUT_MATERIAL').inputs['Surface'])
    width, height = original.image.size
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device, scene.cycles.samples = 'CPU', 1
    destination = nodes.new('ShaderNodeTexImage')
    nodes.active = destination
    # Fresh packed charts reserve padding before normalization. Old atlases
    # receive zero expansion; padding must never cross an unrelated island.
    margin = int(plan.get('atlas_padding', 0))
    if margin < 0 or margin > 4:
        raise ValueError('Registered atlas padding must be between zero and four')

    def raster(name):
        image = bpy.data.images.new(name, width=width, height=height, alpha=False)
        image.colorspace_settings.name = 'Non-Color'
        destination.image = image
        bpy.ops.object.bake(type='EMIT', margin=margin)
        pixels = np.empty(len(image.pixels), np.float32)
        image.pixels.foreach_get(pixels)
        return np.rint(np.clip(pixels.reshape(height, width, 4)[::-1, :, :3]*255, 0, 255)).astype('u1')

    colors = raster('registered face albedo')
    links.new(admitted.outputs[0], emission.inputs['Color'])
    protection = raster('registered face coverage')
    original_pixels = np.empty(len(original.image.pixels), np.float32)
    original.image.pixels.foreach_get(original_pixels)
    retained = np.rint(original_pixels.reshape(height, width, 4)[::-1, :, :3]*255).clip(0, 255).astype('u1')
    uncovered = protection[:, :, 0] == 0
    colors[uncovered] = retained[uncovered]
    output.write_bytes(dkimg.encode_png(colors))
    mask_path = output.with_suffix('.face-mask.png')
    mask_path.write_bytes(dkimg.encode_png(protection))
    receipt = dict(character=plan['character'], mesh_sha256=hashlib.sha256(mesh_path.read_bytes()).hexdigest(),
                   original_texture_sha256=hashlib.sha256(texture_path.read_bytes()).hexdigest(),
                   projection_sha256=hashlib.sha256(projection.read_bytes()).hexdigest(),
                   projections=hashes, reviewed_projection=plan,
                   dark_hair_protection=protect_dark,
                   visibility='Per-texel comparison against 2048-square geometry Z passes in float EXR alpha; .08 normalized-unit tolerance',
                   depth_maps={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in depth_paths},
                   tint_mask_sha256=hashlib.sha256(mask_path.read_bytes()).hexdigest(), margin=margin,
                   method=('Measured inverse feature registration; frontmost-surface incidence blend' if any(p.get('registration') for p in views) else 'Direct mesh-conditioned camera projection; frontmost-surface incidence blend'),
                   atlas_scope='Original bytes preserved exactly outside nonzero UV coverage',
                   uncovered_texels=int(uncovered.sum()), changed_uncovered_texels=0)
    if occlusion_receipt:receipt['complete_model_occlusion']=occlusion_receipt
    output.with_suffix('.face.json').write_text(json.dumps(receipt, indent=2)+'\n')
