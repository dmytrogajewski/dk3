"""The standalone dkq3 base game package `dkq3-base.pk3`: the files the stock ioquake3 client and native modules
require to start the standalone game `dkq3` and put a player in a map. Every byte comes from the named constants
below; no file is read. specs/assets/ASSET-base.md traces each entry to the engine line that requires it.

usage: basegame.py OUT_PK3    writes the package to OUT_PK3

FRD: specs/frds/FRD-010-standalone-dkq3-base-game-package.md
"""
import math
import struct
import sys
from collections import namedtuple

import md3
import pk3

USAGE = "usage: basegame.py OUT_PK3\n"

# default.cfg: FS_InitFilesystem stops without it (code/qcommon/files.c:4137). Only gameplay bindings: the client
# handles Escape and the console key itself (code/client/cl_keys.c:1261-1301), and no engine cvar is set.
DEFAULT_CFG_HEADER = "// dkq3 base game: default key bindings (dkq3/tools/basegame.py)"
BINDINGS = (("w", "+forward"), ("s", "+back"), ("a", "+moveleft"), ("d", "+moveright"), ("SPACE", "+moveup"),
            ("c", "+movedown"), ("MOUSE1", "+attack"), ("MOUSE2", "detonate"), ("SHIFT", "+speed"), ("F11", "screenshot"),
            ("e", "use"), ("i", "inventory"), ("MWHEELUP", "weapprev"), ("MWHEELDOWN", "weapnext"),
            ("F5", "save quick"), ("F9", "load quick"), ("f", "companion follow"), ("h", "companion wait"),
            ("g", "companion attack"), ("j", "companion pickup"), ("p", "attribute_next"),
            ("o", "attribute_increase"), ("ENTER", "cin_skip"), ("TAB", "+scores"))

# sound/feedback/hit.wav: the default sound effect (code/client/snd_openal.c:484, code/client/snd_dma.c:402), a short
# square-wave click in 16-bit mono PCM (code/client/snd_codec_wav.c:131-176).
WAV_PCM, WAV_CHANNELS, WAV_RATE, WAV_BITS = 1, 1, 22050, 16
HIT_SAMPLES = 1102
HIT_HALF_PERIOD = 25
HIT_AMPLITUDE = 4096

# white.tga: the client registers the shader "white" at startup (code/client/cl_main.c:3176) and fills the letterbox of
# a screen wider than 4:3 with it under g_color_table[0], black (code/client/cl_scrn.c:483-489). Without the image
# R_FindShader falls back to the DEFAULT shader, whose stage is opaque CGEN_IDENTITY (tr_shader.c R_CreateBuiltinShaders,
# ComputeColors), so the fill ignores that colour and paints the bars WHITE
# (specs/bugs/BUG-menu-video-resolution-and-border.md, measured: "Couldn't find image file for shader white"). A plain
# white image makes the same call a 2D shader with rgbGen/alphaGen vertex (tr_shader.c "GUI elements"), which takes the
# colour and the alpha the client asks for.
WHITE_TEXTURE = "white.tga"
WHITE_SIZE, WHITE_RGB = 8, (0xFF, 0xFF, 0xFF)

# The player model: DEFAULT_MODEL "sarge" with skin "default" (code/cgame/cg_local.h:83, cg_players.c:689).
PLAYER_DIR = "models/players/sarge/"
SKIN_TEXTURE = PLAYER_DIR + "sarge.tga"
ICON = PLAYER_DIR + "icon_default.tga"
# Uncompressed true-colour TGA (code/renderercommon/tr_image_tga.c:102-116), power-of-two squares of one colour.
TGA_HEADER = struct.Struct("<BBBHHBHHHHBB")
TGA_TRUE_COLOUR, TGA_BITS = 2, 24
TEXTURE_SIZE, ICON_SIZE = 8, 32
SKIN_RGB, ICON_RGB = (0x80, 0x60, 0x40), (0x40, 0x60, 0x80)

