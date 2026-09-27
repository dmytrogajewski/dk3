# SPDX-License-Identifier: GPL-2.0-or-later
import unittest
from unittest.mock import patch

from runtime_input import NativeInput
from runtime_arena_combat import evade


class NativeInputTests(unittest.TestCase):
    def test_server_disconnect_invalidates_save_and_load_before_completion(self):
        driver = NativeInput(None, None, None, None, [])
        fatal = "Client Hiro dropped: Server command overflow"
        for action in (driver.save, driver.load):
            with self.subTest(action=action.__name__), patch.object(driver, "text", return_value="prior\n"), \
                 patch.object(driver, "issue"), patch("runtime_input.wait", return_value="prior\n" + fatal) as wait:
                with self.assertRaisesRegex(RuntimeError, "Server command overflow"):
                    action("encounter")
                self.assertTrue(wait.call_args.args[2]("prior\n" + fatal))

    def test_client_crash_is_reported_instead_of_waiting_for_an_absent_server(self):
        driver = NativeInput(None, None, None, None, [])
        fatal = "ERROR: Zig client: InvalidImpactEvent"
        with patch.object(driver, "text", return_value=fatal + "\nnative menus initialized\n"), \
             patch.object(driver, "issue") as issue:
            with self.assertRaisesRegex(RuntimeError, "InvalidImpactEvent"):
                driver.observe()
            issue.assert_not_called()
        with patch.object(driver, "text", return_value="prior\n"), \
             patch.object(driver, "issue"), patch("runtime_input.wait", return_value="prior\n" + fatal) as wait:
            with self.assertRaisesRegex(RuntimeError, "InvalidImpactEvent"):
                driver.observe()
            self.assertTrue(wait.call_args.args[2]("prior\n" + fatal))

    def test_splash_dodge_accounts_for_time_needed_to_reach_cover(self):
        corners = ((-896, 500), (-720, 500), (-720, 780), (-896, 780))
        self.assertEqual(evade((-896, 500, 984), corners, [(1.5, (-896, 500))]), (-720, 780))
        # An imminent hit cannot be avoided by pretending the far corner was
        # reached instantly. A crossing route through its impact is rejected.
        chosen = evade((-810, 640, 984), corners, [(0.3, (-820, 610)), (1.0, (-720, 780))])
        self.assertEqual(chosen, (-896, 780))

    def test_movement_clock_excludes_diagnostics_and_world_restoration(self):
        driver = NativeInput(None, None, None, None, [])
        # Only confirmed forward intervals in one live world count as a stall.
        samples = [
            ("e1m1a", "normal", 0, 100),
            ("e1m1a", "normal", 127, 200),
            ("e1m1a", "normal", 127, 300),
            ("e1m1a", "normal", 0, 400),
            ("e1m1a", "normal", 0, 10000),
            ("e1m1a", "normal", 127, 10100),
            ("e1m1b", "normal", 127, 10200),
            ("e1m1b", "frozen", 127, 10300),
            ("e1m1b", "normal", 127, 10400),
            ("e1m1b", "normal", 127, 100),  # Restored command clock.
            ("e1m1b", "normal", 127, 200),
        ]
        with patch.object(driver, "_observe_once", side_effect=[
            ({"map": name, "mode": mode, "forward": forward, "cmd": cmd}, 0)
            for name, mode, forward, cmd in samples
        ]):
            for _ in samples:
                driver.observe()
        self.assertEqual(driver.forward_ms, 200)

    def test_save_and_load_refusals_end_the_wait_without_claiming_completion(self):
        driver = NativeInput(None, None, None, None, [])
        for action in (driver.save, driver.load):
            with self.subTest(action=action.__name__), patch.object(driver, "text", return_value="prior\n"), \
                 patch.object(driver, "issue"), patch("runtime_input.wait", return_value="prior\nSave/load refused: CannotSaveDeadPlayer\n") as wait:
                with self.assertRaisesRegex(RuntimeError, "Save/load refused"):
                    action("encounter")
                self.assertTrue(wait.call_args.args[2]("prior\nSave/load refused: CannotSaveDeadPlayer\n"))

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


class RuntimeGenerationTests(unittest.TestCase):
    def test_staging_rejects_a_module_changed_after_identity_was_recorded(self):
        import hashlib
        import json
        from pathlib import Path
        import tempfile
        from runtime_input import record_identity
        from runtime_probe import stage_client_modules
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            engine, prefix, report = root / 'installed', root / 'building', root / 'report'
            (engine / 'bin').mkdir(parents=True)
            (engine / 'bin/dk3').write_bytes(b'engine')
            report.mkdir()
            records = {}
            for name in ('qagame.so', 'cgame.so', 'ui.so', 'scripts/dk3-projectile-weather.shader'):
                installed = engine / 'share/dk3' / name
                installed.parent.mkdir(parents=True, exist_ok=True)
                installed.write_text(name)
                source = prefix / ('lib/dk3' if name.endswith('.so') else 'share/dk3') / name
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_text(name)
                records['share/dk3/' + name] = hashlib.sha256(name.encode()).hexdigest()
            (engine / 'installation.json').write_text(json.dumps({'files': records}))
            record_identity(engine, prefix, report, require_installation=True)
            (prefix / 'lib/dk3/cgame.so').write_bytes(b'next build')
            with self.assertRaisesRegex(RuntimeError, 'Staged runtime changed'):
                stage_client_modules(prefix, root / 'rejected', installation=engine)
            with self.assertRaisesRegex(RuntimeError, 'runtime differs'):
                record_identity(engine, prefix, report, require_installation=True)
            # The immutable generation remains usable while a new one builds.
            stage_client_modules(engine, root / 'accepted', installation=engine)
            self.assertEqual((root / 'accepted/dk3/cgame.so').read_bytes(), b'cgame.so')
