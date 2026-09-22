"""Daikatana IBSP version 41 reader with bounds checks (specs/assets/ASSET-bsp.md).

Layout from reference/dk-gold/user/qfiles.h:392-673: Quake II's 19 lumps plus LUMP_EXTSURFINFO and LUMP_PLANEPOLYS, with
a 32-byte dleaf_t. `Bsp` checks the header, every lump's bounds and its record size when it is built; `validate()` checks
every cross-lump index the Gold loaders follow (base/qcommon/cmodel.cpp CM_LoadMap, base/ref_gl/gl_model.cpp
Mod_LoadBrushModel). Every failure is a named BspError giving the source, the lump and the byte offset.

FRD: specs/frds/FRD-012-bsp-v41-to-v46-converter-hardened.md
"""
import struct

import numpy as np

IDENT, VERSION = b'IBSP', 41          # qfiles.h:397-400; Mod_LoadBrushModel accepts only BSPVERSION (gl_model.cpp:1218)
LUMPS = ['entities', 'planes', 'vertexes', 'visibility', 'nodes', 'texinfo', 'faces', 'lighting', 'leafs', 'leaffaces',
         'leafbrushes', 'edges', 'surfedges', 'models', 'brushes', 'brushsides', 'pop', 'areas', 'areaportals',
         'extsurfinfo', 'planepolys']
HEADER_LUMPS = 21                     # qfiles.h:453-474
HEADER = struct.Struct('<4si')
LUMP = struct.Struct('<ii')
HEADER_SIZE = HEADER.size + HEADER_LUMPS * LUMP.size
INT = struct.Struct('<i')
CONTENTS_SOLID = 0x1                  # qfiles.h:523
TEXINFO_SIZE = 76

# numpy views of the on-disk structs (qfiles.h); lumps without an entry are byte streams.
DT = {
    'planes': np.dtype([('normal', '<f4', 3), ('dist', '<f4'), ('type', '<i4')]),
    'vertexes': np.dtype([('xyz', '<f4', 3)]),
    'nodes': np.dtype([('planenum', '<i4'), ('children', '<i4', 2), ('mins', '<i2', 3), ('maxs', '<i2', 3),
                       ('firstface', '<u2'), ('numfaces', '<u2')]),
    'texinfo': np.dtype([('vecs', '<f4', 8), ('flags', '<i4'), ('value', '<i4'), ('texture', 'S32'),
                         ('nexttexinfo', '<i4')]),
    'faces': np.dtype([('planenum', '<u2'), ('side', '<i2'), ('firstedge', '<i4'), ('numedges', '<i2'),
                       ('texinfo', '<i2'), ('styles', 'u1', 4), ('lightofs', '<i4')]),
    'leafs': np.dtype([('contents', '<i4'), ('cluster', '<i2'), ('area', '<i2'), ('mins', '<i2', 3), ('maxs', '<i2', 3),
                       ('firstleafface', '<u2'), ('numleaffaces', '<u2'), ('firstleafbrush', '<u2'),
                       ('numleafbrushes', '<u2'), ('brushnum', '<i4')]),
    'leaffaces': np.dtype('<u2'),
    'leafbrushes': np.dtype('<u2'),
    'edges': np.dtype([('v', '<u2', 2)]),
    'surfedges': np.dtype('<i4'),
    'models': np.dtype([('mins', '<f4', 3), ('maxs', '<f4', 3), ('origin', '<f4', 3), ('headnode', '<i4'),
                        ('firstface', '<i4'), ('numfaces', '<i4')]),
    'brushes': np.dtype([('firstside', '<i4'), ('numsides', '<i4'), ('contents', '<i4')]),
    'brushsides': np.dtype([('planenum', '<u2'), ('texinfo', '<i2')]),
    'areas': np.dtype([('numareaportals', '<i4'), ('firstareaportal', '<i4')]),
    'areaportals': np.dtype([('portalnum', '<i4'), ('otherarea', '<i4')]),
    'extsurfinfo': np.dtype([('color', '<f4', 3)]),
    'planepolys': np.dtype('<i4'),
}
# Lumps the Gold loaders stop on when empty (cmodel.cpp:281-282, 320-321, 377-378, 435-436, 485-486, 529-530;
# gl_model.cpp:1047-1048).
REQUIRED = ('models', 'texinfo', 'nodes', 'leafs', 'planes', 'leafbrushes', 'surfedges')
NO_LIMIT = -(1 << 31)


