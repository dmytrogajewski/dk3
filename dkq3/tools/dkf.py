#!/usr/bin/env python3
"""Daikatana `.dkf` fonts and the HUD art package (specs/ports/PORT-hud.md).

A `.dkf` file is pure metrics: 780 bytes of magic, version, height and three 256-byte tables (the width of each
character, its x position in the glyph sheet and its y position), read by `ReadDKF`
(reference/dk-gold/base/ref_common/dk_ref_font.cpp:42-84). Because it carries no pixels, the package keeps the file
**verbatim** and the cgame parses the same bytes at run time; only the glyph sheet is converted. Gold draws a font from
`fonts/<name>.font.bmp` (`dk_ref_font.cpp:138`), an 8-bit BMP whose index 255 is transparent, which `dk_extract.py`
already decodes, so the sheet is taken from that decode and written as a TGA the renderer loads.

Text measurement and wrapping belong to the independent shared client/UI glyph
code in src/shared/dk_font.h. This converter validates and packages supplied metrics
and artwork; it contains no translated font-layout routines.

usage: dkf.py --data=DIR --manifest=FILE --images=DIR --pk3=FILE --report=FILE --summary=FILE [--pak5=FILE]

FRD: specs/frds/FRD-029-hud-fonts-and-client-presentation.md
"""
import argparse
import collections
import json
import os
import struct
import sys

import dk2q3
import dk_extract
import dkimg
import dkm2md3
import dkpak
import pk3
import sky

PREFIX = "dkf:"

# The header ReadDKF reads: the 4-byte magic, then two int32 (dk_ref_font.cpp:52-71).
MAGIC = b"dkf "
VERSION = 0
HEADER = struct.Struct("<4sii")
MAGIC_AT, VERSION_AT, HEIGHT_AT = 0, 4, 8
# Three tables of one byte per character: width, x position, y position (dk_ref_font.h:17-26).
TABLE_ENTRIES = 256
WIDTH_AT = HEADER.size
POS_X_AT = WIDTH_AT + TABLE_ENTRIES
POS_Y_AT = POS_X_AT + TABLE_ENTRIES
FILE_SIZE = POS_Y_AT + TABLE_ENTRIES

DKF_SUFFIX = ".dkf"
# Gold builds the sheet path from the font name: "fonts/%s.font.bmp" (dk_ref_font.cpp:138). The extraction keys an entry
# by its path without the extension, so the sheet of `<base>.dkf` is the image key `<base>.font`.
SHEET_KEY_SUFFIX = ".font"
SPACE = ord(" ")
# A character the font does not define (dk_ref_font.cpp:174-178).
ABSENT = 0

