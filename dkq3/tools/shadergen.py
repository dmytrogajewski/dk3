#!/usr/bin/env python3
"""Daikatana surface flags, animation rings, skies and 1.3 glow layers as ioquake3 shaders (specs/assets/ASSET-shaders.md).

Every render rule follows Gold's renderer, reference/dk-gold/base/ref_gl/gl_rsurf.cpp, not the flag names.

FRD: specs/frds/FRD-014-surface-flags-and-texture-animation-as-q3-shaders.md
"""
import argparse
import collections
import json
import math
import os
import struct
import sys

import numpy as np

import dkimg
import pk3

# Daikatana texinfo flags (reference/dk-gold/user/dk_shared.h:326-357).
SURF_FULLBRIGHT, SURF_SKY, SURF_WARP, SURF_TRANS33, SURF_TRANS66, SURF_FLOWING = 0x2, 0x4, 0x8, 0x10, 0x20, 0x40
SURF_ALPHACHAN, SURF_MIDTEXTURE, SURF_SURGE, SURF_BIGSURGE, SURF_FOGPLANE = 0x40000, 0x80000, 0x200000, 0x400000, 0x1000000
ALPHA_CHAIN = SURF_TRANS33 | SURF_TRANS66 | SURF_ALPHACHAN      # r_surfs_alpha (gl_rsurf.cpp:2494-2498)


# The first matching bits pick the draw chain: R_RecursiveWorldNode for the world (gl_rsurf.cpp:2484-2529),
# R_DrawInlineBModel for brush models (:1750-1798), where GL_RenderLightmappedPoly draws nothing for SKY (:1499-1502).
WORLD_ORDER = ((SURF_SKY, 'sky'), (ALPHA_CHAIN, 'alpha'), (SURF_MIDTEXTURE, 'mid'), (SURF_FULLBRIGHT, 'fullbright'))
SUBMODEL_ORDER = ((ALPHA_CHAIN, 'alpha'), (SURF_FULLBRIGHT, 'fullbright'), (SURF_MIDTEXTURE, 'mid'), (SURF_SKY, 'undrawn'))


def category(flags, submodel=False):
    """-> the draw chain of a surface: sky, alpha, mid, fullbright or opaque (lightmapped multitexture or the warp texture
    chain), or undrawn. A world surface whose flags equal SURF_FOGPLANE is skipped (gl_rsurf.cpp:2511-2514)."""
    if flags == SURF_FOGPLANE and not submodel:
        return 'undrawn'
    for bits, chain in SUBMODEL_ORDER if submodel else WORLD_ORDER:
        if flags & bits:
            return chain
    return 'opaque'


# Flags gl_rsurf.cpp reads to draw a surface; the others (footsteps, LIGHT, HINT, FOGPLANE with other bits) draw nothing.
RENDER_FLAGS = (SURF_FULLBRIGHT | SURF_SKY | SURF_WARP | SURF_TRANS33 | SURF_TRANS66 | SURF_FLOWING | SURF_ALPHACHAN |
                SURF_MIDTEXTURE | SURF_SURGE | SURF_BIGSURGE)
SKY_PREFIX = 'textures/dkq3/sky/'
SKY_BOX_PREFIX = 'env/32bit/'        # SetSky: env/32bit/<sky><suffix>.tga (gl_warp.cpp:1386-1391)
NODRAW_SUFFIX, MODEL_SUFFIX = '-nodraw', '-model'
NODRAW_DEFINITION = {'kind': 'nodraw'}      # a name no surface draws: brush sides, contents, noshader
# The glow frame of a ring frame without a glow layer: 1.3 skips that frame's glow pass (R_TextureAnimationGlow returns
# r_notexture, RB_RenderLightmappedSurface tests it, install/daikatana 0x5d0580-0x5d05c9, 0x5d3abc), and adding black adds nothing.
BLACK_NAME = 'textures/dkq3/black'


def lightmapped(flags, submodel=False):
    """Whether Gold draws a lightmap on the surface: Mod_LoadFaces builds none for SKY, FULLBRIGHT or flags equal to
    SURF_FOGPLANE (gl_model.cpp:840-842), R_RenderBrushPoly adds none for SKY or FULLBRIGHT (gl_rsurf.cpp:928-931), and a
    brush model's opaque warp chain is never blended with multitexture (gl_rsurf.cpp:1789-1807)."""
    if flags & (SURF_SKY | SURF_FULLBRIGHT) or flags == SURF_FOGPLANE:
        return False
    return not (submodel and category(flags, submodel) == 'opaque' and flags & SURF_WARP)


