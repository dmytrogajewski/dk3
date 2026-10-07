# SPDX-License-Identifier: GPL-2.0-or-later
import copy
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch
import zipfile

import numpy as np

import animation_manifest as manifest
import animation_motion as motion
import cinematic_author as cine
import animation_author as author
import animation_blender as adapter
import neural_rig as rig
import skeletal_iqm as sk


def model():
    bind=np.array([[0.,0,0,0,0,0,1,1,1,1]])
    result=sk.Model({0:np.array([[0.,0,0],[1,0,0],[0,1,0]]),1:np.zeros((3,2)),
                     2:np.tile([0.,0,1],(3,1)),4:np.zeros((3,4),int),5:np.tile([255,0,0,0],(3,1))},
                    [('body','body',0,3,0,1)],np.array([[0,1,2]]),['pelvis'],[-1],bind,bind[None])
    rig.skeleton(result,'hiro')
    result.frames[0]=rig.pose(result,sk.matrices(result.bind,result.parents),0,'idle','relaxed')
    return result


def document():
    return dict(version=1,characters=[dict(character='hiro',source_model='models/characters/hiro.dkm',
                mapping_key='player/hiro',target_model='models/neural/hiro.iqm',iqm='hiro.iqm',skeleton='current',
                clips=dict(walk=dict(source_frames=[20,29],target_frames=[40,63],sequence='walka',authority_fps=10,
                                     fps=30,loop=True,root_motion='in_place',contacts={'foot_l':[[0,4]]})))])


class ManifestTests(unittest.TestCase):
    def test_runtime_compilation_and_authoritative_timing(self):
        doc=document()
        self.assertEqual(manifest.compile_manifest(doc,{'models/neural/hiro.iqm':64}),b'player/hiro 20 29 40 63 30 0 0\n')
        self.assertEqual(manifest.aliases(doc)['hiro']['walk']['duration'],1)
        del doc['characters'][0]['clips']['walk']['authority_fps']
        self.assertIsNone(manifest.aliases(doc)['hiro']['walk']['duration'])

    def test_authoritative_duration_mapping_uses_effective_target_rate(self):
        clip=document()['characters'][0]['clips']['walk'];clip['fps']=0
        self.assertEqual(manifest.effective_rate(clip),24)
        del clip['authority_fps']
        with self.assertRaisesRegex(manifest.Error,'actual authoritative'):manifest.effective_rate(clip)

    def test_duplicates_unsafe_yaml_and_unknown_fields_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/'source.yaml'
            for text in ('version: 1\nversion: 2\n','version: !!python/object/apply:os.system [echo unsafe]\n'):
                path.write_text(text)
                with self.assertRaises(ValueError if 'object' not in text else Exception):manifest.load(path)
        doc=document();doc['characters'][0]['clips']['walk']['facial']='unknown'
        with self.assertRaises(manifest.Error):manifest.validate(doc)

    def test_range_contact_and_grid_capacity_rejected(self):
        for modify in (lambda clip:clip.update(target_frames=[60,80]),
                       lambda clip:clip.update(contacts={'foot_l':[[0,6],[6,8]]}),
                       lambda clip:clip.update(attack_grid=dict(first=65500,count=12))):
            doc=document();modify(doc['characters'][0]['clips']['walk'])
            with self.assertRaises(manifest.Error):manifest.validate(doc,{'models/neural/hiro.iqm':64})

    def test_invalid_nested_types_fail_as_manifest_errors(self):
        for key in ('contacts','joint_limits','props','attachments','motion','retarget'):
            doc=document();doc['characters'][0]['clips']['walk'][key]=23
            with self.subTest(key=key),self.assertRaises(manifest.Error):manifest.validate(doc)
        doc=document();doc['characters'][0]['clips']['walk']['fps']=29.97
        with self.assertRaisesRegex(manifest.Error,'integer'):manifest.validate(doc)
        doc=document();duplicate=copy.deepcopy(doc['characters'][0]);duplicate['source_model']='models/other/hiro.dkm';duplicate['target_model']='models/neural/other.iqm'
        doc['characters'].append(duplicate)
        with self.assertRaisesRegex(manifest.Error,'duplicate character'):manifest.validate(doc)