# The art the status bar, the crosshair, the inventory and the menus draw; every key under these prefixes is
# packaged. `pics/interface/` holds the menu cursor and its backgrounds and `pics/menu/` the three skill pictures
# of the new-game screen (reference/dk-gold/base/dk_/dk_menu.cpp `bitmaps`, dk_menu_newgame.cpp `skill_pics`),
# which roadmap Step 40 draws. `skins/ib_` holds the fourteen faces of 1.3's front-end button strip plus Gold's
# blank and help ones (dk_menu.cpp `button_skins`): 1.3 wraps them on `models/interface/ib_button.dkm`, which is
# where their labels come from, and so does the port, through the `dkq3/menu/` shaders below.
# Roadmap Step 44 (specs/ports/PORT-environments.md) added two names. "pics/particles/" is Daikatana's own particle atlas,
# the single 256x128 image every client-side particle takes its art from as a sub-rectangle (base/ref_gl/gl_particle.cpp
# R_InitParticles); the weather families draw out of it, so it is packaged rather than approximated. "pics/final_end" is
# the 256x256 plate `draw_theend` fades in when the server sends svc_end_of_game (base/client/cl_scrn.cpp:2769-2792).
# BUG-loading-screen-is-missing added "pics/load", which is the WHOLE loading-screen family and nothing else: the two
# progress-bar images `pics/loadbar` and `pics/loadblock` (base/client/cl_scrn.cpp SCR_DrawLoading) and the
# `pics/loadscreens/` tree Gold tiles the plaque out of (base/client/console.cpp Con_DrawConsolePic, six
# `<name>_<index>.bmp` per set). It is a PREFIX rather than a list of the 27 sets, so a set the corpus holds and this
# file does not know about is packaged anyway. The one thing under the prefix the port does not draw, 1.3's own
# `<name>_unified.tga`, is taken back out by UNIFIED_SUFFIX below.
ART_PREFIXES = ("pics/statusbar/", "pics/crosshair/", "pics/interface/", "pics/menu/", "pics/particles/", "pics/final_end", "pics/load", "skins/ib_")
# Family 5 of specs/ports/PORT-render-effects.md (beams): the images Gold's renderer binds by name for its beam list
# (base/ref_gl/gl_rmisc.cpp:18-27 R_InitMiscTextures, BEAM_TEX_LIGHTNING .. BEAM_TEX_DISCUSTRAIL), each a 64x64 (the tracer
# 16x16) glow on black with an alpha channel, drawn as the texture of a beam quad by src/cgame/effects/dk_effects.c through
# build/cgame.zig's `dkq3/beam/<name>` shaders. Exact keys, not a prefix: `pics/misc/` also holds the laserburn decals,
# laser3 and the charflares, which nothing packaged draws. The two skins the table also names (we_mflash2, we_sclawslash)
# are a rejected image and the grapple chain no Gold code draws.
BEAM_ART_KEYS = frozenset(("pics/misc/w_zap001", "pics/misc/laser", "pics/misc/beamspark", "pics/misc/novalaser",
                           "pics/misc/tracer", "pics/misc/we_disctr"))
# 1.3's own single-texture loading plaque. pak5 adds a `pics/loadscreens/<name>_unified.tga`, 1024x512 with 768x480 of
# artwork in it, beside each set of six tiles -- the same repacking `pics/interface/back_unified` is of the menu's tiles.
# The port draws Gold's six tiles (base/client/console.cpp Con_DrawConsolePic), whose composite IS the 640x480 screen, and
# nothing reads the unified variant, whose drawn window 1.3 alone knows. Twenty-seven of them are 56 MB of an UNCOMPRESSED
# package (pk3.py stores every entry), so they are left out by this rule -- a suffix, not a list of names, so a set the
# corpus holds and this file does not know about still has its tiles packaged
# (specs/bugs/BUG-loading-screen-is-missing.md "What Gold does that the port does not").
LOADSCREEN_PREFIX = "pics/loadscreens/"
UNIFIED_SUFFIX = "_unified"

