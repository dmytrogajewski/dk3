#!/usr/bin/env python3
"""Daikatana DKM models converted into models ioquake3 loads, with a sidecar the game module reads
(specs/assets/ASSET-dkm.md).

`convert(model, skins, archive)` turns one `dkm.Model` into a target model and its sidecar:
- **Target.** An MD3 (md3.py) when every dequantized position fits MD3's 1/64-unit shorts; otherwise a static IQM
  (iqm.py) with float positions when the model has one frame; otherwise `TargetError`.
- **No welding.** Target surface `i` is source surface `i`. Its vertices are the surface's distinct (source vertex,
  texture coordinate) pairs in order of first use by its triangles in source order. Triangles keep source order and
  corner order, and frames keep source order.
- **Split.** A surface over the renderers' vertex limit (`SHADER_MAX_VERTEXES` - 1, tr_model.c:454, tr_model_iqm.c:419)
  continues in parts appended after the last source surface. Triangles naming a surface index past the surface records,
  which Gold loads and never draws, follow in nodraw surfaces named `ORPHAN_SURFACE`.
- **Positions, texture coordinates, normals.** Positions are Gold's dequantized positions (dkm.py). Texture coordinates
  are normalized as the GL command strips store them: `(s + 0.5) / skinwidth`, `(t + 0.5) / skinheight`. Normals are the
  vertnormals.h vectors (dkm.VERTEX_NORMALS), encoded as MD3 latitude and longitude.
- **Shaders** follow the mesh draw (gl_mesh.cpp:356-395). A surface whose name makes it `SRF_NODRAW`
  (gl_model.cpp:1527-1560), or that no strip draws, gets `NODRAW_SHADER`. Any other surface gets the skin its strips name,
  else skin 0, else `NOTEXTURE_SHADER`.
- **Render variants.** An MD3 surface carries its shader four times, `RENDER_VARIANTS`: the skin as it is, then Gold's
  RF_TRANSLUCENT, RF_FULLBRIGHT and both draws of it (gl_mesh.cpp:336-344, :1802-1811), which the cgame selects with
  `refEntity_t.skinNum` 0-3 (tr_mesh.c: `skinNum % numShaders`). The package's `scripts/dkq3-models.shader` defines the three
  scripted variants of every packaged skin (`variant_stanzas`); the plain skin stays ioquake3's implicit shader.
- **Sidecar.** Source header, frame names, the sequence table as `dk_GetAnimSequences` fills `frameData_t`
  (dk_model.cpp:248-311), surfaces with Gold's flags and hardpoint triangles (hierarchy.cpp:112-128, gl_model.cpp:47-110),
  skins, and the index map from every source triangle and target vertex back to source indexes.
- **Losses.** Every property the target does not keep is a loss entry with its reason.

FRD: specs/frds/FRD-017-dkm-models-with-preserved-surfaces-vertices-and-sequences.md
"""
import argparse
import collections
import concurrent.futures
import json
import math
import multiprocessing
import os
import resource
import sys
from dataclasses import dataclass

import numpy as np

import dk2q3
import dk_extract
import dkimg
import dkm
import dkpak
import iqm
import md3
import pk3
import shadergen

MD3, IQM = 'md3', 'iqm'
# Gold's MAX_FRAMES (qfiles.h:81). qfiles.h declares MD3_MAX_FRAMES 1024, but no ioquake3 source outside qfiles.h reads it,
# and the frame number travels in 16 bits (code/qcommon/msg.c:796); the corpus maximum is 1394 (ASSET-dkm.md).
FRAME_LIMIT = 2048
SURFACE_VERTEX_LIMIT = iqm.SHADER_MAX_VERTEXES - 1
NODRAW_SHADER = 'models/dkq3/nodraw'
NOTEXTURE_SHADER = 'models/dkq3/notexture'
# Family 17 of specs/ports/PORT-render-effects.md: the suffixes of a skin's four render variants, in `skinNum` order --
# bit 0 RF_TRANSLUCENT, bit 1 RF_FULLBRIGHT. The cgame's DK_MODEL_VARIANT_* (src/cgame/dk_local.h) names the same order.
RENDER_VARIANTS = ('', '@alpha', '@bright', '@alphabright')
# The target surface of triangles whose surface index names no surface record.
ORPHAN_SURFACE = 'dkq3_orphan_{}'
SIDECAR_FORMAT, SIDECAR_VERSION = 'dkq3-dkm', 1
# md3Frame_t.name holds 15 bytes and its terminator.
FRAME_NAME_BYTES = md3.FRAME_NAME_LEN - 1
# MD3 normals: latitude (high byte) and longitude (low byte) in 1/256 turns (code/renderergl1/tr_surface.c:647-659).
NORMAL_STEPS = 256
UP = (0.0, 0.0, 1.0)
RENDER_FLAGS = (dkm.SRF_TRANS33 | dkm.SRF_TRANS66 | dkm.SRF_ALPHA | dkm.SRF_GLOW | dkm.SRF_COLORBLEND | dkm.SRF_FULLBRIGHT |
                dkm.SRF_ENVMAP | dkm.SRF_TEXENVMAP_ADD | dkm.SRF_TEXENVMAP_MULT)
