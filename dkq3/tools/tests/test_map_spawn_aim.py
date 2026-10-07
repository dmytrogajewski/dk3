# SPDX-License-Identifier: GPL-2.0-or-later
"""The spawn-aim probe sees what the eye sees at spawn, and says when it is a wall."""
import math
import unittest

import map_spawn_aim
import quake_map

STYLE = quake_map.FaceStyle(shader='test/wall')


def style_for(style):
    return lambda index, normal: style


def box(mins, maxs, style=STYLE, source='box'):
    x0, y0 = mins[0], mins[1]
    x1, y1 = maxs[0], maxs[1]
    z0, z1 = mins[2], maxs[2]
    points = [(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
    polygons = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return quake_map.brush_from_mesh(points, polygons, style_for(style), source)


def arena(brushes, origin, angle):
    """-> a one-spawn document: floor, lid, four walls, then whatever is added."""
    shell = [box((-512, -512, -32), (512, 512, 0)),                     # floor
             box((-512, -512, 256), (512, 512, 288)),                   # lid
             box((-512, -512, 0), (-480, 512, 256)),                    # west
             box((480, -512, 0), (512, 512, 256)),                      # east
             box((-512, -512, 0), (512, -480, 256)),                    # south
             box((-512, 480, 0), (512, 512, 256))]                      # north
    entities = [quake_map.Entity(keys={'classname': 'worldspawn'}, brushes=shell + list(brushes))]
    entities.append(quake_map.Entity(keys={'classname': 'info_player_deathmatch',
                                           'origin': origin, 'angle': str(angle)},
                                     source='spawn_crate'))
    return quake_map.MapDoc(entities=entities)


def index_of(document):
    return map_spawn_aim.solid_index(document, set())


class MeasureTest(unittest.TestCase):
    def test_a_crate_in_front_of_the_eye_is_measured_as_a_crate(self):
        # a crate 60 units north of an eye that is looking north: the view IS the crate
        document = arena([box((-64, 60, 0), (64, 192, 96), source='crate')], '-16 0 24', 90)
        row = map_spawn_aim.probe(document)[0]
        self.assertAlmostEqual(row['centre'], 60.0, places=1)
        self.assertLess(row['cone'], map_spawn_aim.MIN_CONE)
        self.assertTrue(row['blocked'], 'a start whose whole view is one crate must be reported')

    def test_the_same_crate_behind_the_shoulders_is_cover_not_a_blocked_view(self):
        document = arena([box((-64, -192, 0), (64, -60, 96), source='crate')], '-16 0 24', 90)
        row = map_spawn_aim.probe(document)[0]
        self.assertGreater(row['centre'], 400.0)       # north is the far wall of the room
        self.assertAlmostEqual(row['cover'], 60.0, places=1)
        self.assertFalse(row['blocked'])

    def test_cover_is_only_asked_about_behind_the_shoulders(self):
        # a solid 50 units dead ahead must never be counted as the spawn's cover
        document = arena([box((-64, 50, 0), (64, 120, 96), source='crate')], '-16 0 24', 90)
        row = map_spawn_aim.probe(document)[0]
        self.assertGreater(row['cover'], 400.0, 'the crate is in FRONT, so it is not cover')


class SolveTest(unittest.TestCase):
    def test_the_solver_turns_the_start_away_from_the_crate(self):
        document = arena([box((-64, 60, 0), (64, 192, 96), source='crate')], '-16 0 24', 90)
        index = index_of(document)
        eye = map_spawn_aim.starts(document)[0][1]
        angle, got = map_spawn_aim.solve(index, eye)
        self.assertIsNotNone(angle, 'a 1024 room has somewhere to look')
        self.assertFalse(got['blocked'])
        apart = abs(angle - 90.0) % 360.0
        self.assertGreater(min(apart, 360.0 - apart), 90.0,
                           'the answer must look away from the crate it was facing')

    def test_a_rail_line_all_the_way_down_a_catwalk_has_no_answer(self):
        """A lane walled at eye height on both sides cannot be aimed out of."""
        rails = [box((-512, 20, 0), (512, 36, 44), source='rail_n'),
                 box((-512, -36, 0), (512, -20, 44), source='rail_s')]
        index = index_of(arena(rails, '0 0 24', 0))
        angle, got = map_spawn_aim.solve(index, (0.0, 0.0, 22.0))
        self.assertIsNone(angle, 'the honest answer here is None, not a confident angle')



class SiteTest(unittest.TestCase):
    """A position has to survive the other gate as well: nobody far away may already see it."""

    def test_an_open_floor_offers_no_site_because_the_far_side_can_see_it(self):
        document = arena([], '0 0 24', 0)
        got = map_spawn_aim.sites(document, grid=96.0, min_range=100.0, separation=0.0)
        self.assertGreater(got['scanned'], 50, 'the 1024 room has plenty of walkable eye points')
        self.assertEqual(got['offered'], 0,
                         'on open floor every point is shot from the far side of the room')

    def test_a_site_is_not_offered_when_it_can_see_an_existing_start(self):
        """A second start must not share a first blood with one already placed: this
        is the rule that moved japanDM's fourth deck start off (-520, 296), which was
        seatable, unexposed and well aimed and looked straight down 420 units of ring
        walkway at `deck_w`.  The room here is bent into two halves that are
        walk-connected around a corner but cannot see each other."""
        bend = [box((-16, -512, 0), (16, 300, 224), source='wall_w'),
                box((160, -300, 0), (192, 512, 224), source='wall_e')]
        document = arena(bend, '-300 0 24', 0)
        index = index_of(document)
        _name, start_eye, _angle = map_spawn_aim.starts(document)[0]
        got = map_spawn_aim.sites(document, grid=96.0, min_range=2048.0, separation=240.0,
                                  limit=500)
        self.assertGreater(got['offered'], 3, 'beyond the bend there is somewhere to start')
        for row in got['found']:
            eye = (row['pos'][0], row['pos'][1], row['floor'] + 22.0)
            self.assertFalse(index.clear(start_eye, eye),
                             'an offered site must not be able to see the existing start')
            self.assertGreater(row['pos'][0], -16.0, 'and it must be off the west half')

    def test_a_site_is_only_offered_when_a_player_body_fits(self):
        """Eight units off a face is a legal FOOT and an impossible BODY -- the exact
        defect that cost japanDM a capture at (1016, -168), 8 units from a glass
        balustrade.  The same box and the same inset are used both ways here."""
        document = arena([box((-96, -186, 0), (96, -174, 40), source='balustrade')],
                         '0 0 24', 0)
        index = index_of(document)
        self.assertTrue(map_spawn_aim.body_box(index, (0.0, -166.0, 24.0)),
                        'a body 7 units inside a balustrade is stuck, not seated')
        self.assertFalse(map_spawn_aim.body_box(index, (0.0, -150.0, 24.0)),
                         'the same body nine units clear is seated')

    def test_found_sites_are_ordered_and_aimable(self):
        bend = [box((-16, -512, 0), (16, 300, 224), source='wall_w'),
                box((160, -300, 0), (192, 512, 224), source='wall_e')]
        got = map_spawn_aim.sites(arena(bend, '-300 0 24', 0), grid=96.0,
                                  min_range=2048.0, separation=240.0, limit=500)
        for row in got['found']:
            self.assertGreaterEqual(row['centre'], map_spawn_aim.MIN_CENTRE)
            self.assertGreaterEqual(row['cone'], map_spawn_aim.MIN_CONE)
        self.assertGreaterEqual(got['found'][0]['rank'], got['found'][-1]['rank'],
                                'the list is ordered by how much the spot is worth')


if __name__ == '__main__':
    unittest.main()
