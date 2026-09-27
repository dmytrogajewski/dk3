# SPDX-License-Identifier: GPL-2.0-or-later
import unittest
from unittest.mock import patch

from runtime_input import NativeInput
from runtime_opening_route import firing_pause


class NativeInputTests(unittest.TestCase):
    def test_firing_window_excludes_expiring_attacks_and_hatching(self):
        row = {"class": "monster_slaughterskeet", "skeeter": "attack", "velocity": (0, 0, 0), "attack_left": "599"}
        self.assertFalse(firing_pause(row))
        row["attack_left"] = "900"
        self.assertTrue(firing_pause(row))
        row["skeeter"] = "hatching"
        self.assertFalse(firing_pause(row))
        row.update({"class": "monster_froginator", "frog": "bite", "ground": "2046", "velocity": (0, 0, -40)})
        self.assertTrue(firing_pause(row))
        row["ground"] = "2047"
        self.assertFalse(firing_pause(row))

    def test_campaign_driver_rejects_mutation_and_command_chaining(self):
        driver = NativeInput(None, None, None, None, [])
        with patch("runtime_input.send") as send:
            for command in ("devmap e1m1b", "dk3_runtime_equip 26", "give all",
                            "dk3_runtime_place 0 0 0", "+use", "-use", "weapon 2; give all", "weapon 2\ngive all"):
                with self.assertRaises(ValueError):
                    driver.issue(command)
            send.assert_not_called()
            driver.issue("+forward")
            driver.issue("dk3_look 90 -12")
            driver.issue("use")
            self.assertEqual(send.call_count, 3)

    def test_readiness_waits_for_processed_input(self):
        driver = NativeInput(None, None, None, None, [])
        with patch.object(driver, "observe", side_effect=[
            {"processed": 0, "ready": 1, "weapon": 2},
            {"processed": 1, "ready": 0, "weapon": 2},
            {"processed": 1, "ready": 1, "weapon": 1},
            {"processed": 1, "ready": 1, "weapon": 2},
        ]) as observe:
            self.assertEqual(driver.ready(2)["weapon"], 2)
            self.assertEqual(observe.call_count, 4)

    def test_water_current_does_not_require_a_stationary_world_position(self):
        driver = NativeInput(None, None, None, None, [])
        state = {"processed": 1, "forward": 0, "water": 2, "map": "e1m1b", "cmd": 100, "pos": (0, 0, 0)}
        with patch.object(driver, "issue"), patch.object(driver, "observe", return_value=state):
            self.assertEqual(driver.stop_forward(), state)

    def test_failed_attack_still_releases_input_and_does_not_pass(self):
        driver = NativeInput(None, None, None, None, [])
        with patch.object(driver, "ready", return_value={"event": 0, "fire": -1}), \
             patch.object(driver, "issue") as issue, \
             patch.object(driver, "until", side_effect=[TimeoutError("no attack"), {"buttons": 0}]):
            with self.assertRaises(TimeoutError):
                driver.fire()
            self.assertEqual([call.args[0] for call in issue.call_args_list], ["+attack", "-attack"])

    def test_observation_waits_for_connection_event_during_map_handoff(self):
        driver = NativeInput(None, None, None, None, [])
        with patch.object(driver, "_observe_once", side_effect=[
            ({"connecting": 1}, 40), ({"processed": 1, "map": "e1m1a"}, 90),
        ]) as observe, patch("runtime_input.wait") as wait:
            self.assertEqual(driver.observe()["map"], "e1m1a")
            self.assertEqual(observe.call_count, 2)
            event = wait.call_args.args[2]
            self.assertFalse(event(" " * 40 + "loading"))
            self.assertTrue(event(" " * 40 + "dk3 zig: player entered isolated movement runtime"))

    def test_vertical_aim_waits_for_the_reachable_movement_pitch(self):
        driver = NativeInput(None, None, None, None, [])
        with patch.object(driver, "issue") as issue, patch.object(driver, "until") as until:
            driver.aim(0, -90)
            self.assertEqual(issue.call_args.args[0], "dk3_look 0 -87.890625")
            predicate = until.call_args.args[0]
            self.assertFalse(predicate({"angles": (0, 0, 0)}))
            self.assertTrue(predicate({"angles": (-87.891, 0, 0)}))

    def test_release_does_not_acknowledge_a_player_still_sliding(self):
        driver = NativeInput(None, None, None, None, [])
        observations = [
            {"processed": 1, "forward": 0, "map": "e1m1b", "cmd": 100, "pos": (0, 0, 0)},
            {"processed": 1, "forward": 0, "map": "e1m1b", "cmd": 150, "pos": (12, 0, 0)},
            {"processed": 1, "forward": 0, "map": "e1m1b", "cmd": 200, "pos": (16, 0, 0)},
            {"processed": 1, "forward": 0, "map": "e1m1b", "cmd": 250, "pos": (16, 0, 0)},
        ]
        with patch.object(driver, "issue"), patch.object(driver, "observe", side_effect=observations) as observe:
            self.assertEqual(driver.stop_forward()["cmd"], 250)
            self.assertEqual(observe.call_count, 4)
