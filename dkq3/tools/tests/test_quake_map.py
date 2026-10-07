# SPDX-License-Identifier: GPL-2.0-or-later
"""Authored geometry becomes exactly the brushes q3map2 will accept."""
import math
from pathlib import Path
import re
import unittest

import quake_map


STYLE = quake_map.FaceStyle(shader='textures_test/wall')


def style(index, normal):
    return STYLE


def brush(points, polygons, source='part', style_for_face=style):
    return quake_map.brush_from_mesh(points, polygons, style_for_face, source)


def prism(ring_xy, z0, z1):
    """A prism over a closed XY ring, wound outward: bottom reversed, top direct."""
    low = [(x, y, z0) for x, y in ring_xy]
    high = [(x, y, z1) for x, y in ring_xy]
    count = len(ring_xy)
    polygons = [tuple(reversed(range(count))), tuple(range(count, 2 * count))]
    polygons += [(index, (index + 1) % count, (index + 1) % count + count, index + count)
                 for index in range(count)]
    return low + high, polygons


def box(x0, y0, z0, x1, y1, z1):
    points = [(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
    # points index: p = 4*zbit + 2*ybit + xbit
    polygons = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return points, polygons


class BrushFromMeshTest(unittest.TestCase):
    def test_closed_box_becomes_one_convex_brush(self):
        points, polygons = box(0, 0, 0, 64, 64, 64)
        made = brush(points, polygons)
        self.assertEqual(len(made.faces), 6)
        self.assertAlmostEqual(made.volume(), 64.0 ** 3, places=3)
        normals = {tuple(round(component) for component in face.normal) for face in made.faces}
        self.assertEqual(normals, {(1, 0, 0), (0, 1, 0), (0, 0, 1), (-1, 0, 0), (0, -1, 0), (0, 0, -1)})
        quake_map.validate_brush(made, 'worldspawn')

    def test_flipped_part_still_gets_outward_planes(self):
        points, polygons = box(0, 0, 0, 32, 32, 32)
        straight = brush(points, polygons)
        reversed_ = brush(points, [tuple(reversed(polygon)) for polygon in polygons])
        self.assertEqual(sorted(face.normal for face in straight.faces),
                         sorted(face.normal for face in reversed_.faces))

    def test_concave_part_is_rejected(self):
        # An extruded L: every face is planar, yet the outer corner pokes out of
        # the slab planes, which is precisely what a convex brush may not do.
        l_ring = [(0, 0), (128, 0), (128, 64), (64, 64), (64, 128), (0, 128)]
        points, polygons = prism(l_ring, 0, 32)
        with self.assertRaises(quake_map.BrushError) as caught:
            quake_map.validate_brush(brush(points, polygons))
        self.assertIn('not convex', str(caught.exception))

    def test_duplicate_plane_is_rejected(self):
        points, polygons = box(0, 0, 0, 64, 64, 64)
        made = brush(points, polygons)
        made.faces.append(made.faces[0])          # the same plane twice
        with self.assertRaises(quake_map.BrushError) as caught:
            quake_map.validate_brush(made)
        self.assertIn('duplicate', str(caught.exception))

    def test_open_shell_is_rejected(self):
        points, polygons = box(0, 0, 0, 64, 64, 64)
        with self.assertRaises(quake_map.BrushError) as caught:
            brush(points, polygons[:-1])
        self.assertIn('open', str(caught.exception))

    def test_self_touching_shell_is_rejected(self):
        points, polygons = box(0, 0, 0, 64, 64, 64)
        with self.assertRaises(quake_map.BrushError) as caught:
            brush(points, polygons + [polygons[1]])
        self.assertIn('self-intersects', str(caught.exception))

    def test_degenerate_part_is_rejected(self):
        points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0), (0, 0, 1)]
        polygons = [(0, 1, 2), (0, 2, 3), (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
        with self.assertRaises(quake_map.BrushError):
            brush(points, polygons)

    def ramp(self, angle_degrees=0.0):
        """A 45-degree ramp: a prism over a right triangle, stood up and turned."""
        points, polygons = prism([(0, 0), (128, 0), (0, 128)], -64, 64)
        stand = lambda point: (point[0], -point[2], point[1])
        angle = math.radians(angle_degrees)
        turn = lambda point: (point[0] * math.cos(angle) - point[1] * math.sin(angle),
                              point[0] * math.sin(angle) + point[1] * math.cos(angle), point[2])
        placed = [quake_map.snap(turn(stand(point))) for point in points]
        return brush(placed, polygons)

    def test_slanted_ramp_becomes_a_convex_brush(self):
        made = self.ramp()
        quake_map.validate_brush(made)
        self.assertAlmostEqual(made.volume(), 0.5 * 128.0 * 128.0 * 128.0, places=3)
        slope = max(made.faces, key=lambda face: min(abs(face.normal[0]), abs(face.normal[2])))
        self.assertAlmostEqual(abs(slope.normal[0]), math.sqrt(0.5), places=6)
        self.assertAlmostEqual(abs(slope.normal[1]), 0.0, places=6)
        self.assertAlmostEqual(abs(slope.normal[2]), math.sqrt(0.5), places=6)

    def test_slanted_ramp_survives_plane_snapping(self):
        """Turning the ramp leaves irrational corners that the 1/8 grid must round."""
        made = self.ramp(45.0)
        quake_map.validate_brush(made)
        expected = 0.5 * 128.0 * 128.0 * 128.0
        self.assertAlmostEqual(made.volume(), expected, delta=expected * 1e-3)
        off_plane = max(max(abs(quake_map.dot(point, face.normal) - face.dist)
                            for point in face.points) for face in made.faces)
        self.assertLess(off_plane, quake_map.PLANAR_TOLERANCE)


class FaceTextWriterTest(unittest.TestCase):
    def line(self, **style_keys):
        points, polygons = box(0, 0, 0, 128, 64, 32)
        style = quake_map.FaceStyle(shader='neo/concrete', shift=(8.0, -16.0), rotate=90.0,
                                    scale=(0.25, 0.25), **style_keys)
        made = brush(points, polygons, style_for_face=lambda index, normal: style)
        return made.faces[0].line()

    def test_line_carries_the_classic_projection_tail(self):
        line = self.line()
        first, second, third, shader, shift_s, shift_t, rotate, scale_s, scale_t, content, flags, value = \
            re.match(r'\t\t\( ([\d. -]+)\) \( ([\d. -]+)\) \( ([\d. -]+)\) (\S+) '
                     r'(-?\d+) (-?\d+) (-?\d+) ([\d.]+) ([\d.]+) (\d+) (\d+) (\d+)$', line).groups()
        self.assertEqual(shader, 'neo/concrete')
        self.assertEqual((shift_s, shift_t, rotate), ('8', '-16', '90'))
        self.assertEqual((scale_s, scale_t), ('0.2500', '0.2500'))
        self.assertEqual((content, flags, value), ('0', '0', '0'))
        for corner in (first, second, third):
            self.assertEqual(len(corner.split()), 3)

    def test_detail_face_sets_only_the_content_bit(self):
        content = int(self.line(detail=True).split()[-3])
        self.assertEqual(content, quake_map.C_DETAIL)
        self.assertEqual(self.line().split()[-3], '0')


class DocumentTest(unittest.TestCase):
    def document(self):  # -> a MapDoc whose entity 0 is a sealed 256x256x64 room slab
        points, polygons = box(-128, -128, 0, 128, 128, 64)
        entity = quake_map.Entity(keys={'classname': 'worldspawn', 'message': 'test'},
                                  brushes=[brush(points, polygons, source='floor')],
                                  source='worldspawn')
        return quake_map.MapDoc(entities=[entity])

    def test_document_writes_entities_in_order(self):
        document = self.document()
        spawn = quake_map.Entity(keys={'classname': 'info_player_deathmatch', 'origin': '0 0 24'})
        document.entities.append(spawn)
        text = document.text()
        self.assertTrue(text.startswith('// entity 0 (worldspawn)'))
        self.assertIn('"info_player_deathmatch"', text)
        self.assertEqual(len(re.findall(r'^\t\t\(', text, re.MULTILINE)), 6)

    def test_entity_without_a_classname_is_reported(self):
        document = self.document()
        document.entities.append(quake_map.Entity(keys={'origin': '0 0 24'}, source='bad'))
        self.assertTrue(any('no classname' in problem for problem in document.validate()))

    def test_worldspawn_must_come_first(self):
        document = quake_map.MapDoc(entities=[quake_map.Entity(keys={'classname': 'func_wall'})])
        self.assertEqual(document.validate(), ['entity 0 is not worldspawn'])

    def test_writer_refuses_an_invalid_document(self):
        document = self.document()
        # Two planes enclose nothing; only the document check can stop the writer.
        made = brush(*box(0, 0, 0, 128, 128, 64), source='slab')
        made.faces = made.faces[:2]
        document.entities[0].brushes.append(made)
        with self.assertRaises(quake_map.BrushError):
            quake_map.write_map(document, '/tmp/should-not-exist.map')
        self.assertFalse(Path('/tmp/should-not-exist.map').exists())

    def test_bounds_cover_every_entity(self):
        document = self.document()
        points, polygons = box(-256, 0, 0, -128, 64, 16)
        document.entities[0].brushes.append(brush(points, polygons, source='wing'))
        self.assertEqual(document.bounds(), ((-256.0, -128.0, 0.0), (128.0, 128.0, 64.0)))


if __name__ == '__main__':
    unittest.main()


class SegmentPredicateTest(unittest.TestCase):
    """The audit's eyes: what is solid, what is underfoot and what blocks a shot."""

    def setUp(self):
        points, polygons = box(-64, -64, -32, 64, 64, 0)
        self.slab = brush(points, polygons, source='slab')          # a floor plate
        points, polygons = box(256, 256, 0, 320, 320, 32)
        self.wall = brush(points, polygons, source='wall')

    def test_a_segment_passing_clean_through_reports_both_surfaces(self):
        crossed = quake_map.span(self.slab, (0, 0, -256), (0, 0, 128))
        self.assertIsNotNone(crossed)
        entry, exit_ = crossed
        self.assertAlmostEqual(entry, 224.0 / 384.0, places=6)       # the underside
        self.assertAlmostEqual(exit_, 256.0 / 384.0, places=6)       # the walking surface

    def test_a_segment_ending_inside_exits_at_its_far_end(self):
        self.assertEqual(quake_map.span(self.slab, (0, 0, -256), (0, 0, -16))[1], 1.0)

    def test_a_segment_outside_every_plane_misses(self):
        self.assertIsNone(quake_map.span(self.slab, (0, 0, 128), (0, 0, 256)))          # above
        self.assertIsNone(quake_map.span(self.slab, (0, 0, -256), (0, 0, -48)))         # below
        self.assertIsNone(quake_map.span(self.slab, (512, 0, -64), (512, 0, 128)))      # beside
        self.assertIsNone(quake_map.span(self.slab, (-256, 0, 64), (256, 0, 64)))       # over

    def test_a_segment_running_through_the_interior_spans_the_whole_segment(self):
        self.assertEqual(quake_map.span(self.slab, (-32, 0, -16), (32, 0, -16)), (0.0, 1.0))
        self.assertIsNone(quake_map.span(self.slab, (-32, 0, 48), (32, 0, 48)))         # along, above

    def test_blocking_needs_the_wall_between_the_two_points(self):
        self.assertTrue(quake_map.blocks(self.wall, (0, 288, 16), (512, 288, 16)))
        self.assertFalse(quake_map.blocks(self.wall, (0, 288, 16), (128, 288, 16)))     # short of it
        self.assertFalse(quake_map.blocks(self.wall, (512, 288, 64), (512, 288, 128)))  # past and above

    def test_inside_names_the_interior_not_the_boundary(self):
        self.assertTrue(quake_map.inside(self.slab, (0, 0, -16)))
        self.assertFalse(quake_map.inside(self.slab, (0, 0, 0)))
        self.assertFalse(quake_map.inside(self.slab, (0, 0, 96)))

    def test_ground_below_reports_the_highest_surface(self):
        points, polygons = box(-512, -512, -32, 512, 512, 0)
        floor = brush(points, polygons, source='floor')
        self.assertAlmostEqual(quake_map.ground_below([floor], (0, 0, 24)), 0.0, places=6)
        points, polygons = box(-64, -64, 0, 64, 64, 96)
        platform = brush(points, polygons, source='platform')
        self.assertAlmostEqual(quake_map.ground_below([floor, platform], (0, 0, 96 + 24)), 96.0, places=6)
        self.assertAlmostEqual(quake_map.ground_below([floor, platform], (256, 0, 24)), 0.0, places=6)
        self.assertIsNone(quake_map.ground_below([platform], (256, 0, 24)))

    def test_ground_below_over_an_open_shaft_is_none(self):
        points, polygons = box(-512, -512, -32, -64, 512, 0)
        west = brush(points, polygons, source='west')
        points, polygons = box(64, -512, -32, 512, 512, 0)
        east = brush(points, polygons, source='east')
        self.assertIsNone(quake_map.ground_below([west, east], (0, 0, 24)))


if __name__ == '__main__':
    unittest.main()
