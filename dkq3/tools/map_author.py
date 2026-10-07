# SPDX-License-Identifier: GPL-2.0-or-later
"""Export an authored Blender scene into a Quake 3 `.map` document.

Run this inside Blender (`blender -b scene.blend --python map_author.py -- ...`);
the `.blend` file is the level's authored source and stays editable in the
Blender GUI. The scene contract is deliberately small so that a hand-modelled
room and a scripted one export identically. One Blender unit is one Quake unit.

* Every mesh object contributes brushes. Each loose part must be closed,
  planar-faced and convex, and becomes exactly one brush. Blender UVs are
  ignored because Quake projects textures from world space (Radiant's classic
  axis-aligned form), which keeps neighbouring brushes continuous. Face
  windings are re-derived from the shell, so a flipped part still exports
  outward-facing planes.
* A material carries `dk3.shader` (its path below `textures/`, without that
  prefix), `dk3.repeat` (world units one texture repeat spans), `dk3.texwidth`
  (the texture width q3map2 measures, so the emitted scale does not depend on
  which images happen to be open here) and optionally `dk3.shift` (`[s, t]`)
  and `dk3.rotate` (degrees).
* An object with `dk3.entity` becomes that entity class; `dk3.keys` holds a JSON
  object of extra epairs. A mesh's brushes become the entity's submodel, so a
  hazard volume is a cube named with `trigger_hurt` and nothing else.
* An empty with `dk3.entity` becomes a point entity at its origin. `angle`
  comes from `dk3.angle` or, when absent, the empty's own Z rotation.
* The scene's `dk3.world` JSON object supplies worldspawn epairs. `message`
  there is also the title the multiplayer map catalog advertises.

Non-manifold, concave or self-intersecting parts are reported by object and part
number instead of being quietly dropped, because a brush q3map2 discards is a
hole in the level that only appears after a full compile.
"""
from __future__ import annotations

import argparse
import bmesh
import json
from math import degrees
from pathlib import Path
import sys

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import quake_map

DEFAULT_REPEAT = 128.0     # Radiant: one texture at scale 1 covers as many units as it has pixels
DEFAULT_TEXWIDTH = 512.0   # the generated material set ships at 512 px
PLANE_KEY = 1.0 / 64.0     # how closely two polygons must agree to share a plane


def prop(owner, name, default=None):
    value = owner.get(name, default)
    return list(value) if hasattr(value, 'to_list') else value


def entity_keys(owner, raw):
    if not raw:
        return {}
    try:
        keys = json.loads(raw) if isinstance(raw, str) else dict(raw)
        return {str(key): str(value) for key, value in keys.items()}
    except (ValueError, TypeError) as error:
        raise quake_map.BrushError('%s: entity keys are not a JSON object (%s)' % (owner, error))


def material_style(material, detail=False):
    """-> FaceStyle for one material, scaled to the shader size q3map2 measures."""
    shader = prop(material, 'dk3.shader')
    if not shader:
        raise quake_map.BrushError('%s: material has no dk3.shader' % material.name)
    repeat = float(prop(material, 'dk3.repeat', DEFAULT_REPEAT))
    width = float(prop(material, 'dk3.texwidth', DEFAULT_TEXWIDTH))
    if repeat <= 0 or width <= 0:
        raise quake_map.BrushError('%s: dk3.repeat and dk3.texwidth must be positive' % material.name)
    shift = prop(material, 'dk3.shift', (0.0, 0.0)) or (0.0, 0.0)
    scale = repeat / width
    return quake_map.FaceStyle(shader=str(shader), shift=(float(shift[0]), float(shift[1])),
                               rotate=float(prop(material, 'dk3.rotate', 0.0) or 0.0),
                               scale=(scale, scale),
                               detail=bool(detail or prop(material, 'dk3.detail', False)),
                               solid=bool(prop(material, 'dk3.solid', True)))


def visible(object):
    return not object.name.startswith('_') and not object.hide_get() and not object.hide_render


def scene_geometry(object, mesh):
    """-> (world points, [(vertex-index ring, material index)]).

    The mesh is copied into bmesh, put in world space and its normals are
    recalculated from the shell, which is what makes an author who modelled a
    part inside-out still reach a brush with outward-facing planes.
    """
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.transform(object.matrix_world)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    index = {vert: position for position, vert in enumerate(bm.verts)}
    points = [tuple(vert.co) for vert in bm.verts]
    rings = [(tuple(index[vert] for vert in face.verts), face.material_index)
             for face in bm.faces if len(face.verts) >= 3]
    bm.free()
    return points, rings


