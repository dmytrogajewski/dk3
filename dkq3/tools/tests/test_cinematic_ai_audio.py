# SPDX-License-Identifier: GPL-2.0-or-later
"""Checks recorded dialogue alignment without requiring game assets."""

import unittest

import numpy as np

from cinematic_ai_audio import align_voice


class CinematicAudioAlignmentTests(unittest.TestCase):
    def test_finds_engine_playback_offset_in_mixed_audio(self):
        rng = np.random.default_rng(401)
        voice = rng.normal(0, 0.2, 4000).astype(np.float32)
        recording = rng.normal(0, 0.02, 32000).astype(np.float32)
        recording[11920:15920] += voice
        actual, confidence = align_voice(recording, voice, expected=1.52)
        self.assertAlmostEqual(actual, 1.49, places=4)
        self.assertGreater(confidence, 0.9)

    def test_rejects_missing_voice(self):
        rng = np.random.default_rng(402)
        recording = rng.normal(0, 1, 32000).astype(np.float32)
        voice = rng.normal(0, 1, 4000).astype(np.float32)
        with self.assertRaisesRegex(ValueError, "confidence"):
            align_voice(recording, voice, expected=1.5)


if __name__ == "__main__":
    unittest.main()
