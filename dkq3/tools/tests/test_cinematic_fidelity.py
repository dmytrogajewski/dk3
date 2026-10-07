# SPDX-License-Identifier: GPL-2.0-or-later
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import numpy as np
from scipy.spatial.transform import Rotation

import animation_manifest as schema
import animation_motion as motion
import cinematic_model as rebuild
import cinematic_reconstruction as capture
import skeletal_iqm as sk
from neural_assets import connected_motion
from tests.test_animation_author import model, document


class PerformanceFidelityTests(unittest.TestCase):
    def test_grip_surface_accepts_anatomical_or_corrective_hand_only(self):
        contact=dict(prop='prop_30',members=['prop_30'],pivot=[0,0,0],parent='hand_l',position=[0,0,0],source_grip=True)
        for bone in ('hand_l','deform_hand_l'):
            schema.prop_contacts([dict(contact,attachment_bone=bone)])
        for bone in ('hand_r','deform_hand_r','prop_30','chest'):
            with self.assertRaises(schema.Error):schema.prop_contacts([dict(contact,attachment_bone=bone)])
        with self.assertRaises(schema.Error):schema.prop_contacts([dict(contact,attachment_bone='hand_l',source_grip=False)])

    def test_absolute_head_corrective_and_shared_neck_match_the_measured_heading(self):
        source=model();sample=motion.from_model(source,0,0,30);j=source.names.index('head')
        neck_index=source.names.index('neck');sample.world[:,neck_index,:3,:3]=np.eye(3)
        sample.world[:,j,:3,3]=sample.world[:,neck_index,:3,3]+[0,0,4]
        rotation=Rotation.from_euler('z',110,degrees=True).as_matrix()
        sample.rest[j,:3,:3]=rotation;sample.world[:,j,:3,:3]=rotation
        sample.metadata['semantic_frames']={'head':{'basis':rotation.tolist()}}
        target=copy.deepcopy(source)
        motion.attach(target,'deform_head','head',[0,0,0]);motion.attach(target,'deform_neck','neck',[0,0,0])
        bones={n:n for n in source.names if not n.startswith(('tag_','prop_','hp_','ctf_','fingers_','thumb_','clavicle_'))}
        recipe=dict(bones=bones,forward='x',up='z',scale=1,absolute_rotations={'head':{'forward':[1,0,0],'up':[0,0,1]}},neck_turn_weight=.5)
        result=motion.retarget(target,sample,recipe,'preserve')
        np.testing.assert_allclose(result.metadata['source_correctives']['deform_head'][0][:3],sample.world[0,j,:3],atol=1e-10)
        neck=np.asarray(result.metadata['source_correctives']['deform_neck'])[0]
        np.testing.assert_allclose(neck[:3,:3],Rotation.from_euler('z',55,degrees=True).as_matrix(),atol=1e-10)
        np.testing.assert_array_equal(neck[:3,3],sample.world[0,source.names.index('neck'),:3,3])
        with self.assertRaises(schema.Error):motion.retarget(target,sample,dict(recipe,absolute_rotations={}), 'preserve')

    def test_reference_root_origin_preserves_source_vertical_performance(self):
        m=model();sample=motion.from_model(m,0,0,30);sample.world[:,:,:3,3]+=[2,3,4]
        bones={n:n for n in m.names if not n.startswith(('tag_','prop_','hp_','ctf_','fingers_','thumb_','clavicle_'))}
        default=motion.retarget(m,sample,dict(bones=bones,forward='x',up='z',scale=1),'preserve')
        fixed=motion.retarget(m,sample,dict(bones=bones,forward='x',up='z',scale=1,root_origin='reference'),'preserve')
        np.testing.assert_allclose(fixed.world[:,0,:3,3],sample.world[:,0,:3,3],atol=1e-10)
        np.testing.assert_allclose(default.world[:,0,:3,3],sk.matrices(m.bind,m.parents)[None,0,:3,3],atol=1e-10)

    def test_surface_correctives_require_exact_observations_without_relaxing_anatomy(self):
        source=model();m=copy.deepcopy(source);motion.attach(m,'deform_hand_l','hand_l',[0,0,0])
        sample=motion.from_model(source,0,0,30)
        bones={n:n for n in source.names if not n.startswith(('tag_','prop_','hp_','ctf_','fingers_','thumb_','clavicle_'))}
        retargeted=motion.retarget(m,sample,dict(bones=bones,forward='x',up='z',scale=1),'preserve')
        recipe=dict(correctives={'deform_hand_l':'hand_l'})
        fixed=motion.apply_correctives(m,retargeted,recipe['correctives'])
        self.assertTrue(motion.validate(m,fixed,recipe)['passed'])
        with self.assertRaises(schema.Error):motion.validate(m,fixed,{})
        changed=copy.deepcopy(fixed);changed.world[:,m.names.index('deform_hand_l'),0,3]+=.01
        result=motion.validate(m,changed,recipe)
        self.assertIn('ANIM_SOURCE_POSE_MISMATCH',{f['code'] for f in result['failures']})
        changed=copy.deepcopy(fixed);changed.world[:,m.names.index('hand_l'),0,3]+=.1
        result=motion.validate(m,changed,recipe)
        self.assertIn('ANIM_BONE_LENGTH_CHANGE',{f['code'] for f in result['failures']})
        del fixed.metadata['source_correctives']
        with self.assertRaises(schema.Error):motion.apply_correctives(m,fixed,recipe['correctives'])

    def test_source_grip_preserves_measured_sliding_hand(self):
        m=model();motion.attach(m,'prop_30','hand_l',[0,0,0]);sample=motion.from_model(m,0,0,10)
        sample.world=np.repeat(sample.world,3,axis=0);sample.travel=np.zeros((3,3));j=m.names.index('hand_l')
        sample.world[:,j,2,3]+=[0,1,2];prop=np.repeat(np.eye(4)[None],3,axis=0);prop[:,:3,3]=[4,5,6]
        sample.metadata.update(source_props={'prop_30':dict(world=prop.tolist(),visible=[True]*3,reference_frame=0,surface='staff',rms_max=0)},source_hand_points={'hand_l':sample.world[:,j,:3,3].tolist()})
        contact=dict(prop='prop_30',members=['prop_30'],pivot=[0,0,0],parent='hand_l',position=[0,0,0],source_grip=True,orientation='source_world')
        corrected=motion.prop_policy(m,sample,dict(props={'prop_30':dict(mode='captured')},prop_contacts=[contact]))
        np.testing.assert_allclose(corrected.world[:,m.names.index('prop_30')],prop,atol=1e-10)

    def test_grip_checks_visible_hand_surface_even_when_bone_contact_is_exact(self):
        m=model();motion.attach(m,'prop_30','hand_l',[0,0,0]);j=m.names.index('hand_l')
        m.arrays[4][:]=[j,0,0,0];m.arrays[5][:]=[255,0,0,0]
        sample=motion.from_model(m,0,0,30)
        contact=dict(prop='prop_30',members=['prop_30'],pivot=[0,0,0],parent='hand_l',position=[0,0,0],max_error=.02,max_surface_error=.75)
        recipe=dict(source_frames=[0,0],prop_contacts=[contact])
        fixed=motion.prop_policy(m,sample,recipe);result=motion.validate(m,fixed,recipe)
        self.assertLess(result['metrics']['prop_contact:prop_30']['maximum'],.02)
        self.assertGreater(result['metrics']['hand_surface:prop_30']['maximum'],.75)
        self.assertIn('ANIM_ATTACHMENT_ERROR',{f['code'] for f in result['failures']})

    def test_released_prop_keeps_captured_motion_outside_contact_interval(self):
        m=model();motion.attach(m,'prop_30','hand_l',[0,0,0]);sample=motion.from_model(m,0,0,10)
        sample.world=np.repeat(sample.world,3,axis=0);sample.travel=np.zeros((3,3))
        captured=np.repeat(np.eye(4)[None],3,axis=0);captured[:,:3,3]=[[0,0,0],[5,4,-5],[10,8,-10]]
        sample.metadata['source_props']={'prop_30':dict(world=captured.tolist(),visible=[True]*3,reference_frame=0,surface='sword',rms_max=0)}
        contact=dict(prop='prop_30',members=['prop_30'],pivot=[0,0,0],parent='hand_l',position=[0,0,0],intervals=[[0,0]])
        fixed=motion.prop_policy(m,sample,dict(props={'prop_30':dict(mode='captured')},prop_contacts=[contact]))
        j=m.names.index('prop_30')
        np.testing.assert_allclose(fixed.world[1:,j],captured[1:],atol=1e-10)
        np.testing.assert_allclose(fixed.world[0,j,:3,3],fixed.world[0,m.names.index('hand_l'),:3,3],atol=1e-10)
        self.assertTrue(motion.validate(m,fixed,dict(prop_contacts=[contact]))['passed'])
        for intervals in ([[0,3]],[[2,1]],[[0,1],[1,2]]):
            bad=dict(contact,intervals=intervals)
            with self.assertRaises(schema.Error):
                schema.prop_contacts([bad]);motion.prop_policy(m,sample,dict(props={'prop_30':dict(mode='captured')},prop_contacts=[bad]))

    def test_source_corrective_and_grip_schema_rejects_malformed_mappings(self):
        for value in (3,[],{'wrong':'hand_l'},{'deform_unknown':'unknown'}):
            doc=document();doc['characters'][0]['clips']['walk']['correctives']=value
            with self.assertRaises(schema.Error):schema.validate(doc)

    def test_collapsed_original_blade_is_hidden_before_rigid_fitting(self):
        import yaml
        body=np.array([[0.,0,0],[2,0,0],[0,3,0],[0,0,4]])
        blade=np.array([[0.,0,0],[30,0,0],[30,1,0],[0,1,0]])
        surfaces=[dict(name='body',prop=False,points=np.repeat(body[None],2,axis=0),tri=np.array([[0,1,2]]),uv=np.zeros((4,2))),
                  dict(name='blade',prop=True,points=np.array([blade,blade*.01]),tri=np.array([[0,1,2]]),uv=np.zeros((4,2)))]
        source='models/hiro.dkm';blob=b'original'
        profile=dict(version=1,source_model=source,source_md3_sha256=capture.digest(blob),surface='body',reference_frame=0,
                     markers={'pelvis':dict(parent=None,anchor=[0,0,0],vertices=[0,1,2,3])},clips={'test':dict(sequence='test',source_frames=[0,1])},
                     props={'prop_30':dict(surface='blade',reference_frame=0)},provenance=dict(origin='test',license='test',redistribution='test',credit='test'))
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);p=root/'profile.yaml';p.write_text(yaml.safe_dump(profile));z=root/'models.pk3'
            with zipfile.ZipFile(z,'w') as archive:
                archive.writestr(source+'.md3',blob);archive.writestr(source+'.json','{}');archive.writestr(source+'.anim','dk3_animation 1\n2\n"test" 0 1 10\n')
            with patch('neural_assets.read_md3',return_value=(surfaces,{})),patch('neural_assets.source_props',side_effect=lambda s,m:s),patch('neural_assets.split_hidden_props',side_effect=lambda s:s):
                capture.capture(p,z,root/'out')
            result=motion.read(root/'out/test.npz')
            self.assertEqual(result.metadata['source_props']['prop_30']['visible'],[True,False])

    def bent_arm(self):
        m=model();world=sk.matrices(m.bind,m.parents)[None].copy()
        a,b,c=[m.names.index(n+'_r') for n in ('upperarm','forearm','hand')]
        upper=np.array([.1,.7,-.5]);upper/=np.linalg.norm(upper)
        lower=np.array([.5,-.7,-.2]);lower/=np.linalg.norm(lower)
        world[:,b,:3,3]=world[:,a,:3,3]+upper*np.linalg.norm(m.bind[b,:3])
        world[:,c,:3,3]=world[:,b,:3,3]+lower*np.linalg.norm(m.bind[c,:3])
        return m,world,(a,b,c)

    def test_observed_bent_elbow_retains_performance_outside_generic_pole_cone(self):
        m,world,(a,b,c)=self.bent_arm()
        old=sk.matrices(connected_motion(m,world),m.parents)
        fixed=sk.matrices(connected_motion(m,world,temporal_poles=True,preserve_observed_poles=True),m.parents)
        np.testing.assert_allclose(fixed[:,[a,b,c],:3,3],world[:,[a,b,c],:3,3],atol=1e-8)
        self.assertGreater(float(np.linalg.norm(old[:,b,:3,3]-world[:,b,:3,3])),1)
        # The compatibility default is unchanged and still opt-in.
        np.testing.assert_array_equal(connected_motion(m,world),connected_motion(m,world,preserve_observed_poles=False))

    def test_source_fidelity_rejects_the_old_numerically_valid_gesture(self):
        m,world,(a,b,c)=self.bent_arm();sample=motion.Motion(m.names,m.parents,sk.matrices(m.bind,m.parents),world,30.,np.zeros((1,3)),{})
        bones={n:n for n in m.names if not n.startswith(('tag_','prop_','hp_','ctf_','fingers_','thumb_','clavicle_'))}
        recipe=dict(bones=bones,forward='x',up='z',scale=1.)
        old=motion.retarget(m,sample,recipe,'preserve')
        fixed=motion.retarget(m,sample,dict(recipe,preserve_observed_poles=True),'preserve')
        limits=dict(source_fidelity=dict(max_direction_degrees=1))
        result=motion.validate(m,old,limits)
        self.assertIn('ANIM_SOURCE_POSE_MISMATCH',{f['code'] for f in result['failures']})
        self.assertTrue(motion.validate(m,fixed,limits)['passed'])
        fixed=motion.solve_contacts(m,fixed,{'foot_l':[[0,0]],'foot_r':[[0,0]]})
        self.assertTrue(motion.validate(m,fixed,limits)['passed'])

    def test_captured_prop_uses_original_orientation_and_discrete_visibility(self):
        m=model();motion.attach(m,'prop_30','hand_l',[0,0,0]);sample=motion.from_model(m,0,0,10)
        sample.world=np.repeat(sample.world,3,axis=0);sample.travel=np.zeros((3,3))
        world=np.repeat(np.eye(4)[None],3,axis=0);world[:,:3,:3]=Rotation.from_euler('y',[60,65,70],degrees=True).as_matrix();world[:,:3,3]=[2,3,4]
        sample.metadata['source_props']={'prop_30':dict(world=world.tolist(),visible=[True,False,True],reference_frame=0,surface='sword',rms_max=.02)}
        sampled=motion.resample(sample,30,count=5)
        recipe=dict(props={'prop_30':dict(mode='captured')},source_frames=[0,2])
        corrected=motion.prop_policy(m,sampled,recipe);channels=motion.export_channels(corrected);j=m.names.index('prop_30')
        np.testing.assert_allclose(corrected.world[:,j],np.asarray(sampled.metadata['source_props']['prop_30']['world']),atol=1e-10)
        np.testing.assert_array_equal(channels[:,j,7]>0,[True,True,False,True,True])
        self.assertGreater(float(motion.angle(corrected.world[0,j,:3,:3],np.eye(3))),59)
        del sampled.metadata['source_props']
        with self.assertRaises(schema.Error) as error:motion.prop_policy(m,sampled,recipe)
        self.assertEqual(error.exception.code,'ANIM_UNOBSERVABLE_MARKER')

    def test_captured_reflection_and_non_boolean_visibility_are_rejected(self):
        m=model();sample=motion.from_model(m,0,0,30)
        prop=dict(world=[np.eye(4).tolist()],visible=[True],reference_frame=0,surface='sword',rms_max=0)
        sample.metadata['source_props']={'prop_30':prop}
        motion.validate_motion(sample);prop['world'][0][0][0]=-1
        with self.assertRaises(schema.Error):motion.validate_motion(sample)
        prop['world'][0][0][0]=1;prop['visible']=[1]
        with self.assertRaises(schema.Error):motion.validate_motion(sample)

    def test_fidelity_threshold_and_captured_policy_arguments_are_bounded(self):
        for value in (float('nan'),16,-1):
            doc=document();doc['characters'][0]['clips']['walk']['source_fidelity']=dict(max_direction_degrees=value)
            with self.assertRaises(schema.Error):schema.validate(doc)
        doc=document();doc['characters'][0]['clips']['walk']['props']={'prop_30':dict(mode='captured',frames=[0,1])}
        with self.assertRaises(schema.Error):schema.validate(doc)


