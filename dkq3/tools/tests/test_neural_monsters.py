# SPDX-License-Identifier: GPL-2.0-or-later
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import numpy as np
import skeletal_iqm as sk
from neural_monster_rig import fit,align
from neural_monster_skeleton import skeleton,fit_humanoid
from neural_rig import LANDMARKS,pose
from neural_monsters import package,record_stage,save
from neural_package import physics_rig,validate_package


def fixture():
    points=np.array([[x,y,z] for x in (-5,-3,3,5) for y in (-2,2) for z in (-1,1)],dtype=float)
    points=np.vstack([points,points+[0,0,4]])
    angles=np.deg2rad([0,60,179,240])
    rotation=np.array([[[np.cos(a),-np.sin(a),0],[np.sin(a),np.cos(a),0],[0,0,1]] for a in angles])
    translation=np.array([[0,0,0],[4,2,1],[8,-3,2],[9,6,1]])
    motion=np.einsum('fij,vj->fvi',rotation,points)+translation[:,None]
    tags=np.array([[0,0,7],[1,2,9],[3,4,10],[5,6,11]],dtype=float)
    source=dict(actor=dict(reference_frame=0),surfaces=[{}],tags=['tag_weapon'],
                metadata=dict(sequences=dict(frame_data=[dict(animation_name='ataka',first=0,last=3)])))
    vertices=np.vstack([points,points[0]])
    geometry={0:vertices,1:np.zeros((len(vertices),2)),2:np.tile([0,0,1.],(len(vertices),1))}
    triangles=np.array([[0,1,2],[2,3,4]])
    return fit(source,{'0_points':motion,'tag_tag_weapon':tags},geometry,
               [('body','models/neural/test/body',0,len(vertices),0,2)],triangles),motion,tags


