# SPDX-License-Identifier: GPL-2.0-or-later
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from neural_package import MANIFEST, prune_props, validate_package, classic_archive, require_classic_directory


class PackageTest(unittest.TestCase):
    def test_sparse_archive_above_two_gib_retains_native_offsets_and_payload(self):
        # Sparse prefix crosses Python's conservative boundary without a
        # multi-gigabyte test payload or a change to the reviewed contents.
        previous=zipfile.ZIP64_LIMIT
        payload=b'shader and model bytes remain exact'
        with tempfile.TemporaryDirectory() as temporary:
            for compatible in (False,True):
                path=Path(temporary)/('classic.pk3' if compatible else 'zip64.pk3')
                with path.open('w+b') as stream:
                    stream.seek((1<<31)+64)
                    writer=classic_archive(stream) if compatible else zipfile.ZipFile(stream,'w')
                    with writer as archive:archive.writestr('scripts/probe.shader',payload)
                with zipfile.ZipFile(path) as archive:
                    self.assertEqual(archive.read('scripts/probe.shader'),payload)
                    if compatible:
                        require_classic_directory(path,archive)
                        self.assertGreater(archive.getinfo('scripts/probe.shader').header_offset,1<<31)
                    else:
                        with self.assertRaisesRegex(ValueError,'ZIP32'):require_classic_directory(path,archive)
        self.assertEqual(zipfile.ZIP64_LIMIT,previous)

    def test_forced_zip64_local_header_is_rejected_even_with_classic_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'forced.pk3'
            with zipfile.ZipFile(path,'w') as archive:
                with archive.open('scripts/probe.shader','w',force_zip64=True) as stream:stream.write(b'unchanged')
            with zipfile.ZipFile(path) as archive:
                self.assertEqual(archive.read('scripts/probe.shader'),b'unchanged')
                with self.assertRaisesRegex(ValueError,'ZIP32'):require_classic_directory(path,archive)

    def test_prop_repair_retains_other_performances_and_package_integrity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            base = root / 'base.pk3'
            base.write_bytes(b'original converted models remain unchanged')
            source, output = root / 'bad.pk3', root / 'fixed.pk3'
            files = {
                MANIFEST: b'models/e1/d1_supertorture.dkm models/neural/rack.iqm\nmodels/cinematic/c_super_e1m3.dkm models/neural/super.iqm\n',
                'models/neural/rack.iqm': b'incorrect generated body',
                'models/neural/rack.iqm.0.skin': b'incorrect skin',
                'models/neural/super.iqm': b'unchanged authored performance',
                'models/neural/super.iqm.0.skin': b'unchanged skin',
            }
            report = dict(format=1, source_models_sha256=hashlib.sha256(base.read_bytes()).hexdigest(),
                          files={name: hashlib.sha256(data).hexdigest() for name, data in files.items()},
                          models=[dict(source='models/e1/d1_supertorture.dkm'), dict(source='models/cinematic/c_super_e1m3.dkm')])
            with zipfile.ZipFile(source, 'w') as archive:
                for name, data in files.items(): archive.writestr(name, data)
                archive.writestr('dk3/neural-assets.json', json.dumps(report))
            original_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            with self.assertRaisesRegex(ValueError, 'non-character prop'):
                validate_package(source, base)
            self.assertEqual(['models/neural/rack.iqm'], prune_props(source, output, base))
            self.assertEqual(original_hash, hashlib.sha256(source.read_bytes()).hexdigest())
            fixed = validate_package(output, base)
            self.assertEqual([dict(source='models/cinematic/c_super_e1m3.dkm')], fixed['models'])
            with zipfile.ZipFile(output) as archive:
                self.assertNotIn('models/neural/rack.iqm', archive.namelist())
                self.assertNotIn('models/neural/rack.iqm.0.skin', archive.namelist())
                self.assertEqual(files['models/neural/super.iqm'], archive.read('models/neural/super.iqm'))
                self.assertEqual(files['models/neural/super.iqm.0.skin'], archive.read('models/neural/super.iqm.0.skin'))