def surface(texinfo, index, resolve, sky, submodel=False):
    """-> (shader name, definition) of the surfaces drawn with texinfo `index`. `resolve(texture)` gives (engine name, WAL
    size, image size, glow image name or None); `sky` is the worldspawn sky key. A brush model's MIDTEXTURE and opaque
    surfaces show the entity frame, 0 at load (R_TextureAnimation, gl_rsurf.cpp:95-113); its definition is named apart
    when it differs from the world's."""
    flags = texinfo[index]['flags']
    chain = category(flags, submodel)
    if chain == 'sky':
        return SKY_PREFIX + sky, dict(kind='sky', box=SKY_BOX_PREFIX + sky)
    indices = [index] if submodel and chain in ('opaque', 'mid') else ring(texinfo, index)
    frames = [resolve(texinfo[i]['texture']) for i in indices]
    glow = [frame[3] or BLACK_NAME for frame in frames] if any(frame[3] for frame in frames) else []
    render = flags & RENDER_FLAGS
    name = frames[0][0] + (f'#{render:x}' if render else '') + (f'+{len(frames)}' if len(frames) > 1 else '')
    if chain == 'undrawn':
        return name + NODRAW_SUFFIX, dict(NODRAW_DEFINITION)
    definition = dict(kind='surface', category=chain, flags=render, frames=[frame[0] for frame in frames],
                      glow=glow, lightmap=lightmapped(flags, submodel), wal=list(frames[0][1]),
                      image=list(frames[0][2]))
    if submodel and surface(texinfo, index, resolve, sky)[1] != definition:
        name += MODEL_SUFFIX
    return name, definition


# Every stage draws its colour unscaled (rgbGen identity): Gold draws world polygons in colour 1, 1, 1 (gl_rsurf.cpp:906).
IDENTITY = 'rgbGen identity'
LIGHTMAP_MAP = 'map $lightmap'
# The lightmap multiplies what is drawn (GL_MODULATE, gl_rsurf.cpp:1489-1694; R_BlendLightmaps GL_ZERO GL_SRC_COLOR, :664).
FILTER = 'blendFunc GL_DST_COLOR GL_ZERO'
# Blended chains keep glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) (gl_rsurf.cpp:878) with GLSTATE_BLEND.
BLEND = 'blendFunc blend'
# 1.3 RB_RenderTexGlow: glBlendFunc(GL_ONE, GL_ONE) (install/daikatana 0x5d39de-0x5d39e8).
ADD = 'blendFunc GL_ONE GL_ONE'
TRANS_ALPHA = ((SURF_TRANS33, 0.33), (SURF_TRANS66, 0.66))     # R_RenderBrushPoly colour alpha (gl_rsurf.cpp:894-903)
TWO_PI = 2 * math.pi
TURB_TEXELS = 8                  # warpsin.h is 8 * sin(i * 2pi / 256) (reference/dk-gold/base/ref_gl/warpsin.h)
TURB_FREQUENCY = 1 / TWO_PI      # the table index is (coordinate / 8 + time) radians (gl_rsurf.cpp:278-282, :35)
FLOWING_TILES = 0.5              # FLOWING_SPEED = frac(time * 0.5) of a tile (gl_rsurf.cpp:39, :1596)
WARP_FLOWING_TEXELS = 64         # a warp scrolls 64 * FLOWING_SPEED texels (gl_rsurf.cpp:244-245)
SURGE_WAVES = ((SURF_SURGE, 0.25, 1), (SURF_BIGSURGE, 0.5, 4))  # fWaveModifier, fWaveMultiplier (gl_rsurf.cpp:251-265)
ANIMATION_FPS = 2                # r_global_ent.frame = (int)(r_newrefdef.time * 2) (gl_rsurf.cpp:2570)
MAX_IMAGE_ANIMATIONS = 8         # code/renderergl1/tr_local.h:258


def number(value):
    """Shader text for a number: at most six significant digits, no exponent for the values used here."""
    return '%g' % value


def image_line(frames):
    """`map` for one frame, `animMap` at Gold's two frames per second for a ring, keeping ioq3's first eight."""
    kept = frames[:MAX_IMAGE_ANIMATIONS]
    return f'map {kept[0]}' if len(kept) == 1 else f"animMap {ANIMATION_FPS} {' '.join(kept)}"