# The strip's plate shaders (specs/ports/PORT-menus.md "The strip in 3D"). 1.3 renders `models/interface/ib_button.dkm`
# fourteen times, each copy wearing one `skins/ib_*` face as its skin (dk_menu.cpp `PlaceButtons`, `button->skin`), with
# RF_FULLBRIGHT, and gives a plate that may not be used the colour 0.25 (gl_mesh.cpp `GL_LightVerts` takes a non-zero
# entity colour as the vertex colour itself). ioquake3 can put a skin on a whole model only as `customShader`, and only a
# scripted shader can light a model from the entity's colour, so the package defines one shader per face under
# `dkq3/menu/`: the face's own TGA, `rgbGen entity` (the ui gives 255 for full bright, 64 for Gold's 0.25), no picmip
# because Gold's interface art is never reduced, NO MIPMAPS because Gold refuses them to every image whose name holds
# "ib_" ("We don't want interface skins to mipmap", gl_image.cpp:1633-1637 -- measured: the strip region of SCN-menus
# fell from 0.127 to 0.039 when the port matched it), and Gold's alias-model rules for a skin with an alpha channel --
# alpha test GL_GREATER 0 and no face culling (gl_mesh.cpp:398-405, :1760-1761), as dkm2md3.py's model skins take them.
MENU_SKIN_PREFIX = "skins/ib_"
# The panels' borders and plaques (specs/ports/PORT-menus.md "The panels"): Gold draws every CInterfaceBox and
# CInterfaceLine as `models/interface/iu_unitbox.dkm` wearing `skins/iu_buttonmini.wal`, and a CInterfacePicker's plaque
# wearing `skins/iu_plaque.bmp` (dk_menu_controls.cpp). RegisterSkin loads `<base>.wal` before the name itself
# (gl_image.cpp:1863-1900), so the plaque is the WAL's metal plate, not the flat BMP the image step keys the name to: it
# is decoded here from the archives, as dkm2md3.py decodes a model skin, and packaged as `skins/iu_plaque@wal`.
# `pics/noscreen_avail` is the load and save panels' "no screen available" plate. Their shaders mipmap: Gold's
# "ib_"-only rule leaves `iu_` skins mipmapped (gl_image.cpp:1633-1637).
BORDER_ART_KEYS = frozenset(("skins/iu_buttonmini", "pics/noscreen_avail"))
BORDER_SHADERS = (("dkq3/menu/iu_buttonmini", "skins/iu_buttonmini"), ("dkq3/menu/iu_plaque", "skins/iu_plaque@wal"))
PLAQUE_KEY = "skins/iu_plaque@wal"
PLAQUE_SOURCE = "skins/iu_plaque.wal"
MENU_SHADER_PREFIX = "dkq3/menu/"
MENU_SHADER_SCRIPT = "scripts/dkq3-menu.shader"
# The one flat fill the front end draws: the highlight bars of a file list and the shade under a dialog, which 1.3 draws
# translucent. The engine's own "white" shader takes no alpha from trap_R_SetColor (its stage is GL_ONE GL_ZERO), so the
# package defines a blended one and the ui registers it (specs/ports/PORT-menus.md "Widgets").
FILL_SHADER = ("dkq3/menu/fill\n{\n\tnopicmip\n\tnomipmaps\n\t{\n\t\tmap $whiteimage\n"
               "\t\tblendFunc GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA\n\t\trgbGen vertex\n\t\talphaGen vertex\n\t}\n}\n")
# `status` of a manifest entry that produced an image.
IMAGE = "image"
PNG = ".png"
TGA = ".tga"

# An uncompressed 32-bit TGA, the form the renderer reads (code/renderercommon/tr_image_tga.c). ioquake3 stores the last
# file row at the top and ignores the top-down flag, so the file holds the bottom row first.
TGA_HEADER = struct.Struct("<BBBHHBHHHHBB")
TGA_TRUE_COLOUR = 2
TGA_BITS = 32
TGA_ALPHA_BITS = 8

# The one packaged art image whose artwork does not fill its texture. `pics/interface/back_unified` is a 1024x512 texture
# -- the next power of two of its 896x480 artwork in each dimension, so the renderer never resamples it -- and a menu that
# draws the whole texture puts that padding on screen as a black border down the right and along the bottom
# (specs/bugs/BUG-menu-background-shows-its-padding.md). The extent is measured from the artwork here and packaged beside
# the TGA, so the ui reads the artwork's own size rather than carrying a number of its own, exactly as it reads a glyph
# sheet's size from that sheet's TGA header.
BACKGROUND_KEY = "pics/interface/back_unified"
EXTENT_SUFFIX = ".extent"
EXTENT = struct.Struct("<HH")
# A texel none of whose colour channels passes this is padding. Measured on back_unified: the strongest texel outside the
# artwork reaches 8 -- the tail of the filter that resampled the artwork into the power-of-two texture -- while the
# faintest artwork column peaks at 61 and the faintest artwork row at 96, so every threshold in 8..60 measures the same
# 896x480 and 32 sits in the middle of that window. `extent_row` reports both edges of the window, so a corpus that
# closed it is visible rather than silently re-measured.
PADDING_MAX_CHANNEL = 32

USAGE = __doc__.split("usage: ")[1].split("\n")[0]


class DkfError(ValueError):
    """A `.dkf` file ReadDKF would refuse."""

    def __init__(self, font, offset, detail):
        super().__init__(f"{font}: offset {offset}: {detail}")
        self.font, self.offset = font, offset


