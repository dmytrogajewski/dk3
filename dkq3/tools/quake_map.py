# SPDX-License-Identifier: GPL-2.0-or-later
"""Quake 3 `.map` document model, brush validation and writer.

This is the dialect q3map2 (GtkRadiant 1.6.7, `tools/quake3/q3map2/map.c`
`ParseRawBrush`) reads in its classic `BPRIMIT_OLDBRUSHES` form:

    {
      "key" "value"                     ... entity epairs
      {
        ( x y z ) ( x y z ) ( x y z ) shader shiftS shiftT rotate scaleS scaleT content flags value
      }                                  ... one brush per convex, closed part
    }

The three points define the face plane through `PlaneFromPoints`
(`libs/mathlib/mathlib.c:437`), which uses `CrossProduct(c - a, b - a)`: that
normal points out of the plane for points wound **clockwise seen from outside**,
and a brush is the intersection of the resulting negative half-spaces. The
shader name omits its `textures/` prefix because the parser re-adds it.

Geometry authored in Blender reaches Quake through this module only. Brushes
stay convex so q3map2's CSG needs no decomposition, every emitted point is
snapped to a grid so neighbouring brushes share planes exactly, and each
validation failure names the object and part that broke the contract instead of
leaving the compiler to guess.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path

PLANE_SNAP = 1.0 / 8.0      # grid every emitted plane point is quantized to
DEGENERATE = 1e-6           # a triangle smaller than this defines no plane
# IBSP stores vertices as 1/8-unit integers (surface.c rounds them the same way),
# so a face on a slanted plane legitimately leaves its own plane by up to that
# much once its corners are quantized. The tolerances sit above that rounding
# and below any bend an author could introduce by hand.
PLANAR_TOLERANCE = 0.25     # how far a corner may leave its own face plane
CONVEX_TOLERANCE = 0.25     # how far a corner may poke out of any plane
MAX_COORD = 8192.0 * 16.0   # the outer bound q3map2 itself refuses to exceed
TEXTURE_EPSILON = 1e-4
C_DETAIL = 0x08000000       # q3map2.h:181, the same bit Radiant writes and q3map2.h keeps


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def length(a):
    return math.sqrt(dot(a, a))


def snap(point, grid=PLANE_SNAP):
    return tuple(round(value / grid) * grid for value in point)


class BrushError(ValueError):
    """A mesh part that cannot become a Quake brush, named by its source."""


@dataclass(frozen=True)
class FaceStyle:
    """How one face is textured: a shader plus the classic 2-axis projection.

    `detail` sets the only content bit q3map2 still reads from a `.map` face.
    A detail brush is decoration to the compiler: it neither splits the VIS
    tree nor shadows light, which is what lets a dense set dressing stay cheap.
    `solid` is not written out at all — a shader's `surfaceparm` decides that in
    the game — but the level audit needs it to tell a wall from a trigger.
    """
    shader: str
    shift: tuple[float, float] = (0.0, 0.0)
    rotate: float = 0.0
    scale: tuple[float, float] = (1.0, 1.0)
    detail: bool = False
    solid: bool = True


@dataclass(frozen=True)
class Face:
    """One brush side: an outward-facing plane plus its texture projection.

    `points` walks the whole ring, which the convexity test needs, while
    `definition` is the non-degenerate triple the writer emits — q3map2 reads
    exactly three points per side and derives the plane from them.
    """
    points: tuple[tuple[float, float, float], ...]        # clockwise seen from outside
    definition: tuple[tuple[float, float, float], ...]
    normal: tuple[float, float, float]
    dist: float
    style: FaceStyle

    def line(self):
        first, second, third = self.definition
        fmt = lambda p: '( %.3f %.3f %.3f )' % tuple(p)
        style = self.style
        numbers = '%g %g %g %.4f %.4f %d %d %d' % (style.shift[0], style.shift[1], style.rotate,
                                                   style.scale[0], style.scale[1],
                                                   C_DETAIL if style.detail else 0, 0, 0)
        return '\t\t%s %s %s %s %s' % (fmt(first), fmt(second), fmt(third), style.shader, numbers)


@dataclass
class Brush:
    """A closed, convex, planar polyhedron: exactly one Quake brush."""
    faces: list[Face]
    source: str = 'brush'

    def corners(self):
        seen, corners = set(), []
        for face in self.faces:
            for point in face.points:
                if point not in seen:
                    seen.add(point)
                    corners.append(point)
        return corners

    def bounds(self):
        corners = self.corners()
        mins = tuple(min(point[axis] for point in corners) for axis in range(3))
        maxs = tuple(max(point[axis] for point in corners) for axis in range(3))
        return mins, maxs

    def center(self):
        mins, maxs = self.bounds()
        return tuple((low + high) / 2 for low, high in zip(mins, maxs))

    def volume(self):
        """Enclosed volume by the divergence theorem: sum v0 . (v1 x v2) / 6 over
        every triangle of every face fan. The sign says nothing about the windings:
        Quake planes come from `PlaneFromPoints`, whose cross order is reversed
        against this one, so `validate_brush` checks the plane test that actually
        decides correctness."""
        total = 0.0
        for face in self.faces:
            for a, b, c in triangle_fan(face.points):
                total += dot(a, cross(b, c)) / 6.0
        return abs(total)

    def shaders(self):
        return sorted({face.style.shader for face in self.faces})

    def text(self):
        return '\t{\n' + '\n'.join(face.line() for face in self.faces) + '\n\t}'


@dataclass
class Entity:
    """Epairs plus the brushes that belong to them. Entity 0 is the world."""
    keys: dict[str, str] = field(default_factory=dict)
    brushes: list[Brush] = field(default_factory=list)
    source: str = 'entity'

    @property
    def classname(self):
        return self.keys.get('classname', '')

    def text(self):
        lines = ['{']
        lines.extend('\t"%s" "%s"' % (key, value) for key, value in self.keys.items())
        if self.brushes:
            lines.append('')
            lines.extend(brush.text() for brush in self.brushes)
        lines.append('}')
        return '\n'.join(lines)


@dataclass
class MapDoc:
    """An entity-ordered document whose first entity is `worldspawn`."""
    entities: list[Entity] = field(default_factory=list)

    def brushes(self):
        return [brush for entity in self.entities for brush in entity.brushes]

    def bounds(self):
        boxes = [brush.bounds() for brush in self.brushes()]
        if not boxes:
            return (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)
        return (tuple(min(box[0][axis] for box in boxes) for axis in range(3)),
                tuple(max(box[1][axis] for box in boxes) for axis in range(3)))

    def validate(self) -> list[str]:
        """-> human-readable defects; an empty list means the writer may run."""
        problems = []
        if not self.entities or self.entities[0].classname != 'worldspawn':
            problems.append('entity 0 is not worldspawn')
        for entity in self.entities:
            if not entity.classname:
                problems.append('%s: entity has no classname' % entity.source)
            # Brushes under a named entity become a compiled submodel (*N), which
            # is how func_door, func_button and every trigger reach the game.
            for brush in entity.brushes:
                try:
                    validate_brush(brush, entity.source)
                except BrushError as error:
                    problems.append(str(error))
        return problems

    def text(self) -> str:
        blocks = ['// entity %d (%s)\n%s' % (index, entity.source, entity.text())
                  for index, entity in enumerate(self.entities)]
        return '\n'.join(blocks) + '\n'


def triangle_fan(ring):
    """The triangles of a polygon given as its whole corner ring, fanned from ring[0].

    The caller passes every corner: fanning from the second corner instead loses
    one triangle per quad, which halves the volume a closed shell reports.
    """
    for index in range(1, len(ring) - 1):
        yield ring[0], ring[index], ring[index + 1]


def plane_from_points(pts):
    """-> (unit normal, distance, planar, defining triple) with q3map2's cross order."""
    origin = pts[0]
    normal, definition = None, None
    for index in range(1, len(pts) - 1):
        candidate = cross(sub(pts[index + 1], origin), sub(pts[index], origin))
        if length(candidate) > DEGENERATE:
            normal, definition = candidate, (pts[0], pts[index], pts[index + 1])
            break
    if normal is None:
        return None, None, False, None
    normal = tuple(component / length(normal) for component in normal)
    dist = dot(origin, normal)
    planar = all(abs(dot(point, normal) - dist) < PLANAR_TOLERANCE for point in pts)
    return normal, dist, planar, definition


