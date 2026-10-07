# SPDX-License-Identifier: GPL-2.0-or-later
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image

import cinematic_pair_review as review
import cinematic_surface_audit as surface
import cinematic_pose_stage as stage
import skeletal_iqm as sk


class NativePairTests(unittest.TestCase):
    def record(self, root: Path, presentation: str, times: list[int], scene: str = "dojo_dialogue") -> None:
        root.mkdir()
        data=dict(passed=True,presentation=presentation,identity="runtime-hash",scene=scene,map="intr_dialogue",
                  shots=[0],excluded_packages=[],overlays={},performances=[])
        (root/"recording.json").write_text(json.dumps(data),encoding="utf-8")
        for time in times:
            Image.new("RGB",(16,12),(time%255,0,0)).save(root/f"shot-000-{time:08}.jpg")

    def test_pairs_native_times_and_keeps_visual_decision_open(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);self.record(root/"old","legacy",[1000,1500]);self.record(root/"new","skeletal",[1050,1550])
            report=review.build(root/"old",root/"new",root/"out")
            self.assertEqual(report["frame_count"],2)
            self.assertEqual(report["decision"],"requires_visual_review")
            self.assertEqual([row["difference_ms"] for row in report["frames"]],[50,50])
            self.assertIn("original / skeletal",(root/"out/index.html").read_text(encoding="utf-8"))
            with self.assertRaises(review.ReviewError):review.build(root/"old",root/"new",root/"out")

    def test_rejects_mismatched_scene_and_unpaired_time(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);self.record(root/"old","legacy",[1000]);self.record(root/"new","skeletal",[1600],"different")
            with self.assertRaisesRegex(review.ReviewError,"scene differs"):
                review.build(root/"old",root/"new",root/"out")
            data=json.loads((root/"new/recording.json").read_text());data["scene"]="dojo_dialogue"
            (root/"new/recording.json").write_text(json.dumps(data))
            with self.assertRaisesRegex(review.ReviewError,"no candidate capture"):
                review.build(root/"old",root/"new",root/"out")

    def test_fallback_recording_requires_original_render_diagnostics(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);self.record(root/"old","fallback",[1000]);self.record(root/"new","skeletal",[1000])
            source=root/"old/recording.json";data=json.loads(source.read_text());data["performances"]=[dict(presentation="dk3 presentation: entity=65 frame=7")]
            source.write_text(json.dumps(data))
            self.assertEqual(review.build(root/"old",root/"new",root/"out")["original_presentation"],"fallback")
            data["performances"]=[dict(presentation="dk3 skeletal presentation: entity=65 frame=7")]
            source.write_text(json.dumps(data))
            with self.assertRaisesRegex(review.ReviewError,"did not prove original"):
                review.recording(root/"old","legacy")

    def test_surface_links_use_same_visible_entity(self):
        row=dict(shot=8,now=51000,presentation=(
            "dk3 skeletal presentation: entity=65 now=51121 frame=1579 oldframe=1578 model=models/cinematic/c_hiro_intr.dkm\n"
            "dk3 presentation: now=51121 camera=1 entity=65 frame=686 oldframe=685"))
        links=surface.frame_links(dict(performances=[row]),"models/cinematic/c_hiro_intr.dkm")
        self.assertEqual(links,[dict(shot=8,now=51000,source_frame=686,candidate_frame=1579,entity=65)])
        row["presentation"]=row["presentation"].replace("entity=65 frame=686","entity=66 frame=686")
        self.assertEqual(surface.frame_links(dict(performances=[row]),"models/cinematic/c_hiro_intr.dkm"),[])

    def test_surface_envelope_detects_horizontal_shape_change(self):
        old=np.array([[x,y,z] for z in (1.,2.,3.) for x in (-1.,0.,1.) for y in (-1.,0.,1.)])
        moved=old+[2.,0.,0.]
        band=surface.compare(old,moved)[0]
        self.assertAlmostEqual(band["center_error"],2.)
        self.assertAlmostEqual(band["width_ratio"]["x"],1.)

    def test_pose_stage_body_excludes_prop_faces(self):
        points=np.zeros((123,3));points[:,0]=np.arange(123)
        triangles=np.vstack((np.arange(120).reshape(40,3),[120,121,122]))
        bind=np.array([[0.,0,0,0,0,0,1,1,1,1]])
        model=sk.Model({0:points,1:np.zeros((123,2)),2:np.tile([0.,0,1.],(123,1)),
                        4:np.zeros((123,4),dtype=np.uint8),5:np.tile([255,0,0,0],(123,1))},
                       [('body','body',0,120,0,40),('prop_staff','staff',120,3,40,1)],triangles,
                       ['pelvis'],[-1],bind,bind[None])
        vertices,faces=stage.body_mesh(model,0)
        self.assertEqual(vertices.shape,(120,3))
        self.assertEqual(faces.shape,(40,3))
        self.assertLess(faces.max(),120)


if __name__=="__main__":unittest.main()
