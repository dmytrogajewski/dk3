"""Daikatana lighting -> ioquake3 lightmap pages and light grid (specs/assets/ASSET-bsp.md, "Lightmaps", "Light Grid").

LUMP_LIGHTING holds one RGB block per lightstyle per face, back to back from dface_t.lightofs. The rules follow Gold's
renderer, reference/dk-gold/base/ref_gl:
- block size: CalcSurfaceExtents in float32 (gl_model.cpp:713-765);
- which faces are lit: Mod_LoadFaces (gl_model.cpp:840-842);
- the style sum and clamp: R_BuildLightMap (gl_light.cpp:520-790);
- block placement: LM_AllocBlock (gl_rsurf.cpp:2788-2819);
- lightmap st: GL_BuildPolygonFromSurface (gl_rsurf.cpp:2880-2899);
- entity light: R_LightPoint (gl_light.cpp:163-420).

Values are stored in ioquake3's units: R_LoadLightmaps and R_LoadLightGrid (code/renderergl1/tr_bsp.c). Blocks of lightstyles
other than 0 are skipped and reported, because the game module sets those styles' values.

FRD: specs/frds/FRD-013-lightmaps-verified-in-engine.md
"""
import numpy as np

LUXEL = 16                  # world units per luxel: the >> 4 and * 16 of CalcSurfaceExtents and GL_CreateSurfaceLightmap
STYLE_NONE = 255            # styles[] terminator
STYLE_NORMAL = 0            # lightstyle 0, always on

SURF_FULLBRIGHT, SURF_SKY, SURF_FOGPLANE = 0x2, 0x4, 0x1000000     # texinfo flags (user/dk_shared.h:326-357)
CONTENTS_SOLID = 0x1        # user/qfiles.h:523

# Gold draws texture * min(sum * gl_modulate * style, 255) / 255 (gl_light.cpp:559-634, 696-712). ioquake3 shifts a lightmap
# byte by r_mapOverBrightBits - tr.overbrightBits at load (tr_bsp.c:100-125) and the hardware gamma ramp shifts the screen
# by tr.overbrightBits (tr_image.c:1313), so a byte is worth 2^r_mapOverBrightBits times its value in a window and in
# fullscreen alike. Storing sum * gl_modulate * style / 2^r_mapOverBrightBits gives Gold's multiplier on screen
# (specs/assets/ASSET-bsp.md, "Lightmap Scale", checked by headless screenshots at candidate scales).
GL_MODULATE = 2.0           # gl_rmain.cpp:1670; the 1.3 renderer's Cvar_Get("gl_modulate", "2") (install/daikatana 0x5cc0c7)
STYLE_NORMAL_VALUE = 1.0    # lightstyle 0 while lightmaps are built and in play (gl_rsurf.cpp:2962-2971)
R_MAP_OVERBRIGHT_BITS = 2   # r_mapOverBrightBits default (code/renderergl1/tr_init.c:1064)
LIGHTMAP_SCALE = GL_MODULATE * STYLE_NORMAL_VALUE / (1 << R_MAP_OVERBRIGHT_BITS)


def texture_coords(points, vecs):
    """-> float32 (s, t) of each point: x * vec.x + y * vec.y + z * vec.z + offset, added in C order in float32 like
    CalcSurfaceExtents' `val` (gl_model.cpp:738, 750)."""
    p, v = np.asarray(points, np.float32).reshape(-1, 3), np.asarray(vecs, np.float32).reshape(2, 4)
    return tuple(p[:, 0] * v[i, 0] + p[:, 1] * v[i, 1] + p[:, 2] * v[i, 2] + v[i, 3] for i in range(2))


def surface_extents(points, vecs):
    """-> (bmins s, bmins t, smax, tmax) in luxels, as CalcSurfaceExtents (gl_model.cpp:713-765) and
    GL_CreateSurfaceLightmap (gl_rsurf.cpp:2920-2921) compute them."""
    s, t = texture_coords(points, vecs)
    bmins = [int(np.floor(c.min() / np.float32(LUXEL))) for c in (s, t)]
    bmaxs = [int(np.ceil(c.max() / np.float32(LUXEL))) for c in (s, t)]
    return bmins[0], bmins[1], bmaxs[0] - bmins[0] + 1, bmaxs[1] - bmins[1] + 1