def inside(brush, point):
    """-> whether `point` sits in the brush's interior (its negative half-spaces)."""
    return all(dot(point, face.normal) - face.dist < -CONVEX_MARGIN for face in brush.faces)


CONVEX_MARGIN = 1.0


def outside(brush, point, clearance=CONVEX_MARGIN):
    """-> whether `point` stands at least `clearance` clear of the whole brush.

    The complement of `inside`, and not the same test: a point sitting exactly on
    one of the brush's planes is neither inside nor outside by a margin, and a
    compiler walking a BSP resolves that on-plane point by whichever child it
    visits first. That is the difference between a lamp that lights a street and a
    lamp the compiler calls `Entity leaked`, so a point entity is asked to prove it
    stands clear, not merely to fail to be buried.
    """
    return any(dot(point, face.normal) - face.dist > clearance for face in brush.faces)


def span(brush, start, end):
    """-> the (entry, exit) fractions where start→end crosses the brush, or None.

    Both ends matter: the entry says whether a sightline is blocked at all, and
    the exit says how high a solid surface reaches under a spawn point.
    """
    low, high = 0.0, 1.0
    direction = sub(end, start)
    for face in brush.faces:
        normal, dist = face.normal, face.dist
        denominator = dot(direction, normal)
        offset = dot(start, normal) - dist
        if abs(denominator) < 1e-9:
            if offset > 0:
                return None
            continue
        fraction = -offset / denominator
        # Inside the brush means dot(p, normal) <= dist along the whole segment.
        # A plane the ray crosses with its normal (denominator < 0) can only be
        # left again, so it raises the lower bound; one it crosses against its
        # normal lowers the upper bound. Swapping the two says "no intersection"
        # precisely when the segment passes clean through the brush.
        if denominator < 0:
            low = max(low, fraction)
        else:
            high = min(high, fraction)
        if low > high:
            return None
    return (low, high) if high >= 0.0 and low <= 1.0 else None


