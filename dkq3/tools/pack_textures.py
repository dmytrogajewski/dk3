#!/usr/bin/env python3
"""Package every texture a map's texinfo names at its Step 6 resolution into a pk3 under the names ioquake3 resolves,
with the per-map texture-name remap for level-palette variants.

`zig build assets-textures` runs it under dkguard on the `zig build assets-images` outputs
(specs/assets/ASSET-textures.md).

FRD: specs/frds/FRD-011-original-resolution-textures-package.md
"""
import argparse
import json
import os
import sys

import dk_extract
import pk3

PREFIX = 'pack-textures:'
IMAGE = 'image'
PNG_SUFFIX, WAL_SUFFIX = '.png', '.wal'
LOSS_SOURCE = 'source_preference'
MAX_NAME = 63     # dshader_t.shader is char[MAX_QPATH] (code/qcommon/qfiles.h:392-396): 63 bytes and a NUL
MAP_WORKERS = 1   # the maps' texinfo and worldspawn lumps are small; one worker keeps the run within one process pair


def engine_name(file):
    """The name ioquake3 resolves to a manifest file: R_FindImageFile tries the bare name with each image extension
    (code/renderergl1/tr_image.c:922-1010), so the name is the file without `.png`."""
    return file[:-len(PNG_SUFFIX)]


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('paks', nargs='+', metavar='PAK', help='archives in override order; their maps name the textures')
    ap.add_argument('--manifest', required=True, help='manifest.json written by dk_extract.py')
    ap.add_argument('--images', required=True, help='images directory written by dk_extract.py')
    ap.add_argument('--out', required=True, help='pk3 to write')
    ap.add_argument('--textures-manifest', required=True, help='textures.json to write: remap, missing names, textures')
    ap.add_argument('--summary', required=True, help='summary.txt to write: the lines printed on success')
    ap.add_argument('--missing', action='append', default=[], metavar='NAME',
                    help='a texinfo texture that has no image in any archive, as expected; repeatable')
    return ap.parse_args(argv)


def unresolved(uses, images):
    """{texinfo texture: [maps]} of the textures without a Step 6 image (no key, or a status other than `image`)."""
    return {key: sorted({name for names in palettes.values() for name in names})
            for key, palettes in sorted(uses.items()) if images.get(key, {}).get('status') != IMAGE}


def texture_records(uses, images, absent):
    """{engine name: record} of every packed file: its entry, key, the maps drawing it, the chosen source, the image size
    and the WAL size texture coordinates are divided by (gl_rsurf.cpp:2873-2879), and its losses."""
    records = {}
    for key, palettes in uses.items():
        if key in absent:
            continue
        image = images[key]
        losses = [] if image['src'].endswith(WAL_SUFFIX) else [dict(reason=LOSS_SOURCE, detail=(
            f"Gold draws {key}.wal for world surfaces (gl_model.cpp:674-677); the Step 6 preference packs {image['src']}"))]
        for file in image['files']:
            maps = palettes.get(file['palette'], ()) if file['palette'] else [n for names in palettes.values() for n in names]
            records[engine_name(file['file'])] = dict(
                entry=file['file'], key=key, maps=sorted(set(maps)), src=f"{image['src_pak']}:{image['src']}",
                w=image['w'], h=image['h'], engine_w=image['engine_w'], engine_h=image['engine_h'], losses=losses)
    return records


def remap(records, uses, images):
    """{map: {texinfo texture: engine name}}: a map whose level palette decoded a texture's non-primary file (Step 6
    `<key>@<palette dir>.png`) names that file; every map is listed, most with no remap."""
    names = {name: {} for name in records}
    for key, palettes in uses.items():
        for file in images.get(key, {}).get('files', ())[1:]:
            for name in palettes.get(file['palette'], ()):
                names[name][key] = engine_name(file['file'])
    return names


def summary(records, uses, images, absent, files, size):
    """The summary lines: maps, texinfo textures, packed textures by chosen source type, palette variants, missing names,
    packed textures whose image size is not the WAL size texture coordinates use, entries and bytes."""
    packed = [images[key] for key in uses if key not in absent]
    kinds = ', '.join(f"{ext[1:]} {sum(image['src'].endswith(ext) for image in packed)}" for ext in dk_extract.EXTENSIONS)
    resized = sum(image['engine_w'] is not None and (image['w'], image['h']) != (image['engine_w'], image['engine_h'])
                  for image in packed)
    return [f'{PREFIX} {len(records)} maps, {len(uses)} texinfo textures, {len(packed)} packed ({kinds}), '
            f'{len(files) - len(packed)} palette variants, {len(absent)} missing, {resized} with a WAL size other than '
            f'the image', f'{PREFIX} {len(files)} entries, {size} bytes']


def _read(path):
    with open(path, 'rb') as f:
        return f.read()


def main(argv=None):
    args = parse_args(argv)
    with open(args.manifest, encoding='utf-8') as f:
        images = json.load(f)['images']
    sources, maps = dk_extract.plan(args.paks)
    records, uses, failures = dk_extract.level_palettes(maps, sources, MAP_WORKERS)
    absent = unresolved(uses, images)
    failures += [f"{key}: no image, named by {', '.join(names)}" for key, names in absent.items() if key not in args.missing]
    files = sorted(file['file'] for key in uses if key not in absent for file in images[key]['files'])
    failures += [f'{name}: {len(name)} bytes, beyond the {MAX_NAME} of dshader_t.shader'
                 for name in map(engine_name, files) if len(name) > MAX_NAME]
    for failure in failures:
        print(f'{PREFIX} FAIL {failure}', file=sys.stderr)
    if failures:
        return 1
    for path in (args.out, args.textures_manifest, args.summary):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    entries = [(file, _read(os.path.join(args.images, file))) for file in files]
    pk3.write(args.out, entries)
    with open(args.textures_manifest, 'w', encoding='utf-8') as f:
        json.dump({'missing': {key: names for key, names in absent.items() if key in args.missing},
                   'remap': remap(records, uses, images), 'textures': texture_records(uses, images, absent)},
                  f, indent=1, sort_keys=True)
        f.write('\n')
    lines = summary(records, uses, images, absent, files, sum(len(data) for _, data in entries))
    with open(args.summary, 'w', encoding='utf-8') as f:
        f.write(''.join(line + '\n' for line in lines))
    print('\n'.join(lines))
    return 0


if __name__ == '__main__':
    sys.exit(main())
