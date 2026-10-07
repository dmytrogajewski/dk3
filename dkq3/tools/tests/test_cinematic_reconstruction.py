# SPDX-License-Identifier: GPL-2.0-or-later
import copy
import json
from argparse import Namespace
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import numpy as np
from scipy.spatial.transform import Rotation
import yaml

import animation_author as author
import animation_manifest as schema
import animation_motion as motion
import animation_preview as preview
import cinematic_author as cine
import cinematic_reconstruction as reconstruction
import skeletal_iqm as sk
from tests.test_animation_author import model, document


class SourceCaptureTests(unittest.TestCase):
    def test_observations_recover_known_rigid_motion_and_anchor(self):
        rest=np.array([[0.,0,0],[2,0,0],[0,3,0],[0,0,4],[1,1,1]])
        angles=[0,30,70];rot=Rotation.from_euler('z',angles,degrees=True).as_matrix()
        shift=np.array([[0.,0,0],[3,1,2],[5,2,3]])
        points=np.einsum('fij,vj->fvi',rot,rest)+shift[:,None]
        anchor=np.array([.5,.6,.7]);capture,metrics=reconstruction.rigid_capture(rest,points,anchor,0)
        np.testing.assert_allclose(capture[:,:3,:3],rot,atol=1e-12)
        np.testing.assert_allclose(capture[:,:3,3],rot@anchor+shift,atol=1e-12)
        self.assertLess(metrics['rms_max'],1e-12)
        repeated,_=reconstruction.rigid_capture(rest,points,anchor,0)
        np.testing.assert_array_equal(capture,repeated)

    def test_unobservable_collinear_marker_rejected(self):
        points=np.array([[0.,0,0],[1,0,0],[2,0,0],[3,0,0]])
        with self.assertRaises(schema.Error) as error:
            reconstruction.rigid_capture(points,points[None],np.zeros(3),.002)
        self.assertEqual(error.exception.code,'ANIM_UNOBSERVABLE_MARKER')

    def test_capture_rejects_changed_source_and_nonrigid_region(self):
        points=np.array([[0.,0,0],[2,0,0],[0,3,0],[0,0,4]])
        surface=dict(name='body',prop=False,points=np.array([points,points*3]),tri=np.array([[0,1,2]]),uv=np.zeros((4,2)))
        source='models/hiro.dkm';blob=b'pinned local test source'
        profile=dict(version=1,source_model=source,source_md3_sha256=reconstruction.digest(blob),surface='body',reference_frame=0,
            markers={'pelvis':dict(parent=None,anchor=[0,0,0],vertices=[0,1,2,3])},
            clips={'action':dict(sequence='action',source_frames=[0,1])},
            provenance=dict(origin='test',license='test',redistribution='test',credit='test'))
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);package=root/'models.pk3';recipe=root/'profile.yaml'
            with zipfile.ZipFile(package,'w') as z:
                z.writestr(source+'.md3',blob);z.writestr(source+'.json',b'{}');z.writestr(source+'.anim',b'dk3_animation 1\n2\n"action" 0 1 10\n')
            recipe.write_text(yaml.safe_dump(profile))
            with patch('neural_assets.read_md3',return_value=([surface],{})),patch('neural_assets.source_props',side_effect=lambda s,m:s),patch('neural_assets.split_hidden_props',side_effect=lambda s:s):
                with self.assertRaises(schema.Error) as error:reconstruction.capture(recipe,package,root/'fit')
                self.assertEqual(error.exception.code,'ANIM_MARKER_FIT_ERROR')
                self.assertFalse((root/'fit/action.npz').exists())
                self.assertFalse(json.loads((root/'fit/capture.json').read_text())['passed'])
            profile['source_md3_sha256']='0'*64;recipe.write_text(yaml.safe_dump(profile))
            with self.assertRaises(schema.Error) as error:reconstruction.capture(recipe,package,root/'changed')
            self.assertEqual(error.exception.code,'ANIM_SOURCE_HASH_MISMATCH');self.assertFalse((root/'changed').exists())

    def test_output_tokens_cannot_escape_explicit_root(self):
        for value in ('../clip','a/b','a\\b','/tmp/clip','x.y'):
            with self.subTest(value=value),self.assertRaises(schema.Error):reconstruction.filename_token(value,'clip')

    def test_head_orientation_survives_retarget_without_bind_mutation(self):
        m=model();before=m.bind.copy();m.frames=np.repeat(m.bind[None],3,axis=0)
        j=m.names.index('head');m.frames[:,j,3:7]=Rotation.from_euler('z',[0,40,80],degrees=True).as_quat()
        sampled=motion.from_model(m,0,2,10)
        bones={n:n for n in m.names if not n.startswith(('tag_','prop_','hp_','ctf_','fingers_','thumb_','clavicle_'))}
        recipe=dict(bones=bones,forward='x',up='z')
        default=motion.retarget(m,sampled,recipe,'preserve')
        transferred=motion.retarget(m,sampled,dict(recipe,rotation_bones=['head']),'preserve')
        np.testing.assert_allclose(transferred.world[:,j,:3,:3],sampled.world[:,j,:3,:3],atol=1e-10)
        self.assertGreater(float(motion.angle(default.world[-1,j,:3,:3],transferred.world[-1,j,:3,:3])),70)
        np.testing.assert_array_equal(m.bind,before)
        with self.assertRaises(schema.Error) as error:motion.retarget(m,sampled,dict(recipe,rotation_bones=['unknown']))
        self.assertEqual(error.exception.code,'ANIM_UNKNOWN_BONE')
        with self.assertRaises(schema.Error):motion.retarget(m,sampled,dict(recipe,rotation_bones=[[]]))