def redrawn(wal, image):
    """Whether a packed image is not its WAL resampled by one power of two on both axes. 1.3 draws such a TGA at its own
    size (R_FindImage, install/daikatana 0x5be058-0x5be0b4), one texel per world unit like Gold's WAL."""
    ratio = (image[0] / wal[0], image[1] / wal[1])
    return ratio[0] != ratio[1] or not math.log2(ratio[0]).is_integer()


def warped(definition):
    """A warp is drawn by DrawSubdividedPolys, which mid textures never use (GL_RenderLightmappedPoly, gl_rsurf.cpp:1648-1660)."""
    return bool(definition['flags'] & SURF_WARP) and definition['category'] != 'mid'


def texture_mods(definition):
    """tcMod lines shared by the texture and glow stages: the redrawn-TGA scale, the warp and the flow."""
    (width, height), image, flags = definition['wal'], definition['image'], definition['flags']
    mods = [f'tcMod scale {number(width / image[0])} {number(height / image[1])}'] if redrawn((width, height), image) else []
    if warped(definition):
        mods.append(f'tcMod turb 0 {number(TURB_TEXELS / width)} 0 {number(TURB_FREQUENCY)}')
    if flags & SURF_FLOWING:
        tiles = WARP_FLOWING_TEXELS * FLOWING_TILES / width if warped(definition) else FLOWING_TILES
        mods.append(f'tcMod scroll {number(-tiles)} 0')
    return mods


def deforms(definition):
    """deformVertexes for a surging warp: Gold's z wave at 1 radian per second over (s + t) * modifier (gl_rsurf.cpp:291-295)."""
    for bit, modifier, multiplier in SURGE_WAVES if warped(definition) else ():
        if definition['flags'] & bit:
            spread = TWO_PI * definition['wal'][0] / modifier
            return [f'deformVertexes wave {number(spread)} sin 0 {number(TURB_TEXELS * multiplier)} 0 {number(TURB_FREQUENCY)}']
    return []


def surface_stages(definition):
    """Stages of a drawn surface by draw chain, lightmap and glow."""
    chain, lit, mods = definition['category'], definition['lightmap'], texture_mods(definition)
    image = image_line(definition['frames'])
    if chain == 'opaque':
        stages = [[LIGHTMAP_MAP, IDENTITY]] if lit else []
        stages.append([image, FILTER, IDENTITY, *mods] if lit else [image, IDENTITY, *mods])
    elif chain == 'alpha':
        alpha = [f'alphaGen const {number(a)}' for bit, a in TRANS_ALPHA if definition['flags'] & bit][:1]
        stages = [[image, BLEND, IDENTITY, *alpha, *mods]] + ([[LIGHTMAP_MAP, FILTER, IDENTITY]] if lit else [])
    elif chain == 'mid':
        stages = [[image, 'alphaFunc GT0', BLEND, 'depthWrite', IDENTITY, *mods]]
        stages += [[LIGHTMAP_MAP, FILTER, 'depthFunc equal', IDENTITY]] if lit else []
    else:
        stages = [[image, BLEND, 'depthWrite', IDENTITY, *mods]]
    if definition['glow'] and chain != 'fullbright':
        stages.append([image_line(definition['glow']), ADD, IDENTITY, *mods])
    return stages


def shader_text(name, definition):
    """-> the ioquake3 script of one shader (code/renderergl1/tr_shader.c ParseShader, ParseStage)."""
    kind = definition['kind']
    general = ([f"skyParms {definition['box']} - -"] if kind == 'sky' else ['surfaceparm nodraw'] if kind == 'nodraw'
               else deforms(definition))
    stages = surface_stages(definition) if kind == 'surface' else []
    body = ''.join(f'\t{line}\n' for line in general)
    body += ''.join('\t{\n' + ''.join(f'\t\t{line}\n' for line in stage) + '\t}\n' for stage in stages)
    return f'{name}\n{{\n{body}}}\n'


def losses(definition):
    """-> the losses a surface definition applies beyond those every shader of its kind has (specs/assets/ASSET-shaders.md)."""
    found = []
    if len(definition['frames']) > MAX_IMAGE_ANIMATIONS:
        found.append('animation_frames_dropped')
    if warped(definition) and definition['flags'] & SURF_FLOWING and WARP_FLOWING_TEXELS % definition['wal'][0]:
        found.append('flowing_warp_jump')
    return found


