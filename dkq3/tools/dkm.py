"""Daikatana DKM model reader (`DKMD` versions 1 and 2), matching Mod_LoadAliasModel
(reference/dk-gold/base/ref_gl/gl_model.cpp:1442-1700) and the structs of reference/dk-gold/user/qfiles.h:75-313.

`read(data, name)` returns a `Model`: the `dmdl_t` header, skin names, texture coordinates in skin pixels, triangles
(surface, vertex indexes, texture coordinate indexes per uv frame), frames with Gold's dequantized positions and light
normal indexes, the GL command strips the renderer draws, surface records and the animation sequence header and table.
Input Gold rejects raises a `DkmError` subclass naming the model, the byte offset and the rule. Standard library and numpy.

FRD: specs/frds/FRD-017-dkm-models-with-preserved-surfaces-vertices-and-sequences.md
"""
import math
import struct
from dataclasses import dataclass

import numpy as np

# The vectors a light normal index selects: CVertexNormals (reference/dk-gold/user/vertnormals.h), the table the GL mesh
# lights with (base/ref_gl/gl_mesh.cpp:40-94); anorms.h serves only the software and Glide renderers (r_alias.cpp:40-48).
# Index 0 and 1 are the north and south poles, then 23 longitudes of 11 latitudes 15 degrees apart:
# x = cos(phi) cos(theta), y = cos(phi) sin(theta), z = sin(phi).
LONGITUDES, LATITUDES, LATITUDE_STEP = 23, 11, 180.0 / 12


