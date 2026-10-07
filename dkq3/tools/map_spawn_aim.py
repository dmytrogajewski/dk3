# SPDX-License-Identifier: GPL-2.0-or-later
"""Measure what a player actually sees the instant they spawn, and fix it.

A deathmatch start is placed for two opposing reasons at once.  It must not be a
firing position, so something solid belongs within reach of it; and it must not be
a wall, because the first half-second of a life is spent reading the fight, and a
start whose eye line lands on a crate 45 units away reads as a texture test, not a
place.  `map_sightlines.py` guards the first half (a spawn that can already shoot
another spawn is reported).  Nothing guarded the second, and japanDM shipped 8 of
14 starts facing a solid closer than 100 units.

This probe answers, per start, at the eye height the engine will actually use:

  * `centre`  -- how far the straight-ahead ray goes before it hits something;
  * `cone`    -- the same, worst of four rays at +-12 and +-25 degrees, which is
                 how much of the first impression is wall;
  * `cover`   -- the nearest solid behind the shoulders, where the first half of
                 the rule lives, measured over the rear half-circle only.

`--solve` then proposes a facing per start: maximize the open line and the cone,
keep cover in the 40..240 band, and never turn a start into a firing position.
The answer is a measurement, so it can be argued with; it is not a guess.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
from pathlib import Path
import sys

import map_sightlines
import quake_map

EYE_BELOW_ORIGIN = 2.0        # eye = authored origin - 2 (feet + 22, origin = feet + 24)
BODY_HALF = 15.0              # the player box is -15..15 in x and y (q_shared.h)
BODY_BELOW = 24.0             # ... and -24..+32 in z around the authored origin
BODY_ABOVE = 32.0
# The box is sampled on a 3x3x3 lattice, inset two units inside every face: a
# body that merely TOUCHES its floor or a wall that is exactly at its flank is
# seated, not stuck, and an exact coincident plane reads as a hit to a trace.
BODY_SAMPLE = (-BODY_HALF + 2.0, 0.0, BODY_HALF - 2.0)
BODY_LEVELS = (-BODY_BELOW + 2.0, 0.0, BODY_ABOVE - 2.0)
CONE_OFFSETS = (-25.0, -12.0, 12.0, 25.0)
REAR_OFFSETS = tuple(range(60, 301, 20))
MIN_CONE = 90.0               # closer than this and the view is a texture test
MIN_CENTRE = 120.0            # the straight-ahead line at least clears three bodies
COVER_BAND = (40.0, 240.0)    # solid within reach, but not wedged against it


def load_non_solid(materials_path):
    """-> the shader spellings a ray may pass through, both key and declared path."""
    return set(map_sightlines.non_solid_shaders(materials_path))


def solid_index(document, non_solid):
    brushes = [brush for entity in document.entities for brush in entity.brushes
               if any(face.style.solid for face in brush.faces)]
    return map_sightlines.Index(brushes, cell=128.0)


def starts(document):
    """-> [(label, eye, authored angle)] for every authored deathmatch start."""
    out = []
    for entity in document.entities:
        if not entity.classname.startswith('info_player_'):
            continue
        origin = [float(value) for value in entity.keys['origin'].split()]
        out.append((entity.source, (origin[0], origin[1], origin[2] - EYE_BELOW_ORIGIN),
                    float(entity.keys.get('angle', 0.0))))
    return out


def reach(index, eye, angle, distance=3000.0):
    """-> how far a ray from `eye` along `angle` gets, in units."""
    radians = math.radians(angle)
    fraction, hit = index.cast(eye, (eye[0] + math.cos(radians) * distance,
                                     eye[1] + math.sin(radians) * distance, eye[2]))
    return distance if hit is None else fraction * distance


def body_box(index, origin):
    """-> the sampled points of the player box that a solid already occupies.

    The engine seats a spawn by putting a 30 x 30 x 56 box around the authored
    origin and lifting a body that does not fit.  `map_sightlines` proves a FOOT
    fits -- a face to stand on, eight units off every edge, 56 units of headroom --
    and that is not the same claim: japanDM's `deck_se` was 8 units from a glass
    balustrade, which is legal for a foot and impossible for a body, and the engine
    spent 20 seconds of the capture refusing to put a player down there.  The box is
    sampled rather than intersected exactly (27 points, the corners and the middle
    of every face and edge), which catches every intrusion the size of a player.
    """
    x, y, z = origin
    inside = []
    for dx in BODY_SAMPLE:
        for dy in BODY_SAMPLE:
            for dz in BODY_LEVELS:
                point = (x + dx, y + dy, z + dz)
                fraction, hit = index.cast(point, (point[0] + 0.5, point[1], point[2]))
                if hit is not None and fraction <= 0.0:
                    inside.append(point)
    return inside


def measure(index, eye, angle):
    """-> the three numbers that describe one facing, plus the verdict they imply."""
    got = dict(centre=reach(index, eye, angle),
               cone=min(reach(index, eye, angle + offset, 1200.0) for offset in CONE_OFFSETS),
               cover=min(reach(index, eye, angle + offset, 800.0) for offset in REAR_OFFSETS))
    got['blocked'] = got['cone'] < MIN_CONE or got['centre'] < MIN_CENTRE
    return got


def solve(index, eye, step=5.0):
    """-> (angle, measurement) the best of the whole circle for one eye position."""
    best = None
    for angle in range(0, 360, int(step)):
        got = measure(index, eye, angle)
        if got['blocked']:
            continue
        rank = (min(got['centre'], 1400.0) + 0.6 * min(got['cone'], 700.0)
                + (60.0 if COVER_BAND[0] <= got['cover'] <= COVER_BAND[1] else 0.0))
        if best is None or rank > best[0]:
            best = (rank, angle % 360, got)
    return (best[1], best[2]) if best else (None, None)


def probe(document, non_solid=(), solve_angles=False):
    index = solid_index(document, set(non_solid))
    rows = []
    for label, eye, angle in starts(document):
        origin = (eye[0], eye[1], eye[2] + EYE_BELOW_ORIGIN)
        row = dict(name=label, eye=[round(value, 1) for value in eye], angle=angle,
                   stuck=len(body_box(index, origin)),
                   **measure(index, eye, angle))
        if solve_angles:
            suggested, got = solve(index, eye)
            row['suggest'] = suggested
            row['suggested'] = got
        rows.append(row)
    return rows


SITE_SEPARATION = 240.0       # closer than this to another start and they crowd


def sites(document, grid=48.0, min_range=640.0, separation=SITE_SEPARATION, region=None,
          limit=12):
    """-> walkable eye points that pass BOTH gates a start has to pass, and the counts.

    `map_sightlines.py` says where a start may not BE (somebody standing 640 units
    away can already shoot it); everything above says where a start may not LOOK.
    Each rule alone is not enough -- japanDM's eastern deck start moved twice
    because the spot that could be aimed was the spot that could be shot -- so this
    asks both questions of every walkable eye point the sightline model finds:
    first that the engine can hold a body there and that no other start can be
    seen from it, then that nothing beyond `min_range` can see it at all, and only
    then that `solve` can aim it at something worth looking at.

    Every candidate is cast at every walkable eye point, so a whole-map scan is
    candidates x samples: minutes single-threaded on a map with 3643 of them.  Pass
    `region` to search one district, which is what moving a start actually needs.
    """
    solid = [brush for entity in document.entities for brush in entity.brushes
             if any(face.style.solid for face in brush.faces)]
    index = map_sightlines.Index(solid, cell=max(grid, 96.0))
    here = [(name, eye) for name, eye, _angle in starts(document)]
    samples = map_sightlines.reachable(
        index,
        map_sightlines.eye_positions(index, document.bounds(), grid=grid,
                                     head_room=map_sightlines.HEAD_ROOM),
        here, grid=grid)
    offered = []
    for x, y, eye_z, floor in samples:
        if region and not (region[0] <= x <= region[2] and region[1] <= y <= region[3]):
            continue
        if any(math.hypot(x - point[0], y - point[1]) < separation for _name, point in here):
            continue
        eye = (x, y, eye_z)
        if body_box(index, (x, y, eye_z + EYE_BELOW_ORIGIN)):
            continue                       # the engine cannot hold a body here
        origin = (x, y, eye_z + EYE_BELOW_ORIGIN)
        if any(index.clear(point, (origin[0], origin[1], origin[2] - EYE_BELOW_ORIGIN))
               for _name, point in here):
            continue                       # it would share a first blood with a start
        if any(index.clear((sx, sy, vantage_eye), eye)
               for sx, sy, vantage_eye, _floor in samples
               if math.hypot(sx - x, sy - y) >= min_range):
            continue                       # somebody far away can already shoot it
        angle, got = solve(index, eye)
        if got is None:
            continue                       # and it has nothing to look at
        row = dict(pos=[x, y], floor=floor, eye=eye_z, angle=angle,
                   centre=round(got['centre'], 1), cone=round(got['cone'], 1),
                   cover=round(got['cover'], 1))
        row['rank'] = round(min(row['centre'], 1400.0) + 0.6 * min(row['cone'], 700.0)
                            + (60.0 if COVER_BAND[0] <= row['cover'] <= COVER_BAND[1] else 0.0),
                            1)
        offered.append(row)
    offered.sort(key=lambda row: -row['rank'])
    return dict(found=offered[:limit], offered=len(offered), scanned=len(samples))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--map', type=Path, required=True, help='the exported .map')
    parser.add_argument('--materials', type=Path, default=None, help='the map materials.py')
    parser.add_argument('--solve', action='store_true', help='also propose a facing per start')
    parser.add_argument('--propose-sites', type=int, default=0, metavar='N',
                        help='also list the N walkable spots that pass both start gates')
    parser.add_argument('--grid', type=float, default=48.0, help='eye sampling step')
    parser.add_argument('--region', type=float, nargs=4, metavar=('X0', 'Y0', 'X1', 'Y1'),
                        default=None, help='only look for sites inside this rectangle')
    parser.add_argument('--min-range', type=float, default=640.0,
                        help='a shot from further away than this exposes a site')
    parser.add_argument('--separation', type=float, default=SITE_SEPARATION,
                        help='keep proposed sites at least this far from an existing start')
    parser.add_argument('--report', type=Path, default=None, help='write the measurement as JSON')
    arguments = parser.parse_args(argv)
    non_solid = load_non_solid(arguments.materials) if arguments.materials else ()
    rows = probe(map_sightlines.read_map(arguments.map, non_solid=non_solid),
                 non_solid=non_solid, solve_angles=arguments.solve)
    if arguments.report:
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        arguments.report.write_text(json.dumps(rows, indent=2) + '\n')
    print('map-spawn-aim: %s' % arguments.map.name)
    bad = 0
    for row in rows:
        bad += bool(row['blocked'])
        print('  %-28s angle %6.1f  centre %6.0f cone %6.0f cover %6.0f%s%s'
              % (row['name'], row['angle'], row['centre'], row['cone'], row['cover'],
                 '  BLOCKED' if row['blocked'] else '',
                 '' if row.get('suggest') is None else '  -> %d' % row['suggest']))
    wedged = sum(1 for row in rows if row['stuck'])
    print('map-spawn-aim: %d of %d starts have nothing to look at (cone < %g or line < %g)'
          % (bad, len(rows), MIN_CONE, MIN_CENTRE))
    if wedged:
        print('map-spawn-aim: %d of %d starts cannot hold a player body (%s)'
              % (wedged, len(rows),
                 ', '.join('%s: %d points' % (row['name'], row['stuck'])
                           for row in rows if row['stuck'])))
    if arguments.propose_sites:
        document = map_sightlines.read_map(arguments.map, non_solid=non_solid)
        got = sites(document, grid=arguments.grid, min_range=arguments.min_range,
                    separation=arguments.separation, region=arguments.region,
                    limit=arguments.propose_sites)
        print('map-spawn-aim: %d of %d free eye samples pass every rule; best %d'
              % (got['offered'], got['scanned'], min(len(got['found']), arguments.propose_sites)))
        for row in got['found']:
            print('  (%8.1f, %8.1f) floor %5.0f  angle %3d  centre %6.0f cone %6.0f cover %5.0f'
                  % (row['pos'][0], row['pos'][1], row['floor'], row['angle'], row['centre'],
                     row['cone'], row['cover']))
        if not got['offered']:
            print('map-spawn-aim: no walkable eye point passes both gates here',
                  file=sys.stderr)
            return 1
    if bad or wedged:
        print('map-spawn-aim: %d start(s) have nothing to look at, %d cannot hold a body'
              % (bad, wedged), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