class BadMagic(DkfError):
    """The first four bytes are not `dkf ` (dk_ref_font.cpp:56-61)."""


class UnsupportedVersion(DkfError):
    """The version is not 0 (dk_ref_font.cpp:66-71)."""


class BadHeight(DkfError):
    """A height of 0 or below leaves every glyph empty."""


class Truncated(DkfError):
    """The file is shorter than the header and its three tables."""


Font = collections.namedtuple("Font", "name height width pos_x pos_y")
"""`width`, `pos_x` and `pos_y` are 256-byte tables indexed by character."""


def read(raw, name):
    """-> Font, as ReadDKF fills a dk_font; a file it would refuse raises."""
    if len(raw) < FILE_SIZE:
        raise Truncated(name, len(raw), f"{len(raw)} bytes; ReadDKF reads {FILE_SIZE}")
    magic, version, height = HEADER.unpack_from(raw)
    if magic != MAGIC:
        raise BadMagic(name, MAGIC_AT, f"{magic!r} where ReadDKF requires {MAGIC!r}")
    if version != VERSION:
        raise UnsupportedVersion(name, VERSION_AT, f"version {version}; ReadDKF reads {VERSION}")
    if height <= 0:
        raise BadHeight(name, HEIGHT_AT, f"height {height}")
    return Font(name, height, raw[WIDTH_AT:POS_X_AT], raw[POS_X_AT:POS_Y_AT], raw[POS_Y_AT:FILE_SIZE])


def font_height(font):
    """-> the height of every glyph (Gold FontHeight, dk_ref_font.cpp:157-163)."""
    return font.height


def glyphs(font):
    """-> the characters the font defines, in order."""
    return [c for c in range(TABLE_ENTRIES) if font.width[c] != ABSENT]


def fits_sheet(font, width, height):
    """-> the characters whose glyph box leaves the `width` by `height` sheet."""
    return [c for c in glyphs(font)
            if font.pos_x[c] + font.width[c] > width or font.pos_y[c] + font.height > height]


def tga(image):
    """-> uncompressed 32-bit TGA bytes of an (H, W, 3|4) RGB(A) image, bottom row first."""
    height, width, channels = image.shape
    header = TGA_HEADER.pack(0, 0, TGA_TRUE_COLOUR, 0, 0, 0, 0, 0, width, height, TGA_BITS, TGA_ALPHA_BITS)
    rgba = image if channels == 4 else _opaque(image)
    # TGA texels are blue, green, red, alpha.
    return header + rgba[::-1, :, [2, 1, 0, 3]].tobytes()


def _opaque(image):
    import numpy as np

    alpha = np.full(image.shape[:2] + (1,), 255, np.uint8)
    return np.concatenate((image, alpha), axis=2)


def _visible(image, max_channel=PADDING_MAX_CHANNEL):
    """-> an (H, W) mask of the texels that are not padding: opaque and with a colour channel past `max_channel`."""
    mask = image[:, :, :3].max(axis=2) > max_channel
    if image.shape[2] > 3:
        mask = mask & (image[:, :, 3] > 0)
    return mask


def used_extent(image, max_channel=PADDING_MAX_CHANNEL):
    """-> (width, height) of the top-left box outside which every column and row is padding.

    Rows are counted from the top, as the renderer draws them. An image that is padding throughout measures (0, 0).
    """
    import numpy as np

    visible = _visible(image, max_channel)
    columns = np.nonzero(visible.any(axis=0))[0]
    rows = np.nonzero(visible.any(axis=1))[0]
    return (int(columns[-1]) + 1 if columns.size else 0, int(rows[-1]) + 1 if rows.size else 0)