# frameData_t defaults dk_GetAnimSequences sets for every sequence (dk_model.cpp:303-306).
SEQUENCE_FLAGS, NO_SOUND_FRAME = 0, -1
# Mod_ResolveHardpoint(mod, "s_head", "hp_head") (gl_model.cpp:1693).
HEAD_SURFACE, HEAD_HARDPOINT = 's_head', 'hp_head'
# The surface names R_GetModelHardpoint is asked for in Gold's client: `hp_gun`, `hp_head`, `hr_muzzle`, `hr_muzzle1`...
# (base/client/cl_ents.cpp:1520, :2060, :2096; base/client/cl_tent.cpp:2387). A hardpoint IS a named surface
# (hierarchy.cpp:65-73), so these are the surfaces that become MD3 tags.
HARDPOINT_PREFIXES = ('hp_', 'hr_')
# The surface names Gold's client asks R_GetModelHardpoint for that carry neither prefix: the sunflare's flame stands at the
# view weapon's `fire` surface (base/client/cl_tent.cpp:4223, TrackEntFX_Fire; w_sflare.dkm and we_sunprj.dkm carry one).
# Retain the authored flag attachment for dk3's multiplayer presentation.
HARDPOINT_NAMES = ('fire', 'ctf_flag')
# md3Tag_t carries a rotation as well as a position. R_GetModelHardpoint returns a position only - it never builds an
# orientation, and every caller gives the child the PARENT's angles (cl_ents.cpp:2096-2113) - so the tag's rotation is the
# identity and the attachment takes its angles from the parent, as Gold does.
IDENTITY_AXIS = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)


class TargetError(ValueError):
    """A model no target keeps: out of MD3's range with more than one frame, or a layout the target rejects."""


@dataclass(frozen=True)
class Skin:
    """A model skin name and its resolution: the shader and packaged image, and the archive entry decoded (None when absent)."""
    name: str
    shader: str
    image: str
    source: str


@dataclass(frozen=True)
class Converted:
    target: str
    entry: str
    sidecar_entry: str
    data: bytes
    sidecar: dict
    losses: list
    counts: dict


@dataclass
class Part:
    """One target surface: the source surface, its pairs in first-use order, triangles as pair indexes, source triangles."""
    surface: int
    pairs: dict
    triangles: list
    sources: list


def gold_flags(name, flags):
    """The flags Mod_LoadAliasModel adds from a surface name (gl_model.cpp:1527-1560), case-sensitive like strstr."""
    if 'nd_' in name:
        flags |= dkm.SRF_NODRAW
    for token, flag in (('chrome', dkm.SRF_ENVMAP), ('shinya', dkm.SRF_TEXENVMAP_ADD), ('shinym', dkm.SRF_TEXENVMAP_MULT),
                        ('shiny', dkm.SRF_TEXENVMAP_ADD), ('remove', dkm.SRF_NODRAW)):
        if token in name:
            flags |= flag
            break
    for token, flag in (('33', dkm.SRF_TRANS33), ('66', dkm.SRF_TRANS66)):
        if token in name:
            flags |= flag
            break
    for token, flag in (('head', dkm.SRF_STATICSKIN), ('hp_', dkm.SRF_NODRAW), ('bright', dkm.SRF_FULLBRIGHT)):
        if token in name:
            flags |= flag
    return flags


def is_record(model, index):
    """Whether a triangle's surface index names one of the model's surface records."""
    return 0 <= index < len(model.surfaces)


def parts(model):
    """-> the target surfaces: part 0 of every source surface in order, the further parts of split surfaces, then every part
    of each surface index past the records, in index order."""
    by_surface = {i: [Part(i, {}, [], [])] for i in range(len(model.surfaces))}
    for t, triangle in enumerate(model.triangles):
        found = by_surface.setdefault(triangle.surface, [Part(triangle.surface, {}, [], [])])
        corners = tuple(zip(triangle.xyz, triangle.st_frames[0]))
        part = found[-1]
        if len(part.pairs) + len(set(corners) - set(part.pairs)) > SURFACE_VERTEX_LIMIT:
            part = Part(triangle.surface, {}, [], [])
            found.append(part)
        part.triangles.append(tuple(part.pairs.setdefault(corner, len(part.pairs)) for corner in corners))
        part.sources.append(t)
    records = range(len(model.surfaces))
    orphans = sorted(index for index in by_surface if not is_record(model, index))
    return ([by_surface[i][0] for i in records] + [part for i in records for part in by_surface[i][1:]] +
            [part for i in orphans for part in by_surface[i]])


def surface_name(model, index):
    """The target name of a surface index: its record's name, or `ORPHAN_SURFACE` past the records."""
    return model.surfaces[index].name if is_record(model, index) else ORPHAN_SURFACE.format(index)


def encode_normal(vector):
    """-> the MD3 normal of a unit vector: latitude atan2(y, x) and longitude acos(z) in 1/256 turns."""
    x, y, z = (float(c) for c in vector)
    lat = round(math.atan2(y, x) * NORMAL_STEPS / (2 * math.pi)) % NORMAL_STEPS
    lng = round(math.acos(max(-1.0, min(1.0, z))) * NORMAL_STEPS / (2 * math.pi)) % NORMAL_STEPS
    return lat << 8 | lng


def decode_normal(normal):
    """-> the unit vector R_LoadMD3's renderer draws for an MD3 normal (tr_surface.c:647-659)."""
    lat, lng = (normal >> 8) * 2 * math.pi / NORMAL_STEPS, (normal & 0xFF) * 2 * math.pi / NORMAL_STEPS
    return (math.cos(lat) * math.sin(lng), math.sin(lat) * math.sin(lng), math.cos(lng))


