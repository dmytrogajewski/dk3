# SPDX-License-Identifier: GPL-2.0-or-later
import copy
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import numpy as np
from scipy.spatial.transform import Rotation
import yaml

import animation_manifest as schema
import animation_motion as motion
import cinematic_author as cine
import cinematic_reconstruction as reconstruction
import neural_assets as assets
import skeletal_iqm as sk
from tests.test_animation_author import model


class MeasuredOrientationTests(unittest.TestCase):
    def test_export_discards_numerical_residuals_without_changing_source_motion(self):
        target=model();target.frames=np.repeat(target.bind[None],3,axis=0)
        clean=motion.from_model(target,0,2,30);noisy=copy.deepcopy(clean)
        noisy.world[:,:,0,3]+=np.array([0.,1e-15,-1e-15])[:,None]
        before=noisy.world.copy();source=target.frames.copy()
        a=motion.export_channels(clean);b=motion.export_channels(noisy)
        np.testing.assert_array_equal(a,b)
        np.testing.assert_array_equal(noisy.world,before)
        np.testing.assert_array_equal(target.frames,source)
        self.assertFalse(np.signbit(b[b==0]).any())
        target.frames=a;first=sk.write(target);target.frames=b
        self.assertEqual(first,sk.write(target))

    def test_semantic_landmarks_form_a_proper_frame_without_mutating_observations(self):
        points=np.array([[0.,-1,0],[0,1,0],[0,0,-1],[0,0,1]])
        before=points.copy();axes={'left':[[0],[1]],'up':[[2],[3]]}
        np.testing.assert_allclose(reconstruction.landmark_basis(points,axes),np.eye(3))
        rotated=Rotation.from_euler('z',110,degrees=True).as_matrix()
        np.testing.assert_allclose(reconstruction.landmark_basis(points@rotated.T,axes),rotated,atol=1e-12)
        np.testing.assert_array_equal(points,before)
        with self.assertRaises(schema.Error):reconstruction.landmark_basis(points,dict(axes,left=[[0],[0]]))
        with self.assertRaises(schema.Error):reconstruction.landmark_basis(points,dict(axes,up=[[[]],[1]]))

    def test_absolute_transfer_retains_the_measured_initial_head_heading(self):
        target=model();before=target.bind.copy();sample=motion.from_model(target,0,0,30)
        j=target.names.index('head');r=Rotation.from_euler('z',110,degrees=True).as_matrix()
        sample.rest[j,:3,:3]=r;sample.world[:,j,:3,:3]=r
        sample.metadata['semantic_frames']={'head':{'basis':r.tolist()}}
        bones={n:n for n in target.names if not n.startswith(('tag_','prop_','fingers_','thumb_','clavicle_'))}
        recipe=dict(bones=bones,forward='x',up='z')
        relative=motion.retarget(target,sample,dict(recipe,rotation_bones=['head']))
        absolute=motion.retarget(target,sample,dict(recipe,absolute_rotations={'head':{'forward':[1,0,0],'up':[0,0,1]}}))
        np.testing.assert_allclose(relative.world[:,j,:3,:3],np.eye(3)[None],atol=1e-10)
        np.testing.assert_allclose(absolute.world[:,j,:3,:3],r[None],atol=1e-10)
        np.testing.assert_array_equal(target.bind,before)
        del sample.metadata['semantic_frames']
        with self.assertRaises(schema.Error) as error:motion.retarget(target,sample,dict(recipe,absolute_rotations={'head':{'forward':[1,0,0],'up':[0,0,1]}}))
        self.assertEqual(error.exception.code,'ANIM_UNOBSERVABLE_MARKER')

    def test_unmapped_fingers_inherit_the_hand_instead_of_counter_rotating(self):
        target=model();target.frames=np.repeat(target.bind[None],3,axis=0);j=target.names.index('hand_l')
        target.frames[:,j,3:7]=Rotation.from_euler('y',[10,35,60],degrees=True).as_quat()
        sample=motion.from_model(target,0,2,30);bones={n:n for n in target.names if not n.startswith(('tag_','prop_','fingers_','thumb_','clavicle_'))}
        recipe=dict(bones=bones,forward='x',up='z',rotation_bones=['hand_l'],bind_bones=['fingers_l','thumb_l'])
        result=motion.retarget(target,sample,recipe)
        local=sk.channels(result.world,result.parents)
        for name in ('fingers_l','thumb_l'):
            k=target.names.index(name);np.testing.assert_allclose(local[:,k,3:7],np.repeat(target.bind[k:k+1,3:7],3,axis=0),atol=1e-10)
        with self.assertRaises(schema.Error):motion.retarget(target,sample,dict(recipe,bind_bones=['head']))

    def test_temporal_poles_reject_elbow_plane_flips_and_close_the_loop(self):
        target=model();bind=sk.matrices(target.bind,target.parents);fitted=np.repeat(bind[None],60,axis=0)
        a,b,c=(target.names.index(n) for n in ('upperarm_r','forearm_r','hand_r'))
        direction=target.bind[b,:3]+target.bind[c,:3];direction/=np.linalg.norm(direction)
        l1,l2=np.linalg.norm(target.bind[b,:3]),np.linalg.norm(target.bind[c,:3])
        axis=np.cross(direction,[1.,0,0]);axis/=np.linalg.norm(axis)
        origin=bind[a,:3,3]
        fitted[:,c,:3,3]=origin+direction*((l1+l2)*.75)
        fitted[:,b,:3,3]=origin+direction*l1+np.where(np.arange(60)%2,1.,-1.)[:,None]*axis*.05
        raw=sk.matrices(assets.connected_motion(target,fitted),target.parents)
        stable=sk.matrices(assets.connected_motion(target,fitted,temporal_poles=True,cyclic_poles=True),target.parents)
        jump=lambda w:float(motion.angle(w[1:,b,:3,:3],w[:-1,b,:3,:3]).max())
        self.assertGreater(jump(raw),45);self.assertLess(jump(stable),15)
        self.assertLess(float(motion.angle(stable[0,b,:3,:3],stable[-1,b,:3,:3])),15)
        local=sk.channels(stable,target.parents)
        np.testing.assert_allclose(local[:,b,:3],np.repeat(target.bind[b:b+1,:3],60,axis=0),atol=1e-10)