# Three boxes inside the stock player box, mins (-15, -15, -24) and maxs (15, 15, 32) (code/game/g_client.c:27-28):
# the legs around the entity origin, the torso on tag_torso and the head on tag_head (code/cgame/cg_players.c:2348,
# :2574); tag_weapon holds the weapon (code/cgame/cg_weapons.c:1252).
Part = namedtuple("Part", "model skin surface mins maxs tags")
TORSO_HEIGHT = 20
PARTS = (
    Part("lower.md3", "lower_default.skin", "l_legs", (-10, -10, -24), (10, 10, 0), (("tag_torso", (0, 0, 0)),)),
    Part("upper.md3", "upper_default.skin", "u_torso", (-10, -10, 0), (10, 10, TORSO_HEIGHT),
         (("tag_head", (0, 0, TORSO_HEIGHT)), ("tag_weapon", (8, -8, 10)))),
    Part("head.md3", "head_default.skin", "h_head", (-6, -6, 0), (6, 6, 10), ()),
)
FRAME_NAME = "frame0"
IDENTITY_AXIS = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
# Encoded normals are 1/256 turns: latitude in the high byte, longitude in the low byte
# (code/renderergl1/tr_surface.c:647-659).
QUARTER_TURN = 64
# The corners of a face are listed counter-clockwise seen from the positive side of its axis. Shaders cull
# CT_FRONT_SIDED with glCullFace(GL_FRONT) (code/renderergl1/tr_backend.c:126-148), so a visible triangle winds
# clockwise seen from outside: reversed on the positive face, as listed on the negative one.
FACE_CORNERS = ((0, 0), (1, 0), (1, 1), (0, 1))
POSITIVE_FACE_TRIANGLES = ((0, 2, 1), (0, 3, 2))
NEGATIVE_FACE_TRIANGLES = ((0, 1, 2), (0, 2, 3))

# animNumber_t from BOTH_DEATH1 to LEGS_TURN (code/game/bg_public.h): CG_ParseAnimationFile needs every one; the
# optional TORSO_GETFLAG .. TORSO_NEGATIVE default to TORSO_GESTURE (code/cgame/cg_players.c:196-205).
ANIMATIONS = ("BOTH_DEATH1", "BOTH_DEAD1", "BOTH_DEATH2", "BOTH_DEAD2", "BOTH_DEATH3", "BOTH_DEAD3", "TORSO_GESTURE",
              "TORSO_ATTACK", "TORSO_ATTACK2", "TORSO_DROP", "TORSO_RAISE", "TORSO_STAND", "TORSO_STAND2",
              "LEGS_WALKCR", "LEGS_WALK", "LEGS_RUN", "LEGS_BACK", "LEGS_SWIM", "LEGS_JUMP", "LEGS_LAND", "LEGS_JUMPB",
              "LEGS_LANDB", "LEGS_IDLE", "LEGS_IDLECR", "LEGS_TURN")
# first frame, frame count, looping frames, frames per second: the one frame of every model.
ANIMATION_ROW = (0, 1, 0, 10)


def default_cfg():
    lines = [DEFAULT_CFG_HEADER] + [f'bind {key} "{command}"' for key, command in BINDINGS]
    return ("\n".join(lines) + "\n").encode("ascii")


def riff_chunk(tag, payload):
    return tag + struct.pack("<I", len(payload)) + payload


