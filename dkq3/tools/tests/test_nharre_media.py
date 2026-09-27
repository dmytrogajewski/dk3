# SPDX-License-Identifier: GPL-2.0-or-later
import unittest

import sp2shaders


class NharreMediaTest(unittest.TestCase):
    def test_ground_crack_is_admitted_as_a_decal(self):
        shaders = dict(sp2shaders.frame_shaders(
            'models/e2/we_hammercrack.sp2', 0, 'synthetic-crack.png', True))
        mark = shaders['models/e2/we_hammercrack.sp2/0@mark']
        self.assertIn('polygonOffset', mark)
        self.assertIn('clampMap synthetic-crack.png', mark)
        self.assertIn('alphaGen vertex', mark)
        # Adding the mark must preserve the independently selectable blend modes.
        self.assertIn('blendFunc blend', shaders['models/e2/we_hammercrack.sp2/0'])
        self.assertIn('GL_SRC_ALPHA GL_ONE',
                      shaders['models/e2/we_hammercrack.sp2/0@alphachannel'])