def record_size(name):
    """Bytes per record of lump `name`; 1 for the byte-stream lumps."""
    return DT[name].itemsize if name in DT else 1


class BspError(ValueError):
    """Malformed BSP data. Names the source, the lump and the byte offset of the fault."""

    def __init__(self, source, lump, offset, detail):
        super().__init__(f'{source}: {lump}: offset {offset}: {detail}')
        self.source, self.lump, self.offset = source, lump, offset


class BadHeader(BspError):
    """The file is shorter than dheader_t, or its ident or version is not IBSP 41."""


class LumpOutOfBounds(BspError):
    """A lump_t reaches before the start or past the end of the file."""


class FunnyLumpSize(BspError):
    """A lump length is not a multiple of its record size (Gold's "funny lump size")."""


class EmptyLump(BspError):
    """A lump the Gold loaders require holds no record."""


class BadIndex(BspError):
    """A record refers outside the lump it indexes, or the node tree reaches a node twice."""


class BadLeaf(BspError):
    """Leaf 0 is not solid, or no other leaf is empty (cmodel.cpp:453-466)."""


class BadVisibility(BspError):
    """The dvis_t header, a row offset, a compressed row or a leaf cluster lies outside the visibility lump."""


class Bsp:
    """One IBSP 41 file. `lumps` maps each lump name to (fileofs, filelen), both inside the file."""

    def __init__(self, data, source='bsp'):
        self.data, self.source = data, source
        if len(data) < HEADER_SIZE:
            raise BadHeader(source, 'header', 0, f'{len(data)} bytes, shorter than the {HEADER_SIZE}-byte dheader_t')
        ident, self.version = HEADER.unpack_from(data)
        if ident != IDENT:
            raise BadHeader(source, 'header', 0, f'ident {ident!r} is not {IDENT!r}')
        if self.version != VERSION:
            raise BadHeader(source, 'header', len(IDENT), f'version {self.version} is not {VERSION}')
        self.lumps = {}
        for i, name in enumerate(LUMPS):
            at = HEADER.size + i * LUMP.size
            fileofs, filelen = LUMP.unpack_from(data, at)
            if fileofs < 0 or filelen < 0 or fileofs + filelen > len(data):
                raise LumpOutOfBounds(source, name, at, f'fileofs {fileofs} filelen {filelen} outside the '
                                                        f'{len(data)}-byte file')
            if filelen % record_size(name):
                raise FunnyLumpSize(source, name, fileofs, f'filelen {filelen} is not a multiple of {record_size(name)}')
            self.lumps[name] = (fileofs, filelen)

    def raw(self, name):
        fileofs, filelen = self.lumps[name]
        return self.data[fileofs:fileofs + filelen]

    def arr(self, name):
        """Lump `name` as a numpy array of its records."""
        return np.frombuffer(self.raw(name), DT[name])

    def count(self, name):
        return self.lumps[name][1] // record_size(name)

    def faces(self):
        return self.arr('faces')

    def texinfo(self):
        """-> list of dicts: vecs (2x4 float), flags, value, texture (lower case), next"""
        return [dict(vecs=tuple(float(v) for v in t['vecs']), flags=int(t['flags']), value=int(t['value']),
                     texture=t['texture'].split(b'\0')[0].decode('latin1').lower(), next=int(t['nexttexinfo']))
                for t in self.arr('texinfo')]

    def entities(self):
        return self.raw('entities').split(b'\0')[0].decode('latin1', 'replace')

    def validate(self):
        """Checks what the Gold loaders index: required lumps, every cross-lump index, the node tree of every model,
        the solid and empty leaves, and the visibility header. Raises EmptyLump, BadIndex, BadLeaf or BadVisibility."""
        for name in REQUIRED:
            if not self.count(name):
                raise EmptyLump(self.source, name, self.lumps[name][0], 'no records')
        n = {name: self.count(name) for name in DT}
        self._check_faces(n)
        self._check_leafs(n)
        self._check_brushes(n)
        self._check_models(n)
        self._check_areas(n)
        self._check_visibility()

    def _check_faces(self, n):
        faces = self.arr('faces')
        self._range('faces', 'planenum', faces['planenum'], n['planes'])
        self._range('faces', 'texinfo', faces['texinfo'], n['texinfo'])     # gl_model.cpp:822-824
        self._span('faces', 'firstedge', faces['firstedge'], faces['numedges'], n['surfedges'])
        self._range('surfedges', 'edge', np.abs(self.arr('surfedges').astype(np.int64)), n['edges'])
        self._range('edges', 'v', self.arr('edges')['v'].max(axis=1, initial=0), n['vertexes'])
        self._range('texinfo', 'nexttexinfo', self.arr('texinfo')['nexttexinfo'], n['texinfo'], NO_LIMIT)
        if n['extsurfinfo'] not in (0, n['texinfo']):                         # one per texinfo (gl_model.cpp:516-527)
            raise BadIndex(self.source, 'extsurfinfo', self.lumps['extsurfinfo'][0],
                           f"{n['extsurfinfo']} records for {n['texinfo']} texinfo")

    def _check_leafs(self, n):
        leafs = self.arr('leafs')
        self._span('leafs', 'firstleafface', leafs['firstleafface'], leafs['numleaffaces'], n['leaffaces'])
        self._span('leafs', 'firstleafbrush', leafs['firstleafbrush'], leafs['numleafbrushes'], n['leafbrushes'])
        if n['areas']:
            self._range('leafs', 'area', leafs['area'], n['areas'])
        self._range('leaffaces', 'face', self.arr('leaffaces'), n['faces'])        # gl_model.cpp:1027-1028
        self._range('leafbrushes', 'brush', self.arr('leafbrushes'), n['brushes'])
        nodes = self.arr('nodes')
        self._range('nodes', 'planenum', nodes['planenum'], n['planes'])
        for side in range(2):
            self._range('nodes', 'children', nodes['children'][:, side], n['nodes'], -n['leafs'])
        if int(leafs[0]['contents']) != CONTENTS_SOLID:
            raise BadLeaf(self.source, 'leafs', self.lumps['leafs'][0], 'leaf 0 is not CONTENTS_SOLID')
        if not (leafs['contents'][1:] == 0).any():
            raise BadLeaf(self.source, 'leafs', self.lumps['leafs'][0], 'no empty leaf')

    def _check_brushes(self, n):
        brushes = self.arr('brushes')
        self._span('brushes', 'firstside', brushes['firstside'], brushes['numsides'], n['brushsides'])
        sides = self.arr('brushsides')
        self._range('brushsides', 'planenum', sides['planenum'], n['planes'])
        self._range('brushsides', 'texinfo', sides['texinfo'], n['texinfo'], -1)   # cmodel.cpp:564-566

    def _check_models(self, n):
        models = self.arr('models')
        self._range('models', 'headnode', models['headnode'], n['nodes'], -n['leafs'])
        self._span('models', 'firstface', models['firstface'], models['numfaces'], n['faces'])
        for model in models:
            self.tree_leaves(int(model['headnode']))

    def _check_areas(self, n):
        areas = self.arr('areas')
        self._span('areas', 'firstareaportal', areas['firstareaportal'], areas['numareaportals'], n['areaportals'])
        self._range('areaportals', 'otherarea', self.arr('areaportals')['otherarea'], n['areas'])

    def _check_visibility(self):
        vis = self.visibility()
        if vis is None:
            return
        clusters = self.arr('leafs')['cluster'].astype(np.int64)
        bad = np.flatnonzero((clusters < -1) | (clusters >= vis[0]))
        if bad.size:
            leaf = int(bad[0])
            raise BadVisibility(self.source, 'leafs', self.lumps['leafs'][0] + leaf * record_size('leafs'),
                                f'leaf {leaf} cluster {int(clusters[leaf])} outside the {vis[0]} clusters')

    def visibility(self):
        """-> (numclusters, bitofs array of shape (numclusters, 2) with PVS and PHS row offsets) of dvis_t
        (qfiles.h:643-653), or None when the lump is empty."""
        lump, base = self.raw('visibility'), self.lumps['visibility'][0]
        if not lump:
            return None
        numclusters = INT.unpack_from(lump)[0] if len(lump) >= INT.size else -1
        header = INT.size * (1 + 2 * max(numclusters, 0))
        if numclusters < 0 or header > len(lump):
            raise BadVisibility(self.source, 'visibility', base,
                                f'numclusters {numclusters} needs a {header}-byte header in a {len(lump)}-byte lump')
        bitofs = np.frombuffer(lump, '<i4', 2 * numclusters, INT.size).reshape(numclusters, 2)
        bad = np.flatnonzero(((bitofs < header) | (bitofs >= len(lump))).any(axis=1))
        if bad.size:
            c = int(bad[0])
            raise BadVisibility(self.source, 'visibility', base + INT.size * (1 + 2 * c),
                                f'cluster {c} row offsets {bitofs[c].tolist()} outside the rows [{header}, {len(lump)})')
        return numclusters, bitofs

    def pvs_rows(self):
        """-> [(decompressed PVS row, overruns)] per cluster, each row (numclusters + 7) >> 3 bytes with one bit per
        cluster; [] when the visibility lump is empty."""
        vis = self.visibility()
        if vis is None:
            return []
        numclusters, bitofs = vis
        lump, base = self.raw('visibility'), self.lumps['visibility'][0]
        return [decompress_vis(lump, int(offset), (numclusters + 7) >> 3, self.source, base) for offset in bitofs[:, 0]]

    def leaf_at(self, point):
        """-> the leaf holding `point`, as CM_PointLeafnum_r walks the tree from node 0 (cmodel.cpp:1057-1089): the front
        child when the point lies on or in front of the node's plane (float arithmetic), else the back child."""
        planes, nodes, node = self.arr('planes'), self.arr('nodes'), 0
        at = np.asarray(point, np.float32)
        while node >= 0:
            plane = planes[int(nodes[node]['planenum'])]
            front = np.float32(np.dot(plane['normal'], at)) - plane['dist'] >= 0
            node = int(nodes[node]['children'][0 if front else 1])
        return -1 - node

    def tree_leaves(self, head):
        """-> the leaf indices under node `head` (a negative head is leaf -1-head), front child first. A node reached
        twice is a BadIndex: the children do not form a tree."""
        nodes, seen, stack, leaves = self.arr('nodes'), set(), [head], []
        while stack:
            node = stack.pop()
            if node < 0:
                leaves.append(-1 - node)
                continue
            if node in seen:
                raise BadIndex(self.source, 'nodes', self.lumps['nodes'][0] + node * record_size('nodes'),
                               f'node {node} is reached twice under head node {head}')
            seen.add(node)
            stack.extend(int(child) for child in reversed(nodes[node]['children']))
        return leaves

    def _range(self, lump, field, values, limit, low=0):
        values = np.asarray(values, np.int64)
        bad = np.flatnonzero((values < low) | (values >= limit))
        if bad.size:
            i = int(bad[0])
            raise BadIndex(self.source, lump, self.lumps[lump][0] + i * record_size(lump),
                           f'{lump}[{i}].{field} {int(values[i])} outside [{low}, {limit})')

    def _span(self, lump, field, first, count, limit):
        first, count = np.asarray(first, np.int64), np.asarray(count, np.int64)
        bad = np.flatnonzero((first < 0) | (count < 0) | (first + count > limit))
        if bad.size:
            i = int(bad[0])
            raise BadIndex(self.source, lump, self.lumps[lump][0] + i * record_size(lump),
                           f'{lump}[{i}].{field} {int(first[i])} + {int(count[i])} outside [0, {limit}]')


