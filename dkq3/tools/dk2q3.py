#!/usr/bin/env python3
"""Daikatana IBSP 41 -> ioquake3 IBSP 46 (specs/assets/ASSET-bsp.md).

Finds the map and its `.ent` override through the 1.3 file-system search order, resolves texture-coordinate divisors from
the Step 6 manifest and the Step 11 textures.json, names each surface's shader with shadergen.py's render rules, and writes
the converted map, a JSON report of the applied losses and the shader definitions shadergen.py packages
(specs/assets/ASSET-shaders.md). Lightmaps follow Gold (Step 13). The entity lump keeps the Daikatana text, and the same map
with the stock ioquake3 game module projection as its entity lump is written for engine acceptance only (Step 15,
specs/assets/ASSET-entities.md).

FRD: specs/frds/FRD-012-bsp-v41-to-v46-converter-hardened.md
FRD: specs/frds/FRD-013-lightmaps-verified-in-engine.md
FRD: specs/frds/FRD-014-surface-flags-and-texture-animation-as-q3-shaders.md
FRD: specs/frds/FRD-015-entity-census-verbatim-preservation-and-stock-module-projection.md
"""
import argparse
import collections
import json
import os
import struct
import sys

import numpy as np

import dkbsp
import dkpak
import asset_source
import entities
import lightmap
import q3bsp
import shadergen

Q = q3bsp
PREFIX = 'dk2q3:'
TEXTURE_PREFIX = 'textures/'
IMAGE_STATUS = 'image'
# Gold draws r_notexture, an 8x8 image (gl_particle.cpp:43), for a texinfo texture it cannot load (gl_model.cpp:679-683).
NOTEXTURE_SHADER = shadergen.NOTEXTURE_NAME
NOTEXTURE_SIZE = (8, 8)
# 1.3's Mod_LoadTexinfo loads textures/<texture>_glow.tga per texinfo (install/daikatana 0x5c3ed7-0x5c3f11).
GLOW_SUFFIX = '_glow'
NO_SHADER = 'noshader'                       # brush sides without a texinfo (texinfo -1)
CONTENTS_SHADER = 'textures/dkq3/contents_%08x'
# CMod_LoadSubmodels (cm_load.c:137-139) with the build's collision rows: at most CAPSULE_MODEL_HANDLE models
# (build/ioq3_patches.zig capsule_model_handle = max_submodels - 2; upstream MAX_SUBMODELS 256,
# specs/bugs/BUG-maps-over-256-submodels-do-not-load.md). Model indices above 255 reach the client packed game-side
# (roadmap Step 61, src/game/shared/dk_modelindex.h), not through a wider wire field.
MAX_SUBMODELS = 510
MAX_FACE_POINTS = 64                         # code/renderergl1/tr_local.h:504, ParseFace (tr_bsp.c:320-325)
MAX_SHADER_NAME = 63                         # dshader_t.shader is char[MAX_QPATH] (code/qcommon/qfiles.h:392-396)
# CM_BoundBrush reads sides 0-5 as the axial planes -x, +x, -y, +y, -z, +z (code/qcommon/cm_load.c:215-224).
AXIAL_NORMALS = np.array([[-1, 0, 0], [1, 0, 0], [0, -1, 0], [0, 1, 0], [0, 0, -1], [0, 0, 1]], np.float32)
MERGED_AREA = 0                              # every leaf in one area, as Gold with map_noareas 1 (cmodel.cpp:1854-1864)
LIGHTMAP_BY_VERTEX = -3                      # carried unchanged: code/renderergl1/tr_local.h
DK_SURF_NODRAW = 0x80                        # user/dk_shared.h:335; Gold never draws such a face (gl_rsurf.cpp:2466)
# Faces Gold's draw chains skip (shadergen.category): world flags equal to SURF_FOGPLANE (gl_rsurf.cpp:2511-2514) and SKY
# on a brush model (GL_RenderLightmappedPoly, :1499-1502).
UNDRAWN_FOGPLANE, UNDRAWN_SUBMODEL_SKY = 'fogplane', 'submodel_sky'
# 1.3's CMod_LoadEntityString (install/daikatana 0x4a83f0) uses maps/<map>.ent when FS_LoadFile returns 2 to 0x80000 bytes.
ENTITY_FILE_MIN, ENTITY_FILE_MAX = 2, 0x80000
PAK_NAMES = tuple(f'pak{i}.pak' for i in range(9, -1, -1))
VIS_HEADER = struct.Struct('<ii')

