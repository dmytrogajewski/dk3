# SPDX-License-Identifier: GPL-2.0-or-later
"""Render front and side views of an unrigged local GLB for mesh admission."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def run(source: Path, output: Path) -> None:
    if source.stat().st_size>64*1024*1024:
        raise ValueError("candidate GLB exceeds 64 MiB")
    if output.exists() and any(output.iterdir()):
        raise ValueError("review output must be fresh")
    output.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
    subjects=[obj for obj in bpy.context.scene.objects if obj.type=="MESH"]
    if not subjects or len(subjects)>256:
        raise ValueError("bounded candidate mesh required")
    vertices=[obj.matrix_world@Vector(corner) for obj in subjects for corner in obj.bound_box]
    low=Vector(tuple(min(v[k] for v in vertices) for k in range(3)))
    high=Vector(tuple(max(v[k] for v in vertices) for k in range(3)))
    center=(low+high)*.5;extent=max(high-low)
    if not .01<extent<1000:
        raise ValueError("invalid candidate bounds")
    scene=bpy.context.scene
    scene.render.engine="CYCLES";scene.cycles.device="CPU";scene.cycles.samples=16
    scene.render.resolution_x=1200;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG";scene.view_settings.view_transform="Standard"
    world=bpy.data.worlds.new("review world");scene.world=world;world.use_nodes=True
    world.node_tree.nodes.get("Background").inputs["Color"].default_value=(.5,.5,.5,1)
    world.node_tree.nodes.get("Background").inputs["Strength"].default_value=.45
    light=bpy.data.lights.new("review light","AREA");light.energy=50;light.size=3*extent
    lamp=bpy.data.objects.new("review light",light);scene.collection.objects.link(lamp)
    lamp.location=center+Vector((extent,-extent,extent));lamp.rotation_euler=(center-lamp.location).to_track_quat("-Z","Y").to_euler()
    camera_data=bpy.data.cameras.new("review camera");camera_data.type="ORTHO";camera_data.ortho_scale=extent*1.15
    camera=bpy.data.objects.new("review camera",camera_data);scene.collection.objects.link(camera);scene.camera=camera
    for label,direction in (("front",Vector((0,-1,0))),("side",Vector((1,0,0)))):
        camera.location=center+direction*extent*3
        camera.rotation_euler=(center-camera.location).to_track_quat("-Z","Y").to_euler()
        scene.render.filepath=str(output/(label+".png"))
        bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output/"candidate.blend"))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    run(args.source,args.out)
