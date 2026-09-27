# SPDX-License-Identifier: GPL-2.0-or-later
import unittest
from unittest.mock import patch

from runtime_input import NativeInput


class NativeInputTests(unittest.TestCase):
    def test_campaign_driver_rejects_mutation_and_command_chaining(self):
        driver = NativeInput(None, None, None, None, [])
        with patch("runtime_input.send") as send:
            for command in ("devmap e1m1b", "dk3_runtime_equip 26", "give all",
                            "dk3_runtime_place 0 0 0", "weapon 2; give all", "weapon 2\ngive all"):
                with self.assertRaises(ValueError):
                    driver.issue(command)
            send.assert_not_called()
            driver.issue("+forward")
            driver.issue("dk3_look 90 -12")
            self.assertEqual(send.call_count, 2)

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
