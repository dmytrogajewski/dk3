"""dkimg: Daikatana images decoded the way the Gold loaders store them (LoadTGA, LoadBMP, LoadPCX, GL_LoadWal in
reference/dk-gold/base/ref_gl/gl_image.cpp and base/ref_common/dk_ref_common.cpp), the 8-bit rules of GL_LoadPic and
GL_Upload8 (R_FloodFillSkin, index 255 transparency, the fringe fill), and a PNG writer and reader.

Formats, rules and named errors: specs/assets/ASSET-images.md; WAL layout: specs/assets/ASSET-wal.md.
"""
import collections, struct, zlib
import numpy as np
import dkwal

TRANSPARENT_INDEX = 255          # engine: palette index 255 is transparent (gl_image.cpp:76, 2070)
FRINGE_FALLBACK_INDEX = 0        # GL_Upload8's colour when no neighbour is opaque (gl_image.cpp:1490-1491)


class ImageError(ValueError):
    """An image the Gold loaders cannot load; carries the entry name and the byte offset of the fault."""

    def __init__(self, entry, offset, detail):
        super().__init__(f"{entry}: offset {offset}: {detail}")
        self.entry, self.offset = entry, offset


class UnsupportedTgaType(ImageError):
    """TGA image type other than 2 or 10: LoadTGA's ERR_DROP (gl_image.cpp:612-614)."""


class UnsupportedTgaPixels(ImageError):
    """TGA with a colour map or a pixel size other than 24 and 32: LoadTGA's ERR_DROP (gl_image.cpp:616-618)."""


class TruncatedImage(ImageError):
    """The file ends before a header field, a palette or a texel the loader reads: Gold reads past the buffer."""


class ZeroDimension(ImageError):
    """Width or height 0: GL_LoadPic's ERR_FATAL (gl_image.cpp:1547-1548)."""


class UnsupportedBmpDepth(ImageError):
    """BMP with a bit count other than 8: LoadBMP's ERR_FATAL (dk_ref_common.cpp:266-267)."""


class BadBmpHeader(ImageError):
    """BMP whose signature, info header size or compression LoadBMP stops on (dk_ref_common.cpp:250-259, 299-300)."""


class BadPcxHeader(ImageError):
    """PCX header LoadPCX answers with "Bad pcx file" and no image (dk_ref_common.cpp:44-53)."""


def _nonzero(entry, fields):
    """Raises ZeroDimension at the offset of the first (offset, value) whose value is 0."""
    for at, value in fields:
        if value == 0:
            raise ZeroDimension(entry, at, "zero width or height; GL_LoadPic stops with ERR_FATAL")


def _require(raw, at, count, entry):
    """Raises TruncatedImage at the file length unless `count` bytes follow offset `at`."""
    if at + count > len(raw):
        raise TruncatedImage(entry, len(raw), f"needs {count} bytes at {at}; the file has {len(raw)}")


def wal_to_rgba(raw, level=0, palette=None, entry=dkwal.DEFAULT_ENTRY):
    """Decode a WAL mip level to ((H,W,4) uint8, dkwal.Miptex) as GL_Upload8 uploads it: index 255
    has alpha 0 and takes a neighbour's colour (specs/assets/ASSET-wal.md). `palette` (768 bytes) is
    the shared palette a miptexOld_t needs; a miptex_t uses its embedded palette."""
    t = dkwal.parse_wal(raw, entry)
    colours = palette if t.palette is None else t.palette
    if colours is None:
        raise dkwal.MissingPalette(entry, 0, f"{t.layout} embeds no palette; pass the shared palette")
    w, h, texels = t.mip(level)
    return upload8(np.frombuffer(texels, dtype=np.uint8).reshape(h, w), colours), t


def upload8(indices, palette):
    """(H,W) palette indices -> (H,W,4) uint8 as GL_Upload8 expands an 8-bit image with no palette argument
    (gl_image.cpp:1463-1497): index 255 has alpha 0 (GL_MakePalette24, gl_image.cpp:72-76) and the colour of
    its first opaque neighbour (`_fringe_source`)."""
    h, w = indices.shape
    idx = indices.reshape(-1)
    pal = np.frombuffer(palette, dtype=np.uint8).reshape(256, 3)
    transparent = idx == TRANSPARENT_INDEX
    alpha = np.where(transparent, 0, 255).astype(np.uint8)
    rgb = pal[np.where(transparent, _fringe_source(idx, w), idx)]
    return np.dstack([rgb.reshape(h, w, 3), alpha.reshape(h, w)])


