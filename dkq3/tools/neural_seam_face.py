#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Admit a fresh image-tool face when bounded seam re-registration was rejected."""
import argparse
import json
from pathlib import Path
import shutil
from types import SimpleNamespace

from PIL import Image
import skeletal_iqm as sk
from neural_monsters import digest, save, run_stage
from neural_monster_face import geometry_digest, coordinates


def admit(actor, image, prompt, blender, python):
    ledger = json.loads((actor.parent/'pipeline.json').read_text())
    row = next(r for r in ledger['actors'] if r['slug'] == actor.name)
    stage = row['stages']['convert']
    if actor.name in ('prisoner', 'prisonerb') or stage.get('state') != 'failed' or not stage.get('error', '').startswith('Seam repair changed the registered face'):
        raise ValueError('Fresh seam face intake requires the recorded registration rejection')
    conversion = json.loads((actor/'conversion.json').read_text())
    if conversion['topology']['source_glb_sha256'] != digest(actor/'model.glb'):
        raise ValueError('Different inferred GLB')
    model = sk.read((actor/'model.iqm').read_bytes())
    sk.validate(model)
    image_data = Image.open(image)
    image_data.verify()
    image_data = Image.open(image)
    if image_data.width != image_data.height or image_data.width < 768:
        raise ValueError('Registered face projection must be square and at least 768 pixels')
    reference = actor/'face-seam-source'
    receipt = json.loads((reference/'receipt.json').read_text())
    if receipt['inputs']['model.iqm'] != digest(actor/'model.iqm') or receipt['inputs']['geometry'] != geometry_digest(actor):
        raise ValueError('New face render belongs to a different repaired mesh')
    if receipt['outputs']['front.png'] != digest(reference/'front.png'):
        raise ValueError('New face render changed')
    plan = json.loads((actor/'face-plan.json').read_text())
    for name in ('face-plan.json', 'face-projection.png', 'face-prompt.txt'):
        source = actor/name
        shutil.copy2(source, actor/(source.stem+'-before-seams-'+digest(source)[:12]+source.suffix))
    shutil.copy2(image, actor/'face-projection.png')
    shutil.copy2(prompt, actor/'face-prompt.txt')
    origin, scale = coordinates(actor)
    plan.update(mesh_sha256=digest(actor/'model.iqm'), geometry_sha256=geometry_digest(actor),
        projection_sha256=digest(actor/'face-projection.png'), prompt_sha256=digest(actor/'face-prompt.txt'),
        origin=origin, scale=scale, reference_front_path='face-seam-source/front.png',
        reference_front_sha256=digest(reference/'front.png'),
        method='Fresh built-in image edit of the repaired mesh orthographic face; bounded atlas bake')
    save(actor/'face-plan.json', plan)
    run_stage(SimpleNamespace(out=actor.parent, command='convert', models=[actor.name],
        blender=blender, python=python, triangles=36000, repair_uv_seams=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor', type=Path, required=True)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--prompt', type=Path, required=True)
    parser.add_argument('--blender', default='blender')
    parser.add_argument('--python', type=Path, default=Path('zig-out/neural-tools/runtime/bin/python'))
    args = parser.parse_args()
    # Resolving a venv interpreter symlink selects its bare base interpreter.
    admit(args.actor.resolve(), args.image.resolve(), args.prompt.resolve(), args.blender, args.python.absolute())