# ---------------------------------------------------------------------------------------------------------------------
# Light styles as shader animation (roadmap Step 30, specs/ports/PORT-render-effects.md).
#
# ioquake3 has no light styles, and Step 13 kept only the style-0 lightmap block of every face, so the light an animated
# or switched style added is not in the converted data at all. What survives is the style's RHYTHM, and that is what an
# ioquake3 waveform can carry. These functions are the conversion Step 30 records: a style string becomes one `rgbGen wave`.
#
# Gold's client is the authority, not the editor documentation. `CL_SetLightstyle` (base/client/cl_fx.cpp:76) computes
#     cl_lightstyle[i].map[k] = (float)(s[k]-'a')/(float)('m'-'a');
# so 'a' is 0.0 (dark) and 'm' is 1.0 (normal). install/dlls/dk_ents.def:42-44 claims the opposite ("a being the
# brightest, z being the darkest"); the running code wins, and the disagreement is recorded in ASSET-shaders.md.
# `CL_RunLightStyles` (cl_fx.cpp:40-59) steps one character per CL_FRAME_MILLISECONDS, which is 100
# (user/dk_shared.h:6-7), so N characters loop at 10/N Hz. A style the server never set holds 1.0 (cl_fx.cpp:53).

LIGHTSTYLE_BASE_CHAR, LIGHTSTYLE_FULL_CHAR = 'a', 'm'
LIGHTSTYLE_DIVISOR = ord(LIGHTSTYLE_FULL_CHAR) - ord(LIGHTSTYLE_BASE_CHAR)      # 'm' - 'a' = 12
LIGHTSTYLE_FRAME_MS = 100                                                       # CL_FRAME_MILLISECONDS
LIGHTSTYLE_HZ = 1000.0 / LIGHTSTYLE_FRAME_MS                                    # ten characters per second
LIGHTSTYLE_UNSET_VALUE = 1.0                                                    # a style with no string (cl_fx.cpp:53)
# Original periodic/flicker samples; custom authored styles are read from user assets.
DEFAULT_LIGHTSTYLES = {
    0: 'm', 1: 'mlkpmn', 2: 'acegikmoqsuwywu sqomkigeca'.replace(' ', ''),
    3: 'jkmkijlm', 4: 'am', 5: 'jlnprpnlj', 6: 'lokmpn', 7: 'kmljkm',
    8: 'lmjklmk', 9: 'aaaammmm', 10: 'mmmlammk', 11: 'gikmoqomkig', 63: 'a',
}
LIGHTSTYLE_CUSTOM_FIRST = 12        # LIGHT.CPP:637
LIGHTSTYLE_SWITCHABLE_FIRST = 32    # LIGHT.CPP:211
LIGHTSTYLE_ON, LIGHTSTYLE_OFF = 'm', 'a'        # light_use (LIGHT.CPP:55-73)
LIGHTSTYLE_SCRIPT = 'scripts/dkq3-lightstyles.shader'
LIGHTSTYLE_PREFIX = 'textures/dkq3/lightstyle/'
# ioquake3's waveform names (code/renderergl1/tr_shader.c NameToGenFunc, :270-300).
WAVE_SIN, WAVE_SQUARE, WAVE_TRIANGLE = 'sin', 'square', 'triangle'
WAVE_SAWTOOTH, WAVE_INVERSE_SAWTOOTH, WAVE_NOISE = 'sawtooth', 'inversesawtooth', 'noise'
WAVE_ORDER = (WAVE_SIN, WAVE_SQUARE, WAVE_TRIANGLE, WAVE_SAWTOOTH, WAVE_INVERSE_SAWTOOTH, WAVE_NOISE)

Wave = collections.namedtuple('Wave', 'func base amplitude phase frequency')


def lightstyle_values(text):
    """-> the intensity of every character of a light style string, as CL_SetLightstyle computes it (cl_fx.cpp:76):
    (c - 'a') / ('m' - 'a'). 'a' is 0.0 and 'm' is 1.0. A character outside a-z is not rejected, because Gold rejects
    none either: the corpus binds the string "10" on `end`, whose values are negative."""
    return [(ord(c) - ord(LIGHTSTYLE_BASE_CHAR)) / LIGHTSTYLE_DIVISOR for c in text]


