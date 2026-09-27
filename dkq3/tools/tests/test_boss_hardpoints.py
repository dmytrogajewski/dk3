# SPDX-License-Identifier: GPL-2.0-or-later
from types import SimpleNamespace
import unittest

import numpy as np

import dkm2md3


class BossHardpointsTest(unittest.TestCase):
    def test_boss_visible_surfaces_keep_animated_attachment_centroids(self):
        names = ['body', 'eye2', 'sword1', 'eye1', 'sword2', 'hr_muzzle', 'fire', 'ctf_flag']
        model = SimpleNamespace(
            surfaces=[SimpleNamespace(name=name) for name in names],
            triangles=[SimpleNamespace(surface=i, xyz=(i * 3, i * 3 + 1, i * 3 + 2))
                       for i in range(len(names))],
            frames=[None, None],
        )
        points = np.arange(len(names) * 9, dtype=np.float32).reshape(-1, 3)
        # Existing muzzle/flame/flag tags and newly required named visible surfaces
        # share the same centroid contract across animation frames.
        positions = np.stack([points, points + np.array([3, -5, 7])])
        tags = dkm2md3._hardpoint_tags(model, positions)
        self.assertEqual([tag.name for tag in tags[0]], names[1:])
        for frame, actual in enumerate(tags):
            for index, tag in enumerate(actual, 1):
                np.testing.assert_allclose(tag.origin, positions[frame, index * 3:index * 3 + 3].mean(axis=0))
                self.assertEqual(tag.axis, dkm2md3.IDENTITY_AXIS)


if __name__ == '__main__':
    unittest.main()
