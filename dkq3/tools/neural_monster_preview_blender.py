# SPDX-License-Identifier: GPL-2.0-or-later
"""Preview serialized skin positions and normals, including UV seam lighting."""
import argparse
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector
import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parent))
from neural_monster_blender import source,surface,studio


def preview(directory):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    arrays=np.load(directory/'preview.npz')
    document=json.loads((directory/'preview.json').read_text())
    obj=surface('serialized creature',arrays['points'][0],arrays['triangles'][:,[0,2,1]],arrays['uv'],directory/'body.png')
    if any(row[1].endswith('/head') for row in document.get('meshes',[])):
        material=obj.data.materials[0].copy()
        texture=next(n for n in material.node_tree.nodes if n.type=='TEX_IMAGE')
        texture.image=bpy.data.images.load(str((directory/'head.png').resolve()))
        obj.data.materials.append(material)
        for _,label,_,_,first,count in document['meshes']:
            if label.endswith('/head'):
                for polygon in obj.data.polygons[first:first+count]:polygon.material_index=1
    for polygon in obj.data.polygons:polygon.use_smooth=True
    original,authored=source(directory)
    originals=[]
    for i,descriptor in enumerate(original['surfaces']):
        item=surface('original '+descriptor['name'],authored[f'{i}_points'][0],authored[f'{i}_tri'],authored[f'{i}_uv'],directory/descriptor['texture'])
        item.hide_render=True
        originals.append(item)
    scene,camera,center,extent=studio(arrays['points'][0],resolution=768)
    scene.view_settings.exposure=.8
    camera.location=Vector(center)+Vector((3,-1.25,.65))*extent
    camera.rotation_euler=(Vector(center)-camera.location).to_track_quat('-Z','Y').to_euler()
    loop_vertices=np.array([loop.vertex_index for loop in obj.data.loops])
    for points,normals,row in zip(arrays['points'],arrays['normals'],document['poses']):
        # Jumping creatures can leave their neutral-pose camera completely.
        # Compare each generated/source pair at one shared scale and position.
        source_frame=row.get('source_frame',row['frame'])
        pair=np.concatenate([points,*[authored[f'{i}_points'][source_frame]
                                     for i in range(len(originals))]])
        low,high=pair.min(axis=0),pair.max(axis=0)
        pose_center,pose_extent=(low+high)/2,float(np.max(high-low))
        camera.location=Vector(pose_center)+Vector((3,-1.25,.65))*pose_extent
        camera.rotation_euler=(Vector(pose_center)-camera.location).to_track_quat('-Z','Y').to_euler()
        camera.data.ortho_scale=pose_extent*1.35
        for label,offset,energy in [('key',(2,-1,3),1000),('fill',(1,2,1),500)]:
            light=bpy.data.objects[label]
            light.location=Vector(pose_center)+Vector(offset)*pose_extent
            light.rotation_euler=(Vector(pose_center)-light.location).to_track_quat('-Z','Y').to_euler()
            light.data.energy,light.data.size=energy*(pose_extent/56)**2,pose_extent*1.5
        obj.hide_render=False
        for item in originals:item.hide_render=True
        obj.data.vertices.foreach_set('co',points.astype(np.float32).ravel())
        obj.data.update()
        obj.data.normals_split_custom_set(normals[loop_vertices].tolist())
        scene.render.filepath=str(directory/row['image'])
        bpy.ops.render.render(write_still=True)
        obj.hide_render=True
        for i,item in enumerate(originals):
            item.hide_render=False
            item.data.vertices.foreach_set('co',authored[f'{i}_points'][row.get('source_frame',row['frame'])].astype(np.float32).ravel())
            item.data.update()
        scene.render.filepath=str(directory/row['source_image'])
        bpy.ops.render.render(write_still=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    preview(args.actor)