def _fringe_source(d, w):
    """Fill transparent RGB from adjacent opaque pixels without wrapping rows."""
    grid = d.reshape(-1, w)
    result = np.zeros_like(grid)
    assigned = np.zeros_like(grid, dtype=bool)
    for dy, dx in ((-1, 0), (0, -1), (1, 0), (0, 1)):
        neighbour = np.roll(grid, (dy, dx), axis=(0, 1))
        valid = neighbour != TRANSPARENT_INDEX
        if dy: valid[0 if dy > 0 else -1, :] = False
        if dx: valid[:, 0 if dx > 0 else -1] = False
        take = valid & ~assigned
        result[take] = neighbour[take]
        assigned |= take
    return result.reshape(-1)


def flood_fill_skin(indices, palette):
    """Propagate border colors into the connected background; no fixed queue limit."""
    height, width = indices.shape
    background = int(indices[0, 0])
    if background == TRANSPARENT_INDEX:
        return indices.copy(), 0
    region = np.zeros_like(indices, dtype=bool)
    pending = collections.deque([(0, 0)])
    region[0, 0] = True
    boundary = collections.deque()
    def neighbours(y, x):
        for yy, xx in ((y-1, x), (y, x-1), (y+1, x), (y, x+1)):
            if 0 <= yy < height and 0 <= xx < width:
                yield yy, xx
    while pending:
        y, x = pending.popleft()
        for yy, xx in neighbours(y, x):
            if indices[yy, xx] == background:
                if not region[yy, xx]:
                    region[yy, xx] = True
                    pending.append((yy, xx))
            elif indices[yy, xx] != TRANSPARENT_INDEX:
                boundary.append((y, x, int(indices[yy, xx])))
    result = indices.copy()
    unfilled = region.copy()
    while boundary:
        y, x, color = boundary.popleft()
        if not unfilled[y, x]:
            continue
        result[y, x], unfilled[y, x] = color, False
        boundary.extend((yy, xx, color) for yy, xx in neighbours(y, x) if unfilled[yy, xx])
    result[unfilled] = background
    return result, int(np.count_nonzero(result != indices))


TGA_HEADER = struct.Struct("<BBBHHBHHHHBB")   # TargaHeader (gl_image.cpp:559-565): 18 bytes
TGA_UNCOMPRESSED, TGA_RLE = 2, 10              # image types LoadTGA reads (gl_image.cpp:612-613)
TGA_COLORMAP_TYPE_AT, TGA_IMAGE_TYPE_AT, TGA_WIDTH_AT, TGA_HEIGHT_AT, TGA_PIXEL_SIZE_AT = 1, 2, 12, 14, 16
TGA_ATTRIBUTES_AT, TGA_TOP_DOWN = 17, 0x20     # the origin bit LoadTGA does not read (gl_image.cpp:636, 667)
TGA_PIXEL_SIZES = (24, 32)                     # gl_image.cpp:617
TGA_RUN_FLAG, TGA_COUNT_MASK = 0x80, 0x7F      # packet header (gl_image.cpp:670-672)


def tga_to_rgba(raw, entry=dkwal.DEFAULT_ENTRY):
    """-> (H,W,4) uint8 as LoadTGA stores it (gl_image.cpp:573-739): BGR(A) to RGBA, the first row of
    the file at the bottom whatever the attributes byte says."""
    _require(raw, 0, TGA_HEADER.size, entry)
    id_length, colormap_type, image_type, _, _, _, _, _, width, height, pixel_size, _ = TGA_HEADER.unpack_from(raw)
    if image_type not in (TGA_UNCOMPRESSED, TGA_RLE):
        raise UnsupportedTgaType(entry, TGA_IMAGE_TYPE_AT,
                                 f"image type {image_type}; LoadTGA reads {TGA_UNCOMPRESSED} and {TGA_RLE}")
    for at, value, accepted in ((TGA_COLORMAP_TYPE_AT, colormap_type, (0,)), (TGA_PIXEL_SIZE_AT, pixel_size, TGA_PIXEL_SIZES)):
        if value not in accepted:
            raise UnsupportedTgaPixels(entry, at, f"colour-map type {colormap_type}, {pixel_size} bits; LoadTGA "
                                                  f"reads no colour map and {' or '.join(map(str, TGA_PIXEL_SIZES))} bits")
    _nonzero(entry, ((TGA_WIDTH_AT, width), (TGA_HEIGHT_AT, height)))
    channels, start = pixel_size // 8, TGA_HEADER.size + id_length
    if image_type == TGA_RLE:
        texels = np.frombuffer(_tga_packets(raw, start, width * height * channels, channels, entry), np.uint8)
    else:
        _require(raw, start, width * height * channels, entry)
        texels = np.frombuffer(raw, np.uint8, width * height * channels, start)
    bgra = texels.reshape(height, width, channels)[::-1]
    alpha = bgra[..., 3] if channels == 4 else np.full((height, width), 255, np.uint8)
    return np.dstack([bgra[..., 2], bgra[..., 1], bgra[..., 0], alpha])