def extent_row(image, key, max_channel=PADDING_MAX_CHANNEL):
    """-> the report row of `key`'s artwork extent: its texture size, the used box and the window `max_channel` sits in.

    `artwork_floor` is the peak of the faintest column or row of the artwork and `padding_peak` the strongest colour
    channel anywhere outside it, so every threshold from `padding_peak` to `artwork_floor - 1` measures the same box.
    They are the evidence that the threshold cut the artwork where it ends rather than somewhere inside it.
    """
    import numpy as np

    height, width = image.shape[0], image.shape[1]
    used_width, used_height = used_extent(image, max_channel)
    colour = image[:, :, :3].max(axis=2)
    if not used_width or not used_height:
        return dict(key=key, size=[int(width), int(height)], used=[used_width, used_height],
                    artwork_floor=0, padding_peak=int(colour.max()))
    used = colour[:used_height, :used_width]
    floor = min(int(used.max(axis=0).min()), int(used.max(axis=1).min()))
    outside = max(int(colour[used_height:, :].max()) if used_height < height else 0,
                  int(colour[:, used_width:].max()) if used_width < width else 0)
    return dict(key=key, size=[int(width), int(height)], used=[used_width, used_height],
                artwork_floor=floor, padding_peak=outside)


def _image_file(images, records, key):
    """-> the extraction's PNG path for `key`, or None when it produced no image."""
    record = records.get(key)
    if not record or record.get("status") != IMAGE or not record.get("files"):
        return None
    return os.path.join(images, record["files"][0]["file"])


def _read(path):
    with open(path, "rb") as f:
        return f.read()


def unified_loadscreen(key):
    """-> whether `key` is 1.3's single-texture loading plaque, which the port does not draw (UNIFIED_SUFFIX)."""
    return key.startswith(LOADSCREEN_PREFIX) and key.endswith(UNIFIED_SUFFIX)


def art_keys(records):
    """-> the HUD art keys of the extraction plus the beam textures, sorted; font sheets are left to the fonts that name
    them and 1.3's unified loading plaques to the rule above."""
    return sorted(key for key in records
                  if (key.startswith(ART_PREFIXES) or key in BEAM_ART_KEYS or key in BORDER_ART_KEYS)
                  and not key.endswith(SHEET_KEY_SUFFIX) and not unified_loadscreen(key))


def menu_shader_name(key):
    """`skins/ib_singleplay` -> `dkq3/menu/ib_singleplay`, the name the ui registers for a plate face."""
    return MENU_SHADER_PREFIX + key[len("skins/"):]


def border_shader_script():
    """-> the stanzas of the panels' border and plaque skins, lit by the entity's colour like the plates."""
    return "".join(f"{name}\n{{\n\tnopicmip\n\t{{\n\t\tmap {image}{TGA}\n\t\trgbGen entity\n\t}}\n}}\n"
                   for name, image in BORDER_SHADERS)


def plaque_image(game):
    """-> the (H, W, 4) plaque Gold's RegisterSkin shows for skins/iu_plaque.bmp: the WAL, decoded by the Step 6 decoder."""
    entry = game.find(PLAQUE_SOURCE)
    if entry is None:
        raise DkfError(PLAQUE_SOURCE, 0, "no archive holds it")
    status, images, _, _ = dk_extract._decode(PLAQUE_SOURCE, entry[1], dk_extract.SKIN, [])
    if status != dk_extract.IMAGE:
        raise DkfError(PLAQUE_SOURCE, 0, f"decodes to {status}")
    return images[0][1]


def menu_shader_script(faces):
    """-> scripts/dkq3-menu.shader: one stanza per (key, has alpha) of `faces`, sorted by key, then the border skins."""
    stanzas = []
    for key, alpha_channel in sorted(faces):
        cull = "\tcull disable\n" if alpha_channel else ""
        test = "\t\talphaFunc GT0\n" if alpha_channel else ""
        stanzas.append(f"{menu_shader_name(key)}\n{{\n\tnopicmip\n\tnomipmaps\n{cull}\t{{\n\t\tmap {key}{TGA}\n{test}"
                       f"\t\trgbGen entity\n\t}}\n}}\n")
    return "".join(stanzas) + border_shader_script() + FILL_SHADER


