# SPDX-License-Identifier: GPL-2.0-or-later
"""Repair exposed-head seams and missing normals without changing other IQM data."""
import hashlib
import json
from pathlib import Path

import numpy as np

import iqm
import skeletal_iqm as sk


def normal_range(data):
    header = dict(zip((name for name, _ in iqm.HEADER_FIELDS), iqm.HEADER.unpack_from(data)))
    for i in range(header['num_vertexarrays']):
        kind, flags, fmt, size, offset = iqm.VERTEX_ARRAY.unpack_from(
            data, header['ofs_vertexarrays'] + i * iqm.VERTEX_ARRAY.size)
        if kind == 2:
            if flags or fmt != 7 or size != 3:
                raise ValueError('Head lighting requires float3 normals')
            return offset, header['num_vertexes'] * 12
    raise ValueError('IQM has no normals')


def tangent_range(data):
    header = dict(zip((name for name, _ in iqm.HEADER_FIELDS), iqm.HEADER.unpack_from(data)))
    for i in range(header['num_vertexarrays']):
        kind, flags, fmt, size, offset = iqm.VERTEX_ARRAY.unpack_from(
            data, header['ofs_vertexarrays'] + i * iqm.VERTEX_ARRAY.size)
        if kind == 3 and not flags and fmt == 7 and size == 4:
            return offset, header['num_vertexes'] * 16
    return None


def head_normals(data):
    model = sk.read(data)
    head = [i for i, name in enumerate(model.names)
            if not name.startswith(('tag_', 'prop_')) and
            (name in ('head', 'neck') or name.endswith(('_head', '_neck')))]
    selected = np.sum(np.where(np.isin(model.arrays[4], head), model.arrays[5], 0), axis=1) > 127
    missing = np.linalg.norm(model.arrays[2],axis=1) < 1e-6
    head_vertices = int(selected.sum())
    selected |= missing
    points, triangles = model.arrays[0], model.triangles
    _, inverse = np.unique(np.round(points, 4), axis=0, return_inverse=True)
    # IQM winding is clockwise. Weld positions across UV/surface boundaries
    # for the lighting calculation, without welding any exported geometry.
    faces = np.cross(points[triangles[:, 2]] - points[triangles[:, 0]],
                     points[triangles[:, 1]] - points[triangles[:, 0]])
    normals = np.zeros((inverse.max() + 1, 3))
    for corner in range(3):
        np.add.at(normals, inverse[triangles[:, corner]], faces)
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
    corrected = normals[inverse].astype('<f4')
    # Opposite coincident faces can cancel. Missing normals still require a
    # usable direction; use the largest incident face instead of a zero vector.
    weak = missing & (np.linalg.norm(corrected,axis=1) < .5)
    if weak.any():
        areas=np.linalg.norm(faces,axis=1)
        strongest=np.zeros(len(points))
        for triangle,face,area in zip(triangles,faces,areas):
            for vertex in triangle:
                if weak[vertex] and area>strongest[vertex]:
                    strongest[vertex]=area
                    corrected[vertex]=face/max(float(area),1e-9)
        if np.any(np.linalg.norm(corrected[missing],axis=1)<.5):
            raise ValueError('Missing normal has no nondegenerate incident face')
    selected &= np.linalg.norm(corrected, axis=1) > .5
    original = model.arrays[2].copy()
    model.arrays[2][selected] = corrected[selected]
    offset, size = normal_range(data)
    output = bytearray(data)
    output[offset:offset + size] = model.arrays[2].astype('<f4').tobytes()
    ranges = [[offset, size]]
    tangent = tangent_range(data)
    if tangent:
        first, length = tangent
        vectors = np.frombuffer(data, '<f4', count=length // 4, offset=first).reshape(-1, 4).copy()
        old = vectors[selected, :3].astype(float)
        n = model.arrays[2][selected]
        old -= n * np.sum(n * old, axis=1, keepdims=True)
        weak = np.linalg.norm(old, axis=1) < 1e-8
        axes = np.eye(3)[np.argmin(np.abs(n[weak]), axis=1)]
        old[weak] = np.cross(n[weak], axes)
        vectors[selected, :3] = old / np.maximum(np.linalg.norm(old, axis=1, keepdims=True), 1e-9)
        output[first:first + length] = vectors.astype('<f4').tobytes()
        ranges.append([first, length])
    output = bytes(output)
    cursor = 0
    for first, length in sorted(ranges):
        assert data[cursor:first] == output[cursor:first]
        cursor = first + length
    assert data[cursor:] == output[cursor:]
    return output, dict(vertices=int(selected.sum()),head_vertices=head_vertices,missing_normals=int(missing.sum()),
        changed_vertices=int(np.any(original != model.arrays[2], axis=1).sum()),
        input_iqm_sha256=hashlib.sha256(data).hexdigest(),
        output_iqm_sha256=hashlib.sha256(output).hexdigest(),
        normal_byte_range=[offset, size],
        lighting_byte_ranges=ranges,
        method='Area-weighted head normals across coincident UV seams and missing-normal reconstruction from incident faces; only normals and orthogonal tangents change; preserve sculpt creases')


def repair_actor(actor):
    actor = Path(actor)
    source = (actor / 'model.iqm').read_bytes()
    output, report = head_normals(source)
    report['tool_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    report['input_file'] = 'model-before-surface-' + report['input_iqm_sha256'][:12] + '.iqm'
    (actor / report['input_file']).write_bytes(source)
    temporary = actor / 'model.surface.partial'
    temporary.write_bytes(output)
    temporary.replace(actor / 'model.iqm')
    (actor / 'surface-normals.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    conversion = json.loads((actor / 'conversion.json').read_text())
    conversion['surface_lighting'] = report
    (actor / 'conversion.json').write_text(json.dumps(conversion, indent=2, sort_keys=True) + '\n')
    return report
