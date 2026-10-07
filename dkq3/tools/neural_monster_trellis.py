#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Local TRELLIS.2 inference with pinned weights, alpha input and 4096px atlas."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--actor', type=Path, required=True)
    parser.add_argument('--resolution', default='1024_cascade')
    parser.add_argument('--sampling-settings', type=Path, help='explicit reviewed sampling parameters; default pipeline settings otherwise')
    args = parser.parse_args()
    sampling = json.loads(args.sampling_settings.read_text()) if args.sampling_settings else {}
    allowed = {'sparse_structure_sampler_params', 'shape_slat_sampler_params', 'tex_slat_sampler_params'}
    if set(sampling) - allowed:
        raise ValueError('Unknown reconstruction sampler')
    for values in sampling.values():
        if set(values) - {'steps', 'guidance_strength', 'guidance_rescale'}:
            raise ValueError('Unsupported sampling parameter')
        if not 8 <= values.get('steps', 12) <= 64 or not 0 <= values.get('guidance_strength', 1) <= 10 or not 0 <= values.get('guidance_rescale', 0) <= 1:
            raise ValueError('Invalid sampling settings')
    deploy = args.source.parent.parent
    os.environ.setdefault('ATTN_BACKEND', 'sdpa')
    os.environ.setdefault('SPARSE_ATTN_BACKEND', 'xformers')
    os.environ.setdefault('PYTORCH_CUDA_ALLOC_CONF', 'expandable_segments:True')
    os.environ.setdefault('FLEX_GEMM_AUTOTUNE_CACHE_PATH', str(deploy/'flex-gemm-cache.json'))
    os.environ.setdefault('TORCH_EXTENSIONS_DIR', str(deploy/'torch-extensions'))
    os.environ.setdefault('TRITON_CACHE_DIR', str(deploy/'triton-cache'))
    os.environ.setdefault('CC', '/usr/bin/gcc-14')
    os.environ.setdefault('CXX', '/usr/bin/g++-14')
    os.environ.setdefault('CUDA_HOME', '/usr/local/cuda-12.9')
    os.environ.setdefault('TORCH_CUDA_ARCH_LIST', '12.0')
    os.environ.setdefault('MAX_JOBS', '2')
    sys.path.insert(0, str(args.source.resolve()))
    import torch
    import torch.nn.functional as functional
    import numpy as np
    import timm
    import xformers.ops as xops
    from safetensors.torch import load_file
    from PIL import Image
    from trellis2.pipelines import Trellis2ImageTo3DPipeline
    from trellis2.modules import image_feature_extractor
    from trellis2.pipelines import rembg
    from trellis2.representations.mesh.base import Mesh, MeshWithVoxel
    from neural_trellis_memory import install
    import o_voxel
    install()
    if not torch.cuda.is_available(): raise RuntimeError('TRELLIS.2 requires the local CUDA device')
    # The wheel's automatic choice launches a Hopper-only FlashAttention 3
    # kernel on sm_120. CUTLASS supports the sparse block-diagonal masks here;
    # dense attention uses PyTorch's qualified SDPA dispatcher.
    efficient_attention = xops.memory_efficient_attention
    def blackwell_attention(*args, **kwargs):
        kwargs.setdefault('op', xops.MemoryEfficientAttentionCutlassOp)
        return efficient_attention(*args, **kwargs)
    xops.memory_efficient_attention = blackwell_attention
    fill_holes = Mesh.fill_holes
    def bounded_hole_fill(mesh, *args, **kwargs):
        # CuMesh uses cudaMalloc outside PyTorch's caching allocator. Release
        # inactive decoder blocks before its topology allocations.
        torch.cuda.empty_cache()
        return fill_holes(mesh, *args, **kwargs)
    Mesh.fill_holes = bounded_hole_fill
    records = json.loads((deploy/'weights.json').read_text())
    weights = {row['repository']: Path(row['path']) for row in records}

    class PublisherDinoV3:
        """Same ViT-L/16 LVD1689M weights in the publisher's public timm layout.

        Match the original extractor: raw tokens, bfloat16-quantized RoPE periods,
        ImageNet normalization and functional layer norm without learned affine.
        """
        def __init__(self, model_name, image_size=512):
            self.image_size = image_size
            self.model = timm.create_model('vit_large_patch16_dinov3.lvd1689m', pretrained=False,
                                           dynamic_img_size=True, img_size=512)
            state = load_file(str(weights['timm/vit_large_patch16_dinov3.lvd1689m']/'model.safetensors'))
            self.model.load_state_dict(state, strict=True)
            self.model.norm = torch.nn.Identity()
            self.model.rope.periods = self.model.rope.periods.to(torch.bfloat16).to(torch.float32)
            self.model.eval()

        def to(self, device): self.model.to(device)
        def cuda(self): self.model.cuda()
        def cpu(self): self.model.cpu()

        @torch.no_grad()
        def __call__(self, images):
            if isinstance(images, list):
                images = torch.stack([torch.from_numpy(np.array(image.resize((self.image_size, self.image_size), Image.Resampling.LANCZOS).convert('RGB')).astype(np.float32)/255).permute(2, 0, 1) for image in images]).cuda()
            means = images.new_tensor([.485, .456, .406])[None, :, None, None]
            stds = images.new_tensor([.229, .224, .225])[None, :, None, None]
            features = self.model.forward_features((images-means)/stds)
            return functional.layer_norm(features, features.shape[-1:])

    class AlphaInput:
        def __init__(self, **kwargs): pass
        def to(self, device): pass
        def cuda(self): pass
        def cpu(self): pass
        def __call__(self, image): raise ValueError('This pipeline requires an RGBA concept with real transparency')

    image_feature_extractor.DinoV3FeatureExtractor = PublisherDinoV3
    rembg.BiRefNet = AlphaInput
    config = json.loads((weights['microsoft/TRELLIS.2-4B']/'pipeline.json').read_text())
    for name, path in config['args']['models'].items():
        if path.startswith('microsoft/TRELLIS-image-large/'):
            path = weights['microsoft/TRELLIS-image-large']/path.removeprefix('microsoft/TRELLIS-image-large/')
        else: path = weights['microsoft/TRELLIS.2-4B']/path
        config['args']['models'][name] = str(path)
    configured = deploy/'configured'
    configured.mkdir(exist_ok=True)
    (configured/'pipeline.json').write_text(json.dumps(config))
    image = Image.open(args.actor/'concept.png')
    if image.mode != 'RGBA' or image.getextrema()[3][0] == 255: raise ValueError('Expected a transparent concept image')
    start = time.monotonic()
    seed = int.from_bytes(hashlib.sha256(args.actor.name.encode()).digest()[:4], 'little') & 0x7fffffff
    checkpoint = args.actor/'generated-mesh.pt'
    checkpoint_report = checkpoint.with_suffix('.json')
    fingerprint = dict(image=hashlib.sha256((args.actor/'concept.png').read_bytes()).hexdigest(),
                       resolution=args.resolution,seed=seed,weights=records,
                       encoder='public DINOv3 LVD1689M; quantized RoPE; nonaffine layer norm')
    if sampling:
        fingerprint['sampling'] = sampling
    if checkpoint.is_file() and checkpoint_report.is_file() and json.loads(checkpoint_report.read_text())==fingerprint:
        saved = torch.load(checkpoint,map_location='cuda',weights_only=True)
        saved['layout'] = {k:slice(*v) for k,v in saved['layout'].items()}
        mesh = MeshWithVoxel(**saved)
        print('Reusing generated mesh checkpoint',flush=True)
    else:
        pipeline = Trellis2ImageTo3DPipeline.from_pretrained(str(configured))
        pipeline.low_vram = True
        pipeline.cuda()
        mesh = pipeline.run(image, seed=seed, pipeline_type=args.resolution, max_num_tokens=32768, **sampling)[0]
        saved = {k:getattr(mesh,k).cpu() for k in ('vertices','faces','coords','attrs')}
        saved.update(origin=mesh.origin.tolist(),voxel_size=mesh.voxel_size,voxel_shape=list(mesh.voxel_shape),
                     layout={k:[v.start,v.stop,v.step] for k,v in mesh.layout.items()})
        temporary=checkpoint.with_suffix('.pending')
        torch.save(saved,temporary)
        temporary.replace(checkpoint)
        checkpoint_report.write_text(json.dumps(fingerprint,sort_keys=True,indent=2)+'\n')
        del saved,pipeline
    import gc
    gc.collect()
    torch.cuda.empty_cache()
    mesh.simplify(16777216)
    torch.cuda.empty_cache()
    glb = o_voxel.postprocess.to_glb(vertices=mesh.vertices, faces=mesh.faces,
        attr_volume=mesh.attrs, coords=mesh.coords, attr_layout=mesh.layout, voxel_size=mesh.voxel_size,
        aabb=[[-.5, -.5, -.5], [.5, .5, .5]], decimation_target=100000,
        texture_size=4096, remesh=True, remesh_band=1, remesh_project=0, verbose=True)
    temporary = args.actor/'model.pending.glb'
    glb.export(str(temporary), extension_webp=True)
    temporary.replace(args.actor/'model.glb')
    report = dict(format=1, generator='microsoft/TRELLIS.2-4B', source=args.source.name,
                  weights=records, encoder='timm public publisher conversion; same DINOv3 ViT-L/16 LVD1689M',
                  resolution=args.resolution, seed=seed, texture_size=4096, low_vram=True,
                  attention='dense PyTorch SDPA; sparse xformers CUTLASS',
                  device=torch.cuda.get_device_name(), seconds=time.monotonic()-start,
                  input_sha256=hashlib.sha256((args.actor/'concept.png').read_bytes()).hexdigest(),
                  glb_sha256=hashlib.sha256((args.actor/'model.glb').read_bytes()).hexdigest())
    if sampling:
        report['sampling'] = sampling
        report['sampling_settings_sha256'] = hashlib.sha256(args.sampling_settings.read_bytes()).hexdigest()
    (args.actor/'trellis.json').write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__': main()
