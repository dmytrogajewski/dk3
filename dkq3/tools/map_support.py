#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Say which pieces of an authored map hang in the air.

The complaint that started this -- "some parts of the map is flying (e.g. on 3
level)" -- cannot be answered from a screenshot: a slab with nothing under it
photographs exactly like a slab on a column when the column is behind the camera.
It is a property of the *support graph*, and that graph is readable offline from
the furniture manifest the author pass records, so this answers in about a second
and names the offending objects instead of leaving the judgement to a photograph.

One object supports another when it holds it up from below (their heights meet
within `Z_TOL` and their footprints overlap by real area) or when it holds it
from the side within `Z_TOL` of a shared face -- a parapet bolted to a deck edge
is not floating just because it does not rest on anything.  Support then spreads
transitively outward from the street plane, and anything whose chain never
reaches it is unsupported.

Only the level's own structure is charged with standing up.  `rail`, `detail` and
`prop` entries are dressing fixed to something else and are reported as
information: a lantern hanging from an awning is meant to be airborne.

    python3 dkq3/tools/map_support.py --map japanDM [--deep] [--fail]
"""

from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path

#: How close two surfaces must be to count as touching.
Z_TOL = 3.0
#: A resting contact needs at least this much footprint overlap, in square units.
MIN_CONTACT_AREA = 100.0
#: ... and a side contact needs at least this much shared span on each of its
#: two axes, so a post merely crossing a slab diagonally cannot hold it up.
MIN_SIDE_SPAN = 8.0
#: Cells for the XY broad phase; the map is 2304 units across.
CELL = 192.0


def _footprint_area(a, b):
    span_x = min(a[2][0], b[2][0]) - max(a[1][0], b[1][0])
    span_y = min(a[2][1], b[2][1]) - max(a[1][1], b[1][1])
    return span_x * span_y if span_x > 0.0 and span_y > 0.0 else 0.0


def _side_span(a, b, axis):
    """-> the shared span of two boxes on the two axes other than `axis`."""
    product = 1.0
    for other in range(3):
        if other == axis:
            continue
        span = min(a[2][other], b[2][other]) - max(a[1][other], b[1][other])
        if span < MIN_SIDE_SPAN:
            return 0.0
        product *= span
    return product


def _supports(upper, lower):
    """-> why `lower` holds `upper`, or None.

    A rest is a top-to-bottom meeting; `encased` covers a piece whose foot sits
    inside the body of the piece it belongs to, and `bolted` a side fixing.
    """
    if _footprint_area(upper, lower) >= MIN_CONTACT_AREA:
        if abs(upper[1][2] - lower[2][2]) <= Z_TOL:
            return 'rests'
        if lower[1][2] < upper[1][2] < lower[2][2]:
            return 'encased'
    for axis in (0, 1):
        for pressed, carrier in ((upper, lower), (lower, upper)):
            if (abs(pressed[2][axis] - carrier[1][axis]) <= Z_TOL
                    or abs(pressed[1][axis] - carrier[2][axis]) <= Z_TOL):
                if _side_span(upper, lower, axis):
                    return 'bolted'
    return None


def _cells(box):
    for cx in range(int(box[1][0] // CELL), int(box[2][0] // CELL) + 1):
        for cy in range(int(box[1][1] // CELL), int(box[2][1] // CELL) + 1):
            yield (cx, cy)


def graph(rows):
    """-> parents[i]: the indices of every object that touches i from below or side."""
    grid = collections.defaultdict(list)
    for index, box in enumerate(rows):
        for cell in _cells(box):
            grid[cell].append(index)
    parents = collections.defaultdict(list)
    for members in grid.values():
        for a in members:
            for b in members:
                if a == b or rows[a][1][2] < rows[b][1][2]:
                    continue
                if _supports(rows[a], rows[b]):
                    parents[a].append(b)
    return parents


def reach_ground(rows, parents, ground):
    """-> the indices whose support chain reaches an object sitting on the street."""
    standing = {index for index, box in enumerate(rows) if box[1][2] <= ground + Z_TOL}
    holders = collections.defaultdict(list)
    for child, carriers in parents.items():
        for carrier in carriers:
            holders[carrier].append(child)
    frontier = list(standing)
    while frontier:
        for child in holders[frontier.pop()]:
            if child not in standing:
                standing.add(child)
                frontier.append(child)
    return standing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--map', default='japanDM')
    parser.add_argument('--manifest', default=None,
                        help='default zig-out/map-dev/<map>/<map>-boxes.json')
    parser.add_argument('--ground', type=float, default=0.0,
                        help='the street plane every chain must reach')
    parser.add_argument('--charge', default='slab,stair',
                        help='kinds charged with standing up (default slab,stair)')
    parser.add_argument('--deep', action='store_true', help='list every unsupported object')
    parser.add_argument('--fail', action='store_true', help='exit non-zero on any finding')
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    manifest = Path(args.manifest or
                    root / 'zig-out' / 'map-dev' / args.map / ('%s-boxes.json' % args.map))
    rows = [(row['name'], tuple(row['low']), tuple(row['high']), row['kind'])
            for row in json.loads(manifest.read_text(encoding='utf-8'))]
    charge = tuple(part for part in args.charge.split(',') if part)
    parents = graph(rows)
    standing = reach_ground(rows, parents, args.ground)
    floating = [index for index, row in enumerate(rows)
                if row[3] in charge and index not in standing]
    by_group = collections.Counter()
    for index in floating:
        parts = rows[index][0].split('_')
        by_group['_'.join(parts[:-1]) or rows[index][0]] += 1
    for group, count in by_group.most_common():
        print('%-28s %3d floating' % (group, count))
    for index in (floating if args.deep else []):
        name, low, high, kind = rows[index]
        print('  %-34s %-6s [%7.1f %7.1f %7.1f] [%7.1f %7.1f %7.1f]'
              % (name, kind, *low, *high))
    dressing = [index for index, row in enumerate(rows)
                if row[3] not in charge and index not in standing]
    print('%s: %d objects, %d charged, %d unsupported, %d dressing loose, %d supported'
          % (args.map, len(rows), len([r for r in rows if r[3] in charge]),
             len(floating), len(dressing), len(standing)))
    return 1 if (args.fail and floating) else 0


if __name__ == '__main__':
    raise SystemExit(main())