def gold_lightmapped(flags):
    """Whether Mod_LoadFaces builds a lightmap for a texinfo's flags: not SKY or FULLBRIGHT, and not exactly FOGPLANE
    (gl_model.cpp:840-842; R_BuildLightMap refuses the same, gl_light.cpp:532-533)."""
    return not flags & (SURF_SKY | SURF_FULLBRIGHT) and flags != SURF_FOGPLANE


class LightingOutOfBounds(ValueError):
    """A lightmapped face's style blocks reach past the lighting lump; Gold would read past its copy (gl_light.cpp:559-634)."""


def face_luxels(lighting, lightofs, styles, width, height):
    """-> (float64 luxels height x width x 3, skipped styles): the sum of a face's style-0 blocks, which lie back to back
    from lightofs in styles[] order up to the first 255 (R_BuildLightMap, gl_light.cpp:559-634)."""
    size = width * height * 3
    total, dropped = np.zeros(size, np.float64), []
    for k, style in enumerate(int(s) for s in styles):
        if style == STYLE_NONE:
            break
        if lightofs + (k + 1) * size > len(lighting):
            raise LightingOutOfBounds(f'lightofs {lightofs}: style block {k} ends at byte {lightofs + (k + 1) * size} '
                                      f'of a {len(lighting)}-byte lighting lump')
        block = np.frombuffer(lighting, np.uint8, size, lightofs + k * size)
        if style == STYLE_NORMAL:
            total += block
        else:
            dropped.append(style)
    return total.reshape(height, width, 3), tuple(dropped)


def scale_luxels(luxels, scale):
    """-> uint8 luxels: luxels * scale truncated like Q_ftol, and a luxel whose brightest channel passes 255 multiplied by
    the float 255 / max so its hue stays (R_BuildLightMap, gl_light.cpp:656-712)."""
    lit = np.trunc(np.asarray(luxels, np.float64) * scale)
    peak = lit.max(axis=-1, keepdims=True)
    t = np.float32(255.0) / np.maximum(peak, 1.0).astype(np.float32)
    return np.where(peak > 255.0, np.trunc(lit.astype(np.float32) * t), lit).astype(np.uint8)


BLOCK_SIZE = 128            # BLOCK_WIDTH, BLOCK_HEIGHT (gl_rsurf.cpp:22-23); ioquake3's LIGHTMAP_SIZE (tr_bsp.c:134)


class BlockTooLarge(ValueError):
    """A face's lightmap block fits on no empty page; Gold stops with Sys_Error (gl_rsurf.cpp:2927-2929)."""


class Atlas:
    """Deterministic shelf packing into ioquake3 lightmap pages."""

    def __init__(self):
        self.pages = []
        self.new_page()

    def new_page(self):
        self.pages.append(np.zeros((BLOCK_SIZE, BLOCK_SIZE, 3), np.uint8))
        self.x = self.y = self.row_height = 0

    def alloc(self, width, height):
        if not (0 < width <= BLOCK_SIZE and 0 < height <= BLOCK_SIZE):
            raise BlockTooLarge(f'{width}x{height} luxels exceeds {BLOCK_SIZE}x{BLOCK_SIZE}')
        if self.x + width > BLOCK_SIZE:
            self.x = 0
            self.y += self.row_height
            self.row_height = 0
        if self.y + height > BLOCK_SIZE:
            self.new_page()
        result = len(self.pages) - 1, self.x, self.y
        self.x += width
        self.row_height = max(self.row_height, height)
        return result

    def blit(self, page, x, y, luxels):
        height, width = luxels.shape[:2]
        self.pages[page][y:y + height, x:x + width] = luxels

    def tobytes(self):
        pages = self.pages if len(self.pages) > 1 else self.pages * 2
        return b''.join(page.tobytes() for page in pages)


GRID_SIZE = (64.0, 64.0, 128.0)     # lightGridSize unless worldspawn has "gridsize" (tr_bsp.c:1698-1700, 1759-1762)


