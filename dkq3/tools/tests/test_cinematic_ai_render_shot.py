"""Frame planning tests for resumable cinematic video shots."""

import unittest

from dkq3.tools.cinematic_ai_render_shot import segment_frames


class SegmentFrameTests(unittest.TestCase):
    def test_one_segment(self):
        self.assertEqual(segment_frames(3.0), (72, [73]))

    def test_boundary_overlap_and_tail(self):
        target, counts = segment_frames(8.0)
        self.assertEqual(target, 192)
        self.assertEqual(counts, [81, 81, 33])
        self.assertGreaterEqual(sum(counts) - len(counts) + 1, target)

    def test_reject_nonfinite_and_invalid_maximum(self):
        with self.assertRaises(ValueError):
            segment_frames(float("nan"))
        with self.assertRaises(ValueError):
            segment_frames(3.0, 80)


if __name__ == "__main__":
    unittest.main()
