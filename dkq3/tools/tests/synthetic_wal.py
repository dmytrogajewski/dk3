"""Synthetic WAL files for the dkwal, dkimg and sweep tests, built from named constants.

Offsets are written out by hand from reference/dk-gold/user/qfiles.h, independently of the format
strings in dkwal.py, so a layout mistake in the parser cannot hide behind the same mistake here.
`miptex_t` (qfiles.h:375-386): `char version` and `char name[32]` take 33 bytes and `unsigned width`
aligns to 0x24. `miptexOld_t` (qfiles.h:363-372) has no version byte and no palette. No game data is
used.

FRD: specs/frds/FRD-005-wal-parser-matches-miptex-t.md
"""
import struct

MIPTEX_VERSION = 3
MIPLEVELS, MIPLEVELS_OLD = 9, 4
NAME_SIZE = 32
PALETTE_SIZE = 768

# miptex_t field offsets and size.
VERSION_AT, NAME_AT, WIDTH_AT, HEIGHT_AT, OFFSETS_AT = 0x00, 0x01, 0x24, 0x28, 0x2C
ANIMNAME_AT, FLAGS_AT, CONTENTS_AT, PALETTE_AT, VALUE_AT = 0x50, 0x70, 0x74, 0x78, 0x378
MIPTEX_SIZE = 0x37C
PADDING_AT, PADDING_SIZE = 0x21, 3

# miptexOld_t field offsets and size.
OLD_NAME_AT, OLD_WIDTH_AT, OLD_HEIGHT_AT, OLD_OFFSETS_AT = 0x00, 0x20, 0x24, 0x28
OLD_ANIMNAME_AT, OLD_FLAGS_AT, OLD_CONTENTS_AT, OLD_VALUE_AT = 0x38, 0x58, 0x5C, 0x60
MIPTEX_OLD_SIZE = 0x64

OLD_NAME = b"e1/old"
TRANSPARENT_INDEX = 255


def mip_size(width, height, level):
    """Texel count of a mip level; each dimension halves and stops at 1 (gl_image.cpp:1381-1386)."""
    return max(width >> level, 1) * max(height >> level, 1)


def chain(width, height, levels, start):
    """-> (offsets of `levels` consecutive mip levels starting at `start`, total texel bytes)."""
    offsets, pos = [], start
    for level in range(levels):
        offsets.append(pos)
        pos += mip_size(width, height, level)
    return offsets, pos - start


def texels(count):
    """Distinct opaque indices (never the transparent index 255)."""
    return bytes(i % TRANSPARENT_INDEX for i in range(count))


def _pack(buf, fields):
    for at, fmt, values in fields:
        struct.pack_into("<" + fmt, buf, at, *values)


def miptex(width=4, height=2, body=None, *, version=MIPTEX_VERSION, name=b"", animname=b"",
           flags=0, contents=0, palette=bytes(PALETTE_SIZE), value=0, offsets=None,
           levels=MIPLEVELS):
    """-> `miptex_t` header followed by the mip texels (default: `levels` chained levels)."""
    chained, size = chain(width, height, levels, MIPTEX_SIZE)
    offsets = chained + [0] * (MIPLEVELS - levels) if offsets is None else offsets
    buf = bytearray(MIPTEX_SIZE)
    _pack(buf, [(VERSION_AT, "b", (version,)), (NAME_AT, "32s", (name,)),
                (WIDTH_AT, "II", (width, height)), (OFFSETS_AT, "9I", offsets),
                (ANIMNAME_AT, "32s", (animname,)), (FLAGS_AT, "ii", (flags, contents)),
                (PALETTE_AT, "768s", (palette,)), (VALUE_AT, "i", (value,))])
    return bytes(buf) + (texels(size) if body is None else body)


def miptex_old(width=4, height=2, body=None, *, name=OLD_NAME, animname=b"", flags=0, contents=0,
               value=0, offsets=None):
    """-> `miptexOld_t` header followed by four chained mip levels."""
    chained, size = chain(width, height, MIPLEVELS_OLD, MIPTEX_OLD_SIZE)
    buf = bytearray(MIPTEX_OLD_SIZE)
    _pack(buf, [(OLD_NAME_AT, "32s", (name,)), (OLD_WIDTH_AT, "II", (width, height)),
                (OLD_OFFSETS_AT, "4I", chained if offsets is None else offsets),
                (OLD_ANIMNAME_AT, "32s", (animname,)),
                (OLD_FLAGS_AT, "iii", (flags, contents, value))])
    return bytes(buf) + (texels(size) if body is None else body)
