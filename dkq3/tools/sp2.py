"""Daikatana SP2 sprite reader, matching Mod_LoadSpriteModel (reference/dk-gold/base/ref_gl/gl_model.cpp:1787-1824) and
the layout of reference/dk-gold/user/qfiles.h:318-339 (specs/assets/ASSET-sp2.md).

`dsprite_t`: int ident ("IDS2"), int version (2), int numframes, then numframes `dsprframe_t` records of int width, height,
origin_x, origin_y (raster coordinates inside the picture) and char name[MAX_SKINNAME] (64).

FRD: specs/frds/FRD-018-sp2-sprites.md
"""
import struct
from dataclasses import dataclass

HEADER = struct.Struct('<4sii')      # ident, version, numframes
FRAME = struct.Struct('<iiii64s')    # width, height, origin_x, origin_y, name
NAME_SIZE = 64                       # MAX_SKINNAME (qfiles.h:83)
IDENT, VERSION = b'IDS2', 2          # IDSPRITEHEADER, SPRITE_VERSION (qfiles.h:323-325)
MAX_FRAMES = 32                      # MAX_MD2SKINS (qfiles.h:82), gl_model.cpp:1804-1806
IDENT_OFFSET, VERSION_OFFSET, NUMFRAMES_OFFSET = 0, 4, 8


class Sp2Error(ValueError):
    """A sprite Gold cannot load; names the sprite and the byte offset of the fault."""

    def __init__(self, sprite, offset, detail):
        super().__init__(f'{sprite}: offset {offset}: {detail}')
        self.sprite, self.offset = sprite, offset


class BadIdent(Sp2Error):
    """Not IDS2: Mod_NumForName prints "unknown field" and loads no model (gl_model.cpp:364-393)."""


class UnsupportedVersion(Sp2Error):
    """A version other than 2: Mod_LoadSpriteModel's ERR_DROP (gl_model.cpp:1800-1802)."""


class Truncated(Sp2Error):
    """The file ends before its header or its frame records: Gold reads past the buffer (gl_model.cpp:1809-1817)."""


class NameNotTerminated(Sp2Error):
    """A frame name without a NUL in its 64 bytes: R_FindImage's strlen runs into the next record (gl_image.cpp:1742)."""


class BadFrameCount(Sp2Error):
    """More than MAX_MD2SKINS frames (ERR_DROP, gl_model.cpp:1804-1806), or none: `e->frame % numframes` divides by the count."""


@dataclass(frozen=True)
class Frame:
    width: int
    height: int
    origin_x: int
    origin_y: int
    name: str
    padding: int     # non-NUL bytes after the name's terminator, which Gold never reads


@dataclass(frozen=True)
class Sprite:
    name: str
    version: int
    frames: tuple
    trailing: int    # bytes after the last frame record, which Gold never reads


def _require(raw, size, name):
    if len(raw) < size:
        raise Truncated(name, len(raw), f'needs {size} bytes; the file has {len(raw)}')


def read(raw, name):
    """-> the `Sprite` of the file bytes `raw`, named `name` in errors."""
    _require(raw, HEADER.size, name)
    ident, version, numframes = HEADER.unpack_from(raw)
    if ident != IDENT:
        raise BadIdent(name, IDENT_OFFSET, f'ident {ident!r}; Gold loads sprites with {IDENT!r}')
    if version != VERSION:
        raise UnsupportedVersion(name, VERSION_OFFSET, f'version {version}; Mod_LoadSpriteModel loads {VERSION}')
    if not 0 < numframes <= MAX_FRAMES:
        raise BadFrameCount(name, NUMFRAMES_OFFSET, f'{numframes} frames; a sprite draws 1 to {MAX_FRAMES}')
    end = HEADER.size + numframes * FRAME.size
    _require(raw, end, name)
    frames = []
    for index in range(numframes):
        at = HEADER.size + index * FRAME.size
        width, height, origin_x, origin_y, text = FRAME.unpack_from(raw, at)
        if b'\0' not in text:
            raise NameNotTerminated(name, at + FRAME.size - NAME_SIZE, f'frame {index} name has no NUL in {NAME_SIZE} bytes')
        cut = text.index(b'\0')
        frames.append(Frame(width, height, origin_x, origin_y, text[:cut].decode('latin1'), sum(map(bool, text[cut:]))))
    return Sprite(name, version, tuple(frames), len(raw) - end)