# Daikatana contents bit (user/qfiles.h:523-561) -> ioquake3 contents (surfaceflags.h:30-60); a 0 target is a recorded
# loss, except LADDER, which reaches the brush's sides as SURF_LADDER (specs/assets/ASSET-bsp.md, "Contents").
CONTENTS = (
    (0x00000001, 'SOLID', Q.CONTENTS_SOLID), (0x00000002, 'WINDOW', Q.CONTENTS_SOLID), (0x00000004, 'AUX', 0),
    (0x00000008, 'LAVA', Q.CONTENTS_LAVA), (0x00000010, 'SLIME', Q.CONTENTS_SLIME), (0x00000020, 'WATER', Q.CONTENTS_WATER),
    (0x00000040, 'MIST', 0), (0x00000080, 'CLEAR', Q.CONTENTS_SOLID), (0x00000100, 'NOTSOLID', 0),
    (0x00000200, 'NOSHOOT', Q.CONTENTS_PLAYERCLIP | Q.CONTENTS_MONSTERCLIP), (0x00000400, 'FOG', Q.CONTENTS_FOG),
    (0x00000800, 'NITRO', 0), (0x00008000, 'AREAPORTAL', Q.CONTENTS_AREAPORTAL),
    (0x00010000, 'PLAYERCLIP', Q.CONTENTS_PLAYERCLIP), (0x00020000, 'MONSTERCLIP', Q.CONTENTS_MONSTERCLIP),
    (0x00040000, 'CURRENT_0', 0), (0x00080000, 'CURRENT_90', 0), (0x00100000, 'CURRENT_180', 0),
    (0x00200000, 'CURRENT_270', 0), (0x00400000, 'CURRENT_UP', 0), (0x00800000, 'CURRENT_DOWN', 0),
    (0x01000000, 'ORIGIN', Q.CONTENTS_ORIGIN), (0x02000000, 'MONSTER', Q.CONTENTS_BODY),
    (0x04000000, 'DEADMONSTER', Q.CONTENTS_CORPSE), (0x08000000, 'DETAIL', Q.CONTENTS_DETAIL),
    (0x10000000, 'TRANSLUCENT', Q.CONTENTS_TRANSLUCENT), (0x20000000, 'LADDER', 0),
    (0x40000000, 'NPCCLIP', Q.CONTENTS_BOTCLIP),
)
CONTENTS_LADDER = 0x20000000
PROJECTED_CONTENTS = ('LADDER',)
# Daikatana surface bit (user/dk_shared.h:326-357) -> ioquake3 surface flags (surfaceflags.h:62-80); 0 is a recorded loss
# (specs/assets/ASSET-bsp.md, "Surface flags").
SURFACES = (
    (0x1, 'LIGHT', 0), (0x2, 'FULLBRIGHT', Q.SURF_NOLIGHTMAP), (0x4, 'SKY', Q.SURF_SKY | Q.SURF_NOIMPACT | Q.SURF_NOLIGHTMAP),
    (0x8, 'WARP', 0), (0x10, 'TRANS33', 0), (0x20, 'TRANS66', 0), (0x40, 'FLOWING', 0), (0x80, 'NODRAW', Q.SURF_NODRAW),
    (0x100, 'HINT', Q.SURF_HINT), (0x200, 'SKIP', Q.SURF_SKIP), (0x400, 'WOOD', 0), (0x800, 'METAL', Q.SURF_METALSTEPS),
    (0x1000, 'STONE', 0), (0x2000, 'GLASS', 0), (0x4000, 'ICE', Q.SURF_SLICK), (0x8000, 'SNOW', 0), (0x10000, 'MIRROR', 0),
    (0x20000, 'TRANSTHING', 0), (0x40000, 'ALPHACHAN', 0), (0x80000, 'MIDTEXTURE', 0), (0x100000, 'PUDDLE', 0),
    (0x200000, 'SURGE', 0), (0x400000, 'BIGSURGE', 0), (0x800000, 'BULLETLIGHT', 0), (0x1000000, 'FOGPLANE', 0),
    (0x2000000, 'SAND', 0),
)
UINT32 = 0xFFFFFFFF


class ConvertError(ValueError):
    """A map the converter cannot turn into an IBSP 46 ioquake3 loads as Gold loaded the original."""


class TextureError(ConvertError):
    """A texinfo texture has no Step 6 image, no WAL size, and textures.json does not list it as missing for the map."""


class InputMismatch(ConvertError):
    """The Step 6 manifest, textures.json and the game directory disagree (built from different corpora or runs)."""


class LimitError(ConvertError):
    """The map passes a limit or a layout assumption of ioquake3's loaders."""


class LightmapError(ConvertError):
    """A lit face's style blocks reach past the lighting lump, or its block fits no lightmap page (Gold would read past its
    copy or stop with Sys_Error)."""


class ShaderRuleError(ConvertError):
    """A nexttexinfo chain Gold cannot animate (shadergen.RingError), or one shader name with two definitions
    (specs/assets/ASSET-shaders.md)."""


class BrushOwnership(ConvertError):
    """A brush is reached from the node trees of two models, so no contiguous brush range per model exists."""


class MapNotFound(ConvertError):
    """The game directory holds no maps/<map>.bsp."""


def _map_bits(value, table, projected=()):
    """-> (target bits, names of set bits the table drops, set bits the table does not define)."""
    value &= UINT32
    target, dropped, known = 0, [], 0
    for bit, name, bits in table:
        known |= bit
        if value & bit:
            target |= bits
            if not bits and name not in projected:
                dropped.append(name)
    return target, dropped, value & ~known


