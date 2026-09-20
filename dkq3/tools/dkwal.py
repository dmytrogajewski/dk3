"""dkwal: Daikatana WAL textures, read as GL_LoadWal reads them (reference/dk-gold/base/ref_gl/gl_image.cpp).

Both layouts of reference/dk-gold/user/qfiles.h are read field by field at their C offsets:
`miptex_t` (version 3, nine mip offsets, embedded palette) and the Quake II `miptexOld_t`. The
format, the validation rules and the corpus statistics are in specs/assets/ASSET-wal.md.
"""
import dataclasses
import struct

DEFAULT_ENTRY = "<wal>"
LAYOUT_MIPTEX = "miptex_t"
LAYOUT_MIPTEX_OLD = "miptexOld_t"
MIPTEX_VERSION = 3                                  # qfiles.h:361
VERSION = struct.Struct("<b")                       # miptex_t.version is a signed char (qfiles.h:377)
OLD_LAYOUT_ABOVE = 0x20                             # qfiles.h:356-359, gl_image.cpp:1690
MIPTEX = struct.Struct("<b32s3xII9I32sii768si")     # qfiles.h:375-386: 892 bytes, width aligned to 0x24
MIPTEX_OLD = struct.Struct("<32sII4I32siii")        # qfiles.h:363-372: 100 bytes, no version, no palette
WIDTH_AT = {MIPTEX: struct.calcsize("<b32s3x"), MIPTEX_OLD: struct.calcsize("<32s")}
DIMENSION_SIZE = struct.calcsize("<I")


class WalError(ValueError):
    """A WAL the engine cannot load; carries the entry name and the file offset of the fault."""

    def __init__(self, entry, offset, detail):
        super().__init__(f"{entry}: offset {offset}: {detail}")
        self.entry, self.offset = entry, offset


class UnsupportedVersion(WalError):
    """First byte neither a Quake II name byte nor MIPTEX_VERSION: GL_LoadWal's ERR_DROP."""


class TruncatedHeader(WalError):
    """File shorter than its layout's header: the loader would read fields past the buffer."""


class ZeroDimension(WalError):
    """Width or height 0: GL_LoadPic's ERR_FATAL."""


class MipPastEnd(WalError):
    """A mip level's texels start inside the header or end past the file: the loader reads outside it."""


class MissingPalette(WalError):
    """A miptexOld_t decoded without the shared palette it needs (it embeds none, qfiles.h:363-372)."""


@dataclasses.dataclass(frozen=True)
class Miptex:
    """A parsed WAL header (specs/assets/ASSET-wal.md); `raw` is the whole file."""
    layout: str
    version: int
    name: str
    width: int
    height: int
    offsets: tuple
    animname: str
    flags: int
    contents: int
    palette: bytes
    value: int
    header_size: int
    raw: bytes
    entry: str = DEFAULT_ENTRY

    def mip(self, level):
        """-> (width, height, texel indices) of a mip level. Each dimension halves and stops at 1
        (gl_image.cpp:1381-1386). Raises MipPastEnd when the level's texels are not in the file."""
        width, height = max(self.width >> level, 1), max(self.height >> level, 1)
        at = self.offsets[level]
        if at < self.header_size or at + width * height > len(self.raw):
            raise MipPastEnd(self.entry, at, f"mip level {level} ({width}x{height}) is not between the "
                                             f"{self.header_size}-byte header and the file end ({len(self.raw)})")
        return width, height, self.raw[at:at + width * height]


def _text(field):
    """A char[32] field up to its first NUL."""
    return field.split(b"\0")[0].decode("latin1")


def _miptex(b, entry):
    version, name, width, height, *rest = MIPTEX.unpack_from(b)
    animname, flags, contents, palette, value = rest[9:]
    return Miptex(LAYOUT_MIPTEX, version, _text(name), width, height, tuple(rest[:9]),
                  _text(animname), flags, contents, palette, value, MIPTEX.size, bytes(b), entry)


def _miptex_old(b, entry):
    name, width, height, *rest = MIPTEX_OLD.unpack_from(b)
    animname, flags, contents, value = rest[4:]
    return Miptex(LAYOUT_MIPTEX_OLD, None, _text(name), width, height, tuple(rest[:4]),
                  _text(animname), flags, contents, None, value, MIPTEX_OLD.size, bytes(b), entry)


def parse_wal(b, entry=DEFAULT_ENTRY):
    """-> Miptex. Raises a WalError subclass for a file GL_LoadWal would not load."""
    if len(b) < VERSION.size:
        raise TruncatedHeader(entry, len(b), "empty file")
    version = VERSION.unpack_from(b)[0]
    if version != MIPTEX_VERSION and version <= OLD_LAYOUT_ABOVE:
        raise UnsupportedVersion(entry, 0, f"version {version}; GL_LoadWal accepts {MIPTEX_VERSION} "
                                           f"or a Quake II name byte above {OLD_LAYOUT_ABOVE:#x}")
    layout = MIPTEX_OLD if version > OLD_LAYOUT_ABOVE else MIPTEX
    if len(b) < layout.size:
        raise TruncatedHeader(entry, len(b), f"{len(b)} bytes; the header needs {layout.size}")
    t = (_miptex_old if layout is MIPTEX_OLD else _miptex)(b, entry)
    for at, size in ((WIDTH_AT[layout], t.width), (WIDTH_AT[layout] + DIMENSION_SIZE, t.height)):
        if size == 0:
            raise ZeroDimension(entry, at, "zero width or height; GL_LoadPic stops with ERR_FATAL")
    t.mip(0)
    return t
