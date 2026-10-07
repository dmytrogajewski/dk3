#!/usr/bin/env python3.14
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate a map's image set locally: SDXL + tile ControlNet for albedo, procedural
periodic fields for height, and derived normal / specular / glow / alpha maps.

Run with the CUDA interpreter, one pass per material:

    python3.14 -B dkq3/tools/neural_textures.py --recipes maps/japanDM/textures.py \
        --out maps/japanDM/assets --dir japandm [--only a,b] [--sky] [--force]

Why this shape rather than plain text-to-image:

* **Tileability is constructed, not asked for.** Every structure a material needs
  (slab grid, ribs, weave, plank seams) is generated here as a *periodic* field —
  FFT noise whose spectrum only contains whole-image frequencies, and patterns
  built with `index % period`. The diffusion model is steered by that field through
  `xinsir/controlnet-tile-sdxl-1.0`, so it decorates a structure that already
  wraps instead of inventing one that does not. Any residual edge mismatch is then
  moved to the middle of the tile by a half-period roll and softened there, which
  is invisible on a material and cannot touch the wrap boundary.
* **Normal maps come from the height field, not from the picture.** Diffusing a
  normal map produces lighting that disagrees with the albedo the moment the light
  moves; deriving it from the same field the ControlNet saw keeps bump and
  pattern registered, and FFT derivatives of a periodic field have no edge
  artefacts to hide. renderergl2 finds `<name>_n` and `<name>_s` by itself
  (`CollapseStagesToLightall` in tr_shader.c), so a companion map needs no shader
  line — and an absent one degrades quietly to a flat surface.
* **Specular and glow are derived, so they cannot drift** from the albedo they
  belong to: a specular level from luminance and the recipe's material character,
  a glow mask as the bright pass of the same image.
* **The sky is one panorama reprojected into six faces**, because six independently
  generated faces cannot agree at a cube edge. The reprojection follows
  `MakeSkyVec` in `engine/ioquake3/code/renderergl2/tr_sky.c`: with `u` across and
  `v` down a face image, `rt` looks at `(1, -(2u-1), 1-2v)`, `bk` at `(-1, 2u-1,
  1-2v)`, `lf` at `(2u-1, 1, 1-2v)`, `ft` at `(-(2u-1), -1, 1-2v)`, `up` at
  `(2v-1, 1-2u, 1)` and `dn` at `(1-2v, 1-2u, -1)` — a non-mirrored view, which is
  what makes the six faces meet. Each face then gets its own detail pass steered by
  its own reprojection, so a 90-degree face is not a 384-pixel strip of panorama.

FLUX.1-dev is deliberately not used: its licence is research/non-commercial, and
this map ships. SDXL base 1.0 and the xinsir tile ControlNet are CreativeML Open
RAIL++-M and the fp16 VAE fix is MIT; the manifest records that per image.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import time

import numpy as np


# --------------------------------------------------------------------------- #
# periodic fields (no GPU needed)
# --------------------------------------------------------------------------- #
def periodic_noise(height, width, octaves=5, base=4, seed=0, decay=2.2, anisotropy=1.0):
    """-> fractal value noise in 0..1 whose spectrum holds only whole-image
    frequencies, so the field wraps exactly in both axes. `anisotropy` squeezes the
    vertical frequencies, which is what brushed metal and woven cloth want."""
    rng = np.random.default_rng(seed)
    total, weight_sum = None, 0.0
    for octave in range(octaves):
        frequency = base * (2 ** octave)
        fy = np.fft.fftfreq(height)[:, None] * max(1.0, frequency / anisotropy)
        fx = np.fft.rfftfreq(width)[None, :] * frequency
        radius = np.sqrt(fy ** 2 + fx ** 2)
        spectrum = rng.normal(size=radius.shape) + 1j * rng.normal(size=radius.shape)
        spectrum /= (1.0 + radius) ** (decay / 2.0)
        field = np.fft.irfft2(spectrum, s=(height, width))
        field /= (field.std() or 1.0)
        weight = 0.55 ** octave
        total = field * weight if total is None else total + field * weight
        weight_sum += weight
    field = total / weight_sum
    return np.clip(0.5 + 0.42 * field, 0.0, 1.0).astype(np.float32)


def _wrap_shift(size, amount):
    return int(round(amount * size)) % size