def _lightstyle_runs(values):
    """-> [(value, length)] of the consecutive equal runs of `values`."""
    runs = []
    for v in values:
        if runs and runs[-1][0] == v:
            runs[-1][1] += 1
        else:
            runs.append([v, 1])
    return [(v, n) for v, n in runs]


def lightstyle_waveform(values):
    """-> the ioquake3 waveform that carries the shape of `values`.

    One value is steady. Two values whose runs all have the same length are a square wave (Gold's fast and slow strobes).
    A string that rises to one peak and falls back is a triangle, or a sawtooth when the peak sits at an end. Everything
    else - Gold's flickers and candles - has no closed form, so it becomes `noise`, the waveform ioquake3 offers for it."""
    distinct = set(values)
    if len(distinct) < 2:
        return WAVE_SIN
    if len(distinct) == 2 and len({n for _, n in _lightstyle_runs(values)}) == 1:
        return WAVE_SQUARE
    peak = values.index(max(values))
    rises = all(values[i] <= values[i + 1] for i in range(peak))
    falls = all(values[i] >= values[i + 1] for i in range(peak, len(values) - 1))
    if rises and falls and len(distinct) > 2:
        if peak == len(values) - 1:
            return WAVE_SAWTOOTH
        if peak == 0:
            return WAVE_INVERSE_SAWTOOTH
        return WAVE_TRIANGLE
    return WAVE_NOISE


def lightstyle_wave(text):
    """-> the `Wave` an ioquake3 shader animates a Daikatana light style with.

    `base` and `amplitude` are the midpoint and half-range of the style's own intensities, so the wave spans exactly what
    the style spans. `frequency` is 10/N Hz for N characters, Gold's own step. `phase` is 0: a shader's clock cannot be
    aligned with Gold's server frame counter, which is a recorded loss."""
    values = lightstyle_values(text)
    if not values:
        return Wave(WAVE_SIN, LIGHTSTYLE_UNSET_VALUE, 0.0, 0.0, 0.0)
    low, high = min(values), max(values)
    if low == high:
        return Wave(WAVE_SIN, low, 0.0, 0.0, 0.0)
    return Wave(lightstyle_waveform(values), (low + high) / 2, (high - low) / 2, 0.0, LIGHTSTYLE_HZ / len(values))


def lightstyle_rgbgen(text):
    """-> the `rgbGen wave` directive of a light style string (tr_shader.c:851-855, ParseWaveForm)."""
    w = lightstyle_wave(text)
    return f'rgbGen wave {w.func} {number(w.base)} {number(w.amplitude)} {number(w.phase)} {number(w.frequency)}'


def lightstyle_name(style):
    """-> the shader name of a light style number."""
    return f'{LIGHTSTYLE_PREFIX}{style}'


def lightstyle_shader_text(style, text):
    """-> the ioquake3 script of one light style: the lightmap stage a surface of that style would carry.

    It animates `$lightmap` alone, because the only lightmap a converted map holds is the style-0 block (ASSET-bsp.md,
    "Light Styles"). It records the mapping from a style to its animation; no converted surface references it, which is
    the loss specs/ports/PORT-render-effects.md carries."""
    return f'{lightstyle_name(style)}\n{{\n\t{{\n\t\t{LIGHTMAP_MAP}\n\t\t{lightstyle_rgbgen(text)}\n\t}}\n}}\n'


def lightstyle_script():
    """-> the text of `scripts/dkq3-lightstyles.shader`: one shader per style of Gold's table, in style order."""
    return ''.join(lightstyle_shader_text(style, DEFAULT_LIGHTSTYLES[style]) for style in sorted(DEFAULT_LIGHTSTYLES))


# Original dk3 diagnostic checker; no embedded game artwork.
NOTEXTURE_SIZE = 8
NOTEXTURE_NAME = 'textures/dkq3/notexture'


SKY_SUFFIXES = ('rt', 'bk', 'lf', 'ft', 'up', 'dn')          # gl_warp.cpp:1279, code/renderergl1/tr_shader.c:1257
# An uncompressed true-colour TGA with rows stored bottom-up, as LoadTGA reads it (code/renderercommon/tr_image_tga.c:139-190).
TGA_HEADER = struct.Struct('<BBBHHBHHHHBB')
TGA_TRUE_COLOUR, TGA_ALPHA_BITS = 2, 8


