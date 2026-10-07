#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build a matched 3D original/IQM pose stage for headless Blender review.

The stage is an authoring reference. It never changes the original assets, the
candidate model, or the game's runtime selection.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

import numpy as np

import animation_manifest as schema
import cinematic_reconstruction as capture
import cinematic_model
from cinematic_surface_audit import frame_links
from cinematic_pair_review import ReviewError
from neural_assets import read_md3, source_props, split_hidden_props
import skeletal_iqm as sk


def body_mesh(model: sk.Model, frame: int) -> tuple[np.ndarray, np.ndarray]:
    selected=[];faces=[]
    for name,_,first,count,start,length in model.meshes:
        if name.startswith("prop_"):
            continue
        selected.extend(range(first,first+count))
        faces.extend(model.triangles[start:start+length])
    ids=np.asarray(selected,dtype=np.int64)
    if len(ids)<100 or len(ids)>250000 or len(faces)>250000:
        raise ReviewError("bounded candidate body mesh required")
    lookup=np.full(len(model.arrays[0]),-1,dtype=np.int32)
    lookup[ids]=np.arange(len(ids),dtype=np.int32)
    triangles=lookup[np.asarray(faces,dtype=np.int64)]
    if np.any(triangles<0):
        raise ReviewError("candidate body face references an omitted prop")
    return sk.skin(model,model.frames[frame:frame+1])[0,ids],triangles


def build(profile_path: Path, base_models: Path, candidate_iqm: Path, recording_path: Path,
          output: Path, shot: int, now: int, blender: str = "blender") -> dict:
    output=output.resolve()
    if output.exists() and any(output.iterdir()):
        raise ReviewError(f"pose-stage output must be fresh: {output}")
    if not 0<=shot<256 or not 0<=now<=3_600_000:
        raise ReviewError("invalid shot or native time")
    profile=schema.load(profile_path)
    source=schema.asset(profile["source_model"],"source model",".dkm")
    with zipfile.ZipFile(base_models) as package:
        blob=capture.archive_read(package,source+".md3",32*1024*1024)
        if hashlib.sha256(blob).hexdigest()!=profile["source_md3_sha256"]:
            raise ReviewError("pinned original MD3 hash differs")
        metadata=json.loads(capture.archive_read(package,source+".json",4*1024*1024))
    surface=next((s for s in split_hidden_props(source_props(read_md3(blob)[0],metadata))
                  if s["name"]==profile["surface"] and not s.get("prop")),None)
    if surface is None:
        raise ReviewError("original reference body missing")
    if candidate_iqm.stat().st_size>32*1024*1024 or recording_path.stat().st_size>100*1024*1024:
        raise ReviewError("candidate model or native recording exceeds size limit")
    model=sk.read(candidate_iqm.read_bytes())
    native=json.loads(recording_path.read_text(encoding="utf-8"))
    if native.get("passed") is not True or native.get("presentation")!="skeletal":
        raise ReviewError("pose stage needs a passed native skeletal preview")
    links=[item for item in frame_links(native,source) if item["shot"]==shot]
    if not links:
        raise ReviewError(f"native recording contains no visible {source} in shot {shot}")
    frame=min(links,key=lambda item:abs(item["now"]-now))
    if abs(frame["now"]-now)>250:
        raise ReviewError(f"nearest native capture is {frame['now']} ms, over 250 ms from request")
    a,b=frame["source_frame"],frame["candidate_frame"]
    if not 0<=a<len(surface["points"]) or not 0<=b<len(model.frames):
        raise ReviewError("native frame ID outside source or candidate")
    observed=cinematic_model.source_motion(surface,profile)
    candidate_points,candidate_triangles=body_mesh(model,b)
    original_points=surface["points"][a]
    original_triangles=surface["tri"]
    if len(original_points)>250000 or len(original_triangles)>250000:
        raise ReviewError("original body exceeds stage limits")
    original_bones=observed.world[a,:,:3,3]
    candidate_bones=sk.matrices(model.frames[b:b+1],model.parents)[0,:,:3,3]
    output.mkdir(parents=True)
    bundle=output/"poses.npz"
    np.savez_compressed(bundle,original_points=original_points,original_triangles=original_triangles,
                        candidate_points=candidate_points,candidate_triangles=candidate_triangles,
                        original_bones=original_bones,original_parents=np.asarray(observed.parents),
                        candidate_bones=candidate_bones,candidate_parents=np.asarray(model.parents),
                        original_names=np.asarray(observed.names),candidate_names=np.asarray(model.names))
    script=Path(__file__).with_name("cinematic_pose_stage_blender.py")
    command=[blender,"--background","--factory-startup","--threads","4","--python-exit-code","1",
             "--python",str(script),"--","--input",str(bundle),"--out",str(output)]
    with (output/"blender.log").open("w",encoding="utf-8") as log:
        subprocess.run(command,check=True,timeout=180,stdout=log,stderr=subprocess.STDOUT)
    blend=output/"pose-stage.blend";preview=output/"pose-stage.png"
    if not blend.is_file() or not preview.is_file():
        raise ReviewError("Blender did not emit both the scene and preview")
    result=dict(schema=1,shot=shot,requested_ms=now,captured_ms=frame["now"],
                original_frame=a,candidate_frame=b,source_model=source,
                original_md3_sha256=profile["source_md3_sha256"],candidate_iqm_sha256=schema.sha(candidate_iqm),
                recording_sha256=schema.sha(recording_path),profile_sha256=schema.sha(profile_path),
                bundle_sha256=schema.sha(bundle),blend_sha256=schema.sha(blend),preview_sha256=schema.sha(preview),
                blender_script_sha256=schema.sha(script),scope="matched posed geometry and joints for authoring; no artistic acceptance")
    (output/"stage.json").write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    return result


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile",type=Path,required=True)
    parser.add_argument("--base-models",type=Path,required=True)
    parser.add_argument("--candidate-iqm",type=Path,required=True)
    parser.add_argument("--recording",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--shot",type=int,required=True)
    parser.add_argument("--time-ms",type=int,required=True)
    parser.add_argument("--blender",default="blender")
    args=parser.parse_args()
    try:
        result=build(args.profile,args.base_models,args.candidate_iqm,args.recording,args.out,
                     args.shot,args.time_ms,args.blender)
    except (ReviewError,OSError,ValueError,KeyError,zipfile.BadZipFile,subprocess.CalledProcessError,subprocess.TimeoutExpired) as error:
        parser.exit(1,f"cinematic pose stage: {error}\n")
    print(json.dumps(result,indent=2))


if __name__=="__main__":main()