def decompress_vis(lump, offset, row, source='bsp', base=0):
    """-> (row bytes, overruns) of the compressed PVS row at `offset`, as CM_DecompressVis builds it (cmodel.cpp:1747-1780):
    a non-zero byte is copied, a zero byte and a count stand for that many zero bytes, and a run passing the row end is
    clamped (Gold's "Vis decompression overrun", counted here). A row needing bytes past the lump is BadVisibility; its
    offset is `base` (the lump's file offset) plus the position in the lump."""
    out, overruns, at = bytearray(), 0, offset
    while len(out) < row:
        code = lump[at] if at < len(lump) else None
        if code is None or (code == 0 and at + 1 >= len(lump)):
            raise BadVisibility(source, 'visibility', base + at, f'the row starting at {offset} needs bytes past the '
                                                                 f'{len(lump)}-byte lump')
        if code:
            out.append(code)
            at += 1
            continue
        run = lump[at + 1]
        at += 2
        if len(out) + run > row:
            run, overruns = row - len(out), overruns + 1
        out += bytes(run)
    return bytes(out), overruns


# Entity string, parsed as the Gold client reads worldspawn keys (cmodel.cpp CM_EpairsForClass, dk_shared.cpp COM_Parse).
MAX_TOKEN_CHARS = 512        # dk_defines.h:65; COM_Parse discards a bare word this long (dk_shared.cpp:618-622)
MAX_EPAIRS = 32              # CM_EpairsForEdict's tpair[32] (cmodel.cpp:101, 125-126)
COMMENT, QUOTE, NUL = '//', '"', '\0'


