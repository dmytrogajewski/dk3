#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare a captured original vertex performance with the actual skinned IQM.

This checks geometry after skinning, where plausible bone positions can still
produce a visibly wrong costume. It is a diagnostic, never artistic approval.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

import numpy as np

import animation_manifest as schema
import cinematic_reconstruction as capture
from cinematic_pair_review import ReviewError
from neural_assets import read_md3, source_props, split_hidden_props
import skeletal_iqm as sk


SKELETAL = re.compile(r"dk3 skeletal presentation: entity=(\d+) .*?frame=(\d+) .*?model=([^\s]+)")
PRESENTATION = re.compile(r"dk3 presentation: .*?entity=(\d+) frame=(\d+)")
BANDS = ((-25.,-15.),(-15.,0.),(0.,12.),(12.,20.),(20.,25.),(25.,35.))


def frame_links(recording: dict, source: str) -> list[dict]:
    """Take frame IDs from one native render diagnostic, not an inferred clock."""
    result = []
    for row in recording.get("performances", []):
        text = row.get("presentation", "")
        skeletal = [m for m in SKELETAL.finditer(text) if m[3] == source]
        rendered = list(PRESENTATION.finditer(text))
        if not skeletal or not rendered:
            continue
        # The final presentation diagnostic is the visible draw at this
        # timestamp. It may belong to another actor; do not guess a pairing.
        source_entity, source_frame = map(int, rendered[-1].groups())
        candidate = next((m for m in skeletal if int(m[1]) == source_entity), None)
        if candidate is None:
            continue
        result.append(dict(shot=row["shot"],now=row["now"],source_frame=source_frame,
                           candidate_frame=int(candidate[2]),entity=source_entity))
    return result


def envelope(points: np.ndarray, lo: float, hi: float) -> dict | None:
    selected = points[(points[:,2] >= lo) & (points[:,2] < hi)]
    if len(selected) < 10:
        return None
    return dict(count=len(selected),center=np.median(selected,axis=0).tolist(),
                x=np.percentile(selected[:,0],[5,95]).tolist(),
                y=np.percentile(selected[:,1],[5,95]).tolist())


def compare(source_points: np.ndarray, candidate_points: np.ndarray) -> list[dict]:
    if source_points.ndim != 2 or candidate_points.ndim != 2 or source_points.shape[1] != 3 or candidate_points.shape[1] != 3:
        raise ReviewError("both posed surfaces must contain xyz vertices")
    if not np.isfinite(source_points).all() or not np.isfinite(candidate_points).all():
        raise ReviewError("posed surfaces contain nonfinite vertices")
    results=[]
    for lo,hi in BANDS:
        old,new=envelope(source_points,lo,hi),envelope(candidate_points,lo,hi)
        if old is None or new is None:
            continue
        delta=np.asarray(new["center"])-old["center"]
        widths={axis:float(new[axis][1]-new[axis][0]) / max(.01,old[axis][1]-old[axis][0]) for axis in ("x","y")}
        # Vertex density varies enormously between the original MD3 and the
        # new IQM. Within a fixed height band, median Z mostly measures the
        # tessellation pattern; only compare horizontal silhouette placement.
        results.append(dict(z=[lo,hi],original=old,candidate=new,center_error=float(np.linalg.norm(delta[:2])),
                            center_delta=delta.tolist(),width_ratio=widths))
    return results


def build(profile_path: Path, base_models: Path, candidate_iqm: Path, recording_path: Path,
          output_path: Path, max_center_error: float = 1.5, max_width_ratio: float = 1.35) -> dict:
    if not 0 < max_center_error <= 100 or not 1 < max_width_ratio <= 10:
        raise ReviewError("invalid surface-audit tolerances")
    if output_path.exists():
        raise ReviewError(f"audit output must be fresh: {output_path}")
    profile=schema.load(profile_path)
    source=schema.asset(profile["source_model"],"source model",".dkm")
    with zipfile.ZipFile(base_models) as package:
        blob=capture.archive_read(package,source+".md3",32*1024*1024)
        if hashlib.sha256(blob).hexdigest()!=profile["source_md3_sha256"]:
            raise ReviewError("pinned original MD3 hash differs")
        metadata=json.loads(capture.archive_read(package,source+".json",4*1024*1024))
    surfaces=split_hidden_props(source_props(read_md3(blob)[0],metadata))
    observed=next((item for item in surfaces if item["name"]==profile["surface"] and not item.get("prop")),None)
    if observed is None:
        raise ReviewError("declared original body surface missing")
    if candidate_iqm.stat().st_size>32*1024*1024:
        raise ReviewError("candidate IQM exceeds bounded model size")
    model=sk.read(candidate_iqm.read_bytes())
    # Explicitly omit rigid props and keep all costume/approved-head surfaces.
    selected=np.concatenate([np.arange(first,first+count) for name,material,first,count,_,_ in model.meshes
                             if not name.startswith("prop_")])
    if len(selected) < 100:
        raise ReviewError("candidate contains no body surface")
    if recording_path.stat().st_size>100*1024*1024:
        raise ReviewError("native recording exceeds bounded size")
    recording=json.loads(recording_path.read_text(encoding="utf-8"))
    if recording.get("passed") is not True or recording.get("presentation")!="skeletal":
        raise ReviewError("surface audit needs a passed skeletal native recording")
    links=frame_links(recording,source)
    if not links:
        raise ReviewError("no native render frame links for source model")
    frames=[]
    for link in links:
        a,b=link["source_frame"],link["candidate_frame"]
        if not 0<=a<len(observed["points"]) or not 0<=b<len(model.frames):
            raise ReviewError(f"native frame outside asset: source {a}, candidate {b}")
        posed=sk.skin(model,model.frames[b:b+1])[0,selected]
        bands=compare(observed["points"][a],posed)
        failures=[dict(z=band["z"],center_error=band["center_error"],width_ratio=band["width_ratio"])
                  for band in bands if band["center_error"]>max_center_error or any(v>max_width_ratio or v<1/max_width_ratio for v in band["width_ratio"].values())]
        frames.append(dict(**link,bands=bands,failures=failures))
    result=dict(schema=1,passed=not any(row["failures"] for row in frames),scope="geometry after IQM skinning; visual acting review still required",
                original_model=source,original_md3_sha256=profile["source_md3_sha256"],
                candidate_iqm_sha256=schema.sha(candidate_iqm),native_recording_sha256=schema.sha(recording_path),
                tolerances=dict(center_units=max_center_error,width_ratio=max_width_ratio),
                sampled_frames=len(frames),failed_frames=sum(bool(row["failures"]) for row in frames),frames=frames)
    output_path.parent.mkdir(parents=True,exist_ok=True)
    output_path.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    return result


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile",type=Path,required=True)
    parser.add_argument("--base-models",type=Path,required=True)
    parser.add_argument("--candidate-iqm",type=Path,required=True)
    parser.add_argument("--recording",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--max-center-error",type=float,default=1.5)
    parser.add_argument("--max-width-ratio",type=float,default=1.35)
    args=parser.parse_args()
    try:
        result=build(args.profile,args.base_models,args.candidate_iqm,args.recording,args.out,
                     args.max_center_error,args.max_width_ratio)
    except (ReviewError,OSError,ValueError,KeyError,zipfile.BadZipFile) as error:
        parser.exit(2,f"cinematic surface audit: {error}\n")
    print(f"{result['sampled_frames']} linked native frames; {result['failed_frames']} failed surface envelopes; report: {args.out}")
    if not result["passed"]:
        parser.exit(1)


if __name__=="__main__":main()
