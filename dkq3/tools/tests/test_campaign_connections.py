# SPDX-License-Identifier: GPL-2.0-or-later
import struct
import unittest

from campaign_connections import connections, read_map


class Connections(unittest.TestCase):
    def test_named_start_is_not_replaced_with_arbitrary_fallback(self):
        exit = dict(entity=2, destination="e1m1b", target="absent", cinematic="", flags=0)
        maps = {"e1m1a": dict(exits=[exit], starts=[]),
                "e1m1b": dict(exits=[], starts=[dict(entity=3, targetname="unrelated")])}
        row = connections(maps)[0]
        self.assertEqual(row["landing_candidates"], [])
        self.assertIn("named_landing_missing", row["issues"])
        self.assertEqual(row["status"], "geometry_unreviewed")

    def test_multiple_connections_remain_distinct_and_cut_is_explicit(self):
        exits = [dict(entity=i, destination="e1m1b", target="door", cinematic="", flags=0) for i in (4, 7)]
        exits.append(dict(entity=9, destination="e1m1b", target="door", cinematic="ending", flags=0))
        maps = {"e1m1a": dict(exits=exits, starts=[]),
                "e1m1b": dict(exits=[], starts=[dict(entity=1, targetname="DOOR")])}
        rows = connections(maps)
        self.assertEqual([r["entity"] for r in rows], [4, 7, 9])
        self.assertEqual(rows[0]["landing_candidates"][0]["entity"], 1)
        self.assertEqual(rows[2]["status"], "authored_cut")

    def test_bad_lump_is_rejected_before_parsing(self):
        data = bytearray(144)
        struct.pack_into("<4si", data, 0, b"IBSP", 46)
        struct.pack_into("<ii", data, 8, 140, 10)
        with self.assertRaisesRegex(ValueError, "invalid BSP lump 0"):
            read_map("e1m1a", bytes(data))
