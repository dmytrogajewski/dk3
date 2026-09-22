#!/usr/bin/env python3
"""Daikatana SP2 sprites as ioquake3 shaders, frame images and a sidecar per sprite (specs/assets/ASSET-sp2.md).

Every draw rule follows R_DrawSpriteModel (reference/dk-gold/base/ref_gl/gl_rmain.cpp:401-537).

FRD: specs/frds/FRD-018-sp2-sprites.md
"""
import argparse
import collections
import json
import os
import sys
from dataclasses import dataclass

import dk2q3
import dk_extract
import dkimg
import dkm2md3
import dkpak
import pk3
import shadergen
import sp2

# The stage R_DrawSpriteModel sets: blend, alpha test, the entity colour (gl_rmain.cpp:452-500). The alpha test function in
# force is GL_GREATER 0 from the world passes (gl_rsurf.cpp:1349) or GL's default GL_ALWAYS; both keep every texel a blend shows.
BLEND = 'blendFunc blend'
ADD = 'blendFunc GL_SRC_ALPHA GL_ONE'          # SPR_ALPHACHANNEL (gl_rmain.cpp:470-473)
ALPHA_TEST = 'alphaFunc GT0'
# Native cgame supplies rectangular sprites through AddPolyToScene. Its color
# lives on the four vertices; there is no refEntity whose shaderRGBA can be read.
SPRITE_COLOUR = 'rgbGen vertex'
ALPHACHANNEL_SUFFIX = '@alphachannel'


DEPTH_WRITE = 'depthWrite'      # GLSTATE_DEPTH_MASK stays set only for an image without alpha (gl_rmain.cpp:484-488)


def _token(name):
    """A script token: quoted when the name holds whitespace, which COM_ParseExt reads as one token (q_shared.c:530-536)."""
    return f'"{name}"' if any(c.isspace() for c in name) else name


def _text(name, image, blend, alpha_gen, alpha):
    stage = [f'map {_token(image)}', blend, ALPHA_TEST] + ([] if alpha else [DEPTH_WRITE]) + [SPRITE_COLOUR, alpha_gen]
    body = ''.join(f'\t\t{line}\n' for line in stage)
    return f'{_token(name)}\n{{\n\tcull disable\n\t{{\n{body}\t}}\n}}\n'


def frame_shaders(sprite, index, image, alpha):
    """Two authored blend modes, modulated by the native sprite's vertex color."""
    name = f'{sprite}/{index}'
    result = [(name, _text(name, image, BLEND, 'alphaGen vertex', alpha)),
              (name + ALPHACHANNEL_SUFFIX, _text(name + ALPHACHANNEL_SUFFIX, image, ADD, 'alphaGen vertex', alpha))]
    if sprite in ('models/global/we_dispunch.sp2', 'models/global/we_bhole.sp2', 'models/global/we_scorch.sp2'):
        mark = name + '@mark'
        result.append((mark, f'{mark}\n{{\n polygonOffset\n cull disable\n'
                       f' {{ clampMap {_token(image)}\n blendFunc blend\n rgbGen vertex\n alphaGen vertex\n }}\n}}\n'))
    return result


# R_FindImage(name, it_sprite): no skin flood fill and no scrap (gl_image.cpp:1594-1625).
SPRITE_TYPE = 'it_sprite'
PNG = '.png'
VARIANT = '@sprite-{}'      # an image other than Step 6's <key>.png: <key>@sprite-<extension>.png
STEP6, VARIANT_RESOLUTION, MISSING, UNLOADABLE = 'step6', 'variant', 'missing', 'unloadable'
# R_FindImage returns NULL for a name under 5 bytes or whose last 4 bytes are none of these (strcmp, gl_image.cpp:1742-1791).
MIN_NAME_BYTES = 5
LOADABLE = ('.pcx', '.bmp', '.wal', '.tga')
# R_DrawSpriteModel draws r_notexture for a NULL image (gl_rmain.cpp:432-433): shadergen.py's 8x8 Gold pattern, opaque.
NOTEXTURE_IMAGE = 'sprites/dkq3/notexture.tga'
NOTEXTURE_SIZE = (8, 8)


@dataclass(frozen=True)
class FrameImage:
    """A frame's image: its resolution, packaged entry, PNG bytes, source (`<archive>:<entry>`), size and alpha."""
    resolution: str
    image: str
    png: bytes
    source: str
    size: tuple
    alpha: bool


