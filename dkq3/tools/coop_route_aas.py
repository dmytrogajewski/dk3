#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offline area-graph queries for co-op route authoring.

Reads a map's compiled AAS (the navigation the bots use) from the local
navigation package and answers what the running game would: which area a
point lies in, the shortest reachability path between two points, and what a
point can reach at all (with the map's controls, exits and pickups that lie in
reachable areas). Doors and walls are as compiled; movers are not modelled.

  coop_route_aas.py e1m2a area -- -770,377,-204
  coop_route_aas.py e1m2a path -- -770,377,-204 450,1330,72
  coop_route_aas.py e1m2a flood [--reverse] -- -770,377,-204
  coop_route_aas.py e1m2a islands
"""
import argparse
import heapq
from pathlib import Path
import struct
import sys
import zipfile

import coop_route_map as layout
import coop_route_survey as survey

ROOT = Path(__file__).resolve().parents[2]
SHARE = ROOT / 'zig-out/native-dev/play/current/share/dk3'
# Lump record sizes of AAS version 5, in file order.
SIZES = (32, 12, 20, 8, 4, 24, 4, 48, 28, 44, 12, 20, 4, 16)
TRAVEL = {1: 'invalid', 2: 'walk', 3: 'crouch', 4: 'barrierjump', 5: 'jump', 6: 'ladder', 7: 'walkoffledge',
          8: 'swim', 9: 'waterjump', 10: 'teleport', 11: 'elevator', 12: 'rocketjump', 13: 'bfgjump',
          14: 'grapplehook', 15: 'doublejump', 16: 'rampjump', 17: 'strafejump', 18: 'jumppad', 19: 'funcbob'}
# What a co-op player can do (no rocket/BFG jumps or grapple).
PLAYER = {2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 18, 19}


class Graph:
    def __init__(self, data):
        if data[:4] != b'EAAS' or struct.unpack_from('<i', data, 4)[0] != 5:
            raise ValueError('unsupported AAS file')
        header = bytearray(data[:124])
        for index in range(116):
            header[index + 8] ^= (index * 119) & 255
        lumps = []
        for index, size in enumerate(SIZES):
            offset, length = struct.unpack_from('<ii', header, 12 + index * 8)
            lumps.append((data[offset:offset + length], size))
        self.planes = [struct.unpack_from('<4f', lumps[2][0], i * 20) for i in range(len(lumps[2][0]) // 20)]
        self.nodes = [struct.unpack_from('<3i', lumps[10][0], i * 12) for i in range(len(lumps[10][0]) // 12)]
        self.areas = [struct.unpack_from('<3i9f', lumps[7][0], i * 48) for i in range(len(lumps[7][0]) // 48)]
        self.settings = [struct.unpack_from('<7i', lumps[8][0], i * 28) for i in range(len(lumps[8][0]) // 28)]
        self.reach = [struct.unpack_from('<3i6fiH', lumps[9][0], i * 44) for i in range(len(lumps[9][0]) // 44)]

    def area(self, point):
        node = 1
        while node > 0:
            planenum, front, back = self.nodes[node]
            *normal, distance = self.planes[planenum]
            side = sum(n * p for n, p in zip(normal, point)) - distance
            node = front if side > 0 else back
        return -node

    def standing(self, point):
        """Area of a player standing at `point`, searching a little below it."""
        # A standing origin lies on the boundary of its thin grounded area.
        x, y, z = point
        for drop in (-4, *range(4, 164, 8)):
            area = self.area((x, y, z - drop))
            if area and self.settings[area][5]:
                return area
        return self.area((x, y, z + 4))

    def edges(self, area):
        contents, flags, presence, cluster, cluster_area, count, first = self.settings[area]
        for index in range(first, first + count):
            to, face, edge, *rest = self.reach[index]
            start, end, kind, time = rest[0:3], rest[3:6], rest[6], rest[7]
            yield to, start, end, kind & 0xffffff, time

    def blocked(self, boxes):
        """Areas overlapping any of the boxes (closed doors, removed bridges)."""
        result = set()
        for area in range(1, len(self.areas)):
            box = self.areas[area][3:9]
            for lo, hi in boxes:
                if all(box[axis] < hi[axis] and box[axis + 3] > lo[axis] for axis in range(3)):
                    result.add(area)
        return result

    def search(self, origin, allowed=PLAYER, reverse=False, avoid=frozenset()):
        """Dijkstra over reachabilities; returns {area: (time, previous, reach)}."""
        if reverse:
            incoming = {}
            for area in range(1, len(self.settings)):
                for to, start, end, kind, time in self.edges(area):
                    incoming.setdefault(to, []).append((area, start, end, kind, time))
        best = {origin: (0, None, None)}
        queue = [(0, origin)]
        while queue:
            cost, area = heapq.heappop(queue)
            if cost > best[area][0]:
                continue
            links = incoming.get(area, []) if reverse else self.edges(area)
            for to, start, end, kind, time in links:
                if kind not in allowed or to in avoid:
                    continue
                total = cost + max(1, time)
                if to not in best or total < best[to][0]:
                    best[to] = (total, area, (start, end, kind))
                    heapq.heappush(queue, (total, to))
        return best

    def describe(self, area):
        number, faces, first, *box = self.areas[area]
        contents, flags = self.settings[area][0], self.settings[area][1]
        liquid = ' water' if contents & 1 else ' lava' if contents & 2 else ' slime' if contents & 4 else ''
        return (f'area {area} centre {box[6]:.0f},{box[7]:.0f},{box[8]:.0f} box {box[0]:.0f},{box[1]:.0f},{box[2]:.0f}'
                f'..{box[3]:.0f},{box[4]:.0f},{box[5]:.0f} reach {self.settings[area][5]}{liquid}'
                f'{" grounded" if flags & 1 else ""}{" ladder" if flags & 2 else ""}')


def point(text):
    values = [float(value) for value in text.split(',')]
    if len(values) != 3:
        raise argparse.ArgumentTypeError('expected x,y,z')
    return tuple(values)


def features(data):
    """Map controls, exits, keys and pickups worth knowing about, with centres."""
    return [row for row in layout.markers(survey.bsp_entities(data)) if row['kind'] != 'mover']


def islands(graph, bsp, minimum=20):
    """Groups of areas that reach each other both ways, largest first, with the
    map features inside each: the places authored progression must connect."""
    forward = {area: {to for to, *_rest, kind, _time in graph.edges(area) if kind in PLAYER} for area in range(1, len(graph.settings))}
    # Kosaraju: order by finish time, then sweep the transposed graph.
    order, seen = [], set()
    for root in forward:
        if root in seen:
            continue
        stack = [(root, iter(forward[root]))]
        seen.add(root)
        while stack:
            area, children = stack[-1]
            for child in children:
                if child not in seen:
                    seen.add(child)
                    stack.append((child, iter(forward.get(child, ()))))
                    break
            else:
                order.append(area)
                stack.pop()
    backward = {}
    for area, targets in forward.items():
        for to in targets:
            backward.setdefault(to, set()).add(area)
    group, groups = {}, []
    for root in reversed(order):
        if root in group:
            continue
        members, stack = [], [root]
        group[root] = len(groups)
        while stack:
            area = stack.pop()
            members.append(area)
            for child in backward.get(area, ()):
                if child not in group:
                    group[child] = len(groups)
                    stack.append(child)
        groups.append(members)
    rows = [(row, graph.standing(row['centre'])) for row in features(bsp)]
    for number, members in sorted(enumerate(groups), key=lambda item: -len(item[1])):
        if len(members) < minimum:
            continue
        xs = [graph.areas[a][9] for a in members]
        ys = [graph.areas[a][10] for a in members]
        zs = [graph.areas[a][11] for a in members]
        exits = sorted({group[to] for a in members for to in forward[a] if group.get(to) != number and len(groups[group[to]]) >= minimum})
        print(f'island {number}: {len(members)} areas, extent {min(xs):.0f},{min(ys):.0f},{min(zs):.0f} .. '
              f'{max(xs):.0f},{max(ys):.0f},{max(zs):.0f}; one-way to {exits or "-"}')
        for row, area in rows:
            if area and group.get(area) == number:
                x, y, z = row['centre']
                print(f'    {row["kind"]:6} #{row["index"]:<4} {row["classname"]:22} {row["targetname"] or row["target"] or row["map"]:16} at {x:.0f},{y:.0f},{z:.0f}')
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('map')
    parser.add_argument('command', choices=('area', 'path', 'flood', 'islands'))
    parser.add_argument('points', nargs='*', type=point)
    parser.add_argument('--share', type=Path, default=SHARE)
    parser.add_argument('--reverse', action='store_true', help='flood: areas that can reach the point instead')
    parser.add_argument('--avoid', action='append', default=[], metavar='X0,Y0,Z0,X1,Y1,Z1',
                        help='treat areas overlapping this box as closed (repeatable), e.g. a locked door')
    parser.add_argument('--mode', default='easy', choices=('easy', 'normal', 'hard', 'dm', 'ctf', 'deathtag'),
                        help='navigation variant the game would load (the map cfg names it; default easy)')
    args = parser.parse_args(argv)
    with zipfile.ZipFile(args.share / 'dk3-navigation.pk3') as package:
        asset = args.map
        try:
            for line in package.read(f'dk3/navigation/{args.map}.cfg').decode().splitlines()[1:]:
                words = line.split()
                if len(words) == 2 and words[0] == args.mode:
                    asset = words[1]
        except KeyError:
            pass
        graph = Graph(package.read(f'maps/{asset}.aas'))
    with zipfile.ZipFile(args.share / 'dk3-maps.pk3') as package:
        bsp = package.read(f'maps/{args.map}.bsp')
    if args.command == 'islands':
        return islands(graph, bsp)
    origin = graph.standing(args.points[0])
    if args.command == 'area':
        for value in args.points:
            area = graph.standing(value)
            print(f'{value}: ' + (graph.describe(area) if area else 'solid or outside'))
        return 0
    if not origin:
        print(f'{args.points[0]}: no area')
        return 1
    boxes = []
    for text in args.avoid:
        values = [float(value) for value in text.split(',')]
        boxes.append((values[:3], values[3:]))
    best = graph.search(origin, reverse=args.reverse, avoid=graph.blocked(boxes))
    if args.command == 'path':
        goal = graph.standing(args.points[1])
        if goal not in best:
            print(f'no route from area {origin} to area {goal}')
            return 1
        steps, area = [], goal
        while best[area][1] is not None:
            steps.append((area, best[area][2]))
            area = best[area][1]
        print(f'{len(steps)} reachabilities, reachability time {best[goal][0] / 100:.1f} s')
        for area, (start, end, kind) in reversed(steps):
            print(f'  {TRAVEL.get(kind, kind):12} {start[0]:.0f},{start[1]:.0f},{start[2]:.0f} -> '
                  f'{end[0]:.0f},{end[1]:.0f},{end[2]:.0f}  (area {area})')
        return 0
    print(f'{"reverse " if args.reverse else ""}flood from {graph.describe(origin)}: {len(best)} areas')
    xs = [graph.areas[a][9] for a in best]
    ys = [graph.areas[a][10] for a in best]
    zs = [graph.areas[a][11] for a in best]
    print(f'  extent {min(xs):.0f},{min(ys):.0f},{min(zs):.0f} .. {max(xs):.0f},{max(ys):.0f},{max(zs):.0f}')
    for row in features(bsp):
        area = graph.standing(row['centre'])
        status = 'reachable' if area in best else 'unreachable' if area else 'no area'
        x, y, z = row['centre']
        print(f'  {status:11} {row["kind"]:6} #{row["index"]:<4} {row["classname"]:22} {row["targetname"] or row["target"] or row["map"]:16} '
              f'at {x:.0f},{y:.0f},{z:.0f}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