class SceneSourceTests(unittest.TestCase):
    def scene(self):
        return dict(version=1,scene='fixture',actors={},shots=[dict(duration=2,
            camera=dict(keys=[dict(at=0,position=[10,20,30],angles=[1,2,3])]))])

    def test_native_roundtrip_is_exact_and_preserves_negative_queue_time(self):
        data,_=cine.compile_scene(self.scene());shots=reconstruction.parse_program(data)
        shots[0]['tracks']=[dict(classname='cine_hiro',unique='hero',tasks=[dict(kind='animation',when=-1.,
            destination=[0.,0.,0.],angles=[0.,0.,0.],attribute=0.,duration=0.,animation='ambba',use='',sound='',unique='hero')])]
        encoded=reconstruction.encode_program(shots)
        self.assertEqual(reconstruction.encode_program(reconstruction.parse_program(encoded)),encoded)
        self.assertEqual(reconstruction.parse_program(encoded)[0]['tracks'][0]['tasks'][0]['when'],-1)
        expected=Path(__file__).with_name('fixtures')/'cinematic-reconstruction.cfg'
        self.assertEqual(encoded,expected.read_bytes())

    def test_native_parser_rejects_trailing_nonfinite_truncated_and_unsafe_audio(self):
        data,_=cine.compile_scene(self.scene())
        for changed in (data+b'extra',data[:-8],data.replace(b'shot 2 ',b'shot nan '),
                        data.replace(b'sounds 0',b'sounds 1\n"../bad.wav" 0 2 0')):
            with self.subTest(data=changed),self.assertRaises((schema.Error,ValueError)):
                reconstruction.parse_program(changed)

    def test_reference_requires_valid_recorded_initial_transform(self):
        data,_=cine.compile_scene(self.scene());shot=reconstruction.parse_program(data)[0]
        spawn=dict(kind='spawn',when=-1.,destination=[1.,2.,3.],angles=[0.,90.,0.],attribute=0.,duration=0.,
                   animation='',use='',sound='',unique='hiro1')
        shot['tracks']=[dict(classname='cine_hiro',unique='hiro1',tasks=[spawn])]
        other=copy.deepcopy(shot);other['tracks'][0]['tasks']=[]
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);package=root/'data.pk3'
            with zipfile.ZipFile(package,'w') as z:z.writestr('dk3/cinematics/intro.cfg',reconstruction.encode_program([shot,other]))
            recipe=root/'ref.yaml';recipe.write_text(yaml.safe_dump(dict(version=1,source_program='dk3/cinematics/intro.cfg',source_shots=[1],actors=['hiro1'],scene='ref')))
            result=reconstruction.reference(package,recipe,root/'out')
            self.assertEqual(result['initial'][0]['destination'],[1,2,3])
            shot['tracks'][0]['tasks'].append(dict(spawn,kind='move'))
            with zipfile.ZipFile(package,'w') as z:z.writestr('dk3/cinematics/intro.cfg',reconstruction.encode_program([shot,other]))
            with self.assertRaises(schema.Error) as error:reconstruction.reference(package,recipe,root/'bad')
            self.assertEqual(error.exception.code,'CINE_REFERENCE_STATE')
            self.assertFalse((root/'bad').exists())

    def test_scene_package_is_deterministic_and_does_not_override_campaign(self):
        data,_=cine.compile_scene(self.scene())
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);program=root/'fixture.cfg';program.write_bytes(data)
            reconstruction.scene_package(program,[],root/'a.pk3')
            reconstruction.scene_package(program,[],root/'b.pk3')
            self.assertEqual((root/'a.pk3').read_bytes(),(root/'b.pk3').read_bytes())
            with zipfile.ZipFile(root/'a.pk3') as z:self.assertEqual(set(z.namelist()),{'dk3/cinematics/fixture.cfg','dk3/authoring/fixture.json'})
            with self.assertRaises(schema.Error) as error:
                reconstruction.scene_package(program,[root/'a.pk3'],root/'conflict.pk3')
            self.assertEqual(error.exception.code,'CINE_REPLACEMENT_CONFLICT')
            self.assertFalse((root/'conflict.pk3').exists())


