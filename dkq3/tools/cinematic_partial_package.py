#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build a local, partial Hiro cinematic IQM overlay for native review.

Only declared authored clips replace legacy frame ranges. The native client
uses the original DKM/MD3 for every other cinematic sequence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
from zipfile import ZIP_DEFLATED, ZipInfo

import numpy as np

import animation_manifest as schema
import animation_motion as motion
from neural_package import classic_archive, validate_package
import skeletal_iqm as sk


SOURCE = 'models/cinematic/c_hiro_intr.dkm'
TARGET = 'models/neural/c_hiro_intr.iqm'
MATERIALS = {
    'models/neural/hiro-dojo-slim/body': 'models/neural/hiro-dojo-slim/body.png',
    'models/neural/hiro/head': 'models/neural/hiro/head.png',
}
CLIPS = (
    ('stance', (122, 142), 'ambba', True),
    ('look_left', (163, 172), 'lftlook', False),
)


def shader(name: str, image: str) -> str:
    result = []
    for suffix, bright, alpha in (('', False, False), ('@alpha', False, True),
                                  ('@bright', True, False), ('@alphabright', True, True)):
        lines = [name + suffix, '{', ' nomipmaps', ' cull none', ' {', '  map ' + image]
        if alpha:
            lines += ['  blendFunc blend', '  alphaFunc GT0', '  depthWrite']
        lines += ['  rgbGen ' + ('identityLighting' if bright else 'lightingDiffuse')]
        if alpha:
            lines += ['  alphaGen entity']
        lines += [' }', '}', '']
        result.extend(lines)
    return '\n'.join(result)


def build(rig_path: Path, stance_path: Path, look_path: Path, body_path: Path,
          head_path: Path, base_path: Path, output: Path) -> dict:
    report_path = output.with_suffix('.json')
    if output.exists() or output.is_symlink() or report_path.exists() or report_path.is_symlink():
        raise schema.Error('partial overlay output already exists', 'ANIM_INVALID_PATH', str(output))
    inputs = (rig_path, stance_path, look_path, body_path, head_path, base_path)
    if any(not path.is_file() for path in inputs):
        raise schema.Error('partial overlay input is missing', 'ANIM_INVALID_PATH')
    if any(path.stat().st_size > 64 * 1024 * 1024 for path in inputs[:-1]):
        raise schema.Error('partial overlay input exceeds 64 MiB', 'ANIM_INVALID_PATH')
    if output.resolve() in {path.resolve() for path in inputs}:
        raise schema.Error('partial overlay would overwrite source', 'ANIM_INVALID_PATH')
    model = sk.read(rig_path.read_bytes())
    if set(material for _, material, *_ in model.meshes) != set(MATERIALS):
        raise schema.Error('partial overlay rig uses unexpected materials', 'ANIM_INVALID_SOURCE')
    if len(model.frames) != 1:
        raise schema.Error('partial overlay needs one neutral bind frame', 'ANIM_INVALID_BIND')
    data = [motion.read(path) for path in (stance_path, look_path)]
    for (_, _, _, loop), sampled in zip(CLIPS, data):
        report = motion.validate(model, sampled, dict(loop=loop, root_motion='preserve'))
        if not report['passed']:
            raise schema.Error('authored clip failed skeletal validation: ' + str(report['failures'][0]))
        if sampled.metadata.get('kind') != 'authored_cinematic' or sampled.fps != 30:
            raise schema.Error('partial overlay requires independently authored 30 fps motion')
    frames = [model.bind[None]]
    clips = {}
    index = 1
    for (label, source_range, sequence, loop), sampled in zip(CLIPS, data):
        channels = motion.export_channels(sampled)
        frames.append(channels)
        clips[label] = dict(source_frames=list(source_range), target_frames=[index, index + len(channels) - 1],
                            sequence=sequence, authority_fps=10, fps=0, loop=loop,
                            root_motion='preserve')
        index += len(channels)
    model.frames = np.concatenate(frames)
    manifest = dict(version=1, characters=[dict(character='hiro', source_model=SOURCE,
        target_model=TARGET, iqm=str(rig_path.resolve()), skeleton='dk3_humanoid_dojo_neutral_v1',
        clips=clips)])
    table = schema.compile_manifest(manifest, {TARGET: len(model.frames)})
    model_bytes = sk.write(model)
    skin = {}
    suffixes = ('', '@alpha', '@bright', '@alphabright')
    for variant, suffix in enumerate(suffixes):
        skin[f'{TARGET}.{variant}.skin'] = ('\n'.join(
            f'{mesh},{material}{suffix}' for mesh, material, *_ in model.meshes) + '\n').encode()
    shaders = ''.join(shader(name, image) for name, image in MATERIALS.items()).encode()
    files = {
        'dk3/neural-models.cfg': f'{SOURCE} {TARGET}\n'.encode(),
        'dk3/neural-animations.cfg': table,
        TARGET: model_bytes,
        'models/neural/hiro-dojo-slim/body.png': body_path.read_bytes(),
        'models/neural/hiro/head.png': head_path.read_bytes(),
        'scripts/dk3-neural.shader': shaders,
        **skin,
    }
    report = dict(format=1, source_models_sha256=schema.sha(base_path),
        files={name: hashlib.sha256(payload).hexdigest() for name, payload in files.items()},
        models=[dict(source=SOURCE, target=TARGET)],
        provenance='generated slim gi body, previously approved Hiro face, independently authored stance/look',
        scope='partial cinematic diagnostic; other sequences require original DKM fallback',
        validation='structural and motion only; native and visual acceptance pending',
        inputs={str(path.resolve()): schema.sha(path) for path in inputs})
    files['dk3/neural-assets.json'] = (json.dumps(report, indent=2, sort_keys=True) + '\n').encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix='.' + output.stem + '.',
                                                  suffix='.partial', dir=output.parent)
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        with classic_archive(temporary) as archive:
            for name, payload in sorted(files.items()):
                entry = ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                entry.compress_type = ZIP_DEFLATED
                archive.writestr(entry, payload)
        validate_package(temporary, base_path)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    receipt = dict(passed=True, package=str(output), package_sha256=schema.sha(output),
                   frames=len(model.frames), clips=clips, source_animation_used=False,
                   native_preview='pending', visual_acceptance='unverified', inputs=report['inputs'])
    schema.write_json(output.with_suffix('.json'), receipt)
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('rig', 'stance', 'look', 'body', 'head', 'base_models', 'out'):
        parser.add_argument('--' + name.replace('_', '-'), type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(build(args.rig, args.stance, args.look, args.body,
                               args.head, args.base_models, args.out), indent=2))
    except (schema.Error, OSError, ValueError, KeyError) as error:
        parser.exit(1, f'cinematic partial package: {error}\n')


if __name__ == '__main__':
    main()
