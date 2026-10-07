#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Use the admitted full-resolution TRELLIS pipeline for dedicated heads."""
import argparse
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path
import sys

parser = argparse.ArgumentParser(add_help=False)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--actor', type=Path, required=True)
parser.add_argument('--sampling-settings', type=Path)
parser.add_argument('--resolution', default='1024_cascade')
args, _ = parser.parse_known_args()
os.environ.setdefault('ATTN_BACKEND', 'sdpa')
os.environ.setdefault('SPARSE_ATTN_BACKEND', 'xformers')
sys.path.insert(0, str(args.source.resolve()))
import torch
from neural_head_memory import install, clear_convolution_caches
install()
from trellis2.pipelines import Trellis2ImageTo3DPipeline
from trellis2.modules.sparse import SparseTensor
from trellis2.representations.mesh.base import MeshWithVoxel

original_run = Trellis2ImageTo3DPipeline.run
latent_file = args.actor / 'head-latents.pt'
latent_receipt = args.actor / 'head-latents.json'


def fingerprint(seed, pipeline_type):
    result = dict(image_sha256=hashlib.sha256((args.actor / 'concept.png').read_bytes()).hexdigest(),
                pipeline_sha256=hashlib.sha256(Path(__file__).with_name('neural_monster_trellis.py').read_bytes()).hexdigest(),
                weights_sha256=hashlib.sha256((args.source.parent.parent / 'weights.json').read_bytes()).hexdigest(),
                seed=seed, pipeline_type=pipeline_type)
    if args.sampling_settings:
        result['sampling_settings_sha256'] = hashlib.sha256(args.sampling_settings.read_bytes()).hexdigest()
    return result


@torch.no_grad()
def decode(pipeline, shape, texture, resolution):
    # flex_gemm consults weight.requires_grad even inside torch.no_grad().
    # Inference weights are frozen so no backward-only neighbor maps are built.
    for model in pipeline.models.values():
        model.requires_grad_(False)
    saved = dict(shape_features=shape.feats.cpu(), shape_coords=shape.coords.cpu(), shape_scale=list(shape._scale),
                 texture_features=texture.feats.cpu(), texture_coords=texture.coords.cpu(), texture_scale=list(texture._scale),
                 resolution=resolution)
    temporary = latent_file.with_suffix('.pending')
    torch.save(saved, temporary)
    temporary.replace(latent_file)
    del saved
    latent_receipt.write_text(json.dumps(pipeline._head_latent_fingerprint, indent=2) + '\n')
    meshes, subs = pipeline.decode_shape_slat(shape, resolution)
    # Texture decoding does not consume mesh geometry. Stage it on the host
    # while the independent sparse color decoder occupies the device.
    for mesh in meshes:
        mesh.vertices = mesh.vertices.cpu()
        mesh.faces = mesh.faces.cpu()
    released = clear_convolution_caches([shape, texture, *subs])
    torch.cuda.empty_cache()
    print('Head texture decoding: staged geometry on CPU; released neighbor caches', released, flush=True)
    voxels = pipeline.decode_tex_slat(texture, subs)
    del subs
    torch.cuda.empty_cache()
    results = []
    for mesh, voxel in zip(meshes, voxels):
        mesh.vertices = mesh.vertices.to(pipeline.device)
        mesh.faces = mesh.faces.to(pipeline.device)
        mesh.fill_holes()
        results.append(MeshWithVoxel(mesh.vertices, mesh.faces, origin=[-.5, -.5, -.5],
                                    voxel_size=1 / resolution, coords=voxel.coords[:, 1:], attrs=voxel.feats,
                                    voxel_shape=torch.Size([*voxel.shape, *voxel.spatial_shape]),
                                    layout=pipeline.pbr_attr_layout))
    return results


@torch.no_grad()
def run(pipeline, image, *positional, **options):
    key = fingerprint(options.get('seed', 42), options.get('pipeline_type', '1024_cascade'))
    pipeline._head_latent_fingerprint = key
    if latent_file.exists() and latent_receipt.exists() and json.loads(latent_receipt.read_text()) == key:
        print('Reusing exact sampled head latents', flush=True)
        with torch.serialization.safe_globals([Fraction]):
            saved = torch.load(latent_file, map_location='cpu', weights_only=True)
        shape = SparseTensor(saved['shape_features'].to(pipeline.device), saved['shape_coords'].to(pipeline.device))
        shape._scale = tuple(saved['shape_scale'])
        texture = SparseTensor(saved['texture_features'].to(pipeline.device), saved['texture_coords'].to(pipeline.device))
        texture._scale = tuple(saved['texture_scale'])
        resolution = saved['resolution']
        del saved
        return pipeline.decode_latent(shape, texture, resolution)
    return original_run(pipeline, image, *positional, **options)


Trellis2ImageTo3DPipeline.decode_latent = decode
Trellis2ImageTo3DPipeline.run = run
import o_voxel
original_export = o_voxel.postprocess.to_glb


def export(**options):
    # Preserve the full-resolution inferred surface. A second dual-contouring
    # rebuild with projection disabled tears thin hair/cloth and shifts features.
    options['remesh'] = False
    return original_export(**options)


o_voxel.postprocess.to_glb = export
for name in ('model.glb','trellis.json'):
    path = args.actor/name
    if path.is_file():
        backup = path.with_name(path.stem+'-before-surface-export-'+hashlib.sha256(path.read_bytes()).hexdigest()[:12]+path.suffix)
        if not backup.exists():
            backup.write_bytes(path.read_bytes())
from neural_monster_trellis import main
main()
(args.actor/'head-export.json').write_text(json.dumps(dict(
    mode='Published o_voxel standard surface cleanup, no second dual-contouring rebuild',
    pipeline_type=args.resolution,texture_size=4096,decimation_target=100000,
    tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    output_glb_sha256=hashlib.sha256((args.actor/'model.glb').read_bytes()).hexdigest()),indent=2)+'\n')
