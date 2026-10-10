#!/usr/bin/env python3
"""Where can a landmark stand, and what stands in it afterwards?

`build_blender.landmarks()` asks `_rect_clear()` whether a rect has a storey to
itself.  A refused landmark used to cost a whole build-and-read cycle to diagnose:
Blender takes a minute, and the refusal said only "a walking line runs through it".
This tool asks the same questions outside Blender, over a grid, and names the line,
the brush or the player's own start that refused a site.

It reads the authored facts out of the generator rather than restating them:
`WALK_LINES`, the seven `CLIMB_*` tables, their `climb_lines()` sampling and
`SPAWNS` are parsed out of `build_blender.py` with `ast`, and the solids come from
the box manifest the last author run wrote (`japanDM-boxes.json`).

Two questions, because a landmark has two ways to fail:

* **site** -- the manifest is truncated at the first brush the landmarks themselves
  make.  That index, not a name filter, is the honest boundary: `box()` appends in
  build order, so everything before the landmarks' own pieces is exactly what
  existed when they were sited, and everything after them is what is laid *around*
  them (`--until lantern_court,roof_mast`).
* **conflicts** -- the full manifest, checking that nothing laid later stands
  inside a landmark.  Sections like the bazaar and the colonnade ask `_site_clear`
  and step aside; the tool is the proof that they all do.

    python3 -B dkq3/tools/map_site_probe.py --until lantern_court,roof_mast
    python3 -B dkq3/tools/map_site_probe.py --conflicts lantern_court,vendor,roof_mast
"""

import argparse
import ast
import json
import sys

HERE = __file__.rsplit('/', 1)[0]
BUILDER = HERE + '/../../maps/japanDM/build_blender.py'

#: What the literal tables in `build_blender.py` are allowed to mention.
CONSTS = {'T0': 0, 'T1': 256, 'T2': 512, 'VIA': 704, 'PLAZA': 448, 'LANE': 96,
          'FOOT': 1152, 'FACE': 1024, 'DECK': 32}
FACE = 1024.0
#: Which brushes the crossing/nesting audits never charge, so a landmark may
#: overlap them; mirrors `build_blender.SHELLS`.
SHELLS = ('facade_', 'sky_ring', 'sky_lid', 'clip_')
#: The audit's body: HULL_HALF + the route clearance wide, BODY_TOP tall, and
#: nothing above a step-up counts, because the engine walks over it.  Mirrors
#: `build_blender._box_on_body`.
BODY_HALF, BODY_TALL, CLEARANCE, STEP_UP = 15.0 + 6.0, 56.0, 6.0, 18.0
#: How far a player's own start is kept clear, as `_rect_clear` keeps it.
SPAWN_KEEP = 88.0


def literal_tables(path):
    """-> every module-level tuple/list table in a file, evaluated with CONSTS."""
    with open(path) as handle:
        tree = ast.parse(handle.read())
    tables = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and isinstance(node.value, (ast.Tuple, ast.List)):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    try:
                        tables[target.id] = eval(
                            compile(ast.Expression(node.value), '<table>', 'eval'),
                            dict(CONSTS))
                    except Exception:        # a table that needs more than the consts
                        pass
    return tables


def climb_lines(climb, stand_off=40.0, back=128.0):
    """-> the walking lines a flight of steps implies, as `build_blender` samples it."""
    name, start, end, width = climb
    along = 0 if abs(end[0] - start[0]) > abs(end[1] - start[1]) else 1
    across = 1 - along
    sign = 1.0 if end[along] > start[along] else -1.0
    offset = max(24.0, width / 2.0 - 24.0)
    lines = []
    laterals = [0.0]
    if width >= 128.0:
        laterals += [width / 4.0, -width / 4.0]
    if width - 48.0 > offset:
        laterals += [offset, -offset]
    for lateral in laterals:
        foot, top = list(start), list(end)
        foot[across] += lateral
        top[across] += lateral
        lines.append(('%s/run%+d' % (name, lateral), [tuple(foot), tuple(top)]))
    door = [list(start), list(start)]
    door[0][along] -= sign * back
    door[1][along] -= sign * 16.0
    lines.append(('%s/approach' % name, [tuple(door[0]), tuple(door[1])]))
    mouth = [list(start), list(start)]
    for one in mouth:
        one[along] -= sign * stand_off
        one[across] -= width / 2.0 + 16.0
    mouth[1][across] += width + 32.0
    lines.append(('%s/mouth' % name, [tuple(mouth[0]), tuple(mouth[1])]))
    return lines