class ContactTests(unittest.TestCase):
    def test_sole_checks_detect_planted_boot_tilt_and_floor_solver_flattens_it(self):
        target=model();bind=sk.matrices(target.bind,target.parents)
        for side in ('l','r'):
            foot=target.names.index('foot_'+side);center=bind[foot,:3,3]+[0,0,-2]
            start=len(target.arrays[0]);points=center+np.array([[-1,-.5,0],[1,-.5,0],[0,.5,0]])
            additions={0:points,1:np.zeros((3,2)),2:np.tile([0,0,1],(3,1)),4:np.tile([foot,0,0,0],(3,1)),5:np.tile([255,0,0,0],(3,1))}
            for key,data in additions.items():target.arrays[key]=np.vstack((target.arrays[key],data))
            target.triangles=np.vstack((target.triangles,[start,start+1,start+2]))
        target.meshes=[('body','body',0,9,0,3)];sample=motion.from_model(target,0,0,30)
        for side in ('l','r'):
            for bone in ('foot','toe'):
                j=target.names.index(bone+'_'+side);sample.world[:,j,:3,:3]=Rotation.from_euler('y',35,degrees=True).as_matrix()@sample.world[:,j,:3,:3]
        intervals={n:[[0,0]] for n in ('foot_l','foot_r')};floor=float(target.arrays[0][:,2].min());recipe=dict(contacts=intervals,contact_floor=floor)
        raw=motion.solve_contacts(target,sample,intervals,True)
        before=motion.validate(target,raw,recipe);self.assertFalse(before['passed'])
        self.assertTrue(any(f['code']=='ANIM_ATTACHMENT_ERROR' for f in before['failures']))
        solved=motion.solve_contacts(target,sample,intervals,True,floor)
        after=motion.validate(target,solved,recipe);self.assertTrue(after['passed'])
        ids,_=motion.sole_support(target,'foot_l');local=motion.export_channels(solved)
        np.testing.assert_allclose(motion.skin_points(target,local,ids),sk.skin(target,local)[:,ids],atol=1e-10)
        with self.assertRaises(schema.Error):motion.sole_support(model(),'foot_l')

    def test_source_world_orientation_survives_changed_parent_hand_pose(self):
        target=model();motion.attach(target,'prop_staff','hand_l',[0,0,0]);target.frames=np.repeat(target.frames[:1],3,axis=0)
        prop=target.names.index('prop_staff');hand=target.names.index('hand_l')
        sample=motion.from_model(target,0,2,30);original=sample.world[:,prop,:3,:3].copy()
        sample.world[:,hand,:3,:3]=Rotation.from_euler('x',[30,50,70],degrees=True).as_matrix()
        contact=dict(prop='prop_staff',members=['prop_staff'],pivot=[0,0,0],parent='hand_l',position=[0,0,0],orientation='source_world')
        recipe=dict(source_frames=[0,2],prop_contacts=[contact]);result=motion.prop_policy(target,sample,recipe)
        np.testing.assert_allclose(result.world[:,prop,:3,:3],original,atol=1e-10)
        checked=motion.validate(target,result,recipe)
        self.assertLess(checked['metrics']['prop_orientation:prop_staff']['maximum'],.001)
        broken=copy.deepcopy(result);broken.world[:,prop,:3,:3]=Rotation.from_euler('z',20,degrees=True).as_matrix()@original
        checked=motion.validate(target,broken,recipe);self.assertFalse(checked['passed'])
        self.assertGreater(checked['metrics']['prop_orientation:prop_staff']['maximum'],19)

    def test_staff_floor_contact_solves_the_arm_and_reports_residual(self):
        target=model();motion.attach(target,'prop_staff','hand_l',[0,0,0]);sample=motion.from_model(target,0,0,30)
        prop=target.names.index('prop_staff');hand=target.names.index('hand_l');point=np.array([0.,0,-3])
        height=float((sample.world[0,hand,:3,3]+sample.world[0,prop,:3,:3]@point)[2]+.3)
        contact=dict(prop='prop_staff',members=['prop_staff'],pivot=[0,0,0],parent='hand_l',position=[0,0,0],orientation='source_world',floor_contact=dict(point=point.tolist(),height=height,max_error=.1))
        recipe=dict(source_frames=[0,0],prop_contacts=[contact]);result=motion.prop_policy(target,sample,recipe)
        checked=motion.validate(target,result,recipe);self.assertTrue(checked['passed'])
        self.assertLess(checked['metrics']['prop_floor:prop_staff']['maximum'],.1)
        self.assertGreater(result.world[0,hand,2,3]-sample.world[0,hand,2,3],.2)
        contact['orientation']='inherit'
        with self.assertRaises(schema.Error):schema.prop_contacts([contact])

    def test_grouped_grip_keeps_hidden_frames_and_relative_prop_geometry(self):
        target=model();motion.attach(target,'prop_hilt','hand_l',[9,0,0]);motion.attach(target,'prop_blade','hand_l',[12,0,0])
        target.frames=np.repeat(target.frames[:1],4,axis=0);hilt=target.names.index('prop_hilt');blade=target.names.index('prop_blade')
        target.frames[[0,3],hilt,7:10]=0;target.frames[[0,3],blade,7:10]=0
        sample=motion.from_model(target,0,3,30);before=target.frames.copy()
        contact=dict(prop='prop_hilt',members=['prop_hilt','prop_blade'],pivot=[0,0,0],parent='hand_l',position=[1,0,0],max_error=.02,finger_pose={'fingers_l':[0,-30,0]},blend_frames=2)
        recipe=dict(source_frames=[0,3],prop_contacts=[contact])
        result=motion.prop_policy(target,sample,recipe);exported=motion.export_channels(result)
        np.testing.assert_array_equal(exported[:,[hilt,blade],7:10],before[:,[hilt,blade],7:10])
        np.testing.assert_allclose(result.world[:,blade,:3,3]-result.world[:,hilt,:3,3],sample.world[:,blade,:3,3]-sample.world[:,hilt,:3,3],atol=1e-10)
        np.testing.assert_allclose(exported[[0,3],hilt,:3],before[[0,3],hilt,:3],atol=1e-10)
        checked=motion.validate(target,result,recipe);self.assertTrue(checked['passed'])
        self.assertEqual(checked['metrics']['prop_contact:prop_hilt']['visible_frames'],2)
        broken=copy.deepcopy(result);broken.world[1,hilt,0,3]+=.5
        self.assertFalse(motion.validate(target,broken,recipe)['passed'])
        np.testing.assert_array_equal(target.frames,before)

    def test_unknown_grip_and_wrong_hand_fingers_are_rejected(self):
        target=model();motion.attach(target,'prop_hilt','hand_l',[0,0,0])
        contact=dict(prop='prop_hilt',members=['prop_hilt'],pivot=[0,0,0],parent='hand_l',position=[0,0,0],finger_pose={'fingers_r':[0,-30,0]})
        character=dict(character='hiro',clips={'clip':dict(prop_contacts=[contact])})
        with self.assertRaises(schema.Error) as error:schema.validate_rig(character,target)
        self.assertEqual(error.exception.code,'ANIM_ATTACHMENT_ERROR')
        contact['members']=['prop_missing']
        with self.assertRaises(schema.Error):schema.prop_contacts([contact])
        for change in (dict(max_error=float('nan')),dict(blend_frames=0),dict(pivot=[1,2]),dict(members=['prop_hilt','prop_hilt'])):
            invalid=dict(contact,members=['prop_hilt']);invalid.update(change)
            with self.subTest(change=change),self.assertRaises(schema.Error):schema.prop_contacts([invalid])

    def test_floating_body_contact_adjustment_preserves_lengths_and_floor_goals(self):
        target=model();sample=motion.from_model(target,0,0,30)
        sample.world=np.repeat(sample.world,3,axis=0);sample.travel=np.zeros((3,3));sample.world[1,:,:3,3]+=[0,0,2]
        contacts={n:[[0,2]] for n in ('foot_l','foot_r')}
        raw=motion.solve_contacts(target,sample,contacts)
        solved=motion.solve_contacts(target,sample,contacts,True)
        before=motion.validate(target,raw,dict(contacts=contacts,max_foot_slide=.05))
        after=motion.validate(target,solved,dict(contacts=contacts,max_foot_slide=.05))
        self.assertFalse(before['passed']);self.assertTrue(after['passed'])
        self.assertGreater(solved.metadata['contact_solve']['root_adjustment'],1)
        self.assertNotIn('root_adjustment',raw.metadata['contact_solve'])


