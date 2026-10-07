#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offline first-person view of a converted BSP for co-op route authoring.

Rasterises the map's faces (world and brush entities, in their spawn
positions) from a camera with a depth buffer, shading by surface normal and
tinting by texture, so a route author can see what a player sees at a spot:
ledges, gratings, holes and exits. Input is the local converted map package;
the PNG is written locally. Movers are drawn where they spawn.

  coop_route_view.py e1m2b --at 512,984,462 --yaw 270 --out view.png
"""
import argparse
import hashlib
import math
from pathlib import Path
import struct
import sys
import zipfile

import numpy as np

import coop_route_map as layout


def faces(data):
    """Triangles (n, 3, 3) with per-triangle normals and texture tints."""
    parts = layout.lumps(data)
    shaders = [struct.unpack_from('<64sii', parts[1], i * 72)[0].rstrip(b'\0').decode(errors='replace')
               for i in range(len(parts[1]) // 72)]
    vertices = np.frombuffer(parts[10], dtype=np.float32).reshape(-1, 11)[:, :3]
    meshverts = np.frombuffer(parts[11], dtype=np.int32)
    triangles, normals, tints = [], [], []
    for face in struct.iter_unpack('<12i12f2i', parts[13]):
        shader, kind, first, count, mesh_first, mesh_count = face[0], face[2], face[3], face[4], face[5], face[6]
        name = shaders[shader] if shader < len(shaders) else ''
        if 'sky' in name or name.endswith('/trigger') or 'clip' in name:
            continue
        if kind == 2:
            # Curved patch: draw its control grid as quads (close enough to
            # show where pipes and arches stand).
            width, height = face[24], face[25]
            if width < 2 or height < 2 or width * height != count:
                continue
            grid = vertices[first:first + count].reshape(height, width, 3)
            quads = []
            for row in range(height - 1):
                for column in range(width - 1):
                    a, b, c, d = grid[row, column], grid[row, column + 1], grid[row + 1, column + 1], grid[row + 1, column]
                    quads.extend(([a, b, c], [a, c, d]))
            tris = np.array(quads, dtype=np.float32)
            edge = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
            length = np.linalg.norm(edge, axis=1, keepdims=True)
            patch_normals = edge / np.maximum(length, 1e-6)
            digest = hashlib.sha1(name.encode()).digest()
            tint = np.array([100 + digest[0] % 156, 100 + digest[1] % 156, 100 + digest[2] % 156], dtype=np.float32)
            # Patches are drawn from both sides.
            triangles.extend([tris, tris[:, ::-1]])
            normals.extend([patch_normals, -patch_normals])
            tints.extend([np.repeat(tint[None], len(tris), axis=0)] * 2)
            continue
        if kind not in (1, 3) or mesh_count == 0:
            continue
        tris = vertices[meshverts[mesh_first:mesh_first + mesh_count] + first].reshape(-1, 3, 3)
        digest = hashlib.sha1(name.encode()).digest()
        tint = np.array([100 + digest[0] % 156, 100 + digest[1] % 156, 100 + digest[2] % 156], dtype=np.float32)
        triangles.append(tris)
        normals.append(np.repeat(np.array([face[12 + 9:12 + 12]], dtype=np.float32), len(tris), axis=0))
        tints.append(np.repeat(tint[None], len(tris), axis=0))
    return np.concatenate(triangles), np.concatenate(normals), np.concatenate(tints)


def render(triangles, normals, tints, eye, yaw, pitch, width, height, fov, markers=()):
    yaw, pitch = math.radians(yaw), math.radians(pitch)
    forward = np.array([math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), -math.sin(pitch)])
    right = np.array([math.sin(yaw), -math.cos(yaw), 0.0])
    up = np.cross(right, forward)
    focal = (width / 2) / math.tan(math.radians(fov) / 2)
    rel = triangles - np.array(eye, dtype=np.float32)
    cam = np.stack([rel @ right, rel @ up, rel @ forward], axis=-1)  # x right, y up, z depth
    # Faces are one-sided: draw those facing the eye.
    facing = np.einsum('ij,ij->i', normals, -rel.mean(axis=1)) > 0
    keep = (cam[..., 2] > 4).all(axis=1) & facing
    cam, normals, tints = cam[keep], normals[keep], tints[keep]
    light = np.clip(0.35 + 0.65 * np.abs(normals @ np.array([0.3, 0.5, 0.8])), 0, 1)
    colour = (tints * light[:, None]).astype(np.uint8)
    sx = width / 2 + focal * cam[..., 0] / cam[..., 2]
    sy = height / 2 - focal * cam[..., 1] / cam[..., 2]
    depth = np.full((height, width), np.inf, dtype=np.float32)
    image = np.full((height, width, 3), 20, dtype=np.uint8)
    for t in range(len(cam)):
        xs, ys, zs = sx[t], sy[t], cam[t, :, 2]
        lo_x, hi_x = max(0, int(xs.min())), min(width - 1, int(xs.max()) + 1)
        lo_y, hi_y = max(0, int(ys.min())), min(height - 1, int(ys.max()) + 1)
        if lo_x > hi_x or lo_y > hi_y:
            continue
        gx, gy = np.meshgrid(np.arange(lo_x, hi_x + 1) + 0.5, np.arange(lo_y, hi_y + 1) + 0.5)
        (ax, bx, cx), (ay, by, cy) = xs, ys
        area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        if abs(area) < 1e-6:
            continue
        w0 = ((bx - gx) * (cy - gy) - (cx - gx) * (by - gy)) / area
        w1 = ((cx - gx) * (ay - gy) - (ax - gx) * (cy - gy)) / area
        w2 = 1 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue
        # Perspective-correct depth: interpolate 1/z.
        inv = w0 / zs[0] + w1 / zs[1] + w2 / zs[2]
        z = np.where(inside, 1 / np.maximum(inv, 1e-9), np.inf)
        region = depth[lo_y:hi_y + 1, lo_x:hi_x + 1]
        nearer = z < region
        region[nearer] = z[nearer]
        image[lo_y:hi_y + 1, lo_x:hi_x + 1][nearer] = colour[t]
    # Distance fog so near and far surfaces separate.
    fog = np.clip(depth / 3000, 0, 0.7)[..., None]
    image = (image * (1 - fog) + 20 * fog).astype(np.uint8)
    for point, rgb in markers:
        rel = np.array(point) - np.array(eye)
        cz = rel @ forward
        if cz <= 4:
            continue
        px = int(width / 2 + focal * (rel @ right) / cz)
        py = int(height / 2 - focal * (rel @ up) / cz)
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                if 0 <= py + dy < height and 0 <= px + dx < width and abs(dx) + abs(dy) <= 3:
                    image[py + dy, px + dx] = rgb
    return image


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('map')
    parser.add_argument('--package', type=Path, default=layout.ROOT / 'zig-out/native-dev/play/current/share/dk3/dk3-maps.pk3')
    parser.add_argument('--at', required=True, help='eye position x,y,z')
    parser.add_argument('--yaw', type=float, default=0)
    parser.add_argument('--pitch', type=float, default=0, help='positive looks down')
    parser.add_argument('--fov', type=float, default=100)
    parser.add_argument('--size', default='640x360')
    parser.add_argument('--mark', action='append', default=[], help='point x,y,z to mark in red')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(argv)
    with zipfile.ZipFile(args.package) as package:
        data = package.read(f'maps/{args.map}.bsp')
    width, height = (int(v) for v in args.size.split('x'))
    eye = [float(v) for v in args.at.split(',')]
    triangles, normals, tints = faces(data)
    markers = [([float(v) for v in text.split(',')], (255, 40, 40)) for text in args.mark]
    image = render(triangles, normals, tints, eye, args.yaw, args.pitch, width, height, args.fov, markers)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    layout.png(args.out, np.ascontiguousarray(image))
    print(f'{args.out}: {width}x{height} from {eye} yaw {args.yaw} pitch {args.pitch}')
    return 0


if __name__ == '__main__':
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.exit(main())
