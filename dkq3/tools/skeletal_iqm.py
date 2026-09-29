# SPDX-License-Identifier: GPL-2.0-or-later
"""Skeletal IQM v2 asset IO, using the bundled renderercommon/iqm.h layout.

Local asset tooling only. Transforms are parent-relative translation, quaternion
(xyzw), scale; all sampling and skinning happens in the existing IQM renderer.
"""
from dataclasses import dataclass
import struct

import numpy as np

import iqm

JOINT = struct.Struct('<Ii10f')
POSE = struct.Struct('<iI20f')
ANIM = struct.Struct('<3IfI')


@dataclass
class Model:
    arrays: dict
    meshes: list
    triangles: np.ndarray
    names: list
    parents: list
    bind: np.ndarray
    frames: np.ndarray


def read(data):
    header = dict(zip((k for k, _ in iqm.HEADER_FIELDS), iqm.HEADER.unpack_from(data)))
    if header['magic'] != iqm.MAGIC or header['version'] != 2 or header['filesize'] != len(data):
        raise ValueError('invalid skeletal IQM header')

    def records(layout, count, offset):
        return [layout.unpack_from(data, offset + i * layout.size) for i in range(count)]

    def string(offset):
        start = header['ofs_text'] + offset
        return data[start:data.index(b'\0', start)].decode('ascii')

    meshes = [(string(a), string(b), *rest) for a, b, *rest in records(iqm.MESH, header['num_meshes'], header['ofs_meshes'])]
    arrays = {}
    for kind, flags, fmt, size, offset in records(iqm.VERTEX_ARRAY, header['num_vertexarrays'], header['ofs_vertexarrays']):
        if kind not in (0, 1, 2, 4, 5):
            continue
        if flags or fmt != (1 if kind in (4, 5) else 7):
            raise ValueError('unsupported skeletal vertex array')
        arrays[kind] = np.frombuffer(data, dtype='u1' if fmt == 1 else '<f4',
                                    count=header['num_vertexes'] * size, offset=offset).reshape(-1, size).copy()
    triangles = np.frombuffer(data, '<u4', count=header['num_triangles'] * 3, offset=header['ofs_triangles']).reshape(-1, 3).copy()
    joints = records(JOINT, header['num_joints'], header['ofs_joints'])
    poses = records(POSE, header['num_poses'], header['ofs_poses'])
    if not joints or len(joints) != len(poses) or len(joints) > 128:
        raise ValueError('skeletal IQM must have matching joints and poses')
    channels = np.frombuffer(data, '<u2', count=header['num_frames'] * header['num_framechannels'], offset=header['ofs_frames']).reshape(header['num_frames'], -1)
    frames = np.empty((header['num_frames'], len(joints), 10))
    cursor = 0
    for j, pose in enumerate(poses):
        frames[:, j] = pose[2:12]
        for channel in range(10):
            if pose[1] & (1 << channel):
                frames[:, j, channel] += channels[:, cursor] * pose[12 + channel]
                cursor += 1
    if cursor != header['num_framechannels']:
        raise ValueError('IQM frame channel count')
    model = Model(arrays, meshes, triangles, [string(j[0]).rstrip('_') for j in joints],
                  [j[1] for j in joints], np.array([j[2:] for j in joints]), frames)
    validate(model)
    return model


def validate(model):
    vertices, joints = len(model.arrays[0]), len(model.names)
    if not 0 < joints <= 128 or len(set(model.names)) != joints or len(model.parents) != joints:
        raise ValueError('invalid IQM skeleton')
    if any(p < -1 or p >= j for j, p in enumerate(model.parents)):
        raise ValueError('IQM parents must precede children')
    if model.frames.ndim != 3 or model.frames.shape[1:] != (joints, 10) or not len(model.frames) or model.bind.shape != (joints, 10):
        raise ValueError('invalid IQM poses')
    for kind, width in ((0, 3), (1, 2), (2, 3), (4, 4), (5, 4)):
        if model.arrays[kind].shape != (vertices, width) or not np.isfinite(model.arrays[kind]).all():
            raise ValueError('invalid IQM vertex array')
    if model.arrays[4].max() >= joints or not (model.arrays[5].astype(int).sum(axis=1) == 255).all():
        raise ValueError('invalid IQM skin weights')
    if not np.isfinite(model.frames).all() or not np.isfinite(model.bind).all():
        raise ValueError('nonfinite IQM pose')
    for name, material, fv, nv, ft, nt in model.meshes:
        if len(name) >= 64 or len(material) >= 64 or not 0 < nv < 1000 or not 0 < nt < 2000 or fv + nv > vertices or ft + nt > len(model.triangles):
            raise ValueError('IQM mesh exceeds renderer limits')
        tri = model.triangles[ft:ft + nt]
        if tri.min() < fv or tri.max() >= fv + nv:
            raise ValueError('IQM triangle outside its mesh')


