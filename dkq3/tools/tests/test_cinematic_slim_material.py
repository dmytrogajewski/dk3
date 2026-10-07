# SPDX-License-Identifier: GPL-2.0-or-later
"""A hand-weighted robe tab must not become skin in the semantic albedo."""
from __future__ import annotations

import unittest
import numpy as np

import animation_manifest as schema
from cinematic_slim_material_blender import paint


class SlimMaterialTests(unittest.TestCase):
    def test_robe_tab_stays_cloth_beside_exposed_hand(self):
        points = np.concatenate((
            np.tile([0., 0., 10.], (1100, 1)),
            np.tile([1.7, 10., 3.2], (1100, 1)),
            np.tile([.24, 6.8, 3.8], (100, 1))), axis=0)
        rgb = np.concatenate((
            np.tile([.85, .85, .81], (1100, 1)),
            np.tile([.53, .52, .51], (1100, 1)),
            np.tile([.86, .86, .82], (100, 1))), axis=0)
        ownership = np.zeros(len(points))
        ownership[-100:] = 1.
        result, regions = paint(points, rgb, ownership, ownership)
        self.assertEqual(regions['skin_vertices'], 1100)
        self.assertGreater(result[-100:, 0].min(), .7)
        self.assertGreater(result[1100:2200, 0].mean(), result[1100:2200, 2].mean())

    def test_nonfinite_surface_rejected(self):
        with self.assertRaises(schema.Error):
            paint(np.array([[np.nan, 0., 0.]]), np.zeros((1, 3)))


if __name__ == '__main__':
    unittest.main()