def blocks(brush, start, end):
    """-> whether the brush cuts the segment at all."""
    return span(brush, start, end) is not None


def ground_below(brushes, origin):
    """-> the height of the highest solid surface under `origin`, or None over sky.

    The column is cast upward into the spawn point, so a brush's *exit* height is
    the surface a player would stand on; its entry point is the underside, which
    would report a floor many units too low for any thick floor slab.
    """
    best, column = None, (origin[0], origin[1], origin[2] - 4096.0)
    for brush in brushes:
        crossed = span(brush, column, origin)
        if crossed is None:
            continue
        _, exit_fraction = crossed
        candidate = column[2] + exit_fraction * (origin[2] - column[2])
        best = candidate if best is None else max(best, candidate)
    return best


def brush_from_mesh(points, polygons, style_for_face, source: str,
                    grid: float = PLANE_SNAP) -> Brush:
    """Turn one closed mesh part into a validated brush.

    `points` are the part's vertices in world space, `polygon` tuples index them,
    and `style_for_face(index, normal)` returns a `FaceStyle`. Windings are
    normalised once from the part's raw volume sign, so an author who modelled
    the part inside-out still gets outward-facing Quake planes.
    """
    if len(polygons) < 4:
        raise BrushError('%s: a brush needs at least 4 faces, got %d' % (source, len(polygons)))
    raw_volume = sum(dot(points[a], cross(points[b], points[c])) / 6.0
                     for polygon in polygons for a, b, c in triangle_fan(polygon))
    if abs(raw_volume) < 1.0:
        raise BrushError('%s: the part encloses %.3f units, too small to be a brush'
                         % (source, raw_volume))
    # `PlaneFromPoints` uses CrossProduct(c - a, b - a), the reverse of the
    # right-hand convention, so a part whose corners run counter-clockwise seen
    # from outside would yield inward planes. Reversing it once fixes every face.
    if raw_volume > 0:
        polygons = [tuple(reversed(polygon)) for polygon in polygons]
    directed = {}
    faces = []
    for index, polygon in enumerate(polygons):
        if len(polygon) < 3:
            raise BrushError('%s: face %d has fewer than 3 corners' % (source, index))
        ordered = list(polygon)
        snapped = [snap(points[i], grid) for i in ordered]
        corners = [pt for position, pt in enumerate(snapped) if pt != snapped[position - 1]]
        if len(corners) < 3:
            raise BrushError('%s: face %d collapses when planes are snapped' % (source, index))
        normal, dist, planar, definition = plane_from_points(corners)
        if normal is None:
            raise BrushError('%s: face %d is degenerate' % (source, index))
        if not planar:
            raise BrushError('%s: face %d is not planar' % (source, index))
        for position in range(len(corners)):
            edge = (corners[position], corners[(position + 1) % len(corners)])
            if edge in directed:
                raise BrushError('%s: face %d repeats an edge, the shell self-intersects' % (source, index))
            directed[edge] = index
        faces.append(Face(points=tuple(corners), definition=tuple(definition), normal=normal,
                          dist=dist, style=style_for_face(index, normal)))
    for edge, owner in directed.items():
        if directed.get((edge[1], edge[0])) is None:
            raise BrushError('%s: face %d leaves edge %.1f %.1f %.1f -> %.1f %.1f %.1f open'
                             % (source, owner, *edge[0], *edge[1]))
    return Brush(faces=faces, source=source)