class SourceModelTests(unittest.TestCase):
    def test_model_admission_preserves_alpha_and_bright_presentation_variants(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);m=model();m.meshes=[('dojo','models/neural/dojo/body',0,3,0,1)]
            (root/'model.iqm').write_bytes(sk.write(m));(root/'body.png').write_bytes(b'local texture')
            target='models/neural/test.iqm';source='models/test.dkm';files={target:b'old model','scripts/dk3-neural.shader':b'// retained shaders\n'}
            for i,suffix in enumerate(('','@alpha','@bright','@alphabright')):files[target+f'.{i}.skin']=('old,models/neural/test/body'+suffix+'\n').encode()
            report=dict(passed=True,model_file='model.iqm',output_sha256=schema.sha(root/'model.iqm'),source_model=source,body_material='models/neural/dojo/body')
            rebuild.admit_repair(files,{source:target},{},root,root/'body.png',target,report,'0'*64)
            for i,suffix in enumerate(('','@alpha','@bright','@alphabright')):self.assertEqual(files[target+f'.{i}.skin'],('dojo,models/neural/dojo/body'+suffix+'\n').encode())
            shader=files['scripts/dk3-neural.shader'];self.assertTrue(shader.startswith(b'// retained shaders\n'))
            rebuild.admit_repair(files,{source:target},{},root,root/'body.png',target,report,'0'*64)
            self.assertEqual(shader,files['scripts/dk3-neural.shader'])
            for suffix in ('@alpha','@bright','@alphabright'):self.assertEqual(shader.count(('models/neural/dojo/body'+suffix+'\n{').encode()),1)
            files['models/neural/hiro/head.png']=b'approved face'
            report['admitted_head']=dict(material='models/neural/hiro/head',texture_sha256=capture.digest(b'approved face'))
            rebuild.admit_repair(files,{source:target},{},root,root/'body.png',target,report,'0'*64)
            files['models/neural/hiro/head.png']=b'different face'
            with self.assertRaises(schema.Error) as failure:rebuild.admit_repair(files,{source:target},{},root,root/'body.png',target,report,'0'*64)
            self.assertEqual(failure.exception.code,'ANIM_SOURCE_HASH_MISMATCH')

    def test_head_replacement_keeps_sleeves_above_cut_plane(self):
        m=model();motion.attach(m,'deform_head','head',[0,0,0])
        m.arrays[0]=np.array([[0.,0,24],[1,0,24],[0,1,24],[0,0,26],[1,0,26],[0,1,26]])
        m.arrays[1]=np.zeros((6,2));m.arrays[2]=np.tile([0.,0,1],(6,1))
        m.arrays[4]=np.array([[m.names.index('upperarm_r'),0,0,0]]*3+[[m.names.index('deform_head'),0,0,0]]*3)
        m.arrays[5]=np.tile([255,0,0,0],(6,1));m.triangles=np.array([[0,1,2],[3,4,5]])
        rows=rebuild.source_body_rows(m,22)
        self.assertEqual(len(rows),1)
        np.testing.assert_allclose([c[0] for c in rows[0]],m.arrays[0][:3])

    def test_corrective_weight_fit_recovers_translating_source_surface(self):
        m=model();motion.attach(m,'deform_hand_r','hand_r',[0,0,0])
        j=m.names.index('deform_hand_r');m.frames=np.repeat(m.bind[None],4,axis=0)
        m.frames[:,j,:3]+=[[0,0,0],[1,0,2],[0,2,-1],[-1,-2,1]]
        m.arrays[0]=sk.matrices(m.bind,m.parents)[j,:3,3]+np.array([[0.,0,0],[.1,0,0],[0,.1,0]])
        m.arrays[4]=np.tile([j,0,0,0],(3,1));m.arrays[5]=np.tile([255,0,0,0],(3,1))
        weights,report=rebuild.learn_weights(m,m.arrays[0],sk.skin(m,m.frames),sk.matrices(m.frames,m.parents),np.arange(4))
        self.assertLess(report['vertex_rms_max'],1e-7)
        np.testing.assert_allclose(weights[:,j],1,atol=1e-7)
        np.testing.assert_array_equal(weights[:,m.names.index('hand_r')],0)

    def test_weight_fit_recovers_measured_deformation_without_bone_stretch(self):
        m=sk.Model({0:np.array([[0.,0,1],[2,0,1],[1,1,1]]),1:np.zeros((3,2)),2:np.tile([0.,0,1],(3,1)),
                    4:np.array([[0,1,0,0]]*3),5:np.array([[128,127,0,0]]*3)},
                   [('body','body',0,3,0,1)],np.array([[0,1,2]]),['pelvis','spine'],[-1,0],
                   np.array([[0,0,0,0,0,0,1,1,1,1],[0,0,2,0,0,0,1,1,1,1]],float),np.zeros((6,2,10)))
        m.frames[:]=m.bind;m.frames[:,1,3:7]=Rotation.from_euler('y',[0,10,20,-20,-10,0],degrees=True).as_quat()
        observed=sk.skin(m,m.frames);world=sk.matrices(m.frames,m.parents)
        weights,report=rebuild.learn_weights(m,m.arrays[0],observed,world,np.arange(6))
        np.testing.assert_allclose(weights[:,0],128/255,atol=1e-7)
        self.assertLess(report['vertex_rms_max'],1e-7);np.testing.assert_allclose(weights.sum(axis=1),1)

    def test_subdivision_preserves_uv_seam_geometry_and_normalized_influences(self):
        m=model();m.arrays[0]=np.array([[0.,0,0],[1,0,0],[0,1,0],[0,0,0],[0,1,0],[-1,0,0]])
        m.arrays[1]=np.array([[0.,0],[1,0],[0,1],[1,0],[1,1],[0,0]])
        m.arrays[2]=np.tile([0.,0,1],(6,1));m.arrays[4]=np.zeros((6,4),int);m.arrays[5]=np.tile([255,0,0,0],(6,1))
        m.triangles=np.array([[0,1,2],[3,4,5]]);m.meshes=[('body','body',0,6,0,2)]
        rebuilt=rebuild.subdivide(m,2);sk.validate(rebuilt)
        np.testing.assert_array_equal(rebuilt.arrays[5].sum(axis=1),255)
        # Shared seam points are geometrically equal despite distinct UVs.
        points=rebuilt.arrays[0];uv=rebuilt.arrays[1];duplicates=0
        for p in np.unique(points,axis=0):
            selected=np.all(points==p,axis=1)
            if len(np.unique(uv[selected],axis=0))>1:duplicates+=1
        self.assertGreater(duplicates,0);self.assertEqual(len(rebuilt.triangles),32)

    def test_rebuild_rejects_template_hash_and_path_escape_before_output(self):
        import yaml
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);profile=root/'profile.yaml';profile.write_text('version: 1\n')
            (root/'template.iqm').write_bytes(sk.write(model()))
            recipe=dict(version=1,profile='profile.yaml',template='template.iqm',template_sha256='0'*64,
                head_material='models/neural/hiro/head',body_material='models/neural/hiro-dojo/body',neck_cut=22,subdivision=2,head_scale=1,provenance={})
            path=root/'recipe.yaml';path.write_text(yaml.safe_dump(recipe))
            with self.assertRaises(schema.Error) as error:rebuild.rebuild(path,root/'missing.pk3',root/'out')
            self.assertEqual(error.exception.code,'ANIM_SOURCE_HASH_MISMATCH');self.assertFalse((root/'out').exists())
            recipe['template']='../outside.iqm';path.write_text(yaml.safe_dump(recipe))
            with self.assertRaises(schema.Error):rebuild.rebuild(path,root/'missing.pk3',root/'out')


if __name__=='__main__':unittest.main()