class EntityError(ValueError):
    """An entity string the Gold parser stops on with Sys_Error or ERR_DROP (cmodel.cpp:121-126, 242-243)."""


def _blank(c):
    """COM_Parse's `c <= ' '` on a signed char: control bytes, space and bytes 0x80-0xFF (dk_shared.cpp:564, 616)."""
    return c <= ' ' or c >= '\x80'


def com_parse(text, at):
    """-> (token, offset after it, or None where COM_Parse sets data to NULL) (COM_Parse, dk_shared.cpp:546)."""
    while True:
        while at < len(text) and text[at] != NUL and _blank(text[at]):
            at += 1
        if at >= len(text) or text[at] == NUL:
            return '', None
        if not text.startswith(COMMENT, at):
            break
        while at < len(text) and text[at] not in '\n' + NUL:
            at += 1
    end = at + 1 if text[at] == QUOTE else at
    while end < len(text) and (text[end] not in QUOTE + NUL if text[at] == QUOTE else not _blank(text[end])):
        end += 1
    if text[at] == QUOTE:
        return text[at + 1:end][:MAX_TOKEN_CHARS], (end + 1 if end < len(text) and text[end] == QUOTE else None)
    return ('' if end - at >= MAX_TOKEN_CHARS else text[at:end]), end


