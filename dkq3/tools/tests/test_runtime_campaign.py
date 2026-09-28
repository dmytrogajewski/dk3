# SPDX-License-Identifier: GPL-2.0-or-later
"""Acceptance bookkeeping contracts; these fixtures are not engine evidence."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

from runtime_campaign_probe import complete_opening
from runtime_input import cinematic_shots


class CampaignEvidenceTests(unittest.TestCase):
    def test_short_shot_uses_actual_transition_not_the_finished_cursor(self):
        inputs = [{"observed": dict(map="intro", cinematic=1, shot=i)} for i in (0, 2)]
        inputs.append({"observed": dict(map="intro", cinematic=0, shot=3)})
        actual = lambda log: cinematic_shots(log, inputs, "intro", "intro", 3)
        self.assertEqual(actual(""), {0, 2})
        self.assertEqual(actual("dk3 cinematic: shot=2/3 name=intro\n"), {0, 1, 2})
        self.assertEqual(actual("dk3 cinematic: shot=2/3 name=other\n"
                                "dk3 cinematic: shot=2/4 name=intro\n"), {0, 2})
        inputs.pop(0)
        self.assertNotIn(0, actual("dk3 cinematic: started\n"))

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.args = SimpleNamespace(checkpoint=None, opening=True, report=Path(temporary.name))
        self.rows = [{"observed": {"map": name}} for name in
                     ("intro", "e1m1a", "e1m1b", "e1m1c", "e1m1b", "e1m1c", "e1m2a")]
        self.rows.append({"combat_target": 42, "fired": True, "contacted": True})
        self.driver = SimpleNamespace(inputs=self.rows)
        self.final = dict(map="e1m2a", mode="normal", health=82, skill=3)
        self.shots = set(range(115))
        self.write("connected-death-reload", {"death": {"health": -1}, "restored": {"health": 60, "mode": "normal"}})
        self.write("visited-world-roundtrip", {"before": {"boss": 0}, "after": {"boss": 0},
                   "bridge_arrival": {"map": "e1m1b"}, "factory_return": {"map": "e1m1c"}})
        self.write("monitor-restoration", {"restored_player": {"mode": "frozen"}, "released_player": {"mode": "normal"}})

    def write(self, name, value):
        (self.args.report / (name + ".json")).write_text(json.dumps(value))

    def complete(self):
        return complete_opening(self.args, self.driver, self.shots, self.final)

    def test_only_fresh_continuous_route_can_receive_fresh_acceptance(self):
        self.assertTrue(self.complete())
        self.args.checkpoint = Path("legitimate.sav")
        self.assertFalse(self.complete())
        self.args.checkpoint = None
        del self.rows[4]
        with self.assertRaisesRegex(RuntimeError, "connected map sequence"):
            self.complete()

    def test_missing_intro_or_target_contact_invalidates_acceptance(self):
        self.shots.remove(30)
        with self.assertRaises(RuntimeError):
            self.complete()
        self.shots.add(999)
        with self.assertRaises(RuntimeError):
            self.complete()
        self.shots.add(30)
        self.rows[-1]["contacted"] = False
        with self.assertRaisesRegex(RuntimeError, "target contact"):
            self.complete()

    def test_failed_restoration_invalidates_acceptance(self):
        self.write("monitor-restoration", {"restored_player": {"mode": "normal"}, "released_player": {"mode": "normal"}})
        with self.assertRaisesRegex(RuntimeError, "Monitor evidence"):
            self.complete()

    def test_missing_evidence_does_not_silently_pass(self):
        (self.args.report / "connected-death-reload.json").unlink()
        with self.assertRaises(FileNotFoundError):
            self.complete()
