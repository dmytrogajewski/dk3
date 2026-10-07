# SPDX-License-Identifier: GPL-2.0-or-later
"""The sightline probe reads a real `.map` and measures only what a player can occupy."""
import math
import tempfile
import unittest
from pathlib import Path

import map_sightlines
import quake_map

STYLE = quake_map.FaceStyle(shader='test/wall')
TRIGGER = quake_map.FaceStyle(shader='common/trigger')


def style_for(style):
    return lambda index, normal: style


def box(mins, maxs, style=STYLE, source='box'):
    x0, y0, z0 = mins
    x1, y1, z1 = maxs
    points = [(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
    polygons = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return quake_map.brush_from_mesh(points, polygons, style_for(style), source)


def room():
    """A 1024-room with a floor, a lid, four walls and one partition, plus a trigger.

    Two spawns sit behind the partition, one does not, and the trigger volume
    covers the third spawn so that a tool which mistook a trigger for a wall
    would report it as cover.
    """
    walls = [box((-512, -512, -32), (512, 512, 0)),                    # floor
             box((-512, -512, 256), (512, 512, 288)),                  # lid
             box((-512, -512, 0), (-480, 512, 256)),                   # west
             box((480, -512, 0), (512, 512, 256)),                     # east
             box((-512, -512, 0), (512, -480, 256)),                   # south
             box((-512, 480, 0), (512, 512, 256)),                     # north
             box((-16, -256, 0), (16, 256, 128)),                      # partition
             box((-256, -256, 0), (-128, -128, 128), TRIGGER, 'trigger')]
    world = quake_map.Entity(keys={'classname': 'worldspawn', 'message': 'probe'}, brushes=walls)
    spawns = [quake_map.Entity(keys={'classname': 'info_player_deathmatch', 'origin': origin,
                                     'angle': '0'}, source='spawn%d' % index)
              for index, origin in enumerate(('-288 -64 24', '288 -64 24', '-192 -192 24'))]
    item = quake_map.Entity(keys={'classname': 'weapon_test', 'origin': '288 192 24'},
                            source='gun')
    return quake_map.MapDoc(entities=[world] + spawns + [item])


class ReadMapTest(unittest.TestCase):
    def document(self, temporary, name='probe.map'):
        path = Path(temporary) / name
        quake_map.write_map(room(), path)
        return path

    def test_written_document_reads_back_with_the_same_planes(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = self.document(temporary)
            read = map_sightlines.read_map(path, non_solid=('trigger',))
            original = room()
            self.assertEqual(len(read.brushes()), len(original.brushes()))
            self.assertEqual(read.entities[0].keys['message'], 'probe')
            self.assertEqual([entity.classname for entity in read.entities],
                             [entity.classname for entity in original.entities])
            self.assertEqual([sorted(brush.shaders()) for brush in read.brushes()],
                             [sorted(brush.shaders()) for brush in original.brushes()])
            for before, after in zip(original.brushes(), read.brushes()):
                self.assertEqual(before.bounds()[0], after.bounds()[0])
                self.assertEqual(before.bounds()[1], after.bounds()[1])
                self.assertEqual(len(before.faces), len(after.faces))

    def test_a_trigger_shader_is_not_an_occluder(self):
        with tempfile.TemporaryDirectory() as temporary:
            read = map_sightlines.read_map(self.document(temporary), non_solid=('trigger',))
            kinds = {brush.shaders()[0]: any(face.style.solid for face in brush.faces)
                     for brush in read.brushes()}
            self.assertTrue(kinds['test/wall'])
            self.assertFalse(kinds['common/trigger'])

    def test_a_comment_line_does_not_become_a_token(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = self.document(temporary)
            text = path.read_text().replace('// entity 0', '// a brace } and a quote " here')
            path.write_text(text)
            self.assertTrue(map_sightlines.read_map(path, non_solid=('trigger',)).brushes())


class ProbeTest(unittest.TestCase):
    def setUp(self):
        self.document = map_sightlines.read_map_text = None
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'probe.map'
            quake_map.write_map(room(), path)
            self.doc = map_sightlines.read_map(path, non_solid=('trigger',))

    def test_samples_sit_on_the_floor_with_headroom(self):
        index = map_sightlines.Index([brush for brush in self.doc.brushes()
                                      if any(face.style.solid for face in brush.faces)], cell=128.0)
        samples = map_sightlines.eye_positions(index, self.doc.bounds(), grid=64.0)
        self.assertGreater(len(samples), 40)
        for x, y, eye, floor in samples:
            self.assertAlmostEqual(eye - floor, map_sightlines.EYE_ABOVE_FLOOR, places=6)

    def test_the_roof_of_the_sealing_shell_is_not_walkable(self):
        # Sampling flat tops finds the lid of the shell as readily as the floor;
        # only the set a spawn can walk to may be measured.
        report = map_sightlines.probe(self.doc, grid=64.0, directions=4, reach=1024.0,
                                      thresholds=(200.0,))
        self.assertGreater(report['unreachable_samples'], 0)
        self.assertGreater(report['samples'], 40)
        self.assertEqual(report['samples'] + report['unreachable_samples'],
                         report['samples_considered'])

    def test_the_partition_blocks_only_below_its_top(self):
        index = map_sightlines.Index([brush for brush in self.doc.brushes()
                                      if any(face.style.solid for face in brush.faces)], cell=128.0)
        blocked, _ = index.cast((-288.0, -64.0, 64.0), (288.0, -64.0, 64.0))
        self.assertLess(blocked, 1.0)
        clear, winner = index.cast((-288.0, -64.0, 200.0), (288.0, -64.0, 200.0))
        self.assertEqual(clear, 1.0)
        self.assertIsNone(winner)

    def test_probe_reports_the_partition_pair_as_covered_and_the_third_as_open(self):
        report = map_sightlines.probe(self.doc, grid=64.0, directions=8, reach=1024.0,
                                      thresholds=(200.0,), min_range=96.0)
        # spawn 1 (-288,-64) and spawn 3 (-192,-192) share the west half behind the
        # partition; spawn 2 (288,-64) is east of it, and the partition runs the
        # whole depth, so it is the only pair the level leaves open.
        self.assertEqual(report['spawn_pairs_visible'],
                         ['info_player_deathmatch 1<->info_player_deathmatch 3'])
        self.assertTrue(any('weapon_test' in line for line in report['spawn_sees_item']))
        self.assertEqual(report['spawns'], 3)

    def test_exposure_is_a_range_question(self):
        """Someone standing beside a spawn is not what a spawn's cover is for."""
        index = map_sightlines.Index([])                      # open space: nothing blocks
        spawn = ('info_player_deathmatch 1', (0.0, 0.0, 22.0))
        beside = map_sightlines.exposures(index, [spawn], [(0.0, 96.0, 22.0, 0.0)],
                                          min_range=640.0)
        self.assertEqual(beside, {})
        distant = map_sightlines.exposures(index, [spawn], [(0.0, 900.0, 22.0, 0.0)],
                                           min_range=640.0)
        self.assertEqual(sorted(distant), ['info_player_deathmatch 1'])
        self.assertEqual(distant['info_player_deathmatch 1']['vantages'], 1)
        self.assertEqual(distant['info_player_deathmatch 1']['worst'][0]['range'], 900.0)

    def test_reach_is_measured_from_a_floor_a_player_can_stand_on(self):
        samples = [(0.0, 0.0, 22.0, 0.0)]                     # one standing spot, floor 0
        self.assertTrue(map_sightlines.within_reach(samples, (24.0, 24.0, 24.0)))
        self.assertFalse(map_sightlines.within_reach(samples, (0.0, 0.0, 280.0)))
        self.assertFalse(map_sightlines.within_reach(samples, (600.0, 0.0, 24.0)))

    def test_closest_approach_stays_on_the_segment(self):
        near, point = map_sightlines.distance_to_segment((0.0, 10.0, 0.0), (100.0, 0.0, 0.0),
                                                        (200.0, 0.0, 0.0))
        self.assertAlmostEqual(near, math.hypot(100.0, 10.0))
        self.assertEqual(point, (100.0, 0.0, 0.0))


if __name__ == '__main__':
    unittest.main()