# Every light normal index a byte can hold: the vertnormals.h vectors, and UP past the table.
VECTORS = np.array([dkm.VERTEX_NORMALS[i] if i < dkm.NUM_NORMALS else UP for i in range(NORMAL_STEPS)], np.float32)
ENCODED = np.array([encode_normal(v) for v in VECTORS], np.int64)


def _loss(reason, detail):
    return dict(reason=reason, detail=detail)


def _normalized(model, part):
    """-> the texture coordinates of a part's pairs, normalized by the surface's skin size; 0 where the size is 0 or the part
    has no surface record."""
    if not is_record(model, part.surface):
        return [(0.0, 0.0)] * len(part.pairs)
    surface = model.surfaces[part.surface]
    return [((model.st[st][0] + 0.5) / surface.skinwidth if surface.skinwidth > 0 else 0.0,
             (model.st[st][1] + 0.5) / surface.skinheight if surface.skinheight > 0 else 0.0) for _, st in part.pairs]


def _strip_skins(model):
    """-> {surface index: skin indexes its strips name, in strip order}."""
    found = {}
    for strip in model.strips:
        skins = found.setdefault(strip.surface, [])
        if strip.skin not in skins:
            skins.append(strip.skin)
    return found


def _shader(skins, flags, drawn):
    """The mesh draw's choice (gl_mesh.cpp:361-395): nodraw, the strips' skin, skin 0, then r_notexture."""
    if flags & dkm.SRF_NODRAW or drawn is None:
        return NODRAW_SHADER
    for index in (drawn, 0):
        if 0 <= index < len(skins) and skins[index].shader:
            return skins[index].shader
    return NOTEXTURE_SHADER


def _first_triangle(model, index):
    """R_GetModelHardpoint's triangle (hierarchy.cpp:112-128): the first triangle of the surface, else 0."""
    return next((t for t, triangle in enumerate(model.triangles) if triangle.surface == index), 0)


def _surfaces(model, skins, targets):
    strip_skins, records = _strip_skins(model), []
    for index, surface in enumerate(model.surfaces):
        flags = gold_flags(surface.name, surface.flags)
        drawn = strip_skins.get(index, [None])[0]
        records.append(dict(name=surface.name, flags=surface.flags, gold_flags=flags, skinindex=surface.skinindex,
                            skinwidth=surface.skinwidth, skinheight=surface.skinheight, num_uvframes=surface.num_uvframes,
                            hardpoint_triangle=_first_triangle(model, index), drawn_skin=drawn, shader=_shader(skins, flags, drawn),
                            target_surfaces=[j for j, part in enumerate(targets) if part.surface == index]))
    return records


def _hardpoint_surfaces(model):
    """-> [(surface index, name)] of the surfaces a hardpoint lookup names, in source order, at most MD3_MAX_TAGS of them
    (the corpus maximum is 4 per model, ASSET-dkm.md)."""
    found = [(i, s.name) for i, s in enumerate(model.surfaces)
             if s.name.lower().startswith(HARDPOINT_PREFIXES) or s.name.lower() in HARDPOINT_NAMES]
    return found[:md3.MAX_TAGS]


def _hardpoint_tags(model, positions):
    """-> one `md3.Tag` list per frame: every hardpoint surface at R_GetModelHardpoint's position for that frame.

    Gold takes the centroid of the FIRST triangle of the named surface (hierarchy.cpp:114-128) from the frame's
    dequantized vertices, and returns

        hardPt = ent.origin + temp.x * forward + temp.y * (-right) + temp.z * up

    (hierarchy.cpp:152-159, :202-213), where `temp` is that centroid in model space and `-right` is Quake's `left`. That
    is exactly how ioquake3 places a tag: `R_LerpTag` returns the model-space origin and the caller composes it with the
    parent's axis, which `AnglesToAxis` fills with (forward, left, up). So the model-space centroid stored here, attached
    through `trap_R_LerpTag`, lands where Gold's hardpoint lands, and ioquake3's own frame interpolation stands in for
    Gold's `ent.backlerp` blend of the two frames (hierarchy.cpp:134-142).

    `render_scale` is deliberately not applied, because Gold's scaling block is commented out (hierarchy.cpp:191-201)."""
    surfaces = _hardpoint_surfaces(model)
    triangles = [(name, _first_triangle(model, index)) for index, name in surfaces]
    tags = []
    for frame in range(len(model.frames)):
        per_frame = []
        for name, triangle in triangles:
            corners = positions[frame][list(model.triangles[triangle].xyz)].astype(np.float64)
            per_frame.append(md3.Tag(name, tuple(corners.mean(axis=0).tolist()), IDENTITY_AXIS))
        tags.append(per_frame)
    return tags


def _resolved_hardpoints(model):
    """Mod_ResolveHardpoint (gl_model.cpp:47-110): the first surfaces named s_head and hp_head, ignoring case, and the
    hardpoint surface's first triangle, else 0."""
    names = [surface.name.lower() for surface in model.surfaces]
    if HEAD_SURFACE not in names or HEAD_HARDPOINT not in names:
        return []
    return [dict(surface=HEAD_SURFACE, hardpoint=HEAD_HARDPOINT, triangle=_first_triangle(model, names.index(HEAD_HARDPOINT)))]


def _sequences(model):
    table = model.sequences
    frame_data = [dict(animation_name=s.name, first=s.first, last=s.last, flags=SEQUENCE_FLAGS, soundframe1=NO_SOUND_FRAME,
                       soundframe2=NO_SOUND_FRAME) for s in table.table]
    return dict(count=table.count, offset=table.offset, valid=table.valid, frame_data=frame_data)