class QueueAuthoringTests(unittest.TestCase):
    def scene(self):
        return dict(version=1,scene='queued',actors={'hiro':{'class':'cine_hiro','at':[0,0,0],'queue_spawn':True}},shots=[dict(duration=2,camera={'keys':[{'at':0,'position':[1,2,3],'angles':[0,0,0]}]},tracks={'hiro':[]})])

    def aliases(self):return {'hiro':{'talk':dict(sequence='tka',duration=3),'walk':dict(sequence='walka',duration=2)}}

    def test_queue_spans_cut_and_inherited_move_does_not_add_speed_commands(self):
        scene=self.scene();scene['shots'][0]['tracks']['hiro']=[{'queue':True,'move_to':[10,0,0],'mode':'inherit','clip':'walk'},{'queue':True,'play':'talk'},{'at':1,'enqueue':True,'play':'talk'},{'at':2,'clear':True}]
        data,report=cine.compile_scene(scene,self.aliases());tasks=reconstruction.parse_program(data)[0]['tracks'][0]['tasks']
        self.assertEqual([t['kind'] for t in tasks],['spawn','move','animation','animation','clear'])
        self.assertEqual([t['when'] for t in tasks],[-1,-1,-1,1,2]);self.assertTrue(report['warnings'])
        self.assertEqual(cine.compile_scene(scene,self.aliases())[0],data)

    def test_queue_is_explicit_and_negative_authored_times_remain_invalid(self):
        for action in ({'at':-1,'play':'talk'},{'queue':True,'at':0,'play':'talk'},{'queue':False,'play':'talk'},{'queue':True,'enqueue':True,'play':'talk'},{'queue':True,'move_to':[1,2,3],'mode':'inherit','speed':40}):
            scene=self.scene();scene['shots'][0]['tracks']['hiro']=[action]
            with self.subTest(action=action),self.assertRaises(schema.Error):cine.compile_scene(scene,self.aliases())
        scene=self.scene();scene['shots'][0]['tracks']['hiro']=[{'queue':True,'play':'talk'},{'at':1,'play':'talk'}]
        with self.assertRaises(schema.Error):cine.compile_scene(scene,self.aliases())

    def test_reference_retains_existing_initial_spawn_without_duplicating_it(self):
        data,_=cine.compile_scene(self.scene(),self.aliases())
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);package=root/'data.pk3';recipe=root/'reference.yaml'
            with zipfile.ZipFile(package,'w') as z:z.writestr('dk3/cinematics/intro.cfg',data)
            recipe.write_text(yaml.safe_dump(dict(version=1,source_program='dk3/cinematics/intro.cfg',source_shots=[0],actors=['hiro'],scene='ref')))
            result=reconstruction.reference(package,recipe,root/'out')
            self.assertEqual((root/'out/ref.cfg').read_bytes(),data);self.assertEqual(len(result['initial']),1)

    def test_control_selection_retains_door_and_target_chain_only(self):
        data,_=cine.compile_scene(self.scene(),self.aliases());shots=reconstruction.parse_program(data)
        shots[0]['tracks'][0]['tasks'].append(dict(shots[0]['tracks'][0]['tasks'][0],kind='use',use='door'))
        authored=[dict(classname='worldspawn'),dict(classname='func_door',uniqueid='door',model='*15',target='noise'),dict(classname='target_speaker',targetname='noise',noise='doors/open.wav'),dict(classname='monster_guard')]
        self.assertEqual(reconstruction.fixture_controls(authored,shots),authored[1:3])
        with self.assertRaises(schema.Error) as error:reconstruction.fixture_controls(authored[:2],shots)
        self.assertEqual(error.exception.code,'CINE_MISSING_USE_TARGET')
        authored[1]['classname']='trigger_changelevel'
        with self.assertRaises(schema.Error) as error:reconstruction.fixture_controls(authored,shots)
        self.assertEqual(error.exception.code,'CINE_UNREVIEWED_CONTROL')

    def test_performance_comparison_ignores_cameras_but_detects_use_or_timing_changes(self):
        data,_=cine.compile_scene(self.scene(),self.aliases());before=reconstruction.parse_program(data);after=copy.deepcopy(before)
        after[0]['initial']=[50.,60,70,0,0,0]
        self.assertEqual(reconstruction.performance_contract(before),reconstruction.performance_contract(after))
        after[0]['tracks'][0]['tasks'][0]['destination'][0]+=1
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);a=root/'a.cfg';b=root/'b.cfg';a.write_bytes(data);b.write_bytes(reconstruction.encode_program(after))
            with self.assertRaises(schema.Error) as error:reconstruction.compare_performance(a,b,root/'report.json')
            self.assertEqual(error.exception.code,'CINE_PERFORMANCE_CHANGED');self.assertFalse(json.loads((root/'report.json').read_text())['passed'])
            with self.assertRaises(schema.Error):reconstruction.compare_performance(a,b,a)
            self.assertEqual(a.read_bytes(),data)

    def test_timed_empty_animation_is_an_admission_barrier_and_none_is_retained(self):
        data,_=cine.compile_scene(self.scene(),self.aliases());shots=reconstruction.parse_program(data)
        row=shots[0]['tracks'][0]['tasks'][0]
        shots[0]['tracks'][0]['tasks']=[dict(row,kind='animation',animation='',when=-1),dict(row,kind='animation',animation='',when=1),dict(row,kind='none',when=-1)]
        contract=reconstruction.performance_contract(shots)
        tasks=contract[0]['tracks'][0]['tasks']
        self.assertEqual([t['kind'] for t in tasks],['animation','none'])
        self.assertEqual(tasks[0]['when'],1)


if __name__=='__main__':unittest.main()