def hit_wav():
    samples = b"".join(struct.pack("<h", HIT_AMPLITUDE if i // HIT_HALF_PERIOD % 2 == 0 else -HIT_AMPLITUDE)
                       for i in range(HIT_SAMPLES))
    block_align = WAV_CHANNELS * WAV_BITS // 8
    fmt = struct.pack("<HHIIHH", WAV_PCM, WAV_CHANNELS, WAV_RATE, WAV_RATE * block_align, block_align, WAV_BITS)
    return riff_chunk(b"RIFF", b"WAVE" + riff_chunk(b"fmt ", fmt) + riff_chunk(b"data", samples))


def tga(size, rgb):
    header = TGA_HEADER.pack(0, 0, TGA_TRUE_COLOUR, 0, 0, 0, 0, 0, size, size, TGA_BITS, 0)
    return header + bytes(reversed(rgb)) * (size * size)


def animation_cfg():
    lines = ["// dkq3 base game placeholder player: every animation shows the one frame of the model"]
    lines += ["\t".join(map(str, ANIMATION_ROW)) + f"\t\t// {name}" for name in ANIMATIONS]
    return ("\n".join(lines) + "\n").encode("ascii")


def axis_normal(axis, sign):
    """The encoded normal along +/- axis: longitude from +Z, latitude from +X towards +Y."""
    if axis == 2:
        return 0 if sign > 0 else 2 * QUARTER_TURN
    return (axis + (0 if sign > 0 else 2)) * QUARTER_TURN << 8 | QUARTER_TURN


def box_surface(part):
    """Four vertices per face with the face's outward normal; texture coordinates span each face once."""
    vertices, st, triangles = [], [], []
    bounds = (part.mins, part.maxs)
    for axis in range(3):
        u, v = (axis + 1) % 3, (axis + 2) % 3
        for sign, side in ((-1, 0), (1, 1)):
            first = len(vertices)
            for cu, cv in FACE_CORNERS:
                corner = [0, 0, 0]
                corner[axis], corner[u], corner[v] = bounds[side][axis], bounds[cu][u], bounds[cv][v]
                vertices.append((*corner, axis_normal(axis, sign)))
                st.append((float(cu), float(cv)))
            order = POSITIVE_FACE_TRIANGLES if sign > 0 else NEGATIVE_FACE_TRIANGLES
            triangles += [tuple(first + i for i in triangle) for triangle in order]
    return md3.Surface(name=part.surface, shaders=(SKIN_TEXTURE,), triangles=tuple(triangles), st=tuple(st),
                       vertices=(tuple(vertices),))


def player_model(part):
    radius = math.sqrt(max(sum(c * c for c in (x, y, z)) for x in (part.mins[0], part.maxs[0])
                           for y in (part.mins[1], part.maxs[1]) for z in (part.mins[2], part.maxs[2])))
    frame = md3.Frame(mins=part.mins, maxs=part.maxs, origin=(0, 0, 0), radius=radius, name=FRAME_NAME)
    tags = [md3.Tag(name, origin, IDENTITY_AXIS) for name, origin in part.tags]
    return md3.encode(PLAYER_DIR + part.model, [frame], tags=[tags], surfaces=[box_surface(part)])


def skin(part):
    return f"{part.surface},{SKIN_TEXTURE}\n".encode("ascii")


def effects_entries():
    """Original soft particle texture and ordinary ioquake3 material definitions."""
    size = 32
    header = TGA_HEADER.pack(0, 0, TGA_TRUE_COLOUR, 0, 0, 0, 0, 0, size, size, 32, 8)
    pixels = bytearray()
    for y in range(size):
        for x in range(size):
            radius = math.hypot((x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1)
            pixels.extend((255, 255, 255, round(max(0, 1 - radius) ** 2 * 255)))
    shader = '''dk3/fx/glow
{
 cull disable
 { map gfx/dk3/particle.tga
   blendFunc GL_SRC_ALPHA GL_ONE
   rgbGen vertex
   alphaGen vertex
 }
}
dk3/fx/smoke
{
 cull disable
 { map gfx/dk3/particle.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
 }
}
dk3/fx/cloak
{
 cull disable
 { map gfx/dk3/particle.tga
   tcGen environment
   blendFunc GL_SRC_ALPHA GL_ONE
   rgbGen entity
   alphaGen entity
 }
}
dk3/fx/beam
{
 cull disable
 { map $whiteimage
   blendFunc GL_SRC_ALPHA GL_ONE
   rgbGen vertex
   alphaGen vertex
 }
}
'''
    # Rectangles in the user-supplied 256x128 particle atlas, sampled at pixel
    # centers. The image itself is converted by the HUD/art package.
    for name, bounds in {'smoke': (64, 0, 127, 63), 'simple': (48, 48, 63, 63),
                         'bubble': (0, 64, 31, 95), 'snow': (0, 0, 63, 63),
                         'cp1': (96, 32, 127, 63), 'cp2': (160, 32, 191, 63),
                         'cp3': (224, 32, 255, 63), 'cp4': (224, 96, 255, 127)}.items():
        x0, y0, x1, y1 = bounds
        shader += (f'dk3/particle/{name}\n{{\n cull disable\n'
                   ' { map pics/particles/particles.tga\n'
                   '   blendFunc blend\n   rgbGen vertex\n   alphaGen vertex\n'
                   f'   tcMod transform {(x1-x0)/256} 0 0 {(y1-y0)/128} {(x0+.5)/256} {(y0+.5)/128}\n'
                   ' }\n}\n')
    shader += '''console
{
 { map $whiteimage
   rgbGen const ( 0.035 0.055 0.07 )
 }
}
'''
    for name in ('flareShader', 'sun'):
        shader += name + '''
{
 cull disable
 { map gfx/dk3/particle.tga
   blendFunc add
   rgbGen vertex
 }
}
'''
    shader += '''projectionShadow
{
 polygonOffset
 { map gfx/dk3/particle.tga
   blendFunc blend
   rgbGen const ( 0 0 0 )
   alphaGen vertex
 }
}
'''
    return [('gfx/dk3/particle.tga', header + pixels), ('scripts/dk3-effects.shader', shader.encode('ascii'))]


def entries():
    """(name, bytes) of every file of the package, in package order."""
    return [("default.cfg", default_cfg()), ("sound/feedback/hit.wav", hit_wav()),
            (PLAYER_DIR + "animation.cfg", animation_cfg())] + \
        [(PLAYER_DIR + part.model, player_model(part)) for part in PARTS] + \
        [(PLAYER_DIR + part.skin, skin(part)) for part in PARTS] + \
        [(SKIN_TEXTURE, tga(TEXTURE_SIZE, SKIN_RGB)), (ICON, tga(ICON_SIZE, ICON_RGB)),
         (WHITE_TEXTURE, tga(WHITE_SIZE, WHITE_RGB))] + effects_entries()


def main(argv):
    if len(argv) != 2:
        sys.stderr.write(USAGE)
        return 2
    pk3.write(argv[1], entries())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