def _part_shader(model, surfaces, index):
    return surfaces[index]['shader'] if is_record(model, index) else NODRAW_SHADER


def render_variants(shader):
    """-> the four shaders of an MD3 surface, in `RENDER_VARIANTS` order. Nodraw and notexture have no variants: a hidden
    surface stays hidden and a missing skin stays the notexture image whatever the entity's render flags."""
    if shader in (NODRAW_SHADER, NOTEXTURE_SHADER):
        return (shader,) * len(RENDER_VARIANTS)
    return tuple(shader + suffix for suffix in RENDER_VARIANTS)


def variant_stanzas(shader, image, alpha_channel):
    """-> the three scripted render variants of one model skin, as Gold's R_DrawAliasModel draws a model under its render
    flags (base/ref_gl/gl_mesh.cpp):

    - every model is drawn with the alpha test GL_GREATER 0 and depth writes on (:1760-1761, GLSTATE_PRESET1), with face
      culling off for a skin that has an alpha channel (:398-405, gl_image.cpp:1476-1502);
    - RF_TRANSLUCENT blends at the entity's alpha under the renderer's standing GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA
      (:336-344, gl_rmisc.cpp:171), the texture's own alpha multiplied in by GL_MODULATE (:1961): `blendFunc blend`,
      `alphaGen entity`, `alphaFunc GT0`, `depthWrite` (an ioquake3 blended stage writes no depth unless told to);
    - RF_FULLBRIGHT lights every vertex at 1 (:1802-1811): `rgbGen identityLighting`, where the plain draw is ioquake3's
      implicit `rgbGen lightingDiffuse`, Gold's R_LightPoint shade."""
    cull = '\tcull disable\n' if alpha_channel else ''
    blended = '\t\tblendFunc blend\n\t\talphaFunc GT0\n\t\tdepthWrite\n'
    stanzas = []
    for suffix, stage in (('@alpha', f'{blended}\t\trgbGen lightingDiffuse\n\t\talphaGen entity\n'),
                          ('@bright', '\t\trgbGen identityLighting\n'),
                          ('@alphabright', f'{blended}\t\trgbGen identityLighting\n\t\talphaGen entity\n')):
        stanzas.append(f'{shader}{suffix}\n{{\n{cull}\t{{\n\t\tmap {image}\n{stage}\t}}\n}}\n')
    return ''.join(stanzas)


def png_has_alpha(data):
    """Whether PNG bytes carry an alpha channel: colour type 4 or 6 in IHDR. The skin decoder writes RGBA only for an image
    with a texel below opaque (`_decode_skin`, dk_extract.OPAQUE), which is Gold's `has_alpha`."""
    return len(data) >= 26 and data[:8] == b'\x89PNG\r\n\x1a\n' and data[25] in (4, 6)


def model_shader_script(skins):
    """-> scripts/dkq3-models.shader: the nodraw shader, then the render variants of every (shader, image, has alpha) of
    `skins`, sorted by shader, each once."""
    text, seen = [SHADER_SCRIPT_TEXT], {}
    for shader, image, alpha_channel in sorted(set(skins)):
        if seen.setdefault(shader, (image, alpha_channel)) != (image, alpha_channel):
            raise ValueError(f'{shader}: two images for one skin shader ({seen[shader][0]}, {image})')
        text.append(variant_stanzas(shader, image, alpha_channel))
    return ''.join(text)


def _orphan_surfaces(model, targets):
    """-> each surface index past the records: its triangle count and target surfaces."""
    indexes = sorted({part.surface for part in targets if not is_record(model, part.surface)})
    return [dict(index=i, triangles=sum(len(p.sources) for p in targets if p.surface == i),
                 target_surfaces=[j for j, p in enumerate(targets) if p.surface == i]) for i in indexes]


def _index_map(model, targets):
    triangles = [None] * len(model.triangles)
    for j, part in enumerate(targets):
        for local, source in enumerate(part.sources):
            triangles[source] = [j, local]
    return dict(triangles=triangles, surfaces=[dict(source_surface=part.surface, vertices=[list(pair) for pair in part.pairs])
                                               for part in targets])


def _positions(model):
    """-> (frames, num_xyz, 3) float32 positions of every frame."""
    return np.stack([frame.positions for frame in model.frames])


def _fits_md3(positions):
    scaled = np.round(positions.astype(np.float64) * md3.XYZ_SCALE)
    return bool(((scaled >= md3.SHORT_MIN) & (scaled <= md3.SHORT_MAX)).all())


def _md3(model, entry, targets, surfaces, positions, normals):
    frames = []
    for frame, points in zip(model.frames, positions):
        mins, maxs = points.min(axis=0).astype(np.float64), points.max(axis=0).astype(np.float64)
        radius = float(np.linalg.norm(np.maximum(np.abs(mins), np.abs(maxs))))
        frames.append(md3.Frame(tuple(mins.tolist()), tuple(maxs.tolist()), (0.0, 0.0, 0.0), radius,
                                frame.name.encode('latin1')[:FRAME_NAME_BYTES].decode('latin1')))
    encoded = []
    for part in targets:
        xyz = [pair[0] for pair in part.pairs]
        points, codes = positions[:, xyz, :].astype(np.float64).tolist(), ENCODED[normals[:, xyz]].tolist()
        vertices = tuple(tuple((*p, n) for p, n in zip(frame_points, frame_codes)) for frame_points, frame_codes in zip(points, codes))
        encoded.append(md3.Surface(surface_name(model, part.surface), render_variants(_part_shader(model, surfaces, part.surface)), tuple(part.triangles),
                                   tuple(_normalized(model, part)), vertices))
    return md3.encode(entry, frames, _hardpoint_tags(model, positions), encoded, max_frames=FRAME_LIMIT)


