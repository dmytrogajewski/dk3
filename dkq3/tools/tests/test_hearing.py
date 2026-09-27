# SPDX-License-Identifier: GPL-2.0-or-later
"""Synthetic distinct PVS/PHS rows catch loss of around-corner hearing data."""
import collections
import struct
import unittest
from types import SimpleNamespace
import dkbsp
import dk2q3


class Map(dkbsp.Bsp):
    def __init__(self):
        self.source = 'synthetic-hearing'
        self.lumps = {'visibility': (0, 24)}
        # Two isolated visibility clusters can hear each other.
        self.data = struct.pack('<5i', 2, 20, 22, 21, 23) + b'\x01\x02\x03\x03'

    def raw(self, name):
        return self.data


class Hearing(unittest.TestCase):
    def test_conversion_keeps_hearing_independent_from_visibility(self):
        source = Map()
        self.assertEqual([row for row, _ in source.pvs_rows()], [b'\x01', b'\x02'])
        self.assertEqual([row for row, _ in source.phs_rows()], [b'\x03', b'\x03'])
        converted = SimpleNamespace(b=source, losses=collections.Counter())
        dk2q3.Converter.build_vis(converted)
        self.assertEqual(converted.visibility, struct.pack('<2i', 2, 1) + b'\x01\x02')
        self.assertEqual(converted.hearing, b'DKPH' + struct.pack('<2i', 2, 1) + b'\x03\x03' + b'DKPT' + struct.pack('<I', 14))

    def test_hearing_offsets_are_not_silently_replaced_with_pvs(self):
        source = Map()
        source.data = struct.pack('<5i', 2, 20, 24, 21, 23) + b'\x01\x02\x03\x03'
        with self.assertRaises(dkbsp.BadVisibility):
            source.phs_rows()


if __name__ == '__main__':
    unittest.main()
