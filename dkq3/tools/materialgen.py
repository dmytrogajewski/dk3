#!/usr/bin/env python3
"""materialgen: remaster material sidecars for renderer_vulkan (docs/vulkan-remaster.md).

Reads the converted texture package (and optionally the HD overlay and the shader package) and
writes a cosmetic package of `textures/<name>.mat` sidecars, plus `<name>_n.png` normal maps with
--normals. The OpenGL renderers never open these files; the Vulkan remaster path reads them in
image.zig `material`, so a sidecar overrides the renderer's name-only guesses.

Sidecar keys (one `key value` per line): roughness, metalness, bump, emissive, specular and
liquid (water, slime or lava). Values come from the image itself (detail energy, saturation,
bright saturated texels), the texture name, and for liquids the shader scripts (tcMod turb or
deformVertexes on a texture marks it as a liquid surface).

With --data (the original game directory) the package also carries every map's emitting
surfaces and sky as `maps/<map>.lights` (surface_lights.py), which the ray traced lighting uses
instead of the name-based emissive guess.
"""
import argparse
import io
import re
import sys
import zipfile
from pathlib import Path

import numpy as np

import dkimg

IMAGE_SUFFIXES = ('.png', '.tga', '.jpg')
METAL = ('metal', 'steel', 'grate', 'pipe', 'chrome', 'iron', 'rust', 'panel', 'vent', 'tech', 'door', 'plate',
         'girder', 'beam', 'bolt', 'rivet', 'mech', 'gear', 'copper', 'brass', 'gold', 'silver')
ROUGH = ('rock', 'stone', 'brick', 'dirt', 'mud', 'sand', 'moss', 'bark', 'wood', 'ground', 'grass', 'cliff',
         'cave', 'earth', 'gravel', 'concrete', 'plaster', 'leaf', 'leaves', 'root', 'hay', 'cloth', 'carpet')
SMOOTH = ('glass', 'window', 'ice', 'marble', 'tile', 'floor', 'crystal', 'polish', 'mirror')
GLOW = ('light', 'lamp', 'glow', 'neon', 'fire', 'flame', 'torch', 'lite', 'lava', 'magma', 'screen', 'monitor')
LAVA = ('lava', 'magma')
SLIME = ('slime', 'sludge', 'acid', 'toxic', 'goo', 'poison', 'ooze')
WATER = ('water', 'swamp', 'pool', 'wave', 'river', 'sea', 'lake', 'wtr')


def has(name, words):
    """A keyword starts or ends one of the letter runs of the file name: `swamp03`,
    `bigswamp` and `wtrfall` match, but `swtrunk` (sw-tr-unk) is not water and `seat` not sea."""
    tokens = [token for token in re.split(r'[^a-z]+', name.rsplit('/', 1)[-1].lower()) if token]
    # Three-letter keywords (sea, goo, mud, ice, wtr) only as whole runs: `seat`, `goodstone`.
    return any(token == word or (len(word) > 3 and (token.startswith(word) or token.endswith(word)))
               for token in tokens for word in words)


def decode(name, data):
    lower = name.lower()
    if lower.endswith('.png'):
        image = dkimg.decode_png(data)
    elif lower.endswith('.tga'):
        image = dkimg.tga_to_rgba(data, name)
    else:
        return None
    if image.shape[2] == 3:
        image = np.concatenate([image, np.full(image.shape[:2] + (1,), 255, np.uint8)], axis=2)
    return image