def matrices(channels, parents):
    """Parent-relative IQM channels -> absolute 4x4 matrices, for any leading axes."""
    q = channels[..., 3:7]
    q = q / np.maximum(np.linalg.norm(q, axis=-1, keepdims=True), 1e-12)
    x, y, z, w = np.moveaxis(q, -1, 0)
    r = np.stack((1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w),
                  2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w),
                  2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)), axis=-1).reshape(channels.shape[:-1] + (3, 3))
    out = np.zeros(channels.shape[:-1] + (4, 4))
    out[..., :3, :3] = r * channels[..., None, 7:10]
    out[..., :3, 3] = channels[..., :3]
    out[..., 3, 3] = 1
    for j, parent in enumerate(parents):
        if parent >= 0:
            out[..., j, :, :] = out[..., parent, :, :] @ out[..., j, :, :]
    return out


def channels(mats, parents):
    """Absolute rigid matrices -> local IQM poses. Eigenvectors avoid 180-degree singularities."""
    local = mats.copy()
    for j, parent in enumerate(parents):
        if parent >= 0:
            local[..., j, :, :] = np.linalg.inv(mats[..., parent, :, :]) @ mats[..., j, :, :]
    r = local[..., :3, :3]
    k = np.empty(r.shape[:-2] + (4, 4))
    a, b, c = r[..., 0, 0], r[..., 1, 1], r[..., 2, 2]
    k[..., 0, 0], k[..., 1, 1], k[..., 2, 2], k[..., 3, 3] = a-b-c, b-a-c, c-a-b, a+b+c
    for i, j, value in ((0, 1, r[..., 0, 1]+r[..., 1, 0]), (0, 2, r[..., 0, 2]+r[..., 2, 0]),
                        (1, 2, r[..., 1, 2]+r[..., 2, 1]), (0, 3, r[..., 2, 1]-r[..., 1, 2]),
                        (1, 3, r[..., 0, 2]-r[..., 2, 0]), (2, 3, r[..., 1, 0]-r[..., 0, 1])):
        k[..., i, j] = k[..., j, i] = value
    _, vectors = np.linalg.eigh(k)
    q = vectors[..., -1]
    q *= np.where(q[..., 3:] < 0, -1, 1)
    result = np.ones(local.shape[:-2] + (10,))
    result[..., :3], result[..., 3:7] = local[..., :3, 3], q
    # IQM interpolates channels. Adjacent antipodal quaternions must agree.
    if result.ndim == 3:
        for f in range(1, len(result)):
            flip = (result[f, :, 3:7] * result[f-1, :, 3:7]).sum(axis=1) < 0
            result[f, flip, 3:7] *= -1
    return result


def skin(model, frames=None):
    transforms = matrices(model.frames if frames is None else frames, model.parents) @ np.linalg.inv(matrices(model.bind, model.parents))
    p = model.arrays[0]
    out = np.zeros((len(transforms), len(p), 3))
    for influence in range(4):
        m = transforms[:, model.arrays[4][:, influence]]
        out += (np.einsum('fvij,vj->fvi', m[..., :3, :3], p) + m[..., :3, 3]) * (model.arrays[5][:, influence] / 255)[None, :, None]
    return out


