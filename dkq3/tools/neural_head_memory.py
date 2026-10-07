# SPDX-License-Identifier: GPL-2.0-or-later
"""Bound row-independent decoder normalization without reducing reconstruction detail."""
import torch
import torch.nn.functional as functional


def layer_norm_rows(module, features, rows=65536):
    output = torch.empty_like(features)
    for start in range(0, len(features), rows):
        chunk = features[start:start + rows].float()
        normalized = functional.layer_norm(chunk, module.normalized_shape, module.weight, module.bias, module.eps)
        output[start:start + rows] = normalized.to(features.dtype)
    return output


def install():
    from trellis2.modules.norm import LayerNorm32
    original = LayerNorm32.forward

    def forward(module, features):
        if features.ndim != 2 or features.requires_grad or features.numel() < 16777216 or torch.is_autocast_enabled():
            return original(module, features)
        return layer_norm_rows(module, features)

    LayerNorm32.forward = forward
    from trellis2.models.sc_vaes.sparse_unet_vae import SparseConvNeXtBlock3d
    original_block = SparseConvNeXtBlock3d._forward

    def block_forward(module, sparse):
        if sparse.feats.requires_grad or sparse.feats.numel() < 16777216:
            return original_block(module, sparse)
        result = module.conv(sparse)
        result = result.replace(module.norm(result.feats))
        output = torch.empty_like(result.feats)
        for start in range(0, len(output), 32768):
            output[start:start + 32768] = module.mlp(result.feats[start:start + 32768])
        return result.replace(output) + sparse

    SparseConvNeXtBlock3d._forward = block_forward
    from trellis2.modules.sparse.conv import conv_flex_gemm
    original_convolution = conv_flex_gemm.sparse_conv3d_forward

    def convolution(module, sparse):
        # Decoding only proceeds toward finer scales. Previous neighbor maps
        # are derived data and are not subdivision guides for texture decoding.
        active = str(sparse._scale)
        for scale, cache in sparse._spatial_cache.items():
            if scale != active:
                for key in list(cache):
                    if key.startswith('SubMConv3d_neighbor_cache_'):
                        del cache[key]
        return original_convolution(module, sparse)

    conv_flex_gemm.sparse_conv3d_forward = convolution


def clear_convolution_caches(tensors):
    """Drop derived neighbor maps; retain subdivision guides and coordinates."""
    released = 0
    seen = set()
    for tensor in tensors:
        cache = tensor._spatial_cache
        if id(cache) in seen:
            continue
        seen.add(id(cache))
        for level in cache.values():
            for key in list(level):
                if key.startswith('SubMConv3d_neighbor_cache_'):
                    del level[key]
                    released += 1
    return released
