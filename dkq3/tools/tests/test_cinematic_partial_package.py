# SPDX-License-Identifier: GPL-2.0-or-later
"""The authored two-clip package must remain reproducible and legacy-scoped."""
from __future__ import annotations

from io import BytesIO
from pathlib import Path
import tempfile
import unittest
import zipfile

import numpy as np
from PIL import Image

import animation_motion as motion
import cinematic_motion_author as author
import cinematic_partial_package as package
import skeletal_iqm as sk
from tests.test_animation_author import model


class PartialPackageTests(unittest.TestCase):
    def test_exact_two_clip_archive_and_repeated_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rig = model()
            original = rig.meshes[0]
            rig.meshes[0] = (original[0], next(iter(package.MATERIALS)), *original[2:])
            for kind in (0, 1, 2, 4, 5):
                rig.arrays[kind] = np.concatenate((rig.arrays[kind], rig.arrays[kind]))
            rig.triangles = np.concatenate((rig.triangles, rig.triangles + 3))
            rig.meshes.append(('face', 'models/neural/hiro/head', 3, 3, 1, 1))
            rig_path = root / 'rig.iqm'
            rig_path.write_bytes(sk.write(rig))
            keys = dict(version=1, fps=30, frames=9, loop=True,
                        provenance='independent test motion',
                        keys=[dict(frame=0), dict(frame=8)])
            stance = root / 'stance.npz'
            motion.write(stance, author.author(keys, rig))
            keys['loop'] = False
            look = root / 'look.npz'
            motion.write(look, author.author(keys, rig))
            png = BytesIO()
            Image.new('RGB', (2, 2), 'white').save(png, format='PNG')
            body, head = root / 'body.png', root / 'head.png'
            body.write_bytes(png.getvalue())
            head.write_bytes(png.getvalue())
            base = root / 'base.pk3'
            base.write_bytes(b'local base identity')
            outputs = [root / 'first.pk3', root / 'second.pk3']
            receipts = [package.build(rig_path, stance, look, body, head, base, path)
                        for path in outputs]
            self.assertEqual(receipts[0]['package_sha256'], receipts[1]['package_sha256'])
            with zipfile.ZipFile(outputs[0]) as archive:
                self.assertEqual(archive.read('dk3/neural-models.cfg'),
                                 b'models/cinematic/c_hiro_intr.dkm models/neural/c_hiro_intr.iqm\n')
                self.assertEqual(archive.read('dk3/neural-animations.cfg'),
                                 b'models/cinematic/c_hiro_intr.dkm 122 142 1 9 0 0 0\n'
                                 b'models/cinematic/c_hiro_intr.dkm 163 172 10 18 0 0 0\n')
                self.assertEqual(len(sk.read(archive.read(package.TARGET)).frames), 19)
            self.assertEqual(rig_path.read_bytes(), sk.write(rig))
            with self.assertRaisesRegex(ValueError, 'already exists'):
                package.build(rig_path, stance, look, body, head, base, outputs[0])


if __name__ == '__main__':
    unittest.main()
