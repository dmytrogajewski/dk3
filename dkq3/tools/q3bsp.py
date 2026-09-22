"""Quake 3 BSP (IBSP v46) writer.

Struct layout from ioquake3 code/qcommon/qfiles.h.
"""
import struct
import numpy as np

IDENT, VERSION = b'IBSP', 46
LUMPS = ['entities', 'shaders', 'planes', 'nodes', 'leafs', 'leafsurfaces',
         'leafbrushes', 'models', 'brushes', 'brushsides', 'drawverts',
         'drawindexes', 'fogs', 'surfaces', 'lightmaps', 'lightgrid', 'visibility']

DT = {
 'shaders':     np.dtype([('shader', 'S64'), ('surfaceFlags', '<i4'), ('contentFlags', '<i4')]),
 'planes':      np.dtype([('normal', '<f4', 3), ('dist', '<f4')]),
 'nodes':       np.dtype([('planeNum', '<i4'), ('children', '<i4', 2),
                          ('mins', '<i4', 3), ('maxs', '<i4', 3)]),
 'leafs':       np.dtype([('cluster', '<i4'), ('area', '<i4'), ('mins', '<i4', 3),
                          ('maxs', '<i4', 3), ('firstLeafSurface', '<i4'),
                          ('numLeafSurfaces', '<i4'), ('firstLeafBrush', '<i4'),
                          ('numLeafBrushes', '<i4')]),
 'models':      np.dtype([('mins', '<f4', 3), ('maxs', '<f4', 3), ('firstSurface', '<i4'),
                          ('numSurfaces', '<i4'), ('firstBrush', '<i4'), ('numBrushes', '<i4')]),
 'brushes':     np.dtype([('firstSide', '<i4'), ('numSides', '<i4'), ('shaderNum', '<i4')]),
 'brushsides':  np.dtype([('planeNum', '<i4'), ('shaderNum', '<i4')]),
 'drawverts':   np.dtype([('xyz', '<f4', 3), ('st', '<f4', 2), ('lightmap', '<f4', 2),
                          ('normal', '<f4', 3), ('color', 'u1', 4)]),
 'fogs':        np.dtype([('shader', 'S64'), ('brushNum', '<i4'), ('visibleSide', '<i4')]),
 'surfaces':    np.dtype([('shaderNum', '<i4'), ('fogNum', '<i4'), ('surfaceType', '<i4'),
                          ('firstVert', '<i4'), ('numVerts', '<i4'), ('firstIndex', '<i4'),
                          ('numIndexes', '<i4'), ('lightmapNum', '<i4'),
                          ('lightmapX', '<i4'), ('lightmapY', '<i4'),
                          ('lightmapWidth', '<i4'), ('lightmapHeight', '<i4'),
                          ('lightmapOrigin', '<f4', 3), ('lightmapVecs', '<f4', (3, 3)),
                          ('patchWidth', '<i4'), ('patchHeight', '<i4')]),
}
MST_PLANAR, MST_PATCH, MST_TRISOUP, MST_FLARE = 1, 2, 3, 4

# ioquake3 contents and surface flags the converters write (code/qcommon/surfaceflags.h:30-80).
CONTENTS_SOLID, CONTENTS_LAVA, CONTENTS_SLIME, CONTENTS_WATER, CONTENTS_FOG = 0x1, 0x8, 0x10, 0x20, 0x40
CONTENTS_AREAPORTAL, CONTENTS_PLAYERCLIP, CONTENTS_MONSTERCLIP, CONTENTS_BOTCLIP = 0x8000, 0x10000, 0x20000, 0x400000
CONTENTS_ORIGIN, CONTENTS_BODY, CONTENTS_CORPSE, CONTENTS_DETAIL = 0x1000000, 0x2000000, 0x4000000, 0x8000000
CONTENTS_TRANSLUCENT = 0x20000000
SURF_SLICK, SURF_SKY, SURF_LADDER, SURF_NOIMPACT, SURF_NODRAW = 0x2, 0x4, 0x8, 0x10, 0x80
SURF_HINT, SURF_SKIP, SURF_NOLIGHTMAP, SURF_METALSTEPS = 0x100, 0x200, 0x400, 0x1000


def encode(lumps):
    """-> the IBSP 46 bytes of `lumps`, a dict name -> bytes | numpy array; an absent lump is empty."""
    head = bytearray(8 + 8 * len(LUMPS))
    head[0:4] = IDENT
    head[4:8] = struct.pack('<i', VERSION)
    body = bytearray()
    for i, name in enumerate(LUMPS):
        v = lumps.get(name, b'')
        b = v.tobytes() if isinstance(v, np.ndarray) else bytes(v)
        struct.pack_into('<ii', head, 8 + 8 * i, len(head) + len(body), len(b))
        body += b + b'\0' * ((-len(b)) % 4)
    return bytes(head) + bytes(body)