def loose_parts(rings):
    """Group rings so that each group is one connected loose part of the mesh."""
    parent = {}

    def find(vertex):
        parent.setdefault(vertex, vertex)
        while parent[vertex] != vertex:
            parent[vertex] = parent[parent[vertex]]
            vertex = parent[vertex]
        return vertex

    for ring, _ in rings:
        for other in ring[1:]:
            root, sibling = find(ring[0]), find(other)
            if root != sibling:
                parent[root] = sibling
    groups = {}
    for index, (ring, _) in enumerate(rings):
        groups.setdefault(find(ring[0]), []).append(index)
    return [[rings[index] for index in members] for members in groups.values()]


def plane_key(points, ring):
    corners = [points[index] for index in ring]
    normal = quake_map.plane_from_points(corners)[0]
    if normal is None:
        return None
    quantize = lambda value: round(value / PLANE_KEY) * PLANE_KEY
    return (quantize(normal[0]), quantize(normal[1]), quantize(normal[2]),
            quantize(sum(a * b for a, b in zip(corners[0], normal))))


def merge_coplanar(points, rings, source):
    """Join the polygons that share a plane: one brush plane may exist only once.

    -> [(ring of vertex indices, contributing polygon indices)] per plane.
    """
    groups = {}
    for index, ring in enumerate(rings):
        key = plane_key(points, ring)
        if key is None:
            raise quake_map.BrushError('%s: polygon %s is degenerate' % (source, ring))
        groups.setdefault(key, []).append(index)
    merged = []
    for key, members in groups.items():
        boundary = {}
        for index in members:
            ring = rings[index]
            for position, start in enumerate(ring):
                edge = (start, ring[(position + 1) % len(ring)])
                if tuple(reversed(edge)) in boundary:
                    del boundary[tuple(reversed(edge))]
                else:
                    boundary[edge] = index
        if not boundary:
            raise quake_map.BrushError('%s: plane %s closes on itself' % (source, key))
        outgoing = {}
        for start, end in boundary:
            if start in outgoing:
                raise quake_map.BrushError('%s: plane %s branches, the merged face is not one loop'
                                           % (source, key))
            outgoing[start] = end
        first = next(iter(outgoing))
        ring, cursor = [first], outgoing[first]
        while cursor != first:
            ring.append(cursor)
            cursor = outgoing.get(cursor)
            if cursor is None or len(ring) > len(outgoing):
                raise quake_map.BrushError('%s: plane %s does not close into one loop' % (source, key))
        merged.append((tuple(ring), members))
    return merged


def ring_is_convex(points, ring, normal):
    origin = points[ring[0]]
    sign = 0.0
    for position in range(len(ring)):
        a = points[ring[(position - 1) % len(ring)]]
        b = points[ring[position]]
        c = points[ring[(position + 1) % len(ring)]]
        turn = quake_map.dot(quake_map.cross(quake_map.sub(b, a), quake_map.sub(c, b)), normal)
        if turn and sign and turn * sign < 0:
            return False
        sign = sign or turn
    return True


def brushes_for_mesh(object, mesh):
    """-> (brushes, defects) for one mesh object."""
    points, rings = scene_geometry(object, mesh)
    slots = [slot.material for slot in object.material_slots]
    # `map_blender.decorate` marks an object, not a material, and the exporter
    # used to read the flag off the material alone: every one of japanDM's 4876
    # exported faces came out with a content-flags word of `0`, so not one brush
    # was ever detail and `decorate`'s promise of "no VIS splits" was fiction.
    detail = bool(prop(object, 'dk3.detail', False))
    brushes, defects = [], []
    for part, rings in enumerate(loose_parts(rings)):
        source = '%s part %d' % (object.name, part)
        try:
            merged = merge_coplanar(points, [ring for ring, _ in rings], source)
        except quake_map.BrushError as error:
            defects.append(str(error))
            continue
        styles = []
        for ring, member_indices in merged:
            chosen = {rings[index][1] for index in member_indices}
            if len(chosen) > 1:
                defects.append('%s: one plane carries %d materials; split the object'
                               % (source, len(chosen)))
                break
            index = chosen.pop()
            if index >= len(slots) or slots[index] is None:
                defects.append('%s: face %s has no material' % (source, ring))
                break
            normal = quake_map.plane_from_points([points[position] for position in ring])[0]
            if not ring_is_convex(points, ring, normal):
                defects.append('%s: plane at %s merged into a concave face; separate the coplanar parts'
                               % (source, tuple(round(value) for value in points[ring[0]])))
                break
            try:
                styles.append(material_style(slots[index], detail=detail))
            except quake_map.BrushError as error:
                defects.append(str(error))
                break
        else:
            try:
                brushes.append(quake_map.brush_from_mesh(
                    points, [ring for ring, _ in merged],
                    lambda index, normal: styles[index], source))
            except quake_map.BrushError as error:
                defects.append(str(error))
    return brushes, defects


