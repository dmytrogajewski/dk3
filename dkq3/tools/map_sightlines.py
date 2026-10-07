#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Measure what a deathmatch map actually shows the players who can stand in it.

`map_author.audit` answers one visibility question — can one spawn see another —
using the brushes it has in memory. This tool answers the rest, from the exported
`.map` a compile will consume: how many long clear lines the level offers, where
they run, whether any of them passes close enough to a spawn to make that spawn
a sniper's target, and whether a spawn can already see a weapon or an armour.

Nothing here is a compiler substitute: it ignores VIS clusters and light. It is a
stand-in for a player standing at eye height on a real floor, and it is cheap
enough to run after every geometry change instead of after a twenty-minute light
pass.

Method:

* solid brushes come from worldspawn, minus the shaders whose own surfaceparms
  make them empty space (`trigger`, `nonsolid`, `hint` -- not `sky`, which is
  solid here by the shipped game's own convention);
* walkable samples come from upward-facing brush faces on a grid: one eye point
  per cell per distinct floor height, kept only with real headroom above it, so
  the probe never measures a line no player can occupy;
* from each eye point, `--directions` horizontal rays are cast to `--reach`;
  a ray's clear length is the distance to the first solid surface;
* a clear line longer than a threshold is a sightline;
* a spawn is exposed when some *other* walkable eye point further away than
  `--min-range` already has a clear shot at it, and an item is stranded when no
  walkable eye point is within a body's reach of it.

Eye height, floor and headroom offsets are the same player-box numbers
`map_author.py` audits with (q_shared.h PLAYER_MINS/MAXS, PERSPECTIVE_HEIGHT).
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import importlib.util
import json
import math
from pathlib import Path
import re
import sys

import map_materials
import quake_map

TOKEN = re.compile(r'\{|\}|\((?:[^()]*)\)|"(?:[^"\\]|\\.)*"|[^{}"\s]+')
EYE_ABOVE_FLOOR = 22.0        # feet + 22 (PERSPECTIVE_HEIGHT), which is origin - 2
HEAD_ROOM = 56.0              # feet to ceiling a standing player needs
MIN_UP_NZ = math.sqrt(0.5)    # steepest surface the engine lets you stand on (45 deg)
EDGE_MARGIN = 8.0             # how far inside a face a STANDING foot must sit
# A standing sample is kept away from a face's edge so an eye is never sampled
# inside a wall. A foot on a walk does not have that luxury: japanDM's stairs are
# treads 19 units deep, and an 8-unit margin on each side leaves a 3-unit band a
# 12-unit probe almost always misses -- so the walk probe is allowed to stand on
# the face right up to its edge, which is what a foot does on a real step.
WALK_STEP = 18.0              # the engine's step-up: what a foot actually clears
STEP_DOWN = 64.0              # how far a foot may be dropped without a jump
PROBE_STEP = 12.0             # how finely a walk is tested along its length
REACH_XY = 80.0               # sampling half-cell 48 + player box 15 + item box 16
# Two footfalls further apart than this are not one step. Samples sit on a grid
# and floor edges do not, so a grid can miss the whole band between one floor's
# last sample and the next floor's first: japanDM's footbridge and the deck it
# joins were both walkable and both sampled, but not neighbours, because the
# standing margin ate the one column of cells that joined them. A link may
# therefore span a step and a half, with `stepped` proving the ground under all
# of it, which is also what lets a stair flight cross a cell column or two.
MAX_LINK_FACTOR = 2.2
REACH_BELOW, REACH_ABOVE = 16.0, 56.0     # a standing player's box, feet to crown

# What a ray may cross when no materials table was offered: substrings matched
# against the shader name, standing in for `map_materials.NON_SOLID_PARMS`.  With
# a table -- which is how the pipeline runs it -- `non_solid_shaders` reads the
# real answer off the surfaceparms instead.
DEFAULT_NON_SOLID = ('trigger', 'hint', 'nonsolid')


def read_map(path, non_solid=()):
    """-> a `quake_map.MapDoc` read back from the text a writer emitted.

    Only what visibility needs is rebuilt: outward planes per face, one brush per
    brush block, and the entity epairs. Face rings are the writer's defining
    triple, which is all `quake_map.span` reads.
    """
    text = re.sub(r'//[^\n]*', '', Path(path).read_text(encoding='utf-8'))
    tokens = TOKEN.findall(text)
    position = 0
    non_solid = set(non_solid)

    def triple(token):
        numbers = [float(value) for value in token[1:-1].split()]
        if len(numbers) != 3:
            raise ValueError('%s: a plane needs three coordinates' % token)
        return tuple(numbers)

    def parse_brush():
        nonlocal position
        position += 1                                       # '{'
        faces = []
        while tokens[position] != '}':
            definition = tuple(triple(tokens[position + offset]) for offset in range(3))
            shader = tokens[position + 3]
            numbers = tokens[position + 4:position + 12]
            if len(numbers) != 8:
                raise ValueError('%s: face is missing its texture projection' % shader)
            normal, dist, _, _ = quake_map.plane_from_points(definition)
            if normal is None:
                raise ValueError('%s: degenerate face plane' % shader)
            style = quake_map.FaceStyle(shader=shader,
                                        scale=(float(numbers[3]), float(numbers[4])),
                                        detail=bool(int(float(numbers[5])) & quake_map.C_DETAIL),
                                        solid=not any(part in shader for part in non_solid))
            faces.append(quake_map.Face(points=definition, definition=definition, normal=normal,
                                        dist=dist, style=style))
            position += 12
        position += 1                                       # '}'
        return quake_map.Brush(faces=faces, source=shader)

    def parse_entity(index):
        nonlocal position
        position += 1                                       # '{'
        keys, brushes = {}, []
        while tokens[position] != '}':
            token = tokens[position]
            if token == '{':
                brushes.append(parse_brush())
            elif token.startswith('"'):
                keys[token[1:-1]] = tokens[position + 1][1:-1]
                position += 2
            else:
                raise ValueError('entity %d: unexpected %r' % (index, token))
        position += 1                                       # '}'
        label = '%s %d' % (keys.get('classname', 'brushes'), index)
        return quake_map.Entity(keys=keys, brushes=brushes, source=label)

    entities = []
    while position < len(tokens):
        if tokens[position] != '{':
            raise ValueError('unexpected %r between entities' % tokens[position])
        entities.append(parse_entity(len(entities)))
    if not entities or entities[0].classname != 'worldspawn':
        raise ValueError('%s: entity 0 is not worldspawn' % path)
    return quake_map.MapDoc(entities=entities)


def non_solid_shaders(table_path, parms=map_materials.NON_SOLID_PARMS):
    """-> the shader names a ray may cross and nobody can stand on, from the map table.

    The answer is the surfaceparms the generated shader carries, not a guess at
    the material's kind: japanDM declared kind 'trigger' and the probe still cast
    its body rays through what the compiler had made a solid brush, because the
    block was filed under the common name while the map wrote the table key and
    q3map2 hands a name it cannot find a default SOLID contents.  Probe and
    compiler have to agree, or the probe measures a map nobody will play.
    """
    spec = importlib.util.spec_from_file_location('dk3_map_sightline_table', str(Path(table_path).resolve()))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return map_materials.non_solid_names(module.MATERIALS, parms)


class Index:
    """Solid brushes on a uniform grid, so a ray only meets the brushes near it."""

    def __init__(self, brushes, cell=128.0):
        self.brushes = list(brushes)
        self.cell = float(cell)
        self.boxes = [brush.bounds() for brush in self.brushes]
        self.grid = defaultdict(list)
        for position, (mins, maxs) in enumerate(self.boxes):
            corner = [int(math.floor(value / self.cell)) for value in mins]
            other = [int(math.floor(value / self.cell)) for value in maxs]
            for x in range(corner[0], other[0] + 1):
                for y in range(corner[1], other[1] + 1):
                    for z in range(corner[2], other[2] + 1):
                        self.grid[(x, y, z)].append(position)
        # Walkable surfaces are the faces a foot can rest on, which is anything no
        # steeper than 45 degrees -- so a ramp's top counts, not only a flat top.
        # The plane is kept rather than a height, because on a slope the surface
        # under a foot depends on where along the slope that foot is. Every face is
        # also remembered once, whole, so `eye_positions` can offer a floor that is
        # too small for a grid line a standing spot of its own.
        self.floors = defaultdict(list)
        self.walk_faces = []
        for position, brush in enumerate(self.brushes):
            for face in brush.faces:
                nx, ny, nz = face.normal
                if nz < MIN_UP_NZ:
                    continue
                xs = [point[0] for point in face.points]
                ys = [point[1] for point in face.points]
                bounds = (min(xs), min(ys), max(xs), max(ys), face.dist, nx, ny, nz)
                self.walk_faces.append(bounds)
                corner = (int(math.floor(bounds[0] / self.cell)), int(math.floor(bounds[1] / self.cell)))
                other = (int(math.floor(bounds[2] / self.cell)), int(math.floor(bounds[3] / self.cell)))
                for x in range(corner[0], other[0] + 1):
                    for y in range(corner[1], other[1] + 1):
                        self.floors[(x, y)].append((position, bounds))

    def candidates(self, start, end):
        """-> the brush positions whose grid cell the segment passes through."""
        delta = quake_map.sub(end, start)
        steps = max(1, int(quake_map.length(delta) / (self.cell * 0.5)) + 1)
        seen = set()
        for step in range(steps + 1):
            fraction = step / float(steps)
            point = tuple(start[axis] + delta[axis] * fraction for axis in range(3))
            cell = tuple(int(math.floor(value / self.cell)) for value in point)
            seen.update(self.grid.get(cell, ()))
        return seen

    def cast(self, start, end):
        """-> (fraction of the way to the first solid surface, brush position or None)."""
        best, winner = 1.0, None
        for position in self.candidates(start, end):
            crossed = quake_map.span(self.brushes[position], start, end)
            if crossed is None:
                continue
            entry = crossed[0]
            if entry < best:
                best, winner = max(entry, 0.0), position
        return best, winner

    def clear(self, start, end):
        return self.cast(start, end)[1] is None

    def floor_heights(self, x, y, reach=0.0):
        """-> the distinct walkable-surface heights under (x, y).

        `reach` widens each face by that much before the test, which is how a
        walking probe gets to stand on a tread's last millimetre. It must not be
        used where headroom is judged, or the probe would sample eyes inside
        walls.  A horizontal face is at its plane distance; a sloped one is the plane read
        at the foot, `(dist - x*nx - y*ny) / nz`. Normals are unit, so that
        division is a height and nothing else (`quake_map.plane_from_points`).
        """
        cell = (int(math.floor(x / self.cell)), int(math.floor(y / self.cell)))
        found = []
        for _, (x0, y0, x1, y1, dist, nx, ny, nz) in self.floors.get(cell, ()):
            if (x0 + EDGE_MARGIN - reach < x < x1 - EDGE_MARGIN + reach
                    and y0 + EDGE_MARGIN - reach < y < y1 - EDGE_MARGIN + reach):
                found.append(dist if nz > 0.999 else (dist - x * nx - y * ny) / nz)
        found.sort()
        # Surfaces within eight units of each other are one surface to stand on,
        # and the foot rests on the TOP of them: japanDM paves its street with
        # two-unit grate plates, four-unit pool frames and six-unit light strips,
        # and a probe that kept the lower one asked for headroom starting inside
        # the plate and reported the plate's own footprint as unstandable. Same
        # for a ramp's foot, where the wedge is a few units above the deck it
        # leaves from -- keeping the deck height lost the first tread's worth of
        # samples and severed the ramp from the floor it starts on.
        distinct = []
        for height in found:
            if not distinct or height - distinct[-1] > 8.0:
                distinct.append(height)
            else:
                distinct[-1] = height
        return distinct


def eye_positions(index, bounds, grid=96.0, head_room=HEAD_ROOM):
    """-> [(x, y, eye_z, floor_z)] a standing player could occupy, one per cell/floor.

    A grid is what keeps the cost honest, and a grid is also what misses floors:
    japanDM's stair treads are 19 units deep, so a 48-unit grid line lands on one
    by luck and a flight of twelve read as a bare roof with a 192-unit cliff at the
    top of it. So every walkable face is asked for a place to stand as well: the
    first grid point inside its standing band if it holds one (the grid pass finds
    those anyway, and the set dedupes them), and its own centre if it does not.
    Either way a floor the level offers is a floor the probe can be standing on.
    """
    (min_x, min_y, min_z), (max_x, max_y, max_z) = bounds
    first_x, first_y = min_x + grid * 0.5, min_y + grid * 0.5
    found, seen = [], set()

    def stand(x, y, floor):
        if floor < min_z - 1.0 or floor > max_z:
            return
        key = (round(x, 3), round(y, 3), round(floor, 3))
        if key in seen:
            return
        fraction, _ = index.cast((x, y, floor + 1.0), (x, y, floor + 1.0 + head_room))
        if fraction < 1.0:
            return                                    # no headroom: not a place to stand
        seen.add(key)
        found.append((x, y, floor + EYE_ABOVE_FLOOR, floor))

    x = first_x
    while x < max_x:
        y = first_y
        while y < max_y:
            for floor in index.floor_heights(x, y):
                stand(x, y, floor)
            y += grid
        x += grid

    for x0, y0, x1, y1, dist, nx, ny, nz in index.walk_faces:
        near, far = x0 + EDGE_MARGIN, x1 - EDGE_MARGIN
        deep, wider = y0 + EDGE_MARGIN, y1 - EDGE_MARGIN
        if far <= near or wider <= deep:
            continue                                  # the face is narrower than a foot
        point_x = first_x + math.ceil((near - first_x) / grid) * grid
        point_y = first_y + math.ceil((deep - first_y) / grid) * grid
        if point_x <= far and point_y <= wider:
            height = dist if nz > 0.999 else (dist - point_x * nx - point_y * ny) / nz
            stand(point_x, point_y, height)
        else:
            point_x, point_y = (near + far) / 2.0, (deep + wider) / 2.0
            height = dist if nz > 0.999 else (dist - point_x * nx - point_y * ny) / nz
            stand(point_x, point_y, height)
        # A floor's EDGE is where the route to it lives: the strip where a stair
        # foot meets a roof, where a ramp meets the street it leaves, the tread a
        # grid line just misses. Those are the parts of a plane a grid has no
        # reason to touch, so the standing band's own corners are asked for a
        # place to stand as well -- japanDM's market ramp has a foot 16 units deep
        # against a wall face, and nothing on any 48-unit grid stands in it.
        for corner_x, corner_y in ((near, deep), (far, deep), (near, wider), (far, wider)):
            stand(corner_x, corner_y, dist if nz > 0.999
                  else (dist - corner_x * nx - corner_y * ny) / nz)
    return found


def stepped(index, start, end, floor, target):
    """-> whether ground between two samples can be walked, ending on `target`.

    One point per cell is what a grid can afford, and a staircase pays for it: the
    cell that holds a flight samples whichever tread its point lands on, so the
    last tread the grid sees can stand two or three rises below the floor it hands
    over to. Measured cell to cell that is a cliff -- japanDM's monorail stairs
    read as a 32-unit wall and the whole upper tier, two pickups and a spawn
    included, came out unreachable while a player walks the flight in six easy
    steps. Walking is not a jump between cells, it is a sequence of small steps,
    so this asks the question the physics asks: every `PROBE_STEP` units, is there
    a surface no more than one `WALK_STEP` above the one you are standing on, with
    the foot allowed to rest on the very edge of a face (`reach` above).

    The probe carries a SET of heights rather than one, because a footfall often
    has more than one surface to choose from and the right choice is the one that
    gets you to `target`. japanDM's north roof is one plane at 512 crossed by the
    foot of a stair whose first tread stands 16 proud of it: a probe that always
    took the highest option ended that crossing three rises up and refused a link
    any player walks by stepping around the stair, and the whole roof tier lost its
    reachability on paper only.

    The walk also has to arrive: `abs(target - current) <= WALK_STEP` on the last
    footfall. Without that test every pair of cells with air between them linked
    and the probe reported the lid of the map shell as walkable. The ground has to
    stay under the feet the whole way as well: `WALK_STEP` up, `STEP_DOWN` down,
    and no further. A kerb is a step; a ledge is a decision the probe does not
    make for the player, because counting the way down would hand the report every
    awning, hedge and skylight top a jump-off-the-roof lands on, and a position a
    player cannot hold and return from is not a position. Routes that need a jump,
    a rocket jump or a strafe jump are therefore not counted either:
    `dkbsp`/AAS navigation is where those get proven, not here.
    """
    length = math.hypot(end[0] - start[0], end[1] - start[1])
    steps = max(1, int(length / PROBE_STEP) + 1)
    levels = {floor}
    for step in range(1, steps + 1):
        fraction = step / float(steps)
        point = (start[0] + (end[0] - start[0]) * fraction,
                 start[1] + (end[1] - start[1]) * fraction)
        under = index.floor_heights(*point, reach=EDGE_MARGIN)
        options = set()
        for level in levels:
            options.update(height for height in under
                           if level - STEP_DOWN <= height <= level + WALK_STEP)
        if not options:
            return False
        levels = options
    return any(abs(target - level) <= WALK_STEP for level in levels)


def reachable(index, samples, eyes, grid=96.0, max_step=WALK_STEP):
    """-> the samples a player who started at a spawn can walk to.

    Sampling walkable faces finds every top in the level, including the lid of the
    shell that seals it, so "is there a floor and headroom" is not enough: the
    walkable set is the one connected to a spawn. Neighbouring cells link when a
    step between them is at most `max_step` high and a player's body clears the
    gap, or when the ground between them can be walked a step at a time and ends
    on the far floor (`stepped`) -- how a flight of stairs and a 45-degree ramp get
    counted. A cell reachable only by falling, jumping, rocket-jumping or flying is
    not counted: those routes end somewhere a player cannot hold or cannot return
    from, and a vantage nobody can keep is not a vantage.
    """
    cells = {}
    for position, (x, y, _eye, floor) in enumerate(samples):
        cells.setdefault((int(math.floor(x / grid)), int(math.floor(y / grid))), []).append(position)
    reach = int(math.ceil(MAX_LINK_FACTOR))       # how many cell indices one step spans

    def link(first, second):
        x0, y0, _eye0, floor0 = samples[first]
        x1, y1, _eye1, floor1 = samples[second]
        step = math.hypot(x1 - x0, y1 - y0)
        if step > grid * MAX_LINK_FACTOR:
            return False
        # Any step that is long, or high, or both has to have ground under every
        # footfall of it; a step that is neither only has to have a body that fits.
        if (abs(floor1 - floor0) > max_step or step > grid * 1.05) \
                and not stepped(index, (x0, y0), (x1, y1), floor0, floor1):
            return False
        walk = max(floor0, floor1) + 2.0 + 24.0            # the body, not the eye
        return index.clear((x0, y0, walk), (x1, y1, walk))

    seeds = []
    for _name, eye in eyes:
        centre = (int(math.floor(eye[0] / grid)), int(math.floor(eye[1] / grid)))
        landing = eye[2] - EYE_ABOVE_FLOOR
        best, best_distance = None, grid * MAX_LINK_FACTOR
        for dx in (-2, -1, 0, 1, 2):
            for dy in (-2, -1, 0, 1, 2):
                for position in cells.get((centre[0] + dx, centre[1] + dy), ()):
                    x, y, _eye, floor = samples[position]
                    distance = math.hypot(x - eye[0], y - eye[1])
                    if distance < best_distance and abs(floor - landing) <= max_step:
                        best, best_distance = position, distance
        if best is not None:
            seeds.append(best)
    seen, queue = set(seeds), list(seeds)
    while queue:
        position = queue.pop()
        x, y, _eye, _floor = samples[position]
        centre = (int(math.floor(x / grid)), int(math.floor(y / grid)))
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            for offset in range(1, reach + 1):
                for neighbour in cells.get((centre[0] + dx * offset, centre[1] + dy * offset), ()):
                    if neighbour in seen or not link(position, neighbour):
                        continue
                    seen.add(neighbour)
                    queue.append(neighbour)
    return [samples[position] for position in sorted(seen)]


def sightlines(index, samples, directions=16, reach=2048.0, thresholds=(640.0, 1024.0, 1536.0)):
    """-> (segments, rays, per-threshold counts) from every sample in every heading."""
    segments, rays, counts = [], 0, {threshold: 0 for threshold in thresholds}
    for x, y, eye, floor in samples:
        for step in range(directions):
            yaw = 2.0 * math.pi * step / float(directions)
            start = (x, y, eye)
            end = (x + reach * math.cos(yaw), y + reach * math.sin(yaw), eye)
            fraction, _ = index.cast(start, end)
            rays += 1
            if fraction <= 0.0:
                continue
            length = fraction * reach
            for threshold in thresholds:
                if length >= threshold:
                    counts[threshold] += 1
            if length >= min(thresholds):
                end_point = tuple(start[axis] + (end[axis] - start[axis]) * fraction
                                  for axis in range(3))
                segments.append(dict(start=[round(value, 1) for value in start],
                                     end=[round(value, 1) for value in end_point],
                                     floor=round(floor, 1), heading=round(math.degrees(yaw)),
                                     length=round(length, 1)))
    return segments, rays, counts


def distance_to_segment(point, start, end):
    """-> (closest approach, the closest point) between a point and a segment."""
    delta = quake_map.sub(end, start)
    squared = sum(component * component for component in delta)
    if squared <= 0.0:
        return quake_map.length(quake_map.sub(point, start)), start
    fraction = sum((point[axis] - start[axis]) * delta[axis] for axis in range(3)) / squared
    fraction = max(0.0, min(1.0, fraction))
    closest = tuple(start[axis] + delta[axis] * fraction for axis in range(3))
    return quake_map.length(quake_map.sub(point, closest)), closest


def exposures(index, eyes, samples, min_range=640.0):
    """-> which spawn points somebody standing well away can already shoot, and from where.

    Exposure is a range question: a spawn needs its own cover against a player who
    arrives from the far end of a street, not against one standing beside it. The
    first cut of this measured something else -- it took any long clear line whose
    *closest approach* to a spawn was within a radius and cast from that nearest
    point, which by construction sits no further away than the radius, so on a map
    of streets almost every spawn failed it and cover was invisible to the result.
    Here every walkable eye point is cast at every spawn eye and only hits beyond
    `min_range` count, which is what a spawn's walls are for.
    """
    found = {}
    for name, eye in eyes:
        hits = []
        for x, y, vantage_eye, _floor in samples:
            range_ = math.hypot(x - eye[0], y - eye[1])
            if range_ < min_range:
                continue
            if index.clear((x, y, vantage_eye), eye):
                hits.append((range_, (x, y, vantage_eye)))
        if hits:
            hits.sort(reverse=True)
            found[name] = dict(vantages=len(hits),
                               worst=[dict(vantage=[round(value, 1) for value in point],
                                           range=round(hit, 1)) for hit, point in hits[:3]])
    return found


def within_reach(samples, position):
    """-> whether a player standing on one of these floors could touch `position`.

    Generous by one sampling cell, deliberately: eyes are found on a grid, so the
    nearest sample to the one spot a player would actually stand on is up to half a
    cell away. What this cannot forgive is a different floor -- an item on the deck
    is out of reach from the street however close it looks in plan.
    """
    x, y, z = position
    return any(abs(sample[0] - x) <= REACH_XY and abs(sample[1] - y) <= REACH_XY
               and sample[3] - REACH_BELOW <= z <= sample[3] + REACH_ABOVE
               for sample in samples)


def probe(document, non_solid=(), grid=96.0, directions=16, reach=2048.0,
          thresholds=(640.0, 1024.0, 1536.0), min_range=640.0, head_room=HEAD_ROOM):
    """-> the whole measurement: samples, lines, spawn exposure, item lines."""
    solid = [brush for entity in document.entities for brush in entity.brushes
             if any(face.style.solid for face in brush.faces)]
    solid = [brush for brush in solid if any(face.style.solid for face in brush.faces)]
    index = Index(solid, cell=max(grid, 96.0))
    bounds = document.bounds()
    every = eye_positions(index, bounds, grid=grid, head_room=head_room)
    eyes = []
    for entity in document.entities:
        origin = entity.keys.get('origin')
        if not origin or entity.classname == 'worldspawn':
            continue
        position = tuple(float(value) for value in origin.split())
        if entity.classname.startswith('info_player_'):
            eyes.append((entity.source or entity.classname,
                         (position[0], position[1], position[2] - 2.0)))
    spawns = dict(eyes)
    samples = reachable(index, every, eyes, grid=grid)
    segments, rays, counts = sightlines(index, samples, directions=directions, reach=reach,
                                        thresholds=thresholds)
    items = []
    for entity in document.entities:
        origin = entity.keys.get('origin')
        if not origin or not entity.classname.startswith(('weapon_', 'ammo_', 'item_')):
            continue
        position = tuple(float(value) for value in origin.split())
        items.append((entity.classname + ' ' + entity.source,
                      (position[0], position[1], position[2] + 8.0)))
    pairs = []
    for first, first_eye in spawns.items():
        for second, second_eye in spawns.items():
            if second <= first:
                continue
            if index.clear(first_eye, second_eye):
                pairs.append('%s<->%s' % (first, second))
    exposed_items = []
    for first, first_eye in spawns.items():
        for name, position in items:
            if index.clear(first_eye, position):
                exposed_items.append('%s sees %s' % (first, name))
    seen = exposures(index, list(spawns.items()), samples, min_range=min_range)
    stranded = [name for name, position in items if not within_reach(samples, position)]
    tiers = defaultdict(int)
    for _x, _y, _eye, floor in samples:
        tiers['%d' % (int(floor) // 64 * 64)] += 1
    longest = sorted(segments, key=lambda segment: -segment['length'])[:10]
    return dict(map=str(bounds), bounds=[list(bounds[0]), list(bounds[1])],
                solid_brushes=len(solid), samples=len(samples), samples_considered=len(every),
                unreachable_samples=len(every) - len(samples), rays=rays,
                thresholds={('%g' % threshold): counts[threshold] for threshold in sorted(thresholds)},
                sightlines=len(segments), longest=longest,
                spawns=len(spawns), spawn_pairs_visible=sorted(pairs),
                spawn_sees_item=sorted(exposed_items),
                exposed_spawns={name: hits for name, hits in sorted(seen.items())},
                exposed_spawn_count=len(seen),
                min_range=min_range, stranded_items=sorted(stranded),
                walkable_tiers=dict(sorted(tiers.items(), key=lambda entry: int(entry[0]))),
                items=len(items))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--map', type=Path, required=True, help='exported .map to measure')
    parser.add_argument('--materials', type=Path, default=None,
                        help='the map materials.py, to learn which shaders are see-through')
    parser.add_argument('--non-solid', default=None, help='comma list of shader paths a ray may cross')
    parser.add_argument('--grid', type=float, default=96.0)
    parser.add_argument('--directions', type=int, default=16)
    parser.add_argument('--reach', type=float, default=2048.0)
    parser.add_argument('--thresholds', default='640,1024,1536')
    parser.add_argument('--min-range', type=float, default=640.0,
                        help='how far away a shooter must stand for exposure to count')
    parser.add_argument('--head-room', type=float, default=HEAD_ROOM)
    parser.add_argument('--report', type=Path, default=None)
    parser.add_argument('--max-exposed', type=int, default=0,
                        help='fail above this many spawns exposed to a long sightline')
    parser.add_argument('--items-visible', action='store_true',
                        help='also fail when a spawn already sees a pickup')
    arguments = parser.parse_args(argv)
    if arguments.non_solid:
        non_solid = [name.strip() for name in arguments.non_solid.split(',') if name.strip()]
    elif arguments.materials:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        non_solid = non_solid_shaders(arguments.materials)
    else:
        non_solid = list(DEFAULT_NON_SOLID)
    thresholds = sorted(float(value) for value in arguments.thresholds.split(','))
    document = read_map(arguments.map, non_solid)
    report = probe(document, grid=arguments.grid, directions=arguments.directions,
                   reach=arguments.reach, thresholds=thresholds, min_range=arguments.min_range,
                   head_room=arguments.head_room)
    report['non_solid'] = non_solid
    if arguments.report:
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        arguments.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('map-sightlines: %d solid brushes, %d walkable eye samples of %d, %d rays'
          % (report['solid_brushes'], report['samples'], report['samples_considered'],
             report['rays']))
    print('map-sightlines: sightlines %s (of %d clear lines)'
          % (json.dumps(report['thresholds']), report['sightlines']))
    for segment in report['longest'][:5]:
        print('  %6.0f u  heading %3d  %s -> %s'
              % (segment['length'], segment['heading'], segment['start'][:2], segment['end'][:2]))
    print('map-sightlines: walkable floors by height %s' % json.dumps(report['walkable_tiers']))
    print('map-sightlines: %d spawns, %d pairs in open sight, %d exposed beyond %g u'
          % (report['spawns'], len(report['spawn_pairs_visible']), report['exposed_spawn_count'],
             report['min_range']))
    for name, hits in sorted(report['exposed_spawns'].items()):
        print('  exposed %s: %d vantages, worst %s'
              % (name, hits['vantages'], '; '.join('%.0f u from %s'
                                                   % (hit['range'], hit['vantage'][:2])
                                                   for hit in hits['worst'])))
    if report['stranded_items']:
        print('map-sightlines: %d items out of reach of any walkable floor: %s'
              % (len(report['stranded_items']), ', '.join(report['stranded_items'])))
    if report['spawn_sees_item']:
        print('map-sightlines: %d spawn-to-item lines, e.g. %s'
              % (len(report['spawn_sees_item']), report['spawn_sees_item'][0]))
    problems = []
    if report['spawn_pairs_visible']:
        problems.append('%d spawn pairs with no cover' % len(report['spawn_pairs_visible']))
    if report['exposed_spawn_count'] > arguments.max_exposed:
        problems.append('%d spawns exposed to a long sightline (limit %d)'
                        % (report['exposed_spawn_count'], arguments.max_exposed))
    if arguments.items_visible and report['spawn_sees_item']:
        problems.append('%d spawn-to-item sightlines' % len(report['spawn_sees_item']))
    if report['stranded_items']:
        problems.append('%d items out of reach: %s'
                        % (len(report['stranded_items']), ', '.join(report['stranded_items'])))
    if problems:
        print('map-sightlines: %s' % '; '.join(problems), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print('map-sightlines: %s' % error, file=sys.stderr)
        sys.exit(1)
