# SPDX-License-Identifier: GPL-2.0-or-later
"""Blender-only static review render of four authored poses."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector
import numpy as np


def run(source: Path, output: Path) -> None:
    if source.stat().st_size > 64*1024*1024:
        raise ValueError("pose bundle exceeds 64 MiB")
    with np.load(source,allow_pickle=False) as bundle:
        points=bundle["points"];triangles=bundle["triangles"];frames=bundle["frames"]
    if points.ndim!=3 or points.shape[0]!=4 or points.shape[2]!=3 or not 100<=points.shape[1]<=250000:
        raise ValueError("invalid pose count or geometry")
    if triangles.ndim!=2 or triangles.shape[1]!=3 or not 1<=len(triangles)<=250000 or triangles.min()<0 or triangles.max()>=points.shape[1] or not np.isfinite(points).all():
        raise ValueError("invalid bounded triangles or points")
    for obj in tuple(bpy.data.objects):
        bpy.data.objects.remove(obj,do_unlink=True)
    scene=bpy.context.scene
    material=bpy.data.materials.new("neutral performance review")
    material.diffuse_color=(.62,.62,.58,1)
    material.use_nodes=True
    material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value=(.62,.62,.58,1)
    for index,frame in enumerate(frames):
        mesh=bpy.data.meshes.new(f"frame {int(frame)}")
        mesh.from_pydata(points[index].tolist(),[],triangles.tolist());mesh.update()
        obj=bpy.data.objects.new(f"authored frame {int(frame)}",mesh)
        scene.collection.objects.link(obj);obj.location.y=(index-1.5)*35
        mesh.materials.append(material)
        for polygon in mesh.polygons:polygon.use_smooth=True
        font=bpy.data.curves.new(f"label {int(frame)}","FONT")
        font.body=f"frame {int(frame)}"
        label=bpy.data.objects.new(f"label {int(frame)}",font)
        scene.collection.objects.link(label)
        label.location=(0,(index-1.5)*35-9,-29)
        label.rotation_euler=(0,0,1.5707963268)
        font.size=3
    floor=bpy.data.meshes.new("floor")
    floor.from_pydata([(-35,-80,-25),(-35,80,-25),(35,80,-25),(35,-80,-25)],[],[(0,1,2),(0,2,3)])
    floor_obj=bpy.data.objects.new("reference floor",floor);scene.collection.objects.link(floor_obj)
    world=bpy.data.worlds.new("review world");scene.world=world;world.use_nodes=True
    world.node_tree.nodes.get("Background").inputs["Color"].default_value=(.45,.45,.45,1)
    world.node_tree.nodes.get("Background").inputs["Strength"].default_value=.8
    light=bpy.data.lights.new("review light","AREA");light.energy=15000;light.size=80
    lamp=bpy.data.objects.new("review light",light);scene.collection.objects.link(lamp)
    lamp.location=(70,-15,90);lamp.rotation_euler=(Vector((0,0,0))-lamp.location).to_track_quat("-Z","Y").to_euler()
    camera_data=bpy.data.cameras.new("front camera");camera_data.type="ORTHO";camera_data.ortho_scale=170
    camera=bpy.data.objects.new("front camera",camera_data);scene.collection.objects.link(camera)
    camera.location=(180,0,4);camera.rotation_euler=(Vector((0,0,0))-camera.location).to_track_quat("-Z","Y").to_euler()
    scene.camera=camera
    scene.render.engine="CYCLES";scene.cycles.device="CPU";scene.cycles.samples=8
    scene.render.resolution_x=1800;scene.render.resolution_y=750;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG";scene.view_settings.view_transform="Standard"
    scene.render.filepath=str(output/"motion-poses.png")
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output/"motion-poses.blend"))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    run(args.input.resolve(),args.out.resolve())