# The player box is -15..15 in x/y and -24..32 in z around the entity origin
# (q_shared.h PLAYER_MINS/PLAYER_MAXS), so an origin rests 24 units above the
# floor and its eyes sit at feet + 22 (bg_misc.cc PERSPECTIVE_HEIGHT) -- two
# units *below* the origin. Auditing with the wrong offset reports every spawn as
# floating and tests sightlines at a height no player ever occupies.
# Auditing offsets for a spawn, in world units.
EYE_Z = -2.0               # eye height relative to the spawn origin
FEET_Z = -24.0             # the floor under a spawn, relative to its origin
HEAD_Z = 24.0              # a probe inside the box, safely under its 32-unit ceiling
GROUND_TOLERANCE = 4.0     # how far the floor may sit below that footprint


def audit(document, solid_shaders):
    """-> multiplayer geometry findings, before a 20-minute compile says nothing.

    A spawn inside a wall, a pickup over a shaft, a spawn that can already see
    another spawn and a lamp buried in a slab are all real defects that a BSP
    compile cannot report -- and the last one it reports wrongly. q3map2 cannot
    place an entity origin whose point falls in a solid leaf, and the message it
    has for that is `Entity 5, Brush 0: Entity leaked`, naming the light's own
    point-brush: a map with no hole in it at all reads as a leak. Check lamps
    here, where the name of the lamp is known.
    """
    findings = {}
    solid, spawns, pickups, lamps = [], [], {}, {}
    for entity in document.entities:
        if entity.classname == 'worldspawn':
            solid = [brush for brush in entity.brushes
                     if any(face.style.solid for face in brush.faces)]
            continue
        origin = entity.keys.get('origin')
        if not origin:
            continue
        position = tuple(float(value) for value in origin.split())
        if entity.classname.startswith(('info_player_', 'pickup_', 'teleport_destination')):
            spawns.append((entity.source, position))
        if entity.classname.startswith(('weapon_', 'ammo_', 'item_')):
            pickups.setdefault(entity.classname, []).append((entity.source, position))
        if entity.classname == 'light':
            lamps.setdefault('light', []).append((entity.source, position))
    problems, embedded, floating, unsupported = [], [], [], []
    for source, position in spawns + [(name, place) for group in pickups.values() for name, place in group]:
        if any(quake_map.inside(brush, position) for brush in solid):
            embedded.append(source)
    buried_lights = []
    for source, position in lamps['light']:
        # Not `inside`: a lamp centred exactly on a stair's riser plane is buried
        # to the compiler and clear to that test, so the lamp must prove it stands
        # a margin outside every solid instead.
        if not all(quake_map.outside(brush, position) for brush in solid):
            buried_lights.append('%s at %s' % (source, ', '.join('%g' % value
                                                                 for value in position)))
    for source, position in spawns:
        feet = position[2] + FEET_Z
        floor = quake_map.ground_below(solid, position)
        floating = floor is None or feet - floor > GROUND_TOLERANCE
        buried = floor is not None and floor > feet + GROUND_TOLERANCE
        if floating or buried:
            unsupported.append('%s (floor %s, feet %.0f)'
                               % (source, 'none' if floor is None else '%.0f' % floor, feet))
        head = (position[0], position[1], position[2] + HEAD_Z)
        if any(quake_map.inside(brush, head) for brush in solid):
            embedded.append('%s (headroom)' % source)
    seen = []
    eyes = [(source, (position[0], position[1], position[2] + EYE_Z)) for source, position in spawns]
    for index, (first, first_eye) in enumerate(eyes):
        for second, second_eye in eyes[index + 1:]:
            if not any(quake_map.blocks(brush, first_eye, second_eye) for brush in solid):
                seen.append('%s<->%s' % (first, second))
    if embedded:
        problems.append('entities inside solid geometry: %s' % ', '.join(sorted(set(embedded))))
    if unsupported:
        problems.append('spawns without a floor: %s' % ', '.join(unsupported))
    if buried_lights:
        problems.append('lights inside solid geometry (q3map2 calls this a leak): %s'
                        % ', '.join(sorted(buried_lights)))
    return dict(findings=dict(spawns=len(spawns), pickups={name: len(group) for name, group in sorted(pickups.items())},
                              spawn_pairs_without_cover=len(seen), open_lines=sorted(seen)[:12],
                              solid_brushes=len(solid), lights=len(lamps['light'])),
                problems=problems)


