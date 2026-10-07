#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Find where a sealed-looking map is actually open to the void.

q3map2 says `Entity leaked` and nothing else: GtkRadiant's q3map2 writes no
pointfile for this map, and the entity/brush pair it names is a light with no
brushes at all, so the message locates nothing. This tool answers the same
question the compiler asks -- is the empty space a player occupies connected to
the space outside every brush? -- and prints the path.

Method, and why it cannot lie about a hole:

* solid brushes come from worldspawn plus any brush entity, keeping only the
  shaders whose emitted surfaceparms leave them solid, which is the same set
  q3map2 puts in its base tree (`nonsolid`, `hint` and `trigger` brushes are
  empty space to it, and a `sky` surface is solid unless the shader says
  otherwise -- that distinction is the whole reason this tool exists);
* the world is sampled on a cell grid; a cell is *blocked* when its whole box
  touches a solid brush's bounds, so a free cell is a box of proven empty space;
* two adjacent free cells share a 2-cell box of empty space, so walking between
  their centres can never cross a brush. The walk is therefore sound: if this
  tool escapes to the grid boundary, the connection is real geometry, not a
  sampling artefact. The other direction is only approximate -- a gap narrower
  than `--step` is invisible here, so a clean report is evidence, not proof.

Rotated brushes are conservative here: a ramp blocks the cells its bounds touch,
which is more solid than it is. Nothing walkable hides behind that.
"""
from __future__ import annotations

import argparse
from collections import deque
import importlib.util
import json
from math import ceil
from pathlib import Path
import sys

import map_sightlines
import map_materials
import quake_map

NON_SOLID_PARMS = map_materials.NON_SOLID_PARMS


def nonsolid_shaders(table_path):
    """-> the shader names whose own surfaceparms make them empty space.

    Read from the table that generated the shader text, not from a guess at the
    shader name: a `sky` surface is solid in the shipped game's convention and
    nonsolid only if a tool put it that way.
    """
    spec = importlib.util.spec_from_file_location('dk3_map_leak_table', str(Path(table_path).resolve()))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return map_materials.non_solid_names(module.MATERIALS)


def solid_brushes(document, empty):
    """-> worldspawn and brush-entity brushes that are solid to the compiler."""
    out = []
    for entity in document.entities:
        for brush in entity.brushes:
            if any(face.style.shader in empty for face in brush.faces):
                continue
            if not any(face.style.solid for face in brush.faces):
                continue
            out.append(brush)
    return out


class Space:
    """The empty boxes of a cell grid, and the walk between them."""

    def __init__(self, brushes, step=32.0, pad=8.0):
        self.step = float(step)
        mins = [min(brush.bounds()[0][axis] for brush in brushes) for axis in range(3)]
        maxs = [max(brush.bounds()[1][axis] for brush in brushes) for axis in range(3)]
        self.origin = [mins[axis] - pad for axis in range(3)]
        self.size = [int(ceil((maxs[axis] - self.origin[axis] + pad) / self.step)) + 1
                     for axis in range(3)]
        self.blocked = bytearray(self.size[0] * self.size[1] * self.size[2])
        for brush in brushes:
            self._block(brush.bounds())
        self.brushes = brushes

    def _cell(self, point):
        return tuple(int((point[axis] - self.origin[axis]) / self.step) for axis in range(3))

    def _index(self, cell):
        return (cell[2] * self.size[1] + cell[1]) * self.size[0] + cell[0]

    def _block(self, bounds):
        """Mark every cell whose box touches this brush's bounds.

        No slack on the range: one cell of margin around every brush walls in the
        air a player stands in, because a floor brush 32 thick and a 32-unit cell
        share a plane, and the spawn point 24 above it lands inside the margin.
        """
        lo = [max(int((bounds[0][axis] - self.origin[axis]) / self.step), 0)
              for axis in range(3)]
        hi = [min(int((bounds[1][axis] - self.origin[axis]) / self.step), self.size[axis] - 1)
              for axis in range(3)]
        width = hi[0] - lo[0] + 1
        if width < 1 or hi[1] < lo[1] or hi[2] < lo[2]:
            return
        span = b'\x01' * width
        row = self.size[0]
        for z in range(lo[2], hi[2] + 1):
            for y in range(lo[1], hi[1] + 1):
                start = (z * self.size[1] + y) * row + lo[0]
                self.blocked[start:start + width] = span

    def free(self, cell):
        if any(cell[axis] < 0 or cell[axis] >= self.size[axis] for axis in range(3)):
            return False
        return not self.blocked[self._index(cell)]

    def point(self, cell):
        return tuple(self.origin[axis] + (cell[axis] + 0.5) * self.step for axis in range(3))

    def walk(self, seeds, on_boundary):
        """-> (escaped cell or None, path of cells, cells visited)."""
        seen = set()
        queue = deque()
        for seed in seeds:
            cell = self._cell(seed)
            if not self.free(cell):
                continue
            seen.add(cell)
            queue.append((cell, None))
        parents = {}
        visited = 0
        while queue:
            cell, parent = queue.popleft()
            visited += 1
            parents[cell] = parent
            if on_boundary(cell):
                path = []
                while cell is not None:
                    path.append(cell)
                    cell = parents[cell]
                return path[-1], list(reversed(path)), visited
            for axis in range(3):
                for delta in (-1, 1):
                    other = list(cell)
                    other[axis] += delta
                    other = tuple(other)
                    if other in seen or not self.free(other):
                        continue
                    seen.add(other)
                    queue.append((other, cell))
        return None, [], visited


def near(space, cell, radius=3):
    """-> the brushes around an escaped cell, nearest first: what to go and look at."""
    centre = space.point(cell)
    out = []
    for brush in space.brushes:
        mins, maxs = brush.bounds()
        distance = 0.0
        for axis in range(3):
            gap = max(mins[axis] - centre[axis], 0.0, centre[axis] - maxs[axis])
            distance += gap * gap
        out.append((distance ** 0.5, brush.source))
    out.sort()
    return out[:8]


def probe(map_path, materials, step=32.0, seeds=None):
    empty = nonsolid_shaders(materials) if materials else []
    document = map_sightlines.read_map(map_path, empty)
    brushes = solid_brushes(document, empty)
    space = Space(brushes, step=step)
    if not seeds:
        seeds = []
        for entity in document.entities:
            origin = entity.keys.get('origin')
            if origin and entity.classname.startswith('info_player_'):
                seeds.append(tuple(float(value) for value in origin.split()))
        if not seeds:
            seeds = [(0.0, 0.0, 0.0)]
    size = space.size
    escaped, path, visited = space.walk(seeds, lambda cell: 0 in (cell[0], cell[1], cell[2]) or
                                        cell[0] == size[0] - 1 or cell[1] == size[1] - 1 or
                                        cell[2] == size[2] - 1)
    return dict(map=str(map_path), step=space.step, cells=space.cells if hasattr(space, 'cells')
                else len(space.blocked), solid_brushes=len(brushes), empty_shaders=empty,
                seeds=len(seeds), cells_visited=visited,
                escaped=None if escaped is None else list(space.point(escaped)),
                path=[list(space.point(cell)) for cell in path],
                suspects=[] if escaped is None else [
                    dict(brush=source, distance=round(distance, 1))
                    for distance, source in near(space, escaped)])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--map', type=Path, required=True, help='exported .map to test')
    parser.add_argument('--materials', type=Path, default=None,
                        help='the map materials.py, to learn which shaders are empty space')
    parser.add_argument('--step', type=float, default=32.0, help='cell edge in map units')
    parser.add_argument('--seed', default=None,
                        help='fallback interior point "x y z" if the map has no spawns')
    parser.add_argument('--report', type=Path, default=None)
    arguments = parser.parse_args(argv)
    seeds = None
    if arguments.seed:
        seeds = [tuple(float(value) for value in arguments.seed.split())]
    report = probe(arguments.map, arguments.materials, step=arguments.step, seeds=seeds)
    if arguments.report:
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        arguments.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('map-leak: %d solid brushes, %d cells of %g, %d cells reached from %d spawns'
          % (report['solid_brushes'], report['cells'], report['step'], report['cells_visited'],
             report['seeds']))
    if report['escaped'] is None:
        print('map-leak: sealed at this resolution (a gap under %g units is not tested)'
              % report['step'])
        return 0
    print('map-leak: ESCAPES at %s -- %d steps of %g out'
          % (', '.join('%g' % value for value in report['escaped']), len(report['path']) - 1,
             report['step']))
    print('map-leak: path first/last %s -> %s' % (report['path'][0], report['path'][-1]))
    for suspect in report['suspects']:
        print('  %7.1f  %s' % (suspect['distance'], suspect['brush']))
    return 1


if __name__ == '__main__':
    sys.exit(main())
