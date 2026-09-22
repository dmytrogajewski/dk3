"""MD3 encoder: ioquake3's triangle model format (`IDP3` version 15), laid out like code/qcommon/qfiles.h.

`encode` returns the bytes of one model: `md3Header_t`, the frames, the tags, then each surface. Every struct is a
table of (C field name, struct format) so the layout can be checked against qfiles.h field by field
(tests/test_md3.py compiles those checks with `zig cc`). Standard library only.

FRD: specs/frds/FRD-010-standalone-dkq3-base-game-package.md
"""
import struct
from dataclasses import dataclass

IDENT = b"IDP3"
VERSION = 15
MAX_QPATH = 64

HEADER_FIELDS = (("ident", "4s"), ("version", "i"), ("name", "64s"), ("flags", "i"), ("numFrames", "i"),
                 ("numTags", "i"), ("numSurfaces", "i"), ("numSkins", "i"), ("ofsFrames", "i"), ("ofsTags", "i"),
                 ("ofsSurfaces", "i"), ("ofsEnd", "i"))
FRAME_FIELDS = (("bounds", "6f"), ("localOrigin", "3f"), ("radius", "f"), ("name", "16s"))
TAG_FIELDS = (("name", "64s"), ("origin", "3f"), ("axis", "9f"))
SURFACE_FIELDS = (("ident", "4s"), ("name", "64s"), ("flags", "i"), ("numFrames", "i"), ("numShaders", "i"),
                  ("numVerts", "i"), ("numTriangles", "i"), ("ofsTriangles", "i"), ("ofsShaders", "i"),
                  ("ofsSt", "i"), ("ofsXyzNormals", "i"), ("ofsEnd", "i"))
SHADER_FIELDS = (("name", "64s"), ("shaderIndex", "i"))
TRIANGLE_FIELDS = (("indexes", "3i"),)
ST_FIELDS = (("st", "2f"),)
XYZ_NORMAL_FIELDS = (("xyz", "3h"), ("normal", "H"))
# The file stores coordinates in 1/64 units (`MD3_XYZ_SCALE`).
XYZ_SCALE = 64
# qfiles.h limits (`MD3_MAX_*`) and the size of `md3Frame_t.name`.
MAX_FRAMES, MAX_TAGS, MAX_SURFACES = 1024, 16, 32
MAX_SHADERS, MAX_VERTS, MAX_TRIANGLES = 256, 4096, 8192
FRAME_NAME_LEN = 16
# `md3XyzNormal_t` holds a coordinate times XYZ_SCALE in a signed short and the encoded normal in 16 bits.
SHORT_MIN, SHORT_MAX, NORMAL_MAX = -32768, 32767, 0xFFFF
MAX_COORDINATE = SHORT_MAX / XYZ_SCALE


class Md3Error(ValueError):
    """A model the engine cannot load; the message starts with the offending field."""


def layout(fields):
    """The little-endian struct of a qfiles.h type given as (C field name, format) pairs."""
    return struct.Struct("<" + "".join(fmt for _, fmt in fields))


HEADER = layout(HEADER_FIELDS)
FRAME = layout(FRAME_FIELDS)
TAG = layout(TAG_FIELDS)
SURFACE = layout(SURFACE_FIELDS)
SHADER = layout(SHADER_FIELDS)
TRIANGLE = layout(TRIANGLE_FIELDS)
ST = layout(ST_FIELDS)
XYZ_NORMAL = layout(XYZ_NORMAL_FIELDS)


@dataclass(frozen=True)
class Frame:
    """`md3Frame_t`: the bounds, local origin and radius of one animation frame."""
    mins: tuple
    maxs: tuple
    origin: tuple
    radius: float
    name: str


@dataclass(frozen=True)
class Tag:
    """`md3Tag_t`: a named attachment point; `axis` is the 3x3 rotation, row by row."""
    name: str
    origin: tuple
    axis: tuple


@dataclass(frozen=True)
class Surface:
    """`md3Surface_t` and its chunks. `vertices` holds, per frame, one `(x, y, z, normal)` per vertex in model
    units; `normal` is the encoded latitude (high byte) and longitude (low byte)."""
    name: str
    shaders: tuple
    triangles: tuple
    st: tuple
    vertices: tuple


