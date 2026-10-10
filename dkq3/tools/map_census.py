#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""One number per claim about what a map actually contains, from its own products.

Every polish claim about this map -- "more materials", "props everywhere", "all the
prop palettes are being worn", "the surface count is what costs frames" -- has so far
been answered by whichever tool happened to exist, and twice by an impression.  This
is the single place that answers all of them, off the exported `.map`, the authored
box manifest, the compile report and the staged image tree, in one run:

    materials     how many distinct shaders a face actually wears, and how much of
                  the level's area each one carries.  A material declared in the
                  table and never placed is *not* in use, and a table of 27 with 5
                  doing 70 % of the drawing is not 27 materials.
    palettes      the prop palette census specifically: this map ships eight prop
                  materials and three of them (`prop_canvas`, `prop_rubber`,
                  `prop_paint_cyan`) had never received a single face, which is a
                  large part of why 45 props read as one grey object repeated.
    placements    how many instances of each prop archetype the author placed, read
                  off `<map>-boxes.json` rather than counted off a screenshot.
    memory        texture bytes and drawn-surface counts -- the honest fps proxies.
                  The headless software renderer used by `map_view_probe` cannot
                  measure the owner's GPU framerate at all, so these two numbers,
                  plus the compile's own surface count, are what is reported instead.

Nothing here is a verdict about taste.  A frame where one material covers 90 % of the
screen is reported by `map_frame_audit.py`, not here, and no number in this file can
tell the owner the street looks like 2017.

    python3 -B dkq3/tools/map_census.py --map japanDM [--gate]
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import map_sightlines

#: Shaders that are not surfaces anybody looks at: the sky room and the volumes.
TOOL_SHADERS = ('sky', 'nodraw', 'trigger', 'clip')
#: The eight prop materials the palette is supposed to rotate between.
PROP_PALETTE = ('prop_steel', 'prop_rubber', 'prop_wood', 'prop_canvas',
                'prop_paint_red', 'prop_paint_cyan', 'prop_concrete', 'foliage')


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def polygon_area(points, normal):
    """-> the area of a planar polygon, in world units squared.

    Fan triangulation about the first vertex, projected onto the plane's dominant
    axis.  A face's bounding box is *not* its area on anything non-axis-aligned --
    the ramps are inclined and a box would overstate them by their slope.
    """
    if len(points) < 3:
        return 0.0
    axis = max(range(3), key=lambda index: abs(normal[index])) if any(normal) else 2
    u, v = (0, 1) if axis == 2 else ((1, 2) if axis == 0 else (0, 2))
    total = 0.0
    for index in range(1, len(points) - 1):
        ax, ay = points[index][u] - points[0][u], points[index][v] - points[0][v]
        bx, by = points[index + 1][u] - points[0][u], points[index + 1][v] - points[0][v]
        total += abs(ax * by - ay * bx)
    return total * 0.5