def height_field(kind, size, spec, seed=0):
    """-> the periodic height field named by a recipe's `control` block."""
    grit = float(spec.get('grit', 0.5))
    cells = int(spec.get('cells', 4))
    mortar = float(spec.get('mortar', 0.1))
    bolts = float(spec.get('bolts', 0.0))
    blur = float(spec.get('blur', 1.0))
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    if kind == 'grit':
        field = periodic_noise(size, size, 6, max(2, int(spec.get('grit_base', 8))), seed, 2.6)
        veins = periodic_noise(size, size, 3, int(spec.get('veins', 10)) or 8, seed + 7, 1.4)
        field = 0.72 * field + 0.28 * veins
    elif kind == 'slabs':
        u = (x / size) * cells
        row = (y / size) * cells
        v = row + np.where(np.floor(row) % 2 == 1, 0.5, 0.0)
        gap = np.minimum(np.minimum(u % 1.0, 1.0 - (u % 1.0)), np.minimum(v % 1.0, 1.0 - (v % 1.0)))
        field = np.clip(gap / max(mortar, 1e-3), 0, 1) ** 0.6
        field = 0.75 * field + 0.25 * periodic_noise(size, size, 5, cells * 2, seed, 2.4)
    elif kind == 'panels':
        u, v = (x / size) * cells, (y / size) * cells
        gap = np.minimum(np.minimum(u % 1.0, 1.0 - (u % 1.0)), np.minimum(v % 1.0, 1.0 - (v % 1.0)))
        field = np.clip(gap / max(mortar, 1e-3), 0, 1) ** 0.5
        tile = np.floor(u) * 7919 + np.floor(v) * 104729
        tone = ((np.sin(tile) * 43758.5453) % 1.0).astype(np.float32)
        field = 0.55 * field + 0.2 * (0.5 + 0.5 * (tone - 0.5)) + 0.25 * periodic_noise(
            size, size, 6, cells * 3, seed, 2.3)
        if bolts:
            bolt = periodic_noise(size, size, 1, cells * 2, seed + 11, 1.0)
            spots = np.exp(-((bolt - 0.5) * 60) ** 2).astype(np.float32)
            field = np.clip(field + bolts * spots, 0, 1)
    elif kind == 'ribs':
        u = (x / size) * cells
        v = (y / size) * cells
        ridge = np.abs(np.sin(u * math.pi)) ** 0.6 * 0.75 + np.abs(np.sin(v * math.pi)) ** 0.6 * 0.35
        field = ridge + grit * 0.3 * periodic_noise(size, size, 5, cells * 2, seed, 2.5)
        if bolts:
            bx = ((u + 0.5) % 2.0) - 1.0
            by = ((v + 0.5) % 2.0) - 1.0
            field = np.clip(field + bolts * np.exp(-((bx ** 2 + by ** 2) * 900.0)), 0, 1)
    elif kind == 'brushed':
        field = periodic_noise(size, size, 5, 6, seed, 2.0, anisotropy=26.0)
        field = 0.7 * field + 0.3 * periodic_noise(size, size, 4, 3, seed + 3, 2.0, anisotropy=60.0)
    elif kind == 'grid':
        u, v = (x / size) * cells, (y / size) * cells
        bar = np.clip(np.minimum(np.minimum(u % 1.0, 1.0 - (u % 1.0)),
                                 np.minimum(v % 1.0, 1.0 - (v % 1.0))) / max(mortar, 1e-3), 0, 1)
        field = bar ** 0.4 + grit * 0.25 * periodic_noise(size, size, 5, cells * 3, seed, 2.4)
    elif kind == 'weave':
        warp = np.sin((x / size) * cells * 2.0 * math.pi) ** 2
        weft = np.sin((y / size) * cells * 2.0 * math.pi) ** 2
        field = 0.5 * warp + 0.5 * weft + grit * 0.25 * periodic_noise(size, size, 5, 24, seed, 2.2)
    elif kind == 'planks':
        v = (y / size) * cells
        seam = np.clip(np.minimum(v % 1.0, 1.0 - (v % 1.0)) / 0.06, 0, 1) ** 0.5
        grain = periodic_noise(size, size, 5, 5, seed, 2.4, anisotropy=14.0)
        field = 0.6 * seam + 0.4 * grain
    elif kind == 'blocks':
        block = periodic_noise(size, size, 3, 3, seed, 1.2)
        stroke = periodic_noise(size, size, 2, int(spec.get('cells', 4)), seed + 5, 1.0, anisotropy=1.6)
        field = 0.55 * (block > 0.45) + 0.45 * (stroke > 0.52)
    elif kind == 'ripple':
        cx, cy = size / 2.0, size / 2.0
        d = np.minimum.reduce([np.abs(x - cx), np.abs(x - cx - size), np.abs(x - cx + size)])
        e = np.minimum.reduce([np.abs(y - cy), np.abs(y - cy - size), np.abs(y - cy + size)])
        rings = 0.5 + 0.5 * np.cos(np.sqrt(d ** 2 + e ** 2) / size * cells * 4.0 * math.pi)
        field = rings * 0.7 + 0.3 * periodic_noise(size, size, 4, cells, seed, 2.2)
    else:
        raise ValueError('unknown control kind %r' % kind)
    field = np.clip(field, 0.0, 1.0)
    if blur > 0:
        from scipy.ndimage import gaussian_filter
        field = gaussian_filter(field, blur, mode='wrap')
    low, high = float(field.min()), float(field.max())
    field = (field - low) / (high - low) if high > low else field * 0 + 0.5
    return field.astype(np.float32)


def slopes(field):
    """-> (dh/dx, dh/dy) of a periodic field, taken in the Fourier domain, so a
    derivative has no edge special case to disagree with its wrap."""
    size = field.shape[0]
    fy = np.fft.fftfreq(size)[:, None] * size * 1j
    fx = np.fft.rfftfreq(size)[None, :] * size * 1j
    spectrum = np.fft.rfft2(field.astype(np.float64))
    return (np.fft.irfft2(spectrum * fx, s=field.shape),
            np.fft.irfft2(spectrum * fy, s=field.shape))


