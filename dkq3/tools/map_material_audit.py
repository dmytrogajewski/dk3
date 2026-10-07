# SPDX-License-Identifier: GPL-2.0-or-later
"""Where each material actually went, and at what scale it lands on a wall.

The owner's "some textures used wrong way" and "metal looks oversized" are both
questions about the *pairing* of a material with the faces wearing it, which
neither the shader table nor a screenshot answers on its own: a diamond-plate
material tiled at a 32-unit repeat is exactly right on a handrail and absurd on a
400-unit facade, and the only way to see that is to ask, per material, how big the
faces it covers actually are.

Reports per material: face count, total area, the median and 90th-percentile face
extent, the largest offenders with their centre, and the world size of one tile as
the .map actually wrote it (`scale` is texels-per-unit, so one tile spans
`texwidth / scale` units).  A material whose tile is far larger than its median
face is showing a crop of itself; one whose tile is far smaller than its largest
face is the same small pattern stamped over a wall.
"""
import argparse
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import map_sightlines


def extent(points):
    """-> the long and short side of a face's bounding box, in world units."""
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    zs = [point[2] for point in points]
    spans = sorted((max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)), reverse=True)
    return spans[0], spans[1]


def pct(values, fraction):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(fraction * (len(ordered) - 1)))]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('map', type=Path)
    parser.add_argument('--materials', type=Path, default=None,
                        help='materials.py to compare declared repeat with written scale')
    parser.add_argument('--worst', type=int, default=4)
    parser.add_argument('--min-area', type=float, default=0.0)
    args = parser.parse_args()

    declared = {}
    if args.materials:
        import importlib.util
        spec = importlib.util.spec_from_file_location('mats', args.materials)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for shader, entry in module.MATERIALS.items():
            declared[shader.split('/')[-1]] = (entry.get('repeat'), entry.get('texwidth'))

    doc = map_sightlines.read_map(args.map)
    faces = defaultdict(list)
    for brush in doc.brushes():
        for face in brush.faces:
            if face.style.shader in ('__TB_empty', '__TB_lightgrid') or 'nodraw' in face.style.shader:
                continue
            if len(face.points) < 3:
                continue
            long_side, short_side = extent(face.points)
            if long_side * short_side < args.min_area:
                continue
            centre = tuple(sum(component) / len(face.points) for component in zip(*face.points))
            key = face.style.shader.split('/')[-1]
            scale = face.style.scale or (1.0, 1.0)
            texwidth = declared.get(key, (None, None))[1] or 512
            tile = (texwidth / scale[0]) if scale[0] else 0.0
            faces[key].append((long_side, short_side, centre, scale, tile,
                               tuple(round(v, 3) for v in face.normal)))

    print('%-16s %6s %9s %8s %8s %8s  %s' % ('material', 'faces', 'area', 'med', 'p90',
                                              'tile', 'declared repeat/texwidth'))
    for key, rows in sorted(faces.items(), key=lambda kv: -sum(r[0] * r[1] for r in kv[1])):
        areas = [r[0] * r[1] for r in rows]
        long_sides = [r[0] for r in rows]
        tile = sorted({round(r[4], 1) for r in rows})
        print('%-16s %6d %9.0f %8.1f %8.1f %8s  %s'
              % (key, len(rows), sum(areas), pct(long_sides, 0.5), pct(long_sides, 0.9),
                 '/'.join(str(t) for t in tile[:3]), declared.get(key, '')))
        for row in sorted(rows, key=lambda r: -(r[0] * r[1]))[:args.worst]:
            print('        %6.0f x %6.0f at (%6.0f,%6.0f,%6.0f) n=%s scale=%s'
                  % (row[0], row[1], row[2][0], row[2][1], row[2][2], row[5], row[3]))


if __name__ == '__main__':
    sys.exit(main())
