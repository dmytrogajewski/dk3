#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Turn one generated prop mesh into the convex brushes a Quake 3 map can hold.

Run inside Blender:

    blender -b --python dkq3/tools/map_prop_brushes.py -- \
        --prop maps/japanDM/props/lantern --tris 400 --pieces 10 --preview prev.png

Why this exists at all, in three sentences.  A `.map` has no models: every prop
must be a brush, a brush is the intersection of its planes, and so a concave prop
is several convex brushes or none.  `misc_model` is not an escape -- measured on
this engine's q3map2, an OBJ prop produced 8 planar surfaces belonging to no
brush, shader `missing`, non-solid, while the BSP's brush count never left 6.  So
the generated mesh has to be *decomposed*, and the only honest measure of a
decomposition is how much of the object its hulls actually contain.

Decimate, split the surface into clusters with an area-weighted kd-tree, take one
convex hull per cluster, merge coplanar facets, keep only hulls whose faces stay
planar, and record each piece's mean baked colour so the placement pass can pick
a material.  `--tris` and `--pieces` are the quality dials; `concavity` in the
report is the number to watch -- 1 - (piece volume / hull volume), averaged.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import time

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector


# --------------------------------------------------------------------------- #
# reading the generated mesh
# --------------------------------------------------------------------------- #
def imported_mesh(glb):
    """-> the joined, transform-free mesh the generator produced."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(glb))
    bpy.ops.object.select_all(action='DESELECT')
    objects = [object for object in bpy.context.scene.objects if object.type == 'MESH']
    if not objects:
        raise RuntimeError('%s imported no mesh' % glb)
    for object in objects:
        object.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return joined


def base_colour(object):
    """-> the prop's baked atlas, whatever the importer chose to call its node."""
    for slot in object.material_slots:
        material = slot.material
        if material is None or not material.use_nodes or not material.node_tree:
            continue
        for node in material.node_tree.nodes:
            if node.type == 'TEX_IMAGE' and getattr(node, 'image', None) is not None:
                if node.image.size[0] > 1:
                    return node.image
    return None


def decimate(object, triangles):
    """-> (mesh, faces before, faces after) after a hard collapse onto a budget."""
    mesh = object.data
    before = len(mesh.polygons)
    if before > triangles:
        modifier = object.modifiers.new('dk3decimate', 'DECIMATE')
        modifier.decimate_type = 'COLLAPSE'
        modifier.ratio = max(1e-4, triangles / float(before))
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = object
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return mesh, before, len(mesh.polygons)


def surface_arrays(mesh):
    """-> (vertices, triangles, centroids, areas, triangle-major loop UVs)."""
    mesh.calc_loop_triangles()
    mesh.calc_normals_split() if hasattr(mesh, 'calc_normals_split') else None
    vertices = np.empty((len(mesh.vertices), 3))
    mesh.vertices.foreach_get('co', vertices.reshape(-1))
    loops = mesh.loop_triangles
    triangles = np.empty((len(loops), 3), dtype=np.int64)
    areas = np.empty(len(loops))
    centroids = np.empty((len(loops), 3))
    loops.foreach_get('vertices', triangles.reshape(-1))
    loops.foreach_get('area', areas)
    # `MeshLoopTriangle` carries no `center` in this Blender; the centroid of a
    # triangle is the mean of its three corners anyway.
    centroids[:] = vertices[triangles].mean(axis=1)
    uvs = None
    layer = mesh.uv_layers.active
    if layer is not None:
        flat = np.empty(len(layer.data) * 2)
        layer.data.foreach_get('uv', flat)
        flat = flat.reshape(-1, 2)
        # `MeshLoopTriangle` has no `start_index`; it names its three loops, and
        # those are the indices into the UV layer.
        corners = np.empty((len(loops), 3), dtype=np.int64)
        loops.foreach_get('loops', corners.reshape(-1))
        if corners.size and corners.max() < len(flat):
            uvs = flat[corners]
    return vertices, triangles, centroids, areas, uvs


