#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Draw an authored map as a plan or a section, from the furniture manifest.

A photograph answers "what does this corner look like"; only a drawing answers
"where is everything, and what is missing".  Walkability complaints -- a tread
too shallow to stand on, a stair with a wall where its third lane should be, a
floor with nothing on it, a slab over empty air -- are all questions about the
whole tier at once, and no number of first-person frames adds up to one plan.

Two views come out of this:

  * `--plan Z` looks down on one tier.  A box is drawn if its height straddles
    the tier, so the floor it stands on and the furniture on it appear together.
    Structure is dark, dressing and props are coloured by kind, and a rail is a
    line, so a stairwell reads as a hole with a balustrade around it.
  * `--section AXIS COORD` slices the map vertically (`x` cuts a wall of
    constant x and looks along -x, so the picture is y across, z up).  That is
    how a floating tier is recognised: a slab with air under it and nothing
    under that air for two hundred units.

    python3 dkq3/tools/map_plan.py --map japanDM --plan 256 --out plan-t1.png
    python3 dkq3/tools/map_plan.py --map japanDM --section x -304 --out cut-x.png
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

#: Structure first, dressing over it: the last box drawn wins a pixel.
ORDER = {'slab': 0, 'stair': 1, 'rail': 2, 'detail': 3, 'prop': 4}
SHADE = {'slab': (74, 78, 86), 'stair': (140, 128, 96), 'rail': (30, 200, 200),
         'detail': (200, 150, 60), 'prop': (80, 220, 90)}
#: Anything that crosses two tiers is carrying something, and that is the one
#: question a section is asked -- so supports get their own colour and the
#: tower fronts and the sky/clip shells, which are neither, get their own.
SUPPORT = (225, 60, 60)
FACADE = (60, 96, 150)
FLOOR = (150, 152, 158)
#: Prefixes that are not level geometry: the sky shell and the player clip.
OMIT_DEFAULT = ('sky_', 'clip_', 'trigger')
BACKGROUND = (16, 16, 20)


def colour_for(name, kind, tier=None, high_z=None):
    if name.startswith('facade'):
        return FACADE
    if tier is not None and high_z is not None and abs(high_z - tier) <= 2.0:
        return FLOOR
    if tier is None and kind in ('slab', 'stair'):
        pass
    return SHADE.get(kind, (200, 200, 200))


def _load(manifest):
    rows = json.loads(Path(manifest).read_text(encoding='utf-8'))
    return [(row['name'], tuple(row['low']), tuple(row['high']), row['kind'])
            for row in rows]


def _pixels(width, height):
    return bytearray(bytes(BACKGROUND) * (width * height))


def _rect(canvas, width, height, x0, y0, x1, y1, colour):
    x0, x1 = sorted((max(0, int(x0)), min(width, int(x1))))
    y0, y1 = sorted((max(0, int(y0)), min(height, int(y1))))
    for py in range(y0, y1):
        row = (py * width) * 3
        for px in range(x0, x1):
            canvas[row + px * 3:row + px * 3 + 3] = bytes(colour)


def plan(rows, tier, tol=24.0, scale=0.5, bounds=None,
         omit=OMIT_DEFAULT):
    """-> (width, height, rgb) looking down on the tier at `tier`."""
    xs = [value for row in rows for value in (row[1][0], row[2][0])]
    ys = [value for row in rows for value in (row[1][1], row[2][1])]
    x0, x1 = bounds or (min(xs), max(xs))
    y0, y1 = bounds or (min(ys), max(ys))
    width, height = int((x1 - x0) * scale) + 1, int((y1 - y0) * scale) + 1
    canvas = _pixels(width, height)
    hits = 0
    for name, low, high, kind in sorted(rows, key=lambda row: ORDER.get(row[3], 5)):
        if name.startswith(omit):
            continue
        # A floor is drawn from the tier it carries, not the tier it occupies:
        # a 32-thick deck slab whose top is the T1 walk belongs to T1.  Anything
        # still standing at this height is furniture; anything whose top is a
        # full storey above is a column, and is drawn as one.
        if not (tier - 2.0 <= high[2] <= tier + tol + 2.0 or low[2] <= tier <= high[2]):
            continue
        if kind == 'rail' and abs(high[2] - tier) > 6.0:
            continue
        hits += 1
        tone = FLOOR if abs(high[2] - tier) <= 2.0 else \
            (SUPPORT if high[2] > tier + tol else SHADE.get(kind, (200, 200, 200)))
        # y grows upward on the drawing, which is the way a plan is read.
        _rect(canvas, width, height,
              (low[0] - x0) * scale, (y1 - high[1]) * scale,
              (high[0] - x0) * scale, (y1 - low[1]) * scale, tone)
    return width, height, canvas, hits