def encode_surface(surface):
    """One surface: `md3Surface_t`, then shaders, triangles, texture coordinates and vertices (qfiles.h order)."""
    shaders = b"".join(SHADER.pack(s.encode("latin1"), 0) for s in surface.shaders)
    triangles = b"".join(TRIANGLE.pack(*t) for t in surface.triangles)
    st = b"".join(ST.pack(*c) for c in surface.st)
    xyz = b"".join(XYZ_NORMAL.pack(*(round(c * XYZ_SCALE) for c in v[:3]), v[3])
                   for per_frame in surface.vertices for v in per_frame)
    ofs_triangles = SURFACE.size + len(shaders)
    ofs_st = ofs_triangles + len(triangles)
    ofs_xyz = ofs_st + len(st)
    head = SURFACE.pack(IDENT, surface.name.encode("latin1"), 0, len(surface.vertices), len(surface.shaders),
                        len(surface.st), len(surface.triangles), ofs_triangles, SURFACE.size, ofs_st, ofs_xyz,
                        ofs_xyz + len(xyz))
    return head + shaders + triangles + st + xyz


def _check(ok, field, message):
    if not ok:
        raise Md3Error(f"{field}: {message}")


def _check_name(field, name, size=MAX_QPATH):
    _check(len(name.encode("latin1")) < size, field, f"'{name}' does not fit {size} bytes with its terminator")


def _check_count(field, count, limit):
    _check(count <= limit, field, f"{count} exceeds the limit {limit}")


def validate(name, frames, tags, surfaces, max_frames=MAX_FRAMES):
    """Raises Md3Error for a model beyond the qfiles.h limits (the frame limit `max_frames`) or with inconsistent counts
    or indexes."""
    _check_name("name", name)
    _check(len(frames) > 0, "frames", "R_LoadMD3 rejects a model without frames")
    _check_count("numFrames", len(frames), max_frames)
    for frame in frames:
        _check_name("frame name", frame.name, FRAME_NAME_LEN)
    _check(len(tags) == len(frames) and len({len(t) for t in tags}) == 1, "tags", "every frame needs the same tags")
    _check_count("numTags", len(tags[0]), MAX_TAGS)
    for tag in (tag for per_frame in tags for tag in per_frame):
        _check_name("tag name", tag.name)
    _check_count("numSurfaces", len(surfaces), MAX_SURFACES)
    for surface in surfaces:
        _validate_surface(surface, len(frames))


def _validate_surface(surface, frame_count):
    _check_name("surface name", surface.name)
    for shader in surface.shaders:
        _check_name("shader name", shader)
    _check_count("numShaders", len(surface.shaders), MAX_SHADERS)
    _check(len(surface.vertices) == frame_count, "vertices", f"{len(surface.vertices)} vertex frames, {frame_count} frames")
    verts = len(surface.st)
    _check_count("numVerts", verts, MAX_VERTS)
    _check(all(len(per_frame) == verts for per_frame in surface.vertices), "st", f"{verts} texture coordinates")
    _check_count("numTriangles", len(surface.triangles), MAX_TRIANGLES)
    _check(all(0 <= i < verts for t in surface.triangles for i in t), "indexes", f"an index is outside 0..{verts - 1}")
    vertices = [v for per_frame in surface.vertices for v in per_frame]
    _check(all(SHORT_MIN <= round(c * XYZ_SCALE) <= SHORT_MAX for v in vertices for c in v[:3]), "xyz",
           f"a coordinate is outside {SHORT_MIN / XYZ_SCALE}..{MAX_COORDINATE}")
    _check(all(0 <= v[3] <= NORMAL_MAX for v in vertices), "normal", f"an encoded normal is outside 0..{NORMAL_MAX}")


def encode(name, frames, tags, surfaces, max_frames=MAX_FRAMES):
    """The bytes of one MD3 model. `tags` holds one list of tags per frame. Raises Md3Error (see `validate`)."""
    validate(name, frames, tags, surfaces, max_frames)
    frame_block = b"".join(FRAME.pack(*f.mins, *f.maxs, *f.origin, f.radius, f.name.encode("latin1")) for f in frames)
    tag_block = b"".join(TAG.pack(t.name.encode("latin1"), *t.origin, *t.axis) for per_frame in tags for t in per_frame)
    surface_block = b"".join(encode_surface(s) for s in surfaces)
    ofs_tags = HEADER.size + len(frame_block)
    ofs_surfaces = ofs_tags + len(tag_block)
    head = HEADER.pack(IDENT, VERSION, name.encode("latin1"), 0, len(frames), len(tags[0]), len(surfaces), 0,
                       HEADER.size, ofs_tags, ofs_surfaces, ofs_surfaces + len(surface_block))
    return head + frame_block + tag_block + surface_block
