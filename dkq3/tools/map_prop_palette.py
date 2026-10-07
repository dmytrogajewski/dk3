#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Measure the mean albedo of every crafted material into one JSON file.

`maps/japanDM/props.py` has to decide, per generated piece, which of the map's
own materials it should wear.  A generated piece carries only a mean baked
colour, so the decision is a nearest-colour search -- and a colour search is
only meaningful if both sides are in the same space.  The generator reports
colours in **linear** sRGB (it samples the mesh's own diffuse), while the
crafted `.tga` files are display-referred, so this tool converts the images on
the way out and says so in the file it writes.

Run it after any change to `maps/japanDM/textures.py`:

    python3.14 -B dkq3/tools/map_prop_palette.py --assets maps/japanDM/assets \
        --materials maps/japanDM/materials.py --out maps/japanDM/assets/material_colour.json

Emissive and transparent materials are flagged rather than dropped: a neon sign
whose albedo reads bright must not be chosen to represent a sunlit concrete
panel, and the placement pass uses the flag to keep them off unlit pieces.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image


def srgb_to_linear(value):
    """One 0..1 channel, display-referred -> scene-referred."""
    if value <= 0.04045:
        return value / 12.92
    return math.pow((value + 0.055) / 1.055, 2.4)


def measure(path):
    """-> (mean linear RGB, mean alpha) of one image, downsampled for speed."""
    image = Image.open(path).convert('RGBA')
    image.thumbnail((128, 128), Image.BILINEAR)
    pixels = list(image.getdata())
    total = len(pixels)
    channels = [0.0, 0.0, 0.0]
    alpha = 0.0
    for red, green, blue, a in pixels:
        for position, channel in enumerate((red, green, blue)):
            channels[position] += srgb_to_linear(channel / 255.0)
        alpha += a / 255.0
    return ([round(value / total, 4) for value in channels], round(alpha / total, 4))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', type=Path, required=True, help='the crafted image tree')
    parser.add_argument('--materials', type=Path, required=True, help='the map material table')
    parser.add_argument('--out', type=Path, required=True)
    arguments = parser.parse_args()

    table = {'__file__': str(arguments.materials.resolve())}
    exec(arguments.materials.read_text(encoding='utf-8'), table)
    palette = {}
    for shader, entry in sorted(table['MATERIALS'].items()):
        key = shader.split('/')[-1]
        diffuse = arguments.assets / 'japandm' / ('%s.tga' % key)
        if not diffuse.exists():
            continue
        colour, alpha = measure(diffuse)
        palette[shader] = dict(
            colour=colour, alpha=alpha, kind=entry.get('kind', 'lit'),
            emissive=bool(entry.get('glow')) or entry.get('kind') == 'emissive_full',
            transparent=entry.get('kind') == 'trans' or alpha < 0.98)
    arguments.out.parent.mkdir(parents=True, exist_ok=True)
    arguments.out.write_text(json.dumps(dict(format=1, space='linear-srgb',
                                             palette=palette), indent=1) + '\n', encoding='utf-8')
    print('prop-palette: %d materials -> %s' % (len(palette), arguments.out))
    for shader, entry in sorted(palette.items()):
        print('  %-28s %s%s' % (shader, entry['colour'],
                                '  emissive' if entry['emissive'] else
                                '  transparent' if entry['transparent'] else ''))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
