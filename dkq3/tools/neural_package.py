# SPDX-License-Identifier: GPL-2.0-or-later
"""Validate local cosmetic packages without conversion dependencies."""
import hashlib
import json
import zipfile

MANIFEST = 'dk3/neural-models.cfg'


def validate_package(path, base):
    """Cosmetic overlay admission: closed namespace, per-entry hashes, exact base models."""
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or archive.testzip(): raise ValueError('corrupt neural archive')
        report = json.loads(archive.read('dk3/neural-assets.json'))
        if report.get('format') != 1 or report['source_models_sha256'] != hashlib.sha256(base.read_bytes()).hexdigest():
            raise ValueError('neural package targets another model generation; rebuild it')
        expected = set(report['files']) | {'dk3/neural-assets.json'}
        if set(names) != expected or MANIFEST not in expected:
            raise ValueError('neural package entry manifest mismatch')
        for name, sha in report['files'].items():
            valid = name in (MANIFEST, 'dk3/neural-animations.cfg') or (name.startswith('models/neural/') and name.endswith(('.iqm', '.skin', '.png'))) or name == 'scripts/dk3-neural.shader'
            if not valid or '..' in name.split('/') or hashlib.sha256(archive.read(name)).hexdigest() != sha:
                raise ValueError('invalid neural package entry: ' + name)
        return report