def census(work, source, map_name):
    """-> the census dict, every entry measured from a build product."""
    table = load_module(Path(source) / 'materials.py', 'census_materials')
    materials = table.MATERIALS
    doc = map_sightlines.read_map(work / ('%s.map' % map_name))

    faces, areas = {}, {}
    brushes = 0
    for brush in doc.brushes():
        brushes += 1
        for face in brush.faces:
            shader = face.style.shader
            if not shader or len(face.points) < 3:
                continue
            key = shader.rpartition('/')[2]
            area = polygon_area(face.points, face.normal)
            faces[key] = faces.get(key, 0) + 1
            areas[key] = areas.get(key, 0.0) + area

    declared = sorted(key.rpartition('/')[2] for key, entry in materials.items()
                      if entry['kind'] not in ('nodraw', 'trigger', 'clip', 'sky'))
    seen = sorted(key for key in faces if key not in TOOL_SHADERS)
    total_area = sum(areas.values()) or 1.0

    rows = []
    for key in sorted(faces, key=lambda one: -areas.get(one, 0.0)):
        entry = materials.get('japandm/%s' % key) or materials.get(key) or {}
        repeat, texwidth = entry.get('repeat'), entry.get('texwidth')
        rows.append(dict(material=key, faces=faces[key], area=round(areas[key], 1),
                         area_share=round(areas[key] / total_area, 4),
                         tile_units=round(repeat, 1) if repeat else None,
                         texels_per_unit=round(texwidth / repeat, 2) if repeat and texwidth else None,
                         in_table=bool(entry), kind=entry.get('kind')))

    placements = {}
    manifest = work / ('%s-boxes.json' % map_name)
    if manifest.is_file():
        for box in json.loads(manifest.read_text()):
            name = box['name']
            if not name.startswith('prop_'):
                continue
            archetype = name.rpartition('_')[0].replace('prop_', '', 1)
            placements[archetype] = placements.get(archetype, 0) + 1

    palettes = {}
    for name in PROP_PALETTE:
        palettes[name] = dict(faces=faces.get(name, 0), area=round(areas.get(name, 0.0), 1))

    # Texture memory: what the compiler is given, and what the renderer would hold
    # uncompressed at the declared size.  Both are stated because they answer
    # different complaints -- the pk3 size is a download argument, the resident
    # bytes are a framerate argument.
    base = work / 'home' / '.q3a' / 'baseq3'
    images, on_disk, resident = 0, 0, 0
    biggest = []
    for name, entry in materials.items():
        stem = name.rpartition('/')[2]
        for suffix in ('', '_n', '_s', '_g'):
            for folder in ('textures', ):
                candidate = base / folder / 'japandm' / (stem + suffix + '.tga')
                if not candidate.is_file():
                    continue
                size = candidate.stat().st_size
                width = int(entry.get('texwidth') or 512)
                images += 1
                on_disk += size
                resident += width * width * 4
                biggest.append((size, candidate.name))
    biggest.sort(reverse=True)
    for face in ('ft', 'bk', 'lf', 'rt', 'up', 'dn'):
        candidate = base / 'env' / ('%s_%s.tga' % (map_name.lower(), face))
        if candidate.is_file():
            images += 1
            on_disk += candidate.stat().st_size
            resident += 1024 * 1024 * 4

    build = {}
    build_json = work / ('%s-build.json' % map_name)
    if build_json.is_file():
        build = json.loads(build_json.read_text())
    author = {}
    author_json = work / ('%s-author.json' % map_name)
    if author_json.is_file():
        author = json.loads(author_json.read_text())

    return dict(
        map=map_name, work=str(work),
        materials=dict(in_use=len(seen), declared=len(declared),
                       declared_but_unused=[one for one in declared if one not in seen],
                       in_use_list=seen),
        surfaces=rows,
        palettes=dict(required=len(PROP_PALETTE),
                      worn=sum(1 for row in palettes.values() if row['faces']),
                      per_material=palettes,
                      unworn=[name for name, row in palettes.items() if not row['faces']]),
        placements=dict(archetypes=len(placements), total=sum(placements.values()),
                        per_archetype=placements),
        memory=dict(images=images, on_disk_mib=round(on_disk / 1024 ** 2, 1),
                    resident_mib=round(resident / 1024 ** 2, 1),
                    largest=[dict(name=name, mib=round(size / 1024 ** 2, 2))
                             for size, name in biggest[:6]]),
        compile=dict(brushes=brushes, faces=sum(faces.values()),
                     authored_brushes=author.get('brushes'),
                     compiled_surfaces=(build.get('stages', {}).get('compile', {}) or {}).get('surfaces'),
                     bsp_bytes=(build.get('stages', {}).get('compile', {}) or {}).get('bytes'),
                     pk3_bytes=(build.get('stages', {}).get('package', {}) or {}).get('bytes'),
                     aas=(build.get('stages', {}).get('aas', {}) or {}).get(map_name),
                     defects=author.get('defects'), passes=(build.get('stages', {})
                                                           .get('compile', {}) or {}).get('passes')),
    )


