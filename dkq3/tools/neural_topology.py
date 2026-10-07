# SPDX-License-Identifier: GPL-2.0-or-later
"""Qualify reuse of a registered face after welding the same inferred GLB."""
import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np
from scipy.spatial import cKDTree

import skeletal_iqm as sk


def face_deviation(before, after, bounds):
    """Compare both sampled face surfaces in the same normalized camera space."""
    low, high, width, depth = bounds
    def region(points):
        return points[(points[:, 2] >= low) & (points[:, 2] <= high) &
                      (np.abs(points[:, 1]) <= width) & (points[:, 0] >= depth)]
    a, b = region(before), region(after)
    if min(len(a), len(b)) < 8:
        raise ValueError('Seam repair has no comparable registered face')
    distances = np.concatenate((cKDTree(a).query(b)[0], cKDTree(b).query(a)[0]))
    result = dict(samples=len(distances), p95=float(np.quantile(distances, .95)),
                  maximum=float(distances.max()), unit='normalized source camera units')
    # This is a bounded re-registration of a known GLB, never permission to
    # reuse a projection on an unrelated inferred body or changed pose.
    if result['p95'] > .6 or result['maximum'] > 1.5:
        raise ValueError('Seam repair changed the registered face; generate a new projection: '+str(result))
    return result


def reregister(actor, previous_data, previous_conversion, previous_inputs, blender, env):
    from neural_monsters import digest, save
    from neural_monster_face import geometry_digest, coordinates
    actor = Path(actor)
    plan = json.loads((actor/'face-plan.json').read_text())
    original_plan = json.dumps(plan, indent=2, sort_keys=True)+'\n'
    old = sk.read(previous_data)
    new = sk.read((actor/'model.iqm').read_bytes())
    conversion = json.loads((actor/'conversion.json').read_text())
    topology = conversion.get('topology', {})
    source = digest(actor/'model.glb')
    if source != previous_inputs.get('model.glb') or source != topology.get('source_glb_sha256') or topology.get('weld_distance') != .0001:
        raise ValueError('Face re-registration requires a seam-only conversion of the same GLB')
    # Locate the exact pre-lighting mesh that the image tool originally saw.
    registered = actor/('model-before-surface-'+plan['mesh_sha256'][:12]+'.iqm')
    if hashlib.sha256(previous_data).hexdigest() == plan['mesh_sha256']:
        registered_data = previous_data
    elif registered.is_file() and digest(registered) == plan['mesh_sha256']:
        registered_data = registered.read_bytes()
    else:
        # Animation/weight repairs may have retained the exact registered
        # geometry while changing the complete IQM hash before lighting.
        registered_data = None
        for candidate in actor.glob('model-before-surface-*.iqm'):
            content = candidate.read_bytes()
            model = sk.read(content)
            checksum = hashlib.sha256()
            for array in (model.arrays[0], model.arrays[1], model.arrays[2], model.triangles):
                checksum.update(array.tobytes())
            if checksum.hexdigest() == plan.get('geometry_sha256'):
                registered_data = content
                break
        if registered_data is None:
            raise ValueError('Original registered geometry is unavailable')
    reference = sk.read(registered_data)
    if any(not np.array_equal(reference.arrays[k], old.arrays[k]) for k in (0, 1)) or not np.array_equal(reference.triangles, old.triangles):
        raise ValueError('Current master changed the original registered face geometry')
    for key, name in (('projection_sha256', 'face-projection.png'), ('concept_sha256', 'concept.png'),
                      ('prompt_sha256', 'face-prompt.txt')):
        if key in plan and digest(actor/name) != plan[key]:
            raise ValueError('Reviewed projection input changed: '+name)
    old_origin, old_scale = np.asarray(plan['origin']), plan['scale']
    new_origin, new_scale = coordinates(actor)
    difference = face_deviation((old.arrays[0]-old_origin)/old_scale,
                                (new.arrays[0]-new_origin)/new_scale, plan['bounds'])
    previous_sha = hashlib.sha256(previous_data).hexdigest()
    (actor/('model-before-seams-'+previous_sha[:12]+'.iqm')).write_bytes(previous_data)
    (actor/('conversion-before-seams-'+previous_sha[:12]+'.json')).write_text(json.dumps(previous_conversion, indent=2, sort_keys=True)+'\n')
    history = 'face-plan-before-seams-'+hashlib.sha256(original_plan.encode()).hexdigest()[:12]+'.json'
    (actor/history).write_text(original_plan)
    destination = actor/'face-seam-source'
    destination.mkdir(exist_ok=True)
    camera = dict(origin=new_origin, scale=new_scale, camera=plan['camera'])
    save(destination/'camera.json', camera)
    tool = Path(__file__).with_name('neural_face_preview.py')
    with (destination/'render.log').open('w') as log:
        subprocess.run([blender, '-b', '--threads', '4', '--python-exit-code', '1', '--python', str(tool), '--',
            '--mesh', str(actor/'model.iqm'), '--texture', str(actor/'body.png'), '--plan', str(destination/'camera.json'),
            '--out', str(destination)], env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    plan.update(mesh_sha256=digest(actor/'model.iqm'), geometry_sha256=geometry_digest(actor),
                origin=new_origin, scale=new_scale, reference_front_path='face-seam-source/front.png',
                reference_front_sha256=digest(destination/'front.png'))
    lineage = dict(source_glb_sha256=source, previous_master_sha256=previous_sha,
        current_master_sha256=plan['mesh_sha256'], previous_registration=history,
        previous_registration_sha256=digest(actor/history), face_deviation=difference,
        tool_sha256=digest(Path(__file__)),
        scope='Re-register unchanged image-tool projection after welding coincident UV seams and re-decimating the same GLB; review the baked face from four angles')
    plan['seam_repair'] = lineage
    save(actor/'face-plan.json', plan)
    save(actor/'face-seam-registration.json', lineage)
    save(destination/'receipt.json', dict(inputs={n:digest(actor/n) for n in ('model.iqm', 'body.png')},
        renderer_sha256=digest(tool), outputs={p.name:digest(p) for p in destination.glob('*.png')}))
    return lineage
