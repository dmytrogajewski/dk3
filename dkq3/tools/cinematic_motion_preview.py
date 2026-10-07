#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Render several frames of an authored IQM motion as a Blender contact sheet."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess

import numpy as np

import animation_manifest as schema
import animation_motion as motion
from cinematic_pair_review import ReviewError
import skeletal_iqm as sk


def build(rig: Path, authored_path: Path, output: Path, frames: list[int], blender: str = "blender") -> dict:
    if output.exists() and any(output.iterdir()):
        raise ReviewError(f"preview output must be fresh: {output}")
    if rig.stat().st_size > 32 * 1024 * 1024 or authored_path.stat().st_size > 32 * 1024 * 1024:
        raise ReviewError("rig or motion exceeds 32 MiB")
    model = sk.read(rig.read_bytes())
    authored = motion.read(authored_path)
    if authored.names != model.names or authored.parents != model.parents or not np.allclose(authored.rest, sk.matrices(model.bind,model.parents),atol=1e-4):
        raise ReviewError("authored motion does not belong to this rig")
    if len(frames) != 4 or len(set(frames)) != 4 or any(not 0 <= f < len(authored.world) for f in frames):
        raise ReviewError("four distinct in-range frames required")
    selected=[];faces=[]
    for name,_,first,count,start,length in model.meshes:
        if name.startswith("prop_"):
            continue
        selected.extend(range(first,first+count))
        faces.extend(model.triangles[start:start+length])
    if not 100<=len(selected)<=250000 or len(faces)>250000:
        raise ReviewError("bounded body mesh required")
    ids=np.asarray(selected,dtype=np.int64)
    lookup=np.full(len(model.arrays[0]),-1,dtype=np.int32)
    lookup[ids]=np.arange(len(ids),dtype=np.int32)
    triangles=lookup[np.asarray(faces,dtype=np.int64)]
    if np.any(triangles<0):
        raise ReviewError("body triangle references prop vertex")
    channels=sk.channels(authored.world[frames],model.parents)
    points=sk.skin(model,channels)[:,ids]
    output.mkdir(parents=True)
    bundle=output/"poses.npz"
    np.savez_compressed(bundle,points=points,triangles=triangles,frames=np.asarray(frames),
                        bones=authored.world[frames,:,:3,3],names=np.asarray(model.names),
                        parents=np.asarray(model.parents))
    script=Path(__file__).with_name("cinematic_motion_preview_blender.py")
    command=[blender,"--background","--factory-startup","--threads","4","--python-exit-code","1",
             "--python",str(script),"--","--input",str(bundle),"--out",str(output)]
    with (output/"blender.log").open("w",encoding="utf-8") as log:
        subprocess.run(command,check=True,timeout=180,stdout=log,stderr=subprocess.STDOUT)
    preview=output/"motion-poses.png"
    if not preview.is_file():
        raise ReviewError("Blender did not render motion-poses.png")
    report=dict(version=1,frames=frames,rig_sha256=schema.sha(rig),motion_sha256=schema.sha(authored_path),
                bundle_sha256=schema.sha(bundle),preview_sha256=schema.sha(preview),
                scope="authored motion pose contact sheet; model and acting require visual review")
    schema.write_json(output/"preview.json",report)
    return report


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rig",type=Path,required=True)
    parser.add_argument("--motion",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--frames",type=int,nargs=4,required=True)
    parser.add_argument("--blender",default="blender")
    args=parser.parse_args()
    try:
        print(json.dumps(build(args.rig,args.motion,args.out,args.frames,args.blender),indent=2))
    except (ReviewError,OSError,ValueError,subprocess.CalledProcessError,subprocess.TimeoutExpired) as error:
        parser.exit(1,f"cinematic motion preview: {error}\n")


if __name__ == "__main__":
    main()