class ManifestPublicationTests(unittest.TestCase):
    def test_check_only_and_unchanged_output_retain_bytes_and_timestamp(self):
        m=model();doc=document();doc['characters'][0]['clips']['walk'].update(target_frames=[0,0],contacts={})
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'hiro.iqm').write_bytes(sk.write(m));path=root/'manifest.yaml';path.write_text(yaml.safe_dump(doc));output=root/'native.cfg'
            checked=author.compile_manifest(path,output,check_only=True)
            self.assertFalse(output.exists());self.assertTrue(checked['check_only'])
            first=author.compile_manifest(path,output);stat=output.stat()
            second=author.compile_manifest(path,output)
            self.assertTrue(first['changed']);self.assertFalse(second['changed'])
            self.assertEqual((output.stat().st_mtime_ns,output.stat().st_ino),(stat.st_mtime_ns,stat.st_ino))
            self.assertEqual(checked['sha256'],first['sha256'])

    def test_compiler_rejects_unknown_contact_bone_with_stable_diagnostic(self):
        m=model();doc=document();doc['characters'][0]['clips']['walk'].update(target_frames=[0,0],contacts={'unknown':[[0,0]]})
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'hiro.iqm').write_bytes(sk.write(m));path=root/'manifest.yaml';path.write_text(yaml.safe_dump(doc))
            with self.assertRaises(schema.Error) as error:author.compile_manifest(path,check_only=True)
            diagnostic=error.exception.diagnostic(path)
            self.assertEqual(diagnostic['code'],'ANIM_UNKNOWN_BONE');self.assertEqual(diagnostic['field'],'hiro.walk')
            self.assertEqual(diagnostic['source'],str(path))

    def test_stable_range_path_and_duplicate_diagnostics(self):
        for operation,code in ((lambda:schema.span([4,3]),'ANIM_INVALID_RANGE'),
                               (lambda:schema.asset('../model.iqm'),'ANIM_INVALID_PATH'),
                               (lambda:schema.number(float('nan')),'ANIM_NONFINITE_TRANSFORM')):
            with self.assertRaises(schema.Error) as error:operation()
            self.assertEqual(error.exception.code,code)
        for field in ('character','clip'):
            doc=document()
            if field=='character':doc['characters'][0]['character']='../escape'
            else:doc['characters'][0]['clips']['../escape']=doc['characters'][0]['clips'].pop('walk')
            with self.assertRaises(schema.Error) as error:schema.validate(doc)
            self.assertEqual(error.exception.code,'ANIM_INVALID_PATH')
        with self.assertRaises(schema.Error):author.local(Path('/tmp/recipe'),'../../escape.npz')

    def test_bind_identity_detects_another_rig_and_compiler_preserves_inputs(self):
        m=model();doc=document();character=doc['characters'][0];character['clips']['walk'].update(target_frames=[0,0],contacts={})
        character['bind_pose_sha256']=schema.bind_identity(m);schema.validate_rig(character,m)
        changed=copy.deepcopy(m);changed.bind[0,0]+=.1
        with self.assertRaises(schema.Error) as error:schema.validate_rig(character,changed)
        self.assertEqual(error.exception.code,'ANIM_INCOMPATIBLE_SKELETON')
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);path=root/'manifest.yaml';path.write_text(yaml.safe_dump(doc));(root/'hiro.iqm').write_bytes(sk.write(m));before=path.read_bytes()
            with self.assertRaises(schema.Error):author.compile_manifest(path,path)
            self.assertEqual(path.read_bytes(),before)


