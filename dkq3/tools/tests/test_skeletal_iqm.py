# SPDX-License-Identifier: GPL-2.0-or-later
"""Asset animation checks with generated geometry and analytically known motion."""
import unittest
import struct

import numpy as np

import neural_assets
import skeletal_iqm as sk
import iqm


class SkeletalTest(unittest.TestCase):
    def fixture(self):
        pose = np.array([[0., 0, 0, 0, 0, 0, 1, 1, 1, 1],
                         [2., 0, 0, 0, 0, 0, 1, 1, 1, 1]])
        frames = np.repeat(pose[None], 3, axis=0)
        frames[1, 0, 3:7] = [0, 0, np.sqrt(.5), np.sqrt(.5)]
        frames[2, 0, 3:7] = [0, 0, 1, 0]
        frames[:, 0, 0] = [0, 4, 8]
        return sk.Model({0: np.array([[2., 0, 0], [3, 0, 0], [2, 1, 0]]),
                         1: np.zeros((3, 2)), 2: np.tile([0., 0, 1], (3, 1)),
                         4: np.tile([1, 0, 0, 0], (3, 1)), 5: np.tile([255, 0, 0, 0], (3, 1))},
                        [('body', 'models/neural/test/body', 0, 3, 0, 1)], np.array([[0, 1, 2]]),
                        ['root', 'hp_gun'], [-1, 0], pose, frames)

    def test_skeletal_file_preserves_rotating_child_and_attachment(self):
        model = self.fixture()
        encoded = sk.write(model)
        decoded = sk.read(encoded)
        points = sk.skin(decoded)
        np.testing.assert_allclose(points[:, 0], [[2, 0, 0], [4, 2, 0], [6, 0, 0]], atol=.002)
        tags = sk.matrices(decoded.frames, decoded.parents)[:, 1, :3, 3]
        np.testing.assert_allclose(tags, points[:, 0], atol=.002)
        np.testing.assert_allclose(sk.matrices(sk.channels(sk.matrices(model.frames, model.parents), model.parents), model.parents),
                                   sk.matrices(model.frames, model.parents), atol=1e-6)
        header = dict(zip((k for k, _ in iqm.HEADER_FIELDS), iqm.HEADER.unpack_from(encoded)))
        for f, frame in enumerate(points):
            box = struct.unpack_from('<8f', encoded, header['ofs_bounds'] + f*32)
            self.assertTrue((frame >= np.array(box[:3]) - .002).all())
            self.assertTrue((frame <= np.array(box[3:6]) + .002).all())

    def test_raised_hand_does_not_set_body_scale_or_stretch_bones(self):
        model = self.fixture()
        model.arrays[0][:, 2] = [0, 1, 3]
        source = np.concatenate((model.arrays[0], [[2.2, .1, 1]]))
        poses = np.repeat(source[None], 10, axis=0)
        poses[5, 1, 2] = 9  # A single raised limb, not a taller body.
        detail = neural_assets.cinematic(model, [dict(material='skins/body', points=poses,
                                                     tri=np.array([[0, 1, 2], [0, 1, 3], [0, 2, 3], [1, 2, 3]]))], {})
        self.assertNotEqual(detail['reference_frame'], 5)
        self.assertAlmostEqual(detail['scale'], 1.)
        for joint, parent in enumerate(model.parents):
            if parent >= 0:
                np.testing.assert_allclose(model.frames[:, joint, :3], np.tile(model.bind[joint, :3], (10, 1)), atol=1e-6)

    def test_two_bone_retarget_reaches_hand_without_stretching(self):
        model = self.fixture()
        model.names = ['pelvis', 'upperarm_l', 'forearm_l', 'hand_l']
        model.parents = [-1, 0, 1, 2]
        model.bind = np.tile([0., 0, 0, 0, 0, 0, 1, 1, 1, 1], (4, 1))
        model.bind[2:, 0] = 2
        fitted = sk.matrices(model.bind, model.parents)[None]
        fitted[0, 2, :3, 3] = [1, 1, 1]
        fitted[0, 3, :3, 3] = [2, 2, 0]
        poses = neural_assets.connected_motion(model, fitted)
        actual = sk.matrices(poses, model.parents)
        np.testing.assert_allclose(actual[0, 3, :3, 3], [2, 2, 0], atol=1e-6)
        np.testing.assert_allclose(poses[0, 1:, :3], model.bind[1:, :3], atol=1e-6)

    def test_cinematic_fit_recovers_known_rigid_motion(self):
        rest = np.array([[0., 0, 0], [1, 0, 0], [0, 2, 0], [0, 0, 3]])
        rotation = np.array([[0, -1., 0], [1, 0, 0], [0, 0, 1]])
        posed = rest @ rotation.T + [7, -3, 4]
        result = neural_assets.rigid_fit(rest, np.stack((rest, posed)), np.array([1., .2, .5, 1]))
        np.testing.assert_allclose(result[0], np.eye(4), atol=1e-6)
        np.testing.assert_allclose(result[1, :3, :3], rotation, atol=1e-6)
        np.testing.assert_allclose(result[1, :3, 3], [7, -3, 4], atol=1e-6)

    def test_invalid_bone_index_is_rejected_before_packaging(self):
        model = self.fixture()
        model.arrays[4][0, 0] = 127
        with self.assertRaisesRegex(ValueError, 'skin weights'):
            sk.write(model)

    def test_cinematic_prop_appears_after_collapsed_first_frame(self):
        model = self.fixture()
        rest = np.array([[0., 0, 0], [1, 0, 0], [0, 2, 0]])
        rotation = np.array([[0, -1., 0], [1, 0, 0], [0, 0, 1]])
        posed = np.stack((np.tile([4., 5, 6], (3, 1)), rest + [2, 0, 0], rest @ rotation.T + [7, -3, 4]))
        neural_assets.append_prop(model, dict(points=posed, uv=np.array([[0., 0], [1, 0], [0, 1]]),
                                             normals=np.tile([0., 0, 1], (3, 3, 1)), tri=np.array([[0, 1, 2]]),
                                             material='skins/daikatana'))
        # Exercise quantization, bone scaling and the actual skinning contract.
        decoded = sk.read(sk.write(model))
        np.testing.assert_allclose(sk.skin(decoded)[:, -3:], posed, atol=.002)

    def test_collapsing_sword_is_separated_from_shared_body_material(self):
        body = np.array([[0., 0, 0], [1, 0, 0], [0, 0, 3]])
        hidden = np.tile([0., 0, 1], (3, 1))
        sword = np.array([[0., 0, 1], [0, 0, 5], [1, 0, 1]])
        surface = dict(name='combined', material='skins/hiro',
                       points=np.stack((np.concatenate((body, hidden)), np.concatenate((body, sword)))),
                       tri=np.array([[0, 1, 2], [3, 4, 5]]), uv=np.zeros((6, 2)),
                       normals=np.tile([0., 1, 0], (2, 6, 1)))
        parts = neural_assets.split_hidden_props([surface])
        self.assertEqual(len(parts), 2)
        self.assertFalse(parts[0]['prop'])
        self.assertTrue(parts[1]['prop'])
        np.testing.assert_array_equal(parts[0]['points'], np.stack((body, body)))
        np.testing.assert_array_equal(parts[1]['points'], np.stack((hidden, sword)))

    def test_gameplay_maps_death_crouch_attack_and_locomotion(self):
        for source, target in [('diea', 'BOTH_DEATH1'), ('cwalk', 'LEGS_WALKCR'), ('camba', 'LEGS_IDLECR'),
                               ('ataka', 'TORSO_ATTACK'), ('atakb', 'TORSO_ATTACK2'), ('runa', 'LEGS_RUN')]:
            self.assertEqual(neural_assets.clip_name(source), target)

    def test_carried_body_is_horizontal_at_gameplay_scale_and_tracks_carrier(self):
        model = self.fixture()
        model.names = ['pelvis', 'spine', 'chest', 'neck', 'head', 'thigh_l', 'shin_l', 'foot_l']
        model.parents = [-1, 0, 1, 2, 3, 0, 5, 6]
        absolute = np.tile(np.eye(4), (8, 1, 1))
        absolute[:, :3, 3] = [[0, 0, 4], [0, 0, 10], [0, 0, 16], [0, 0, 23],
                              [0, 0, 26], [0, 4, 2], [0, 4, -10], [0, 4, -22]]
        model.bind = sk.channels(absolute, model.parents)
        model.arrays[0] = np.array([[0., 0, 26], [1, 0, 26], [0, 1, 27]])
        model.arrays[4][:, 0] = 4
        surfaces = []
        for name, low, high in [('s_head', [-19, -8, 0], [-10, -3, 21]),
                                ('s_torso', [-18, -16, 4], [-1, 1, 27]),
                                ('s_legs', [-3, -14, -5], [27, 0, 28])]:
            points = np.array([[x, y, z] for x in (low[0], high[0])
                               for y in (low[1], high[1]) for z in (low[2], high[2])], float)
            surfaces.append(dict(name=name, material='skins/body', points=np.stack((points, points+[3, 0, 2])),
                                 tri=np.array([[0, 1, 2], [2, 3, 4], [4, 5, 6], [6, 7, 0]])))
        detail = neural_assets.cinematic(model, surfaces, {}, carried=True)
        self.assertEqual(detail['scale'], 1.)
        actual = sk.matrices(model.frames, model.parents)
        self.assertLess(actual[0, 4, 0, 3], actual[0, 7, 0, 3]-20)
        np.testing.assert_allclose(actual[1, :, :3, 3]-actual[0, :, :3, 3],
                                   np.tile([3., 0, 2], (8, 1)), atol=1e-6)