def map_contents(contents):
    """Daikatana brush contents -> (ioquake3 contents, dropped bit names, undefined bits)."""
    return _map_bits(contents, CONTENTS, PROJECTED_CONTENTS)


def map_surface(flags):
    """Daikatana texinfo flags -> (ioquake3 surface flags, dropped bit names, undefined bits)."""
    return _map_bits(flags, SURFACES)


def side_surface_flags(contents):
    """Surface flags a brush's contents add to each of its sides: CONTENTS_LADDER becomes SURF_LADDER, which the stock
    game's PM_CheckLadder reads from the trace (Gold reads trace.contents instead, pmove.cpp:986-993)."""
    return Q.SURF_LADDER if contents & CONTENTS_LADDER else 0


def check_limits(bsp, texinfo=None):
    """Raises LimitError when ioquake3's loaders cannot take a validated map as is: more than MAX_SUBMODELS models, a
    brush whose sides 0-5 are not the axial planes CM_BoundBrush reads, or a drawn face with more than MAX_FACE_POINTS
    points."""
    models, brushes = bsp.count('models'), bsp.arr('brushes')
    if models > MAX_SUBMODELS:
        raise LimitError(f'{bsp.source}: {models} models, ioquake3 loads at most {MAX_SUBMODELS}')
    short = np.flatnonzero(brushes['numsides'] < len(AXIAL_NORMALS))
    if short.size:
        raise LimitError(f'{bsp.source}: brush {int(short[0])} has {int(brushes["numsides"][short[0]])} sides; '
                         f'CM_BoundBrush reads {len(AXIAL_NORMALS)}')
    sides = brushes['firstside'][:, None] + np.arange(len(AXIAL_NORMALS))
    normals = bsp.arr('planes')['normal'][bsp.arr('brushsides')['planenum'][sides]]
    unordered = np.flatnonzero((normals != AXIAL_NORMALS).any(axis=(1, 2)))
    if unordered.size:
        raise LimitError(f'{bsp.source}: brush {int(unordered[0])}: sides 0-5 are not the axial planes -x, +x, -y, +y, '
                         f'-z, +z CM_BoundBrush reads')
    texinfo = bsp.texinfo() if texinfo is None else texinfo
    faces = bsp.faces()
    drawn = np.array([not texinfo[int(t)]['flags'] & DK_SURF_NODRAW for t in faces['texinfo']], bool)
    big = np.flatnonzero(drawn & (faces['numedges'] > MAX_FACE_POINTS))
    if big.size:
        raise LimitError(f'{bsp.source}: face {int(big[0])} has {int(faces["numedges"][big[0]])} points; ParseFace '
                         f'draws at most {MAX_FACE_POINTS}')


def lightmapped_faces(bsp, texinfo):
    """-> (face index, face, float32 points in surfedge order, texinfo) of every face the converter draws (not NODRAW, at
    least 3 edges) that gets a lightmap block: light data (lightofs >= 0) and lit by Mod_LoadFaces (gl_model.cpp:840-842)."""
    edges, surfedges, verts = bsp.arr('edges')['v'], bsp.arr('surfedges'), bsp.arr('vertexes')['xyz']
    first = np.where(surfedges >= 0, edges[np.abs(surfedges)][:, 0], edges[np.abs(surfedges)][:, 1])
    for fi, f in enumerate(bsp.faces()):
        t, points = texinfo[int(f['texinfo'])], verts[first[int(f['firstedge']):int(f['firstedge']) + int(f['numedges'])]]
        if int(f['lightofs']) >= 0 and len(points) >= 3 and not t['flags'] & DK_SURF_NODRAW and \
                lightmap.gold_lightmapped(t['flags']):
            yield fi, f, points, t


def world_centre(bsp):
    """-> the centre of the world model's bounds: the initial spot of a text without a usable player spot
    (specs/assets/ASSET-entities.md, "Projection")."""
    world = bsp.arr('models')[0]
    return tuple(float(v) for v in (world['mins'] + world['maxs']) / 2)


class Textures:
    """Shader names and texture-coordinate divisors of one map's texinfo textures, from the Step 6 manifest (`images`) and
    textures.json (`remap`, `missing`, `textures`)."""

    def __init__(self, manifest, textures, map_key):
        self.images, self.records, self.map_key = manifest['images'], textures['textures'], map_key
        self.remap = textures['remap'].get(map_key, {})
        self.missing = {name for name, maps in textures['missing'].items() if map_key in maps}

    def resolve(self, texture):
        """-> (shader name, (WAL width, WAL height), missing key or None) for a texinfo texture name."""
        key = TEXTURE_PREFIX + texture
        if key in self.missing:
            return NOTEXTURE_SHADER, NOTEXTURE_SIZE, key
        image = self.images.get(key, {})
        if image.get('status') != IMAGE_STATUS or image.get('engine_w') is None:
            raise TextureError(f'{self.map_key}: {key}: no Step 6 image with a WAL size, and textures.json does not list '
                               f'it as missing for this map')
        name, size = self.remap.get(key, key), (image['engine_w'], image['engine_h'])
        record = self.records.get(name)
        if record is None or (record['engine_w'], record['engine_h']) != size:
            found = None if record is None else (record['engine_w'], record['engine_h'])
            raise InputMismatch(f'{self.map_key}: {name}: the manifest gives WAL size {size}, textures.json {found}')
        return name, size, None

    def frame(self, texture):
        """-> (engine name, WAL size, image size, glow image name or None) of a texinfo texture, as shadergen.surface reads
        it: the Step 6 image's size, and the `<texture>_glow` image 1.3 draws over it when Step 6 extracted one."""
        name, size, missing = self.resolve(texture)
        if missing:
            return name, size, size, None
        key = TEXTURE_PREFIX + texture
        glow, image = key + GLOW_SUFFIX, self.images[key]
        return name, size, (image['w'], image['h']), glow if self.images.get(glow, {}).get('status') == IMAGE_STATUS else None


