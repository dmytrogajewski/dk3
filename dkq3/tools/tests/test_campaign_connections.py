# SPDX-License-Identifier: GPL-2.0-or-later
import struct
import unittest

from campaign_connections import connections, read_map
from campaign_regions import encode, REVIEWED


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

    def test_intermission_requires_no_named_landing(self):
        exits = [dict(entity=i, destination="destination", target=target, cinematic="", flags=1)
                 for i, target in ((2, ""), (3, "corridor"))]
        maps = {"source": dict(exits=exits, starts=[]),
                "destination": dict(exits=[], starts=[dict(entity=1, targetname="corridor")])}
        rows = connections(maps)
        self.assertEqual(rows[0]["status"], "authored_cut")
        self.assertEqual(rows[1]["status"], "geometry_unreviewed")

    def test_cinematic_control_owns_cut_even_without_exit_flags(self):
        entity_text = (b'{\n"classname" "worldspawn"\n}\n'
                       b'{\n"classname" "func_button"\n"target" "changelev"\n"cinetrigger" "intro"\n}\n'
                       b'{\n"classname" "trigger_changelevel"\n"targetname" "changelev"\n"model" "*1"\n"map" "next"\n}\n\0')
        bsp = bytearray(144)
        struct.pack_into('<4si', bsp, 0, b'IBSP', 46)
        struct.pack_into('<ii', bsp, 8, len(bsp), len(entity_text))
        bsp += entity_text
        struct.pack_into('<ii', bsp, 8 + 7 * 8, len(bsp), 80)
        bsp += struct.pack('<6f4i', 0, 0, 0, 1, 1, 1, 0, 0, 0, 0) * 2
        source = read_map('unrelated_name', bsp)
        rows = connections({'unrelated_name': source, 'next': dict(exits=[], starts=[])})
        self.assertTrue(source['exits'][0]['cinematic_control'])
        self.assertEqual(rows[0]['status'], 'authored_cut')

    def test_geometry_review_requires_both_exact_maps(self):
        document = dict(maps={name: dict(sha256=sha) for name, sha in REVIEWED.items()},
                        connections=[dict(source='e1m1a', destination='e1m1b', entity=25,
                                          status='geometry_unreviewed', return_exit_candidates=[449])])
        self.assertIn('kind "identity"', encode(document))
        document['maps']['e1m1b']['sha256'] = 'f' * 64
        self.assertNotIn('kind "identity"', encode(document))
        self.assertIn('kind "landing"', encode(document))
