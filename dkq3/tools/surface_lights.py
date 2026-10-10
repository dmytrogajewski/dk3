#!/usr/bin/env python3
"""surface_lights: the original maps' emitting surfaces as remaster sidecars for renderer_vulkan.

Daikatana's radiosity lit its maps from light entities and from faces whose texinfo carries
SURF_LIGHT: the texinfo `value` is the emission and the per-texinfo `extsurfinfo` colour its
tint (0 0 0 = the texture's own colour). The converted IBSP 46 maps drop both (dk2q3.SURFACES
maps LIGHT to nothing, and the map bytes must stay unchanged because saves check them), so this
tool writes them next to the maps as `maps/<map>.lights` text sidecars. Only the ray traced
lighting of renderer_vulkan (rt.zig) reads them; the OpenGL renderers never open them.

Sidecar lines:
  surfaces <count>                      the converted map's surface count (stale check)
  surface <index> <value> <r> <g> <b>   a drawn surface of the converted map (dk2q3 surface order)
  sky <value> <r> <g> <b>               the map's emitting sky faces, area-weighted
Colours are 0-1 (extsurfinfo / 255); 0 0 0 means the texture's colour.

The package given with --package is rewritten in place with every map's sidecar added (or
replaced); its other entries are kept. `play.py install` checks the sidecars against the
installed maps and regenerates them from the asset generation's input when they are missing
or stale, so they never need to leave the local machine. Usage:
  python3 dkq3/tools/surface_lights.py --data <Daikatana data dir> --package zig-out/materials/dk3-materials.pk3
"""
import argparse
import sys
import zipfile
from pathlib import Path

import numpy as np

import dk2q3
import dkbsp
import shadergen

DK_SURF_LIGHT = 0x1      # user/dk_shared.h:326
DK_SURF_SKY = 0x4


def face_points(b, face, verts, edges, surfedges):
    ne, first = int(face['numedges']), int(face['firstedge'])
    ids = [edges[abs(int(e))][0 if e >= 0 else 1] for e in surfedges[first:first + ne]]
    return verts[ids]


def polygon_area(points):
    if len(points) < 3:
        return 0.0
    return 0.5 * float(np.linalg.norm(sum(np.cross(points[k] - points[0], points[k + 1] - points[0])
                                          for k in range(1, len(points) - 1))))


def sidecar(b):
    """-> sidecar text for one validated map: its emitting surfaces in the converted surface order (the face walk of
    dk2q3.Converter.build_surfaces) and its emitting sky."""
    texinfo = b.arr('texinfo')
    colours = b.arr('extsurfinfo')
    verts = b.arr('vertexes')['xyz'].astype(np.float64)
    edges = b.arr('edges')['v']
    surfedges = b.arr('surfedges')
    in_submodel = np.zeros(b.count('faces'), bool)
    for model in b.arr('models')[1:]:
        in_submodel[int(model['firstface']):int(model['firstface']) + int(model['numfaces'])] = True
    lines, surface = [], 0
    sky_area, sky_value, sky_colour = 0.0, 0.0, np.zeros(3)
    for fi, f in enumerate(b.faces()):
        ti = int(f['texinfo'])
        flags, value = int(texinfo[ti]['flags']), int(texinfo[ti]['value'])
        colour = colours[ti]['color'] / 255.0 if ti < len(colours) else np.zeros(3)
        emitting = flags & DK_SURF_LIGHT and value > 0
        if emitting and flags & DK_SURF_SKY:
            # Sky faces emit wherever they are, drawn or not (submodel sky is undrawn but still lit the map).
            area = polygon_area(face_points(b, f, verts, edges, surfedges))
            sky_area += area
            sky_value += area * value
            sky_colour += area * (colour if colour.max() > 0 else np.ones(3))
        # The surface walk: exactly the faces build_surfaces turns into surfaces.
        if flags & dk2q3.DK_SURF_NODRAW or int(f['numedges']) < 3:
            continue
        if shadergen.category(flags, bool(in_submodel[fi])) == 'undrawn':
            continue
        if emitting and not flags & DK_SURF_SKY:
            lines.append(f'surface {surface} {value} {colour[0]:.4f} {colour[1]:.4f} {colour[2]:.4f}')
        surface += 1
    if sky_area > 0:
        c = sky_colour / sky_area
        lines.append(f'sky {sky_value / sky_area:.2f} {c[0]:.4f} {c[1]:.4f} {c[2]:.4f}')
    header = f'# dk3 surface lights v1 (dkq3/tools/surface_lights.py)\nsurfaces {surface}\n'
    return header + ''.join(line + '\n' for line in lines), surface


def map_names(game):
    names = set()
    for _, pak in game.paks:
        names.update(n[5:-4] for n in pak.entries if n.startswith('maps/') and n.endswith('.bsp'))
    loose = Path(game.root, 'maps')
    if loose.is_dir():
        names.update(p.stem for p in loose.glob('*.bsp'))
    return sorted(names)


def sidecars(data):
    """-> {'maps/<map>.lights': text} for every map of the game directory `data`."""
    out = {}
    with dk2q3.GameDir(data) as game:
        for name in map_names(game):
            found = game.find(f'maps/{name}.bsp')
            if found is None:
                continue
            try:
                b = dkbsp.Bsp(found[1], found[0])
                b.validate()
            except (dkbsp.BspError, ValueError) as error:
                print(f'surface_lights: skipped {name}: {error}', file=sys.stderr)
                continue
            out[f'maps/{name}.lights'], _ = sidecar(b)
    return out


def write_package(package, texts):
    """Rewrites `package` (created when missing) with `texts` ({path: text}) added or replaced."""
    package = Path(package)
    temporary = package.with_suffix('.tmp')
    with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as out:
        if package.is_file():
            with zipfile.ZipFile(package) as source:
                for info in source.infolist():
                    if info.filename not in texts:
                        out.writestr(info, source.read(info.filename))
        for path, text in sorted(texts.items()):
            out.writestr(zipfile.ZipInfo(path, (1980, 1, 1, 0, 0, 0)), text, zipfile.ZIP_DEFLATED)
    temporary.replace(package)


def recorded_surfaces(text):
    """-> the surface count a sidecar was made for, or None (older sidecars)."""
    for line in text.splitlines():
        if line.startswith('surfaces '):
            try:
                return int(line.split()[1])
            except (IndexError, ValueError):
                return None
    return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--data', required=True, help='legally acquired Daikatana data directory')
    ap.add_argument('--package', required=True, type=Path, help='remaster package to add the sidecars to (rewritten)')
    args = ap.parse_args(argv)
    texts = sidecars(args.data)
    write_package(args.package, texts)
    lights = sum(text.count('\nsurface ') for text in texts.values())
    skies = sum('\nsky ' in text for text in texts.values())
    print(f'surface_lights: {len(texts)} maps, {lights} emitting surfaces, {skies} emitting skies -> {args.package}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
