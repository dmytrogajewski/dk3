# SPDX-License-Identifier: GPL-2.0-or-later
"""The sampled-match summariser must read telemetry even when the console decorates it."""
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import runtime_bot_skill_probe as probe

CLEAN = ('dk3 bot route: slot=0 skill=5 (Capable) fov=120 view=10.0,-1.0 scan=40 alert=0 '
         'target=585 seen_ms=100 goal=0 avoided=0 blocked=0 waypoint=1.00,2.00,3.00\n')
DECORATED = (']\x08 \x08dk3 bot route: slot=1 skill=5 (Capable) fov=120 view=-70.5,0.0 scan=-80 alert=1 '
             'target=0 seen_ms=0 goal=4 avoided=0 blocked=1 waypoint=9.00,9.00,9.00\n')
DEAD = ('dk3 bot route: slot=0 skill=1 (Novice) fov=80 view=1.0,0.0 scan=0 alert=0 '
        'target=0 seen_ms=0 goal=7 avoided=2 blocked=0 waypoint=4.00,5.00,6.00\n')
PLAYER = ('dk3 match player: respawned=0 cmd=850 slot=0 id=232 bot=1 team=free health=100 mode=normal '
          'score=2 deaths=1 captures=0 weapon=1 inventory=2 ammo=0 fire=-1 event=0 experience=1000 level=3 '
          'hurt=0 source=0 hit_weapon=0 pos=1.0,2.0,3.0 appearance=0\n')


class BotSkillProbeTest(unittest.TestCase):
    def analyse(self, text):
        with tempfile.TemporaryDirectory() as temporary:
            args = SimpleNamespace(map='e1dm2a', gametype='0', bots=4, fov=0, phases='5:30', report=Path(temporary))
            result = probe.analyse(text, [(5, 30), (1, 30)], args, Path('synthetic.log'))
            return result, json.loads((args.report / 'result.json').read_text())

    def test_decorated_and_plain_telemetry_both_count(self):
        result, written = self.analyse(CLEAN + DECORATED + DEAD + PLAYER)
        self.assertEqual(result['samples'], 3)
        self.assertEqual(written['samples'], 3)
        level = written['levels']['5']
        self.assertEqual(level['samples'], 2, 'the Novice line belongs to its own level, not this one')
        self.assertEqual(written['levels']['1']['samples'], 1)
        self.assertEqual(level['acquiring_samples'], 1, 'only the line with a non-zero target is acquiring')
        self.assertEqual(level['hurt_alert_samples'], 1)
        self.assertEqual(level['blocked_samples'], 1, 'navigation blockage stays visible')
        self.assertEqual(level['cone'], '120')
        self.assertEqual(sorted(level['sweep_headings']), ['-80', '40'])
        self.assertEqual(written['peak_score_by_slot']['0'], {'score': 2, 'deaths': 1})

    def test_a_log_without_telemetry_reports_nothing_rather_than_crashing(self):
        result, written = self.analyse('Team Play\nFoo killed Bar\n')
        self.assertEqual(result['samples'], 0)
        self.assertEqual(written['levels']['5']['samples'], 0)
        self.assertIsNone(written['levels']['5']['cone'])

    def test_faults_are_counted(self):
        _, written = self.analyse(CLEAN + 'runtime failure: bad projection\n')
        self.assertEqual(written['faults'], 1)


if __name__ == '__main__':
    unittest.main()
