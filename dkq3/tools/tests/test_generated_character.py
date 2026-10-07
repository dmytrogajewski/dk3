# SPDX-License-Identifier: GPL-2.0-or-later
import copy
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

import animation_manifest as schema
import generated_character as generated
import animation_motion as motion
import generated_materials as materials
import generated_atlas_bake as atlas_bake
import neural_character_export as export
import cinematic_model as admission
import skeletal_iqm as sk
from tests.test_animation_author import model


def landmarks():
    return dict(torso=[[0,0,4],[0,0,11],[0,0,18],[0,0,23],[0,0,27]],
                arm_l=[[0,7,20],[0,12,12],[0,15.5,5]],
                arm_r=[[0,-7,20],[0,-12,12],[0,-15.5,5]],
                leg=[[0,3.5,3],[0,5,-9],[0,6.5,-21]],toe=[4,6.5,-23])


class GeneratedCharacterTests(unittest.TestCase):
    def test_collar_weights_preserve_skin_and_lower_body(self):
        source=model();source.arrays[0][:,2]=[23,23,17]
        source.arrays[4][:]=[source.names.index('head'),0,0,0];source.arrays[5][:]=[255,0,0,0]
        before=copy.deepcopy(source)
        result=generated.collar_ownership(source,np.array([[.8,.79,.77],[.6,.4,.3],[.8,.79,.77]]),[18,21])
        self.assertEqual(result['vertices'],1);self.assertEqual(source.arrays[4][0,0],source.names.index('chest'))
        for key in (0,1,2):np.testing.assert_array_equal(source.arrays[key],before.arrays[key])
        for key in (4,5):np.testing.assert_array_equal(source.arrays[key][1:],before.arrays[key][1:])

    def test_approved_face_keeps_shape_uvs_and_source_while_reposing(self):
        source=model();source.arrays[0][:]=[[0,0,25],[1,0,26],[0,1,26]]
        before=copy.deepcopy(source);rotation=np.array([[0.,-1,0],[1,0,0],[0,0,1]])
        result=generated.neutral_admitted_head(source,rotation,[20.5,23.5],[2.55,-.08,.75])
        origin=sk.matrices(source.bind,source.parents)[source.names.index('head'),:3,3]
        np.testing.assert_allclose(result.arrays[0],(source.arrays[0]-origin)@rotation+origin+[2.55,-.08,.75])
        np.testing.assert_array_equal(result.arrays[1],source.arrays[1])
        np.testing.assert_array_equal(result.triangles,source.triangles)
        np.testing.assert_array_equal(result.arrays[5][:,0],255)
        self.assertTrue(np.all(result.arrays[4][:,0]==source.names.index('head')))
        for key in source.arrays:np.testing.assert_array_equal(source.arrays[key],before.arrays[key])
        with self.assertRaises(schema.Error):generated.neutral_admitted_head(source,np.diag([-1.,1,1]),[20.5,23.5],[0,0,0])

    def test_neck_bridge_closes_both_unequal_loops_without_moving_the_face(self):
        def cylinder(count,lower,upper,bone):
            m=model();angle=np.arange(count)*2*np.pi/count
            ring=np.column_stack((np.cos(angle),np.sin(angle)))
            m.arrays={0:np.vstack((np.column_stack((ring,np.full(count,lower))),np.column_stack((ring,np.full(count,upper))))),
                1:np.tile([.3,.4],(count*2,1)),2:np.tile(np.column_stack((ring,np.zeros(count))),(2,1)),
                4:np.tile([m.names.index(bone),0,0,0],(count*2,1)).astype('u1'),5:np.tile([255,0,0,0],(count*2,1)).astype('u1')}
            m.triangles=np.array([[i,(i+1)%count,i+count] for i in range(count)]+[[i+count,(i+1)%count,(i+1)%count+count] for i in range(count)])
            m.meshes=[('neck','models/neck',0,count*2,0,count*2)];return m
        body=cylinder(8,21,23,'neck');head=cylinder(11,23.25,26,'head');original=copy.deepcopy(head)
        rows,report=generated.join_neck(body,head,23,23.25,[0,0])
        self.assertEqual(len(rows),19);self.assertEqual(report['head_boundary_vertices'],11)
        def edges(triangles):
            from collections import Counter
            result=Counter()
            for triangle in triangles:
                p=[tuple(np.round(c,5)) for c in triangle]
                for a,b in zip(p,p[1:]+p[:1]):result[tuple(sorted((a,b)))]+=1
            return result
        counts=edges(body.arrays[0][body.triangles])+edges(head.arrays[0][head.triangles])+edges([[c[0] for c in row] for row in rows])
        for edge,count in counts.items():
            if all(p[2] in (23,23.25) for p in edge):self.assertEqual(count,2)
        for key in head.arrays:np.testing.assert_array_equal(head.arrays[key],original.arrays[key])
        with self.assertRaises(schema.Error):generated.join_neck(body,head,23,23.25,[9,9])

    def test_material_input_hash_keeps_candidate_arrays_immutable(self):
        source=model();before={key:value.copy() for key,value in source.arrays.items()}
        first=generated.neutral_geometry_sha(source.arrays,source.meshes,source.triangles)
        self.assertEqual(first,generated.neutral_geometry_sha(source.arrays,source.meshes,source.triangles))
        self.assertEqual(set(source.arrays),set(before))
        for key,value in before.items():np.testing.assert_array_equal(source.arrays[key],value)

    def test_generated_head_stays_rigid_and_only_lower_neck_blends(self):
        source=model();source.names=['pelvis','neck','head'];source.parents=[-1,0,1]
        source.arrays[0]=np.array([[0.,0,26],[0,0,24],[0,6,23]])
        source.arrays[4]=np.zeros((3,4),dtype='u1');source.arrays[5]=np.tile([255,0,0,0],(3,1)).astype('u1')
        original={key:value.copy() for key,value in source.arrays.items()}
        settings=dict(neck_min_z=21.,head_min_z=25.,half_width=4.)
        report=generated.head_ownership(source,settings)
        self.assertEqual(report['rigid_head_vertices'],1)
        self.assertEqual(source.arrays[4][0,0],2)
        self.assertEqual(source.arrays[5][0,0],255)
        self.assertTrue(0<source.arrays[5][1,0]<255)
        np.testing.assert_array_equal(source.arrays[5][2],original[5][2])
        for key in (0,1,2):np.testing.assert_array_equal(source.arrays[key],original[key])
        self.assertTrue(np.all(source.arrays[5].sum(axis=1)==255))
        with self.assertRaises(schema.Error):generated.head_ownership(source,settings|dict(head_min_z=21.2))

    def test_shared_neck_yaw_preserves_both_joint_endpoints(self):
        names,_,neutral=generated.neutral_rig(landmarks());world=np.repeat(neutral[None],2,axis=0)
        j=names.index('neck');head=names.index('head')
        world[0,head,:3,:3]=np.array([[0.,-1,0],[1,0,0],[0,0,1]])
        before=world.copy();motion.share_neck_turn(world,names,.5)
        np.testing.assert_array_equal(world[:,:,:3,3],before[:,:,:3,3])
        np.testing.assert_array_equal(world[:,head],before[:,head])
        np.testing.assert_allclose(world[0,j,:3,:3]@np.array([1.,0,0]),[2**-.5,2**-.5,0],atol=1e-10)
        np.testing.assert_allclose(world[1,j,:3,:3],np.eye(3),atol=1e-10)

    def test_lower_neck_rounding_keeps_normalized_weights_without_unsigned_underflow(self):
        source=model();source.names=['pelvis','neck','head','chest'];source.parents=[-1,0,1,0]
        source.arrays[0]=np.array([[0.,0,22],[0,0,23],[0,0,24]])
        source.arrays[4]=np.zeros((3,4),dtype='u1');source.arrays[5]=np.tile([255,0,0,0],(3,1)).astype('u1')
        generated.head_ownership(source,dict(neck_min_z=21.,head_min_z=25.,half_width=4.))
        self.assertTrue(np.all(source.arrays[5].sum(axis=1)==255))
        self.assertEqual(source.arrays[5][0,0],0)

    def test_surface_export_rejects_unbounded_or_nonfinite_parameters(self):
        export.validate_settings(3.,0.,100000)
        for band,projection,triangles in [(float('nan'),0.,100000),(9.,0.,100000),(3.,float('inf'),100000),(3.,-.1,100000),(3.,0.,100001),(3.,0.,True)]:
            with self.subTest(values=(band,projection,triangles)),self.assertRaises(ValueError):
                export.validate_settings(band,projection,triangles)

    def test_per_texel_corrections_preserve_valid_cloth_detail_and_exposed_skin(self):
        points=np.array([[-3.,0,20],[-3,0,20],[-3,0,20],[2,0,16],[0,0,9]])
        rgb=np.array([[.8,.78,.74],[.62,.60,.58],[.65,.43,.30],[.65,.43,.30],[.25,.24,.22]])
        corrected,report=atlas_bake.correct_samples(points,rgb)
        np.testing.assert_array_equal(corrected[:2],rgb[:2]);np.testing.assert_array_equal(corrected[3],rgb[3])
        self.assertLess(np.ptp(corrected[2]),.04)
        np.testing.assert_allclose(corrected[4],rgb[4]*.7)
        self.assertEqual(report['cotton_correction_samples'],1)
        self.assertEqual(report['leather_samples'],1)

    def test_material_repair_removes_skin_and_hair_contamination_from_cotton(self):
        points=np.array([[-3.,y,z] for y in (-3.,0,3) for z in (16.,18,20)] + [[-3,1,19],[0,6,-22]])
        colors=np.tile([.7,.68,.65],(len(points),1));colors[0]=[.25,.05,.01];colors[9]=[.02,.02,.02]
        repaired,report=materials.repair_generated_albedo(points,colors)
        np.testing.assert_allclose(repaired[[0,9]],[[.7,.68,.65]]*2)
        np.testing.assert_allclose(repaired[10],colors[10]*.45)
        np.testing.assert_allclose(colors[0],[.25,.05,.01])
        self.assertEqual(report['repaired_cloth_samples'],2)

    def test_generated_surface_transfer_samples_its_own_chart_and_iqm_origin(self):
        points=np.array([[0.,0,0],[2,0,0],[0,2,0]])
        uv=np.array([[0.,0],[1,0],[0,1]])
        actual=materials.transferred_uv(points,uv,np.array([0,1,2]),np.array([.5,.5,0]))
        np.testing.assert_allclose(actual,[.25,.25])
        image=np.array([[[255,0,0],[0,255,0]],[[0,0,255],[255,255,255]]],dtype='u1')
        np.testing.assert_allclose(materials.sample_uv_rgb(image,np.array([[0.,0],[0,1],[.5,.5]])),[[1,0,0],[0,0,1],[.5,.5,.5]])
        with self.assertRaises(schema.Error):materials.transferred_uv(points,uv,np.array([0,1,3]),np.zeros(3))
        with self.assertRaises(schema.Error):materials.sample_uv_rgb(image,np.array([[np.nan,0]]))

    def test_head_collar_clip_preserves_uv_normal_and_weight_at_the_boundary(self):
        source=model();source.meshes=[('head','models/neural/hiro/head',0,3,0,1)]
        source.arrays[0]=np.array([[0.,0,21],[2,0,23],[0,2,23]])
        rows=generated.admitted_head_rows(source,'models/neural/hiro/head',22.)
        self.assertTrue(rows);self.assertTrue(all(corner[0][2]>=22 for row in rows for corner in row))
        self.assertTrue(any(np.isclose(corner[0][2],22) for row in rows for corner in row))
        self.assertTrue(all(sum(corner[5])==255 for row in rows for corner in row))
        np.testing.assert_array_equal(source.arrays[0],[[0,0,21],[2,0,23],[0,2,23]])

    def test_local_anatomy_volumes_follow_generated_scale_and_reject_unbounded_input(self):
        points=np.array([[x,y,z] for x in (-1.,0,1) for y in (-1.,0,1) for z in (-24.,12,16,32)])
        volumes=[dict(center=[0,0,4],radii=[3,4,5])]
        actual=generated.anatomy_volumes(points,volumes)
        np.testing.assert_allclose(actual[0]['center'],[0,0,4])
        moved=generated.anatomy_volumes(points*2+[7,4,-2],volumes)
        np.testing.assert_allclose(moved[0]['center'],[7,4,6])
        np.testing.assert_allclose(moved[0]['radii'],[6,8,10])
        for invalid in (volumes*17,[dict(center=[0,0,0],radii=[1,-1,1])]):
            with self.assertRaises(schema.Error):generated.anatomy_volumes(points,invalid)

    def test_material_regions_keep_open_chest_cloth_bracers_and_feet_distinct(self):
        points=np.array([[2.,0,16],[-3,0,20],[2,2.175,20],[0,14,8],[0,0,9],[0,5,-10],[0,6,-22]])
        colors=materials.garment_colors(points)
        np.testing.assert_allclose(colors[0],[.62,.43,.31])
        np.testing.assert_allclose(colors[[1,5]],[[.78,.765,.715]]*2)
        np.testing.assert_allclose(colors[[2,3,4,6]],[[.045,.05,.043]]*4)
        with self.assertRaises(schema.Error):materials.garment_colors(np.array([[0.,np.nan,0]]))

    def test_model_admission_rejects_an_unrelated_authored_texture(self):
        with tempfile.TemporaryDirectory() as root:
            directory=Path(root);payload=sk.write(model());(directory/'generated.iqm').write_bytes(payload)
            texture=directory/'wrong.png';texture.write_bytes(b'wrong')
            target='models/neural/hiro.iqm';source='models/characters/hiro.dkm'
            report=dict(passed=True,model_file='generated.iqm',source_model=source,
                        output_sha256=schema.sha(directory/'generated.iqm'),material_authoring=dict(output_sha256='0'*64))
            with self.assertRaises(schema.Error) as failure:
                admission.admit_repair({target:payload},{source:target},{},directory,texture,target,report,'1'*64)
            self.assertEqual(failure.exception.code,'ANIM_SOURCE_HASH_MISMATCH')

    def test_neutral_rig_rejects_invalid_landmarks_before_fitting(self):
        for update in (dict(arm_l=[]),dict(toe=[0,0,float('nan')]),dict(extra=1)):
            with self.subTest(update=update),self.assertRaises(schema.Error):
                generated.neutral_rig(landmarks()|update)
        bad=landmarks();bad['arm_l'][1]=bad['arm_l'][0].copy()
        with self.assertRaisesRegex(schema.Error,'degenerate'):generated.neutral_rig(bad)

    def test_reference_mapping_matches_segment_endpoints_without_reflection(self):
        names,_,neutral=generated.neutral_rig(landmarks());target=neutral.copy()
        target[:,:3,3]+=[2,-3,1]
        target[names.index('forearm_l'),:3,3]=[8,8,16]
        transform=generated.segment_transforms(names,neutral,names,target)
        for name,child in (('upperarm_l','forearm_l'),('forearm_l','hand_l'),('shin_r','foot_r')):
            j=names.index(name);c=names.index(child)
            np.testing.assert_allclose(transform[j,:3,:3]@neutral[j,:3,3]+transform[j,:3,3],target[j,:3,3],atol=1e-10)
            np.testing.assert_allclose(transform[j,:3,:3]@neutral[c,:3,3]+transform[j,:3,3],target[c,:3,3],atol=1e-10)
        self.assertTrue(np.all(np.linalg.det(transform[:,:3,:3])>0))
        self.assertEqual(int(np.isclose(np.linalg.svd(transform[names.index('upperarm_l'),:3,:3])[1],1,atol=1e-10).sum()),2)

    def test_reference_mapping_rejects_missing_and_nonfinite_bones(self):
        names,_,neutral=generated.neutral_rig(landmarks())
        with self.assertRaises(schema.Error) as failure:
            generated.segment_transforms(names,neutral,names[:-1],neutral[:-1])
        self.assertEqual(failure.exception.code,'ANIM_UNKNOWN_BONE')
        target=neutral.copy();target[0,0,3]=np.inf
        with self.assertRaises(schema.Error) as failure:
            generated.segment_transforms(names,neutral,names,target)
        self.assertEqual(failure.exception.code,'ANIM_NONFINITE_TRANSFORM')

    def test_deformation_transfers_normals_for_nonuniform_axial_scale(self):
        transform=np.eye(4)[None];transform[0,:3,:3]=np.diag([2,1,.5]);transform[0,:3,3]=[1,2,3]
        points=np.array([[1.,2,3]]);normals=np.array([[1.,1,0]])/np.sqrt(2)
        posed,n=generated.deform(points,normals,np.zeros((1,4),int),np.array([[255,0,0,0]]),transform)
        np.testing.assert_allclose(posed,[[3,4,4.5]])
        np.testing.assert_allclose(n,[[1/np.sqrt(5),2/np.sqrt(5),0]])

    def test_cleanup_repairs_zero_normals_and_omits_zero_area_faces(self):
        arrays={0:np.array([[0.,0,0],[1,0,0],[0,1,0]]),1:np.zeros((3,2)),2:np.zeros((3,3))}
        before=copy.deepcopy(arrays)
        output,meshes,tri,report=generated.clean_geometry(arrays,np.array([[0,2,1],[0,0,1]]),'models/neural/new/body')
        self.assertEqual(len(tri),1);self.assertEqual(report['removed_degenerate_triangles'],1)
        np.testing.assert_allclose(output[2],[[0,0,1]]*3)
        for key in arrays:np.testing.assert_array_equal(arrays[key],before[key])
        self.assertEqual(meshes[0][1],'models/neural/new/body')
        with self.assertRaises(schema.Error):generated.clean_geometry(arrays,np.array([[0,0,1]]),'body')

    def test_generated_mesh_requires_same_concept_and_conversion_hashes(self):
        with tempfile.TemporaryDirectory() as root:
            actor=Path(root)
            for name in ('concept.png','model.glb','geometry.npz','body.png'):(actor/name).write_bytes(b'fixture')
            (actor/'trellis.json').write_text(json.dumps(dict(generator='microsoft/TRELLIS.2-4B',input_sha256='changed',glb_sha256='changed')))
            (actor/'geometry.json').write_text('{}')
            with self.assertRaises(schema.Error) as failure:generated.generated_geometry(actor,'models/neural/new/body')
            self.assertEqual(failure.exception.code,'ANIM_SOURCE_HASH_MISMATCH')
            (actor/'trellis.json').write_text(json.dumps(dict(generator='microsoft/TRELLIS.2-4B',input_sha256=schema.sha(actor/'concept.png'),glb_sha256=schema.sha(actor/'model.glb'))))
            with self.assertRaisesRegex(schema.Error,'another mesh'):generated.generated_geometry(actor,'models/neural/new/body')


if __name__=='__main__':unittest.main()