def convert_font(game, images, records, name, origins):
    """-> (row, entries): the packaged `.dkf` and its sheet, or a row whose `error` says why not."""
    row = dict(name=name, origin=origins[0], overridden=origins[1:], status="failed", error=None,
               height=0, glyphs=0, sheet=None, sheet_size=None)
    found = game.find(name)
    if found is None:
        row["error"] = "the search path no longer holds it"
        return row, []
    origin, raw = found
    row["origin"] = origin
    try:
        font = read(raw, name)
    except DkfError as error:
        row["error"] = str(error)
        return row, []
    row.update(height=font.height, glyphs=len(glyphs(font)))
    key = name[: -len(DKF_SUFFIX)] + SHEET_KEY_SUFFIX
    sheet = _image_file(images, records, key)
    if sheet is None:
        row["error"] = f"no decoded glyph sheet for {key}"
        return row, []
    image = dkimg.read_png(sheet)
    outside = fits_sheet(font, image.shape[1], image.shape[0])
    if outside:
        row["error"] = (f"{len(outside)} glyphs leave the {image.shape[1]}x{image.shape[0]} sheet "
                        f"{key}: {outside[:8]}")
        return row, []
    row.update(status="packaged", sheet=key, sheet_size=[int(image.shape[1]), int(image.shape[0])])
    base = name[: -len(DKF_SUFFIX)]
    entries = [(name, raw), (base + TGA, tga(image)),
               (name + ".json", _sidecar(font, key, image).encode("utf-8"))]
    if name == 'fonts/con_font.dkf':
        entries.append(('gfx/2d/bigchars.tga', console_atlas(font, image)))
        entries.append(('scripts/dk3-console-font.shader', b'''gfx/2d/bigchars
{
 nopicmip
 nomipmaps
 { map gfx/2d/bigchars.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
 }
}
'''))
    return row, entries


