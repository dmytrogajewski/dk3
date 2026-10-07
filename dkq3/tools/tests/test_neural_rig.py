# SPDX-License-Identifier: GPL-2.0-or-later
import unittest
import tempfile
import hashlib
from unittest.mock import patch
from pathlib import Path
import numpy as np
import neural_assets as assets
import neural_rig as rig
import skeletal_iqm as sk
from neural_reweight import patch_weights
from neural_human_motion import human_clips


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
                    if (phase+offset) % 1 < .4:
                        foot = model.names.index('foot_'+side)
                        self.assertAlmostEqual(actual[foot, 2, 3], bind[foot, 2, 3], places=5, msg=name)

    def test_running_has_flight_and_opposed_arm_swing_with_stable_weapon_axes(self):
        for name in rig.LANDMARKS:
            model = self.model()
            bind = rig.skeleton(model, name)
            run = np.array([rig.pose(model, bind, f/100, 'run', 'relaxed') for f in range(100)])
            walk = np.array([rig.pose(model, bind, f/100, 'walk', 'relaxed') for f in range(100)])
            for poses, flight_expected in ((run, True), (walk, False)):
                world = sk.matrices(poses, model.parents)
                feet = [model.names.index('foot_'+s) for s in ('l', 'r')]
                lifted = (world[:, feet, 2, 3] > bind[feet, 2, 3]+.1).all(axis=1)
                self.assertEqual(bool(lifted.any()), flight_expected, name)
                hands = [model.names.index('hand_'+s) for s in ('l', 'r')]
                self.assertLess(np.corrcoef(world[:, hands, 0, 3].T)[0, 1], -.8, name)
                weapon = world[:, model.names.index('tag_weapon'), :3, :3]
                np.testing.assert_allclose(weapon, np.broadcast_to(np.eye(3), weapon.shape), atol=1e-5)

    def test_wrist_fit_rejects_inversion_but_retains_a_small_gesture(self):
        neutral = np.eye(3)[None]
        for angle in (20, 170):
            desired = rig.rotation(1, np.deg2rad(angle))[None]
            actual = assets.wrist_rotation(neutral, desired, np.array([0., 0, -1]))
            bend = np.rad2deg(np.arccos(np.clip(actual[0, 2, 2], -1, 1)))
            self.assertAlmostEqual(bend, min(angle, 35), places=5)

    def test_npc_motion_keeps_scaled_bind_weights_and_authored_attack_frames(self):
        model = self.model()
        rig.skeleton(model, 'hiro')
        model.bind[:, :3] *= 2
        model.bind[0, :3] += [10, 0, 20]
        model.frames = np.repeat(model.bind[None], 24, axis=0)
        metadata = dict(sequences=dict(frame_data=[
            dict(animation_name='runa',first=0,last=15),dict(animation_name='ataka',first=16,last=23)]))
        result, mapping = human_clips(model, metadata, rig.LANDMARKS['hiro'], 'relaxed')
        np.testing.assert_array_equal(result.bind, model.bind)
        np.testing.assert_array_equal(result.frames[16:24], model.frames[16:24])
        for kind in model.arrays: np.testing.assert_array_equal(result.arrays[kind], model.arrays[kind])
        self.assertEqual(mapping[0]['rate'], 30)
        self.assertEqual(mapping[0]['playback_last']-mapping[0]['playback_first']+1, 15)

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
        self.assertEqual(len(model.frames), 65)
        self.assertEqual(mapping[0]['playback_first'], mapping[1]['playback_first'])

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

    def test_shared_run_blocks_preserve_each_grip_and_attack_phase_after_serialization(self):
        model = self.model()
        rig.skeleton(model, 'hiro')
        model.frames = np.repeat(model.bind[None], 7, axis=0)
        shin, hand = (model.names.index(n) for n in ('shin_l', 'hand_r'))
        model.frames[:3, shin, 0] = [10, 20, 30]
        model.frames[3:, hand, 0] = [40, 50, 60, 70]
        clips = {n: dict(first=0, count=3, fps=30, loop=3)
                 for n in ('LEGS_IDLE', 'LEGS_RUN', 'TORSO_STAND')}
        clips['TORSO_STAND_PISTOL'] = dict(first=3, count=1, fps=30, loop=0)
        clips['TORSO_STAND_RIFLE'] = dict(first=5, count=1, fps=30, loop=0)
        clips['TORSO_ATTACK_PISTOL'] = dict(first=3, count=2, fps=30, loop=0)
        clips['TORSO_ATTACK_RIFLE'] = dict(first=5, count=2, fps=30, loop=0)
        metadata = dict(frames=list(range(12)), sequences=dict(frame_data=[
            dict(animation_name=name, first=i*4, last=i*4+3)
            for i, name in enumerate(('runa', 'runb', 'runa'))]))
        rows = assets.gameplay(model, metadata, clips)
        actual = sk.read(sk.write(model))
        self.assertEqual(rows[0]['playback_first'], rows[2]['playback_first'])
        self.assertEqual(rows[0]['attack_first'], rows[2]['attack_first'])
        self.assertNotEqual(rows[0]['playback_first'], rows[1]['playback_first'])
        self.assertEqual(len(actual.frames), 30)
        for row, grip in zip(rows, (40, 60, 40)):
            for leg in range(3):
                pose = actual.frames[row['playback_first']+leg]
                self.assertAlmostEqual(pose[shin, 0], [10, 20, 30][leg], delta=.004)
                self.assertAlmostEqual(pose[hand, 0], grip, delta=.004)
                for attack in range(2):
                    layered = actual.frames[row['attack_first']+attack*3+leg]
                    self.assertAlmostEqual(layered[shin, 0], [10, 20, 30][leg], delta=.004)
                    self.assertAlmostEqual(layered[hand, 0], grip+attack*10, delta=.004)

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

    def test_held_weapon_keeps_authored_turn_with_a_translated_replacement_hand(self):
        model=self.model()
        model.names.append('hand_r');model.parents.append(0)
        model.bind=np.concatenate((model.bind,model.bind))
        model.frames=np.repeat(model.bind[None],2,axis=0)
        model.frames[:,1,0]=[10,13]
        rest=np.array([[0.,0,0],[4,0,0],[0,1,0],[0,0,1]])
        turn=rig.rotation(2,np.pi/2)
        posed=np.stack((rest,rest@turn.T))
        prop=dict(name='sword',material='skins/sword',points=posed,
                  uv=np.zeros((4,2)),normals=np.tile([0.,0,1],(2,4,1)),
                  tri=np.array([[0,1,2],[0,3,1]]))
        source=np.tile(np.eye(4),(2,2,1,1))
        assets.attach_props(model,[prop],source)
        actual=sk.skin(sk.read(sk.write(model)))[:,-4:]
        np.testing.assert_allclose(actual[1,1]-actual[1,0],[0,4,0],atol=.004)
        np.testing.assert_allclose(actual[0,1]-actual[0,0],[4,0,0],atol=.004)
        # The held grip follows the new hand rather than the source origin.
        self.assertGreater(actual[1,:,0].mean(),actual[0,:,0].mean())

    def test_long_staff_grip_uses_surface_between_sparse_vertices(self):
        model=self.model();model.names.append('hand_r');model.parents.append(0)
        model.bind=np.concatenate((model.bind,model.bind));model.frames=np.repeat(model.bind[None],2,axis=0)
        model.frames[:,1,0]=[10,13]
        rest=np.array([[0.,-.3,-24],[0,.3,-24],[0,.3,24],[0,-.3,24]])
        prop=dict(name='staff',material='skins/staff',points=np.repeat(rest[None],2,axis=0),uv=np.zeros((4,2)),normals=np.tile([1.,0,0],(2,4,1)),tri=np.array([[0,1,2],[0,2,3]]))
        assets.attach_props(model,[prop],np.tile(np.eye(4),(2,2,1,1)))
        self.assertEqual(model.parents[-1],model.names.index('hand_r'))
        actual=sk.skin(sk.read(sk.write(model)))[:,-4:]
        np.testing.assert_allclose(actual[:,:,2].mean(1),-1.8,atol=.004)
        np.testing.assert_allclose(actual[1]-actual[0],np.tile([3.,0,0],(4,1)),atol=.004)

    def test_staff_reference_grip_does_not_move_to_end_during_a_fall(self):
        model=self.model();model.names.append('hand_r');model.parents.append(0)
        model.bind=np.concatenate((model.bind,model.bind));model.frames=np.repeat(model.bind[None],2,axis=0)
        model.frames[:,1,0]=[10,13]
        rest=np.array([[0.,-.3,-24],[0,.3,-24],[0,.3,24],[0,-.3,24]])
        prop=dict(name='staff',material='skins/staff',points=np.repeat(rest[None],2,axis=0),uv=np.zeros((4,2)),normals=np.tile([1.,0,0],(2,4,1)),tri=np.array([[0,1,2],[0,2,3]]))
        source=np.tile(np.eye(4),(2,2,1,1))
        source[0,1,:3,3]=[1,0,0]
        source[1,1,:3,3]=[0,0,-24]
        assets.attach_props(model,[prop],source,reference_frame=0)
        actual=sk.skin(sk.read(sk.write(model)))[:,-4:]
        np.testing.assert_allclose(actual[:,:,2].mean(1),-1.8,atol=.004)

    def test_standing_initial_pose_survives_a_majority_of_fallen_frames(self):
        corners=np.array([[x,y,z] for x in (-1.,1.) for y in (-1.,1.) for z in (-1.,1.)])
        points=np.concatenate([corners*3+center for center in ([0,0,28],[0,0,18],[0,0,8],[0,5,-21],[0,-5,-21])])
        model=self.model();count=len(points)
        model.arrays={0:points,1:np.zeros((count,2)),2:np.tile([0.,0,1],(count,1)),
                      4:np.zeros((count,4),int),5:np.tile([255,0,0,0],(count,1))}
        model.meshes=[('body','body',0,count,0,1)];rig.skeleton(model,'hiro')
        posed=np.repeat(points[None],5,axis=0)
        posed[1:]=points@rig.rotation(1,np.pi/2).T
        surface=dict(name='body',material='skins/body',points=posed,uv=np.zeros((count,2)),normals=np.tile([0.,0,1],(5,count,1)),tri=np.array([[0,1,2]]))
        result=assets.cinematic(model,[surface],{})
        actual=sk.matrices(sk.read(sk.write(model)).frames,model.parents)
        self.assertEqual(result['reference_frame'],0)
        head,pelvis=(model.names.index(n) for n in ('head','pelvis'))
        self.assertGreater(actual[0,head,2,3]-actual[0,pelvis,2,3],15)

    def test_pinned_standing_reference_retains_size_when_most_frames_are_crouched(self):
        corners=np.array([[x,y,z] for x in (-1.,1.) for y in (-1.,1.) for z in (-1.,1.)])
        points=np.concatenate([corners*3+center for center in ([0,0,28],[0,0,18],[0,0,8],[0,5,-21],[0,-5,-21])])
        model=self.model();count=len(points)
        model.arrays={0:points,1:np.zeros((count,2)),2:np.tile([0.,0,1],(count,1)),
                      4:np.zeros((count,4),int),5:np.tile([255,0,0,0],(count,1))}
        model.meshes=[('body','body',0,count,0,1)];rig.skeleton(model,'hiro')
        posed=np.repeat(points[None],5,axis=0);posed[:,:,2]*=.55;posed[2]=points
        surface=dict(name='body',material='skins/body',points=posed,uv=np.zeros((count,2)),normals=np.tile([0.,0,1],(5,count,1)),tri=np.array([[0,1,2]]))
        metadata=dict(model='reviewed-reference',sequences=dict(frame_data=[]))
        receipt=dict(frame=2,points_sha256=hashlib.sha256(posed.astype('<f8').tobytes()).hexdigest())
        with patch.dict(assets.CINEMATIC_REFERENCES,{'reviewed-reference':receipt}):
            result=assets.cinematic(model,[surface],{},metadata=metadata)
            self.assertEqual(result['reference_frame'],2)
            self.assertAlmostEqual(result['scale'],1.)
            self.assertFalse(result['reference_landmarks'])
            surface['points'][0,0,0]+=.25
            with self.assertRaisesRegex(ValueError,'different source geometry'):
                assets.cinematic(self.model(),[surface],{},metadata=metadata)

    def test_anatomical_spine_support_excludes_a_moving_nearby_wrist(self):
        corners=np.array([[x,y,z] for x in (-1.,1.) for y in (-1.,1.) for z in (-1.,1.)])
        torso=corners*3+[0,0,18]
        wrist=corners+[4,0,17]
        points=np.concatenate([corners*3+[0,0,28],torso,corners*3+[0,0,8],
                               corners*3+[0,5,-21],corners*3+[0,-5,-21],wrist])
        model=self.model();count=len(points)
        model.arrays={0:points,1:np.zeros((count,2)),2:np.tile([0.,0,1],(count,1)),
                      4:np.zeros((count,4),int),5:np.tile([255,0,0,0],(count,1))}
        model.meshes=[('body','body',0,count,0,1)];rig.skeleton(model,'hiro')
        posed=np.repeat(points[None],2,axis=0)
        posed[1,-8:]=(wrist-[4,0,17])@rig.rotation(1,np.pi/2).T+[4,0,17]
        surface=dict(name='body',material='skins/body',points=posed,uv=np.zeros((count,2)),
                     normals=np.tile([0.,0,1],(2,count,1)),tri=np.array([[0,1,2]]))
        _,unique=np.unique(points,axis=0,return_index=True)
        support=np.flatnonzero((unique>=8)&(unique<16)).tolist()
        receipt=dict(frame=0,points_sha256=hashlib.sha256(posed.astype('<f8').tobytes()).hexdigest(),
                     joint_vertices=dict(spine=support))
        metadata=dict(model='reviewed-spine',sequences=dict(frame_data=[]))
        with patch.dict(assets.CINEMATIC_REFERENCES,{'reviewed-spine':receipt}):
            assets.cinematic(model,[surface],{},metadata=metadata)
        actual=sk.matrices(sk.read(sk.write(model)).frames,model.parents)
        spine=model.names.index('spine')
        np.testing.assert_allclose(actual[1,spine,:3,:3],actual[0,spine,:3,:3],atol=.001)

    def test_reviewed_short_blades_preserve_source_mesh_and_reject_topology_drift(self):
        points=np.arange(27,dtype=float).reshape(9,3)
        surface=dict(name='body',material='skins/actor',points=np.repeat(points[None],2,axis=0),
                     uv=np.arange(18,dtype=float).reshape(9,2)/18,normals=np.tile([0.,0,1],(2,9,1)),
                     tri=np.array([[0,1,2],[3,4,5],[6,7,8]]))
        digest=hashlib.sha256(surface['tri'].astype('<u4').tobytes()+surface['uv'].astype('<f4').tobytes()).hexdigest()
        with patch.dict(assets.CINEMATIC_PROP_TOPOLOGY,{'reviewed-blades':dict(sha256=digest,ranges=((1,3),))}):
            body,weapon=assets.source_props([surface],dict(model='reviewed-blades'))
            self.assertFalse(body['prop']);self.assertTrue(weapon['prop'])
            np.testing.assert_array_equal(weapon['points'][:,weapon['tri']],surface['points'][:,surface['tri'][1:]])
            np.testing.assert_array_equal(weapon['uv'][weapon['tri']],surface['uv'][surface['tri'][1:]])
            surface['uv'][0,0]+=.01
            with self.assertRaisesRegex(ValueError,'topology changed'):
                assets.source_props([surface],dict(model='reviewed-blades'))

    def test_quantized_hidden_staff_is_separated_and_remains_hidden(self):
        rest=np.array([[0.,-.3,-24],[0,.3,-24],[0,.3,24],[0,-.3,24]])
        hidden=rest*.002
        prop=dict(name='staff',material='skins/body',points=np.stack((hidden,rest)),uv=np.zeros((4,2)),normals=np.tile([1.,0,0],(2,4,1)),tri=np.array([[0,1,2],[0,2,3]]))
        pieces=assets.split_hidden_props([prop]);self.assertTrue(pieces[0]['prop'])
        model=self.model();model.frames=np.repeat(model.bind[None],2,axis=0)
        assets.append_prop(model,pieces[0]);actual=sk.skin(sk.read(sk.write(model)))[:,-4:]
        np.testing.assert_allclose(np.ptp(actual[0],axis=0),0,atol=.004)
        self.assertAlmostEqual(float(np.ptp(actual[1,:,2])),48,delta=.004)

    def test_original_head_surface_is_independent_of_an_arm_gesture(self):
        corners=np.array([[x,y,z] for x in (-1.,1.) for y in (-1.,1.) for z in (-1.,1.)])
        head=np.concatenate((corners*[3,3,4]+[0,0,28],corners*[2,2,3]+[0,0,28]))
        body=np.concatenate([corners*3+center for center in ([0,0,18],[0,0,8],[0,5,-21],[0,-5,-21])])
        arm=corners*2+[0,12,6]
        model=self.model();points=np.concatenate((head,body,arm));count=len(points)
        model.arrays={0:points,1:np.zeros((count,2)),2:np.tile([0.,0,1],(count,1)),
                      4:np.zeros((count,4),int),5:np.tile([255,0,0,0],(count,1))}
        model.meshes=[('body','body',0,count,0,1)];model.triangles=np.array([[0,1,2]])
        rig.skeleton(model,'hiro');model.frames=np.repeat(model.bind[None],3,axis=0)
        surfaces=[]
        for name,part in [('head',head),('body',body),('arm',arm)]:
            posed=np.repeat(part[None],3,axis=0)
            if name=='arm':posed[1:]+=np.array([[[8.,-5,10]],[[12.,-8,20]]])
            surfaces.append(dict(name=name,material='skins/'+name,points=posed,uv=np.zeros((len(part),2)),
                                 normals=np.tile([0.,0,1],(3,len(part),1)),tri=np.array([[0,1,2]])))
        result=assets.cinematic(model,surfaces,{},metadata=dict(sequences=dict(frame_data=[dict(animation_name='c_standamb',first=0,last=2)])))
        actual=sk.matrices(sk.read(sk.write(model)).frames,model.parents)
        head_index=model.names.index('head')
        np.testing.assert_allclose(actual[:,head_index,:3,:3],np.repeat(np.eye(3)[None],3,axis=0),atol=.004)
        self.assertEqual(result['reference_frame'],0)
        self.assertEqual(result['source_head_vertices'],len(head))