class OriginalPresentationTests(unittest.TestCase):
    def test_invalid_preview_cli_returns_json_without_starting_guard_or_creating_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);output=root/'report'
            command=[sys.executable,'-B',preview.__file__,'record','--engine',str(root/'missing-engine'),
                     '--guard',str(root/'missing-guard'),'--report',str(output),'--map','intro;quit','--shots','3']
            result=subprocess.run(command,capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,1)
            diagnostic=json.loads(result.stderr)['diagnostics'][0]
            self.assertEqual(diagnostic['code'],'ANIM_INVALID_PATH')
            self.assertEqual(diagnostic['field'],'preview map');self.assertFalse(output.exists())

    def test_preview_rejects_console_injection_and_invalid_limits_before_launch(self):
        args=Namespace(operation='record',seconds=90,map='intr_retake',program='dojo_retake',trigger=3,shots=3)
        preview.validate_arguments(args)
        for field,value in (('map','intro;quit'),('program','../intro'),('trigger',0),('shots',257),('seconds',float('nan'))):
            invalid=copy.copy(args);setattr(invalid,field,value)
            with self.subTest(field=field),self.assertRaises(schema.Error):preview.validate_arguments(invalid)
        args=Namespace(operation='replay',seconds=90,demo=Path('author_preview.dm_1351'),fps=30)
        preview.validate_arguments(args)
        args.demo=Path('demo;quit.dm_1351')
        with self.assertRaises(schema.Error):preview.validate_arguments(args)

    def test_original_profile_excludes_optional_archive_and_rejects_cosmetic_overlay(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);engine=root/'engine';base=engine/'share/dk3';base.mkdir(parents=True)
            for name,entries in (('original.pk3',{'models/hiro.dkm.md3':b'original'}),('neural.pk3',{'dk3/neural-models.cfg':b'mapping'})):
                with zipfile.ZipFile(base/name,'w') as z:
                    for path,data in entries.items():z.writestr(path,data)
            settings={};home=root/'home'
            excluded=preview.presentation_settings(engine,home,settings,'legacy',[])
            self.assertEqual(excluded,[str(base/'neural.pk3')])
            profile=Path(settings['fs_basepath'])/'dk3'
            self.assertTrue((profile/'original.pk3').is_symlink());self.assertFalse((profile/'neural.pk3').exists())
            self.assertEqual((base/'original.pk3').read_bytes(),(profile/'original.pk3').read_bytes())
            with self.assertRaises(schema.Error):preview.presentation_settings(engine,root/'other',{},'legacy',[base/'neural.pk3'])


if __name__=='__main__':unittest.main()