def grid_bounds(mins, maxs, size):
    """-> (float32 origin, int point counts per axis) of R_LoadLightGrid (tr_bsp.c:1660-1666) for the world model bounds."""
    size, mins, maxs = (np.asarray(v, np.float32) for v in (size, mins, maxs))
    origin = size * np.ceil(mins / size)
    return origin, ((size * np.floor(maxs / size) - origin) / size + 1).astype(np.int64)


FIXED_SHADE_VECTOR = (-1.0, -1.0, -1.0)     # the alias model light direction without dynamic lights (gl_mesh.cpp:1896)


def grid_direction(vector):
    """-> (longitude, latitude) bytes of a direction as R_SetupEntityLightingGrid decodes them: x = cos(lat) sin(lng),
    y = sin(lat) sin(lng), z = cos(lng), one byte per 1/256 of a turn (tr_light.c:222-233)."""
    x, y, z = np.asarray(vector, np.float64) / np.linalg.norm(vector)
    turn = 256 / (2 * np.pi)
    return int(round(np.arccos(z) * turn)) % 256, int(round(np.arctan2(y, x) * turn)) % 256


GRID_DIRECTION = grid_direction(FIXED_SHADE_VECTOR)
# Gold's light 1.0 in lightmap byte units: the directional term of a model vertex, min(shadelight + max(dot(shadevector,
# normal), 0), 1) (gl_mesh.cpp:97-99), and R_LightPoint's colour on a map without light data (gl_light.cpp:331-336).
UNIT_LIGHT = 255 >> R_MAP_OVERBRIGHT_BITS
GRID_POINT_BYTES = 8


def grid_ambient(sampler, point):
    """-> the 3 ambient bytes of a grid point, or None for 8 zero bytes: in a solid leaf, or a trace that hits nothing
    (ioquake3 skips an all-zero ambient, tr_light.c:196-199). Otherwise R_LightPoint's style-0 light, sum * gl_modulate *
    gl_modulate (gl_light.cpp:285-297, 383, 402), in lightmap byte units; UNIT_LIGHT without light data."""
    if sampler.in_solid(point):
        return None
    if not sampler.lighting:
        return bytes((UNIT_LIGHT,) * 3)
    light = sampler.light_point(point)
    return None if light is None else scale_luxels(light, LIGHTMAP_SCALE * GL_MODULATE).tobytes()


def grid_lump(sampler, mins, maxs, size):
    """-> LUMP_LIGHTGRID bytes for the world bounds: per point, x first, then y, then z (tr_light.c:166-168), the ambient
    bytes, the directed term UNIT_LIGHT and GRID_DIRECTION; 8 zero bytes where grid_ambient gives None."""
    origin, bounds = grid_bounds(mins, maxs, size)
    step, out = np.asarray(size, np.float32), bytearray()
    for index in np.ndindex(*bounds[::-1]):
        ambient = grid_ambient(sampler, origin + step * np.array(index[::-1], np.float32))
        out += bytes(GRID_POINT_BYTES) if ambient is None else ambient + bytes((UNIT_LIGHT,) * 3 + GRID_DIRECTION)
    return bytes(out)


TRACE_DEPTH = 2048.0        # R_LightPoint traces from p to p.z - 2048 (gl_light.cpp:336-338)


def _plane_distance(point, normal, dist):
    """float32 DotProduct(point, normal) - dist, in C order."""
    return point[0] * normal[0] + point[1] * normal[1] + point[2] * normal[2] - dist


