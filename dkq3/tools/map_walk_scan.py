# SPDX-License-Identifier: GPL-2.0-or-later
"""Walk the authored climb routes against the compiled map, not against the author.

`build_blender.py` audits its own intent: it knows the treads it wrote and the
clearance it asked for, and it reported 0 defects while the engine-side walk probe
showed a player that climbed 88 units of a 256-unit flight and then stood still for
five seconds.  Something between the two views of the map disagrees, and the answer
has to come from what the finished `.map` actually contains.

This re-reads the emitted `.map` and pushes a body box along a route the way the
player does: floor under each sample, then what is overhead, and the first place
where a 24-wide x 56-tall body cannot fit or cannot step.  Body and step numbers are
the engine's, so a route that passes here but fails in the walk probe points at the
probe rather than the geometry.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import map_sightlines

BODY_HALF = 15.0
BODY_TALL = 56.0
STEP_UP = 18.0
HEAD_ROOM = 24.0

ROUTES = {
    'stair_s': ((-304, -1024, 0), (-304, -608, 256)),
    'stair_e': ((1024, -272, 0), (608, -272, 256)),
    'ramp_n': ((-680, 1024, 0), (-680, 580, 256)),
    'ramp_w': ((-1024, -272, 0), (-608, -272, 256)),
    'stair_roof_w': ((-1024, -250, 256), (-628, -250, 512)),
    'stair_roof_e': ((1024, -280, 256), (620, -280, 512)),
    'ramp_roof_n': ((-250, 1024, 256), (-250, 580, 512)),
    'lane_e': ((760, -1000, 0), (760, 1000, 0)),
    'lane_w': ((-760, 1000, 0), (-760, -1000, 0)),
    'deck_ring': ((880, -900, 256), (880, 900, 256)),
}


def route_samples(p0, p1, step=8.0):
    span = max(abs(p1[0] - p0[0]), abs(p1[1] - p0[1]))
    n = max(2, int(span / step) + 1)
    for i in range(n + 1):
        t = i / n
        yield (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)


STEP_DOWN = 48.0


def floors_at(index, x, y):
    """-> sorted walkable surface heights under (x, y), measured without reach."""
    return sorted(index.floor_heights(x, y, reach=1.0) or ())


def ceiling_at(index, x, y, floor):
    """-> (height, brush position) of the first surface a head would meet above a foot.

    The bottom of the blocking brush is reported rather than the ray's entry
    fraction: a stair is built from stacked boxes and thin nosing plates, so a ray
    started just above the tread often begins inside the very plate the foot is on,
    and reading the entry point then reports a one-unit ceiling everywhere.
    """
    frac, position = index.cast((x, y, floor + 2.0), (x, y, floor + BODY_TALL + 12.0))
    if position is None:
        return None, None
    bottom = index.brushes[position].bounds()[0][2]
    if bottom <= floor + 2.0:
        return None, None
    return bottom, position


def describe(index, position):
    if position is None:
        return ''
    brush = index.brushes[position]
    lo, hi = brush.bounds()
    return '%s @%s..%s' % ('/'.join(brush.shaders()), tuple(round(v) for v in lo),
                           tuple(round(v) for v in hi))


def march(index, p0, p1, half=BODY_HALF, step=8.0):
    """-> (problems, profile) for one straight route, walked the way a player walks it.

    The body starts on the declared floor at the route's beginning and is carried
    forward: a surface within a step up is climbed onto, a surface below is fallen
    onto within the engine's step-down, and anything else is a hole.  Height is never
    re-acquired from the destination, which is what made an earlier version of this
    scan believe the bottom of a stair was already its top.
    """
    problems, profile = [], []
    along_x = abs(p1[0] - p0[0]) >= abs(p1[1] - p0[1])
    feet = p0[2]
    for x, y in route_samples(p0, p1, step):
        centre_floor, blocked = None, []
        for off in (-half, 0.0, half):
            px, py = (x, y + off) if along_x else (x + off, y)
            options = [z for z in floors_at(index, px, py)
                       if feet - STEP_DOWN <= z <= feet + STEP_UP
                       # A surface is only a floor if the body can rest on it.
                       and (lambda c: c[0] is None or c[0] >= z + BODY_TALL)(
                           ceiling_at(index, px, py, z))]
            if not options:
                blocked.append(('no floor', px, py, None))
                continue
            floor = max(options)
            ceil, blocker = ceiling_at(index, px, py, floor)
            if ceil is not None and ceil - floor < HEAD_ROOM:
                blocked.append(('head room %.0f' % (ceil - floor), px, py, blocker))
            if off == 0.0:
                centre_floor = floor
        if centre_floor is None:
            problems.append((x, y, ' | '.join('%s@%.0f,%.0f %s' % (w, a, b, describe(index, c))
                                              for w, a, b, c in blocked[:2]), None, None))
            continue
        for why, px, py, blocker in blocked:
            problems.append((px, py, why, centre_floor, describe(index, blocker)))
            if len([q for q in problems if q[2] == why]) > 6 and why not in ('no floor',):
                problems.append((px, py, '(further repeats of %s suppressed)' % why, None, None))
        profile.append((round(y if along_x else x, 1), round(centre_floor, 1)))
        feet = centre_floor
    return problems, profile


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('map_file', type=Path)
    ap.add_argument('--route', action='append', default=[],
                    help='name=x,y,z:x,y,z, overriding or adding a route')
    ap.add_argument('--only', action='append', default=[])
    ap.add_argument('--profile', action='store_true')
    args = ap.parse_args()
    doc = map_sightlines.read_map(args.map_file)
    index = map_sightlines.Index(doc.brushes())
    routes = dict(ROUTES)
    for spec in args.route:
        name, rest = spec.split('=', 1)
        a, b = rest.split(':')
        routes[name] = ([float(v) for v in a.split(',')], [float(v) for v in b.split(',')])
    for name, (p0, p1) in routes.items():
        if args.only and name not in args.only:
            continue
        problems, profile = march(index, p0, p1)
        print('%-14s samples %3d  floor %.0f -> %.0f (rise %.0f)  problems %d'
              % (name, len(profile), profile[0][1] if profile else -1,
                 profile[-1][1] if profile else -1,
                 (profile[-1][1] - profile[0][1]) if profile else 0, len(problems)))
        seen = set()
        for px, py, why, a, b in problems:
            key = (why.split()[0], round(px / 32), round(py / 32))
            if key in seen:
                continue
            seen.add(key)
            print('    %s' % ('%-14s at %7.0f,%7.0f  floor %s   %s'
                              % (why.split()[0], px, py,
                                 '-' if a is None else '%.0f' % a,
                                 why[len(why.split()[0]):].strip()))[:220])
        if args.profile and profile:
            print('    profile:', profile[::6])


if __name__ == '__main__':
    main()