def _iqm(model, targets, surfaces, positions, normals):
    meshes = []
    for part in targets:
        xyz = [pair[0] for pair in part.pairs]
        meshes.append(iqm.Mesh(surface_name(model, part.surface), _part_shader(model, surfaces, part.surface),
                               tuple(map(tuple, positions[0][xyz].tolist())), tuple(map(tuple, VECTORS[normals[0][xyz]].tolist())),
                               tuple(_normalized(model, part)), tuple(part.triangles)))
    try:
        return iqm.encode(meshes)
    except iqm.IqmError as error:
        raise TargetError(f'{model.name}: {error}') from error


def _losses(model, target, targets, surfaces, positions, normals):
    losses, used = [], sorted({xyz for triangle in model.triangles for xyz in triangle.xyz})
    long_names = [frame.name for frame in model.frames if len(frame.name.encode('latin1')) > FRAME_NAME_BYTES]
    if target == MD3 and long_names:
        losses.append(_loss('frame_name_truncated', f'{len(long_names)} frame names over {FRAME_NAME_BYTES} bytes cut in '
                                                    f'md3Frame_t (first {long_names[0]}); the sidecar keeps them whole'))
    zero = [s.name for i, s in enumerate(model.surfaces)
            if (s.skinwidth <= 0 or s.skinheight <= 0) and any(t.surface == i for t in model.triangles)]
    if zero:
        losses.append(_loss('skin_size_zero', f"surfaces {', '.join(zero)} have a skin size of 0: the strips hold inf; "
                                              'texture coordinates 0'))
    past = int((normals[:, used] >= dkm.NUM_NORMALS).sum())
    if past:
        losses.append(_loss('normal_index_out_of_range', f'{past} vertex records name a light normal past the {dkm.NUM_NORMALS} '
                                                         'vertnormals.h entries, which Gold reads out of bounds; converted as up'))
    if not model.sequences.valid:
        losses.append(_loss('sequence_header_invalid', f'num_sequences {model.sequences.count} at ofs_sequences '
                                                       f'{model.sequences.offset} is not a table inside the file; no frame data'))
    if target == MD3:
        points = positions[:, used, :].astype(np.float64)
        error = float(np.abs(np.round(points * md3.XYZ_SCALE) / md3.XYZ_SCALE - points).max())
        losses.append(_loss('position_quantization', f'MD3 stores positions in 1/{md3.XYZ_SCALE} units; largest error {error:.6f}'))
        indexes = sorted(set(normals[:, used].ravel().tolist()))
        angle = max(math.degrees(math.acos(max(-1.0, min(1.0, float(np.dot(VECTORS[i], decode_normal(int(ENCODED[i])))))))) for i in indexes)
        losses.append(_loss('normal_encoding', f'normals as 8-bit latitude and longitude; largest angle error {angle:.3f} degrees'))
    flagged = [f"{s['name']} 0x{s['gold_flags'] & RENDER_FLAGS:x}" for s in surfaces if s['gold_flags'] & RENDER_FLAGS]
    if flagged:
        losses.append(_loss('render_flags', f"surface flags without a converted shader effect (Step 30): {', '.join(flagged)}"))
    split = sorted({part.surface for part in targets[len(model.surfaces):] if is_record(model, part.surface)})
    if split:
        losses.append(_loss('surface_split', ', '.join(f"{model.surfaces[i].name} into {sum(p.surface == i for p in targets)} "
                                                       f'parts over {SURFACE_VERTEX_LIMIT} vertices' for i in split)))
    orphans = _orphan_surfaces(model, targets)
    if orphans:
        losses.append(_loss('orphan_triangles', f"{sum(o['triangles'] for o in orphans)} triangles name surface indexes "
                                                f"{[o['index'] for o in orphans]} past the {len(model.surfaces)} surface records; Gold loads "
                                                'them unchecked and draws none (gl_model.cpp:1587-1606, gl_mesh.cpp:356-395); kept in nodraw surfaces'))
    many = sum(1 for triangle in model.triangles if len(triangle.st_frames) > 1)
    if many:
        losses.append(_loss('uv_frames_dropped', f'{many} triangles with more than one uv frame keep the first'))
    return losses


def convert(model, skins, archive):
    """-> the `Converted` model of a `dkm.Model`; `skins` resolves every model skin in order, `archive` names the source.
    Raises TargetError."""
    if len(skins) != len(model.skins):
        raise TargetError(f'{model.name}: {len(skins)} skin resolutions for {len(model.skins)} skins')
    targets, positions = parts(model), _positions(model)
    normals = np.stack([frame.normals for frame in model.frames]).astype(np.int64)
    surfaces = _surfaces(model, skins, targets)
    target = MD3 if _fits_md3(positions) else IQM
    if target == IQM and len(model.frames) != 1:
        raise TargetError(f'{model.name}: positions pass the MD3 range and {len(model.frames)} frames need vertex animation')
    entry = f'{model.name}.{target}'
    data = _md3(model, entry, targets, surfaces, positions, normals) if target == MD3 else _iqm(model, targets, surfaces, positions, normals)
    sidecar = dict(format=SIDECAR_FORMAT, version=SIDECAR_VERSION, model=model.name,
                   source=dict(archive=archive, dkm_version=model.version, origin=list(model.origin), header=model.header),
                   target=dict(format=target, entry=entry, frame_limit=FRAME_LIMIT),
                   frames=[frame.name for frame in model.frames], sequences=_sequences(model),
                   skins=[dict(name=s.name, shader=s.shader, image=s.image, source=s.source) for s in skins],
                   surfaces=surfaces, orphan_surfaces=_orphan_surfaces(model, targets), resolved_hardpoints=_resolved_hardpoints(model),
                   hardpoint_tags=[dict(surface=name, triangle=_first_triangle(model, index))
                                   for index, name in _hardpoint_surfaces(model)],
                   index_map=_index_map(model, targets))
    counts = dict(frames=len(model.frames), surfaces=len(model.surfaces), target_surfaces=len(targets),
                  vertices=sum(len(part.pairs) for part in targets), triangles=len(model.triangles), bytes=len(data))
    return Converted(target, entry, f'{model.name}.json', data, sidecar, _losses(model, target, targets, surfaces, positions, normals), counts)