class GameDir:
    """Finds a file as the 1.3 file system does: the game directory itself, then pak9.pak ... pak0.pak (each pak of a
    directory is pushed to the head of the search path, then the directory; files.cpp:1142-1160)."""

    def __init__(self, root):
        self.root = root
        self.paks = [(name, dkpak.Pak(os.path.join(root, name))) for name in asset_source.archive_order(root)
                     if os.path.isfile(os.path.join(root, name))]

    def __enter__(self):
        return self

    def __exit__(self, *_):
        for _, pak in self.paks:
            pak.close()

    def find(self, name):
        """-> (origin, bytes) of the first match: `name` for a loose file, `<pak>:<name>` for an archive entry; or None."""
        loose = os.path.join(self.root, name)
        if os.path.isfile(loose):
            with open(loose, 'rb') as f:
                return name, f.read()
        for pak_name, pak in self.paks:
            if name in pak.entries:
                return f'{pak_name}:{name}', pak.read(name)
        return None


def entity_text(lump, found):
    """-> (entity text, its source): the `.ent` override `found` (origin, bytes) replaces the lump when its length is in
    [ENTITY_FILE_MIN, ENTITY_FILE_MAX], as 1.3 prints ".ent file loaded"; otherwise the lump stays ("too small",
    "too large")."""
    if found is None:
        return lump, 'lump'
    origin, data = found
    if not ENTITY_FILE_MIN <= len(data) <= ENTITY_FILE_MAX:
        return lump, f'lump ({origin}: {len(data)} bytes, outside [{ENTITY_FILE_MIN}, {ENTITY_FILE_MAX}])'
    return data, origin


