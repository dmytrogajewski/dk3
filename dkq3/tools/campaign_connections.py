#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Inventory authored campaign connections without inventing portal geometry.

Input is a converted map PK3; output is local, asset-derived JSON. Named starts,
brush bounds and dependencies are evidence, not proof of a continuous seam.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import zipfile

import entities


def vector(value):
    result = [float(part) for part in value.split()]
    if len(result) != 3 or not all(math.isfinite(part) for part in result):
        raise ValueError(f"invalid authored vector: {value!r}")
    return result


def read_map(name, data):
    if len(data) < 144 or struct.unpack_from("<4si", data) != (b"IBSP", 46):
        raise ValueError(f"{name}: invalid converted BSP")
    lumps = []
    for index in range(17):
        offset, length = struct.unpack_from("<ii", data, 8 + index * 8)
        if offset < 0 or length < 0 or offset + length > len(data):
            raise ValueError(f"{name}: invalid BSP lump {index}")
        lumps.append(data[offset:offset + length])
    if len(lumps[7]) % 40 or len(lumps[1]) % 72:
        raise ValueError(f"{name}: invalid model/shader array")
    models = list(struct.iter_unpack("<6f4i", lumps[7]))
    parsed = entities.parse(lumps[0])
    # A cinematic can invoke an otherwise ordinary brush exit through a named
    # control (the opening movie does this). Follow the authored target, not the
    # map's spelling or the absence of a reciprocal corridor.
    cinematic_targets = {entities.value(pairs, 'target').lower()
                         for pairs in parsed if entities.value(pairs, 'cinetrigger')
                         and entities.value(pairs, 'target')}
    starts, exits = [], []
    for index, pairs in enumerate(parsed):
        get = lambda key, default="": entities.value(pairs, key) or default
        classname = get("classname")
        if classname == "info_player_start":
            starts.append(dict(entity=index + 1, targetname=get("targetname"),
                               origin=vector(get("origin", "0 0 0")),
                               angles=vector(get("angles", f"0 {get('angle', '0')} 0")),
                               flags=int(get("spawnflags", "0"))))
        elif classname == "trigger_changelevel":
            reference = get("model")
            if not re.fullmatch(r"\*[0-9]+", reference) or not 0 < int(reference[1:]) < len(models):
                raise ValueError(f"{name} exit {index + 1}: missing brush bounds")
            model = models[int(reference[1:])]
            origin = vector(get("origin", "0 0 0"))
            mins = [model[i] + origin[i] for i in range(3)]
            maxs = [model[3 + i] + origin[i] for i in range(3)]
            if not all(math.isfinite(v) for v in mins + maxs) or any(a > b for a, b in zip(mins, maxs)):
                raise ValueError(f"{name} exit {index + 1}: invalid brush bounds")
            exits.append(dict(entity=index + 1, destination=get("map"), target=get("target"),
                              flags=int(get("spawnflags", "0")), cinematic=get("cinematic"),
                              cinematic_control=get("targetname").lower() in cinematic_targets,
                              model=reference, mins=mins, maxs=maxs,
                              angles=vector(get("angles", f"0 {get('angle', '0')} 0"))))
    shaders = sorted({entry[:64].split(b"\0", 1)[0].decode("ascii")
                      for entry in (lumps[1][i:i + 72] for i in range(0, len(lumps[1]), 72))})
    return dict(sha256=hashlib.sha256(data).hexdigest(), bsp_bytes=len(data),
                entities=len(parsed), starts=starts, exits=exits, world_shaders=shaders)


def connections(maps):
    result = []
    for name, source in sorted(maps.items()):
        for exit in source["exits"]:
            destination = maps.get(exit["destination"])
            row = dict(source=name, **exit, status="geometry_unreviewed", issues=[])
            if destination is None:
                row["issues"].append("destination_missing")
                row["status"] = "invalid"
            else:
                matches = [start for start in destination["starts"]
                           if exit["target"] and start["targetname"].lower() == exit["target"].lower()]
                row["landing_candidates"] = matches
                row["return_exit_candidates"] = [back["entity"] for back in destination["exits"]
                                                   if back["destination"] == name]
                if exit["target"] and len(matches) != 1:
                    row["issues"].append("named_landing_missing" if not matches else "named_landing_ambiguous")
                elif not exit["target"]:
                    row["issues"].append("landing_not_explicit")
                if not row["return_exit_candidates"]:
                    row["issues"].append("no_authored_return")
                # Authored intermission applies to an exit without a named
                # landing. Named submap returns retain direct travel even when
                # the intermission flag is present; map spelling is irrelevant.
                if exit["cinematic"] or exit.get("cinematic_control") or exit["flags"] & 8 or (exit["flags"] & 1 and not exit["target"]):
                    row["status"] = "authored_cut"
            result.append(row)
    return result


def build(package):
    with zipfile.ZipFile(package) as archive:
        # Include transition/ending maps: their names need not start with an
        # episode number. Filtering by naming convention invents missing exits.
        names = [name for name in archive.namelist() if re.fullmatch(r"maps/[a-z0-9_]+\.bsp", name)]
        if len(names) != len(set(names)):
            raise ValueError("duplicate map entries")
        maps = {Path(name).stem: read_map(name, archive.read(name)) for name in sorted(names)}
    if not maps:
        raise ValueError("no campaign maps in supplied package")
    return dict(format=1, map_package_sha256=hashlib.sha256(package.read_bytes()).hexdigest(),
                maps=maps, connections=connections(maps),
                readiness="unreviewed: no connection is admitted as a seamless portal")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--maps", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    document = build(args.maps)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
    print(f"campaign connections: {len(document['maps'])} maps, {len(document['connections'])} exits; geometry requires review")


if __name__ == "__main__":
    main()