def sidecar_bytes(sidecar):
    """The sidecar as sorted, compact, ASCII JSON and a newline: equal sidecars give equal bytes."""
    return json.dumps(sidecar, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode('ascii') + b'\n'


# ---------------------------------------------------------------------------------------------------------------------
# Corpus driver: `zig build assets-models`.

PREFIX = 'dkm2md3:'
MAX_WORKERS = 12                       # spec R7: parallel corpus work uses at most 12 workers
DKM_SUFFIX = '.dkm'
PAK5 = 'pak5.pak'
SHADER_SCRIPT = 'scripts/dkq3-models.shader'
# The nodraw shader has no stage, so the renderer draws nothing for it and prints nothing (tr_shader.c:2373-2377).
SHADER_SCRIPT_TEXT = f'{NODRAW_SHADER}\n{{\n\tsurfaceparm nodraw\n}}\n'
NOTEXTURE_IMAGE = NOTEXTURE_SHADER + '.tga'
CONVERTED, OVERRIDDEN, FAILED = 'converted', 'overridden', 'failed'
STEP6, DECODED, NOTEXTURE, MISSING = 'step6', 'decoded', 'notexture', 'missing'
RESOLUTIONS = (STEP6, DECODED, NOTEXTURE, MISSING)
MODELS_DIR, IMAGES_DIR, SCRIPTS_DIR = 'models', 'images', 'scripts'
TGA, WAL = '.tga', '.wal'
# R_FindImage loads these extensions and returns NULL for any other name (gl_image.cpp:1770-1793).
LOADABLE = ('.pcx', '.bmp', '.wal', '.tga')
PNG = '.png'

_worker = {}


def search_order(game, pak5):
    """-> [(archive name, dkpak.Pak)] in the 1.3 search order after loose files: pak5.pak (from pak5.zip, searched first as
    assets-images orders it) when given, then the game directory's pak9..pak0 (dk2q3.GameDir)."""
    return ([(PAK5, pak5)] if pak5 is not None else []) + list(game.paks)


def discover(root, archives, suffix=DKM_SUFFIX):
    """-> {name: [origin, ...]}: every loose file below `root` ending in `suffix` (`.dkm` models by default, `.sp2` sprites for
    sp2shaders.py), then every archive entry, in search order."""
    found = {}
    for directory, _, files in sorted(os.walk(root)):
        for name in sorted(files):
            relative = os.path.relpath(os.path.join(directory, name), root).replace(os.sep, '/')
            if relative.lower().endswith(suffix):
                found.setdefault(relative.lower(), []).append(relative)
    for pak_name, pak in archives:
        for entry in sorted(pak.entries):
            if entry.endswith(suffix):
                found.setdefault(entry, []).append(pak_name)
    return dict(sorted(found.items()))


def _start_worker(data, pak5, manifest, images, out_dir):
    """Pool initializer: each worker opens the game directory, the archives and the Step 6 manifest once."""
    game = dk2q3.GameDir(data)
    pak = dkpak.Pak(pak5) if pak5 else None
    with open(manifest, encoding='utf-8') as f:
        records = json.load(f)['images']
    _worker.update(game=game, archives=dict(search_order(game, pak)), images=records, images_dir=images, out_dir=out_dir)


def _read_entry(origin, name):
    if origin in _worker['archives']:
        return _worker['archives'][origin].read(name)
    with open(os.path.join(_worker['game'].root, origin), 'rb') as f:
        return f.read()


def _write(path, data):
    """Writes `data` atomically, so workers writing the same skin image never leave a partial file."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary = f'{path}.{os.getpid()}'
    with open(temporary, 'wb') as f:
        f.write(data)
    os.replace(temporary, path)


def _decode_skin(entry, pak_name, variant):
    """Decodes Gold's skin source with the Step 6 decoder (dk_extract._decode) into <out>/images/<variant>.png."""
    status, images, _, _ = dk_extract._decode(entry, _worker['archives'][pak_name].read(entry), dk_extract.SKIN, [])
    if status != dk_extract.IMAGE:
        return None
    image = images[0][1]
    path = os.path.join(_worker['out_dir'], IMAGES_DIR, variant + PNG)
    if not os.path.exists(path):
        temporary = f'{path}.{os.getpid()}.png'
        os.makedirs(os.path.dirname(path), exist_ok=True)
        dkimg.write_png(temporary, image if (image[..., 3] < dk_extract.OPAQUE).any() else image[..., :3])
        os.replace(temporary, path)
    return variant + PNG


def resolve_skin(name):
    """RegisterSkin (gl_image.cpp:1863-1900): a `.tga` name loads the TGA; any other name loads `<base>.wal`, then the
    name itself. -> (Skin, resolution): the Step 6 image when Step 6 chose that source, a decoded `<key>@<ext>` image
    otherwise, notexture for a source Gold shows as r_notexture, or no shader when no archive holds a loadable source."""
    key, ext = os.path.splitext(name.replace('\\', '/').lower())
    record = _worker['images'].get(key)
    candidates = [key + TGA] if ext == TGA else [key + WAL, key + ext]
    listed = {source['entry']: source for source in (record or {}).get('sources', [])}
    entry = next((c for c in candidates if c in listed and os.path.splitext(c)[1] in LOADABLE and listed[c]['status'] != FAILED), None)
    if entry is None:
        return Skin(name, None, None, None), MISSING
    source = f"{listed[entry]['pak']}:{entry}"
    if listed[entry]['status'] != dk_extract.IMAGE:
        return Skin(name, NOTEXTURE_SHADER, NOTEXTURE_IMAGE, source), NOTEXTURE
    if entry == record['src'] and record['status'] == dk_extract.IMAGE:
        image = record['files'][0]['file']
        return Skin(name, os.path.splitext(image)[0], image, source), STEP6
    variant = f'{key}@{os.path.splitext(entry)[1][1:]}'
    image = _decode_skin(entry, listed[entry]['pak'], variant)
    if image is None:
        return Skin(name, NOTEXTURE_SHADER, NOTEXTURE_IMAGE, source), NOTEXTURE
    return Skin(name, variant, image, source), DECODED


def convert_entry(job):
    """Worker: converts one archive copy of a model and writes it below <out>/models/<origin>/ -> its report row."""
    name, origin = job
    row = dict(name=name, archive=origin)
    try:
        model = dkm.read(_read_entry(origin, name), name)
        resolved = [resolve_skin(skin) for skin in model.skins]
        converted = convert(model, tuple(skin for skin, _ in resolved), origin)
    except Exception as error:  # every per-model error is reported by name; none may escape the worker unreported
        return dict(row, status=FAILED, error=f'{type(error).__name__}: {error}')
    outputs = dict(model=f'{origin}/{converted.entry}', sidecar=f'{origin}/{converted.sidecar_entry}')
    _write(os.path.join(_worker['out_dir'], MODELS_DIR, outputs['model']), converted.data)
    _write(os.path.join(_worker['out_dir'], MODELS_DIR, outputs['sidecar']), sidecar_bytes(converted.sidecar))
    return dict(row, status=CONVERTED, dkm_version=model.version, target=converted.target, entry=converted.entry,
                sidecar=converted.sidecar_entry, outputs=outputs,
                counts=converted.counts, losses=converted.losses,
                skins=[dict(name=s.name, shader=s.shader, image=s.image, source=s.source, resolution=r) for s, r in resolved])


def run_jobs(args, jobs):
    """-> the rows of `jobs` from `args.workers` spawned processes, in job order; a dead worker fails every unreturned job."""
    context = multiprocessing.get_context('spawn')
    initargs = (args.data, args.pak5, args.manifest, args.images, args.out_dir)
    rows = []
    with concurrent.futures.ProcessPoolExecutor(args.workers, mp_context=context, initializer=_start_worker, initargs=initargs) as pool:
        try:
            rows.extend(pool.map(convert_entry, jobs, chunksize=1))
        except concurrent.futures.process.BrokenProcessPool as error:
            rows.extend(dict(name=n, archive=o, status=FAILED, error=f'a worker process died: {error}') for n, o in jobs[len(rows):])
    return rows


def table(copies, rows):
    """Marks the first copy of each model converted and the later copies overridden, with their archives."""
    for row in rows:
        origins = copies[row['name']]
        if row['status'] != FAILED:
            row['status'] = CONVERTED if row['archive'] == origins[0] else OVERRIDDEN
        if row['archive'] == origins[0]:
            row['overrides'] = origins[1:]
        else:
            row['overridden_by'] = origins[0]
    return rows


def summary_line(row):
    if row['status'] == FAILED:
        return f"{PREFIX} {row['name']} ({row['archive']}): failed: {row['error']}"
    c = row['counts']
    skins = collections.Counter(skin['resolution'] for skin in row['skins'])
    losses = ', '.join(loss['reason'] for loss in row['losses']) or 'none'
    return (f"{PREFIX} {row['name']} ({row['archive']}): {row['status']} {row['target']}, {c['frames']} frames, {c['surfaces']} surfaces "
            f"({c['target_surfaces']} target), {c['vertices']} vertices, {c['triangles']} triangles, {c['bytes']} bytes; skins "
            + ', '.join(f'{r} {skins[r]}' for r in RESOLUTIONS) + f'; losses {losses}')


def document(rows):
    status = collections.Counter(row['status'] for row in rows)
    targets = collections.Counter(row['target'] for row in rows if row['status'] != FAILED)
    losses = collections.Counter(loss['reason'] for row in rows if row['status'] == CONVERTED for loss in row['losses'])
    return dict(entries=len(rows), packaged=status[CONVERTED], converted=status[CONVERTED] + status[OVERRIDDEN],
                overridden=status[OVERRIDDEN], failed=sorted({row['name'] for row in rows if row['status'] == FAILED}),
                targets={target: targets[target] for target in (MD3, IQM)}, losses=dict(sorted(losses.items())), models=rows)


def summary(report):
    lines = [summary_line(row) for row in report['models']]
    t = report['targets']
    lines.append(f"{PREFIX} losses " + (', '.join(f'{r} {n}' for r, n in report['losses'].items()) or 'none'))
    skins = collections.Counter(s['resolution'] for row in report['models'] if row['status'] == CONVERTED for s in row['skins'])
    lines.append(f"{PREFIX} skins " + ', '.join(f'{r} {skins[r]}' for r in RESOLUTIONS))
    lines.append(f"{PREFIX} total: {report['entries']} entries, {report['packaged']} models packaged, {report['converted']} converted "
                 f"({report['overridden']} overridden), {len(report['failed'])} failed; {MD3} {t[MD3]}, {IQM} {t[IQM]}")
    return lines


def package(args, rows):
    """Writes the pk3: every packaged model and sidecar, their skin images, notexture and the shader script (the nodraw
    shader and every packaged skin's render variants), sorted by name."""
    entries = {NOTEXTURE_IMAGE: os.path.join(args.out_dir, IMAGES_DIR, NOTEXTURE_IMAGE),
               SHADER_SCRIPT: os.path.join(args.out_dir, SHADER_SCRIPT)}
    _write(entries[NOTEXTURE_IMAGE], shadergen.tga_bytes(shadergen.notexture_image()))
    variants = set()
    for row in (row for row in rows if row['status'] == CONVERTED):
        entries[row['entry']] = os.path.join(args.out_dir, MODELS_DIR, row['outputs']['model'])
        entries[row['sidecar']] = os.path.join(args.out_dir, MODELS_DIR, row['outputs']['sidecar'])
        with open(entries[row['sidecar']], encoding='utf-8') as stream:
            metadata = json.load(stream)
        animation = ['dk3_animation 1', str(len(metadata['frames']))]
        for sequence in metadata['sequences']['frame_data']:
            name = sequence['animation_name']
            if any(c in name for c in ('"', '\n', '\r')):
                raise ValueError(f"{row['name']}: invalid animation name {name!r}")
            animation.append(f'"{name}" {sequence["first"]} {sequence["last"]} 10')
        animation_path = entries[row['sidecar']] + '.anim'
        _write(animation_path, ('\n'.join(animation) + '\n').encode('utf-8'))
        entries[row['name'] + '.anim'] = animation_path

        for skin in row['skins']:
            if skin['resolution'] in (STEP6, DECODED):
                base = args.images if skin['resolution'] == STEP6 else os.path.join(args.out_dir, IMAGES_DIR)
                entries[skin['image']] = os.path.join(base, skin['image'])
                with open(entries[skin['image']], 'rb') as f:
                    variants.add((skin['shader'], skin['image'], png_has_alpha(f.read(32))))
    _write(entries[SHADER_SCRIPT], model_shader_script(variants).encode('ascii'))
    pk3.write_files(args.pk3, sorted(entries.items()))


def _rss_mib(who):
    """Peak resident set of this process or of its largest finished child, MiB (ru_maxrss is KiB on Linux)."""
    return resource.getrusage(who).ru_maxrss // 1024


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--data', required=True, help='game directory (zig build -DDK_DATA): loose files and pak0.pak-pak9.pak')
    ap.add_argument('--pak5', help='pak5.pak extracted from pak5.zip, searched before the numbered archives')
    ap.add_argument('--manifest', required=True, help='manifest.json written by dk_extract.py')
    ap.add_argument('--images', required=True, help='images directory written by dk_extract.py')
    ap.add_argument('--out-dir', required=True, help='directory to write: models/<origin>/ per archive copy, images/, scripts/')
    ap.add_argument('--pk3', required=True, help='pk3 to write: every packaged model, sidecar, skin image and the shader script')
    ap.add_argument('--report', required=True, help='JSON report to write')
    ap.add_argument('--summary', required=True, help='text report to write: the lines printed on stdout')
    ap.add_argument('--workers', type=int, required=True, help=f'worker processes, 1 to {MAX_WORKERS} (spec R7)')
    args = ap.parse_args(argv)
    if not 1 <= args.workers <= MAX_WORKERS:
        ap.error(f'--workers must be 1 to {MAX_WORKERS} (spec R7), not {args.workers}')
    return args


def main(argv=None):
    args = parse_args(argv)
    with dk2q3.GameDir(args.data) as game:
        pak5 = dkpak.Pak(args.pak5) if args.pak5 else None
        copies = discover(game.root, search_order(game, pak5))
    rows = table(copies, run_jobs(args, [(name, origin) for name, origins in copies.items() for origin in origins]))
    print(f'{PREFIX} {args.workers} workers, peak RSS main {_rss_mib(resource.RUSAGE_SELF)} MiB, largest worker '
          f'{_rss_mib(resource.RUSAGE_CHILDREN)} MiB', file=sys.stderr)
    report = document(rows)
    lines = summary(report)
    for path in (args.report, args.summary, args.pk3):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(args.report, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=1, sort_keys=True)
        f.write('\n')
    with open(args.summary, 'w', encoding='utf-8') as f:
        f.write(''.join(line + '\n' for line in lines))
    print('\n'.join(lines))
    for row in (row for row in rows if row['status'] == FAILED):
        print(f"{PREFIX} FAIL {row['name']} ({row['archive']}): {row['error']}", file=sys.stderr)
    if report['failed']:
        return 1
    package(args, rows)
    return 0


if __name__ == '__main__':
    sys.exit(main())
