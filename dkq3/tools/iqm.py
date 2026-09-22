"""IQM encoder for static meshes: ioquake3's inter-quake model format (version 2), laid out like
code/renderercommon/iqm.h and accepted by R_LoadIQM (code/renderergl1/tr_model_iqm.c).

`encode` returns the bytes of one model without joints, poses or animations: `iqmHeader_t`, the text block, the meshes, three
vertex arrays (float positions, normals and texture coordinates), the triangles and the bounds of its one frame. Positions are floats,
so a static model keeps coordinates MD3's 1/64-unit shorts cannot hold (FRD-017). Every struct is a table of (C field
name, struct format), checked against iqm.h by tests/test_iqm.py. Standard library only.

FRD: specs/frds/FRD-017-dkm-models-with-preserved-surfaces-vertices-and-sequences.md
"""
import struct
from dataclasses import dataclass

MAGIC = b"INTERQUAKEMODEL\0"
VERSION = 2
MAX_QPATH = 64
# R_LoadIQM rejects a file above 16 MiB (tr_model_iqm.c:215) and a mesh at SHADER_MAX_VERTEXES vertices or
# SHADER_MAX_INDEXES indexes (tr_model_iqm.c:419-431, code/qcommon/qfiles.h:31-32).
MAX_FILESIZE = 16 << 20
SHADER_MAX_VERTEXES = 1000
SHADER_MAX_INDEXES = 6 * SHADER_MAX_VERTEXES
# Vertex array types and formats (iqm.h); R_LoadIQM requires float positions and normals of 3 and texcoords of 2.
POSITION, TEXCOORD, NORMAL = 0, 1, 2
FLOAT = 7
ARRAYS = ((POSITION, 3), (NORMAL, 3), (TEXCOORD, 2))
# R_LoadIQM reads the meshes, vertex arrays, triangles and array values in place through 4-byte struct and int casts
# (tr_model_iqm.c:268, :296, :385, :403, :699, :717, :725), so every block starts on a 4-byte boundary: the text block is
# padded with NUL bytes (specs/bugs/BUG-iqm-models-misaligned-blocks-trap-ubsan.md).
ALIGNMENT = 4

HEADER_FIELDS = (("magic", "16s"), ("version", "I"), ("filesize", "I"), ("flags", "I"), ("num_text", "I"), ("ofs_text", "I"),
                 ("num_meshes", "I"), ("ofs_meshes", "I"), ("num_vertexarrays", "I"), ("num_vertexes", "I"),
                 ("ofs_vertexarrays", "I"), ("num_triangles", "I"), ("ofs_triangles", "I"), ("ofs_adjacency", "I"),
                 ("num_joints", "I"), ("ofs_joints", "I"), ("num_poses", "I"), ("ofs_poses", "I"), ("num_anims", "I"),
                 ("ofs_anims", "I"), ("num_frames", "I"), ("num_framechannels", "I"), ("ofs_frames", "I"),
                 ("ofs_bounds", "I"), ("num_comment", "I"), ("ofs_comment", "I"), ("num_extensions", "I"),
                 ("ofs_extensions", "I"))
MESH_FIELDS = (("name", "I"), ("material", "I"), ("first_vertex", "I"), ("num_vertexes", "I"), ("first_triangle", "I"),
               ("num_triangles", "I"))
VERTEX_ARRAY_FIELDS = (("type", "I"), ("flags", "I"), ("format", "I"), ("size", "I"), ("offset", "I"))
TRIANGLE_FIELDS = (("vertex", "3I"),)
BOUNDS_FIELDS = (("bbmin", "3f"), ("bbmax", "3f"), ("xyradius", "f"), ("radius", "f"))
# One frame: R_AddIQMSurfaces checks the entity frame against num_frames and prints "no such frame" for frame 0 of a model
# without frames (tr_model_iqm.c:1084-1093). A frame without poses reads no frame data (:880) and draws the base positions
# (:1228); its bounds are read from ofs_bounds (:543-557, :932-949).
NUM_FRAMES = 1


class IqmError(ValueError):
    """A model R_LoadIQM rejects; the message starts with the offending field."""


def layout(fields):
    """The little-endian struct of an iqm.h type given as (C field name, format) pairs."""
    return struct.Struct("<" + "".join(fmt for _, fmt in fields))


HEADER = layout(HEADER_FIELDS)
MESH = layout(MESH_FIELDS)
VERTEX_ARRAY = layout(VERTEX_ARRAY_FIELDS)
TRIANGLE = layout(TRIANGLE_FIELDS)
BOUNDS = layout(BOUNDS_FIELDS)