def resolve_frame(name, find, step6):
    """-> the FrameImage of a frame name. `find(entry)` gives (origin, bytes) in the 1.3 search order; `step6(key)` gives Step 6's
    <key>.png bytes or None. The decode equal to Step 6's bytes shares its entry; any other is a variant."""
    if len(name.encode('latin1')) < MIN_NAME_BYTES or name[-len(LOADABLE[0]):] not in LOADABLE:
        return FrameImage(UNLOADABLE, NOTEXTURE_IMAGE, None, None, NOTEXTURE_SIZE, False)
    key, extension = os.path.splitext(name.replace('\\', '/').lower())
    found = find(key + extension)
    if found is None:
        return FrameImage(MISSING, NOTEXTURE_IMAGE, None, None, NOTEXTURE_SIZE, False)
    origin, raw = found
    _, images, _, size = dk_extract._decode(key + extension, raw, SPRITE_TYPE, [])
    rgba = images[0][1]
    alpha = bool((rgba[..., 3] < dk_extract.OPAQUE).any())
    png = dkimg.encode_png(rgba if alpha else rgba[..., :3])
    shared = png == step6(key)
    image = key + ('' if shared else VARIANT.format(extension[1:])) + PNG
    return FrameImage(STEP6 if shared else VARIANT_RESOLUTION, image, png, origin, tuple(size), alpha)


SIDECAR_FORMAT, SIDECAR_VERSION = 'dkq3-sp2', 1
# The renderfx bits R_DrawSpriteModel reads (user/dk_shared.h:692-695): entity axes, and the alphachannel shader variant.
ENTITY_FLAGS = dict(SPR_ORIENTED=0x8, SPR_ALPHACHANNEL=0x20)


@dataclass(frozen=True)
class Converted:
    shaders: list       # [(name, script text)] in frame order
    sidecar: dict
    losses: list


MAX_QPATH = 64      # shader and image names are shorter (code/renderergl1/tr_shader.c:2768, tr_image.c R_FindImageFile)


class LimitError(ValueError):
    """A shader or image name ioquake3 cannot register."""


def _check_name(sprite, name):
    if len(name.encode('latin1')) >= MAX_QPATH:
        raise LimitError(f'{sprite}: {name!r} is {len(name.encode("latin1"))} bytes; ioquake3 names are shorter than {MAX_QPATH}')