def section(rows, axis, coord, depth=64.0, scale=0.5, bounds=None,
          omit=OMIT_DEFAULT):
    """-> a vertical slice: the axis across, z up, for boxes within `depth` of `coord`."""
    across = 1 if axis == 'x' else 0
    xs = [value for row in rows for value in (row[1][across], row[2][across])]
    zs = [value for row in rows for value in (row[1][2], row[2][2])]
    a0, a1 = (min(xs), max(xs)) if bounds is None else bounds[0]
    z0, z1 = (min(zs), max(zs)) if bounds is None else bounds[1]
    width, height = int((a1 - a0) * scale) + 1, int((z1 - z0) * scale) + 1
    canvas = _pixels(width, height)
    hits = 0
    for name, low, high, kind in sorted(rows, key=lambda row: ORDER.get(row[3], 5)):
        if name.startswith(omit):
            continue
        near = (low[0] - depth <= coord <= high[0] + depth) if axis == 'x' \
            else (low[1] - depth <= coord <= high[1] + depth)
        if not near:
            continue
        hits += 1
        # A body more than a storey tall is a column, a pier or a wall.
        tall = high[2] - low[2] > 180.0
        tone = FACADE if name.startswith('facade') else \
            (SUPPORT if tall else SHADE.get(kind, (200, 200, 200)))
        _rect(canvas, width, height, (low[across] - a0) * scale, (z1 - high[2]) * scale,
              (high[across] - a0) * scale, (z1 - low[2]) * scale, tone)
    return width, height, canvas, hits


def write_ppm(path, width, height, canvas):
    path.write_bytes(b'P6\n%d %d\n255\n' % (width, height) + bytes(canvas))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--map', default='japanDM')
    parser.add_argument('--manifest', default=None)
    parser.add_argument('--plan', type=float, action='append', default=[],
                        help='tier height to look down on (repeatable)')
    parser.add_argument('--section', action='append', default=[],
                        metavar='AXIS:COORD', help='vertical slice, e.g. x:-304')
    parser.add_argument('--depth', type=float, default=96.0)
    parser.add_argument('--scale', type=float, default=0.5)
    parser.add_argument('--out', type=Path, default=Path('zig-out/map-dev/japanDM/plan'))
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    manifest = Path(args.manifest or root / 'zig-out' / 'map-dev' / args.map
                    / ('%s-boxes.json' % args.map))
    rows = _load(manifest)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    made = []
    directory = args.out if args.out.suffix == '' else args.out.parent
    directory.mkdir(parents=True, exist_ok=True)
    for tier in args.plan:
        width, height, canvas, hits = plan(rows, tier, scale=args.scale)
        target = directory / ('%s-plan-%g.ppm' % (args.map, tier))
        write_ppm(target, width, height, canvas)
        print('%-28s %4d boxes -> %s' % ('plan z=%g' % tier, hits, target))
        made.append(target)
    for spec in args.section:
        axis, _, coord = spec.partition(':')
        width, height, canvas, hits = section(rows, axis, float(coord), depth=args.depth,
                                              scale=args.scale)
        target = directory / ('%s-section-%s-%s.ppm'
                             % (args.map, axis, coord.replace('-', 'm').replace('.', 'p')))
        write_ppm(target, width, height, canvas)
        print('%-28s %4d boxes -> %s' % ('section %s=%s' % (axis, coord), hits, target))
        made.append(target)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