@dataclass(frozen=True)
class Mesh:
    """One mesh: per-vertex positions, normals and texture coordinates, and triangles as indexes into those vertices."""
    name: str
    material: str
    positions: tuple
    normals: tuple
    texcoords: tuple
    triangles: tuple


def _check(ok, field, message):
    if not ok:
        raise IqmError(f"{field}: {message}")


def validate(meshes):
    """Raises IqmError for meshes R_LoadIQM rejects or this static layout cannot hold."""
    _check(len(meshes) > 0, "meshes", "a model needs a mesh")
    for mesh in meshes:
        for field in ("name", "material"):
            value = getattr(mesh, field)
            _check(len(value.encode("latin1")) < MAX_QPATH, field, f"'{value}' does not fit {MAX_QPATH} bytes with its terminator")
        count = len(mesh.positions)
        _check(len(mesh.normals) == count and len(mesh.texcoords) == count, "arrays", f"{mesh.name}: arrays differ in length")
        _check(count > 0 and len(mesh.triangles) > 0, "empty", f"{mesh.name}: R_LoadIQM rejects a mesh without vertices or triangles")
        _check(count < SHADER_MAX_VERTEXES, "num_vertexes", f"{mesh.name}: {count} vertices, at most {SHADER_MAX_VERTEXES - 1}")
        _check(3 * len(mesh.triangles) < SHADER_MAX_INDEXES, "num_triangles", f"{mesh.name}: {len(mesh.triangles)} triangles")
        _check(all(0 <= i < count for t in mesh.triangles for i in t), "indexes", f"{mesh.name}: an index is outside 0..{count - 1}")


def bounds(meshes):
    """-> `iqmBounds_t` of every position: the box, the largest distance from the Z axis and from the origin."""
    points = [p for mesh in meshes for p in mesh.positions]
    low, high = [min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]
    xyradius = max((p[0] ** 2 + p[1] ** 2) ** 0.5 for p in points)
    radius = max((p[0] ** 2 + p[1] ** 2 + p[2] ** 2) ** 0.5 for p in points)
    return BOUNDS.pack(*low, *high, xyradius, radius)


def encode(meshes):
    """The bytes of one static IQM model. Raises IqmError (see `validate`)."""
    validate(meshes)
    text, offsets = bytearray(b"\0"), {}
    for value in (v for mesh in meshes for v in (mesh.name, mesh.material)):
        if value not in offsets:
            offsets[value] = len(text)
            text += value.encode("latin1") + b"\0"
    text += bytes(-len(text) % ALIGNMENT)
    records, triangles, first_vertex, first_triangle = [], bytearray(), 0, 0
    for mesh in meshes:
        records.append(MESH.pack(offsets[mesh.name], offsets[mesh.material], first_vertex, len(mesh.positions), first_triangle,
                                 len(mesh.triangles)))
        triangles += b"".join(TRIANGLE.pack(*(first_vertex + i for i in t)) for t in mesh.triangles)
        first_vertex, first_triangle = first_vertex + len(mesh.positions), first_triangle + len(mesh.triangles)
    columns = {POSITION: "positions", NORMAL: "normals", TEXCOORD: "texcoords"}
    data = [b"".join(struct.pack(f"<{size}f", *v) for mesh in meshes for v in getattr(mesh, columns[kind])) for kind, size in ARRAYS]
    ofs_text = HEADER.size
    ofs_meshes = ofs_text + len(text)
    ofs_arrays = ofs_meshes + len(records) * MESH.size
    offset = ofs_arrays + len(ARRAYS) * VERTEX_ARRAY.size
    arrays = b""
    for (kind, size), block in zip(ARRAYS, data):
        arrays += VERTEX_ARRAY.pack(kind, 0, FLOAT, size, offset)
        offset += len(block)
    ofs_triangles = offset
    ofs_bounds = ofs_triangles + len(triangles)
    filesize = ofs_bounds + BOUNDS.size
    _check(filesize <= MAX_FILESIZE, "filesize", f"{filesize} bytes, R_LoadIQM loads at most {MAX_FILESIZE}")
    counts = dict(num_text=len(text), ofs_text=ofs_text, num_meshes=len(meshes), ofs_meshes=ofs_meshes,
                  num_vertexarrays=len(ARRAYS), num_vertexes=first_vertex, ofs_vertexarrays=ofs_arrays,
                  num_triangles=first_triangle, ofs_triangles=ofs_triangles, num_frames=NUM_FRAMES, ofs_bounds=ofs_bounds)
    head = HEADER.pack(MAGIC, VERSION, filesize, *(counts.get(name, 0) for name, _ in HEADER_FIELDS[3:]))
    return head + bytes(text) + b"".join(records) + arrays + b"".join(data) + bytes(triangles) + bounds(meshes)