class LightSampler:
    """Sample supplied light data by intersecting a ray with BSP partitions."""

    def __init__(self, bsp):
        self.planes, self.nodes, self.faces, self.lighting = bsp.arr('planes'), bsp.arr('nodes'), bsp.faces(), bsp.raw('lighting')
        texinfo = bsp.arr('texinfo')
        self.vecs, self.flags, self.head, self.blocks = texinfo['vecs'], texinfo['flags'], int(bsp.arr('models')[0]['headnode']), {}
        edges, surfedges = bsp.arr('edges')['v'], bsp.arr('surfedges').astype(np.int64)
        self.face_points = bsp.arr('vertexes')['xyz'][np.where(surfedges >= 0, edges[np.abs(surfedges), 0],
                                                                edges[np.abs(surfedges), 1])]
        self.contents = bsp.arr('leafs')['contents']

    def in_solid(self, point):
        """Whether `point` falls in a CONTENTS_SOLID leaf, descending like Mod_PointInLeaf: the front child when
        DotProduct(p, normal) - dist > 0 (gl_model.cpp:123-146)."""
        p, node = np.asarray(point, np.float32), self.head
        while node >= 0:
            plane = self.planes[int(self.nodes[node]['planenum'])]
            node = int(self.nodes[node]['children'][0 if _plane_distance(p, plane['normal'], plane['dist']) > 0 else 1])
        return bool(self.contents[-1 - node] & CONTENTS_SOLID)

    def light_point(self, point):
        """-> RGB style-0 luxel sum of the first lit face under `point`; zeros for a face without light data; None when
        the trace hits nothing."""
        start = np.asarray(point, np.float32)
        return self.trace(self.head, start, start - np.array((0.0, 0.0, TRACE_DEPTH), np.float32))

    def trace(self, node, start, end):
        """Collect intersected partition faces iteratively, sample nearest valid hit."""
        direction = end - start
        candidates = []
        pending = [(node, 0.0, 1.0)]
        while pending:
            index, low, high = pending.pop()
            if index < 0:
                continue
            record = self.nodes[index]
            plane = self.planes[int(record['planenum'])]
            origin_distance = float(np.dot(start, plane['normal']) - plane['dist'])
            slope = float(np.dot(direction, plane['normal']))
            crossing = -origin_distance / slope if abs(slope) > 1e-10 else None
            if crossing is not None and low <= crossing <= high:
                candidates.extend((crossing, face) for face in range(int(record['firstface']),
                                  int(record['firstface']) + int(record['numfaces'])))
                before = int(origin_distance + slope * low < 0)
                pending.append((int(record['children'][before]), low, crossing))
                pending.append((int(record['children'][1 - before]), crossing, high))
            else:
                side = int(origin_distance + slope * ((low + high) / 2) < 0)
                pending.append((int(record['children'][side]), low, high))
        for distance, face in sorted(candidates):
            value = self.sample(face, start + direction * distance)
            if value is not None:
                return value
        return None

    def sample(self, face, mid):
        """-> the face's luxel under `mid`, zeros without light data, or None outside its lightmap extents."""
        f = self.faces[face]
        if self.flags[int(f['texinfo'])] == SURF_FOGPLANE | SURF_FULLBRIGHT:
            return None
        vecs = self.vecs[int(f['texinfo'])]
        points = self.face_points[int(f['firstedge']):int(f['firstedge']) + int(f['numedges'])]
        smin, tmin, width, height = surface_extents(points, vecs)
        ds, dt = (int(c[0]) - low * LUXEL for c, low in zip(texture_coords(mid, vecs), (smin, tmin)))
        if ds < 0 or dt < 0 or ds > (width - 1) * LUXEL or dt > (height - 1) * LUXEL:
            return None
        if int(f['lightofs']) < 0:
            return np.zeros(3)
        if face not in self.blocks:
            self.blocks[face] = face_luxels(self.lighting, int(f['lightofs']), f['styles'], width, height)[0]
        return self.blocks[face][dt >> 4, ds >> 4]


def lightmap_st(points, vecs, smin, tmin, x, y):
    """-> float32 lightmap st of each point on its page: s - texturemins + light_s * 16 + 8, then / 2048, in float like
    GL_BuildPolygonFromSurface (gl_rsurf.cpp:2880-2899). The half luxel keeps every sample inside the face's block."""
    luxel, span = np.float32(LUXEL), np.float32(BLOCK_SIZE * LUXEL)
    return np.stack([(c - np.float32(low * LUXEL) + np.float32(at * LUXEL) + luxel / 2) / span
                     for c, low, at in zip(texture_coords(points, vecs), (smin, tmin), (x, y))], axis=1)