class MotionTests(unittest.TestCase):
    def test_npz_roundtrip_rejects_invalid_matrix(self):
        m=model();sample=motion.from_model(m,0,0,30)
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/'sample.npz';motion.write(path,sample);loaded=motion.read(path)
            np.testing.assert_array_equal(loaded.world,sample.world)
        sample.world[0,0,0,0]=2
        with self.assertRaises(manifest.Error):motion.validate_motion(sample)

    def test_resample_uses_quaternion_shortest_arc_and_explicit_count(self):
        m=model();m.frames=np.repeat(m.bind[None],2,axis=0)
        m.frames[0,0,3:7]=[0,0,np.sin(np.deg2rad(170)/2),np.cos(np.deg2rad(170)/2)]
        m.frames[1,0,3:7]=[0,0,np.sin(np.deg2rad(-170)/2),np.cos(np.deg2rad(-170)/2)]
        sampled=motion.resample(motion.from_model(m,0,1,30),30,count=3)
        self.assertAlmostEqual(sampled.world[1,0,0,0],-1,places=6)
        self.assertEqual(sampled.metadata['resample']['output_frames'],3)

    def test_contacts_compensate_root_travel_and_report_actual_slide(self):
        m=model();m.frames=np.repeat(m.frames,5,axis=0)
        m.frames[:,0,0]+=np.arange(5)*.1
        sampled=motion.from_model(m,0,4,30);recipe=dict(contacts={'foot_l':[[0,4]]},max_foot_slide=.01)
        self.assertFalse(motion.validate(m,sampled,recipe)['passed'])
        sampled.travel[:,0]=-np.arange(5)*.1
        self.assertTrue(motion.validate(m,sampled,recipe)['passed'])

    def test_target_motion_root_policy_removes_and_restores_travel_without_stretch(self):
        m=model();m.frames=np.repeat(m.frames,5,axis=0);m.frames[:,0,0]=8+np.arange(5)
        captured=motion.from_model(m,0,4,30);original=captured.world.copy()
        stationary=motion.root_policy(captured,'in_place')
        np.testing.assert_allclose(stationary.world[:,0,0,3],8)
        np.testing.assert_array_equal(stationary.travel[:,0],np.arange(5))
        self.assertTrue(motion.validate(m,stationary,{})['passed'])
        np.testing.assert_array_equal(captured.world,original)
        restored=motion.root_policy(stationary,'preserve')
        np.testing.assert_allclose(restored.world,original,atol=1e-8)
        np.testing.assert_array_equal(restored.travel,np.zeros((5,3)))
        paced,speed=motion.constant_travel(stationary)
        self.assertEqual(speed,30);np.testing.assert_array_equal(paced.travel,stationary.travel)

    def test_joint_and_attachment_limits_have_frame_evidence(self):
        m=model();m.frames=np.repeat(m.frames,2,axis=0);j=m.names.index('hand_r')
        m.frames[1,j,3:7]=[0,0,1,0]
        result=motion.validate(m,motion.from_model(m,0,1,30),dict(joint_limits={'hand_r':35},attachments=[dict(bone='tag_weapon',max_angle_step=35)]))
        self.assertFalse(result['passed']);self.assertIn('joint_limit:hand_r',result['metrics'])
        self.assertIn('attachment_angle:tag_weapon',result['metrics'])

    def test_directional_retarget_preserves_fixed_lengths_and_frozen_target(self):
        m=model();bind=sk.matrices(m.bind,m.parents)
        m.frames=np.array([rig.pose(m,bind,f/24,'walk','relaxed') for f in range(24)])
        original=copy.deepcopy(m);sample=motion.from_model(m,0,23,30)
        mapped={n:n for n in m.names if not n.startswith(('tag_','fingers_','thumb_','clavicle_'))}
        result=motion.retarget(m,sample,dict(bones=mapped,forward='x',up='z'))
        self.assertTrue(motion.validate(m,result,dict(max_joint_step=65))['passed'])
        np.testing.assert_array_equal(m.bind,original.bind)
        np.testing.assert_array_equal(m.arrays[5],original.arrays[5])
        np.testing.assert_array_equal(m.frames,original.frames)

    def test_attachment_and_grid_obey_existing_contract(self):
        m=model();base=motion.from_model(m,0,0,30);attack=copy.deepcopy(base)
        j=m.names.index('chest');attack.world[:,j,:3,:3]=rig.rotation(0,.2)
        grid=motion.compose_grid(m,base,attack,['chest'])
        self.assertEqual(grid.shape,(1,len(m.names),10))
        before=len(m.names);motion.attach(m,'prop_key','hand_r',[1,2,3])
        self.assertEqual(m.parents[before],m.names.index('hand_r'))
        np.testing.assert_array_equal(m.frames[:,before,:3],[[1,2,3]])

    def test_loop_resample_keeps_body_and_prop_phase_and_discrete_visibility(self):
        m=model();motion.attach(m,'prop_sword','hand_r',[0,0,0])
        m.frames=np.repeat(m.bind[None],4,axis=0);j=m.names.index('prop_sword')
        m.frames[:,0,0]=np.arange(4);m.frames[:,j,0]=np.arange(4)
        m.frames[:2,j,7:10]=0
        sampled=motion.resample(motion.from_model(m,0,3,30),30,count=2,loop=True)
        np.testing.assert_allclose(sampled.world[:,0,0,3],[0,1.5])
        exported=motion.export_channels(sampled)
        np.testing.assert_allclose(exported[:,j,0],[0,1.5])
        np.testing.assert_array_equal(exported[:,j,7:10],[[0,0,0],[1,1,1]])

    def test_hidden_and_attached_props_preserve_frozen_rig(self):
        m=model();motion.attach(m,'prop_sword','hand_l',[0,0,0]);sampled=motion.from_model(m,0,0,30)
        original=copy.deepcopy(m);j=m.names.index('prop_sword')
        hidden=motion.prop_policy(m,sampled,dict(source_frames=[0,0],props={'prop_sword':dict(mode='hide')}))
        np.testing.assert_array_equal(motion.export_channels(hidden)[:,j,7:10],[[0,0,0]])
        np.testing.assert_array_equal(motion.compose_grid(m,hidden,hidden,['chest'])[:,j,7:10],[[0,0,0]])
        attached=motion.prop_policy(m,sampled,dict(source_frames=[0,0],props={'prop_sword':dict(mode='attach',parent='hand_r',position=[1,2,3])}))
        expected=sampled.world[:,m.names.index('hand_r')].copy()
        expected[:,:3,3]+=(expected[:,:3,:3]@np.array([1,2,3]))
        np.testing.assert_allclose(attached.world[:,j],expected,atol=1e-8)
        np.testing.assert_array_equal(m.bind,original.bind);self.assertEqual(m.parents,original.parents)

    def test_long_contact_reports_linear_memory_bound_and_extreme_frames(self):
        m=model();sampled=motion.from_model(m,0,0,30)
        sampled.world=np.repeat(sampled.world,2048,axis=0);sampled.travel=np.zeros((2048,3));sampled.travel[:,0]=np.linspace(0,1,2048)
        result=motion.validate(m,sampled,dict(contacts={'foot_l':[[0,2047]]},max_foot_slide=.5))
        metric=result['metrics']['contact:foot_l:0-2047']
        self.assertFalse(result['passed']);self.assertAlmostEqual(metric['maximum'],1)
        self.assertIn(2047,metric['extreme_frames'])

    def test_blender_job_cannot_overwrite_motion_input(self):
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/'motion.bvh';path.write_text('preserve source')
            with self.assertRaisesRegex(manifest.Error,'already exists'):
                author.blender(dict(operation='import_motion',input=str(path),output=str(path)),Path(root)/'receipt')
            self.assertEqual(path.read_text(),'preserve source')

    def test_preview_uses_separate_head_material_instead_of_body_atlas(self):
        m=model();m.meshes=[('body','hero/body',0,2,0,1),('head','hero/head',2,1,1,0)]
        with self.assertRaisesRegex(manifest.Error,'multi-material'):adapter.texture_assignments(m,dict(texture='body.png'))
        paths=adapter.texture_assignments(m,dict(textures={'hero/body':'body.png','hero/head':'head.png'}))
        self.assertEqual(paths['hero/body'].name,'body.png');self.assertEqual(paths['hero/head'].name,'head.png')
        with self.assertRaisesRegex(manifest.Error,'missing'):adapter.texture_assignments(m,dict(textures={'hero/body':'body.png'}))


