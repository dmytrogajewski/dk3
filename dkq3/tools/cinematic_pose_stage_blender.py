# SPDX-License-Identifier: GPL-2.0-or-later
"""Blender-only renderer for an explicit matched pose bundle."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector
import numpy as np


def mesh_object(name: str, points: np.ndarray, triangles: np.ndarray, offset: tuple[float,float,float], color: tuple[float,float,float,float]):
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(points.tolist(),[],triangles.tolist())
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location=offset
    material=bpy.data.materials.new(name+"-mat")
    material.diffuse_color=color
    material.use_nodes=True
    material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value=color
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth=True
    return obj


def skeleton(name: str, names: np.ndarray, parents: np.ndarray, points: np.ndarray, offset: Vector, color: tuple[float,float,float,float]):
    curve=bpy.data.curves.new(name,"CURVE")
    curve.dimensions="3D";curve.bevel_depth=.10;curve.bevel_resolution=2
    for j,parent in enumerate(parents):
        if parent<0:
            continue
        spline=curve.splines.new("POLY");spline.points.add(1)
        for point,position in zip(spline.points,(points[parent],points[j])):
            point.co=(*position,1.)
    obj=bpy.data.objects.new(name,curve);bpy.context.scene.collection.objects.link(obj)
    obj.location=offset
    obj.show_in_front=True
    material=bpy.data.materials.new(name+"-mat");material.diffuse_color=color;curve.materials.append(material)
    return obj


def run(source: Path, output: Path) -> None:
    if source.stat().st_size>64*1024*1024:
        raise ValueError("pose bundle exceeds 64 MiB")
    with np.load(source,allow_pickle=False) as bundle:
        data={name:bundle[name] for name in bundle.files}
    for kind in ("original","candidate"):
        points=data[kind+"_points"];triangles=data[kind+"_triangles"]
        if points.ndim!=2 or points.shape[1]!=3 or not 3<=len(points)<=250000 or triangles.ndim!=2 or triangles.shape[1]!=3 or not 1<=len(triangles)<=250000 or not np.isfinite(points).all() or triangles.min()<0 or triangles.max()>=len(points):
            raise ValueError("invalid bounded pose bundle")
    for obj in tuple(bpy.data.objects):
        bpy.data.objects.remove(obj,do_unlink=True)
    original=Vector((0.,-35.,0.));candidate=Vector((0.,35.,0.))
    mesh_object("original MD3 frame",data["original_points"],data["original_triangles"],original,(.36,.55,.77,1))
    mesh_object("posed IQM body",data["candidate_points"],data["candidate_triangles"],candidate,(.8,.52,.32,1))
    for kind,offset,color in (("original",original,(.04,.18,.45,1)),("candidate",candidate,(.48,.16,.02,1))):
        skeleton(kind+" observed joints",data[kind+"_names"],data[kind+"_parents"],data[kind+"_bones"],offset,color)
    scene=bpy.context.scene;scene.render.engine="CYCLES";scene.cycles.device="CPU";scene.cycles.samples=8
    scene.render.resolution_x=1600;scene.render.resolution_y=900;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG"
    scene.world.use_nodes=True
    scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value=(.42,.42,.42,1)
    scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value=.8
    scene.view_settings.view_transform="Standard"
    floor=bpy.data.meshes.new("floor");floor.from_pydata([(-40,-75,-25),(-40,75,-25),(40,75,-25),(40,-75,-25)],[],[(0,1,2),(0,2,3)])
    floor_obj=bpy.data.objects.new("reference floor",floor);scene.collection.objects.link(floor_obj)
    light=bpy.data.lights.new("review light","AREA");light.energy=12000;light.shape="DISK";light.size=80
    lamp=bpy.data.objects.new("review light",light);scene.collection.objects.link(lamp);lamp.location=(60,-20,75)
    lamp.rotation_euler=(Vector((0,0,0))-lamp.location).to_track_quat("-Z","Y").to_euler()
    fill=bpy.data.lights.new("review fill","AREA");fill.energy=7000;fill.shape="DISK";fill.size=100
    fill_obj=bpy.data.objects.new("review fill",fill);scene.collection.objects.link(fill_obj);fill_obj.location=(35,60,45)
    fill_obj.rotation_euler=(Vector((0,0,0))-fill_obj.location).to_track_quat("-Z","Y").to_euler()
    camera_data=bpy.data.cameras.new("review camera");camera_data.type="ORTHO";camera_data.ortho_scale=115
    camera=bpy.data.objects.new("review camera",camera_data);scene.collection.objects.link(camera)
    camera.location=(135,-75,35);camera.rotation_euler=(Vector((0,0,0))-camera.location).to_track_quat("-Z","Y").to_euler();scene.camera=camera
    scene.render.filepath=str(output/"pose-stage.png")
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output/"pose-stage.blend"))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    run(args.input.resolve(),args.out.resolve())