def export(out, report_path):
    scene = bpy.context.scene
    world_keys = {'classname': 'worldspawn', 'message': Path(out).stem}
    world_keys.update(entity_keys('scene', prop(scene, 'dk3.world', {})))
    document = quake_map.MapDoc(entities=[quake_map.Entity(keys=world_keys, source='worldspawn')])
    classes, defects, sides_per_shader = {}, set(), {}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for object in bpy.context.view_layer.objects:
        if not visible(object):
            continue
        classname = prop(object, 'dk3.entity')
        entity = None
        if classname:
            keys = entity_keys(object.name, prop(object, 'dk3.keys', ''))
            keys['classname'] = str(classname)
            origin = prop(object, 'dk3.origin')
            position = list(origin) if origin else [float(coordinate) for coordinate in object.location]
            keys.setdefault('origin', ' '.join('%.3f' % value for value in position))
            if prop(object, 'dk3.angle') is not None:
                keys.setdefault('angle', str(prop(object, 'dk3.angle')))
            elif object.rotation_euler.z:
                keys.setdefault('angle', '%.0f' % degrees(object.rotation_euler.z))
            entity = quake_map.Entity(keys=keys, source=object.name)
            document.entities.append(entity)
        if object.type != 'MESH':
            if entity is None:
                defects.append('%s: %s objects need dk3.entity' % (object.name, object.type.lower()))
            continue
        evaluated = object.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh() if evaluated else None
        if mesh is None or not mesh.polygons:
            defects.append('%s: mesh has no faces' % object.name)
            continue
        brushes, problems = brushes_for_mesh(object, mesh)
        evaluated.to_mesh_clear()
        defects.update(problems)
        if not brushes:
            if not problems:
                defects.append('%s: no closed convex part to export' % object.name)
            continue
        for brush in brushes:
            for shader in brush.shaders():
                sides_per_shader[shader] = sides_per_shader.get(shader, 0) + len(brush.faces)
        (entity or document.entities[0]).brushes.extend(brushes)
        name = entity.classname if entity else 'worldspawn'
        classes[name] = classes.get(name, 0) + len(brushes)
    problems = document.validate()
    defects.update(problems)
    written = quake_map.write_map(document, out) if not problems else ''
    mins, maxs = document.bounds()
    findings = audit(document, sides_per_shader) if not problems else dict(findings={}, problems=[])
    defects.update(findings['problems'])
    summary = dict(map=Path(out).stem, title=document.entities[0].keys.get('message', ''),
                   entities=len(document.entities),
                   brushes=len(document.brushes()),
                   faces=sum(len(brush.faces) for brush in document.brushes()),
                   bounds=[list(mins), list(maxs)], classes=dict(sorted(classes.items())),
                   shaders=dict(sorted(sides_per_shader.items())), multiplayer=findings['findings'],
                   defects=sorted(defects))
    Path(report_path).write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print('map-author: %d entities, %d brushes, %d faces, bounds %.0f %.0f %.0f -> %.0f %.0f %.0f'
          % (summary['entities'], summary['brushes'], summary['faces'], *mins, *maxs))
    print('map-author: %d spawns, %d pickups, %d spawn pairs without cover'
          % (findings['findings'].get('spawns', 0),
             sum(findings['findings'].get('pickups', {}).values()),
             findings['findings'].get('spawn_pairs_without_cover', 0)))
    for line in summary['defects']:
        print('map-author: defect: %s' % line)
    if problems:
        print('map-author: %d defects; %s not written' % (len(problems), out))
        return 1
    print('map-author: wrote %s (%d bytes)' % (out, len(written.encode())))
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--blend', type=Path, help='scene to open; defaults to the running session')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    arguments = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if arguments.blend:
        bpy.ops.wm.open_mainfile(filepath=str(arguments.blend.resolve()))
    sys.exit(export(arguments.out, arguments.report))