def write(model):
    validate(model)
    # OpenGL2 requires tangent space even for diffuse-only skeletal meshes.
    # Build it from indexed UV derivatives; mirrored islands retain handedness.
    p, uv, n = model.arrays[0], model.arrays[1], model.arrays[2]
    tri = model.triangles
    edges = p[tri[:, 1:]] - p[tri[:, :1]]
    delta = uv[tri[:, 1:]] - uv[tri[:, :1]]
    determinant = delta[:, 0, 0]*delta[:, 1, 1] - delta[:, 0, 1]*delta[:, 1, 0]
    reciprocal = np.divide(1., determinant, out=np.zeros_like(determinant), where=np.abs(determinant) > 1e-10)
    tangent = (edges[:, 0]*delta[:, 1, 1:2] - edges[:, 1]*delta[:, 0, 1:2])*reciprocal[:, None]
    bitangent = (edges[:, 1]*delta[:, 0, 0:1] - edges[:, 0]*delta[:, 1, 0:1])*reciprocal[:, None]
    t, b = np.zeros_like(p, dtype=float), np.zeros_like(p, dtype=float)
    for corner in range(3):
        np.add.at(t, tri[:, corner], tangent)
        np.add.at(b, tri[:, corner], bitangent)
    t -= n * (n*t).sum(axis=1, keepdims=True)
    lengths = np.linalg.norm(t, axis=1)
    missing = lengths < 1e-10
    axes = np.eye(3)[np.argmin(np.abs(n[missing]), axis=1)]
    t[missing] = np.cross(n[missing], axes)
    t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-10)
    model.arrays[3] = np.column_stack((t, np.where((np.cross(n, t)*b).sum(axis=1) < 0, -1, 1)))
    buffer = bytearray(iqm.HEADER.size)
    counts = {}

    def block(name, data, count=None):
        buffer.extend(bytes(-len(buffer) % 4))
        counts['ofs_' + name] = len(buffer)
        if count is not None:
            counts['num_' + name] = count
        buffer.extend(data)

    names = list(model.names)
    # Both renderer loaders pack the joint-name run before aligned numeric arrays.
    names[0] += '_' * (-sum(len(n) + 1 for n in names) % 4)
    strings = list(dict.fromkeys([''] + names + [s for m in model.meshes for s in m[:2]]))
    text, offsets = bytearray(), {}
    for s in strings:
        offsets[s] = len(text)
        text.extend(s.encode('ascii') + b'\0')
    block('text', text, len(text))
    block('meshes', b''.join(iqm.MESH.pack(offsets[n], offsets[m], *rest) for n, m, *rest in model.meshes), len(model.meshes))
    va = []
    for kind in (0, 1, 2, 3, 4, 5):
        arr = model.arrays[kind].astype('u1' if kind in (4, 5) else '<f4')
        buffer.extend(bytes(-len(buffer) % 4))
        va.append(iqm.VERTEX_ARRAY.pack(kind, 0, 1 if kind in (4, 5) else 7, arr.shape[1], len(buffer)))
        buffer.extend(arr.tobytes())
    block('vertexarrays', b''.join(va), len(va))
    counts['num_vertexes'] = len(model.arrays[0])
    block('triangles', model.triangles.astype('<u4').tobytes(), len(model.triangles))
    block('joints', b''.join(JOINT.pack(offsets[n], p, *v) for n, p, v in zip(names, model.parents, model.bind)), len(names))
    low, high = model.frames.min(axis=0), model.frames.max(axis=0)
    moving = high > low
    scale = (high - low) / 65535
    masks = (moving.astype(np.uint32) << np.arange(10)).sum(axis=1)
    block('poses', b''.join(POSE.pack(p, int(mask), *lo, *sc) for p, mask, lo, sc in zip(model.parents, masks, low, scale)), len(names))
    packed = np.rint((model.frames - low) / np.where(moving, scale, 1))[:, moving].astype('<u2')
    block('frames', packed.tobytes(), len(model.frames))
    counts['num_framechannels'] = int(moving.sum())
    # A weighted skin point lies in the convex hull of its transformed joint
    # points. Bone-local boxes therefore give conservative bounds without
    # skinning the detailed mesh for every cinematic frame during conversion.
    inverse = np.linalg.inv(matrices(model.bind, model.parents))
    boxes, used = [], []
    for j in range(len(names)):
        influenced = ((model.arrays[4] == j) & (model.arrays[5] > 0)).any(axis=1)
        if not influenced.any(): continue
        local = p[influenced] @ inverse[j, :3, :3].T + inverse[j, :3, 3]
        lo, hi = local.min(axis=0), local.max(axis=0)
        boxes.append(np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]))
        used.append(j)
    boxes = np.array(boxes)
    bounds = []
    for start in range(0, len(model.frames), 256):
        absolute = matrices(model.frames[start:start+256], model.parents)[:, used]
        points = (np.einsum('fjab,jvb->fjva', absolute[..., :3, :3], boxes) + absolute[..., None, :3, 3]).reshape(len(absolute), -1, 3)
        for frame in points:
            lo, hi = frame.min(axis=0)-.01, frame.max(axis=0)+.01
            radius = np.maximum(np.abs(lo), np.abs(hi))
            bounds.append(iqm.BOUNDS.pack(*lo, *hi, np.linalg.norm(radius[:2]), np.linalg.norm(radius)))
    block('bounds', b''.join(bounds))
    if len(buffer) > iqm.MAX_FILESIZE:
        raise ValueError('skeletal model exceeds IQM file limit')
    buffer[:iqm.HEADER.size] = iqm.HEADER.pack(iqm.MAGIC, 2, len(buffer), *(counts.get(n, 0) for n, _ in iqm.HEADER_FIELDS[3:]))
    return bytes(buffer)