def downsample(image, limit):
    while max(image.shape[0], image.shape[1]) > limit and image.shape[0] >= 2 and image.shape[1] >= 2:
        h, w = image.shape[0] // 2 * 2, image.shape[1] // 2 * 2
        image = image[:h, :w].reshape(h // 2, 2, w // 2, 2, -1).mean(axis=(1, 3))
    return image


def luminance(rgb):
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def liquid_shaders(package):
    """Texture base names drawn by turbulent or wave-deformed shader stages."""
    found = set()
    if not package:
        return found
    with zipfile.ZipFile(package) as archive:
        for entry in archive.namelist():
            if not entry.endswith('.shader'):
                continue
            text = archive.read(entry).decode('latin-1').lower()
            for block in re.finditer(r'\n\s*([^\s{}]+)\s*\{(.*?)\n\}', '\n' + text, re.S):
                body = block.group(2)
                if 'tcmod turb' not in body and 'deformvertexes wave' not in body:
                    continue
                for path in re.findall(r'\bmap\s+(textures/[^\s]+)', body):
                    found.add(re.sub(r'\.(png|tga|jpg)$', '', path))
    return found


def material(name, image, turbulent):
    """-> dict of sidecar values for one texture image (H,W,4 uint8)."""
    small = downsample(image.astype(np.float32), 256)
    rgb = small[..., :3] / 255.0
    lum = luminance(rgb)
    peak = rgb.max(axis=2)
    saturation = np.where(peak > 1e-3, (peak - rgb.min(axis=2)) / np.maximum(peak, 1e-3), 0)
    lap = np.abs(4 * lum[1:-1, 1:-1] - lum[:-2, 1:-1] - lum[2:, 1:-1] - lum[1:-1, :-2] - lum[1:-1, 2:])
    detail = float(lap.mean()) if lap.size else 0.0
    mean_saturation = float(saturation.mean())
    glowing = float(((lum > 0.8) & (saturation > 0.25)).mean())
    lower = name.lower()
    values = dict(roughness=0.6 + min(detail * 4, 0.3), metalness=0.0, bump=min(max(detail * 9, 0.25), 1.2),
                  emissive=0.0, specular=1.0)
    if has(lower, METAL):
        values['metalness'] = 0.7 if mean_saturation < 0.3 else 0.35
        values['roughness'] = 0.32 + min(detail * 5, 0.4)
    if has(lower, ROUGH):
        values['roughness'] = 0.85 + min(detail * 2, 0.1)
        values['bump'] = min(max(detail * 12, 0.6), 1.3)
        values['specular'] = 0.7
    if has(lower, SMOOTH):
        values['roughness'] = 0.22 + min(detail * 3, 0.25)
        values['bump'] = min(values['bump'], 0.35)
    # Named light sources glow; otherwise only textures dominated by bright saturated texels.
    if has(lower, GLOW) or glowing > 0.18:
        values['emissive'] = 1.6 if has(lower, GLOW) else 0.6
    kind = None
    if turbulent or has(lower, WATER + SLIME + LAVA):
        mean = rgb.reshape(-1, 3).mean(axis=0)
        if has(lower, LAVA) or (mean[0] > mean[1] * 1.4 and mean[0] > mean[2] * 1.6 and float(lum.mean()) > 0.25):
            kind = 'lava'
        elif has(lower, SLIME) or (mean[1] > mean[0] * 1.15 and mean[1] > mean[2] * 1.25):
            kind = 'slime'
        elif turbulent or has(lower, WATER):
            kind = 'water'
    if kind:
        values.update(roughness=0.06, bump=0.0, metalness=0.0, emissive=2.5 if kind == 'lava' else 0.0)
    values['roughness'] = round(min(max(values['roughness'], 0.04), 1.0), 3)
    values = {key: round(value, 3) for key, value in values.items()}
    if kind:
        values['liquid'] = kind
    return values


def normal_map(image, strength):
    """Tangent-space normal map from the albedo luminance height. +Y follows increasing t (image
    rows downward), the bitangent stage.frag `normalMapped` derives from the texture coordinates."""
    height = luminance(image[..., :3].astype(np.float32) / 255.0)
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    scale = 4.0 * max(strength, 0.1) * max(height.shape) / 256.0
    n = np.stack([-dx * scale, -dy * scale, np.ones_like(height)], axis=2)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return np.clip((n * 0.5 + 0.5) * 255 + 0.5, 0, 255).astype(np.uint8)


def sidecar(values):
    lines = ['# materialgen remaster material']
    lines += [f'{key} {value}' for key, value in values.items()]
    return '\n'.join(lines) + '\n'


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--textures', required=True, type=Path, help='converted dk3-textures.pk3')
    ap.add_argument('--hd', type=Path, help='optional HD overlay (zz-dk3-textures-hd.pk3) used for normal maps')
    ap.add_argument('--shaders', type=Path, help='optional dk3-shaders.pk3 for liquid detection')
    ap.add_argument('--out', required=True, type=Path, help='material package to write')
    ap.add_argument('--normals', action='store_true', help='also write <name>_n.png normal maps')
    ap.add_argument('--normal-limit', type=int, default=1024, help='largest normal map edge')
    ap.add_argument('--summary', type=Path, help='summary text to write')
    ap.add_argument('--data', help='original Daikatana data directory: also write maps/<map>.lights (surface_lights.py)')
    args = ap.parse_args(argv)
    turbulent = liquid_shaders(args.shaders)
    hd = zipfile.ZipFile(args.hd) if args.hd else None
    hd_names = {Path(n).with_suffix('').as_posix(): n for n in hd.namelist()} if hd else {}
    counts = dict(textures=0, liquids=0, metals=0, emissive=0, normals=0, skipped=0)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.out.with_suffix('.tmp')
    with zipfile.ZipFile(args.textures) as source, zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as out:
        for entry in sorted(source.namelist()):
            if not entry.startswith('textures/') or not entry.lower().endswith(IMAGE_SUFFIXES):
                continue
            base = Path(entry).with_suffix('').as_posix()
            if base.endswith(('_n', '_s')):
                continue
            try:
                image = decode(entry, source.read(entry))
            except (ValueError, zipfile.BadZipFile) as error:
                print(f'materialgen: skipped {entry}: {error}', file=sys.stderr)
                image = None
            if image is None:
                counts['skipped'] += 1
                continue
            values = material(base, image, base in turbulent)
            info = zipfile.ZipInfo(base + '.mat', (1980, 1, 1, 0, 0, 0))
            out.writestr(info, sidecar(values), zipfile.ZIP_DEFLATED)
            counts['textures'] += 1
            counts['liquids'] += 'liquid' in values
            counts['metals'] += values['metalness'] > 0
            counts['emissive'] += values['emissive'] > 0
            if args.normals and 'liquid' not in values and values['bump'] > 0:
                detailed = image
                if base in hd_names:
                    try:
                        decoded = decode(hd_names[base], hd.read(hd_names[base]))
                        if decoded is not None:
                            detailed = decoded
                    except ValueError:
                        pass
                detailed = downsample(detailed.astype(np.float32), args.normal_limit)
                info = zipfile.ZipInfo(base + '_n.png', (1980, 1, 1, 0, 0, 0))
                out.writestr(info, dkimg.encode_png(normal_map(detailed, values['bump'])), zipfile.ZIP_STORED)
                counts['normals'] += 1
        if args.data:
            import surface_lights
            for path, text in sorted(surface_lights.sidecars(args.data).items()):
                out.writestr(zipfile.ZipInfo(path, (1980, 1, 1, 0, 0, 0)), text, zipfile.ZIP_DEFLATED)
                counts['light_maps'] = counts.get('light_maps', 0) + 1
    temporary.replace(args.out)
    summary = (f"materialgen: {counts['textures']} sidecars ({counts['liquids']} liquids, {counts['metals']} metals, "
               f"{counts['emissive']} emissive), {counts['normals']} normal maps, {counts.get('light_maps', 0)} map light sidecars, "
               f"{counts['skipped']} skipped -> {args.out}")
    print(summary)
    if args.summary:
        args.summary.write_text(summary + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
