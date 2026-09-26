"""Asset-free regressions for native trigger contact and shared inventory rules."""
from pathlib import Path
import os
import tempfile
import unittest

from tests.support import REPO_ROOT, run_guarded


class GameplayContractsTest(unittest.TestCase):
    def weapons_object(self, temporary):
        output = str(Path(temporary) / 'weapons.o')
        command = [os.environ.get('ZIG', 'zig'), 'build-obj', 'src/weapons/module.zig',
                   '-O', 'ReleaseSafe', '-ffunction-sections', '-lc', '-Iengine/ioquake3/code/qcommon',
                   '-Iengine/ioquake3/code/game', '-Isrc/shared', '-Isrc/game', '-femit-bin=' + output]
        result = run_guarded(command, REPO_ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return output

    def test_native_contracts(self):
        root = Path(REPO_ROOT)
        with tempfile.TemporaryDirectory(prefix='dk3-gameplay-') as temporary:
            output = str(Path(temporary) / 'contracts')
            weapons = self.weapons_object(temporary)
            command = [os.environ.get('ZIG', 'zig'), 'cc', '-std=gnu99', '-O1',
                       '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
                       '-DDK3_GAME', '-Iengine/ioquake3/code/game', '-Isrc/game', '-Isrc/shared',
                       'dkq3/tools/tests/fixtures/gameplay_contracts.c',
                       'src/game/dk_interactions.c',
                       'src/shared/dk_inventory.c', weapons, '-lm', '-o', output]
            result = run_guarded(command, root)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = run_guarded([output], root)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_actor_timing_and_witnesses(self):
        with tempfile.TemporaryDirectory(prefix='dk3-actor-timing-') as temporary:
            output = str(Path(temporary) / 'actors')
            command = [os.environ.get('ZIG', 'zig'), 'cc', '-std=gnu99', '-O1',
                       '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
                       '-DDK3_GAME', '-Iengine/ioquake3/code/game', '-Isrc/game', '-Isrc/shared',
                       'dkq3/tools/tests/fixtures/actor_timing.c',
                       'engine/ioquake3/code/qcommon/q_math.c',
                       'engine/ioquake3/code/qcommon/q_shared.c', '-lm', '-o', output]
            result = run_guarded(command, REPO_ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = run_guarded([output], REPO_ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_crouch_clearance(self):
        with tempfile.TemporaryDirectory(prefix='dk3-crouch-') as temporary:
            output = str(Path(temporary) / 'crouch')
            command = [os.environ.get('ZIG', 'zig'), 'cc', '-std=gnu99', '-O1',
                       '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
                       'dkq3/tools/tests/fixtures/crouch_clearance.c', '-lm', '-o', output]
            result = run_guarded(command, REPO_ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = run_guarded([output], REPO_ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_mover_attachment_teleports(self):
        with tempfile.TemporaryDirectory(prefix='dk3-attachments-') as temporary:
            output = str(Path(temporary) / 'attachments')
            command = [os.environ.get('ZIG', 'zig'), 'cc', '-std=gnu99', '-O1',
                       '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
                       '-DDK3_GAME', '-Iengine/ioquake3/code/game', '-Isrc/game', '-Isrc/shared',
                       'dkq3/tools/tests/fixtures/mover_attachments.c', '-lm', '-o', output]
            result = run_guarded(command, REPO_ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = run_guarded([output], REPO_ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_named_script_targets(self):
        with tempfile.TemporaryDirectory(prefix='dk3-targets-') as temporary:
            output = str(Path(temporary) / 'targets')
            command = [os.environ.get('ZIG', 'zig'), 'cc', '-std=gnu99', '-O1',
                       '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
                       '-DDK3_GAME', '-Iengine/ioquake3/code/game', '-Isrc/game', '-Isrc/shared',
                       'dkq3/tools/tests/fixtures/named_script_targets.c', '-lm', '-o', output]
            result = run_guarded(command, REPO_ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = run_guarded([output], REPO_ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_weapon_sequences(self):
        with tempfile.TemporaryDirectory(prefix='dk3-weapons-') as temporary:
            output = str(Path(temporary) / 'sequences')
            weapons = self.weapons_object(temporary)
            command = [os.environ.get('ZIG', 'zig'), 'cc', '-std=gnu99', '-O1',
                       '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
                       '-DDK3_GAME', '-Iengine/ioquake3/code/game', '-Isrc/game', '-Isrc/shared',
                       'dkq3/tools/tests/fixtures/weapon_sequences.c',
                       'src/shared/dk_inventory.c', 'engine/ioquake3/code/qcommon/q_math.c',
                       'engine/ioquake3/code/qcommon/q_shared.c', weapons, '-lm', '-o', output]
            result = run_guarded(command, REPO_ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = run_guarded([output], REPO_ROOT)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