class PackageTests(unittest.TestCase):
    def test_changed_validated_output_is_rejected_before_admission(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);(root/'hiro.iqm').write_bytes(b'original')
            manifest.write_json(root/'build.json',dict(passed=True,outputs={'hiro.iqm':manifest.sha(root/'hiro.iqm')}))
            (root/'hiro.iqm').write_bytes(b'changed')
            with self.assertRaisesRegex(manifest.Error,'changed after validation'):
                author.package(root/'unused.pk3',root/'unused-models.pk3',root,root/'result.pk3')

    def test_forged_hash_receipt_cannot_admit_changed_geometry(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);original=model();admitted=sk.write(original)
            changed=copy.deepcopy(original);changed.arrays[0][0,0]+=1
            (root/'hiro.iqm').write_bytes(sk.write(changed));doc=document()
            (root/'animation-manifest.yaml').write_text(__import__('yaml').safe_dump(doc))
            target=doc['characters'][0]['target_model'];source=doc['characters'][0]['source_model']
            with zipfile.ZipFile(root/'base.pk3','w') as z:
                z.writestr('dk3/neural-models.cfg',source+' '+target+'\n');z.writestr(target,admitted)
            with zipfile.ZipFile(root/'models.pk3','w') as z:z.writestr(source+'.anim','dk3_animation 1\n30\n"walka" 20 29 10\n')
            digest=manifest.sha(root/'hiro.iqm')
            manifest.write_json(root/'build.json',dict(passed=True,outputs={'hiro.iqm':digest},
                models={target:dict(path='hiro.iqm',sha256=digest,source_sha256=__import__('hashlib').sha256(admitted).hexdigest())}))
            with patch.object(author,'validate_package',return_value={}),self.assertRaisesRegex(manifest.Error,'frozen vertex data'):
                author.package(root/'base.pk3',root/'models.pk3',root,root/'result.pk3')