def _vertex_normals():
    vectors = [(0.0, 0.0, 1.0), (0.0, 0.0, -1.0)]
    for i in range(LONGITUDES):
        theta = math.radians(i * 360.0 / LONGITUDES)
        for j in range(-(LATITUDES // 2), LATITUDES // 2 + 1):
            phi = math.radians(j * LATITUDE_STEP)
            vectors.append((math.cos(phi) * math.cos(theta), math.cos(phi) * math.sin(theta), math.sin(phi)))
    return np.array(vectors, np.float32)


VERTEX_NORMALS = _vertex_normals()
NUM_NORMALS = len(VERTEX_NORMALS)


IDENT = b'DKMD'
VERSIONS = (1, 2)                      # ALIAS_VERSION, ALIAS_VERSION2 (qfiles.h:76-77)
MAX_VERTS = 3072                       # qfiles.h:80; Mod_LoadAliasModel stops above it (gl_model.cpp:1473-1474)
# Surface flags (qfiles.h:286-297).
SRF_NODRAW, SRF_TRANS33, SRF_TRANS66, SRF_ALPHA = 0x1, 0x2, 0x4, 0x8
SRF_GLOW, SRF_COLORBLEND, SRF_HARDPOINT, SRF_STATICSKIN = 0x10, 0x20, 0x40, 0x80
SRF_FULLBRIGHT, SRF_ENVMAP, SRF_TEXENVMAP_ADD, SRF_TEXENVMAP_MULT = 0x100, 0x200, 0x400, 0x800
# `dmdl_t` (qfiles.h:173-208): ident, version, org, then 17 ints starting at byte 20.
HEADER = struct.Struct('<4si3f17i')
HEADER_FIELDS = ('framesize', 'num_skins', 'num_xyz', 'num_st', 'num_tris', 'num_glcmds', 'num_frames', 'num_surfaces',
                 'ofs_skins', 'ofs_st', 'ofs_tris', 'ofs_frames', 'ofs_glcmds', 'ofs_surfaces', 'ofs_end', 'num_sequences',
                 'ofs_sequences')
VERSION_AT, FIELDS_AT, INT_SIZE = 4, 20, 4
FIELD_AT = {name: FIELDS_AT + INT_SIZE * i for i, name in enumerate(HEADER_FIELDS)}
# `daliasframe_t` / `daliasframe2_t` (qfiles.h:141-155): scale, translate, `char name[16]`, then the vertex records.
FRAME_HEAD = struct.Struct('<3f3f16s')
V1_RECORD, V2_RECORD = 4, 5            # dtrivertx_t, dtrivertx2_t (qfiles.h:115-127)
# The packed version 2 position (alias_quant.h, hierarchy.cpp:182-184): x = v >> 21, y = (v >> 11) & 0x3FF, z = v & 0x7FF.
X_SHIFT, Y_SHIFT, Y_MASK, Z_MASK = 21, 11, 0x3FF, 0x7FF
SKIN_NAME = struct.Struct('<64s')      # MAX_SKINNAME (qfiles.h:83)
ST = struct.Struct('<2h')              # dstvert_t (qfiles.h:87-91), skin pixels
# dtriangle_t (qfiles.h:107-113): index_surface, num_uvframes, index_xyz[3], then num_uvframes x index_st[3].
TRIANGLE_HEAD, TRIANGLE_ST = struct.Struct('<5h'), struct.Struct('<3h')
SURFACE = struct.Struct('<32s5i')      # dsurface_t (qfiles.h:299-313)
# GL commands (qfiles.h:165-172, gl_mesh.cpp:356-395): count (> 0 strip, < 0 fan, 0 end), skin index, surface index, then
# |count| x (vertex index, float u, float v).
STRIP_COUNT, STRIP_HEAD, STRIP_VERTEX, STRIP_END = struct.Struct('<i'), struct.Struct('<3i'), struct.Struct('<iff'), 0
MAX_SEQUENCES = 256                    # qfiles.h:84; com_GetFrameData rejects more (com_sub.cpp:3527-3537)
SEQUENCE = struct.Struct('<16s2i')     # animSeq_t (qfiles.h:157-162)


class DkmError(ValueError):
    """A model Gold cannot load, or whose offsets or indexes point outside the file or a table."""

    def __init__(self, model, offset, detail):
        super().__init__(f'{model}: offset {offset}: {detail}')
        self.model, self.offset = model, offset


class Truncated(DkmError):
    """A header, block or record passes the file end, or `ofs_end` is not the file size."""


class BadIdent(DkmError):
    """The file does not start with `DKMD`."""


class UnsupportedVersion(DkmError):
    """A version Mod_LoadAliasModel does not load (gl_model.cpp:1458-1463)."""


class BadCount(DkmError):
    """A count Mod_LoadAliasModel stops on (gl_model.cpp:1470-1483), a negative count, a frame size too small for its
    vertex records, or a triangle without uv frames."""


class IndexOutOfRange(DkmError):
    """A triangle names a vertex or texture coordinate, or a strip a vertex or surface, the model does not have. A triangle's
    surface index is kept unchecked, as Mod_LoadAliasModel copies it (gl_model.cpp:1587-1606)."""


@dataclass(frozen=True)
class Surface:
    """`dsurface_t` as stored; `num_uvframes` is the field Gold overwrites with the hardpoint triangle (gl_model.cpp:1501)."""
    name: str
    flags: int
    skinindex: int
    skinwidth: int
    skinheight: int
    num_uvframes: int


@dataclass(frozen=True)
class Triangle:
    """`dtriangle_t`: the surface index, three vertex indexes and three texture coordinate indexes per uv frame."""
    surface: int
    xyz: tuple
    st_frames: tuple


@dataclass(frozen=True)
class Frame:
    """One animation frame: `positions` (num_xyz, 3) float32 in model units, `normals` (num_xyz,) light normal indexes."""
    name: str
    scale: tuple
    translate: tuple
    positions: np.ndarray
    normals: np.ndarray


@dataclass(frozen=True)
class Strip:
    """One GL command: the renderer draws `skins[skin]` over these vertices unless `surface` is SRF_NODRAW."""
    count: int
    skin: int
    surface: int
    vertices: tuple


@dataclass(frozen=True)
class Sequence:
    """`animSeq_t`: the name and the first and last frame."""
    name: str
    first: int
    last: int


@dataclass(frozen=True)
class Sequences:
    """The raw `num_sequences` and `ofs_sequences`, whether they describe a table inside the file, and the table."""
    count: int
    offset: int
    valid: bool
    table: tuple


@dataclass(frozen=True)
class Model:
    """One parsed model; every table keeps file order. `header` holds the 17 `dmdl_t` ints by field name."""
    name: str
    version: int
    origin: tuple
    header: dict
    skins: tuple
    st: tuple
    triangles: tuple
    surfaces: tuple
    frames: tuple
    strips: tuple
    sequences: Sequences

    @property
    def num_xyz(self):
        return self.header['num_xyz']


def _require(ok, error, model, offset, detail):
    if not ok:
        raise error(model, offset, detail)


def _cstr(field):
    """The bytes of a fixed `char[]` up to its first NUL, or all of them, as latin1 text."""
    return field.split(b'\0', 1)[0].decode('latin1')


def _inside(data, model, offset, size, what):
    _require(offset >= 0 and offset + size <= len(data), Truncated, model, max(offset, 0),
             f'{what}: {size} bytes at {offset} pass the file end at {len(data)}')


def _table(data, model, header, count_field, offset_field, layout, what):
    """-> the records of a fixed-size table after checking it lies inside the file."""
    count, offset = header[count_field], header[offset_field]
    _inside(data, model, offset, count * layout.size, what)
    return [layout.unpack_from(data, offset + i * layout.size) for i in range(count)]


def _check_counts(model, header, version):
    """Mod_LoadAliasModel's checks (gl_model.cpp:1470-1483), non-negative table counts and a frame size that holds the records."""
    at = FIELD_AT
    _require(header['num_xyz'] > 0, BadCount, model, at['num_xyz'], 'model has no vertices')
    _require(header['num_xyz'] <= MAX_VERTS, BadCount, model, at['num_xyz'], f"{header['num_xyz']} vertices, more than {MAX_VERTS}")
    for field, rule in (('num_st', 'model has no st vertices'), ('num_tris', 'model has no triangles'),
                        ('num_frames', 'model has no frames')):
        _require(header[field] > 0, BadCount, model, at[field], rule)
    for field in ('num_skins', 'num_surfaces', 'num_glcmds'):
        _require(header[field] >= 0, BadCount, model, at[field], f'{field} {header[field]} is negative')
    record = V1_RECORD if version == 1 else V2_RECORD
    least = FRAME_HEAD.size + header['num_xyz'] * record
    _require(header['framesize'] >= least, BadCount, model, at['framesize'],
             f"framesize {header['framesize']} is below the {least} bytes of {header['num_xyz']} vertex records")


def _quantized(records, version):
    """-> (num_xyz, 3) float32 quantized coordinates and (num_xyz,) uint8 light normal indexes of one frame's records."""
    if version == 1:
        return records[:, :3].astype(np.float32), records[:, 3].copy()
    packed = records[:, :4].copy().view('<u4')[:, 0]
    q = np.stack([packed >> X_SHIFT, (packed >> Y_SHIFT) & Y_MASK, packed & Z_MASK], axis=1)
    return q.astype(np.float32), records[:, 4].copy()


def _frames(data, model, header, version):
    """GL_LerpVerts at backlerp 0 (gl_mesh.cpp): translate + quantized * scale, in float32."""
    count, size, num_xyz = header['num_frames'], header['framesize'], header['num_xyz']
    _inside(data, model, header['ofs_frames'], count * size, f'{count} frames of {size} bytes')
    record = V1_RECORD if version == 1 else V2_RECORD
    frames = []
    for i in range(count):
        offset = header['ofs_frames'] + i * size
        *vectors, name = FRAME_HEAD.unpack_from(data, offset)
        records = np.frombuffer(data, np.uint8, num_xyz * record, offset + FRAME_HEAD.size).reshape(num_xyz, record)
        quantized, normals = _quantized(records, version)
        scale, translate = np.array(vectors[:3], np.float32), np.array(vectors[3:], np.float32)
        frames.append(Frame(_cstr(name), tuple(vectors[:3]), tuple(vectors[3:]), translate + quantized * scale, normals))
    return tuple(frames)


def _check_index(model, offset, values, limit, what):
    bad = [v for v in values if not 0 <= v < limit]
    _require(not bad, IndexOutOfRange, model, offset, f'{what} {bad[0] if bad else 0} is outside 0..{limit - 1}')


def _triangles(data, model, header):
    """-> the triangles, each followed by its own num_uvframes texture coordinate triples (gl_model.cpp:1587-1606)."""
    triangles, offset = [], header['ofs_tris']
    for _ in range(header['num_tris']):
        _inside(data, model, offset, TRIANGLE_HEAD.size, 'triangle')
        surface, uv_frames, *xyz = TRIANGLE_HEAD.unpack_from(data, offset)
        _require(uv_frames > 0, BadCount, model, offset, f'triangle with {uv_frames} uv frames')
        _inside(data, model, offset + TRIANGLE_HEAD.size, uv_frames * TRIANGLE_ST.size, 'triangle texture coordinates')
        st_frames = tuple(TRIANGLE_ST.unpack_from(data, offset + TRIANGLE_HEAD.size + k * TRIANGLE_ST.size) for k in range(uv_frames))
        _check_index(model, offset, xyz, header['num_xyz'], 'triangle vertex index')
        _check_index(model, offset, [s for f in st_frames for s in f], header['num_st'], 'triangle texture coordinate index')
        triangles.append(Triangle(surface, tuple(xyz), st_frames))
        offset += TRIANGLE_HEAD.size + uv_frames * TRIANGLE_ST.size
    return tuple(triangles)


def _strips(data, model, header):
    """-> the GL commands up to the zero count, all inside the `num_glcmds` ints at `ofs_glcmds`."""
    start = header['ofs_glcmds']
    end = start + header['num_glcmds'] * INT_SIZE
    _inside(data, model, start, end - start, f"{header['num_glcmds']} GL command ints")
    strips, offset = [], start
    while True:
        _require(offset + STRIP_COUNT.size <= end, Truncated, model, offset, 'GL commands end without a zero count')
        count = STRIP_COUNT.unpack_from(data, offset)[0]
        if count == STRIP_END:
            return tuple(strips)
        size = STRIP_HEAD.size + abs(count) * STRIP_VERTEX.size
        _require(offset + size <= end, Truncated, model, offset, f'a GL command of {abs(count)} vertices passes the command block')
        _, skin, surface = STRIP_HEAD.unpack_from(data, offset)
        vertices = tuple(STRIP_VERTEX.unpack_from(data, offset + STRIP_HEAD.size + k * STRIP_VERTEX.size) for k in range(abs(count)))
        _check_index(model, offset, (surface,), header['num_surfaces'], 'GL command surface index')
        _check_index(model, offset, [v[0] for v in vertices], header['num_xyz'], 'GL command vertex index')
        strips.append(Strip(count, skin, surface, vertices))
        offset += size


def _sequences(data, header):
    """-> the header values and, when 0 <= count <= MAX_SEQUENCES and the records lie inside the file, the table."""
    count, offset = header['num_sequences'], header['ofs_sequences']
    valid = 0 <= count <= MAX_SEQUENCES and 0 <= offset and offset + count * SEQUENCE.size <= len(data)
    table = tuple(Sequence(_cstr(n), first, last) for n, first, last in
                  (SEQUENCE.unpack_from(data, offset + i * SEQUENCE.size) for i in range(count))) if valid else ()
    return Sequences(count, offset, valid, table)


def read(data, model):
    """-> the `Model` of the DKM bytes `data`; `model` names it in errors. Raises a `DkmError` subclass."""
    _require(len(data) >= HEADER.size, Truncated, model, 0, f'{len(data)} bytes; dmdl_t needs {HEADER.size}')
    ident, version, *rest = HEADER.unpack_from(data)
    _require(ident == IDENT, BadIdent, model, 0, f'ident {ident!r}, expected {IDENT!r}')
    _require(version in VERSIONS, UnsupportedVersion, model, VERSION_AT, f'version {version}, Gold loads {VERSIONS}')
    header = dict(zip(HEADER_FIELDS, rest[3:]))
    _check_counts(model, header, version)
    _require(header['ofs_end'] == len(data), Truncated, model, FIELD_AT['ofs_end'],
             f"ofs_end {header['ofs_end']} is not the file size {len(data)}")
    frames = _frames(data, model, header, version)
    skins = tuple(_cstr(n) for n, in _table(data, model, header, 'num_skins', 'ofs_skins', SKIN_NAME, 'skin names'))
    st = tuple(_table(data, model, header, 'num_st', 'ofs_st', ST, 'texture coordinates'))
    surfaces = tuple(Surface(_cstr(n), *fields) for n, *fields in
                     _table(data, model, header, 'num_surfaces', 'ofs_surfaces', SURFACE, 'surfaces'))
    triangles = _triangles(data, model, header)
    strips = _strips(data, model, header)
    return Model(model, version, tuple(rest[:3]), header, skins, st, triangles, surfaces, frames, strips,
                 _sequences(data, header))
