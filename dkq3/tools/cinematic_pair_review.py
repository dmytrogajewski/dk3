#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Pair native original/IQM cinematic captures at the same shot and game time.

This is evidence for an artist, not an automatic aesthetic acceptance test.
Both inputs are read-only recording directories made by animation_preview.py.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
from pathlib import Path
import re

from PIL import Image


FRAME = re.compile(r"shot-(\d{3})-(\d{8})\.jpg\Z")
MAX_BYTES = 100 * 1024 * 1024


class ReviewError(ValueError):
    pass


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def recording(directory: Path, expected: str) -> tuple[dict, dict[int, list[tuple[int, Path]]]]:
    source = directory / "recording.json"
    if not source.is_file() or source.stat().st_size > MAX_BYTES:
        raise ReviewError(f"missing or oversized native recording: {source}")
    data = json.loads(source.read_text(encoding="utf-8"))
    presentation=data.get("presentation")
    admitted=(expected=="legacy" and presentation in ("legacy","fallback")) or presentation==expected
    if data.get("passed") is not True or not admitted:
        raise ReviewError(f"{source}: expected a passed {expected} recording")
    if presentation=="fallback":
        diagnostics="\n".join(row.get("presentation","") for row in data.get("performances",[]))
        if "dk3 skeletal presentation:" in diagnostics or "dk3 presentation:" not in diagnostics:
            raise ReviewError(f"{source}: fallback did not prove original model rendering")
    frames: dict[int, list[tuple[int, Path]]] = {}
    for path in directory.iterdir():
        match = FRAME.fullmatch(path.name)
        if match and path.is_file():
            if path.stat().st_size > MAX_BYTES:
                raise ReviewError(f"oversized capture: {path}")
            frames.setdefault(int(match[1]), []).append((int(match[2]), path))
    for values in frames.values():
        values.sort()
        if len({time for time, _ in values}) != len(values):
            raise ReviewError(f"duplicate capture timestamp in {directory}")
    if set(frames) != set(data.get("shots", [])):
        raise ReviewError(f"{directory}: captures do not cover recorded shots")
    return data, frames


def pair_frames(original: dict, candidate: dict, tolerance_ms: int) -> list[tuple[int, int, Path, int, Path]]:
    """One-to-one chronological pairs; never compare different shots."""
    if tolerance_ms < 0 or tolerance_ms > 1000:
        raise ReviewError("time tolerance must be 0..1000 ms")
    result = []
    for shot in sorted(original):
        if shot not in candidate:
            raise ReviewError(f"candidate missing shot {shot}")
        if len(original[shot]) != len(candidate[shot]):
            raise ReviewError(f"shot {shot}: capture counts differ")
        for (reference_time, reference), (candidate_time, image) in zip(original[shot],candidate[shot]):
            if abs(candidate_time-reference_time)>tolerance_ms:
                raise ReviewError(f"no candidate capture for shot {shot}, time {reference_time} ms")
            result.append((shot, reference_time, reference, candidate_time, image))
    return result


def performance_at(data: dict, shot: int, now: int) -> dict:
    items = [row for row in data.get("performances", []) if row.get("shot") == shot]
    if not items:
        return {}
    row = min(items, key=lambda item: abs(item.get("now", -10**12) - now))
    return {"now": row["now"], "actors": row.get("actors", ""),
            "presentation": row.get("presentation", "")}


