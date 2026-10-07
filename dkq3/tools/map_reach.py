# SPDX-License-Identifier: GPL-2.0-or-later
"""Name the parts of a deathmatch map a player cannot walk to.

`map_sightlines` already refuses to count a vantage nobody can keep, and reports
how many of its eye samples were unreachable -- a count.  A count cannot be fixed.
This tool takes the same walk model (`map_sightlines.reachable`, one `WALK_STEP`
per footfall, ground under every step of a long stride) and groups what it drops
into the places those samples came from, so a floating deck is a row in a table
with a coordinate on it.

Read the tiers first: a tier with no reachable samples at all is a floor the level
shows the player and then does not let them stand on, which is the "that part is
flying" complaint in measurement form.
"""
import argparse
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import map_sightlines as walk


def clusters(samples, cell=512.0):
    """-> {(cx, cy, tier): [(x, y, floor)]} coarse neighbourhoods of a floor height."""
    grouped = defaultdict(list)
    for x, y, _eye, floor in samples:
        grouped[(int(math.floor(x / cell)), int(math.floor(y / cell)), int(floor // 64) * 64)].append(
            (x, y, floor))
    return grouped


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--map', type=Path, required=True)
    parser.add_argument('--materials', type=Path, required=True)
    parser.add_argument('--grid', type=float, default=48.0)
    parser.add_argument('--min-cluster', type=int, default=6)
    parser.add_argument('--cell', type=float, default=512.0)
    parser.add_argument('--max-floor', type=float, default=None,
                        help='ignore walkable tops above this (the shell lid is not a floor)')
    parser.add_argument('--report', type=Path, default=None)
    arguments = parser.parse_args(argv)

    document = walk.read_map(arguments.map, walk.non_solid_shaders(arguments.materials))
    solid = [brush for entity in document.entities for brush in entity.brushes
             if any(face.style.solid for face in brush.faces)]
    index = walk.Index(solid, cell=max(arguments.grid, 96.0))
    bounds = document.bounds()
    every = walk.eye_positions(index, bounds, grid=arguments.grid)
    eyes = []
    items = []
    for entity in document.entities:
        origin = entity.keys.get('origin')
        if not origin or entity.classname == 'worldspawn':
            continue
        position = tuple(float(value) for value in origin.split())
        if entity.classname.startswith('info_player_'):
            eyes.append((entity.source or entity.classname,
                         (position[0], position[1], position[2] - 2.0)))
        elif entity.classname.startswith(('weapon_', 'ammo_', 'item_')):
            items.append((entity.classname + ' ' + (entity.source or ''), position))
    reached = walk.reachable(index, every, eyes, grid=arguments.grid)
    lost = [sample for sample in every if sample not in set(reached)]

    if arguments.max_floor is not None:
        every = [sample for sample in every if sample[3] <= arguments.max_floor]
        lost = [sample for sample in lost if sample[3] <= arguments.max_floor]

    tiers = defaultdict(lambda: [0, 0])
    for sample in every:
        tiers[int(sample[3] // 64) * 64][0 if sample in set(reached) else 1] += 1
    print('map-reach: %d walkable positions, %d reachable, %d not'
          % (len(every), len(reached), len(lost)))
    print('map-reach: tiers (floor z -> reachable / total)')
    for tier in sorted(tiers):
        hit, miss = tiers[tier]
        flag = '' if hit else '   <-- NO ACCESS'
        print('    %6d  %5d / %5d%s' % (tier, hit, hit + miss, flag))

    stranded = [name for name, position in items if not walk.within_reach(reached, position)]
    if stranded:
        print('map-reach: %d pickups off the walkable set: %s' % (len(stranded), ', '.join(stranded)))

    grouped = clusters(lost, cell=arguments.cell)
    worst = sorted(grouped.items(), key=lambda entry: -len(entry[1]))
    worst = [entry for entry in worst if len(entry[1]) >= arguments.min_cluster]
    print('map-reach: %d unreachable neighbourhoods of >= %d positions'
          % (len(worst), arguments.min_cluster))
    for (cx, cy, tier), members in worst[:24]:
        xs = [m[0] for m in members]
        ys = [m[1] for m in members]
        floors = [m[2] for m in members]
        nearest = min(math.hypot(x - ex, y - ey) for (x, y, _f) in members
                      for _name, (ex, ey, _e) in eyes)
        print('    x %6.0f..%6.0f  y %6.0f..%6.0f  floor %6.0f..%6.0f  n=%3d  nearest spawn %5.0f'
              % (min(xs), max(xs), min(ys), max(ys), min(floors), max(floors), len(members), nearest))
    if arguments.report is not None:
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        arguments.report.write_text(json.dumps(dict(
            map=str(arguments.map), grid=arguments.grid, considered=len(every),
            reachable=len(reached),
            tiers={str(tier): tiers[tier] for tier in sorted(tiers)},
            stranded_pickups=stranded,
            clusters=[[list(key), len(value)] for key, value in worst],
        ), indent=2, sort_keys=True) + '\n')
    return 1 if any(not tiers[tier][0] for tier in tiers) or stranded else 0


if __name__ == '__main__':
    raise SystemExit(main())
