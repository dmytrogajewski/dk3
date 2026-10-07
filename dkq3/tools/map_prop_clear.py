#!/usr/bin/env python3
"""Fail when a prop pass seats a prop inside something it should not.

`build_blender.verify` sees every brush the author pass emitted, which means it
sees the props as geometry and reports the level's own furniture as a flat list
of boxes.  This tool runs the *placement* pass offline -- no Blender, no
compile -- against the recorded furniture, so a bad coordinate is caught in
about a second instead of at the end of a four-minute build.

The furniture fixture is what the author pass records when
``DK3_BOXES_JSON`` is set.  It still contains the previous build's generated
props, which the new placements will overwrite, so ``prop_*`` entries are
dropped from the fixture and rebuilt here from the placement list instead --
otherwise the report is a diff against the last build rather than against this
one.

    python3 dkq3/tools/map_prop_clear.py --map japanDM

The author pass writes that manifest as part of an ordinary build, because
`map_build.py` sets DK3_BOXES_JSON for the model step; the fixture is therefore
never older than the scene it describes.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
import sys
from pathlib import Path


def _vol(box):
    v = 1.0
    for axis in range(3):
        v *= max(0.0, box[2][axis] - box[1][axis])
    return v


def _intersect(a, b):
    v = 1.0
    for axis in range(3):
        span = min(a[2][axis], b[2][axis]) - max(a[1][axis], b[1][axis])
        if span <= 0:
            return 0.0
        v *= span
    return v


def _load_props(map_dir: Path):
    spec = importlib.util.spec_from_file_location('%s_props' % map_dir.name,
                                                 map_dir / 'props.py')
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(map_dir))
    spec.loader.exec_module(module)
    return module


def _placed_box(props, index, place):
    """-> (name, low, high) AABB of one placement, mirroring prop_scatter.

    The generator leaves a mesh in the positive octant, so the scatter recentres
    it on its own footprint before rotating: the AABB has to be built the same
    way or every yawed prop reports a collision it does not have.
    """
    recipe = props.recipe(place['prop'])
    points = [q for piece in recipe['pieces'] for q in piece['points']]
    if not points:
        return None
    centre_x = 0.5 * (min(q[0] for q in points) + max(q[0] for q in points))
    centre_y = 0.5 * (min(q[1] for q in points) + max(q[1] for q in points))
    cosine, sine = math.cos(math.radians(place['yaw'])), math.sin(math.radians(place['yaw']))
    xs, ys = [], []
    for qx, qy, _ in points:
        px, py = (qx - centre_x) * place['scale'], (qy - centre_y) * place['scale']
        xs.append(place['x'] + px * cosine - py * sine)
        ys.append(place['y'] + px * sine + py * cosine)
    zs = [q[2] * place['scale'] for q in points]
    return ('%s@%g,%g#%d' % (place['prop'], place['x'], place['y'], index),
            (min(xs), min(ys), place['z'] + min(zs)),
            (max(xs), max(ys), place['z'] + max(zs)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--map', default='japanDM')
    parser.add_argument('--fixture', default=str(Path('zig-out/map-dev') / 'japanDM' /
                                                 'japanDM-boxes.json'),
                        help='the furniture manifest the model step wrote')
    parser.add_argument('--face', type=float, default=1024.0)
    parser.add_argument('--plaza', type=float, default=448.0)
    parser.add_argument('--foot', type=float, default=1152.0)
    parser.add_argument('--lane', type=float, default=96.0)
    parser.add_argument('--fixture-overlap', type=float, default=0.20)
    parser.add_argument('--prop-overlap', type=float, default=0.40)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    map_dir = root / 'maps' / args.map
    props = _load_props(map_dir)
    with open(args.fixture) as handle:
        fixture = [(row['name'], tuple(row['low']), tuple(row['high']), row['kind'])
                   for row in json.load(handle)
                   if not row['name'].startswith('prop_')]
    floors = {'T0': 0.0, 'T1': 256.0, 'T2': 512.0}
    places = props.placements(fixture, floors, face=args.face, plaza_half=args.plaza,
                              foot=args.foot, lane=args.lane)
    made = [box for box in (_placed_box(props, i, p) for i, p in enumerate(places))
            if box]
    # `detail` pieces and the trim suffixes are surface dressing: a bin standing
    # where an awning post was is not the defect this tool is for, and prop.py's
    # own TRIM convention says so.
    trim = ('_plinth', '_lid', '_glass', '_glow', '_flange')
    solid = [(n, lo, hi) for n, lo, hi, kind in fixture
             if kind not in ('rail', 'trigger', 'detail') and not n.endswith(trim)]
    defects = 0
    for box in made:
        for name, lo, hi in solid:
            hit = _intersect(box, (name, lo, hi))
            share = hit / max(1e-6, min(_vol(box), _vol((name, lo, hi))))
            if share >= args.fixture_overlap:
                print('%-30s %2.0f%% inside %s' % (box[0], 100 * share, name))
                defects += 1
    for a in range(len(made)):
        for b in range(a + 1, len(made)):
            hit = _intersect(made[a], made[b])
            share = hit / max(1e-6, min(_vol(made[a]), _vol(made[b])))
            if share >= args.prop_overlap:
                print('%-30s %2.0f%% inside %s' % (made[a][0], 100 * share, made[b][0]))
                defects += 1
    for box in made:
        for axis in (0, 1):
            if max(abs(box[1][axis]), abs(box[2][axis])) > args.face + 0.5:
                print('%-30s crosses the outer shell on %s' % (box[0], 'xyz'[axis]))
                defects += 1
    for pattern in props.misses():
        print('anchor miss: %s' % pattern)
        defects += 1
    print('%s: %d placements, %d defects' % (args.map, len(places), defects))
    return 1 if defects else 0


if __name__ == '__main__':
    raise SystemExit(main())