def notexture_image():
    """Return an original magenta/charcoal checker."""
    y, x = np.indices((NOTEXTURE_SIZE, NOTEXTURE_SIZE))
    return np.where(((x // 4 + y // 4) % 2)[..., None],
                    np.array([192, 32, 192], np.uint8), np.array([32, 32, 32], np.uint8))


def tga_bytes(image):
    """-> TGA bytes of an (H, W, 3 or 4) uint8 image given top row first: 24 bits for RGB, 32 for RGBA."""
    height, width, channels = image.shape
    header = TGA_HEADER.pack(0, 0, TGA_TRUE_COLOUR, 0, 0, 0, 0, 0, width, height, 8 * channels,
                             TGA_ALPHA_BITS if channels == 4 else 0)
    order = [2, 1, 0, 3][:channels]
    return header + np.ascontiguousarray(image[::-1][:, :, order]).tobytes()


def sky_side(images, box, suffix):
    """-> the Step 6 manifest key SetSky loads for one side of `box` (env/32bit/<sky>): the 32-bit TGA, else the old PCX, or
    None where Gold draws r_notexture (gl_warp.cpp:1386-1400)."""
    sky = box[len(SKY_BOX_PREFIX):]
    return next((key for key in (box + suffix, f'env/{sky}{suffix}') if images.get(key, {}).get('status') == 'image'), None)


PREFIX = 'shadergen:'
IMAGE = 'image'
CHAINS = ('sky', 'opaque', 'alpha', 'mid', 'fullbright', 'nodraw')
LOSSES = ('animation_frames_dropped', 'flowing_warp_jump', 'sky_sides_notexture')


def script_file(name):
    """-> the script holding a shader: scripts/<first directory below textures/>.shader, else scripts/dkq3.shader. One
    malformed shader makes ScanAndLoadShaderFiles ignore its whole file (tr_shader.c:3006-3024)."""
    parts = name.split('/')
    return f"scripts/{parts[1] if parts[0] == 'textures' and len(parts) > 2 else 'dkq3'}.shader"


def merge(documents):
    """-> ({shader name: definition}, failures): one definition per name over every map's --shaders document."""
    shaders, origin, failures = {}, {}, []
    for document in documents:
        for name, definition in sorted(document['shaders'].items()):
            if name not in shaders:
                shaders[name], origin[name] = definition, document['map']
            elif shaders[name] != definition:
                failures.append(f"{name}: maps {origin[name]} and {document['map']} define it differently")
    return shaders, failures


def unpacked(shaders, images, textures):
    """-> failures for every frame no texture package holds and every glow layer without a Step 6 image."""
    packed, failures = set(textures) | {NOTEXTURE_NAME}, []
    for name, definition in sorted(shaders.items()):
        if definition['kind'] == 'surface':
            failures += [f'{name}: image {frame} is in no package' for frame in definition['frames'] if frame not in packed]
            failures += [f'{name}: image {glow} is in no package' for glow in definition['glow']
                         if glow != BLACK_NAME and images.get(glow, {}).get('status') != IMAGE]
    return failures


def package(shaders, images, images_dir):
    """-> (pk3 entries sorted by name, sky sides drawn with r_notexture): the scripts, every sky side as the TGA ParseSkyParms
    loads (tr_shader.c:1270-1276), every glow layer's Step 6 PNG and the notexture image."""
    notexture, entries, fallback = tga_bytes(notexture_image()), {}, 0
    for name in sorted(shaders):
        entries[script_file(name)] = entries.get(script_file(name), b'') + shader_text(name, shaders[name]).encode('latin1')
    entries[NOTEXTURE_NAME + '.tga'] = notexture
    # The light styles Step 13 dropped, as the shader animation Step 30 maps them to (PORT-render-effects.md).
    entries[LIGHTSTYLE_SCRIPT] = lightstyle_script().encode('latin1')
    for box in sorted({definition['box'] for definition in shaders.values() if definition['kind'] == 'sky'}):
        for suffix in SKY_SUFFIXES:
            key = sky_side(images, box, suffix)
            fallback += key is None
            path = None if key is None else os.path.join(images_dir, images[key]['files'][0]['file'])
            entries[f'{box}_{suffix}.tga'] = notexture if path is None else tga_bytes(dkimg.read_png(path))
    for glow in sorted({glow for definition in shaders.values() if definition['kind'] == 'surface' for glow in definition['glow']}):
        if glow == BLACK_NAME:
            entries[BLACK_NAME + '.tga'] = tga_bytes(np.zeros((1, 1, 3), np.uint8))
            continue
        file = images[glow]['files'][0]['file']
        with open(os.path.join(images_dir, file), 'rb') as f:
            entries[file] = f.read()
    return sorted(entries.items()), fallback


def summary(documents, shaders, fallback, entries):
    """The summary lines: shaders per draw chain, effects, losses, entries and bytes."""
    kinds = collections.Counter(d['category'] if d['kind'] == 'surface' else d['kind'] for d in shaders.values())
    surfaces = [d for d in shaders.values() if d['kind'] == 'surface']
    effects = dict(warp=sum(warped(d) for d in surfaces), flowing=sum(bool(d['flags'] & SURF_FLOWING) for d in surfaces),
                   surge=sum(bool(deforms(d)) for d in surfaces), animated=sum(len(d['frames']) > 1 for d in surfaces),
                   glow=sum(bool(d['glow']) and d['category'] != 'fullbright' for d in surfaces),
                   redrawn=sum(redrawn(d['wal'], d['image']) for d in surfaces))
    lost = collections.Counter(loss for d in surfaces for loss in losses(d))
    lost['sky_sides_notexture'] = fallback
    waves = collections.Counter(lightstyle_wave(text).func for text in DEFAULT_LIGHTSTYLES.values())
    return [f"{PREFIX} {len(documents)} maps, {len(shaders)} shaders: " + ', '.join(f'{k} {kinds[k]}' for k in CHAINS),
            f"{PREFIX} effects " + ', '.join(f'{k} {v}' for k, v in effects.items()),
            f"{PREFIX} losses " + ', '.join(f'{k} {lost[k]}' for k in LOSSES),
            f"{PREFIX} light styles {len(DEFAULT_LIGHTSTYLES)} of Gold's table as shader waves: " +
            ', '.join(f'{f} {waves[f]}' for f in WAVE_ORDER),
            f"{PREFIX} {len(entries)} entries, {sum(len(data) for _, data in entries)} bytes"]


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('shaders', nargs='+', metavar='SHADERS', help='shader definitions dk2q3.py writes with --shaders, one per map')
    ap.add_argument('--manifest', required=True, help='manifest.json written by dk_extract.py: sky and glow images')
    ap.add_argument('--images', required=True, help='images directory written by dk_extract.py')
    ap.add_argument('--textures', required=True, help='textures.json written by pack_textures.py: the packed texture names')
    ap.add_argument('--out', required=True, help='pk3 to write')
    ap.add_argument('--summary', required=True, help='summary.txt to write: the lines printed on success')
    return ap.parse_args(argv)


def _load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def main(argv=None):
    args = parse_args(argv)
    documents, images = [_load(path) for path in args.shaders], _load(args.manifest)['images']
    shaders, failures = merge(documents)
    failures += unpacked(shaders, images, _load(args.textures)['textures'])
    for failure in failures:
        print(f'{PREFIX} FAIL {failure}', file=sys.stderr)
    if failures:
        return 1
    entries, fallback = package(shaders, images, args.images)
    for path in (args.out, args.summary):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    pk3.write(args.out, entries)
    lines = summary(documents, shaders, fallback, entries)
    with open(args.summary, 'w', encoding='utf-8') as f:
        f.write(''.join(line + '\n' for line in lines))
    print('\n'.join(lines))
    return 0


if __name__ == '__main__':
    sys.exit(main())


class RingError(ValueError):
    """A nexttexinfo chain Gold cannot animate: it never returns to its start, which stops the level with ERR_DROP after
    1024 frames (gl_model.cpp:686-705)."""


def ring(texinfo, index):
    """-> texinfo indices of the animation frames R_TextureAnimation steps through from `index` (gl_rsurf.cpp:95-113):
    `next` is followed while it is > 0 (gl_model.cpp:672-673) until the walk returns to `index` or a link is missing. The
    walk stops at the first revisited texinfo, so it terminates on every cyclic chain."""
    frames, at = [index], texinfo[index]['next']
    while 0 < at != index:
        if at in frames or at >= len(texinfo):
            detail = 're-enters at' if at in frames else f'links past the {len(texinfo)} texinfo with'
            raise RingError(f'texinfo {index}: the chain {frames} {detail} texinfo {at} and never returns')
        frames.append(at)
        at = texinfo[at]['next']
    return frames
