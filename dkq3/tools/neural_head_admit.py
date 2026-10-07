#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Admit a visually reviewed reconstruction as a child of an exact body conversion."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil

import numpy as np
import skeletal_iqm as sk
from neural_surface_quality import animation_preservation
from neural_monsters import save


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def admit(root, slug, head, candidate):
    if slug in ('prisoner', 'prisonerb'):
        raise ValueError('Protected assets cannot receive head replacements')
    ledger = root / 'pipeline.json'
    document = json.loads(ledger.read_text())
    row = next(r for r in document['actors'] if r['slug'] == slug)
    actor = root / slug
    base = actor / 'head-baseline'
    convert = row['stages']['convert']
    if convert['state'] != 'complete':
        raise ValueError('A complete body conversion is required')
    old_head = row['stages'].get('head', {})
    for name, expected in convert['outputs'].items():
        product = actor / old_head.get('base_products', {}).get(name, name)
        if (base/name).exists() and digest(base/name)==expected:
            product=base/name
        if digest(product) != expected:
            raise ValueError('Body conversion changed: ' + name)
    review = json.loads((candidate / 'visual-review.json').read_text())
    inspected = review.get('inspected_views', {})
    required = ('front.png', 'quarter.png', 'side.png', 'other-side.png')
    if (review.get('state') != 'accepted'
            or any(not any(Path(path).name == name for path in inspected) for name in required)
            or not review.get('animated_join_review')):
        raise ValueError('Rendered front, quarter, both sides and animated join review is required')
    for origin in ('albedo-painted-review', 'lit-painted-review'):
        for name in required:
            if origin + '/' + name not in inspected:
                raise ValueError('Both albedo and lit review images must be identified: ' + origin + '/' + name)
    required_inputs={'model.iqm','body.png','head.png','head-model.iqm','head-reconstruction.json'}
    if not required_inputs.issubset(review.get('inputs', {})):
        raise ValueError('Visual review must identify the complete rendered candidate')
    for name, expected in review['inputs'].items():
        if digest(candidate / name) != expected:
            raise ValueError('Candidate changed after visual review: ' + name)
    for name, expected in review['inspected_views'].items():
        if digest(candidate / name) != expected:
            raise ValueError('Reviewed image changed: ' + name)
    original_path = base / 'model.iqm' if (base / 'model.iqm').exists() else actor / 'model.iqm'
    old = sk.read(original_path.read_bytes())
    replacement = sk.read((candidate / 'model.iqm').read_bytes())
    preservation = animation_preservation(old, replacement)
    if not np.array_equal(old.bind, replacement.bind) or not np.array_equal(old.frames, replacement.frames):
        raise ValueError('Head replacement must retain exact serialized rig and frame channels')
    reconstruction = json.loads((candidate / 'head-reconstruction.json').read_text())
    for product,field in (('model.iqm','output_iqm_sha256'),('head.png','head_texture_sha256'),('body.png','retained_body_atlas_sha256')):
        if digest(candidate/product)!=reconstruction[field]:
            raise ValueError('Candidate lineage does not describe its current '+product)
    if reconstruction['body_iqm_sha256'] != convert['outputs']['model.iqm']:
        raise ValueError('Head belongs to another body conversion')
    source_products = ['concept.png','prompt.txt','model.glb','trellis.json','head-export.json',
                       'head-geometry.npz','head-geometry.json','head.png']
    source_products += [p.name for p in head.glob('closure-*') if p.is_file()]
    source_products += [p.name for p in head.glob('construction-*') if p.is_file()]
    source_products += [p.name for p in head.glob('alpha-prompt.txt') if p.is_file()]
    for product,field in (('concept.png','head_concept_sha256'),('model.glb','head_glb_sha256'),('head-geometry.npz','head_geometry_sha256')):
        if digest(head/product)!=reconstruction[field]:
            raise ValueError('Reconstruction input changed: '+product)
    painted_products=[p.name for p in candidate.glob('head.face*') if p.is_file()]
    painted_products += [p.name for p in candidate.glob('body-painted.face*') if p.is_file()]
    if (candidate/'body-painted.face.json').is_file():painted_products.append('body-model.iqm')
    if (candidate/'head.face.json').is_file():
        painting_receipt=json.loads((candidate/'head.face.json').read_text())
        if painting_receipt['mesh_sha256']!=digest(candidate/'head-model.iqm'):
            raise ValueError('Head painting belongs to a different mesh')
        if painting_receipt['original_texture_sha256']!=digest(head/'head.png'):
            raise ValueError('Head painting belongs to a different original atlas')
        if not set(painted_products).issubset(review['inputs']):
            raise ValueError('Visual review must identify the head painting receipt and coverage')
    if (candidate/'body-painted.face.json').is_file():
        body_painting=json.loads((candidate/'body-painted.face.json').read_text())
        if body_painting['mesh_sha256']!=digest(candidate/'body-model.iqm'):
            raise ValueError('Body collar painting belongs to a different mesh')
        body_basis = actor/'body-before-face.png' if reconstruction['config'].get('body_texture') == 'before-face' else (base/'body.png' if (base/'body.png').exists() else actor/'body.png')
        if body_painting['original_texture_sha256'] != digest(body_basis):
            raise ValueError('Body collar painting belongs to another original atlas')
        if not set(painted_products).issubset(review['inputs']):
            raise ValueError('Visual review must identify the collar painting receipt and coverage')
    for product in ('head.face.json','body-painted.face.json'):
        if not (candidate/product).is_file():
            continue
        receipt=json.loads((candidate/product).read_text())
        occluder=receipt.get('complete_model_occlusion')
        if occluder and (occluder['path']!='model.iqm' or occluder['sha256']!=digest(candidate/'model.iqm')):
            raise ValueError('Painting occlusion does not describe the reviewed complete model')
        for projection in receipt['projections']:
            if digest(candidate/projection['path']) != projection['sha256']:
                raise ValueError('Material projection changed after painting')
    for name in source_products:
        if not (head/name).is_file():
            raise ValueError('Missing head lineage: '+name)
    changed = ['model.iqm', 'body.png']
    if (candidate / 'body.face-mask.png').exists():
        changed.append('body.face-mask.png')
    base.mkdir(exist_ok=True)
    base_products = dict(old_head.get('base_products', {}))
    for name in changed:
        if not (base / name).exists():
            shutil.copy2(actor / name, base / name)
        if digest(base / name) != convert['outputs'][name]:
            raise ValueError('Frozen conversion mismatch: ' + name)
        base_products[name] = 'head-baseline/' + name
    source = actor / 'head-source'
    source.mkdir(exist_ok=True)
    inputs = {}
    for name in source_products:
        if not (head / name).exists():
            raise ValueError('Missing head lineage: ' + name)
        shutil.copy2(head / name, source / name)
        inputs['head-source/' + name] = digest(source / name)
    for name in changed + ['head.png','head-model.iqm','head-reconstruction.json','visual-review.json'] + painted_products:
        shutil.copy2(candidate / name, actor / name)
    # The gallery must display the exact reviewed mesh, never an older face
    # render that happens to remain in the actor directory.
    rendered_products=[]
    for origin,destination in (('albedo-painted-review','face-review'),('lit-painted-review','face-lit-review')):
        target=actor/destination;target.mkdir(exist_ok=True)
        outputs={}
        for name in required:
            relative=origin+'/'+name
            shutil.copy2(candidate/relative,target/name)
            outputs[name]=digest(target/name)
            rendered_products.append(destination+'/'+name)
        save(target/'receipt.json',dict(inputs={n:digest(actor/n) for n in ('model.iqm','body.png','head.png')},
             outputs=outputs,source_visual_review_sha256=digest(actor/'visual-review.json'),
             scope='Actual serialized candidate; fixed front, quarter and both side views'))
        rendered_products.append(destination+'/receipt.json')
    # Preserve material-generation guides and every admitted prompt in the same
    # project artifact; only reconstruction data/atlases enter the runtime package.
    painting = actor / 'head-painting'
    painting.mkdir(exist_ok=True)
    for path in candidate.glob('texture-*'):
        if path.is_file():
            shutil.copy2(path, painting / path.name)
            inputs['head-painting/' + path.name] = digest(painting / path.name)
    for name in ('head-texture-plan.json', 'body-texture-plan.json'):
        if (candidate / name).is_file():
            shutil.copy2(candidate / name, painting / name)
            inputs['head-painting/' + name] = digest(painting / name)
    metadata = copy.deepcopy(json.loads((actor / 'conversion.json').read_text()))
    historical = {name:metadata.pop(name) for name in ('face_refinement','surface_lighting','surface_closure','topology') if name in metadata}
    metadata.update(triangles=len(replacement.triangles),vertices=len(replacement.arrays[0]),
                    head_reconstruction=reconstruction,animation_preservation=preservation,
                    prior_surface_reports=historical)
    save(actor / 'conversion-head.json', metadata)
    outputs = {name:digest(actor / name) for name in changed + ['head.png','head-model.iqm',
               'head-reconstruction.json','visual-review.json','conversion-head.json'] + painted_products + rendered_products}
    row['stages']['head'] = dict(state='complete',method='Dedicated head reconstruction with geometry-conditioned materials',
        base_products=base_products,inputs=inputs,outputs=outputs,
        tool_sha256=digest(Path(__file__)),native_acceptance='unverified')
    save(ledger,document)
    return row['stages']['head']


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--actor',required=True)
    parser.add_argument('--head',type=Path,required=True)
    parser.add_argument('--candidate',type=Path,required=True)
    args=parser.parse_args()
    print(json.dumps(admit(args.out,args.actor,args.head,args.candidate),indent=2))
