#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Close fragmented neural surfaces, transfer the existing rig, and rebake albedo.

Blender CPU tooling. Original bones, source intervals and attachment names persist.
"""
import argparse,json,hashlib,sys,subprocess
from pathlib import Path
import bpy,bmesh,numpy as np
from mathutils.kdtree import KDTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
import skeletal_iqm as sk
import dkimg


def close(source,output,voxel=.1,thickness=.14,triangles=36000,texture=None,geometry=None,geometry_source_sha256=None,partition_orientations=False,seal_radius=0.,fill_volumes=None):
 if source.name in ('prisoner','prisonerb'):raise ValueError('Protected prisoners cannot be remeshed')
 if not (.02<=voxel<=.2 and .02<=thickness<=.4 and 1000<=triangles<=100000):raise ValueError('Invalid surface closure settings')
 if not 0<=seal_radius<=4.:raise ValueError('Invalid surface sealing radius')
 bpy.ops.wm.read_factory_settings(use_empty=True)
 original_data=(source/'model.iqm').read_bytes();original=sk.read(original_data);points=original.arrays[0]
 restored_geometry=None
 if geometry:
  if hashlib.sha256(original_data).hexdigest()!=geometry_source_sha256:raise ValueError('Restored geometry belongs to another input surface')
  restored_geometry=dict(path=str(geometry),sha256=hashlib.sha256(geometry.read_bytes()).hexdigest(),source_iqm_sha256=geometry_source_sha256)
 height=float(np.ptp(points[:,2]));scale=height/56
 mesh=bpy.data.meshes.new('original surface');mesh.from_pydata(points.tolist(),[],original.triangles[:,[0,2,1]].tolist());mesh.update()
 obj=bpy.data.objects.new('source',mesh);bpy.context.collection.objects.link(obj)
 uv=mesh.uv_layers.new(name='atlas')
 for i,loop in enumerate(mesh.loops):u,v=original.arrays[1][loop.vertex_index];uv.data[i].uv=u,1-v
 mat=bpy.data.materials.new('source albedo');mat.use_nodes=True;mesh.materials.append(mat)
 nodes,links=mat.node_tree.nodes,mat.node_tree.links;image=nodes.new('ShaderNodeTexImage')
 texture=texture or (source/'body-before-face.png' if (source/'body-before-face.png').exists() else source/'body.png')
 image.image=bpy.data.images.load(str(texture.resolve()));image.image.colorspace_settings.name='Non-Color'
 source_texture_sha=hashlib.sha256(texture.read_bytes()).hexdigest()
 emission=nodes.new('ShaderNodeEmission');links.new(image.outputs['Color'],emission.inputs['Color']);links.new(emission.outputs[0],next(n for n in nodes if n.type=='OUTPUT_MATERIAL').inputs['Surface'])
 target=obj.copy();target.data=obj.data.copy();target.name='closed surface';bpy.context.collection.objects.link(target);bpy.context.view_layer.objects.active=target
 bpy.ops.object.select_all(action='DESELECT');target.select_set(True)
 if geometry:
  saved=np.load(geometry)
  mesh=bpy.data.meshes.new('restored closed geometry');mesh.from_pydata(saved['points'].tolist(),[],saved['triangles'].tolist());mesh.update();target.data=mesh
 else:
  bm=bmesh.new();bm.from_mesh(target.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001*scale);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(target.data);bm.free()
  solid=target.modifiers.new('Close thin neural shells','SOLIDIFY');solid.thickness=thickness*scale;solid.offset=0;bpy.ops.object.modifier_apply(modifier=solid.name)
  fillers=[]
  if fill_volumes:
   if not seal_radius:raise ValueError('Local anatomy volumes require the signed-distance export')
   for volume in fill_volumes:
    center=np.asarray(volume['center'],float);radii=np.asarray(volume['radii'],float)
    if center.shape!=(3,) or radii.shape!=(3,) or not np.isfinite(center).all() or not np.isfinite(radii).all() or (radii<=0).any():raise ValueError('Invalid local anatomy volume')
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48,ring_count=24,location=center.tolist())
    filler=bpy.context.object;filler.scale=radii.tolist()
    bpy.ops.object.transform_apply(location=True,rotation=False,scale=True)
    filler.hide_render=True;fillers.append(filler)
   bpy.ops.object.select_all(action='DESELECT');target.select_set(True);bpy.context.view_layer.objects.active=target
  if seal_radius:
   # Expanding then contracting the reinitialized signed-distance surface
   # closes tiny tunnels. A watertight thin shell alone can retain thousands
   # of visible pores and deep cracked seams in reconstructed skin/cloth.
   tree=bpy.data.node_groups.new('Seal reconstruction tunnels','GeometryNodeTree')
   tree.interface.new_socket(name='Geometry',in_out='INPUT',socket_type='NodeSocketGeometry')
   tree.interface.new_socket(name='Geometry',in_out='OUTPUT',socket_type='NodeSocketGeometry')
   entry=tree.nodes.new('NodeGroupInput');exit_node=tree.nodes.new('NodeGroupOutput')
   grid=tree.nodes.new('GeometryNodeMeshToSDFGrid');grid.inputs['Voxel Size'].default_value=voxel*scale;grid.inputs['Band Width'].default_value=8
   expand=tree.nodes.new('GeometryNodeSDFGridOffset');expand.inputs['Distance'].default_value=seal_radius*scale
   contract=tree.nodes.new('GeometryNodeSDFGridOffset');contract.inputs['Distance'].default_value=-seal_radius*scale
   surface=tree.nodes.new('GeometryNodeGridToMesh');surface.inputs['Threshold'].default_value=0.
   union_grid=grid.outputs['SDF Grid']
   for filler in fillers:
    info=tree.nodes.new('GeometryNodeObjectInfo');info.inputs['Object'].default_value=filler
    local_grid=tree.nodes.new('GeometryNodeMeshToSDFGrid');local_grid.inputs['Voxel Size'].default_value=voxel*scale;local_grid.inputs['Band Width'].default_value=8
    tree.links.new(info.outputs['Geometry'],local_grid.inputs['Mesh'])
    union=tree.nodes.new('GeometryNodeSDFGridBoolean');union.operation='UNION'
    # UNION uses one multi-input socket; the two separate grid sockets are
    # only available for DIFFERENCE and change availability with operation.
    grids=next(socket for socket in union.inputs if socket.is_multi_input and not socket.is_unavailable)
    tree.links.new(union_grid,grids);tree.links.new(local_grid.outputs['SDF Grid'],grids)
    union_grid=union.outputs['Grid']
   for a,b in [(entry.outputs['Geometry'],grid.inputs['Mesh']),(union_grid,expand.inputs['Grid']),(expand.outputs['Grid'],contract.inputs['Grid']),(contract.outputs['Grid'],surface.inputs['Grid']),(surface.outputs['Mesh'],exit_node.inputs['Geometry'])]:tree.links.new(a,b)
   remesh=target.modifiers.new('Continuous sealed surface','NODES');remesh.node_group=tree
  else:
   remesh=target.modifiers.new('Continuous surface','REMESH');remesh.mode='VOXEL';remesh.voxel_size=voxel*scale;remesh.use_smooth_shade=True
  bpy.ops.object.modifier_apply(modifier=remesh.name)
  for filler in fillers:bpy.data.objects.remove(filler,do_unlink=True)
 print('Closed surface triangles',len(target.data.polygons),flush=True)
 target.data.calc_loop_triangles()
 if len(target.data.loop_triangles)>triangles:
  dec=target.modifiers.new('Runtime surface budget','DECIMATE');dec.ratio=triangles/len(target.data.loop_triangles);dec.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=dec.name)
 bm=bmesh.new();bm.from_mesh(target.data)
 bmesh.ops.dissolve_degenerate(bm,dist=.0001*scale,edges=list(bm.edges))
 bmesh.ops.triangulate(bm,faces=list(bm.faces))
 # Voxel/decimation can leave isolated sub-voxel double-sided specks. They
 # contain no usable surface and xatlas correctly refuses to parameterize
 # them. Remove entire tiny components, rather than punching holes in skin.
 remaining=set(bm.verts);debris=[];micro_components=0
 while remaining:
  seed=remaining.pop();component={seed};pending=[seed]
  while pending:
   for edge in pending.pop().link_edges:
    for vertex in edge.verts:
     if vertex in remaining:remaining.remove(vertex);component.add(vertex);pending.append(vertex)
  coordinates=np.asarray([v.co[:] for v in component])
  component_faces={face for vertex in component for face in vertex.link_faces}
  # Decimation can also leave a pair of coincident opposite triangles. Its
  # long edge may exceed the extent threshold, but it encloses no volume and
  # has no usable 3D surface. Do not send these flat doublets to xatlas.
  if len(component_faces)<=2 or float(np.linalg.norm(np.ptp(coordinates,axis=0)))<2*voxel*scale:
   debris.extend(component);micro_components+=1
 if debris:bmesh.ops.delete(bm,geom=debris,context='VERTS')
 bm.to_mesh(target.data);bm.free()
 # Dense closed cloth/hair contains many handles. A single requested
 # collapse ratio can finish above its requested triangle budget. Enforce
 # the serialized budget on the cleaned triangular mesh before UV seams
 # duplicate vertices; IQM has a 16 MiB file limit.
 target.data.calc_loop_triangles()
 while len(target.data.loop_triangles)>triangles:
  before=len(target.data.loop_triangles)
  dec=target.modifiers.new('Final closed surface budget','DECIMATE')
  dec.ratio=.95*triangles/before;dec.use_collapse_triangulate=True
  bpy.ops.object.modifier_apply(modifier=dec.name)
  target.data.calc_loop_triangles()
  after=len(target.data.loop_triangles)
  print('Final surface budget',before,'->',after,'limit',triangles,flush=True)
  if after>=before:raise ValueError('Closed topology cannot meet the requested runtime triangle budget')
 # Final collapse can create zero-area faces. Repair those edges before
 # exporting single-precision geometry to the atlas producer.
 bm=bmesh.new();bm.from_mesh(target.data)
 bmesh.ops.dissolve_degenerate(bm,dist=.0001*scale,edges=list(bm.edges))
 bmesh.ops.triangulate(bm,faces=list(bm.faces))
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 bm.to_mesh(target.data);bm.free()
 # Parameterize the closed surface with the already pinned external xatlas.
 # Enlarging only its head input gives facial features extra texture density.
 document=json.loads((source/'source.json').read_text())
 if document['actor'].get('kind')=='character':origin=np.zeros(3);projection_scale=1.
 else:
  report=json.loads((source/'conversion.json').read_text())
  projection_scale=height/56
  pelvis=sk.matrices(original.bind,original.parents)[original.names.index('pelvis'),:3,3]
  origin=pelvis-np.asarray(report['landmarks']['torso'][0])*projection_scale
 target.data.calc_loop_triangles();faces_for_uv=list(target.data.loop_triangles)
 head=np.array([np.mean([(target.data.vertices[i].co.z-origin[2])/projection_scale for i in t.vertices])>20. for t in faces_for_uv])
 output.mkdir(parents=True,exist_ok=True)
 uv_input=output/'uv-input.npz';uv_output=output/'uv-atlas.npz'
 np.savez_compressed(uv_input,points=np.asarray([v.co[:] for v in target.data.vertices],dtype='f4'),triangles=np.asarray([t.vertices[:] for t in faces_for_uv],dtype='u4'),head=head)
 runtime=Path(__file__).resolve().parents[2]/'zig-out/neural-tools/runtime/bin/python'
 uv_command=[str(runtime),'-B',str(Path(__file__).with_name('neural_uv.py')),'--source',str(uv_input),'--out',str(uv_output),'--resolution',str(max(image.image.size))]
 if partition_orientations:uv_command.append('--partition-orientations')
 subprocess.run(uv_command,check=True)
 coordinates=np.load(uv_output)['uv']
 if not target.data.uv_layers:target.data.uv_layers.new(name='atlas')
 for t,values in zip(faces_for_uv,coordinates):
  for loop,value in zip(t.loops,values):target.data.uv_layers.active.data[loop].uv=value
 atlas_report=json.loads(uv_output.with_suffix('.json').read_text())
 for p in target.data.polygons:p.use_smooth=True
 size=max(image.image.size);baked=bpy.data.images.new('closed albedo',width=size,height=size,alpha=False);baked.colorspace_settings.name='Non-Color'
 targetmat=bpy.data.materials.new('closed material');targetmat.use_nodes=True;dest=targetmat.node_tree.nodes.new('ShaderNodeTexImage');dest.image=baked;targetmat.node_tree.nodes.active=dest
 target.data.materials.clear();target.data.materials.append(targetmat)
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
 bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);target.select_set(True);bpy.context.view_layer.objects.active=target
 # A sealed patch can lie beyond the old thin-shell bake cage. Include the
 # declared closure radius so newly filled cloth does not receive black misses.
 cage=max(.3,seal_radius*1.5)*scale;distance=max(.7,seal_radius*3)*scale
 bpy.ops.object.bake(type='EMIT',use_selected_to_active=True,cage_extrusion=cage,max_ray_distance=distance,margin=4)
 pixels=np.empty(len(baked.pixels),np.float32);baked.pixels.foreach_get(pixels);pixels=np.rint(np.clip(pixels.reshape(size,size,4)[::-1,:,:3]*255,0,255)).astype('u1')
 # Transfer semantic skin influences from the retained bind surface. No rig fit.
 tree=KDTree(len(points))
 for i,p in enumerate(points):tree.insert(p,i)
 tree.balance();influences=np.zeros((len(target.data.vertices),len(original.names)))
 for i,v in enumerate(target.data.vertices):
  neighbors=tree.find_n(v.co,4);proximity=np.asarray([1/max(d,.015*scale)**2 for _,_,d in neighbors]);proximity/=proximity.sum()
  for factor,(_,old,_) in zip(proximity,neighbors):
   for j,w in zip(original.arrays[4][old],original.arrays[5][old]):influences[i,j]+=factor*w
 idx=np.argsort(-influences,axis=1)[:,:4]
 # Normalize the admitted top-four influences after dropping smaller tails.
 selected=np.take_along_axis(influences,idx,axis=1);weight=np.rint(selected/np.maximum(selected.sum(axis=1,keepdims=True),1e-20)*255).astype(int);weight[:,0]+=255-weight.sum(axis=1)
 # Geometry-only candidates can have fewer than four joints. IQM still needs
 # four influence slots; padding must add zero weights, not duplicate mass.
 if idx.shape[1]<4:
  padding=((0,0),(0,4-idx.shape[1]));idx=np.pad(idx,padding);weight=np.pad(weight,padding)
 data={k:[] for k in (0,1,2,4,5)};faces=[];surfaces=[];cache={};fv=ft=0;mesh=target.data;mesh.calc_loop_triangles();uv=mesh.uv_layers.active.data
 def finish():
  nonlocal fv,ft,cache
  if len(faces)>ft:surfaces.append((f'body_{len(surfaces)}',original.meshes[0][1],fv,len(data[0])-fv,ft,len(faces)-ft))
  fv,ft,cache=len(data[0]),len(faces),{}
 for t in mesh.loop_triangles:
  if len(cache)+3>=990 or len(faces)-ft>=1900:finish()
  face=[]
  for loop in t.loops:
   i=mesh.loops[loop].vertex_index;tex=uv[loop].uv[:];normal=mesh.corner_normals[loop].vector[:];key=(i,*tex,*normal)
   if key not in cache:
    cache[key]=len(data[0]);data[0].append(mesh.vertices[i].co[:]);data[1].append((tex[0],1-tex[1]));data[2].append(normal);data[4].append(idx[i]);data[5].append(weight[i])
   face.append(cache[key])
  faces.append([face[0],face[2],face[1]])
 finish();result=sk.Model({k:np.asarray(a,dtype='u1' if k in (4,5) else float) for k,a in data.items()},surfaces,np.asarray(faces),original.names,original.parents,original.bind,original.frames)
 output.mkdir(parents=True,exist_ok=True);(output/'model.iqm').write_bytes(sk.write(result));(output/'body.png').write_bytes(dkimg.encode_png(pixels))
 receipt=dict(source_iqm_sha256=hashlib.sha256(original_data).hexdigest(),source_texture_sha256=source_texture_sha,tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),output_iqm_sha256=hashlib.sha256((output/'model.iqm').read_bytes()).hexdigest(),output_texture_sha256=hashlib.sha256((output/'body.png').read_bytes()).hexdigest(),method='Fine closed voxel surface; albedo ray bake; transferred semantic skin; unchanged joints and frame channels',atlas=atlas_report,removed_subvoxel_components=micro_components,voxel=voxel,thickness=thickness,triangle_budget=triangles,triangles=len(faces),joints=len(result.names),frames=len(result.frames),bake_cage=dict(extrusion=cage,max_ray_distance=distance))
 (output/'surface-closure.json').write_text(json.dumps(receipt,indent=2)+'\n')
 if restored_geometry:
  receipt['restored_geometry']=restored_geometry
  (output/'surface-closure.json').write_text(json.dumps(receipt,indent=2)+'\n')
 if seal_radius:
  receipt['surface_sealing']=dict(method='Signed-distance dilation followed by erosion; closing subradius tunnels',radius=seal_radius,world_radius=seal_radius*scale)
 if fill_volumes:receipt['local_anatomy_volumes']=dict(method='Signed-distance union of local closed anatomy volumes',volumes=fill_volumes)
 (output/'surface-closure.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('Surface closure exported',output,flush=True)

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--voxel',type=float,default=.1);p.add_argument('--thickness',type=float,default=.14);p.add_argument('--triangles',type=int,default=36000)
 p.add_argument('--texture',type=Path,help='explicit untouched conversion atlas; prevents using an older face bake')
 p.add_argument('--geometry',type=Path,help='resume an explicitly qualified closed geometry checkpoint')
 p.add_argument('--geometry-source-sha256',help='exact input IQM hash for the restored checkpoint')
 p.add_argument('--partition-orientations',action='store_true',help='bound chart searches on dense closed head shells')
 p.add_argument('--seal-radius',type=float,default=0.,help='close subradius tunnels using signed-distance dilation and erosion')
 p.add_argument('--fill-volumes',type=Path,help='reviewed local closed anatomy volumes for missing jaw/neck surfaces')
 a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);close(a.source,a.out,a.voxel,a.thickness,a.triangles,a.texture,a.geometry,a.geometry_source_sha256,a.partition_orientations,a.seal_radius,json.loads(a.fill_volumes.read_text()) if a.fill_volumes else None)