def _tga_packets(raw, at, size, channels, entry):
    """The first `size` bytes of the texel stream the RLE packets from `at` expand to. LoadTGA carries a
    packet across row ends and stops at the last texel (gl_image.cpp:665-739)."""
    out = bytearray()
    while len(out) < size:
        _require(raw, at, 1, entry)
        header, at = raw[at], at + 1
        count = (header & TGA_COUNT_MASK) + 1
        stored = channels if header & TGA_RUN_FLAG else count * channels
        _require(raw, at, stored, entry)
        out += raw[at:at + channels] * count if header & TGA_RUN_FLAG else raw[at:at + stored]
        at += stored
    return bytes(out[:size])


def write_png(path, img):
    """Writes encode_png(img) to `path`."""
    with open(path, 'wb') as f:
        f.write(encode_png(img))


def encode_png(img):
    """-> PNG bytes of an (H,W,3|4) uint8 image: filter 0 and zlib level 6, so equal images give equal bytes."""
    h, w, nch = img.shape
    ctype = 2 if nch == 3 else 6
    raw = b''.join(b'\0' + img[y].tobytes() for y in range(h))
    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data +
                struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, ctype, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))
    return png


def read_png(path):
    with open(path, 'rb') as f:
        d = f.read()
    pos, idat = 8, b''
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos+4])[0]; tag = d[pos+4:pos+8]
        body = d[pos+8:pos+8+ln]
        if tag == b'IHDR':
            w, h, bd, ctype = struct.unpack('>IIBB', body[:10])
        elif tag == b'IDAT':
            idat += body
        pos += 12 + ln
    nch = 3 if ctype == 2 else 4
    raw = zlib.decompress(idat)
    stride = w * nch
    out = np.zeros((h, w, nch), np.uint8)
    prev = np.zeros(stride, np.int32)
    for y in range(h):
        f = raw[y*(stride+1)]
        line = np.frombuffer(raw[y*(stride+1)+1:(y+1)*(stride+1)], np.uint8).astype(np.int32)
        if f == 0:   cur = line
        elif f == 1:
            cur = line.copy()
            for i in range(nch, stride): cur[i] = (cur[i] + cur[i-nch]) & 255
        elif f == 2: cur = (line + prev) & 255
        elif f == 3:
            cur = line.copy()
            for i in range(stride):
                a = cur[i-nch] if i >= nch else 0
                cur[i] = (cur[i] + ((a + prev[i]) >> 1)) & 255
        else:
            cur = line.copy()
            for i in range(stride):
                a = cur[i-nch] if i >= nch else 0
                c = prev[i-nch] if i >= nch else 0
                b = prev[i]
                p = a + b - c; pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 255
        out[y] = cur.reshape(w, nch); prev = cur
    return out


Indexed = collections.namedtuple("Indexed", "width height indices palette")
"""An 8-bit image: `indices` (H,W) uint8 with the top row first, `palette` 768 RGB bytes."""

BMP_HEADERS = struct.Struct("<2sIHHIIiiHHIIiiII")   # bmpheader_t + bmpinfo_t, packed (dk_ref_common.cpp:116-138)
BMP_PALETTE_ENTRIES, BMP_ENTRY_SIZE = 256, 4         # bgr_t (dk_ref_common.cpp:140-146, 271-276)
BMP_BITS, BMP_BITCOUNT_AT = 8, 28                    # LoadBMP reads 8-bit files only (dk_ref_common.cpp:266)
BMP_SIGNATURE, BMP_INFO_SIZE, BMP_UNCOMPRESSED = b"BM", 40, 0
BMP_TYPE_AT, BMP_INFO_SIZE_AT, BMP_WIDTH_AT, BMP_HEIGHT_AT, BMP_COMPRESSION_AT = 0, 14, 18, 22, 30