class MonsterTest(unittest.TestCase):
    def test_uv_overlap_rejects_overpaint_but_allows_shared_edges(self):
        from neural_surface_quality import uv_quality
        model=SimpleNamespace(arrays={1:np.array([[0,0],[1,0],[0,1],[1,1]],float)},
                              triangles=np.array([[0,1,2],[1,3,2]]))
        self.assertEqual(dict(overlapping_triangle_pairs=0,degenerate_uv_triangles=0),uv_quality(model))
        model.triangles=np.array([[0,1,2],[0,1,2]])
        self.assertEqual(1,uv_quality(model)['overlapping_triangle_pairs'])
        model.triangles=np.array([[0,0,1]])
        self.assertEqual(1,uv_quality(model)['degenerate_uv_triangles'])

    def test_face_registration_moves_painted_eyes_into_sockets_and_keeps_canvas(self):
        from neural_face_registration import fit,project
        anchors=[dict(name='canvas',target=p,source=p) for p in ([0,0],[1,0],[0,1],[1,1])]
        anchors.extend([dict(name='eye left',target=[.43,.61],source=[.43,.66]),
                        dict(name='eye right',target=[.57,.61],source=[.57,.66]),
                        dict(name='mouth',target=[.5,.46],source=[.5,.46])])
        transform=fit(anchors)
        np.testing.assert_allclose(project([[.43,.61],[.57,.61]],transform),[[.43,.66],[.57,.66]],atol=1e-8)
        canvas=np.array([[.1,.9],[.9,.9],[.1,.1],[.9,.1]])
        np.testing.assert_allclose(project(canvas,transform),canvas,atol=1e-8)

    def test_face_registration_rejects_conflicting_or_invalid_landmarks(self):
        from neural_face_registration import fit
        for points in ([[0,0],[0,0],[1,1]],[[0,0],[.5,.5],[1,1]],[[0,0],[1,0],[0,float('nan')]]):
            with self.assertRaises(ValueError):fit([dict(target=p,source=p) for p in points])

    def test_face_registration_rejects_reversed_or_crossed_features(self):
        from neural_face_registration import fit,validate
        canvas=[dict(name='canvas',target=p,source=p) for p in ([0,0],[1,0],[0,1],[1,1])]
        self.assertAlmostEqual(1,validate(fit(canvas))['minimum_jacobian'])
        reversed_image=[dict(target=p,source=[1-p[0],p[1]]) for p in ([0,0],[1,0],[0,1],[1,1])]
        crossed=canvas+[dict(name='eye left',target=[.45,.6],source=[.6,.6]),
                        dict(name='eye right',target=[.55,.6],source=[.4,.6])]
        for anchors in (reversed_image,crossed):
            with self.assertRaisesRegex(ValueError,'folds or collapses'):validate(fit(anchors))

    def test_surface_quality_recognizes_uv_seams_and_rejects_animation_changes(self):
        from neural_surface_quality import topology,animation_preservation
        (model,_),_,_=fixture()
        # A tetrahedron remains closed when a vertex is duplicated for a UV seam.
        points=np.array([[0,0,0],[1,0,0],[0,1,0],[0,0,1],[0,0,0]],float)
        model.arrays[0]=points
        model.arrays[5]=np.tile([255,0,0,0],(5,1)).astype('u1')
        model.triangles=np.array([[4,1,2],[0,3,1],[0,2,3],[1,3,2]])
        self.assertEqual(dict(boundary_edges=0,nonmanifold_edges=0,degenerate_triangles=0),topology(model))
        model.triangles=model.triangles[:3]
        self.assertEqual(3,topology(model)['boundary_edges'])
        changed=sk.Model(model.arrays,model.meshes,model.triangles,model.names,model.parents,model.bind,model.frames.copy())
        changed.frames[0,0,0]+=1
        with self.assertRaises(ValueError):animation_preservation(model,changed)

    def test_quadruped_keeps_connected_lengths_and_source_event_frames(self):
        from neural_quadruped import build
        points=np.array([[x,y,z] for x in (-25,-10,2,12) for y in (-13,0,13) for z in (-12,6,20)],float)
        channels=np.array([[0,0,0,0,0,0,1,1,1,1]],float)
        model=sk.Model({0:points,1:np.zeros((len(points),2)),2:np.tile([0.,0,1],(len(points),1)),
            4:np.zeros((len(points),4),dtype='u1'),5:np.tile([255,0,0,0],(len(points),1)).astype('u1')},
            [('body','body',0,len(points),0,1)],np.array([[0,1,2]]),['creature_00'],[-1],channels,channels[None])
        source=dict(metadata=dict(frames=list(range(32)),sequences=dict(frame_data=[
            dict(animation_name=n,first=i*8,last=i*8+7) for i,n in enumerate(('amba','runa','ataka','diea'))])))
        result,report=build(model,source);data=sk.write(result);restored=sk.read(data);physics_rig(data,'articulated')
        self.assertEqual(32,len(restored.frames));self.assertEqual(source['metadata']['sequences']['frame_data'],report['clips'])
        np.testing.assert_array_equal(restored.arrays[0],points)
        np.testing.assert_allclose(restored.frames[:,1:,:3],np.broadcast_to(restored.bind[1:,:3],restored.frames[:,1:,:3].shape),atol=.002)
        self.assertTrue(np.isfinite(sk.skin(restored)).all())
        self.assertEqual([f'creature_{i:02}' for i in range(16)],restored.names)

    def test_seam_face_registration_rejects_changed_shape(self):
        from neural_topology import face_deviation
        face=np.array([[2.,y,z] for y in (-1.,0.,1.) for z in (23.,25.,27.)])
        self.assertAlmostEqual(.05,face_deviation(face,face+[.05,0,0],(22,30,3,-2))['maximum'])
        with self.assertRaisesRegex(ValueError,'changed the registered face'):
            face_deviation(face,face+[2.,0,0],(22,30,3,-2))

    def test_missing_creature_normals_are_reconstructed_without_motion_changes(self):
        from neural_surface import head_normals
        (model,_),_,_=fixture()
        used=np.unique(model.triangles)
        model.arrays[2][used]=0
        source=sk.write(model)
        output,report=head_normals(source)
        self.assertEqual(len(used),report['missing_normals'])
        a,b=sk.read(source),sk.read(output)
        for kind in (0,1,4,5):np.testing.assert_array_equal(a.arrays[kind],b.arrays[kind])
        np.testing.assert_array_equal(a.frames,b.frames)
        np.testing.assert_array_equal(a.bind,b.bind)
        self.assertTrue(np.all(np.linalg.norm(b.arrays[2],axis=1)>.99))

    def test_head_lighting_repairs_seams_without_changing_other_iqm_bytes(self):
        from neural_surface import head_normals,normal_range,tangent_range
        points=np.array([[0,0,0],[0,1,0],[0,0,1],[0,0,0],[0,0,1],[0,-1,0]],dtype=float)
        bind=np.array([[0,0,0,0,0,0,1,1,1,1]],dtype=float)
        model=sk.Model({0:points,1:np.zeros((6,2)),2:np.array([[1,0,0],[-1,0,0],[0,1,0],[0,0,-1],[0,-1,0],[-1,0,0]],dtype=float),
                        4:np.zeros((6,4),dtype=np.uint8),5:np.tile([255,0,0,0],(6,1)).astype(np.uint8)},
                       [('face','models/neural/test/body',0,6,0,2)],np.array([[0,2,1],[3,5,4]]),
                       ['head'],[-1],bind,np.tile(bind,(2,1,1)))
        source=sk.write(model);output,report=head_normals(source);offset,size=normal_range(source)
        cursor=0
        for first,length in sorted(report['lighting_byte_ranges']):
            self.assertEqual(source[cursor:first],output[cursor:first]);cursor=first+length
        self.assertEqual(source[cursor:],output[cursor:])
        self.assertEqual(6,report['vertices']);self.assertGreater(report['changed_vertices'],0)
        normals=sk.read(output).arrays[2]
        np.testing.assert_allclose(normals,np.tile([1,0,0],(6,1)),atol=1e-6)
        first,length=tangent_range(output)
        tangent=np.frombuffer(output,'<f4',count=length//4,offset=first).reshape(-1,4)
        np.testing.assert_allclose((normals*tangent[:,:3]).sum(axis=1),0,atol=1e-6)
        np.testing.assert_allclose(sk.read(head_normals(output)[0]).arrays[2],normals)

    def test_mechanical_claws_use_distal_arm_joints_and_rigid_triangles(self):
        from neural_mechanical import arms,rigid_panels,motion
        from neural_rig import skin_weights
        config=dict(LANDMARKS['hiro'])
        measured=np.array([[x,sign*(y+dy),z+dz]
            for sign in (1,-1) for y,z in ((16,21),(20,11),(24,-6))
            for x in (-.2,.2) for dy in (-.2,.2) for dz in (-.2,.2)])
        config.update(arms(measured,'sludgeminion'))
        self.assertEqual(-6,config['arm_l'][-1][2])
        names,parents,absolute=skeleton(config)
        points=np.array([[0,24,-9],[.1,24,-9],[0,24.1,-9],
                         [0,-24,-9],[.1,-24,-9],[0,-24.1,-9]],float)
        bind=sk.channels(absolute,parents)
        model=sk.Model({0:points,1:np.zeros((6,2)),2:np.tile([1.,0,0],(6,1))},
                       [('body','body',0,6,0,2)],np.array([[0,1,2],[3,4,5]]),names,parents,bind,bind[None])
        skin_weights(model,'sludgeminion',absolute,landmarks=config)
        rigid_panels(model)
        self.assertTrue(all(names[i].startswith('hand_') for i in model.arrays[4][:,0]))
        model.frames=np.asarray([motion(model,absolute,p,kind) for kind in ('idle','run','attack','death') for p in (0,.25,.5,.75,1)])
        restored=sk.read(sk.write(model));physics_rig(sk.write(model),'humanoid')
        positions=sk.skin(restored)
        for triangle in restored.triangles:
            for a,b in ((0,1),(1,2),(2,0)):
                lengths=np.linalg.norm(positions[:,triangle[a]]-positions[:,triangle[b]],axis=1)
                np.testing.assert_allclose(lengths,lengths[0],atol=.002)

    def test_robes_keep_floor_hem_and_release_a_pose_hands(self):
        from neural_rig import skin_weights
        config=dict(LANDMARKS['hiro']);config['arm_l']=config['arm'];config['arm_r']=(np.asarray(config['arm'])*[1,-1,1]).tolist()
        names,parents,absolute=skeleton(config)
        for name,p in [('cloth_front',[4,0,5]),('cloth_back',[-3,0,5])]:
            names.append(name);parents.append(0);a=np.eye(4);a[:3,3]=p;absolute=np.concatenate((absolute,a[None]))
        p=np.array([[0,15,3],[.1,15,3],[0,15.1,3],[0,0,-23],[.1,0,-23],[0,.1,-23]])
        arrays={0:p,1:np.zeros((6,2)),2:np.tile([1.,0,0],(6,1))}
        model=sk.Model(arrays,[('body','body',0,6,0,2)],np.array([[0,1,2],[3,4,5]]),names,parents,sk.channels(absolute,parents),sk.channels(absolute,parents)[None])
        skin_weights(model,'priest',absolute,landmarks=config)
        winners=[names[i] for i in model.arrays[4][:,0]]
        self.assertTrue(all(n.startswith(('hand_','fingers_','forearm_','thumb_')) for n in winners[:3]),winners)
        self.assertTrue(all(n.startswith('cloth_') for n in winners[3:]),winners)

    def test_pod_hatch_retains_rigid_shell_panels_and_source_interval(self):
        from neural_pod import fit_pod
        points=np.array([[0,0,12],[0,0,-12],[8,0,0],[0,8,0],[-8,0,0],[0,-8,0]],float)
        tri=np.array([[0,2,3],[0,3,4],[0,4,5],[0,5,2],[1,3,2],[1,4,3],[1,5,4],[1,2,5]])
        document=dict(metadata=dict(frames=list(range(23)),sequences=dict(frame_data=[dict(animation_name='amba',first=0,last=10),dict(animation_name='hatcha',first=11,last=22)])))
        model,report=fit_pod(document,{0:points,1:np.zeros((6,2)),2:np.tile([1.,0,0],(6,1))},[('body','body',0,6,0,8)],tri)
        model=sk.read(sk.write(model));physics_rig(sk.write(model),'anchored')
        poses=sk.skin(model);rest=poses[0]
        for t in model.triangles:
            for a,b in ((0,1),(1,2),(2,0)):
                np.testing.assert_allclose(np.linalg.norm(poses[:,t[a]]-poses[:,t[b]],axis=1),np.linalg.norm(rest[t[a]]-rest[t[b]]),atol=.002)
        np.testing.assert_allclose(poses[:12],np.repeat(rest[None],12,axis=0),atol=.002)
        self.assertGreater(np.max(np.linalg.norm(poses[-1]-rest,axis=1)),2)
        self.assertEqual(23,report['output_frames'])

    def test_changed_face_projection_is_rejected_before_atlas_mutation(self):
        from neural_monster_face import bake
        with tempfile.TemporaryDirectory() as temporary:
            actor=Path(temporary)
            (actor/'model.iqm').write_bytes(b'reviewed mesh')
            (actor/'face-projection.png').write_bytes(b'changed projection')
            (actor/'body.png').write_bytes(b'original atlas')
            save(actor/'face-plan.json',dict(mesh_sha256=hashlib.sha256(b'reviewed mesh').hexdigest(),
                 projection_sha256=hashlib.sha256(b'reviewed projection').hexdigest()))
            with patch('neural_monster_face.subprocess.run') as conversion:
                with self.assertRaisesRegex(ValueError,'Reviewed face input changed'):bake(actor,'blender',{})
                conversion.assert_not_called()
            self.assertEqual(b'original atlas',(actor/'body.png').read_bytes())
            self.assertFalse((actor/'body-before-face.png').exists())

    def test_character_master_is_independent_of_cinematic_source_offset(self):
        points=[]
        for sign in (1,-1):
            for y,z in ((8,21),(12,13),(15,6)):
                points.extend([[x,sign*(y+dy),z+dz] for x in (-1,1) for dy in (-.3,.3) for dz in (-.3,.3)])
        points.extend([[0,0,32],[0,0,17],[0,0,12],[0,6,-24],[0,-6,-24]])
        points=np.asarray(points,float)
        document=dict(actor=dict(slug='hiro',kind='character'),tags=[],metadata=dict(frames=['one']))
        def fitted(offset):
            geometry={0:points+offset,1:np.zeros((len(points),2)),2:np.tile([1.,0,0],(len(points),1))}
            return fit_humanoid(document,{},geometry,[('body','body',0,len(points),0,1)],np.array([[0,1,2]]))[0]
        first,shifted=fitted(np.zeros(3)),fitted(np.array([19.,-9.,3.]))
        np.testing.assert_allclose(first.arrays[0],shifted.arrays[0],atol=1e-10)
        np.testing.assert_array_equal(first.arrays[4],shifted.arrays[4])
        np.testing.assert_array_equal(first.arrays[5],shifted.arrays[5])
        np.testing.assert_allclose(first.frames,shifted.frames,atol=1e-8)

    def test_two_body_joints_and_one_attachment_have_four_iqm_influence_slots(self):
        # Mosquito sources have only two motion regions. The independent tag
        # makes three total joints; IQM still requires four padded byte slots.
        with patch('neural_monster_rig.clusters',side_effect=lambda points,*args,**kwargs:(points[:,0]>0).astype(int)):
            (model,_),_,_=fixture()
        self.assertEqual(3,len(model.names))
        self.assertEqual((len(model.arrays[0]),4),model.arrays[4].shape)
        np.testing.assert_array_equal(model.arrays[5].sum(axis=1),255)
        restored=sk.read(sk.write(model))
        self.assertTrue(np.isfinite(sk.skin(restored)).all())

    def test_a_pose_axes_do_not_follow_an_asymmetric_source_pose(self):
        points=np.array([[3.,-12,6],[3,12,6],[5,0,30]])
        geometry={0:points.copy(),2:np.tile([1.,0,0],(3,1))}
        report=align({'actor':{'slug':'mishimaguard'}},{},geometry)
        self.assertEqual(0,report['yaw_degrees'])
        np.testing.assert_array_equal(points,geometry[0])

    def test_authored_anatomical_motion_retains_lengths_and_humanoid_physics(self):
        config=dict(LANDMARKS['hiro'])
        config['arm_l']=config['arm']
        config['arm_r']=(np.asarray(config['arm'])*[1,-1,1]).tolist()
        names,parents,absolute=skeleton(config)
        bind=sk.channels(absolute,parents)
        geometry={0:np.array([[0.,0,27],[1,0,27],[0,1,27]]),1:np.zeros((3,2)),
                  2:np.tile([1.,0,0],(3,1)),4:np.tile([4,0,0,0],(3,1)),5:np.tile([255,0,0,0],(3,1))}
        model=sk.Model(geometry,[('body','body',0,3,0,1)],np.array([[0,1,2]]),names,parents,bind,bind[None])
        for kind in ('idle','walk','run','crouch_walk','jump','attack','death'):
            frames=np.asarray([pose(model,absolute,p,kind,'relaxed') for p in (0,.25,.5,.75,1)])
            np.testing.assert_allclose(np.linalg.norm(frames[:,1:,:3],axis=-1),
                np.tile(np.linalg.norm(bind[1:,:3],axis=-1),(len(frames),1)),atol=1e-8)
        model.frames=frames
        physics_rig(sk.write(model),'humanoid')
        with self.assertRaisesRegex(ValueError,'creature body'):physics_rig(sk.write(model))
        model.names[model.names.index('hand_l')]='missing_hand'
        with self.assertRaisesRegex(ValueError,'anatomical humanoid'):physics_rig(sk.write(model),'humanoid')

    def test_fitted_rotation_preserves_motion_hardpoints_seams_and_iqm_roundtrip(self):
        (model,report),motion,tags=fixture()
        self.assertEqual(4,report['output_frames'])
        self.assertLess(report['maximum_residual'],1e-9)
        np.testing.assert_allclose(sk.skin(model)[:,:len(motion[0])],motion,atol=1e-8)
        np.testing.assert_array_equal(model.arrays[4][0],model.arrays[4][-1])
        np.testing.assert_array_equal(model.arrays[5][0],model.arrays[5][-1])
        encoded=sk.write(model)
        physics_rig(encoded)
        restored=sk.read(encoded)
        np.testing.assert_allclose(sk.skin(restored)[:,:len(motion[0])],motion,atol=.002)
        np.testing.assert_allclose(sk.matrices(restored.frames,restored.parents)[:,-1,:3,3],tags,atol=.002)

    def test_invalid_physics_skeleton_is_rejected(self):
        (model,_),_,_=fixture()
        model.names[1]='creature_99'
        with self.assertRaisesRegex(ValueError,'hierarchy'): physics_rig(sk.write(model))

    def test_stale_package_inputs_cannot_replace_the_prior_overlay(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            base=root/'assets/packages/dk3-models.pk3'
            base.parent.mkdir(parents=True);base.write_bytes(b'base')
            actor=root/'test';actor.mkdir()
            (model,_),_,_=fixture()
            files={'source.npz':b'npz','source.json':b'json','photo.png':b'photo','side.png':b'side',
                   'prompt.txt':b'prompt','concept.png':b'concept','model.glb':b'glb','trellis.json':b'trellis',
                   'model.iqm':sk.write(model),'body.png':b'\x89PNG\r\n\x1a\nfixture','conversion.json':b'{}'}
            for name,data in files.items(): (actor/name).write_bytes(data)
            sha=lambda n:hashlib.sha256(files[n]).hexdigest()
            stage=lambda outputs,inputs:dict(state='complete',outputs={n:sha(n) for n in outputs},inputs={n:sha(n) for n in inputs})
            stages=dict(capture=stage(['photo.png','side.png'],['source.npz','source.json']),
                        concept=stage(['concept.png'],['photo.png','prompt.txt']),
                        trellis=stage(['model.glb','trellis.json'],['concept.png','prompt.txt']),
                        convert=stage(['model.iqm','body.png','conversion.json'],['source.npz','source.json','model.glb','trellis.json']))
            document=dict(actors=[dict(slug='test',source='models/e1/test.dkm',physics='articulated',stages=stages)],
                          assets=str(root/'assets'),source_models_sha256=hashlib.sha256(b'base').hexdigest(),episode=1)
            save(root/'pipeline.json',document)
            args=SimpleNamespace(out=root,characters=None)
            package(args)
            previous=(root/'dk3-neural-episode.pk3').read_bytes()
            validate_package(root/'dk3-neural-episode.pk3',base)
            (actor/'concept.png').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'Changed stage'): package(args)
            self.assertEqual(previous,(root/'dk3-neural-episode.pk3').read_bytes())

    def test_independent_stage_updates_retain_other_actor_receipts(self):
        with tempfile.TemporaryDirectory() as temporary:
            ledger=Path(temporary)/'pipeline.json'
            save(ledger,dict(actors=[dict(slug='a',stages={}),dict(slug='b',stages={})]))
            record_stage(ledger,'a','trellis',dict(state='complete'))
            record_stage(ledger,'b','concept',dict(state='complete'))
            rows=json.loads(ledger.read_text())['actors']
            self.assertEqual('complete',rows[0]['stages']['trellis']['state'])
            self.assertEqual('complete',rows[1]['stages']['concept']['state'])