def build(original_dir: Path, candidate_dir: Path, output_dir: Path, tolerance_ms: int = 250) -> dict:
    original_dir = original_dir.resolve()
    candidate_dir = candidate_dir.resolve()
    output_dir = output_dir.resolve()
    if output_dir.exists() and any(output_dir.iterdir()):
        raise ReviewError(f"output must be fresh: {output_dir}")
    if output_dir == original_dir or output_dir == candidate_dir or original_dir in output_dir.parents or candidate_dir in output_dir.parents:
        raise ReviewError("review output must not overwrite or nest inside a recording")
    old, old_frames = recording(original_dir, "legacy")
    new, new_frames = recording(candidate_dir, "skeletal")
    for field in ("identity", "scene", "map", "shots"):
        if old.get(field) != new.get(field):
            raise ReviewError(f"recording {field} differs")
    if old.get("excluded_packages") is None:
        raise ReviewError("original recording lacks optional-package exclusion evidence")
    matched = pair_frames(old_frames, new_frames, tolerance_ms)
    rows = []
    for shot, old_time, old_path, new_time, new_path in matched:
        with Image.open(old_path) as left, Image.open(new_path) as right:
            if left.size != right.size:
                raise ReviewError(f"capture sizes differ at shot {shot}, time {old_time}")
            size = left.size
        rows.append(dict(shot=shot,original_ms=old_time,candidate_ms=new_time,
                         difference_ms=new_time-old_time,
                         original=old_path.as_uri(),candidate=new_path.as_uri(),
                         original_sha256=digest(old_path),candidate_sha256=digest(new_path),
                         dimensions=list(size),original_performance=performance_at(old,shot,old_time),
                         candidate_performance=performance_at(new,shot,new_time)))
    output_dir.mkdir(parents=True)
    report = dict(schema=1,decision="requires_visual_review",scene=old["scene"],map=old["map"],
                  runtime_identity=old["identity"],original_recording=str(original_dir),
                  candidate_recording=str(candidate_dir),
                  original_recording_sha256=digest(original_dir/"recording.json"),
                  candidate_recording_sha256=digest(candidate_dir/"recording.json"),
                  original_presentation=old["presentation"],original_overlays=old.get("overlays",{}),
                  original_excluded_packages=old["excluded_packages"],
                  candidate_overlays=new.get("overlays",{}),tolerance_ms=tolerance_ms,
                  shot_count=len(old_frames),frame_count=len(rows),frames=rows)
    (output_dir/"review.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    payload=json.dumps([{k:r[k] for k in ("shot","original_ms","candidate_ms","original","candidate","original_performance","candidate_performance")} for r in rows]).replace("<", "\\u003c")
    title=html.escape(f"{old['scene']} — original / skeletal")
    page=f"""<!doctype html><meta charset="utf-8"><title>{title}</title>
<style>body{{font:15px system-ui;background:#17191b;color:#eee;margin:1rem}}button,input{{margin:.5rem}}.views{{display:grid;grid-template-columns:1fr 1fr;gap:1rem}}img{{width:100%;object-fit:contain}}pre{{white-space:pre-wrap;max-height:14rem;overflow:auto;background:#24282c;padding:1rem}}.head{{display:flex;align-items:center;gap:1rem}}</style>
<h1>{title}</h1><p>Read-only evidence. A passed runtime capture does not approve the character or acting.</p>
<div class="head"><button id="prev">◀</button><input id="index" type="range" min="0" max="{len(rows)-1}" value="0"><button id="next">▶</button><strong id="label"></strong></div>
<div class="views"><div><h2>Original</h2><img id="original"><pre id="originalData"></pre></div><div><h2>Skeletal candidate</h2><img id="candidate"><pre id="candidateData"></pre></div></div>
<script>const rows={payload};const index=document.getElementById('index');function show(){{const row=rows[+index.value];document.getElementById('label').textContent=`shot ${{row.shot}} · original ${{row.original_ms}} ms · candidate ${{row.candidate_ms}} ms`;for(const side of ['original','candidate']){{document.getElementById(side).src=row[side];document.getElementById(side+'Data').textContent=JSON.stringify(row[side+'_performance'],null,2)}}}}index.oninput=show;document.getElementById('prev').onclick=()=>{{index.value=Math.max(0,+index.value-1);show()}};document.getElementById('next').onclick=()=>{{index.value=Math.min(rows.length-1,+index.value+1);show()}};document.onkeydown=e=>{{if(e.key==='ArrowLeft')document.getElementById('prev').click();if(e.key==='ArrowRight')document.getElementById('next').click()}};show()</script>"""
    (output_dir/"index.html").write_text(page,encoding="utf-8")
    return report


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original",type=Path,required=True)
    parser.add_argument("--candidate",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--tolerance-ms",type=int,default=250)
    args=parser.parse_args()
    try:
        result=build(args.original,args.candidate,args.out,args.tolerance_ms)
    except (ReviewError,OSError,ValueError) as error:
        parser.exit(1,f"cinematic review: {error}\n")
    print(f"{result['frame_count']} paired frames across {result['shot_count']} shots; visual review required: {args.out/'index.html'}")


if __name__=="__main__":main()