# --------------------------------------------------------------------------- #
# decomposition
# --------------------------------------------------------------------------- #
def cluster(centroids, areas, pieces, minimum):
    """-> triangle-index groups, by an area-weighted kd split of the surface.

    Splitting the surface rather than the volume needs no boolean and no
    watertight input -- and TRELLIS output is not watertight.  Weighting the
    median by triangle area stops one long spike from stealing half the pieces,
    and cutting the longest axis is what turns a cart into a bed, a box and two
    wheels instead of three equal halves of nothing.
    """
    groups = [np.flatnonzero(areas > 0)]
    while len(groups) < pieces:
        # Replace by position: `list.remove(array)` compares with `==`, and two
        # numpy groups of different lengths make that a broadcast, not a match.
        candidates = [position for position, group in enumerate(groups)
                      if len(group) >= 2 * minimum]
        if not candidates:
            break
        pick = max(candidates, key=lambda position: areas[groups[position]].sum())
        best = groups[pick]
        points, weights = centroids[best], areas[best]
        axis = int(np.argmax(points.max(axis=0) - points.min(axis=0)))
        order = np.argsort(points[:, axis])
        running = np.cumsum(weights[order])
        cut = int(np.searchsorted(running, running[-1] / 2.0))
        floor = max(len(order) // 4, 1)
        cut = min(max(cut, floor), len(order) - floor)
        groups[pick:pick + 1] = [best[order[:cut]], best[order[cut:]]]
    return [group for group in groups if len(group)]


def hull(vertices, triangles, group, angle_limit=1.5, snap=0.0):
    """-> (points, polygons, volume) of one convex hull, or None.

    The hull is taken over the corners the cluster touched, so the cut faces
    close themselves and the piece is convex by construction -- which is exactly
    what entitles a brush to reference these planes at all.
    """
    used = np.unique(triangles[group])
    if len(used) < 4:
        return None
    if snap:
        import os
        if os.environ.get('DK3_PROP_DEBUG'):
            print('hull: snap %0.2f -> %d unique corners from %d used'
                  % (snap, len(np.unique(np.round(vertices / snap) * snap, axis=0)),
                     len(used)), file=sys.stderr, flush=True)
        # Quantising the corners *before* hulling is the whole difference between
        # a brush set with 51 facets per piece and one with 8.  A convex hull of a
        # decimated organic mesh inherits every facet of that mesh; snapping to a
        # grid the size of a visible detail collapses them into the planes a real
        # prop has, and a Q3 brush wants planes, not facets.
        corners = np.round(vertices / snap) * snap
        corners = np.unique(corners, axis=0)
        return hull_from_points(corners, angle_limit)
    corners = np.unique(vertices[used], axis=0)
    return hull_from_points(corners, angle_limit)


def hull_from_points(corners, angle_limit=1.5):
    """-> (points, polygons, volume) of the convex hull of a point set.

    `bmesh.ops.convex_hull` needs a closed solid to reason about inside and out:
    a bare point cloud makes it return nothing at all, which is how a first
    attempt here produced zero brushes and no error.  A small seed cube at the
    centroid supplies that solidity, and the hull then swallows it and deletes it
    as interior geometry.
    """
    if len(corners) < 4:
        return None
    centre = corners.mean(axis=0)
    radius = max(float(np.abs(corners - centre).max()), 1.0) * 0.02
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2 * radius,
                          matrix=Matrix.Translation(Vector(centre)) @ Matrix.Diagonal((1, 1, 1, 1)))
    for point in corners:
        bm.verts.new(Vector(point))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=max(1e-6, radius * 0.05))
    geometry = list(bm.verts[:]) + list(bm.edges[:]) + list(bm.faces[:])
    result = bmesh.ops.convex_hull(bm, input=geometry, use_existing_faces=False)
    keep = set(result.get('geom') or [])
    if not keep:
        bm.free()
        return None
    for group, context in ((bm.verts, 'VERTS'), (bm.edges, 'EDGES'), (bm.faces, 'FACES')):
        dead = [element for element in group if element not in keep]
        if dead:
            bmesh.ops.delete(bm, geom=dead, context=context)
    if not bm.faces:
        bm.free()
        return None
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(angle_limit),
                             use_dissolve_boundaries=False, delimit=set(),
                             verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.01)

    def bow(face):
        return max(abs((vert.co - face.verts[0].co).dot(face.normal)) for vert in face.verts)

    # A `dissolve_limit` merge is planar only within its angle tolerance, and a
    # Q3 brush plane is defined by three of these corners -- so a merged face
    # that bows is not "slightly wrong", it is a face whose real plane is
    # undefined.  Triangulating only the offenders keeps the merged count where
    # it is honest and pays a triangle only where it is not.
    for _ in range(3):
        bowing = [face for face in bm.faces
                  if face.calc_area() <= 1e-9 or len(face.verts) < 3 or bow(face) > 0.06]
        if not bowing:
            break
        bmesh.ops.triangulate(bm, faces=bowing)
    if not bm.faces or any(face.calc_area() <= 1e-9 or len(face.verts) < 3 or bow(face) > 0.06
                           for face in bm.faces):
        bm.free()
        return None
    index = {vert: position for position, vert in enumerate(bm.verts)}
    points = [tuple(vert.co) for vert in bm.verts]
    polygons = [tuple(index[vert] for vert in face.verts) for face in bm.faces
                if len(face.verts) >= 3]
    bm.free()
    volume = solid_volume(points, polygons)
    return (points, polygons, volume) if volume > 1e-9 else None


