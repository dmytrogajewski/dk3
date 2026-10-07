# SPDX-License-Identifier: GPL-2.0-or-later
"""The sky is one panorama reprojected through an axis table, so the table is the map.

A mirrored cube face looks fine on a monitor and wrong in the engine: the skyline ends up
hanging from the zenith, which is what one inverted texcoord line did to a shipped
`japanDM`.  Nothing on disk says a cube face is upside down -- the direction one pixel of
one face looks in has to be computed and compared with the axis table the tool documents.
"""
import importlib.util
import math
from pathlib import Path
import unittest

import numpy as np

import neural_textures

REPO_ROOT = Path(__file__).resolve().parents[3]

SIDE_FACES = ('rt', 'bk', 'lf', 'ft')

# The module docstring's MakeSkyVec table, in the q3 convention where `v` is measured
# down from the top of the face image: u = 2u-1, v = 1-2v.
AXES = {
    'rt': lambda u, v: (1.0, -(2 * u - 1.0), 1 - 2 * v),
    'bk': lambda u, v: (-1.0, 2 * u - 1.0, 1 - 2 * v),
    'lf': lambda u, v: (2 * u - 1.0, 1.0, 1 - 2 * v),
    'ft': lambda u, v: (-(2 * u - 1.0), -1.0, 1 - 2 * v),
    'up': lambda u, v: (2 * v - 1.0, 1 - 2 * u, 1.0),
    'dn': lambda u, v: (1 - 2 * v, 1 - 2 * u, -1.0),
}


def face_pixel(side, row, column, size=8):
    """-> the unit direction `cube_face` aims one pixel of one face at."""
    elevation, azimuth = neural_textures.cube_face(side, size)
    e, a = float(elevation[row, column]), float(azimuth[row, column])
    return np.array([math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)])


def expected(side, row, column, size=8):
    """-> the direction the documented axis table gives that pixel."""
    u, v = (column + 0.5) / size, (row + 0.5) / size
    direction = np.array(AXES[side](u, v), np.float64)
    return direction / np.linalg.norm(direction)


def flat_panorama(height=64, width=128):
    """-> a 2:1 panorama that is white above the equator and black below it.

    Its horizon is the only edge in the whole image, so wherever it lands on a face says
    exactly where the reprojection puts elevation zero.
    """
    panorama = np.zeros((height, width, 3), np.uint8)
    panorama[:height // 2] = 255
    return panorama


class CubeFaceTest(unittest.TestCase):
    def test_every_side_face_runs_from_sky_down_to_ground(self):
        for side in SIDE_FACES:
            elevation, _ = neural_textures.cube_face(side, 8)
            self.assertGreater(elevation[0].mean(), 0.3, '%s top row looks down' % side)
            self.assertLess(elevation[-1].mean(), -0.3, '%s bottom row looks up' % side)
            self.assertAlmostEqual(float(elevation[3:5].mean()), 0.0, places=9, msg=side)

    def test_face_pixels_point_where_the_axis_table_says(self):
        corners = ((0, 0), (0, 7), (7, 0), (7, 7), (4, 4))
        for side in neural_textures.CUBE_SIDES:
            for row, column in corners:
                got, want = face_pixel(side, row, column), expected(side, row, column)
                self.assertAlmostEqual(float(np.dot(got, want)), 1.0, places=6,
                                       msg='%s pixel %s points at %s, not %s'
                                       % (side, (row, column), np.round(got, 3),
                                          np.round(want, 3)))

    def test_the_polar_faces_keep_their_hemisphere(self):
        for side, sign in (('up', 1.0), ('dn', -1.0)):
            elevation, _ = neural_textures.cube_face(side, 8)
            self.assertTrue((elevation * sign > 0).all(),
                            '%s samples across the horizon' % side)

    def test_the_panorama_horizon_lands_in_the_middle_of_a_side_face(self):
        face = neural_textures.panorama_face(flat_panorama(), 'ft', 16)
        brightness = face.mean(axis=2)
        self.assertGreater(brightness[:4].mean(), 240, 'the sky half is not on top')
        self.assertLess(brightness[-4:].mean(), 15, 'the ground half is on top')
        self.assertGreater(brightness[:4].mean(), brightness[-4:].mean())

    def test_a_layered_skyline_is_drawn_above_its_horizon(self):
        """The city belongs in the sky half of the panorama, not the ground half.

        Horizontal variation per row is what separates them: a dusk gradient is constant
        along a row, so anything that varies across one is a tower.  The ground half is
        allowed only scattered street specks, which is why it stays an order of magnitude
        quieter.
        """
        recipes = REPO_ROOT / 'maps' / 'japanDM' / 'textures.py'
        if not recipes.is_file():
            self.skipTest('the map recipe table is not present')
        spec = importlib.util.spec_from_file_location('japandm_recipes', recipes)
        recipes = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(recipes)
        panorama = neural_textures.sky_gradient(512, 256, seed=0)
        horizon = int(panorama.shape[0] * 0.5)
        drawn = neural_textures.city_skyline(panorama, recipes.SKY['city'], seed=0)

        def across(band):
            return float(np.asarray(band.std(axis=1)).mean())

        self.assertLess(across(panorama[:horizon]), 0.5, 'the plain sky already had towers in it')
        self.assertGreater(across(drawn[:horizon]), 5.0,
                           'the skyline added no structure above the horizon')
        self.assertLess(across(drawn[horizon:]), across(drawn[:horizon]) / 5.0,
                        'the skyline was drawn below its horizon')


if __name__ == '__main__':
    unittest.main()