def validate_brush(brush: Brush, entity: str = '') -> None:
    """Reject anything q3map2 would silently drop or, worse, compile wrong."""
    label = '%s/%s' % (entity, brush.source) if entity else brush.source
    if len(brush.faces) < 4:
        raise BrushError('%s: only %d faces' % (label, len(brush.faces)))
    if brush.volume() < 1.0:
        raise BrushError('%s: the part encloses too little space to be a brush' % label)
    planes: dict[tuple[int, ...], str] = {}
    for face in brush.faces:
        key = tuple(round(component / 1e-3) for component in face.normal) + (round(face.dist / 1e-3),)
        if key in planes:
            raise BrushError('%s: duplicate or mirrored plane at %s, q3map2 drops such brushes'
                             % (label, planes[key]))
        planes[key] = '%.1f %.1f %.1f' % face.points[0]
        for point in brush.corners():
            if max(abs(component) for component in point) > MAX_COORD:
                raise BrushError('%s: %.0f exceeds the world extent' % (label, max(abs(c) for c in point)))
            # Every corner sits on or behind every outward plane: that is convexity,
            # and it is what lets the exporter skip CSG decomposition.
            if dot(point, face.normal) - face.dist > CONVEX_TOLERANCE:
                raise BrushError('%s: corner %.1f %.1f %.1f is outside the plane of %s, '
                                 'so the part is not convex'
                                 % (label, point[0], point[1], point[2], face.style.shader))
    for face in brush.faces:
        if any(abs(component) < TEXTURE_EPSILON for component in face.style.scale):
            raise BrushError('%s: face %s has a zero texture scale' % (label, face.style.shader))


def write_map(doc: MapDoc, path) -> str:
    """Write `doc` to `path`, refusing a document that fails validation."""
    problems = doc.validate()
    if problems:
        raise BrushError('\n'.join(problems))
    Path(path).write_text(doc.text(), encoding='utf-8')
    return doc.text()