class CinematicTests(unittest.TestCase):
    def aliases(self):
        return {'hiro':{'neutral':dict(sequence='ambappa',duration=2.1),
                        'walk':dict(sequence='walka',duration=2,movement_speed=40),
                        'run':dict(sequence='walkb',duration=2,movement_speed=120)}}

    def scene(self):
        return dict(version=1,scene='studio',actors={'hiro':dict(classname='unused')},shots=[])

    def test_cubic_coefficients_match_native_seconds_polynomial(self):
        coefficients=cine.curves([0,2],[[0,0,0],[10,4,2]])[0]
        for axis,expected in enumerate((10,4,2)):
            a,b,c,d=coefficients[axis*4:axis*4+4]
            self.assertAlmostEqual(((a*2+b)*2+c)*2+d,expected)
        angular=cine.curves([0,2],[[0,170,0],[0,-170,0]],angular=True)[0]
        a,b,c,d=angular[4:8];self.assertAlmostEqual(((a*2+b)*2+c)*2+d,190)

    def test_scene_compiles_spawn_move_head_and_sound(self):
        source=manifest.load(Path(__file__).parents[2]/'animation/studio-scene.yaml')
        encoded,report=cine.compile_scene(source,self.aliases())
        self.assertTrue(encoded.startswith(b'dk3_cinematic 1 3\n'));self.assertIn(b'head 6\n',encoded)
        self.assertIn(b'"cine_hiro" "hiro" 6\n',encoded)
        self.assertIn(b'"walkb"',encoded);self.assertEqual(len(report['shots']),3)
        lines=encoded.decode().splitlines();start=lines.index('head 6')
        coefficients=np.array([[float(v) for v in line.split()] for line in lines[start+2:start+7]]).reshape(5,3,4)
        end_velocity=3*coefficients[:-1,:,0]*.2**2+2*coefficients[:-1,:,1]*.2+coefficients[:-1,:,2]
        np.testing.assert_allclose(end_velocity,coefficients[1:,:,2],atol=1e-5)

    def test_gait_speed_mismatch_is_rejected(self):
        source=manifest.load(Path(__file__).parents[2]/'animation/studio-scene.yaml')
        source['shots'][0]['tracks']['hiro'][1]['speed']=80
        with self.assertRaisesRegex(manifest.Error,'differs from selected gait'):cine.compile_scene(source,self.aliases())

    def test_native_actor_look_is_absolute_and_turn_compensates_yaw_multiplier(self):
        source=dict(version=1,scene='look',actors={'hiro':{'class':'cine_hiro','at':[0,0,0],'angles':[0,90,0]}},
                    shots=[dict(duration=3,camera=dict(keys=[dict(at=0,position=[100,0,40],angles=[0,180,0])]),
                                tracks={'hiro':[dict(at=0,look_at=[100,0,22],duration=1),dict(at=1.2,turn=[0,180,0],duration=1)]})])
        encoded,report=cine.compile_scene(source);lines=encoded.decode().splitlines();start=lines.index('head 6')
        self.assertEqual(lines[start+1],'0 90 0')
        final=[float(x) for x in lines[start+6].split()];a,b,c,d=final[4:8]
        self.assertAlmostEqual(((a*.2+b)*.2+c)*.2+d,0,places=6)
        speed=[line.split() for line in lines if line.startswith('8 ')][0]
        self.assertAlmostEqual(float(speed[8]),18)
        self.assertTrue(any('whole performer' in warning for warning in report['warnings']))

    def test_overlaps_and_unsupported_layers_fail_before_export(self):
        source=manifest.load(Path(__file__).parents[2]/'animation/studio-scene.yaml')
        source['shots'][0]['tracks']['hiro'][2]['at']=2
        with self.assertRaisesRegex(manifest.Error,'overlaps'):cine.compile_scene(source,self.aliases())
        source=manifest.load(Path(__file__).parents[2]/'animation/studio-scene.yaml');source['shots'][0]['events']=[dict(facial='dialogue',at=1)]
        with self.assertRaisesRegex(manifest.Error,'unknown fields'):cine.compile_scene(source,self.aliases())

    def test_missing_authoritative_duration_is_not_guessed(self):
        source=manifest.load(Path(__file__).parents[2]/'animation/studio-scene.yaml')
        del source['shots'][1]['tracks']['hiro'][0]['duration']
        aliases=self.aliases();aliases['hiro']['neutral']['duration']=None
        with self.assertRaisesRegex(manifest.Error,'finite number'):cine.compile_scene(source,aliases)


if __name__=='__main__':unittest.main()
