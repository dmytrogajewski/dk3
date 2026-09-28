# SPDX-License-Identifier: GPL-2.0-or-later
"""Acceptance bookkeeping contracts; these fixtures are not engine evidence."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from runtime_campaign_probe import complete_opening
from runtime_input import cinematic_shots
from runtime_opening_route import fight, terminal_contact
from runtime_bridge_route import observed_heal


class CampaignEvidenceTests(unittest.TestCase):
    def test_pickup_can_be_observed_during_a_damaging_approach(self):
        samples = [{"health": value} for value in (73, 38, 63, 44)]
        self.assertEqual(observed_heal(samples, 25), (samples[1], samples[2]))
        self.assertIsNone(observed_heal([{"health": value} for value in (73, 38, 44)], 25))
        self.assertIsNone(observed_heal([{"health": 100}, {"health": 100}], 25))

    def test_lost_local_actor_is_not_a_kill_or_contact_without_evidence(self):
        terminal = "dk3 zig combat: target=382 blood=30 armor=0 killed=1\n"
        initial = dict(map="e1m1b", health=100, pos=(0, 0, 24), water=0,
                       weapon=2, ammo=10, event=0, fire=-1, buttons=0)
        fired = dict(initial, event=1, fire=100)
        actor = dict(health=50, sight="1", pos=(100, 0, 24), aim=(100, 0, 30),
                     now="100", **{"class": "monster_slaughterskeet"})
        for new_log in ("", terminal):
            with self.subTest(new_log=new_log):
                driver = Mock(inputs=[])
                driver.observe.side_effect = [initial, initial, initial, fired]
                driver.ready.return_value = initial
                # A kill before this encounter cannot qualify the disappearance.
                driver.text.side_effect = [terminal, terminal + new_log]
                driver.diagnostics.return_value = "flight_target=382"
                driver.until.return_value = fired
                with patch("runtime_opening_route.actors", side_effect=[{382: actor}, {382: actor}, {}]):
                    self.assertEqual(fight(driver, Mock(), "e1m1b", 382), bool(new_log))
                evidence = driver.inputs[-1]
                self.assertTrue(evidence["fired"])
                self.assertEqual(evidence["contacted"], bool(new_log))
                self.assertEqual(evidence["lost_target"], not bool(new_log))
                self.assertIsNone(evidence["after"])
                self.assertEqual([call.args[0] for call in driver.issue.call_args_list], ["+attack", "-attack"])

    def test_retired_target_requires_its_actual_terminal_damage(self):
        nonterminal = "dk3 zig combat: target=382 blood=30 armor=0 killed=0\n"
        other_target = "dk3 zig combat: target=383 blood=30 armor=0 killed=1\n"
        no_damage = "dk3 zig combat: target=382 blood=0 armor=0 killed=1\n"
        terminal = "dk3 zig combat: target=382 blood=30 armor=0 killed=1"
        self.assertIsNone(terminal_contact(nonterminal + other_target + no_damage, 382))
        self.assertEqual(terminal_contact(nonterminal + terminal + "\n", 382), terminal)
        self.assertIsNone(terminal_contact(terminal, 38))

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
        self.rows.insert(0, {"arena_contacts": [{"before": 30, "after": 0}], "actual_fire": True,
                             "waves": [f"skeet{i}{side}" for i in range(1, 6) for side in "ab"]})
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
        del self.rows[5]
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

    def test_full_bridge_requires_all_authored_wave_observations(self):
        self.rows[0]["waves"].pop()
        with self.assertRaisesRegex(RuntimeError, "ten authored wave"):
            self.complete()

    def test_missing_evidence_does_not_silently_pass(self):
        (self.args.report / "connected-death-reload.json").unlink()
        with self.assertRaises(FileNotFoundError):
            self.complete()