def shaded(height, strength=1.0):
    """-> a 'clay render' of the height field: the tile ControlNet is a structure
    model, so it needs its control image to carry contrast, and a fixed key light
    gives edges without touching the periodicity."""
    dhdx, dhdy = slopes(height)
    nx, ny = -dhdx * strength * 3.0, -dhdy * strength * 3.0
    nz = np.ones_like(nx)
    length = np.sqrt(nx * nx + ny * ny + 1.0)
    lx, ly, lz = -0.55 / 1.0, -0.62 / 1.0, 0.56 / 1.0
    lambert = np.clip((nx * lx + ny * ly + nz * lz) / length, 0.0, 1.0)
    grey = np.clip(0.30 + 0.62 * height + 0.30 * lambert, 0.0, 1.0)
    tint = np.stack([grey * 0.96, grey * 0.97, grey * 1.0], axis=-1)
    return (np.clip(tint, 0, 1) * 255.0).astype(np.uint8)


def seamless(image, band=0.10, base_sigma=22.0, detail_sigma=4.0):
    """-> the image with its wrap discontinuity moved to the centre and softened.

    A cyclic half-period roll puts the *original* seam in the middle and puts
    continuous interior content on the tile boundary. What is left in the middle is
    softened in two scales: the low frequencies are blended across a wide band, the
    grain is blended across a narrow one, so the tile keeps its detail everywhere
    while the boundary rows and columns are never touched by the filter."""
    from scipy.ndimage import gaussian_filter
    size = image.shape[0]
    rolled = np.roll(np.roll(image, size // 2, axis=0), size // 2, axis=1)
    out = rolled.astype(np.float32)
    half = max(8, int(size * band / 2.0))
    centre = size // 2
    window = np.zeros((size, size), np.float32)
    window[centre - half:centre + half, :] = 1.0
    window[:, centre - half:centre + half] = 1.0
    window = gaussian_filter(window, half / 2.0, mode='constant')
    for sigma, weight in ((base_sigma, 1.0), (detail_sigma, 0.85)):
        smoothed = gaussian_filter(out, sigma, mode='reflect')
        out = out + weight * window[..., None] * (smoothed - out)
    return np.roll(np.roll(out, -size // 2, axis=0), -size // 2, axis=1).clip(0, 255).astype(np.uint8)


def normal_map(height, strength=1.0, vertical='down'):
    """-> tangent-space normal from the height field, derivatives taken in the
    Fourier domain so they are exact for a periodic field. Green follows the
    OpenGL convention (positive up the texture); `vertical='up'` flips it for a
    material whose bumps must read the other way."""
    dhdx, dhdy = slopes(height)
    gx, gy = dhdx * strength, dhdy * strength
    green = gy if vertical == 'down' else -gy
    nz = 1.0 / np.sqrt(1.0 + gx * gx + green * green)
    rgb = np.stack([-gx * nz, green * nz, nz], axis=-1)
    return ((rgb * 0.5 + 0.5) * 255.0).clip(0, 255).astype(np.uint8)


def specular_map(albedo, spec):
    """-> specular level from albedo luminance and the recipe's character: dark
    pixels of a metal are its oxidised, still-reflective parts, so luminance alone
    never decides."""
    luminance = (albedo.astype(np.float32) @ np.array([0.2126, 0.7152, 0.0722], np.float32)) / 255.0
    level = float(spec.get('base', 0.1)) + float(spec.get('gain', 0.2)) * (1.0 - luminance) ** float(
        spec.get('power', 1.5))
    tint = np.array(spec.get('tint', (0.6, 0.6, 0.6)), np.float32)
    return np.clip(level[..., None] * tint[None, None, :], 0, 1).__mul__(255).astype(np.uint8)


def glow_map(albedo, glow):
    """-> additive glow as the bright pass of the albedo, keeping its colour."""
    luminance = (albedo.astype(np.float32) @ np.array([0.2126, 0.7152, 0.0722], np.float32)) / 255.0
    threshold = float(glow.get('threshold', 0.4))
    pass_on = np.clip((luminance - threshold) / max(1e-3, 1.0 - threshold), 0, 1) ** float(
        glow.get('falloff', 1.25))
    colour = albedo.astype(np.float32) / 255.0
    return np.clip(pass_on[..., None] * colour * float(glow.get('gain', 1.0)), 0, 1).__mul__(255).astype(np.uint8)


def alpha_channel(shape, alpha, height=None, seed=0):
    noise = periodic_noise(shape[0], shape[1], 3, 5, seed, 2.0) if alpha.get('variation') else None
    level = np.full(shape, float(alpha.get('base', 96)), np.float32)
    if noise is not None:
        level = level + float(alpha.get('variation', 0.0)) * (noise - 0.5) * 2.0
    if height is not None:
        level = level + float(alpha.get('height_gain', 0.0)) * (height - 0.5) * 2.0
    return np.clip(level, 0, 255).astype(np.uint8)


def resample(image, size):
    """-> nearest-exact box downscale (or bilinear resize) with scipy, so a 1024
    generation can be stored at 512 or 256 without an image library."""
    from scipy.ndimage import zoom
    if image.shape[0] == size:
        return image
    factor = size / image.shape[0]
    if factor < 1.0 and (image.shape[0] % size) == 0:
        step = image.shape[0] // size
        shape = (size, step, size, step) + image.shape[2:]
        return image.reshape(shape).mean(axis=(1, 3)).round().astype(np.uint8)
    axes = (factor, factor) + (1.0,) * (image.ndim - 2)
    return np.clip(zoom(image.astype(np.float32), axes, order=1), 0, 255).astype(np.uint8)


# --------------------------------------------------------------------------- #
# diffusion
# --------------------------------------------------------------------------- #
class Studio:
    """One SDXL + tile ControlNet load for the whole map, kept resident."""

    def __init__(self, models, verbose=True):
        import torch
        from diffusers import AutoencoderKL, ControlNetModel, StableDiffusionXLControlNetPipeline
        self.torch = torch
        self.verbose = verbose
        # The local SDXL snapshot ships only its fp16 weights (unet has no plain
        # diffusion_pytorch_model file), so the pipeline asks for that variant; the
        # fp16-fix VAE and the tile ControlNet ship single-weight files instead.
        self.pipe = StableDiffusionXLControlNetPipeline.from_pretrained(
            models['sdxl'], variant='fp16', use_safetensors=True,
            vae=AutoencoderKL.from_pretrained(models['sdxl-vae'], use_safetensors=True,
                             torch_dtype=torch.float16),   # tiled decode keeps the latents' dtype
            controlnet=ControlNetModel.from_pretrained(models['tile-sdxl'], torch_dtype=torch.float16),
            torch_dtype=torch.float16)
        self.pipe.vae.enable_tiling()          # keeps a 1024^2 decode inside 24 GB
        self.pipe.to('cuda')
        self.unguided = None

    def text(self, prompt, negative, width, height, steps=28, guidance=6.5, seed=0):
        """-> uint8 (height, width, 3) with no control image at all.

        The ControlNet pipeline cannot run without one, so a plain SDXL pipeline
        is derived from the loaded one: `from_pipe` reuses the same unet, VAE and
        text encoders, so nothing is read from disk or allocated a second time.
        """
        if self.unguided is None:
            from diffusers import StableDiffusionXLPipeline
            # The parts are handed over rather than derived with `from_pipe`,
            # which re-reads them from disk at the default float32 and puts a
            # second copy of the same weights on the card.
            self.unguided = StableDiffusionXLPipeline(
                vae=self.pipe.vae, unet=self.pipe.unet, scheduler=self.pipe.scheduler,
                text_encoder=self.pipe.text_encoder, text_encoder_2=self.pipe.text_encoder_2,
                tokenizer=self.pipe.tokenizer, tokenizer_2=self.pipe.tokenizer_2)
        generator = self.torch.Generator(device='cuda').manual_seed(int(seed))
        drawn = self.unguided(prompt=prompt, negative_prompt=negative, height=height, width=width,
                             num_inference_steps=steps, guidance_scale=guidance, generator=generator,
                             original_size=(width, height), target_size=(width, height),
                             negative_original_size=(width, height),
                             negative_target_size=(width, height)).images[0]
        return np.asarray(drawn.convert('RGB'), np.uint8)

    def render(self, prompt, negative, control, size, steps=28, guidance=6.5, scale=0.62, seed=0,
               end=0.7):
        """-> uint8 image steered by `control`; `size` is a side or a (width, height) pair.

        Without `control` this is a plain text-to-image pass, which the panorama
        wants and a material never does.
        """
        from PIL import Image
        width, height = (size, size) if isinstance(size, int) else (int(size[0]), int(size[1]))
        if control is None:
            return self.text(prompt, negative, width, height, steps=steps, guidance=guidance, seed=seed)
        generator = self.torch.Generator(device='cuda').manual_seed(int(seed))
        image = Image.fromarray(control).resize((width, height), Image.BILINEAR)
        arguments = dict(prompt=prompt, negative_prompt=negative, height=height, width=width,
                         num_inference_steps=steps, guidance_scale=guidance, generator=generator)
        # SDXL conditioning wants the intended composition size explicitly; without it the
        # text encoder crops assume the training 1024^2 and drift on other sizes.
        arguments.update(original_size=(width, height), target_size=(width, height),
                         negative_original_size=(width, height), negative_target_size=(width, height))
        # diffusers names the tile control input `image` on this pipeline.
        arguments.update(image=image, controlnet_conditioning_scale=float(scale),
                         control_guidance_end=float(end))
        drawn = self.pipe(**arguments).images[0]
        return np.asarray(drawn.convert('RGB'), np.uint8)


def stable_seed(name, base=1000):
    return base + int(hashlib.sha256(name.encode()).hexdigest()[:6], 16) % 90000


# --------------------------------------------------------------------------- #
# sky
# --------------------------------------------------------------------------- #
CUBE_SIDES = ('rt', 'bk', 'lf', 'ft', 'up', 'dn')


def cube_face(side, size):
    """-> the (row, column) sampling position in panorama coordinates for one face,
    following MakeSkyVec's axis table (see the module docstring)."""
    v, u = np.mgrid[0:size, 0:size].astype(np.float64)
    # The face array is top-down: row 0 is the top of the picture, because
    # `dkimg.encode_tga` is what stores a TGA bottom-up and the renderer turns that
    # back on load.  A q3 `v` texcoord is measured from the image top, so it is the
    # row index itself.  Inverting it here as well mirrored every side face down --
    # a skyline hanging from the zenith, which is exactly what the engine drew.
    u = (u + 0.5) / size
    v = (v + 0.5) / size
    s, t = 2.0 * u - 1.0, 1.0 - 2.0 * v
    direction = {
        'rt': np.stack([np.ones_like(s), -s, t], axis=-1),
        'bk': np.stack([-np.ones_like(s), s, t], axis=-1),
        'lf': np.stack([s, np.ones_like(s), t], axis=-1),
        'ft': np.stack([-s, -np.ones_like(s), t], axis=-1),
        'up': np.stack([-t, -s, np.ones_like(s)], axis=-1),
        'dn': np.stack([t, -s, -np.ones_like(s)], axis=-1),
    }[side]
    dx, dy, dz = direction[..., 0], direction[..., 1], direction[..., 2]
    azimuth = np.arctan2(dy, dx)
    elevation = np.arctan2(dz, np.sqrt(dx * dx + dy * dy))
    return elevation, azimuth


def panorama_face(panorama, side, size):
    """-> one cube face sampled bilinearly out of the (H, W) panorama."""
    from scipy.ndimage import map_coordinates
    elevation, azimuth = cube_face(side, size)
    rows = (0.5 - elevation / math.pi) * panorama.shape[0]
    columns = (azimuth / (2.0 * math.pi) + 0.5) * panorama.shape[1]
    face = np.empty((size, size, panorama.shape[2]), np.float32)
    for channel in range(panorama.shape[2]):
        face[..., channel] = map_coordinates(panorama[..., channel].astype(np.float32),
                                            [np.mod(rows, panorama.shape[0]), columns],
                                            order=1, mode='grid-wrap')
    return face.clip(0, 255).astype(np.uint8)


def sky_gradient(width, height, top=(0.06, 0.07, 0.16), horizon_colour=(0.42, 0.26, 0.34),
                 bottom=(0.03, 0.03, 0.05), seed=0):
    """-> a smooth 2:1 dusk sky, the CPU stand-in for the diffusion pass.

    A gradient rather than noise, because the panorama's vertical axis is
    elevation: any horizontal structure that is not a horizon reads as a
    hallucinated object once the cube faces reproject it.
    """
    rows = (np.arange(height) + 0.5) / height
    ramp = np.clip((rows - 0.30) / 0.35, 0.0, 1.0) ** 1.6             # 0 zenith, 1 nadir
    band = np.exp(-((rows - 0.5) / 0.055) ** 2)                       # dusk glow at the horizon
    top = np.array(top, np.float32) * 255.0
    middle = np.array(horizon_colour, np.float32) * 255.0
    bottom = np.array(bottom, np.float32) * 255.0
    vertical = top[None, :] * (1.0 - ramp[:, None]) + bottom[None, :] * ramp[:, None]
    vertical = vertical * (1.0 - band[:, None]) + middle[None, :] * band[:, None]
    colour = np.repeat(vertical[:, None, :], width, axis=1)
    clouds = periodic_noise(height, width, octaves=4, base=3, seed=seed, decay=2.6,
                            anisotropy=8.0)
    clouds = gaussian_filter1d(clouds, (16.0, 42.0))                  # thin stretched cirrus
    colour *= (0.90 + 0.20 * clouds)[..., None]
    return colour.clip(0, 255).astype(np.uint8)


def gaussian_filter1d(noise, sigmas):
    """-> the noise softened by an anisotropic Gaussian, separably, in the wrap mode
    a panorama needs at its 360-degree join."""
    from scipy.ndimage import gaussian_filter
    return gaussian_filter(noise.astype(np.float32), (sigmas[0], sigmas[1]), mode='wrap')


def city_skyline(panorama, spec, seed=0):
    """-> the panorama with a layered, tileable neon city in front of the horizon.

    The skyline is drawn rather than generated. A generated one lands wherever the
    composition wants, and the cube reprojection only keeps the band around
    elevation 0, so most of a diffusion image is thrown away and the surviving
    band is usually empty sky. Drawing it fixes three things at once: the horizon
    sits exactly where `cube_face` puts elevation 0, the join tiles by
    construction, and the window grid stays crisp at the 1:1 rate a 1024 face
    samples a 4096-wide panorama at.

    Layers run far to near. Each one is veiled by an atmospheric wash, which is
    what makes a distant city read as distance instead of as a darker stripe.
    """
    from scipy.ndimage import gaussian_filter
    rng = np.random.default_rng(seed)
    height, width = panorama.shape[:2]
    out = panorama.astype(np.float32)
    horizon = int(spec.get('horizon', 0.5) * height)
    bloom = np.zeros((height, width), np.float32)

    def paint(x0, x1, y0, y1, colour, alpha=1.0):
        """Paint one rectangle, wrapping in x so the 360-degree join stays closed."""
        x0, x1 = int(x0), int(x1)
        if x1 - x0 >= width:
            x0, x1 = 0, width
        top, bottom = max(0, int(y0)), min(height, int(y1))
        if bottom <= top:
            return

        def blend(left, right):
            if right <= left:
                return
            region = out[top:bottom, left:right]
            out[top:bottom, left:right] = region * (1.0 - alpha) + colour * alpha

        left, right = x0 % width, x1 % width
        if left < right:
            blend(left, right)
        else:
            blend(left, width)
            blend(0, right)

    # Ground: the street canyon below the horizon, dark with a few far lights.
    ground = np.array(spec['ground'], np.float32) * 255.0
    rows = np.arange(horizon, height)[:, None, None]
    fade = np.clip((rows - horizon) / float(max(1, height - horizon)), 0.0, 1.0)
    out[horizon:] = out[horizon:] * (1.0 - fade * 0.85) + ground * fade * 0.85
    specks = rng.random((height, width)) < float(spec.get('ground_lights', 0.00012))
    out[specks] = np.array(spec['near_lights'], np.float32)[None, :] * 255.0 * 0.7

    layers = spec['layers']
    for index, layer in enumerate(layers):
        depth = index / float(max(1, len(layers) - 1))               # 0 farthest
        body = np.array(spec['far_body'], np.float32) * (1.0 - depth) + \
            np.array(spec['near_body'], np.float32) * depth
        lights = np.array(spec['far_lights'], np.float32) * (1.0 - depth) + \
            np.array(spec['near_lights'], np.float32) * depth
        body, lights = body * 255.0, lights * 255.0
        sink = int(depth * layer.get('sink', 0.0) * height)
        base = horizon + sink
        window_x, window_y = layer['window']
        lit = float(layer['lit'])
        cursor, step = 0, int(window_x * 2)
        while cursor < width + width // 16:              # one full turn, plus the wrap
            x = cursor
            tower = int(rng.integers(layer['width'][0] * width, layer['width'][1] * width))
            tall = int(rng.integers(layer['height'][0] * height, layer['height'][1] * height))
            cursor += tower + step
            paint(x, x + tower, base - tall, base, body)
            if depth > 0.5:                       # the nearest towers darken toward their base
                fade = np.linspace(1.0, 1.0 - 0.35 * depth, max(1, tall))[:, None, None]
                piece = out[max(0, base - tall):base, :]
                out[max(0, base - tall):base, :] = piece * fade[:base - max(0, base - tall)]
            if rng.random() < 0.25:                                   # a mast light
                paint(x + tower // 2, x + tower // 2 + 2, base - tall - 6, base - tall, body)
                bloom[base - tall - 6:base - tall, (x + tower // 2) % width] += 1.0
            for row in range(base - tall + 3, base - 2, int(window_y)):
                for column in range(x + 2, x + tower - 2, int(window_x)):
                    if rng.random() > lit:
                        continue
                    tint = lights * float(rng.uniform(0.55, 1.0))
                    if rng.random() < float(layer.get('accent', 0.02)):
                        tint = np.array(spec['neon'][int(rng.integers(0, len(spec['neon'])))],
                                        np.float32) * 255.0
                    paint(column, column + max(1, int(window_x * 0.45)),
                          row, row + max(1, int(window_y * 0.5)), tint)
        veil = float(spec['haze']) * (1.0 - depth)
        if veil > 0.0:
            haze = np.array(spec['haze_tint'], np.float32) * 255.0
            band = np.exp(-((np.arange(height) - horizon) / (0.10 * height)) ** 2)
            band[horizon:] *= 0.25
            out[:] = out * (1.0 - (band * veil)[..., None, None]) + haze * (band * veil)[..., None, None]

    for _ in range(int(spec.get('spires', 0))):               # a few landmarks to break the roofline
        x = int(rng.integers(0, width))
        tower = int(rng.integers(spec['spire_width'][0] * width, spec['spire_width'][1] * width))
        tall = int(rng.integers(spec['spire_height'][0] * height, spec['spire_height'][1] * height))
        body = np.array(spec['near_body'], np.float32) * 255.0 * 1.35
        paint(x, x + tower, horizon - tall, horizon, body)
        paint(x + tower // 2 - 1, x + tower // 2 + 1, horizon - tall - 40, horizon - tall, body)
        bloom[horizon - tall - 42:horizon - tall - 38, (x + tower // 2) % width] += 6.0
        for row in range(horizon - tall + 6, horizon - 8, 10):
            for column in range(x + 3, x + tower - 3, 13):
                if rng.random() < 0.55:
                    paint(column, column + 5, row, row + 5,
                          np.array(spec['near_lights'], np.float32) * 255.0 * rng.uniform(0.6, 1.0))

    # Stars belong above the city glow, and they are the only thing in a sky that
    # should be a hard single pixel: the supersampled reprojection softens them.
    for _ in range(int(spec.get('stars', 0))):
        row = int(rng.integers(0, int(horizon * spec.get('star_band', 0.92))))
        column = int(rng.integers(0, width))
        brightness = float(rng.uniform(0.15, 0.85)) * (1.0 - row / float(horizon))
        out[row:row + 1, column:column + 1] += np.array((0.85, 0.88, 1.0), np.float32) * 255.0 * brightness
        bloom[row:row + 1, column:column + 1] += brightness * 0.5

    bloom = gaussian_filter(bloom, sigma=float(spec.get('bloom_sigma', 6.0)), mode='wrap')
    out += bloom[..., None] * np.array(spec['near_lights'], np.float32)[None, None, :] * 255.0 \
        * float(spec.get('bloom_gain', 0.55))
    return out.clip(0, 255).astype(np.uint8)


def wrap_panorama(image, band=96, sigma=26.0):
    """-> the panorama with its 360-degree join softened in the same way a material
    seam is: roll half, soften the centre, roll back."""
    from scipy.ndimage import gaussian_filter
    width = image.shape[1]
    rolled = np.roll(image, width // 2, axis=1)
    window = np.zeros((image.shape[0], width), np.float32)
    window[:, width // 2 - band // 2:width // 2 + band // 2] = 1.0
    window = gaussian_filter(window, sigma, mode='constant')
    smoothed = gaussian_filter(rolled.astype(np.float32), sigma, mode='wrap')
    return (rolled + window[..., None] * (smoothed - rolled)).clip(0, 255).astype(np.uint8)


def pole_gradients(panorama, sky_rows, ground_rows):
    """-> the panorama with its poles replaced by smooth gradients, because a cube's
    `up` and `dn` faces magnify whatever the last rows hold and a hallucinated
    rooftop at the zenith reads as a smudge."""
    height, width = panorama.shape[:2]
    out = panorama.astype(np.float32)
    # The weights ramp one row at a time and every column together, so they need
    # the width and channel axes as singletons to broadcast against a (h, w, 3).
    sky_top = np.linspace(0.35, 1.0, sky_rows)[:, None, None]
    ceiling = out[:1].mean(axis=1, keepdims=True) * 0.55
    floor = out[-1:].mean(axis=1, keepdims=True) * 0.75
    out[:sky_rows] = ceiling * (1.0 - sky_top) + out[:sky_rows] * sky_top
    if ground_rows:
        ramp = np.linspace(1.0, 0.25, ground_rows)[:, None, None]
        out[height - ground_rows:] = out[height - ground_rows:] * ramp + floor * (1.0 - ramp)
    return out.clip(0, 255).astype(np.uint8)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--recipes', type=Path, required=True, help='map textures.py holding TEXTURES/SKY')
    parser.add_argument('--out', type=Path, required=True, help='image root the map build reads')
    parser.add_argument('--dir', default=None, help='shader directory below --out (default: recipes dir name)')
    parser.add_argument('--models', type=Path, default=Path('~/dk_models/models.json').expanduser())
    parser.add_argument('--only', default=None, help='comma list of recipe names')
    parser.add_argument('--sky', action='store_true', help='generate the env/ cube as well')
    parser.add_argument('--force', action='store_true', help='regenerate images that already exist')
    parser.add_argument('--steps', type=int, default=None)
    parser.add_argument('--skip-sky-detail', action='store_true')
    parser.add_argument('--save-panorama', action='store_true',
                        help='keep the 2:1 panorama beside the cube faces')
    parser.add_argument('--dry-run', action='store_true', help='derive every map from noise, no GPU')
    arguments = parser.parse_args()

    spec = importlib.util.spec_from_file_location('dk3_map_textures', arguments.recipes)
    recipes = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(recipes)
    directory = arguments.dir or arguments.recipes.parent.name.lower()
    root = arguments.out / directory
    root.mkdir(parents=True, exist_ok=True)
    manifest_path = arguments.out / 'neural-textures.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.is_file() else dict(images={})
    manifest.setdefault('provenance', getattr(recipes, 'LICENCES', {}))
    wanted = [name for name in sorted(recipes.TEXTURES)
              if not arguments.only or name in arguments.only.split(',')]
    studio = None if arguments.dry_run else Studio(json.loads(arguments.models.read_text()))
    started = time.time()
    for name in wanted:
        recipe = recipes.TEXTURES[name]
        size = int(recipe.get('size', 512))
        targets = {'': root / ('%s.tga' % name)}
        if recipe.get('normal'):
            targets['_n'] = root / ('%s_n.tga' % name)
        if recipe.get('spec'):
            targets['_s'] = root / ('%s_s.tga' % name)
        if recipe.get('glow'):
            targets['_g'] = root / ('%s_g.tga' % name)
        if not arguments.force and all(path.is_file() for suffix, path in targets.items()):
            print('neural-textures: %s exists' % name)
            continue
        control_spec = dict(recipe.get('control', {}))
        seed = stable_seed(name)
        height = height_field(control_spec.get('kind', 'grit'), 1024, control_spec, seed)
        control = shaded(height, 1.0)
        if studio is None:
            albedo = (np.random.default_rng(seed).integers(0, 256, (1024, 1024, 3))).astype(np.uint8)
        else:
            albedo = studio.render(recipe['prompt'], recipes.NEGATIVE, control, 1024,
                                   steps=arguments.steps or recipe.get('steps', 28),
                                   guidance=recipe.get('guidance', 6.5),
                                   scale=recipe.get('control_scale', 0.62), seed=seed)
        albedo = seamless(albedo)
        albedo = resample(albedo, size)
        # The height is carried at the stored texel size, so its derivatives match
        # the texels a shader will actually sample: a 512 normal map cannot and must
        # not show the bumps of a 1024 field.
        height = resample((height * 255.0).astype(np.uint8), size).astype(np.float32) / 255.0
        images = {'': albedo}
        if recipe.get('normal'):
            images['_n'] = normal_map(height, float(recipe['normal']),
                                      recipe.get('normal_vertical', 'down'))
        if recipe.get('spec'):
            images['_s'] = resample(specular_map(albedo, recipe['spec']), size)
        if recipe.get('glow'):
            images['_g'] = resample(glow_map(albedo, recipe['glow']), size)
        if recipe.get('alpha'):
            base = images['']
            images[''] = np.concatenate([base, alpha_channel(base.shape[:2], recipe['alpha'], height,
                                                             seed)[..., None]], axis=2)
        for suffix, image in images.items():
            import dkimg
            path = targets[suffix]
            path.parent.mkdir(parents=True, exist_ok=True)
            dkimg.write_tga(path, np.ascontiguousarray(image))
        record = dict(prompt=recipe['prompt'], control=control_spec, seed=seed, size=size,
                      steps=arguments.steps or recipe.get('steps', 28),
                      control_scale=recipe.get('control_scale', 0.62),
                      maps=sorted(suffix or 'diffuse' for suffix in images),
                      sha256={suffix or 'diffuse': hashlib.sha256(image.tobytes()).hexdigest()[:16]
                              for suffix, image in images.items()})
        manifest['images']['%s/%s' % (directory, name)] = record
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
        print('neural-textures: %-16s %s (%.0f s, %.1f min total)'
              % (name, ' '.join(sorted(targets)), time.time() - started,
                 (time.time() - started) / 60.0), flush=True)

    if arguments.sky:
        import dkimg
        sky = recipes.SKY
        env = arguments.out / 'env'
        env.mkdir(parents=True, exist_ok=True)
        pan = sky['panorama']
        size = int(sky.get('size', 1024))
        work = tuple(int(value) for value in pan.get('work', (0, 0)))
        if not all(work):
            raise ValueError('the sky panorama needs a `work` size, the 2:1 pixel size '
                             'the cube faces are reprojected out of')
        if studio is None:
            panorama = sky_gradient(work[0], work[1], seed=pan['seed'])
        else:
            generated = tuple(pan.get('generate', (work[0] // 3, work[1] // 3)))
            clouds = studio.render(pan['prompt'], pan['negative'], None,
                                   generated, steps=pan['steps'],
                                   guidance=pan['guidance'], seed=pan['seed'])
            # Only the sky above the horizon comes from the model: SDXL composes
            # best near its trained buckets, and the 7:4 pass is stretched to 2:1.
            panorama = resample_wide(clouds, work[0], work[1])
        panorama = wrap_panorama(panorama)
        panorama = city_skyline(panorama, sky['city'], pan['seed'])
        horizon = int(panorama.shape[0] * float(sky['horizon']['band']))
        panorama = pole_gradients(panorama, horizon * 3, horizon * 4)
        if arguments.save_panorama:
            import dkimg
            dkimg.write_tga(env / ('%s_panorama.tga' % directory), np.ascontiguousarray(panorama))
        faces = {}
        for side in CUBE_SIDES:
            # A 1024 face samples 1024 columns of a 4096-wide panorama, so the face
            # is taken at twice its final size and averaged down: window lights
            # survive that, and they do not survive a bilinear pick.
            base = resample(panorama_face(panorama, side, size * 2), size)
            if studio is not None and side in ('rt', 'bk', 'lf', 'ft') and not arguments.skip_sky_detail \
                    and sky.get('detail'):
                detail = sky['detail']
                base = studio.render(pan['prompt'] + ', distant skyline, atmospheric haze',
                                     pan['negative'], base, size, steps=detail['steps'],
                                     guidance=pan['guidance'], scale=detail['control_scale'],
                                     seed=stable_seed('sky_' + side, pan['seed']), end=0.55)
            base = crossfade_edges(base, faces, 12)
            faces[side] = base
        for side in CUBE_SIDES:
            dkimg.write_tga(env / ('japandm_%s.tga' % side), np.ascontiguousarray(faces[side]))
        manifest['sky'] = dict(panorama=pan['prompt'], seed=pan['seed'], size=size,
                               sides=list(CUBE_SIDES),
                               sha256={side: hashlib.sha256(faces[side].tobytes()).hexdigest()[:16]
                                       for side in CUBE_SIDES})
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
        print('neural-textures: sky faces written for %s (%.1f min total)'
              % ('japandm', (time.time() - started) / 60.0), flush=True)
    return 0


def resample_wide(image, width, height):
    """-> the square generation output stretched to the panorama ratio."""
    from scipy.ndimage import zoom
    return np.clip(zoom(image.astype(np.float32), (height / image.shape[0], width / image.shape[1], 1.0),
                        order=1), 0, 255).astype(np.uint8)


def crossfade_edges(face, done, band):
    """-> the face with its vertical joins softened against the faces already made,
    so the four sides of the cube agree better than independent passes would."""
    from scipy.ndimage import gaussian_filter
    width = face.shape[1]
    out = face.astype(np.float32)
    ramp = np.linspace(0.0, 1.0, band)[None, :, None]
    for neighbour, edge in ((done.get('lf'), 'left'), (done.get('bk'), 'right')):
        if neighbour is None:
            continue
        strip = neighbour[:, -band:, :] if edge == 'left' else neighbour[:, :band, :]
        target = out[:, :band, :] if edge == 'left' else out[:, width - band:, :]
        blended = target * (1.0 - ramp) + strip * ramp
        if edge == 'left':
            out[:, :band, :] = blended
        else:
            out[:, width - band:, :] = blended
    return out.clip(0, 255).astype(np.uint8)


if __name__ == '__main__':
    raise SystemExit(main())