def gate(report, minimum_materials=60):
    """-> [(claim, ok, number)] -- the definition-of-done lines this tool can see."""
    compile_stage = report['compile']
    lines = [
        ('materials in use >= %d' % minimum_materials,
         report['materials']['in_use'] >= minimum_materials, report['materials']['in_use']),
        ('all %d prop palettes worn' % report['palettes']['required'],
         not report['palettes']['unworn'],
         '%d/%d' % (report['palettes']['worn'], report['palettes']['required'])),
        ('prop placements 350-500',
         350 <= report['placements']['total'] <= 500, report['placements']['total']),
        ('author defects == []', compile_stage['defects'] == [],
         len(compile_stage['defects'] or [])),
        ('no declared material sits unused',
         not report['materials']['declared_but_unused'],
         len(report['materials']['declared_but_unused'])),
        ('AAS areas present', bool(compile_stage['aas']),
         (compile_stage['aas'] or {}).get('areas')),
    ]
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--map', default='japanDM')
    parser.add_argument('--source', default=None, help='map source dir (default: maps/<map>)')
    parser.add_argument('--work', type=Path, default=Path('zig-out/map-dev'),
                        help='the build-product root; products live under <work>/<map>/')
    parser.add_argument('--gate', action='store_true', help='also print the pass/fail claims')
    parser.add_argument('--json', action='store_true', help='emit the census as JSON')
    arguments = parser.parse_args()

    source = arguments.source or 'maps/%s' % arguments.map
    report = census(arguments.work / arguments.map, source, arguments.map)
    if arguments.json:
        print(json.dumps(report, indent=1))
        return 0

    print('%s: %d materials in use of %d declared (%s never placed)'
          % (report['map'], report['materials']['in_use'], report['materials']['declared'],
             ', '.join(report['materials']['declared_but_unused']) or 'nothing'))
    print('%-18s %7s %10s %7s %9s %9s  %s'
          % ('material', 'faces', 'area', 'share', 'tile', 'tex/u', 'kind'))
    for row in report['surfaces']:
        print('%-18s %7d %10.0f %6.1f%% %9s %9s  %s%s'
              % (row['material'], row['faces'], row['area'], 100.0 * row['area_share'],
                 row['tile_units'] if row['tile_units'] is not None else '-',
                 row['texels_per_unit'] if row['texels_per_unit'] is not None else '-',
                 row['kind'] or '-', '' if row['in_table'] else '  NOT IN TABLE'))

    palettes = report['palettes']
    print('\nprop palettes: %d/%d worn%s'
          % (palettes['worn'], palettes['required'],
             '' if not palettes['unworn'] else ' -- unworn: ' + ', '.join(palettes['unworn'])))
    for name, row in sorted(palettes['per_material'].items(), key=lambda kv: -kv[1]['faces']):
        print('  %-18s %7d faces %10.0f area' % (name, row['faces'], row['area']))

    placements = report['placements']
    print('\nprop placements: %d across %d archetypes' % (placements['total'],
                                                          placements['archetypes']))
    for name, count in sorted(placements['per_archetype'].items(), key=lambda kv: -kv[1]):
        print('  %-20s %4d' % (name, count))

    memory = report['memory']
    print('\ntexture memory: %d images, %.1f MiB on disk, %.1f MiB resident uncompressed'
          % (memory['images'], memory['on_disk_mib'], memory['resident_mib']))
    for row in memory['largest']:
        print('  %-24s %5.2f MiB' % (row['name'], row['mib']))

    compile_stage = report['compile']
    print('\nworld: %s authored brushes -> %d compiled brushes, %d faces, %s drawn surfaces'
          % (compile_stage['authored_brushes'], compile_stage['brushes'],
             compile_stage['faces'], compile_stage['compiled_surfaces']))
    if compile_stage['aas']:
        print('aas: %(areas)s areas, %(reachabilities)s reachabilities'
              % compile_stage['aas'])
    if compile_stage['passes']:
        print('compile passes: %s' % compile_stage['passes'])

    if arguments.gate:
        print('')
        for claim, ok, number in gate(report):
            print('  [%s] %-40s %s' % ('PASS' if ok else 'FAIL', claim, number))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
