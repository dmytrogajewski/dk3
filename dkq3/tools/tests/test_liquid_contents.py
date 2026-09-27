# SPDX-License-Identifier: GPL-2.0-or-later
"""The independent conversion preserves authored lethal cold volumes."""
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import dk2q3
import q3bsp


class LiquidContents(unittest.TestCase):
    def test_nitro_survives_with_distinct_contents(self):
        projected = {name: target for _, name, target in dk2q3.CONTENTS}
        self.assertEqual(projected['NITRO'], q3bsp.CONTENTS_DK3_NITRO)
        self.assertNotEqual(projected['NITRO'], 0)
        self.assertEqual(projected['NITRO'] & (projected['WATER'] | projected['LAVA'] | projected['SLIME']), 0)
        header = Path(__file__).resolve().parents[3] / 'engine/ioquake3/code/qcommon/surfaceflags.h'
        import re
        value = re.search(r'#define CONTENTS_DK3_NITRO\s+(0x[0-9a-fA-F]+)', header.read_text())[1]
        self.assertEqual(int(value, 16), projected['NITRO'])


if __name__ == '__main__':
    unittest.main()