def solid_volume(points, polygons):
    """-> the volume enclosed by a closed shell, by the divergence theorem.

    Fanning each polygon from its own first corner is exact here because a hull
    facet is convex by construction.  `bmesh.calc_volume` is spelled differently
    in every Blender series; this is not.
    """
    corners = np.asarray(points, dtype=np.float64)
    total = 0.0
    for ring in polygons:
        anchor = corners[ring[0]]
        for position in range(1, len(ring) - 1):
            total += float(np.dot(anchor, np.cross(corners[ring[position]],
                                                   corners[ring[position + 1]])))
    return abs(total) / 6.0


def concavity(vertices, triangles, group, scale, volume):
    """-> 1 - (cluster volume / hull volume), the optimistic end.

    A true solid-vs-solid test needs a closed piece, which needs a boolean, and
    booleans on a decimated mesh are exactly where a batch dies.  This reads the
    cluster's own volume from the divergence theorem over its (open) triangle
    fan: exact for a closed surface, an under-read for an open cluster, so the
    number reported is the *best case* for that piece.  Above ~0.3 the prop
    needs more `--pieces`, not a nicer explanation.
    """
    corners = (vertices * scale)[triangles[group]]
    signed = np.einsum('ni,ni->n', corners[:, 0],
                       np.cross(corners[:, 1], corners[:, 2]))
    own = abs(float(signed.sum()) / 6.0)
    return float(max(0.0, min(1.0, 1.0 - own / volume))) if volume > 1e-9 else 1.0


def piece_colour(image, uvs, group):
    """-> mean sRGB of the baked atlas under one piece, or None without a texture."""
    if image is None or uvs is None:
        return None
    width, height = image.size
    if width < 2 or height < 2:
        return None
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(height, width, 4)
    samples = uvs[group]
    u = np.mod(samples[:, :, 0], 1.0).reshape(-1)
    v = np.mod(samples[:, :, 1], 1.0).reshape(-1)
    columns = np.clip(np.round(u * (width - 1)).astype(int), 0, width - 1)
    rows = np.clip(np.round(v * (height - 1)).astype(int), 0, height - 1)
    return [round(float(value), 4) for value in pixels[rows, columns][:, :3].mean(axis=0)]