def overlap(a0, a1, b0, b1):
    return a0 < b1 and a1 > b0


class Scene:
    """The authored scene, optionally truncated to what a section could see."""

    def __init__(self, manifest, until=None):
        boxes = json.load(open(manifest))
        if until:
            prefixes = tuple(one.strip() for one in until.split(',') if one.strip())
            cut = min((index for index, box in enumerate(boxes)
                       if box['name'].startswith(prefixes)), default=None)
            if cut is None:
                sys.exit('no brush starts with %r -- the manifest is from a build '
                         'without those sections' % (prefixes,))
            boxes = boxes[:cut]
        self.boxes = boxes
        self.solid = [b for b in boxes
                      if b['kind'] not in ('detail', 'rail', 'trigger', 'loose', 'hint')
                      and not b['name'].startswith(SHELLS)]
        tables = literal_tables(BUILDER)
        lines = list(tables['WALK_LINES'])
        for key in ('CLIMB_S', 'CLIMB_N', 'CLIMB_W', 'CLIMB_E', 'ROOF_CLIMB_W',
                    'ROOF_CLIMB_N', 'ROOF_CLIMB_E'):
            lines += climb_lines(tables[key])
        self.points = []
        for label, path in lines:
            for (x0, y0, z0), (x1, y1, z1) in zip(path, path[1:]):
                steps = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) / 10.0))
                for step in range(steps + 1):
                    t = step / float(steps)
                    self.points.append((label, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t,
                                        z0 + (z1 - z0) * t))
        self.spawns = [(name, loc) for name, loc, _angle in tables['SPAWNS']]
        self.spawns_all = tables['SPAWNS']
        self.FLOORS = self._raster_floors()

    def route_blocker(self, low, high):
        """-> the walking line whose body would stand inside a rect."""
        for label, x, y, feet in self.points:
            if (low[0] < x + BODY_HALF and high[0] > x - BODY_HALF
                    and low[1] < y + BODY_HALF and high[1] > y - BODY_HALF
                    and low[2] < feet + BODY_TALL + CLEARANCE
                    and high[2] > feet + STEP_UP):
                return '%s at %d,%d z%d' % (label, round(x), round(y), round(feet))
        return None

    def blockers(self, low, high):
        """-> the structural brushes standing inside a rect."""
        return sorted({box['name'] for box in self.solid
                       if not box['high'][2] <= low[2] + 2.0
                       and not box['low'][2] >= high[2] - 2.0
                       and box['low'][0] < high[0] and box['high'][0] > low[0]
                       and box['low'][1] < high[1] and box['high'][1] > low[1]})

    def spawn_blocker(self, low, high):
        for name, place in self.spawns:
            if (place[0] - SPAWN_KEEP < high[0] and place[0] + SPAWN_KEEP > low[0]
                    and place[1] - SPAWN_KEEP < high[1]
                    and place[1] + SPAWN_KEEP > low[1]
                    and abs(place[2] - low[2]) < 64.0):
                return '%s at %d,%d' % (name, round(place[0]), round(place[1]))
        return None

    def _raster_floors(self):
        """-> {(cell-x, cell-y): {top z}}, the floors a landmark may stand on.

        The deck and the roofs are *tiled*, so asking whether one slab covers a
        rect whole asks the wrong question: a 300-unit block that straddles a
        tile joint has a floor under every inch of it and was refused by the first
        version of this tool.  Rasterising the plates once at 32 units turns the
        question into "is every cell of my footprint floored at this storey".
        """
        cell = 32.0
        grid = {}
        for box in self.boxes:
            if box['kind'] != 'slab':
                continue
            lo, hi = box['low'], box['high']
            if hi[2] <= lo[2]:
                continue
            ix0 = int(lo[0] // cell)
            ix1 = int((hi[0] - 0.01) // cell)
            iy0 = int(lo[1] // cell)
            iy1 = int((hi[1] - 0.01) // cell)
            for ix in range(ix0, ix1 + 1):
                for iy in range(iy0, iy1 + 1):
                    grid.setdefault((ix, iy), set()).add(hi[2])
        return cell, grid

    def floor_at(self, low, high, z):
        """-> the slabs whose top is `z` under a rect, when every cell is floored."""
        touching = sorted(b['name'] for b in self.boxes
                          if b['kind'] == 'slab' and abs(b['high'][2] - z) <= 1.0
                          and b['low'][2] < z and b['low'][0] < high[0]
                          and b['high'][0] > low[0] and b['low'][1] < high[1]
                          and b['high'][1] > low[1])
        if not touching:
            return []
        cell, grid = self.FLOORS
        # Sample the footprint's cells, inset half a cell so a plate that only
        # touches the rect's edge does not count as holding it up.
        ix0 = int((low[0] + cell * 0.5) // cell)
        ix1 = int((high[0] - cell * 0.5) // cell)
        iy0 = int((low[1] + cell * 0.5) // cell)
        iy1 = int((high[1] - cell * 0.5) // cell)
        for ix in range(ix0, ix1 + 1):
            for iy in range(iy0, iy1 + 1):
                if z not in grid.get((ix, iy), ()):
                    return []
        return touching

    def why_not(self, low, high, need_floor=True):
        """-> the reasons a rect cannot hold a landmark; empty when it can."""
        reasons = []
        hits = self.blockers(low, high)
        if hits:
            reasons.append('%d brush(es): %s' % (len(hits), ', '.join(hits[:3])))
        for finder in (self.route_blocker, self.spawn_blocker):
            found = finder(low, high)
            if found:
                reasons.append(found)
        if need_floor and not self.floor_at(low, high, low[2]):
            reasons.append('no slab under it')
        return reasons


def seen_by(spawns, centre, cone=45.0, near=100.0, far=1200.0):
    """-> the authored starts whose own view would include a landmark.

    The plan asks for a landmark identifiable from two different starts, and a
    start is an origin *and* an angle: a thing behind a player's shoulder does not
    tell them where they are.  This is a cone test, not a line of sight -- the
    view probe is what proves the pixels -- but it is the same question.
    """
    import math
    out = []
    for name, place, angle in spawns:
        if abs(place[2] - centre[2]) > 40.0:
            continue
        dx, dy = centre[0] - place[0], centre[1] - place[1]
        distance = math.hypot(dx, dy)
        if not near < distance < far:
            continue
        bearing = math.degrees(math.atan2(dy, dx)) % 360.0
        if abs((bearing - angle + 180.0) % 360.0 - 180.0) < cone:
            out.append('%s@%d' % (name, round(distance)))
    return out


def aabb(corners, z0, z1):
    return ((min(c[0] for c in corners), min(c[1] for c in corners), z0),
            (max(c[0] for c in corners), max(c[1] for c in corners), z1))


def place_frame(axis, front, rect):
    """-> (u0, u1, v0, v1, to_world, to_point) in the block's own frame.

    Same map as `maps/japanDM/build_blender.py::_lm_frame`, kept here so the probe can
    ask the exact question the builder will ask.  `u` runs along the street, `v`
    crosses it growing toward `front`.
    """
    (x0, y0, _z0), (x1, y1, _z1) = rect
    if axis == 'x':
        u0, u1 = x0, x1
        v0, v1 = sorted((front * y0, front * y1))
    else:
        u0, u1 = y0, y1
        v0, v1 = sorted((front * x0, front * x1))

    def to_world(ua, va, ub, vb, za, zb):
        if axis == 'x':
            along, across = (ua, ub), (front * va, front * vb)
        else:
            along, across = (front * va, front * vb), (ua, ub)
        return ((min(along), min(across), min(za, zb)),
                (max(along), max(across), max(za, zb)))

    def to_point(ua, va, za):
        return to_world(ua, va, ua, va, za, za)[0]

    return u0, u1, v0, v1, to_world, to_point


def place(axis, front):
    """-> (u, v) -> world, for a landmark whose street runs along `axis`.

    `u` runs along the street and `v` crosses it, growing toward `front`, which is
    the face the vendor's stair and awning stand on.  Authoring a candidate as an
    axis plus a facing, rather than as a rotated corner pair, is what keeps the
    table in `landmarks()` readable from both ends of an arm.
    """
    if axis == 'x':
        return lambda u, v: (u, front * v)
    return lambda u, v: (front * v, u)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', default='zig-out/map-dev/japanDM/japanDM-boxes.json')
    ap.add_argument('--until', default='lantern_court,roof_mast',
                    help='comma-separated brush prefixes; the manifest is cut at the '
                         'first brush the landmarks make, which is the scene as they '
                         'saw it')
    ap.add_argument('--conflicts', metavar='PREFIXES',
                    help='instead of searching, report every solid in the FULL '
                         'manifest standing inside a brush named by one of these')
    ap.add_argument('--step', type=int, default=20)
    ap.add_argument('--limit', type=int, default=940)
    ap.add_argument('--body', default='300x160,280x150,240x140')
    ap.add_argument('--stair', type=float, default=104.0)
    ap.add_argument('--tall', type=float, default=216.0)
    ap.add_argument('--z', type=float, default=CONSTS['T1'])
    ap.add_argument('--mast', action='store_true')
    ap.add_argument('--sites',
                    help='semicolon-separated axis,front,x0,y0,x1,y1; report each one '
                         'against the cut scene with exactly the keep-out '
                         '`landmarks()` will ask about, so the site a search offered '
                         'and the site that gets built are checked by one statement')
    ap.add_argument('--margin', type=float, default=8.0,
                    help='how much wider than its own deck plate a block asks to be '
                         '(default 8, which is what `landmarks()` uses)')
    args = ap.parse_args()

    if args.sites:
        scene = Scene(args.manifest, args.until)
        print('manifest %s cut before %r: %d boxes, %d solid; margin %g, stair %g, '
              'tall %g' % (args.manifest, args.until, len(scene.boxes), len(scene.solid),
                           args.margin, args.stair, args.tall))
        for one in args.sites.split(';'):
            if not one.strip():
                continue
            axis, front, x0, y0, x1, y1 = one.split(',')
            front = int(front)
            rect = ((float(x0), float(y0), args.z), (float(x1), float(y1), args.z))
            u0, u1, v0, v1, W, _P = place_frame(axis, front, rect)
            low, high = W(u0 - args.margin, v0 - args.margin, u1 + args.margin,
                          v1 + args.stair, args.z, args.z + args.tall)
            reasons = scene.why_not(low, high)
            centre = ((float(x0) + float(x1)) / 2.0, (float(y0) + float(y1)) / 2.0, args.z)
            print('  %s front %+d %s -> %s  keepout %s -> %s  %s  seen by %s'
                  % (axis, front, [round(v) for v in rect[0][:2]],
                     [round(v) for v in rect[1][:2]], [round(v) for v in low[:2]],
                     [round(v) for v in high[:2]],
                     'CLEAR' if not reasons else 'NO: ' + '; '.join(reasons),
                     seen_by(scene.spawns_all, centre)))
        return

    if args.conflicts:
        scene = Scene(args.manifest)
        prefixes = tuple(one.strip() for one in args.conflicts.split(','))
        # The builder's own exemption list, read from the builder rather than copied
        # here, because a copy of it is a second truth about what trim is.
        trim_suffixes = tuple(literal_tables(BUILDER).get('TRIM', ()))
        mine = [b for b in scene.boxes if b['name'].startswith(prefixes)]
        print('%d landmark brush(es) in %d' % (len(mine), len(scene.boxes)))
        bad = 0
        trim = 0
        for one in mine:
            for other in scene.solid:
                if other['name'].startswith(prefixes):
                    continue
                lo, hi = one['low'], one['high']
                olo, ohi = other['low'], other['high']
                if ohi[2] <= lo[2] + 2.0 or olo[2] >= hi[2] - 2.0:
                    continue
                if (olo[0] < hi[0] and ohi[0] > lo[0] and olo[1] < hi[1]
                        and ohi[1] > lo[1]):
                    # A court's paving band running under a pushcart or into the base
                    # of a bridge pier is the paving doing its job, and the builder
                    # itself exempts those suffixes for the same reason.  Counting them
                    # as conflicts would make this gate disagree with the audit it is
                    # meant to preview, so they are tallied apart and the gate reads the
                    # structural number only.
                    if one['name'].endswith(trim_suffixes):
                        trim += 1
                        print('  trim: %s shares %s' % (one['name'], other['name']))
                        continue
                    bad += 1
                    print('  %s %s..%s intrudes on %s %s..%s'
                          % (one['name'], [round(v) for v in lo], [round(v) for v in hi],
                             other['name'], [round(v) for v in olo],
                             [round(v) for v in ohi]))
        print('%d structural conflict(s), %d trim piece(s) sharing a host' % (bad, trim))
        return

    scene = Scene(args.manifest, args.until)
    print('manifest %s cut before %r: %d boxes, %d solid'
          % (args.manifest, args.until, len(scene.boxes), len(scene.solid)))

    bodies = [(float(w), float(h)) for w, h in
              (one.lower().split('x') for one in args.body.split(','))]
    found = []
    for axis in ('x', 'y'):
        for front in (1, -1):
            map_uv = place(axis, front)
            for a0 in range(-args.limit, args.limit + 1, args.step):
                for b0 in range(-args.limit, args.limit + 1, args.step):
                    for (u_span, v_body) in bodies:
                        # `b0` is the *back* edge of the body; the front and the
                        # stair it stands in front of grow toward +v.
                        body = aabb([map_uv(a0, b0), map_uv(a0 + u_span, b0 + v_body)],
                                    args.z, args.z + args.tall)
                        whole = aabb([map_uv(a0, b0),
                                      map_uv(a0 + u_span, b0 + v_body + args.stair)],
                                     args.z, args.z + args.tall)
                        # Nothing of a landmark may stand past the tower-front
                        # line: `verify` charges a brush that crosses it whatever
                        # it is, and a rect whose stair disappears into the wall is
                        # a site the search should never have offered.
                        if max(abs(whole[0][0]), abs(whole[0][1]),
                               abs(whole[1][0]), abs(whole[1][1])) > FACE - 8:
                            continue
                        reasons = scene.why_not(whole[0], whole[1])
                        if reasons:
                            continue
                        if not scene.floor_at(whole[0], whole[1], args.z):
                            continue
                        centre = ((body[0][0] + body[1][0]) / 2.0,
                                  (body[0][1] + body[1][1]) / 2.0, args.z)
                        found.append((-len(seen_by(scene.spawns_all, centre)),
                                      axis, front, a0, b0, u_span, v_body, body, whole))
    found.sort()
    print('T%g vendor blocks: %d site(s)' % (args.z / CONSTS['T1'], len(found)))
    shown = set()
    for one in found:
        key = (one[1], one[2], round(one[7][0][0] / 200), round(one[7][0][1] / 200))
        if key in shown:
            continue
        shown.add(key)
        if len(shown) > 16:
            break
        centre = ((one[7][0][0] + one[7][1][0]) / 2.0, (one[7][0][1] + one[7][1][1]) / 2.0,
                  args.z)
        print('   axis %s front %+d  body %s -> %s  seen by %s'
              % (one[1], one[2], [round(v) for v in one[7][0]],
                 [round(v) for v in one[7][1]], seen_by(scene.spawns_all, centre)))

    if args.mast:
        print('--- roof mast: 120x120 plinth, 384 of air, on a roof plate ---')
        sites = []
        for mx in range(-args.limit, args.limit + 1, 40):
            for my in range(-args.limit, args.limit + 1, 40):
                low, high = (mx - 60.0, my - 60.0, float(CONSTS['T2'])), \
                            (mx + 60.0, my + 60.0, CONSTS['T2'] + 384.0)
                reasons = scene.why_not(low, high)
                if reasons:
                    continue
                sites.append((-len(seen_by(scene.spawns_all, (mx, my, CONSTS['T2']))),
                              mx, my,
                              seen_by(scene.spawns_all, (mx, my, CONSTS['T2']))))
        sites.sort()
        print('   %d site(s), best seen first:' % len(sites))
        for one in sites[:14]:
            print('      centre %5d,%5d  seen by %s' % (one[1], one[2], one[3]))

    print('--- T0 lantern posts: 40x40, 288 of air, on the plaza floor ---')
    for (px, py) in ((-384, -224), (384, -224), (384, 224), (-384, 224),
                     (-224, -224), (224, -224), (224, 224), (-224, 224)):
        low, high = (px - 20.0, py - 20.0, float(CONSTS['T0'])), \
                    (px + 20.0, py + 20.0, CONSTS['T0'] + 288.0)
        reasons = scene.why_not(low, high, need_floor=False)
        print('   post %4d,%4d %s %s' % (px, py, 'OK  ' if not reasons else 'NO  ',
                                         '; '.join(reasons)))


if __name__ == '__main__':
    main()
