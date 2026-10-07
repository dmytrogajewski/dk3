# SPDX-License-Identifier: GPL-2.0-or-later
"""The authored-performance path must be independent of captured source poses."""
from __future__ import annotations

import copy
from pathlib import Path
import tempfile
import unittest

import numpy as np
import yaml

import animation_manifest as schema
import animation_motion as motion
import cinematic_motion_author as author
import cinematic_motion_trial as trial
import skeletal_iqm as sk
from tests.test_animation_author import document, model


def spec() -> dict:
    start=dict(frame=0,root=[0,0,0],hand_l=[2,-1,3],hand_r=[4,2,5],
               elbow_l=[0,0,1],elbow_r=[0,1,1],head=[0,0,0])
    end=dict(start,frame=8)
    return dict(version=1,fps=30,frames=9,loop=True,provenance="locally authored fixture",
                keys=[start,dict(frame=4,head=[0,0,5],hand_r=[5,2,5]),end])


class CinematicMotionAuthorTests(unittest.TestCase):
    def test_independent_pose_has_fixed_lengths_and_closes_loop(self):
        rig=model();result=author.author(spec(),rig)
        self.assertEqual(result.metadata["kind"],"authored_cinematic")
        self.assertEqual(len(result.world),9)
        self.assertTrue(np.allclose(result.world[0],result.world[-1],atol=1e-8))
        bind=sk.matrices(rig.bind,rig.parents)
        for child,parent in enumerate(rig.parents):
            if parent<0 or rig.names[child].startswith(("tag_","cloth_")):
                continue
            expected=np.linalg.norm(bind[child,:3,3]-bind[parent,:3,3])
            length=np.linalg.norm(result.world[:,child,:3,3]-result.world[:,parent,:3,3],axis=1)
            self.assertTrue(np.allclose(length,expected,atol=1e-4),rig.names[child])
        hand=rig.names.index("hand_r")
        self.assertGreater(result.world[0,hand,2,3],bind[hand,2,3]+1)

    def test_malformed_keys_fail_before_output(self):
        rig=model()
        for change in (
            lambda d:d["keys"][1].update(frame=0),
            lambda d:d["keys"][1].update(hand_r=[100,0,0]),
            lambda d:d["keys"][1].update(head=[float("nan"),0,0]),
            lambda d:d["keys"][2].update(head=[0,0,2]),
            lambda d:d["keys"][1].update(unknown=[0,0,0]),
        ):
            with self.subTest(change=change):
                item=copy.deepcopy(spec());change(item)
                with self.assertRaises(schema.Error):author.author(item,rig)

    def test_authored_corrective_follows_parent_without_source_capture(self):
        rig=model();motion.attach(rig,"deform_head","head",[0,0,0])
        authored=author.author(spec(),rig)
        mapping={"deform_head":"head"}
        self.assertIs(motion.apply_correctives(rig,authored,mapping),authored)
        report=motion.validate(rig,authored,dict(correctives=mapping,max_joint_step=65))
        self.assertTrue(report["passed"],report["failures"])
        with self.assertRaises(schema.Error):
            motion.apply_correctives(rig,authored,{"deform_head":"neck"})

    def test_trial_changes_only_selected_clip_and_keeps_source_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);rig=model();(root/"hiro.iqm").write_bytes(sk.write(rig))
            keys=spec();keys["frames"]=24;keys["keys"][-1]["frame"]=23
            authored=author.author(keys,rig);motion.write(root/"authored.npz",authored)
            source=document();clip=source["characters"][0]["clips"]["walk"]
            clip["props"]={"prop_30":{"mode":"captured"}}
            base=root/"source.yaml";base.write_text(yaml.safe_dump(source,sort_keys=False))
            before=base.read_bytes()
            out=root/"trial.yaml"
            receipt=trial.prepare(base,["hiro.walk="+str(root/"authored.npz")],out)
            changed=yaml.safe_load(out.read_text())["characters"][0]["clips"]["walk"]
            self.assertEqual(before,base.read_bytes())
            self.assertEqual(changed["props"]["prop_30"]["mode"],"inherit")
            self.assertEqual(receipt["clips"]["hiro.walk"]["frames"],24)
            with self.assertRaises(schema.Error):
                trial.prepare(base,["hiro.walk="+str(root/"authored.npz")],out)


if __name__=="__main__":unittest.main()