def console_atlas(font, image):
    """Adapt supplied glyphs to the engine console's fixed 16-by-16 grid."""
    import numpy as np
    cell = 1
    while cell < max(font.height, max(font.width[32:127])):
        cell *= 2
    atlas = np.zeros((cell * 16, cell * 16, 4), dtype=np.uint8)
    for character in glyphs(font):
        width = font.width[character]
        x, y = font.pos_x[character], font.pos_y[character]
        glyph = image[y:y + font.height, x:x + width]
        ratio = min(1, cell / max(width, font.height))
        target_width, target_height = max(1, int(width * ratio)), max(1, int(font.height * ratio))
        columns = np.minimum(width - 1, np.arange(target_width) * width // target_width)
        rows = np.minimum(font.height - 1, np.arange(target_height) * font.height // target_height)
        sampled = glyph[rows[:, None], columns]
        left = (character % 16) * cell + (cell - target_width) // 2
        top = (character // 16) * cell + (cell - target_height) // 2
        atlas[top:top + target_height, left:left + target_width, :sampled.shape[2]] = sampled
        if sampled.shape[2] == 3:
            atlas[top:top + target_height, left:left + target_width, 3] = np.any(sampled != 0, axis=2) * 255
    return tga(atlas)


def _sidecar(font, sheet, image):
    """The font's own tables as JSON, so a test can compare the package with the source without re-reading the pak."""
    return json.dumps(dict(height=font.height, sheet=sheet,
                           sheet_size=[int(image.shape[1]), int(image.shape[0])],
                           glyphs={str(c): [font.width[c], font.pos_x[c], font.pos_y[c]] for c in glyphs(font)}),
                      indent=1, sort_keys=True) + "\n"


def document(rows, art, extents):
    packaged = [row for row in rows if row["status"] == "packaged"]
    return dict(fonts=rows, packaged=len(packaged), failed=len(rows) - len(packaged), art=art, art_extents=extents)


def summary(report):
    rows = report["fonts"]
    lines = [f"{PREFIX} {len(rows)} fonts, {report['packaged']} packaged, {report['failed']} failed"]
    for row in rows:
        if row["status"] == "packaged":
            overridden = f", overrides {len(row['overridden'])}" if row["overridden"] else ""
            lines.append(f"{PREFIX} {row['name']} ({row['origin']}): height {row['height']}, "
                         f"{row['glyphs']} glyphs, sheet {row['sheet']} "
                         f"{row['sheet_size'][0]}x{row['sheet_size'][1]}{overridden}")
    lines.append(f"{PREFIX} {len(report['art'])} HUD art images, "
                 f"{len([key for key in report['art'] if key.startswith(LOADSCREEN_PREFIX)])} loading plaque tiles "
                 f"({report['unified_loadscreens']} 1.3 `{UNIFIED_SUFFIX}` plaques left out, the port draws Gold's tiles)")
    lines.append(f"{PREFIX} {len(report.get('menu_shaders', []))} menu plate shaders in {MENU_SHADER_SCRIPT}")
    for extent in report["art_extents"]:
        lines.append(f"{PREFIX} {extent['key']} artwork {extent['used'][0]}x{extent['used'][1]} of a "
                     f"{extent['size'][0]}x{extent['size'][1]} texture "
                     f"(padding peak {extent['padding_peak']}, artwork floor {extent['artwork_floor']}, "
                     f"threshold {PADDING_MAX_CHANNEL})")
    return lines


def parse_args(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], usage=USAGE)
    ap.add_argument("--data", required=True, help="game data corpus directory")
    ap.add_argument("--pak5", help="pak5.pak extracted from pak5.zip")
    ap.add_argument("--manifest", required=True, help="manifest.json written by dk_extract.py")
    ap.add_argument("--images", required=True, help="directory of the <key>.png files dk_extract.py wrote")
    ap.add_argument("--pk3", required=True, help="package to write")
    ap.add_argument("--report", required=True, help="JSON report to write")
    ap.add_argument("--summary", required=True, help="text summary to write")
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    with open(args.manifest, encoding="utf-8") as f:
        records = json.load(f)["images"]
    pak5 = dkpak.Pak(args.pak5) if args.pak5 else None
    try:
        with dk2q3.GameDir(args.data) as game:
            archives = dkm2md3.search_order(game, pak5)
            found = dkm2md3.discover(game.root, archives, suffix=DKF_SUFFIX)
            results = [convert_font(game, args.images, records, name, origins)
                       for name, origins in found.items()]
            plaque = plaque_image(game)
            sky_entries, sky_report = sky.entries(game, args.images, records, tga)
    finally:
        if pak5 is not None:
            pak5.close()
    rows = [row for row, _ in results]
    entries = [entry for _, pairs in results for entry in pairs]
    entries.extend(sky_entries)
    art = art_keys(records)
    extents = []
    faces = []
    for key in art:
        path = _image_file(args.images, records, key)
        if path is None:
            continue
        image = dkimg.read_png(path)
        entries.append((key + TGA, tga(image)))
        if key.startswith(MENU_SKIN_PREFIX):
            faces.append((key, dkm2md3.png_has_alpha(_read(path))))
        # The menus draw the background as a sub-rectangle of its texture, so its artwork extent ships with it.
        if key == BACKGROUND_KEY:
            extent = extent_row(image, key)
            extents.append(extent)
            entries.append((key + EXTENT_SUFFIX, EXTENT.pack(*extent["used"])))
    entries.append((PLAQUE_KEY + TGA, tga(plaque)))
    entries.append((MENU_SHADER_SCRIPT, menu_shader_script(faces).encode("utf-8")))
    report = document(rows, art, extents)
    report['skies'] = sky_report
    report["unified_loadscreens"] = len([key for key in records if unified_loadscreen(key)])
    report["menu_shaders"] = [menu_shader_name(key) for key, _ in sorted(faces)]
    lines = summary(report)
    for path in (args.report, args.summary, args.pk3):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(args.report, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, sort_keys=True)
        f.write("\n")
    with open(args.summary, "w", encoding="utf-8") as f:
        f.write("".join(line + "\n" for line in lines))
    print("\n".join(lines))
    for row in rows:
        if row["status"] != "packaged":
            print(f"{PREFIX} FAIL {row['name']}: {row['error']}", file=sys.stderr)
    if report["failed"]:
        return 1
    pk3.write(args.pk3, sorted(entries))
    return 0


if __name__ == "__main__":
    sys.exit(main())