def read_bmp(raw, entry=dkwal.DEFAULT_ENTRY):
    """-> Indexed as LoadBMP reads it (dk_ref_common.cpp:221-308): 256 BGRX palette entries right after
    the headers, `width` bytes per row from bfOffBits (BMPLineNone skips no padding), bottom row first."""
    _require(raw, 0, BMP_HEADERS.size + BMP_PALETTE_ENTRIES * BMP_ENTRY_SIZE, entry)
    signature, _, _, _, offbits, info_size, width, height, _, bits, compression, *_ = BMP_HEADERS.unpack_from(raw)
    for at, value, accepted in ((BMP_TYPE_AT, signature, BMP_SIGNATURE), (BMP_INFO_SIZE_AT, info_size, BMP_INFO_SIZE),
                                (BMP_COMPRESSION_AT, compression, BMP_UNCOMPRESSED)):
        if value != accepted:
            raise BadBmpHeader(entry, at, f"{value!r} where LoadBMP requires {accepted!r}")
    if bits != BMP_BITS:
        raise UnsupportedBmpDepth(entry, BMP_BITCOUNT_AT, f"{bits} bits per pixel; LoadBMP reads {BMP_BITS}")
    _nonzero(entry, ((BMP_WIDTH_AT, width), (BMP_HEIGHT_AT, height)))
    bgrx = np.frombuffer(raw, np.uint8, BMP_PALETTE_ENTRIES * BMP_ENTRY_SIZE, BMP_HEADERS.size)
    _require(raw, offbits, width * height, entry)
    indices = np.frombuffer(raw, np.uint8, width * height, offbits).reshape(height, width)[::-1]
    return Indexed(width, height, indices, bgrx.reshape(-1, BMP_ENTRY_SIZE)[:, [2, 1, 0]].tobytes())


PCX_HEADER = struct.Struct("<BBBBHHHH")      # pcx_t manufacturer, version, encoding, bits, xmin..ymax (qfiles.h:49-55)
PCX_HEADER_SIZE, PCX_PALETTE_SIZE = 128, 768  # pcx_t.data (qfiles.h:63); palette at len - 768 (dk_ref_common.cpp:65)
PCX_RUN_FLAGS, PCX_COUNT_MASK = 0xC0, 0x3F    # dk_ref_common.cpp:80-82
# (offset, field index in PCX_HEADER, test LoadPCX applies) for every header field (dk_ref_common.cpp:44-53).
PCX_RULES = ((0, 0, lambda v: v == 0x0A), (1, 1, lambda v: v == 5), (2, 2, lambda v: v == 1),
             (3, 3, lambda v: v == 8), (8, 6, lambda v: v < 640), (10, 7, lambda v: v < 480))


def read_pcx(raw, entry=dkwal.DEFAULT_ENTRY):
    """-> Indexed as LoadPCX reads it (dk_ref_common.cpp:18-99): `xmax + 1` texels per row from byte 128,
    run bytes past a row end dropped (the next row overwrites them), the palette the file's last 768 bytes."""
    _require(raw, 0, max(PCX_HEADER_SIZE, PCX_PALETTE_SIZE), entry)
    fields = PCX_HEADER.unpack_from(raw)
    for at, index, accepted in PCX_RULES:
        if not accepted(fields[index]):
            raise BadPcxHeader(entry, at, f"field value {fields[index]}; LoadPCX prints \"Bad pcx file\"")
    xmax, ymax = fields[6:]
    width, height, at, indices = xmax + 1, ymax + 1, PCX_HEADER_SIZE, bytearray()
    for _ in range(height):
        row = bytearray()
        while len(row) < width:
            _require(raw, at, 1, entry)
            value, count, at = raw[at], 1, at + 1
            if value & PCX_RUN_FLAGS == PCX_RUN_FLAGS:
                _require(raw, at, 1, entry)
                value, count, at = raw[at], value & PCX_COUNT_MASK, at + 1
            row += bytes((value,)) * count
        indices += row[:width]
    return Indexed(width, height, np.frombuffer(bytes(indices), np.uint8).reshape(height, width),
                   bytes(raw[-PCX_PALETTE_SIZE:]))
