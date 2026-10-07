# SPDX-License-Identifier: GPL-2.0-or-later
"""Blender-side authoring helpers, shared by every map's `build_blender.py`.

Run inside Blender. Everything here builds **convex closed shells**, because one
closed convex part exports as exactly one Quake brush (`map_author.py`), and
Quake levels are assembled from brushes rather than from one dense mesh. A wall
is therefore a box, a column is a prism over a convex polygon and a ramp is a
turned box: the level reads as the set of solids it will compile into.

The scene contract is the exporter's (`map_author.py`): materials carry
`dk3.shader`/`dk3.repeat`/`dk3.texwidth`, objects carry `dk3.entity`/`dk3.keys`,
and the scene carries `dk3.world`. One Blender unit is one Quake unit.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))


def new_scene():
    """Start from an empty scene, so a rebuilt file never inherits factory cubes."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'NONE'
    return scene


def world(scene, **keys):
    """Set the worldspawn epairs the exporter emits for entity 0."""
    scene['dk3.world'] = json.dumps({key: str(value) for key, value in keys.items()})
    return scene


def material(table, name, **override):
    """-> the Blender material for one `materials.py` entry, carrying its dk3 keys."""
    if name not in table:
        raise KeyError('%s is not in the material table' % name)
    entry = dict(table[name], **override)
    shader = name.rpartition('/')[2] if '/' not in name else name
    key = 'dk3_%s' % name.replace('/', '_')
    made = bpy.data.materials.get(key) or bpy.data.materials.new(key)
    made.use_nodes = True
    made['dk3.shader'] = name
    made['dk3.repeat'] = float(entry.get('repeat', 128.0))
    made['dk3.texwidth'] = float(entry.get('texwidth', 512.0))
    if entry.get('shift'):
        made['dk3.shift'] = [float(value) for value in entry['shift']]
    if entry.get('rotate'):
        made['dk3.rotate'] = float(entry['rotate'])
    # A trigger, a hint volume and a sky shell are not painted occluders, and the
    # scene audit must not read them as walls: it would call a spawn inside a
    # trigger "embedded" and every hazard volume a piece of cover.
    solid = entry.get('solid', entry.get('kind') not in ('trigger', 'hint', 'sky'))
    made['dk3.solid'] = bool(solid)
    return made


def _link(object):
    bpy.context.collection.objects.link(object)
    return object


def _shell(name, points, polygons, mat, collection=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(point) for point in points], [],
                     [list(polygon) for polygon in polygons])
    if mesh.validate():
        raise ValueError('%s: Blender repaired non-manifold geometry' % name)
    mesh.update()
    object = bpy.data.objects.new(name, mesh)
    object.data.materials.append(mat)
    return _link(object)


def _convex(ring):
    """-> whether an XY ring turns the same way at every corner."""
    sign = 0.0
    count = len(ring)
    for index in range(count):
        (ax, ay), (bx, by), (cx, cy) = (ring[(index - 1) % count], ring[index], ring[(index + 1) % count])
        turn = (bx - ax) * (cy - by) - (by - ay) * (cx - bx)
        if turn and sign and turn * sign < 0:
            return False
        sign = sign or turn
    return sign != 0.0


def prism(name, ring, z0, z1, mat, source=None):
    """A vertical prism over a convex XY ring: walls, columns and platforms."""
    ring = [(float(x), float(y)) for x, y in ring]
    if len(ring) < 3 or not _convex(ring):
        raise ValueError('%s: the prism ring must be a convex polygon of 3+ corners' % name)
    if abs(z1 - z0) < 1.0:
        raise ValueError('%s: a prism needs at least a unit of height' % name)
    count = len(ring)
    points = [(x, y, z0) for x, y in ring] + [(x, y, z1) for x, y in ring]
    polygons = [tuple(reversed(range(count))), tuple(range(count, 2 * count))]
    polygons += [(index, (index + 1) % count, (index + 1) % count + count, index + count)
                 for index in range(count)]
    object = _shell(source or name, points, polygons, mat)
    object.name = name
    return object


def paint(object, faces):
    """Give individual faces of a shell their own material.

    `faces` maps an index in the primitive's own polygon order to a material:
    for `prism`, and therefore for `box`, 0 is the cap at `z0`, 1 is the cap at
    `z1`, and 2.. are the walls in ring order.

    The exporter already writes one shader per brush *plane*, so a roof slab may
    honestly wear gravel on top and concrete on the soffit.  Handing one material
    to the whole object is what made every ceiling in japanDM display the
    material of the surface above it, which is the single thing the owner saw and
    called "textures used the wrong way".
    """
    # Append first, index second.  `materials.clear()` rewrites every polygon's
    # `material_index` back to 0, so painting and then rebuilding the slots -- the
    # first attempt here -- leaves the object exactly as it started and says
    # nothing about it.  Appending only keeps slot 0 where the built shell
    # already points.
    slots = list(object.data.materials)
    for material in faces.values():
        if material not in slots:
            slots.append(material)
            object.data.materials.append(material)
    for position, polygon in enumerate(object.data.polygons):
        material = faces.get(position)
        if material is not None:
            polygon.material_index = slots.index(material)
    return object