# --------------------------------------------------------------------------- #
# eyeballing, without a GPU or a game engine
# --------------------------------------------------------------------------- #
def preview(pieces, path, side=340):
    """-> a 3-view silhouette sheet of the hulls, drawn from the recipe itself.

    Workbench and EEVEE both want a GL context a `-b` run may not have; three
    filled orthographic outlines answer the only question worth asking early --
    is this a lantern, or a lump?
    """
    from PIL import Image, ImageDraw
    sheet = Image.new('RGB', (side * 3 + 20, side + 20), (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    points = [point for piece in pieces for point in piece['points']]
    if not points:
        sheet.save(path)
        return
    low = np.min(points, axis=0)
    high = np.max(points, axis=0)
    span = max(float((high - low).max()), 1e-6)
    for view, (horizontal, vertical) in enumerate([(0, 1), (0, 2), (1, 2)]):
        origin = 10 + view * (side + 5)
        for piece in pieces:
            colour = piece.get('colour') or [0.6, 0.6, 0.6]
            # `image.pixels` is a linear float store; sRGB is what a person reads.
            tone = tuple(int(round(255 * min(1.0, channel ** (1 / 2.2))))
                         for channel in colour)
            for ring in piece['polygons']:
                normal = np.asarray([0.0, 0.0, 0.0])
                corners = [piece['points'][index] for index in ring]
                outline = [(origin + (corner[horizontal] - low[horizontal] + 0.04 * span)
                            * side / span,
                            side - 10 - (corner[vertical] - low[vertical] + 0.04 * span)
                            * side / span) for corner in corners]
                draw.polygon(outline, fill=tone, outline=(12, 12, 14))
    sheet.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--prop', type=Path, required=True, help='the prop actor directory')
    parser.add_argument('--out', type=Path, default=None, help='default <prop>/brushes.json')
    parser.add_argument('--tris', type=int, default=420, help='triangle budget')
    parser.add_argument('--pieces', type=int, default=10, help='maximum convex brushes')
    parser.add_argument('--minimum', type=int, default=6, help='never split below this many triangles')
    parser.add_argument('--grid', type=int, default=12,
                        help='corner quantisation across the footprint; the plane-count dial')
    parser.add_argument('--max-planes', type=int, default=16,
                        help='a hull with more facets than this is re-hulled coarser')
    parser.add_argument('--size', type=float, default=None, help='authored footprint (default spec.json)')
    parser.add_argument('--preview', type=Path, default=None)
    # Blender forwards its own command line to the script, `--` included, and
    # argparse reads everything after that marker as positionals -- so slice it
    # off first, the same way map_author.py does.
    arguments = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    glb = arguments.prop / 'model.glb'
    if not glb.is_file():
        raise SystemExit('%s has no model.glb; run the generator first' % arguments.prop)
    spec = json.loads((arguments.prop / 'spec.json').read_text()) \
        if (arguments.prop / 'spec.json').is_file() else {}
    footprint = float(arguments.size or spec.get('size') or 64.0)
    out = arguments.out or (arguments.prop / 'brushes.json')
    started = time.time()

    object = imported_mesh(glb)
    mesh, before, after = decimate(object, arguments.tris)
    vertices, triangles, centroids, areas, loop_uv = surface_arrays(mesh)
    image = base_colour(object)

    # The generator returns a normalised mesh; the map works in engine units at
    # 1 unit = 2 cm, so the longest extent becomes the authored footprint and the
    # lowest point becomes z = 0.  Placement after this only adds an origin, a
    # yaw and a scale, never a reshape.
    touched = vertices[triangles]
    low, high = touched.min(axis=(0, 1)), touched.max(axis=(0, 1))
    scale = footprint / max(1e-6, float((high - low).max()))
    # Put the mesh in engine units *now*, before anything measures or quantises
    # it.  The first attempt here snapped corners on a 6.4-unit grid while the
    # vertices were still normalised to +/-0.4, which collapsed every corner of
    # every cluster onto one point and produced zero brushes and no error.
    vertices = (vertices - low) * scale
    centroids = (centroids - low) * scale

    snap = footprint / max(4.0, float(arguments.grid))
    groups = cluster(centroids, areas, arguments.pieces, arguments.minimum)
    pieces = []
    for group in groups:
        step, made = snap, None
        attempts = []
        for _ in range(4):
            # A brush is a set of planes the compiler must intersect, split for
            # vis and lit per face; a hull that cannot say what it is in
            # `max_planes` of them is not too detailed, it is the wrong shape.
            made = hull(vertices, triangles, group, snap=step)
            attempts.append('%0.2f/%s' % (step, 'none' if made is None else len(made[1])))
            if made is not None and len(made[1]) <= arguments.max_planes:
                break
            step *= 1.6
        if made is None:
            print('props:   cluster of %d triangles produced no hull (%s)'
                  % (len(group), ' '.join(attempts)), file=sys.stderr, flush=True)
            continue
        points, polygons, volume = made
        moved = [[round(float(value[axis]), 3) for axis in range(3)] for value in points]
        array = np.asarray(moved)
        pieces.append(dict(points=moved, polygons=[list(ring) for ring in polygons],
                           triangles=int(len(group)), colour=piece_colour(image, loop_uv, group),
                           concavity=round(concavity(vertices, triangles, group, 1.0, volume), 4),
                           extent=[round(float(value), 1) for value in
                                   array.max(axis=0) - array.min(axis=0)],
                           snap=round(step, 2)))
    all_points = [point for piece in pieces for point in piece['points']]
    extents = np.asarray(all_points) if all_points else np.zeros((1, 3))
    recipe = dict(format=1, prop=arguments.prop.name, generator='TRELLIS.2',
                  source_glb_sha256=hashlib.sha256(glb.read_bytes()).hexdigest(),
                  footprint=footprint, tris=arguments.tris, pieces_target=arguments.pieces,
                  grid=arguments.grid, snap=round(snap, 2), max_planes=arguments.max_planes,
                  faces_before=before, faces_after=after, brushes=len(pieces),
                  planes=sum(len(piece['polygons']) for piece in pieces),
                  concavity=round(float(np.mean([piece['concavity'] for piece in pieces])), 4)
                  if pieces else None,
                  seconds=round(time.time() - started, 1),
                  extent=[round(float(value), 1) for value in extents.max(axis=0) - extents.min(axis=0)],
                  pieces=pieces)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(recipe, indent=1) + '\n')
    if arguments.preview:
        preview(pieces, arguments.preview)
    print('props: %-15s faces %6d->%4d  brushes %2d  planes %3d  concavity %s  extent %s  %.1fs'
          % (arguments.prop.name, before, after, recipe['brushes'], recipe['planes'],
             recipe['concavity'], recipe['extent'], recipe['seconds']), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
