# SPDX-License-Identifier: GPL-2.0-or-later
import unittest
import tempfile
from pathlib import Path
import numpy as np
import neural_assets as assets
import neural_rig as rig
import skeletal_iqm as sk
from neural_reweight import patch_weights


class RigTest(unittest.TestCase):
    def test_rigid_sections_and_local_joint_blends_preserve_motion_and_mesh(self):
        model = self.model()
        model.names = ['upperarm_l', 'forearm_l', 'hand_l', 'tag_weapon']
        model.parents = [-1, 0, 1, 2]
        model.bind = np.repeat(model.bind, 4, axis=0)
        model.bind[1:3, 0] = 10
        model.frames = np.repeat(model.bind[None], 2, axis=0)
        model.frames[1, 1, 3:7] = [0, 0, np.sin(.7), np.cos(.7)]
        # A rigid upper-arm triangle, including a UV seam duplicate, and
        # points at the elbow. The old weighting pulls even the mid-arm.
        model.arrays = {0: np.array([[4., 0, 0], [4, 1, 0], [5, 0, 0], [4, 0, 0], [10, 0, 0], [11, 0, 0], [10, 1, 0]]),
                        1: np.zeros((7, 2)), 2: np.tile([0., 0, 1], (7, 1)),
                        4: np.tile([0, 1, 2, 3], (7, 1)),
                        5: np.tile([150, 100, 5, 0], (7, 1))}
        model.meshes = [('body', 'body', 0, 7, 0, 2)]
        model.triangles = np.array([[0, 1, 2], [4, 5, 6]])
        before = sk.write(model)
        output, report = patch_weights(before)
        original, repaired = sk.read(before), sk.read(output)
        np.testing.assert_array_equal(original.frames, repaired.frames)
        np.testing.assert_array_equal(original.bind, repaired.bind)
        for kind in (0, 1, 2): np.testing.assert_array_equal(original.arrays[kind], repaired.arrays[kind])
        np.testing.assert_array_equal(original.triangles, repaired.triangles)
        self.assertEqual(report['max_influences'], 2)
        np.testing.assert_array_equal(repaired.arrays[5][0], repaired.arrays[5][3])
        self.assertTrue(np.all(repaired.arrays[5][:4, 0] == 255))
        actual = sk.skin(repaired)
        np.testing.assert_allclose(actual[:, :3], np.repeat(model.arrays[0][None, :3], 2, axis=0), atol=1e-5)
        for vertex in range(7):
            used = repaired.arrays[4][vertex][repaired.arrays[5][vertex] > 0]
            if len(used) == 2: self.assertTrue(repaired.parents[used[0]] == used[1] or repaired.parents[used[1]] == used[0])

    def test_team_colors_preserve_protected_face_and_still_tint_armor(self):
        with tempfile.TemporaryDirectory() as directory:
            texture = Path(directory)/'hiro.png'
            pixels = np.full((2, 2, 3), 160, np.uint8)
            texture.write_bytes(assets.dkimg.encode_png(pixels))
            mask = np.zeros_like(pixels)
            mask[0] = 255
            texture.with_suffix('.face-mask.png').write_bytes(assets.dkimg.encode_png(mask))
            files = assets.texture_files('hiro', texture)
            for color in range(1, 12):
                variant = Path(directory)/'variant.png'
                variant.write_bytes(files[f'models/neural/hiro/color{color}.png'])
                actual = assets.dkimg.read_png(variant)[..., :3]
                np.testing.assert_array_equal(actual[0], pixels[0])
                self.assertTrue(np.any(actual[1] != pixels[1]), color)

    def model(self):
        bind = np.array([[0., 0, 0, 0, 0, 0, 1, 1, 1, 1]])
        return sk.Model({0: np.array([[0., 0, 0], [1, 0, 0], [0, 1, 0]]),
                         1: np.zeros((3, 2)), 2: np.tile([0., 0, 1], (3, 1)),
                         4: np.zeros((3, 4), int), 5: np.tile([255, 0, 0, 0], (3, 1))},
                        [('body', 'body', 0, 3, 0, 1)], np.array([[0, 1, 2]]), ['pelvis'], [-1], bind, bind[None])

    def test_run_contacts_reach_ground_without_stretching_any_character(self):
        for name in rig.LANDMARKS:
            model = self.model()
            bind = rig.skeleton(model, name)
            for frame in range(30):
                phase = frame/30
                local = rig.pose(model, bind, phase, 'run')
                actual = sk.matrices(local, model.parents)
                self.assertTrue(np.isfinite(actual).all(), name)
                np.testing.assert_allclose(local[1:, :3], model.bind[1:, :3], atol=1e-6)
                for side, offset in (('l', 0), ('r', .5)):
                    if (phase+offset) % 1 < .5:
                        foot = model.names.index('foot_'+side)
                        self.assertAlmostEqual(actual[foot, 2, 3], bind[foot, 2, 3], places=5, msg=name)

    def test_different_source_ranges_keep_the_same_native_run_clip(self):
        model = self.model()
        rig.skeleton(model, 'hiro')
        model.frames = np.repeat(model.bind[None], 20, axis=0)
        clips = {n: dict(first=0, count=15, fps=30, loop=15) for n in ('LEGS_IDLE', 'LEGS_RUN', 'TORSO_STAND')}
        metadata = dict(frames=list(range(50)), sequences=dict(frame_data=[
            dict(animation_name='runa', first=0, last=9), dict(animation_name='runb', first=10, last=49)]))
        mapping = assets.gameplay(model, metadata, clips)
        for clip in mapping:
            self.assertEqual(clip['playback_last']-clip['playback_first']+1, 15)
            self.assertEqual(clip['rate'], 30)
        self.assertEqual(len(model.frames), 80)

    def test_leg_constraints_reject_folded_and_twisted_source_fits(self):
        for name in rig.LANDMARKS:
            model = self.model()
            bind = rig.skeleton(model, name)
            fitted = np.repeat(bind[None], 3, axis=0)
            for side in ('l', 'r'):
                hip, knee, foot = (model.names.index(n+'_'+side) for n in ('thigh', 'shin', 'foot'))
                fitted[:, foot, :3, 3] = bind[hip, :3, 3] + [[0, 0, -.01], [0, 0, -100], [0, 70, 10]]
                fitted[:, knee, :3, :3] = rig.rotation(2, np.pi)
                fitted[:, knee, :3, 3] = bind[hip, :3, 3]+[-50, 0, 0]
            local = assets.connected_motion(model, fitted)
            actual = sk.matrices(local, model.parents)
            self.assertTrue(np.isfinite(actual).all())
            np.testing.assert_allclose(local[:, 1:, :3], np.repeat(model.bind[None, 1:, :3], 3, axis=0), atol=1e-5)
            for side in ('l', 'r'):
                hip, knee, foot = (model.names.index(n+'_'+side) for n in ('thigh', 'shin', 'foot'))
                a = actual[:, knee, :3, 3]-actual[:, hip, :3, 3]
                b = actual[:, foot, :3, 3]-actual[:, knee, :3, 3]
                flex = np.rad2deg(np.arccos(np.clip((a*b).sum(1)/(np.linalg.norm(a, axis=1)*np.linalg.norm(b, axis=1)), -1, 1)))
                self.assertTrue(np.all((flex >= 2.99) & (flex <= 145.01)), (name, flex))
                self.assertTrue(np.all(a[:, 0] > -.01), (name, a))

    def test_attack_layers_keep_locomotion_and_weapon_hand_on_same_pose(self):
        model = self.model()
        bind = rig.skeleton(model, 'hiro')
        # Use distinct authored local values to expose a wrong layer/index.
        model.frames = np.repeat(model.bind[None], 5, axis=0)
        shin, hand = (model.names.index(n) for n in ('shin_l', 'hand_r'))
        model.frames[:3, shin, 0] = [10, 20, 30]
        model.frames[3:, hand, 0] = [40, 50]
        clips = {n: dict(first=0, count=3, fps=30, loop=3) for n in ('LEGS_IDLE', 'LEGS_RUN', 'TORSO_STAND')}
        clips['TORSO_ATTACK_PISTOL'] = dict(first=3, count=2, fps=30, loop=0)
        rows = assets.gameplay(model, dict(frames=list(range(4)), sequences=dict(frame_data=[dict(animation_name='runa', first=0, last=3)])), clips)
        row = rows[0]
        for attack in range(2):
            for leg in range(3):
                pose = model.frames[row['attack_first']+attack*3+leg]
                self.assertEqual(pose[shin, 0], [10, 20, 30][leg])
                self.assertEqual(pose[hand, 0], [40, 50][attack])

    def test_held_prop_follows_new_hand_and_released_prop_keeps_free_motion(self):
        model = self.model()
        model.names.append('hand_r')
        model.parents.append(0)
        model.bind = np.concatenate((model.bind, model.bind))
        model.frames = np.repeat(model.bind[None], 3, axis=0)
        model.frames[:, 1, 0] = [10, 13, 16]
        source = np.tile(np.eye(4), (3, 2, 1, 1))
        points = np.array([[0., 0, 0], [1, 0, 0], [0, 1, 0]])
        posed = points[None]+np.array([[0., 0, 0], [1, 0, 0], [100, 0, 0]])[:, None]
        prop = dict(name='sword', material='skins/sword', points=posed, uv=np.zeros((3, 2)),
                    normals=np.tile([0., 0, 1], (3, 3, 1)), tri=np.array([[0, 1, 2]]))
        assets.attach_props(model, [prop], source)
        actual = sk.skin(sk.read(sk.write(model)))[:, -3:]
        np.testing.assert_allclose(actual[1]-actual[0], np.tile([3., 0, 0], (3, 1)), atol=.004)
        np.testing.assert_allclose(actual[2], posed[2], atol=.004)

    def test_split_sword_keeps_one_grip_despite_different_visibility(self):
        model = self.model()
        model.names.append('hand_r')
        model.parents.append(0)
        model.bind = np.concatenate((model.bind, model.bind))
        model.frames = np.repeat(model.bind[None], 3, axis=0)
        model.frames[:, 1, 0] = [10, 13, 16]
        source = np.tile(np.eye(4), (3, 2, 1, 1))
        triangle = np.array([[0., 0, 0], [1, 0, 0], [0, 1, 0]])
        pieces = []
        for index in range(2):
            points = np.repeat((triangle+[0, 0, index*5])[None], 3, axis=0)
            if index == 1:
                points[2] = 0  # Hilt stays visible when the blade is hidden.
            pieces.append(dict(name=f'sword_part{index}', material='skins/sword',
                               points=points, uv=np.zeros((3, 2)),
                               normals=np.tile([0., 0, 1], (3, 3, 1)), tri=np.array([[0, 1, 2]])))
        assets.attach_props(model, pieces, source)
        actual = sk.skin(sk.read(sk.write(model)))[:, -6:]
        for frame in (0, 1):
            np.testing.assert_allclose(actual[frame, 3:]-actual[frame, :3],
                                       np.tile([0., 0, 5], (3, 1)), atol=.004)
        np.testing.assert_allclose(np.ptp(actual[2, 3:], axis=0), 0, atol=.004)
