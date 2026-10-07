# SPDX-License-Identifier: GPL-2.0-or-later
"""The chain that carries an authored texture scale into a compiled face.

Two failures this suite exists because of, both found in `japanDM`:

* the motif retune edited `repeat` in the recipe table and the installed map kept
  tiling at the previous size, because the model step was skipped by a staleness
  guard that watched a hand-written list of inputs;
* `craft_textures.ramp()` asked numpy to clamp an index into a six-stop sky and got
  an index off the end of it, so `--sky` had never once completed.

Both are silent: the build reports the change as applied either way.
"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import craft_textures
import map_build


def face(shader, scale, points='( 0 0 0 ) ( 128 0 0 ) ( 128 128 0 )'):
    # shader, shiftS, shiftT, rotate, scaleS, scaleT, content, value, content
    return '\t\t%s %s 0 0 0 %s %s 0 0 0' % (points, shader, scale, scale)


class Ramp(unittest.TestCase):
    STOPS = ((0.0, (0.10, 0.10, 0.10)), (0.44, (0.20, 0.20, 0.20)),
             (0.488, (0.30, 0.30, 0.30)), (0.50, (0.40, 0.40, 0.40)),
             (0.52, (0.50, 0.50, 0.50)), (1.0, (0.60, 0.60, 0.60)))

    def test_a_stop_is_honoured_exactly(self):
        import numpy as np
        out = craft_textures.ramp(np.array([0.0, 0.44, 0.5, 1.0], np.float64), self.STOPS)
        want = [0.10, 0.20, 0.40, 0.60]
        for row, value in zip(out, want):
            self.assertAlmostEqual(float(row[0]), value, places=3)

    def test_a_query_below_the_first_stop_takes_the_first_colour(self):
        import numpy as np
        out = craft_textures.ramp(np.array([-3.0], np.float64), self.STOPS)
        self.assertAlmostEqual(float(out[0][0]), 0.10, places=3)

    def test_the_top_segment_closes_at_the_last_stop(self):
        """The bug: on the last row of a panorama the old code indexed past `colours`."""
        import numpy as np
        rows = (np.arange(400) + 0.5) / 400
        query = np.repeat(rows[:, None], 64, axis=1)
        out = craft_textures.ramp(query, self.STOPS)      # must not raise
        self.assertEqual(out.shape, (400, 64, 3))
        self.assertAlmostEqual(float(out[-1, 0][0]), 0.60, places=3)

    def test_a_query_that_never_reaches_a_stop_never_selects_it(self):
        """`searchsorted` answered stop 6 for a query whose maximum was 0.480."""
        import numpy as np
        rows = (np.arange(512) + 0.5) / 512 * 0.48
        query = np.repeat(rows[:, None], 256, axis=1)
        out = craft_textures.ramp(query, self.STOPS)
        self.assertLess(float(out[..., 0].max()), 0.21)   # still inside segment 0->0.44


class TextureScaleDrift(unittest.TestCase):
    TABLE = ("MATERIALS = {\n"
             "    'japandm/metal_deck': dict(repeat=32.0, texwidth=1024.0),\n"
             "    'japandm/plain': dict(),\n"
             "}\n")

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='dk3-scale-'))
        (self.tmp / 'materials.py').write_text(self.TABLE)

    def document(self, *lines):
        path = self.tmp / 'demo.map'
        path.write_text('{\n' + '\n'.join(lines) + '\n}\n')
        return path

    def test_a_face_at_the_declared_tile_is_not_drift(self):
        doc = self.document(face('japandm/metal_deck', '0.0312'))
        self.assertEqual(map_build.texture_scale_drift(doc, self.tmp), [])

    def test_a_scene_modelled_from_stale_numbers_is_named(self):
        doc = self.document(face('japandm/metal_deck', '0.1250'))
        drift = map_build.texture_scale_drift(doc, self.tmp)
        self.assertEqual([path for path, _ in drift], ['japandm/metal_deck'])
        self.assertEqual(drift[0][1][0], 32.0)            # what the table asks for
        self.assertAlmostEqual(drift[0][1][1], 128.0, places=1)   # what the face carries

    def test_a_tool_material_without_keys_defers_to_the_authors_defaults(self):
        # map_author.py: repeat 128 over a 512 image.
        doc = self.document(face('japandm/plain', '0.2500'))
        self.assertEqual(map_build.texture_scale_drift(doc, self.tmp), [])

    def test_a_shader_outside_the_table_is_left_alone(self):
        doc = self.document(face('common/common', '1.0000'))
        self.assertEqual(map_build.texture_scale_drift(doc, self.tmp), [])


if __name__ == '__main__':
    unittest.main()