def epairs_for_edict(text, at):
    """-> ([(key, value)], offset after the closing brace) like CM_EpairsForEdict (cmodel.cpp:99-190): keys lose
    trailing spaces, keys starting with `_` are dropped."""
    pairs = []
    while True:
        key, at = com_parse(text, at)
        if key.startswith('}'):
            return pairs, at
        if at is None or len(pairs) >= MAX_EPAIRS:
            raise EntityError('EOF without closing brace' if at is None else f'more than {MAX_EPAIRS} epairs')
        value, at = com_parse(text, at)
        if at is None:
            raise EntityError('EOF without closing brace')
        if not key.rstrip(' ').startswith('_'):
            pairs.append((key.rstrip(' '), value))


def key_value(pairs, key):
    """CM_KeyValue (cmodel.cpp:212-223): the first value whose key matches ignoring case, else None."""
    return next((value for name, value in pairs if name.lower() == key.lower()), None)


def epairs_for_class(text, classname):
    """-> the pairs of the first entity whose classname matches ignoring case (CM_EpairsForClass, cmodel.cpp:230-252).
    An entity without a classname does not match (Gold passes NULL to stricmp)."""
    at = 0
    while at is not None:
        token, at = com_parse(text, at)
        if not token.startswith('{'):
            raise EntityError("expected '{'")
        pairs, at = epairs_for_edict(text, at)
        if (key_value(pairs, 'classname') or '').lower() == classname.lower():
            return pairs
    raise EntityError(f'no entity with classname {classname}')
