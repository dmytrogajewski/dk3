#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Top-down walkable-floor map of a converted BSP for co-op route authoring.

Floors (faces whose normal points up) are rasterised by height into a PNG,
optionally restricted to a vertical band; liquid surfaces are cyan-hatched over
the floor beneath them; controls, exits, starts, movers and pickups are marked. A legend file lists every marker with its entity index and
coordinates. Input is the local converted map package; output is local.
"""
import argparse
import json
from pathlib import Path
import struct
import sys
import zipfile
import zlib

import numpy as np

import coop_route_survey as survey

ROOT = Path(__file__).resolve().parents[2]
MARKERS = {
    'exit': (255, 40, 40), 'start': (40, 255, 40), 'use': (255, 255, 0), 'touch': (255, 140, 0),
    'shoot': (255, 0, 255), 'mover': (0, 200, 255), 'pickup': (255, 255, 255), 'mark': (255, 120, 120),
}
FONT = {  # 3x5 digits for marker labels
    '0': '111101101101111', '1': '010110010010111', '2': '111001111100111', '3': '111001111001111',
    '4': '101101111001001', '5': '111100111001111', '6': '111100111101111', '7': '111001001001001',
    '8': '111101111101111', '9': '111101111001111',
}


def lumps(data):
    if struct.unpack_from('<4si', data) != (b'IBSP', 46):
        raise ValueError('invalid converted BSP')
    return [data[o:o + n] for o, n in (struct.unpack_from('<ii', data, 8 + i * 8) for i in range(17))]


LIQUIDS = 8 | 16 | 32  # lava, slime, water contents


def liquids(data):
    """Axial bounds (mins, maxs) of the world's liquid brushes."""
    parts = lumps(data)
    shaders = list(struct.iter_unpack('<64sii', parts[1]))
    planes = list(struct.iter_unpack('<4f', parts[2]))
    sides = list(struct.iter_unpack('<2i', parts[9]))
    world_brushes = struct.unpack_from('<6f4i', parts[7])[9]
    volumes = []
    for first, count, shader in struct.iter_unpack('<3i', parts[8][:world_brushes * 12]):
        if not shaders[shader][2] & LIQUIDS:
            continue
        lo, hi = [-1e9] * 3, [1e9] * 3
        for side in range(first, first + count):
            *normal, distance = planes[sides[side][0]]
            for axis in range(3):
                if abs(normal[axis] - 1) < 1e-4:
                    hi[axis] = distance
                elif abs(normal[axis] + 1) < 1e-4:
                    lo[axis] = -distance
        volumes.append((lo, hi))
    return volumes


def floors(data, min_normal=0.7, volumes=()):
    """Upward faces as triangles, without the surfaces of liquid volumes."""
    parts = lumps(data)
    vertices = np.frombuffer(parts[10], dtype=np.float32).reshape(-1, 11)[:, :3]
    meshverts = np.frombuffer(parts[11], dtype=np.int32)
    triangles = []
    for face in struct.iter_unpack('<12i12f2i', parts[13]):
        kind, first, count, mesh_first, mesh_count = face[2], face[3], face[4], face[5], face[6]
        if kind not in (1, 3):
            continue
        normal = face[12 + 9:12 + 12]
        if normal[2] < min_normal:
            continue
        indices = meshverts[mesh_first:mesh_first + mesh_count] + first
        for triangle in vertices[indices].reshape(-1, 3, 3):
            x, y, z = triangle.mean(axis=0)
            if not any(lo[0] <= x <= hi[0] and lo[1] <= y <= hi[1] and abs(z - hi[2]) < 1 for lo, hi in volumes):
                triangles.append(triangle)
    return np.array(triangles)


def flood(image, depth, volumes, bounds, scale, band):
    """Hatch liquid surfaces over the floors beneath them (and where no floor shows)."""
    (x0, _), (_, y1) = bounds
    height, width = depth.shape
    for lo, hi in volumes:
        if band and not band[0] <= hi[2] <= band[1]:
            continue
        a, b = int(max(0, (lo[0] - x0) / scale)), int(min(width - 1, (hi[0] - x0) / scale))
        c, d = int(max(0, (y1 - hi[1]) / scale)), int(min(height - 1, (y1 - lo[1]) / scale))
        if b < a or d < c:
            continue
        rows, columns = np.mgrid[c:d + 1, a:b + 1]
        region = depth[c:d + 1, a:b + 1]
        visible = ~(region > hi[2] + 1) & ((rows + columns) % 4 == 0)
        image[c:d + 1, a:b + 1][visible] = (0, 255, 255)


def rasterise(triangles, bounds, scale, band):
    (x0, y0), (x1, y1) = bounds
    width, height = int((x1 - x0) / scale) + 1, int((y1 - y0) / scale) + 1
    depth = np.full((height, width), -np.inf, dtype=np.float32)
    for triangle in triangles:
        z = triangle[:, 2].mean()
        if band and not band[0] <= z <= band[1]:
            continue
        px = (triangle[:, 0] - x0) / scale
        py = (y1 - triangle[:, 1]) / scale
        lo_x, hi_x = int(max(0, px.min())), int(min(width - 1, px.max()))
        lo_y, hi_y = int(max(0, py.min())), int(min(height - 1, py.max()))
        if hi_x < lo_x or hi_y < lo_y:
            continue
        gx, gy = np.meshgrid(np.arange(lo_x, hi_x + 1) + 0.5, np.arange(lo_y, hi_y + 1) + 0.5)
        (ax, bx, cx), (ay, by, cy) = px, py
        area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        if abs(area) < 1e-6:
            continue
        w0 = ((bx - gx) * (cy - gy) - (cx - gx) * (by - gy)) / area
        w1 = ((cx - gx) * (ay - gy) - (ax - gx) * (cy - gy)) / area
        inside = (w0 >= -0.01) & (w1 >= -0.01) & (w0 + w1 <= 1.01)
        region = depth[lo_y:hi_y + 1, lo_x:hi_x + 1]
        region[inside] = np.maximum(region[inside], z)
    return depth