class Converter:
    """One validated v41 map -> IBSP 46 bytes and a report (specs/assets/ASSET-bsp.md, "Mapping Rules")."""

    def __init__(self, bsp, textures, entity_text, name, entity_source='lump', lightmap_scale=lightmap.LIGHTMAP_SCALE):
        bsp.validate()
        self.b, self.textures, self.entity_text, self.name = bsp, textures, entity_text, name
        self.entity_source, self.lightmap_scale = entity_source, lightmap_scale
        self.texinfo = bsp.texinfo()
        self.shader_rows, self.shader_index, self.definitions = [], {}, {}
        self.sky = (self.worldspawn_value(entity_text, 'sky') or '').lower()
        self.stats = collections.Counter()
        self.losses = dict(missing_texture=collections.Counter(), surface_flags_dropped=collections.Counter(),
                           contents_dropped=collections.Counter(), light_styles_dropped=collections.Counter(),
                           undrawn_faces=collections.Counter(), surface_undefined=0, contents_undefined=0,
                           nodraw_faces=0, degenerate_faces=0, vis_overruns=0)

    def convert(self):
        """-> (IBSP 46 bytes whose entity lump is the Daikatana text, the same map with the stock projection as its entity
        lump, report dict). Both entity lumps come from one entities.lumps pass (specs/assets/ASSET-entities.md)."""
        self.check_limits()
        self.build_shaders()
        self.build_lightmaps()
        self.build_surfaces()
        self.build_tree()
        self.build_vis()
        verbatim, self.projection = entities.lumps(self.entity_text, self.b.count('models'), world_centre(self.b))
        lumps = dict(entities=verbatim, shaders=self.shader_lump(), planes=self.planes, nodes=self.nodes,
                     leafs=self.leafs, leafsurfaces=self.leafsurfaces, leafbrushes=self.leafbrushes, models=self.models,
                     brushes=self.brushes, brushsides=self.brushsides, drawverts=self.drawverts,
                     drawindexes=self.drawindexes, fogs=b'', surfaces=self.surfaces, lightmaps=self.lightmaps,
                     lightgrid=self.build_lightgrid(verbatim), visibility=self.visibility)
        return q3bsp.encode(lumps), q3bsp.encode(dict(lumps, entities=self.projection.lump)), self.report(lumps)

    # ------------------------------------------------------------------ limits
    def fail(self, error, detail):
        raise error(f'{self.b.source}: {detail}')

    def check_limits(self):
        check_limits(self.b, self.texinfo)

    # ----------------------------------------------------------------- shaders
    def shader(self, name, surface=0, contents=0):
        """-> the shader lump index of (name, surface flags, contents), added in first-use order."""
        key = (name, surface, contents)
        if key not in self.shader_index:
            if len(name.encode('latin1')) > MAX_SHADER_NAME:
                self.fail(LimitError, f'shader {name}: longer than the {MAX_SHADER_NAME} bytes of dshader_t.shader')
            self.shader_index[key] = len(self.shader_rows)
            self.shader_rows.append(key)
        return self.shader_index[key]

    def build_shaders(self):
        """Every texinfo's world shader, in texinfo order: its name (shadergen.surface) with the mapped surface flags."""
        self.texinfo_name, self.texinfo_size, self.texinfo_surface = [], [], []
        for ti, t in enumerate(self.texinfo):
            _, size, missing = self.textures.resolve(t['texture'])
            surface, dropped, undefined = map_surface(t['flags'])
            if missing:
                self.losses['missing_texture'][missing] += 1
            self.losses['surface_flags_dropped'].update(dropped)
            self.losses['surface_undefined'] |= undefined
            name = self.define(ti)
            self.texinfo_name.append(name)
            self.texinfo_size.append(size)
            self.texinfo_surface.append(surface)
            self.shader(name, surface)

    def define(self, ti, submodel=False):
        """-> the shader name of texinfo `ti` on a world or brush-model face; its definition is recorded once per name."""
        try:
            name, definition = shadergen.surface(self.texinfo, ti, self.textures.frame, self.sky, submodel)
        except shadergen.RingError as error:
            self.fail(ShaderRuleError, str(error))
        if self.definitions.setdefault(name, definition) != definition:
            self.fail(ShaderRuleError, f'shader {name}: texinfo {ti} defines it differently from an earlier texinfo')
        return name

    def shader_document(self):
        """-> {"map", "shaders"}: the definition of every shader lump name for shadergen.py; contents and noshader draw
        nothing."""
        return dict(map=self.name, shaders={name: self.definitions.get(name, dict(shadergen.NODRAW_DEFINITION))
                                            for name, _, _ in self.shader_rows})

    def side_shader(self, texinfo, extra):
        if texinfo < 0:
            return self.shader(NO_SHADER, extra)
        return self.shader(self.texinfo_name[texinfo], self.texinfo_surface[texinfo] | extra)

    def shader_lump(self):
        arr = np.zeros(len(self.shader_rows), Q.DT['shaders'])
        for i, (name, surface, contents) in enumerate(self.shader_rows):
            arr[i] = (name.encode('latin1'), surface, contents)
        return arr

    # -------------------------------------------------------------- lightmaps
    def build_lightmaps(self):
        """Gold's lightmap blocks (specs/assets/ASSET-bsp.md, "Lightmaps"): each drawn face Mod_LoadFaces lights, in face
        order, gets its style-0 luxels, scaled into ioquake3's byte range, on LM_AllocBlock pages."""
        lighting, atlas, self.face_lm = self.b.raw('lighting'), lightmap.Atlas(), {}
        for fi, f, points, t in lightmapped_faces(self.b, self.texinfo):
            smin, tmin, width, height = lightmap.surface_extents(points, t['vecs'])
            try:
                luxels, dropped = lightmap.face_luxels(lighting, int(f['lightofs']), f['styles'], width, height)
                page, x, y = atlas.alloc(width, height)
            except (lightmap.LightingOutOfBounds, lightmap.BlockTooLarge) as error:
                self.fail(LightmapError, f'face {fi}: {error}')
            self.losses['light_styles_dropped'].update(str(style) for style in sorted(set(dropped)))
            atlas.blit(page, x, y, lightmap.scale_luxels(luxels, self.lightmap_scale))
            self.face_lm[fi] = (page, x, y, width, height, smin, tmin)
        self.lightmaps = atlas.tobytes() if self.face_lm else b''
        self.stats['lm_faces'] = len(self.face_lm)
        self.stats['lm_pages'] = len(self.lightmaps) // (lightmap.BLOCK_SIZE * lightmap.BLOCK_SIZE * 3)

    # --------------------------------------------------------------- surfaces
    def build_surfaces(self):
        b = self.b
        verts = b.arr('vertexes')['xyz'].astype(np.float64)
        edges = b.arr('edges')['v']
        surfedges = b.arr('surfedges')
        planes = b.arr('planes')
        first_vertex = np.where(surfedges >= 0, edges[np.abs(surfedges)][:, 0], edges[np.abs(surfedges)][:, 1])
        dv, di, rows = [], [], []
        self.surface_of_face = {}
        in_submodel = np.zeros(b.count('faces'), bool)
        for model in b.arr('models')[1:]:
            in_submodel[int(model['firstface']):int(model['firstface']) + int(model['numfaces'])] = True
        for fi, f in enumerate(b.faces()):
            ti, ne = int(f['texinfo']), int(f['numedges'])
            t = self.texinfo[ti]
            if t['flags'] & DK_SURF_NODRAW:
                self.losses['nodraw_faces'] += 1
                continue
            if ne < 3:
                self.losses['degenerate_faces'] += 1
                continue
            submodel = bool(in_submodel[fi])
            if shadergen.category(t['flags'], submodel) == 'undrawn':
                self.losses['undrawn_faces'][UNDRAWN_SUBMODEL_SKY if submodel else UNDRAWN_FOGPLANE] += 1
                continue
            name = self.define(ti, submodel)
            lm = self.face_lm.get(fi) if self.definitions[name].get('lightmap', True) else None
            pts = verts[first_vertex[int(f['firstedge']):int(f['firstedge']) + ne]]
            normal = planes[int(f['planenum'])]['normal'].astype(np.float64)
            if f['side']:
                normal = -normal
            width, height = self.texinfo_size[ti]
            vecs = np.array(t['vecs'], np.float64).reshape(2, 4)
            s = (pts @ vecs[0, :3] + vecs[0, 3]) / width
            tt = (pts @ vecs[1, :3] + vecs[1, 3]) / height
            lmst = np.zeros((ne, 2)) if lm is None else lightmap.lightmap_st(pts, t['vecs'], lm[5], lm[6], lm[1], lm[2])
            first = len(dv)
            dv.extend((tuple(pts[k]), (s[k], tt[k]), tuple(lmst[k]), tuple(normal), self.VERTEX_COLOUR) for k in range(ne))
            fidx = len(di)
            for k in range(1, ne - 1):
                di += [0, k, k + 1]
            self.surface_of_face[fi] = len(rows)
            rows.append((self.shader(name, self.texinfo_surface[ti]), first, ne, fidx, normal, lm))
        self.drawverts = np.array(dv, Q.DT['drawverts'])
        self.drawindexes = np.array(di, '<i4')
        self.surfaces = self.surface_lump(rows)

    # Gold draws world polygons in colour 1, 1, 1 (gl_rsurf.cpp:894-907) and reads texinfo->color (extsurfinfo) only for
    # fog volumes and surface sprites (gl_fogsurf.cpp:849-851, gl_surfsprite.cpp:528-538). ioquake3 draws by-vertex
    # surfaces with CGEN_EXACT_VERTEX (tr_shader.c:2615-2621), so white vertices give Gold's full-bright look there.
    VERTEX_COLOUR = (255, 255, 255, 255)

    def surface_lump(self, rows):
        arr = np.zeros(len(rows), Q.DT['surfaces'])
        for j, (shader, first, ne, fidx, normal, lm) in enumerate(rows):
            a = arr[j]
            a['shaderNum'], a['fogNum'], a['surfaceType'] = shader, -1, Q.MST_PLANAR
            a['firstVert'], a['numVerts'], a['firstIndex'], a['numIndexes'] = first, ne, fidx, (ne - 2) * 3
            if lm is None:
                a['lightmapNum'] = LIGHTMAP_BY_VERTEX       # carried: no luxels -> vertex colours (Step 13)
            else:
                page, lx, ly, lw, lh, _, _ = lm
                a['lightmapNum'], a['lightmapX'], a['lightmapY'] = page, lx, ly
                a['lightmapWidth'], a['lightmapHeight'] = lw, lh
                a['lightmapOrigin'] = self.drawverts[first]['xyz']
            a['lightmapVecs'][2] = normal
        return arr

    # ------------------------------------------------------- tree / collision
    def brush_order(self):
        """-> (brush indices in output order, (first, count) per model): each model's brushes, the ones its node tree's
        leaves list, sorted, model by model; then the brushes no model reaches. ioquake3 takes a submodel's collision
        from a contiguous brush range (cm_load.c:147-157)."""
        b = self.b
        leafs, leafbrushes = b.arr('leafs'), b.arr('leafbrushes')
        owner, order, ranges = {}, [], []
        for m, model in enumerate(b.arr('models')):
            mine = set()
            for leaf in b.tree_leaves(int(model['headnode'])):
                first = int(leafs[leaf]['firstleafbrush'])
                mine.update(int(x) for x in leafbrushes[first:first + int(leafs[leaf]['numleafbrushes'])])
            for brush in sorted(mine):
                if brush in owner:
                    self.fail(BrushOwnership, f'brush {brush} is reached from models {owner[brush]} and {m}')
                owner[brush] = m
            ranges.append((len(order), len(mine)))
            order.extend(sorted(mine))
        order.extend(sorted(set(range(b.count('brushes'))) - set(owner)))
        return order, ranges

    def build_tree(self):
        b = self.b
        planes = b.arr('planes')
        self.planes = np.zeros(len(planes), Q.DT['planes'])
        self.planes['normal'], self.planes['dist'] = planes['normal'], planes['dist']
        nodes = b.arr('nodes')
        self.nodes = np.zeros(len(nodes), Q.DT['nodes'])
        self.nodes['planeNum'], self.nodes['children'] = nodes['planenum'], nodes['children']
        self.nodes['mins'], self.nodes['maxs'] = nodes['mins'], nodes['maxs']
        order, ranges = self.brush_order()
        new_index = np.empty(len(order), np.int64)
        new_index[np.array(order, np.int64)] = np.arange(len(order))
        self.build_leafs(new_index)
        self.build_brushes(order)
        self.build_models(ranges)

    def build_leafs(self, new_index):
        b = self.b
        leafs, leaffaces = b.arr('leafs'), b.arr('leaffaces')
        surfaces, first, count = [], [], []
        for leaf in leafs:
            start = len(surfaces)
            for k in range(int(leaf['numleaffaces'])):
                face = int(leaffaces[int(leaf['firstleafface']) + k])
                if face in self.surface_of_face:
                    surfaces.append(self.surface_of_face[face])
            first.append(start)
            count.append(len(surfaces) - start)
        self.leafsurfaces = np.array(surfaces, '<i4')
        self.leafbrushes = new_index[b.arr('leafbrushes').astype(np.int64)].astype('<i4')
        self.leafs = np.zeros(len(leafs), Q.DT['leafs'])
        self.leafs['cluster'], self.leafs['area'] = leafs['cluster'], MERGED_AREA
        self.leafs['mins'], self.leafs['maxs'] = leafs['mins'], leafs['maxs']
        self.leafs['firstLeafSurface'], self.leafs['numLeafSurfaces'] = first, count
        self.leafs['firstLeafBrush'], self.leafs['numLeafBrushes'] = leafs['firstleafbrush'], leafs['numleafbrushes']

    def build_brushes(self, order):
        brushes, sides = self.b.arr('brushes'), self.b.arr('brushsides')
        self.brushes = np.zeros(len(order), Q.DT['brushes'])
        self.brushsides = np.zeros(len(sides), Q.DT['brushsides'])
        self.brushsides['planeNum'] = sides['planenum']
        assigned = np.zeros(len(sides), bool)
        for p, old in enumerate(order):
            first, count, dk_contents = (int(v) for v in brushes[old])
            contents, dropped, undefined = map_contents(dk_contents)
            self.losses['contents_dropped'].update(dropped)
            self.losses['contents_undefined'] |= undefined
            self.brushes[p] = (first, count, self.shader(CONTENTS_SHADER % contents, 0, contents))
            extra = side_surface_flags(dk_contents)
            for k in range(first, first + count):
                self.brushsides[k]['shaderNum'] = self.side_shader(int(sides[k]['texinfo']), extra)
            assigned[first:first + count] = True
        for k in np.flatnonzero(~assigned):
            self.brushsides[k]['shaderNum'] = self.side_shader(int(sides[k]['texinfo']), 0)

    def build_models(self, ranges):
        models = self.b.arr('models')
        self.models = np.zeros(len(models), Q.DT['models'])
        for i, model in enumerate(models):
            first = int(model['firstface'])
            kept = [self.surface_of_face[f] for f in range(first, first + int(model['numfaces'])) if f in self.surface_of_face]
            self.models[i]['mins'], self.models[i]['maxs'] = model['mins'], model['maxs']
            self.models[i]['firstSurface'], self.models[i]['numSurfaces'] = (kept[0] if kept else 0), len(kept)
            self.models[i]['firstBrush'], self.models[i]['numBrushes'] = ranges[i]

    # ------------------------------------------------------------ visibility
    def build_vis(self):
        """Decompressed PVS rows (CM_DecompressVis semantics) under ioquake3's dvis header: numClusters, clusterBytes
        (cm_load.c:455-477); the PHS rows are dropped."""
        rows = self.b.pvs_rows()
        self.clusters = len(rows)
        self.losses['vis_overruns'] = sum(overruns for _, overruns in rows)
        if not rows:
            self.visibility = b''
            return
        self.visibility = VIS_HEADER.pack(len(rows), (len(rows) + 7) >> 3) + b''.join(row for row, _ in rows)

    # -------------------------------------------------------------- light grid
    @staticmethod
    def worldspawn_value(entities, key):
        """-> the value of `key` in the first entity of the entity text, or None."""
        text = entities.split(b'\0')[0].decode('latin1')
        token, at = dkbsp.com_parse(text, 0)
        return dkbsp.key_value(dkbsp.epairs_for_edict(text, at)[0], key) if token == '{' else None

    @classmethod
    def grid_size(cls, entities):
        """-> the light grid size ioquake3 uses: the first entity's "gridsize" (R_LoadEntities, tr_bsp.c:1759-1762), else
        lightmap.GRID_SIZE."""
        value = cls.worldspawn_value(entities, 'gridsize')
        return lightmap.GRID_SIZE if value is None else tuple(float(v) for v in value.split()[:3])

    def build_lightgrid(self, entities):
        """LUMP_LIGHTGRID sampled like R_LightPoint over the grid R_LoadLightGrid derives from the output world bounds and
        grid size (specs/assets/ASSET-bsp.md, "Light Grid")."""
        world = self.models[0]
        lump = lightmap.grid_lump(lightmap.LightSampler(self.b), world['mins'], world['maxs'], self.grid_size(entities))
        self.stats['grid_points'] = len(lump) // lightmap.GRID_POINT_BYTES
        return lump

    # ---------------------------------------------------------------- report
    def report(self, lumps):
        counts = {name: len(lumps[name]) for name in ('shaders', 'planes', 'nodes', 'leafs', 'leafsurfaces',
                                                       'leafbrushes', 'models', 'brushes', 'brushsides', 'drawverts',
                                                       'drawindexes', 'surfaces')}
        counts.update(lightgrid_points=self.stats['grid_points'], lightmap_faces=self.stats['lm_faces'],
                      lightmap_pages=self.stats['lm_pages'], visibility_clusters=self.clusters,
                      max_surface_verts=int(self.surfaces['numVerts'].max(initial=0)))
        losses = {key: dict(sorted(value.items())) if isinstance(value, collections.Counter) else value
                  for key, value in self.losses.items()}
        losses['areas_merged'] = dict(areas=self.b.count('areas'), areaportals=self.b.count('areaportals'))
        p = self.projection
        projection = dict(mapped=dict(sorted(p.mapped.items())), sounds=p.sounds, live_entities=p.live,
                          dropped={f'{classname}: {reason}': n for (classname, reason), n in sorted(p.dropped.items())},
                          spawn=dict(classname=p.spawn[0], entity=p.spawn[1], origin=p.spawn[2]))
        return dict(map=self.name, source=self.b.source, entities=self.entity_source, counts=dict(sorted(counts.items())),
                    losses=dict(sorted(losses.items())), lightmap_scale=self.lightmap_scale, projection=projection)


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('map', help='map name, e.g. e1m1a')
    ap.add_argument('--data', required=True,
                    help='game directory (zig build -DDK_DATA): loose maps/ files and pak0.pak-pak9.pak, searched like 1.3')
    ap.add_argument('--manifest', required=True,
                    help='manifest.json written by dk_extract.py: WAL sizes (images) and the archive of each map (maps)')
    ap.add_argument('--textures', required=True, help='textures.json written by pack_textures.py: remap and missing names')
    ap.add_argument('--out', required=True, help='IBSP 46 file to write')
    ap.add_argument('--report', required=True, help='JSON report to write: sources, counts and applied losses')
    ap.add_argument('--shaders', required=True, help='JSON to write: the definition of every shader name, read by shadergen.py')
    ap.add_argument('--stock-out', required=True,
                    help='IBSP 46 file to write: the same map with the stock ioquake3 game module projection as its entity '
                         'lump, for engine acceptance only')
    ap.add_argument('--lightmap-scale', type=float, default=lightmap.LIGHTMAP_SCALE,
                    help='luxel sum multiplier (default gl_modulate / 2^r_mapOverBrightBits = %(default)s; for measurement)')
    return ap.parse_args(argv)