def box(name, mins, maxs, mat, source=None):
    """An axis-aligned solid between two corners."""
    (x0, y0, z0), (x1, y1, z1) = (Vector(mins), Vector(maxs))
    if min(x1 - x0, y1 - y0, z1 - z0) < 1.0:
        raise ValueError('%s: a box needs at least a unit in every axis; thin faces collapse' % name)
    return prism(name, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1, mat, source=source)


def plate(name, mins, maxs, mat, source=None):
    """A horizontal slab: the thinnest box the pipeline still accepts."""
    return box(name, mins, maxs, mat, source=source)


def turned(name, centre, size, angles, mat, source=None):
    """A box placed by centre, size and roll/pitch/yaw in degrees.

    Rotation happens on the object, not on the mesh: the exporter reads
    `matrix_world`, so the brush planes come out of the turned corners exactly,
    and the part stays convex however it is oriented. Euler 'XYZ' means the yaw
    is applied last, which is what a ramp wants (turn to face the run, then tilt).
    """
    for selected in bpy.context.selected_objects:
        selected.select_set(False)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=[float(value) for value in centre])
    object = bpy.context.active_object
    object.name = name
    object.scale = [abs(float(value)) for value in size]
    object.rotation_euler = Euler([math.radians(float(value)) for value in angles], 'XYZ')
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    object.data.materials.append(mat)
    return object


def ramp(name, start, end, width, thickness, mat, source=None):
    """An inclined slab from `start` to `end` (both at the walking surface).

    The slab is turned about its own axis, so its underside stays parallel to
    its top and a player can run onto it from either end.
    """
    start, end = Vector(start), Vector(end)
    run = end - start
    length = math.hypot(run.x, run.y, run.z)
    if length < 8.0:
        raise ValueError('%s: a ramp shorter than 8 units is a step, not a ramp' % name)
    yaw = math.degrees(math.atan2(run.y, run.x))
    pitch = -math.degrees(math.atan2(run.z, math.hypot(run.x, run.y)))
    centre = (start + end) / 2.0
    centre.z -= thickness / 2.0            # `start`/`end` describe the walking surface
    return turned(name, centre, (length, width, thickness), (0.0, pitch, yaw), mat, source=source)


def stairs(name, start, end, width, steps, mat, source=None):
    """Ascending treads as separate brushes along one horizontal axis.

    Keeping each tread its own brush rather than one stepped mesh is what lets
    q3map2 (and the bot compiler) see every landing as a real surface.
    """
    start, end = Vector(start), Vector(end)
    along_x = abs(end.x - start.x) >= abs(end.y - start.y)
    if abs(end.x - start.x) > 1.0 and abs(end.y - start.y) > 1.0:
        raise ValueError('%s: stairs run along one axis; use a ramp to turn a corner' % name)
    if steps < 2:
        raise ValueError('%s: stairs need at least two treads' % name)
    rise = (end.z - start.z) / float(steps)
    made = []
    for index in range(steps):
        low = start.z + rise * index
        first, last = (start, end) if along_x else (start.y, end.y)
        near = first + (last - first) * index / float(steps)
        far = first + (last - first) * (index + 1) / float(steps)
        across = (end.y if along_x else end.x)
        if along_x:
            mins, maxs = (min(near, far), across - width / 2.0, low), (max(near, far), across + width / 2.0, low + rise)
        else:
            mins, maxs = (across - width / 2.0, min(near, far), low), (across + width / 2.0, max(near, far), low + rise)
        made.append(box('%s_%02d' % (name, index), mins, maxs, mat, source=source or name))
    return made


def polygon_ring(centre, radius, sides=8, rotation=0.0, squash=1.0):
    """A convex ring for columns and pads; `squash` makes it an ellipse."""
    cx, cy = centre
    return [(cx + radius * math.cos(rotation + index * 2.0 * math.pi / sides),
             cy + radius * squash * math.sin(rotation + index * 2.0 * math.pi / sides))
            for index in range(sides)]


def entity(name, classname, location, keys=None, angle=None):
    """A point entity: spawns, lights, pickups and hazard markers."""
    object = bpy.data.objects.new(name, None)
    object['dk3.entity'] = classname
    if keys:
        object['dk3.keys'] = json.dumps({str(key): str(value) for key, value in keys.items()})
    if angle is not None:
        object['dk3.angle'] = str(angle)
    object.location = [float(value) for value in location]
    return _link(object)


def brush_entity(name, classname, mins, maxs, mat, keys=None, angle=None):
    """A brush entity: one trigger or mover volume, textured by `mat`."""
    made = box(name, mins, maxs, mat)
    made['dk3.entity'] = classname
    if keys:
        made['dk3.keys'] = json.dumps({str(key): str(value) for key, value in keys.items()})
    if angle is not None:
        made['dk3.angle'] = str(angle)
    return made


def decorate(object):
    """Mark a brush as detail: no VIS splits, no shadowing, cheap decoration."""
    object['dk3.detail'] = True
    return object


def hide(*objects):
    """Keep reference geometry in the file without exporting it."""
    for object in objects:
        object.hide_set(True)
        object.hide_render = True
    return objects


def save(path):
    bpy.ops.wm.save_as_mainfile(filepath=str(Path(path).resolve()))
    return Path(path)


def table(path):
    """-> the `MATERIALS` dict of a map's `materials.py`, importable from Blender."""
    import importlib.util
    spec = importlib.util.spec_from_file_location('dk3_map_material_table', str(Path(path).resolve()))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.MATERIALS