def colour(depth):
    valid = np.isfinite(depth)
    image = np.zeros(depth.shape + (3,), dtype=np.uint8)
    if valid.any():
        lo, hi = depth[valid].min(), depth[valid].max()
        t = (depth - lo) / max(1.0, hi - lo)
        # Low floors blue, high floors yellow, through green.
        image[..., 0] = np.where(valid, 40 + 200 * t, 0)
        image[..., 1] = np.where(valid, 60 + 160 * (1 - abs(t - 0.5) * 2) + 30, 0)
        image[..., 2] = np.where(valid, 220 * (1 - t) + 20, 0)
    return image


def mark(image, x, y, rgb, label=None):
    h, w = image.shape[:2]
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            if abs(dx) + abs(dy) <= 3 and 0 <= y + dy < h and 0 <= x + dx < w:
                image[y + dy, x + dx] = rgb
    if label:
        cx = x + 5
        for char in str(label):
            pattern = FONT.get(char)
            if pattern:
                for index, bit in enumerate(pattern):
                    py, px = y - 2 + index // 3, cx + index % 3
                    if bit == '1' and 0 <= py < h and 0 <= px < w:
                        image[py, px] = rgb
            cx += 4


def png(path, image):
    height, width = image.shape[:2]
    raw = b''.join(b'\x00' + image[row].tobytes() for row in range(height))
    def chunk(kind, payload):
        return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload) & 0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


def markers(rows):
    result = []
    for row in rows:
        classname = row.get('classname', '')
        bounds = row.get('bounds')
        if bounds:
            centre = [(bounds[i] + bounds[i + 3]) / 2 for i in range(3)]
        elif 'origin' in row:
            centre = [float(v) for v in row['origin'].split()]
        else:
            continue
        kind = None
        if classname == 'trigger_changelevel':
            kind = 'exit'
        elif classname == 'info_player_start':
            kind = 'start'
        elif classname == 'func_button':
            kind = 'shoot' if float(row.get('health', '0') or 0) > 0 else 'use'
        elif classname in ('trigger_once', 'trigger_multiple') and not row.get('targetname'):
            kind = 'touch'
        elif classname == 'func_explosive' and row.get('target'):
            kind = 'shoot'
        elif classname in ('func_door', 'func_door_rotate', 'func_plat', 'func_train', 'func_elevator'):
            kind = 'mover'
        elif classname.startswith(('item_', 'weapon_', 'ammo_')) and int(row.get('spawnflags', '0') or 0) & 0x7000 != 0x7000:
            kind = 'pickup'
        if kind:
            result.append(dict(index=row['index'], classname=classname, kind=kind, centre=centre,
                               targetname=row.get('targetname', ''), target=row.get('target', ''), map=row.get('map', '')))
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('map')
    parser.add_argument('--package', type=Path, default=ROOT / 'zig-out/native-dev/play/current/share/dk3/dk3-maps.pk3')
    parser.add_argument('--out', type=Path, required=True, help='output PNG; a .json legend is written beside it')
    parser.add_argument('--scale', type=float, default=8, help='world units per pixel')
    parser.add_argument('--band', type=float, nargs=2, metavar=('ZMIN', 'ZMAX'), help='only floors in this height band')
    parser.add_argument('--region', type=float, nargs=4, metavar=('X0', 'Y0', 'X1', 'Y1'))
    parser.add_argument('--mark', action='append', default=[], help='extra point "x,y,z" to mark (e.g. a stuck position)')
    args = parser.parse_args(argv)
    with zipfile.ZipFile(args.package) as package:
        data = package.read(f'maps/{args.map}.bsp')
    volumes = liquids(data)
    triangles = floors(data, volumes=volumes)
    rows = survey.bsp_entities(data)
    points = markers(rows)
    for index, text in enumerate(args.mark):
        points.append(dict(index=900 + index, classname='mark', kind='mark', centre=[float(v) for v in text.split(',')]))
    if args.region:
        bounds = ((args.region[0], args.region[1]), (args.region[2], args.region[3]))
    else:
        bounds = ((triangles[:, :, 0].min() - 64, triangles[:, :, 1].min() - 64), (triangles[:, :, 0].max() + 64, triangles[:, :, 1].max() + 64))
    depth = rasterise(triangles, bounds, args.scale, args.band)
    image = colour(depth)
    flood(image, depth, volumes, bounds, args.scale, args.band)
    (x0, _), (_, y1) = bounds
    shown = []
    for point in points:
        x, y, z = point['centre']
        if args.band and not args.band[0] - 128 <= z <= args.band[1] + 128:
            continue
        px, py = int((x - x0) / args.scale), int((y1 - y) / args.scale)
        if 0 <= px < image.shape[1] and 0 <= py < image.shape[0]:
            mark(image, px, py, MARKERS[point['kind']], point['index'])
            shown.append(point)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    png(args.out, image)
    valid = np.isfinite(depth)
    legend = dict(map=args.map, scale=args.scale, origin=[bounds[0][0], bounds[1][1]], size=list(image.shape[1::-1]),
                  floor_z=[float(depth[valid].min()), float(depth[valid].max())] if valid.any() else None,
                  colours=MARKERS, markers=shown)
    args.out.with_suffix('.json').write_text(json.dumps(legend, indent=1) + '\n')
    print(f'{args.out}: {image.shape[1]}x{image.shape[0]} px, {len(shown)} markers, floors z {legend["floor_z"]}')
    return 0


if __name__ == '__main__':
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.exit(main())