def _load_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def run(args):
    """-> (IBSP 46 bytes, stock-projection IBSP 46 bytes, report, shader document) for the command line; raises one of
    FAILURES."""
    manifest, textures = _load_json(args.manifest), _load_json(args.textures)
    key = f'maps/{args.map}.bsp'
    with GameDir(args.data) as game:
        found = game.find(key)
        if found is None:
            raise MapNotFound(f'{key}: not found in {args.data}')
        origin, data = found
        record = manifest['maps'].get(key)
        archive = origin.split(':', 1)[0] if ':' in origin else None
        if record is None or record['pak'] != archive:
            raise InputMismatch(f'{origin}: the manifest names {record["pak"] if record else "no archive"}')
        bsp = dkbsp.Bsp(data, origin)
        text, source = entity_text(bsp.raw('entities'), game.find(f'maps/{args.map}.ent'))
    converter = Converter(bsp, Textures(manifest, textures, key), text, args.map, source, args.lightmap_scale)
    return (*converter.convert(), converter.shader_document())


FAILURES = (ConvertError, dkbsp.BspError, dkbsp.EntityError, dkpak.PakError, entities.EntityTextError,
            entities.UnknownClassname, entities.StockLimitError)


def write(args, data, stock, report, shaders):
    """Writes the outputs of `run` to the paths of the command line."""
    for path in (args.out, args.stock_out, args.report, args.shaders):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    for path, output in ((args.out, data), (args.stock_out, stock)):
        with open(path, 'wb') as f:
            f.write(output)
    for path, document in ((args.report, report), (args.shaders, shaders)):
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(document, f, indent=1, sort_keys=True)
            f.write('\n')


def main(argv=None):
    args = parse_args(argv)
    try:
        data, stock, report, shaders = run(args)
    except FAILURES as error:
        print(f'{PREFIX} FAIL {error}', file=sys.stderr)
        return 1
    write(args, data, stock, report, shaders)
    counts, losses, projection = report['counts'], report['losses'], report['projection']
    print(f"{PREFIX} {args.map}: {counts['surfaces']} surfaces, {counts['brushes']} brushes, {counts['models']} models, "
          f"{counts['visibility_clusters']} clusters, {counts['shaders']} shaders, {len(data)} bytes; entities from "
          f"{report['entities']}; {len(losses['missing_texture'])} missing textures, {losses['nodraw_faces']} nodraw faces; "
          f"stock projection {sum(projection['mapped'].values())} entities, {sum(projection['dropped'].values())} dropped, "
          f"initial spot {projection['spawn']['origin']}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
