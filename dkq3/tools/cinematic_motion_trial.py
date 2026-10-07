#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Prepare an isolated authored-motion trial from a local captured manifest.

This does not alter the canonical manifest or package/install an unreviewed
character. Captured clips not named on the command line remain unchanged.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import yaml

import animation_manifest as schema
import animation_motion as motion
from animation_author import local


def prepare(base: Path, selections: list[str], output: Path) -> dict:
    if output.exists():
        raise schema.Error("trial manifest output must be fresh", "ANIM_INVALID_PATH", str(output))
    source=schema.validate(schema.load(base))
    root=base.resolve().parent
    document=copy.deepcopy(source)
    characters={row["character"]:row for row in document["characters"]}
    for character in document["characters"]:
        character["iqm"]=str(local(root,character["iqm"]))
        for clip in character["clips"].values():
            for field in ("motion","retarget"):
                if isinstance(clip.get(field),str):clip[field]=str(local(root,clip[field]))
    changed={}
    for selection in selections:
        if "=" not in selection or "." not in selection.split("=",1)[0]:
            raise schema.Error("selection must be character.clip=/absolute/motion.npz", "ANIM_INVALID_PATH", selection)
        identity,value=selection.split("=",1)
        character_name,clip_name=identity.split(".",1)
        if identity in changed or character_name not in characters or clip_name not in characters[character_name]["clips"]:
            raise schema.Error("duplicate or unknown authored clip", "ANIM_DUPLICATE_CLIP", identity)
        path=Path(value).resolve()
        if not path.is_file() or path.stat().st_size>32*1024*1024:
            raise schema.Error("authored motion missing or exceeds 32 MiB", "ANIM_INVALID_PATH", value)
        authored=motion.read(path)
        if authored.metadata.get("kind")!="authored_cinematic":
            raise schema.Error("selected motion is not independently authored", "ANIM_INVALID_SOURCE", identity)
        clip=characters[character_name]["clips"][clip_name]
        start,end=clip["target_frames"]
        if len(authored.world)!=end-start+1 or abs(authored.fps-schema.effective_rate(clip))>1e-6:
            raise schema.Error("authored frame count/rate differs from target", "ANIM_INVALID_RANGE", identity)
        clip["motion"]=str(path)
        for field in ("retarget","source_fidelity","prop_contacts","input_frames","solve_contact_root","contact_floor"):
            clip.pop(field,None)
        clip["solve_contacts"]=False
        # This is an isolated rig/motion trial. Captured prop observations are
        # unavailable in an authored NPZ; inherit the frozen rig's prop track
        # until the scene's hand/prop acting is authored separately.
        inherited=[]
        for name,policy in clip.get("props",{}).items():
            if policy.get("mode")=="captured":
                clip["props"][name]={"mode":"inherit"}
                inherited.append(name)
        changed[identity]=dict(motion_sha256=schema.sha(path),frames=len(authored.world),
                               inherited_props=inherited)
    if not changed:
        raise schema.Error("at least one authored clip required", "ANIM_INVALID_RANGE")
    schema.validate(document)
    schema.write_if_changed(output,yaml.safe_dump(document,sort_keys=False).encode("utf-8"))
    return dict(version=1,base_manifest_sha256=schema.sha(base),trial_manifest_sha256=schema.sha(output),
                clips=changed,scope="local trial only; no artistic acceptance or package admission")


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-manifest",type=Path,required=True)
    parser.add_argument("--clip-motion",action="append",required=True,
                        help="character.clip=/absolute/path/to/motion.npz")
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args()
    try:
        print(json.dumps(prepare(args.base_manifest,args.clip_motion,args.out),indent=2))
    except (schema.Error,OSError,ValueError,KeyError) as error:
        parser.exit(1,f"cinematic motion trial: {error}\n")


if __name__=="__main__":main()
