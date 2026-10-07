# SPDX-License-Identifier: GPL-2.0-or-later
"""The invariants that decide whether japanDM's materials read as surfaces.

Two numbers were argued about in this project without a test holding either one
still.  A `std` target on a graded material looked like it was destroying contrast
(a 4.3x "crush" on roof ballast) and was removed -- but the ratio that made it look
that way was darkening behaving correctly, and nothing recorded which of the two
claims was the real one.  Separately, a diffusion plate divided by its own mean
still paints the plate's slow luminance swings onto a material, and the seam metric
that was supposed to catch bad tiles is structurally unable to see that: a bright
band that is continuous across the wrap scores a perfect zero while drawing a grid
line once per repeat.  Both are pinned here rather than re-argued from screenshots.

The shape guard is in this file too because its absence cost more than any visual
defect did: a `(H,W)` field mixed with a `(H,W,1)` one allocated ~47 GB, and the
kernel killed the desktop session's own cgroup, not just the tool.
"""
import unittest

import numpy as np
from scipy.ndimage import gaussian_filter

import craft_textures as ct

LUMA = ct.LUMA


def _albedo(size=128, seed=3):
    rng = np.random.default_rng(seed)
    base = 0.35 + 0.30 * np.clip(rng.random((size, size)).astype(np.float32), 0, 1)
    return np.repeat(base[..., None], 3, axis=2)


class Grade(unittest.TestCase):
    def test_mean_is_the_only_target(self):
        """Without a `std`, grade is exactly a scale onto the requested level."""
        albedo = _albedo()
        out = ct.grade(albedo, 0.14)
        luminance = out @ LUMA
        self.assertAlmostEqual(float(luminance.mean()), 0.14, places=3)

    def test_spread_follows_the_level_rather_than_a_second_target(self):
        """The spread is the structure's own, scaled by the same factor as the level.

        This is the arithmetic that makes the old "4.3x crushed" reading wrong: a
        material taken to a dark albedo cannot keep a bright material's absolute
        spread, and that is darkening, not damage.
        """
        albedo = _albedo()
        natural = albedo @ LUMA
        scale = 0.14 / float(natural.mean())
        out = ct.grade(albedo, 0.14) @ LUMA
        self.assertAlmostEqual(float(out.std()), float(natural.std()) * scale, places=4)

    def test_a_std_target_still_overrides_the_structure(self):
        """The superseded behaviour is pinned so its removal stays deliberate."""
        out = ct.grade(_albedo(), 0.14, 0.05) @ LUMA
        self.assertAlmostEqual(float(out.std()), 0.05, places=3)


class BorrowDetail(unittest.TestCase):
    """A plate may contribute grain and nothing else."""

    @staticmethod
    def _plate(size=128):
        """A plate with real microstructure on top of a strong slow swing."""
        y, x = np.mgrid[0:size, 0:size].astype(np.float32)
        slow = 0.45 + 0.30 * np.sin(2 * np.pi * x / size) * np.cos(2 * np.pi * y / size)
        # The fine part is whole cycles, not white noise: a real plate is folded to
        # be continuous across the wrap before it is ever borrowed, and noise has an
        # edge jump as large as its own interior gradient by construction, which
        # would be testing the fixture rather than the wrap-blur.
        rng = np.random.default_rng(7)
        fine = np.zeros((size, size), np.float32)
        for fx, fy in ((9, 4), (17, 11), (23, 29), (31, 7)):
            fine += rng.uniform(-0.5, 0.5) * np.sin(2 * np.pi * (fx * x + fy * y) / size)
        fine *= 0.16
        return np.repeat(np.clip(slow + fine, 0.02, 1)[..., None], 3, axis=2)

    def test_low_frequency_is_cut_and_grain_survives(self):
        albedo, plate = _albedo(), self._plate()
        before = ct.borrow_detail(albedo, plate, 0.75, band=None) @ LUMA
        after = ct.borrow_detail(albedo, plate, 0.75) @ LUMA

        def split(field):
            low = gaussian_filter(field, field.shape[0] / 8, mode='wrap')
            return float(low.std()), float((field - low).std())

        low_before, fine_before = split(before)
        low_after, fine_after = split(after)
        self.assertLess(low_after, low_before * 0.75, 'the slow swing was not removed')
        self.assertGreater(fine_after, fine_before * 0.75, 'the grain went with it')

    def test_it_does_not_move_the_level_the_grade_will_set_anyway(self):
        """`grade` runs after `borrow_detail`, so the level is re-imposed regardless."""
        albedo, plate = _albedo(), self._plate()
        plain = float((ct.grade(albedo, 0.175) @ LUMA).mean())
        borrowed = float((ct.grade(ct.borrow_detail(albedo, plate, 0.75), 0.175) @ LUMA).mean())
        self.assertAlmostEqual(plain, borrowed, places=3)

    def test_the_borrowed_field_wraps(self):
        detail = ct.borrow_detail(np.zeros((128, 128, 3), np.float32) + 1.0, self._plate(), 1.0)
        self.assertLess(ct.seam_metric(detail @ LUMA), 1.0)


class ShapeGuard(unittest.TestCase):
    def test_the_broadcast_trap_raises_instead_of_allocating(self):
        albedo = _albedo(64)
        with self.assertRaises(ValueError):
            ct.multiply(albedo, 1.0 + 0.2 * np.zeros((64, 64), np.float32)[..., None]
                        + 0.06 * np.zeros((64, 64), np.float32))


if __name__ == '__main__':
    unittest.main()