def sidecar_bytes(sidecar):
    """The sidecar as sorted, compact, ASCII JSON and a newline: equal sidecars give equal bytes."""
    return json.dumps(sidecar, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode('ascii') + b'\n'


def _frame(sprite, index, frame, image):
    """-> (sidecar record, shaders) of one frame. The quad is R_DrawSpriteModel's, in frame pixels from the entity origin along
    right and up (gl_rmain.cpp:500-528); RT_SPRITE draws a square centred on its origin (tr_surface.c:153-181)."""
    shaders = frame_shaders(sprite.name, index, os.path.splitext(image.image)[0], image.alpha)
    for name in (shaders[0][0], shaders[1][0], os.path.splitext(image.image)[0]):
        _check_name(sprite.name, name)
    quad =dict(left=-frame.origin_x, right=frame.width - frame.origin_x, bottom=-frame.origin_y, top=frame.height - frame.origin_y)
    rt_sprite = dict(offset=[frame.width / 2 - frame.origin_x, frame.height / 2 - frame.origin_y], square=frame.width == frame.height)
    return dict(index=index, width=frame.width, height=frame.height, origin_x=frame.origin_x, origin_y=frame.origin_y, name=frame.name,
                name_padding=frame.padding, image=image.image, resolution=image.resolution, source=image.source,
                image_size=list(image.size), alpha=image.alpha, shader=shaders[0][0], alphachannel_shader=shaders[1][0],
                quad=quad, rt_sprite=rt_sprite), shaders


def _frames_where(records, test):
    return ', '.join(f"{r['index']} {r['name']!r}" for r in records if test(r))


# (reason, which frame records it applies to, what it means). Each applies once per sprite with the frames it names.
FRAME_LOSSES = (
    ('frame_image_missing', lambda r: r['resolution'] == MISSING,
     'no archive holds the image: Gold draws r_notexture (gl_rmain.cpp:432-433), and so does the shader'),
    ('frame_image_unloadable', lambda r: r['resolution'] == UNLOADABLE,
     'R_FindImage loads no name under 5 bytes or without .pcx, .bmp, .wal or .tga (gl_image.cpp:1742-1791): r_notexture'),
    ('name_padding', lambda r: r['name_padding'] > 0, 'bytes after the name terminator, which Gold never reads, are dropped'),
    ('origin_off_centre', lambda r: r['rt_sprite']['offset'] != [0.0, 0.0],
     'RT_SPRITE centres its quad on the origin (tr_surface.c:153-181): move the origin by rt_sprite.offset, or draw the quad'),
    ('rt_sprite_not_square', lambda r: not r['rt_sprite']['square'],
     'RT_SPRITE draws one radius on both axes (tr_surface.c:153-181): draw the sidecar quad as a polygon (Step 30)'),
    ('wal_frame_palette', lambda r: (r['source'] or '').endswith('.wal'),
     'an it_sprite WAL uses the palette current at load (gl_image.cpp:1708-1712); decoded with its own palette'),
)


def _losses(sprite, records):
    losses = [dict(reason=reason, detail=f'frames {_frames_where(records, test)}: {meaning}')
              for reason, test, meaning in FRAME_LOSSES if any(test(r) for r in records)]
    if sprite.trailing:
        losses.append(dict(reason='trailing_bytes', detail=f'{sprite.trailing} bytes after the last frame, which Gold never reads'))
    return losses


def convert(sprite, images, archive):
    """-> the Converted shaders, sidecar and losses of an `sp2.Sprite` whose frames resolved to `images`, read from `archive`."""
    records, shaders = [], []
    for index, (frame, image) in enumerate(zip(sprite.frames, images)):
        record, frame_list = _frame(sprite, index, frame, image)
        records.append(record)
        shaders += frame_list
    source = dict(archive=archive, ident=sp2.IDENT.decode('ascii'), version=sprite.version, numframes=len(sprite.frames),
                  trailing_bytes=sprite.trailing)
    sidecar = dict(format=SIDECAR_FORMAT, version=SIDECAR_VERSION, sprite=sprite.name, source=source,
                   entity_flags=dict(ENTITY_FLAGS), frames=records)
    return Converted(shaders, sidecar, _losses(sprite, records))


# ---------------------------------------------------------------------------------------------------------------------
# Corpus driver: `zig build assets-sprites`.

PREFIX = 'sp2shaders:'
SP2_SUFFIX = '.sp2'
SCRIPT = 'scripts/dkq3-sprites.shader'
SIDECAR_SUFFIX = '.json'
CONVERTED, OVERRIDDEN, FAILED = dkm2md3.CONVERTED, dkm2md3.OVERRIDDEN, dkm2md3.FAILED
RESOLUTIONS = (STEP6, VARIANT_RESOLUTION, MISSING, UNLOADABLE)


class Corpus:
    """The game directory as the 1.3 file system searches it: loose files, pak5.pak, then pak9.pak..pak0.pak
    (dkm2md3.search_order)."""

    def __init__(self, game, pak5):
        self.root, self.archives = game.root, dkm2md3.search_order(game, pak5)

    def read(self, origin, name):
        """The bytes of `name` from `origin`: an archive name, or the loose file's path relative to the game directory."""
        archives = dict(self.archives)
        if origin in archives:
            return archives[origin].read(name)
        return _read_file(os.path.join(self.root, origin))

    def find(self, entry):
        """-> (`<entry>` for a loose file or `<archive>:<entry>`, bytes) of the first holder of `entry`, or None."""
        loose = _read_file(os.path.join(self.root, entry))
        if loose is not None:
            return entry, loose
        return next(((f'{name}:{entry}', pak.read(entry)) for name, pak in self.archives if entry in pak.entries), None)


def _read_file(path):
    if not os.path.isfile(path):
        return None
    with open(path, 'rb') as f:
        return f.read()


def convert_copy(corpus, step6, name, origin):
    """-> (report row, (Converted, frame images) or None) of one archive copy of a sprite; every error becomes a failed row."""
    row = dict(name=name, archive=origin)
    try:
        sprite = sp2.read(corpus.read(origin, name), name)
        images = [resolve_frame(frame.name, corpus.find, step6) for frame in sprite.frames]
        converted = convert(sprite, images, origin)
    except Exception as error:  # every per-sprite error is reported by name; none may stop the other sprites unreported
        return dict(row, status=FAILED, error=f'{type(error).__name__}: {error}'), None
    frames = [{key: record[key] for key in ('index', 'name', 'resolution', 'image', 'source')} for record in converted.sidecar['frames']]
    return dict(row, status=CONVERTED, sidecar=name + SIDECAR_SUFFIX, frames=frames, shaders=len(converted.shaders),
                losses=converted.losses), (converted, images)


def package_entries(results):
    """-> the pk3 entries sorted by name: every packaged sprite's sidecar and frame images, one script of every shader sorted by
    name, and the notexture image."""
    entries, scripts = {NOTEXTURE_IMAGE: shadergen.tga_bytes(shadergen.notexture_image())}, {}
    for row, output in results:
        if row['status'] != CONVERTED:
            continue
        converted, images = output
        entries[row['sidecar']] = sidecar_bytes(converted.sidecar)
        sprite_name = converted.sidecar['sprite']
        frames = converted.sidecar['frames']
        lines = [f'dk3_sprite 1 {len(frames)}']
        for frame in frames:
            lines.append(f'{frame["width"]} {frame["height"]} {frame["origin_x"]} {frame["origin_y"]} '
                         f'"{frame["shader"]}" "{frame["alphachannel_shader"]}"')
        entries[sprite_name + '.frames'] = ('\n'.join(lines) + '\n').encode('latin1')
        entries[sprite_name + '.anim'] = (f'dk3_animation 1 {len(frames)}\namba 0 {len(frames) - 1} 10\n').encode('ascii')
        scripts.update(converted.shaders)
        entries.update((image.image, image.png) for image in images if image.png is not None)
    entries[SCRIPT] = ''.join(scripts[name] for name in sorted(scripts)).encode('latin1')
    return sorted(entries.items())


def document(rows):
    packaged = [row for row in rows if row['status'] == CONVERTED]
    status = collections.Counter(row['status'] for row in rows)
    resolutions = collections.Counter(frame['resolution'] for row in packaged for frame in row['frames'])
    losses = collections.Counter(loss['reason'] for row in packaged for loss in row['losses'])
    images = {frame['image'] for row in packaged for frame in row['frames'] if frame['image'] != NOTEXTURE_IMAGE}
    return dict(entries=len(rows), packaged=status[CONVERTED], converted=status[CONVERTED] + status[OVERRIDDEN],
                overridden=status[OVERRIDDEN], failed=sorted({row['name'] for row in rows if row['status'] == FAILED}),
                frames=sum(len(row['frames']) for row in packaged), shaders=sum(row['shaders'] for row in packaged),
                images=len(images), resolutions={r: resolutions[r] for r in RESOLUTIONS}, losses=dict(sorted(losses.items())),
                sprites=rows)


def summary_line(row):
    if row['status'] == FAILED:
        return f"{PREFIX} {row['name']} ({row['archive']}): failed: {row['error']}"
    found = collections.Counter(frame['resolution'] for frame in row['frames'])
    return (f"{PREFIX} {row['name']} ({row['archive']}): {row['status']}, {len(row['frames'])} frames, {row['shaders']} shaders; images "
            + ', '.join(f'{r} {found[r]}' for r in RESOLUTIONS) + '; losses ' + (', '.join(l['reason'] for l in row['losses']) or 'none'))


def summary(report):
    lines = [summary_line(row) for row in report['sprites']]
    lines.append(f'{PREFIX} resolutions ' + ', '.join(f'{r} {n}' for r, n in report['resolutions'].items()))
    lines.append(f'{PREFIX} losses ' + (', '.join(f'{r} {n}' for r, n in report['losses'].items()) or 'none'))
    lines.append(f"{PREFIX} total: {report['entries']} entries, {report['packaged']} sprites packaged, {report['converted']} converted "
                 f"({report['overridden']} overridden), {len(report['failed'])} failed; {report['frames']} frames, "
                 f"{report['shaders']} shaders, {report['images']} images")
    return lines


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--data', required=True, help='game directory (zig build -DDK_DATA): loose files and pak0.pak-pak9.pak')
    ap.add_argument('--pak5', help='pak5.pak extracted from pak5.zip, searched before the numbered archives')
    ap.add_argument('--images', required=True, help='images directory written by dk_extract.py: the Step 6 <key>.png files')
    ap.add_argument('--pk3', required=True, help='pk3 to write: every packaged sidecar, frame image, the shader script and notexture')
    ap.add_argument('--report', required=True, help='JSON report to write')
    ap.add_argument('--summary', required=True, help='text report to write: the lines printed on stdout')
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    pak5 = dkpak.Pak(args.pak5) if args.pak5 else None
    with dk2q3.GameDir(args.data) as game:
        corpus = Corpus(game, pak5)
        copies = dkm2md3.discover(game.root, corpus.archives, suffix=SP2_SUFFIX)
        results = [convert_copy(corpus, lambda key: _read_file(os.path.join(args.images, key + PNG)), name, origin)
                   for name, origins in copies.items() for origin in origins]
    rows = dkm2md3.table(copies, [row for row, _ in results])
    report = document(rows)
    lines = summary(report)
    for path in (args.report, args.summary, args.pk3):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(args.report, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=1, sort_keys=True)
        f.write('\n')
    with open(args.summary, 'w', encoding='utf-8') as f:
        f.write(''.join(line + '\n' for line in lines))
    print('\n'.join(lines))
    for row in (row for row in rows if row['status'] == FAILED):
        print(f"{PREFIX} FAIL {row['name']} ({row['archive']}): {row['error']}", file=sys.stderr)
    if report['failed']:
        return 1
    pk3.write(args.pk3, package_entries(results))
    return 0


if __name__ == '__main__':
    sys.exit(main())
