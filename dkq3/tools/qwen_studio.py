# SPDX-License-Identifier: GPL-2.0-or-later
"""Diffusion plates for japanDM, rendered locally with Qwen-Image-2.1.

Why this exists next to `craft_textures.py`
------------------------------------------
The procedural painters own structure, scale and albedo level: a diffusion model
cannot be told "mean luminance 0.115" and does not tile.  What a model is good at
is the part no procedural recipe can invent -- the *content* of a light box: a
composition of shapes, blocks of signage, a colour story, the way an actual
advertisement is laid out.  So the split is:

  * `craft_textures.py` draws every structural material and the sky;
  * this module renders **plates** -- one PNG per material in a plate directory;
  * `craft_textures.py --plate-dir` multiplies a plate's *relative* luminance
    microstructure into the drawn albedo (`borrow_detail`), which keeps the
    model's detail and throws away its exposure and white balance, so the declared
    albedo target still decides how bright the surface is;
  * for a light box, where the albedo *is* the content, the recipe may instead ask
    for the plate outright (`plate_use='content'`).

Plates are mirror-folded into a tileable mosaic before use, because a diffusion
sample is not seamless and a visible cut line at every 128 world units would be a
worse artefact than the flatness it replaces.

Transport
---------
ComfyUI is the only runtime that can load this model as shipped: the weight set is
a single-file GGUF (Q8_0) with a separate Qwen3-VL-8B int8 text encoder, and
diffusers has no pipeline for the 2.1 architecture.  We therefore post a graph to
ComfyUI's `/prompt` HTTP endpoint and poll `/history`, which keeps this repository
free of a ComfyUI dependency: the server is an external tool the operator starts,
and `--dry-run` shows the graph without one.

Licence note: the weight set used here is the owner's personal copy of
`abenzerps/Qwen-Image-2.1-Uncensored-GGUF` (Apache-2.0 base weights, Apache-2.0
code; the uncensored LoRA is a third-party fine-tune the owner has accepted for
personal use).  No model weight is shipped with the map -- only rendered images.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import socket
import time
import urllib.error
import urllib.parse
import urllib.request

import numpy as np
from PIL import Image

DEFAULT_SERVER = '127.0.0.1:8189'
DIFFUSION = 'qwen-image-2.1-UC-Q8_0.gguf'
TEXT_ENCODER = 'qwen3vl_8b_int8_convrot.safetensors'
VAE = 'qwen_image_2.1_vae_bf16.safetensors'

#: What a plate must not bring with it -- folded into the positive prompt, because
#: at cfg 1 a negative conditioning is never evaluated (see `graph`).  A baked
#: light direction on a plate becomes a fake key light once it is tiled across a
#: wall, and a vignette becomes a grid of dark rectangles.
AVOID = ('No directional shadow, no cast shadow, no strong key light, no highlight '
         'bloom, no depth of field, no bokeh, no motion blur, no vignette, no frame, '
         'no border, no seam, no readable text or lettering, no human face, no '
         'watermark, no logo.')

#: Prompts per material.  Each says what the plate must contribute and, in the
#: same sentence, what it must not decide -- the albedo level is `grade()`'s job.
PLATES = {
    'asphalt': dict(
        prompt='close-up photograph of dark wet rain asphalt road surface, fine mineral '
               'aggregate and tar, faint faded white painted road marking worn away, '
               'long dark tyre-wear band, thin hairline cracks, rain film with subtle '
               'reflection streaks, top-down orthographic view, flat even overcast '
               'ambient light, seamless material study, high detail micro surface',
        size=(1024, 1024), steps=28, cfg=1.0, grain=0.55),
    'concrete_panel': dict(
        prompt='close-up photograph of dark grey board-formed concrete wall, form-tie '
               'holes and honeycombing, long soft rain streaks, wide dark grime '
               'gradient, rust bleed from embedded steel, matte chalky surface, '
               'top-down orthographic view, flat even overcast ambient light, seamless '
               'material study, high detail micro surface',
        size=(1024, 1024), steps=28, cfg=1.0, grain=0.50),
    'plaza_stone': dict(
        prompt='close-up photograph of large dark granite paving slabs wet from rain, '
               'mineral flecks, narrow dark grout line, thin film of standing water, '
               'faint worn footpath polish, top-down orthographic view, flat even '
               'overcast ambient light, seamless material study, high detail stone grain',
        size=(1024, 1024), steps=28, cfg=1.0, grain=0.45),
    'roof_gravel': dict(
        prompt='close-up photograph of flat rooftop ballast, coarse dark angular stones '
               'set in dark waterproofing membrane, dried rain stains, pooled dirt, '
               'top-down orthographic view, flat even overcast ambient light, seamless '
               'material study, high detail micro surface',
        size=(1024, 1024), steps=28, cfg=1.0, grain=0.55),
    'metal_deck': dict(
        prompt='close-up photograph of worn industrial steel floor plate, scratched '
               'blue-grey safety paint chipped to bright metal, diamond anti-slip '
               'embossed ribs, bolt heads, oily film in the scratches, top-down '
               'orthographic view, flat even ambient light, seamless material study, '
               'high detail micro surface',
        size=(1024, 1024), steps=28, cfg=1.0, grain=0.45),
    'crate': dict(
        prompt='close-up photograph of weathered plywood shipping crate panel, splintered '
               'veneer edge, stencil-painted frame lines, stencilled cargo handling glyphs '
               'and arrows, dark green lacquer bars, salt-blistered surface, flat even '
               'ambient light, orthographic, seamless material study, high detail',
        size=(1024, 1024), steps=28, cfg=1.0, grain=0.50),
    'ad_board': dict(
        use='content',
        prompt='a future Japanese neon-district billboard light box advertisement, bold '
              'abstract graphic design, a stylised angular product silhouette in '
              'cobalt and warm amber, big flat colour fields, diagonal split '
              'composition, katakana signage blocks, thin luminous rules and a barcode '
              'stripe, printed vector poster lit from behind, high contrast, crisp '
              'edges, straight-on orthographic full-frame poster, no camera angle',
        size=(1024, 1024), steps=32, cfg=1.0),
    # Three materials had no plate and were drawn entirely from the painter's own
    # noise.  That is what made `grate` read as streaked grey with no slots,
    # `plant` as dark blobs with no leaves, and `cloth` a flat banding: a painter
    # can put a surface's relief and grime into a tile, but it cannot invent the
    # thing's *identity* out of value noise.
    'grate': dict(
        prompt='close-up photograph of heavy industrial steel floor grating seen straight '
               'down, parallel load-bearing bars with narrow dark open slots between them, '
               'cross bars at a regular pitch, scuffed grey galvanised surface with oily '
               'dark residue collected in the slots and worn bright metal on the bar '
               'crowns, top-down orthographic view, flat even overcast ambient light, '
               'seamless material study, high detail micro surface',
        size=(1024, 1024), steps=28, cfg=1.0, grain=0.50),
    'plant': dict(
        prompt='close-up photograph of dense dark green ground cover, moss and small wet '
               'leaves growing over damp bark mulch, tiny varied leaf shapes at several '
               'scales, deep shadow inside the foliage, faint dew sheen, top-down '
               'orthographic view, flat even overcast ambient light, seamless material '
               'study, high detail micro surface',
        size=(1024, 1024), steps=28, cfg=1.0, grain=0.50),
    'glass': dict(
        prompt='close-up photograph of dark smoked architectural glass at dusk, near-black '
               'blue-grey glass with very faint mottled reflection of a city, even tone '
               'with no gradient, fine dust and dried rain specks, no mullion, no frame, '
               'top-down orthographic view, flat even ambient light, seamless material '
               'study, high detail micro surface',
        size=(1024, 1024), steps=28, cfg=1.0, grain=0.40),
    'cloth': dict(
        prompt='close-up photograph of heavy indigo and crimson striped market awning '
               'canvas, visible woven warp and weft, sun-faded seams, a stitched '
               'repair patch, waxed water-beaded surface, flat even ambient light, '
               'orthographic top-down, seamless material study, high detail thread grain',
        size=(1024, 1024), steps=28, cfg=1.0, grain=0.45),
}


# --------------------------------------------------------------------------- #
# ComfyUI transport
# --------------------------------------------------------------------------- #
def _rpc(server, path, payload=None, timeout=30):
    """-> the decoded JSON body of one ComfyUI HTTP call."""
    request = urllib.request.Request(
        'http://%s%s' % (server, path),
        data=None if payload is None else json.dumps(payload).encode('utf-8'),
        headers={'content-type': 'application/json'})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode('utf-8'))


def graph(prompt, negative, width, height, steps, cfg, seed, prefix):
    """-> the ComfyUI prompt-graph dict for one text-to-image render.

    Two things here are not free choices, and both were learned the hard way:

    * **cfg = 1.0.** Qwen-Image-2.1 is a guidance-distilled flow model, and the
      official ComfyUI template for it samples at CFG 1 with `euler`/`simple`.
      Driving a distilled model at CFG 4.5 does not make it follow the prompt
      harder, it multiplies a difference the network was never trained to
      extrapolate: the first attempt at 4.5 came back as a flat saturated-blue
      field with a lattice of decoder artefacts (mean RGB 0.18, 0.18, 0.96).
      Adherence therefore lives in the wording of the prompt, not in a dial;
    * **`EmptyLatentImage`, not the node's own latent.** ComfyUI 0.38 carries
      latents in a generic 4-channel form and converts per model, which is what
      lets a plate be any size; the `latent` output of the conditioning node is
      only square and only exists to keep an edit's geometry.

    `QwenImage21Cache` is the reference-image KV cache; with no reference images
    it costs nothing, and leaving it in keeps this graph equal to the official one
    if a plate ever needs a reference.
    """
    return {
        '1': dict(class_type='UnetLoaderGGUF', inputs=dict(unet_name=DIFFUSION),
                  _meta=dict(title='Qwen-Image-2.1 uncensored Q8_0')),
        '2': dict(class_type='CLIPLoader', inputs=dict(clip_name=TEXT_ENCODER, type='qwen_image'),
                  _meta=dict(title='Qwen3-VL-8B int8 text encoder')),
        '3': dict(class_type='VAELoader', inputs=dict(vae_name=VAE)),
        '4': dict(class_type='TextEncodeQwenImage21',
                  inputs=dict(clip=['2', 0], prompt=prompt, negative_prompt=negative,
                              resolution=min(width, height), images=[]),
                  _meta=dict(title='prompt / negative')),
        '8': dict(class_type='EmptyLatentImage', inputs=dict(width=width, height=height,
                                                             batch_size=1)),
        '9': dict(class_type='QwenImage21Cache', inputs=dict(model=['1', 0], device='auto',
                                                             dtype='default')),
        '5': dict(class_type='KSampler',
                  inputs=dict(model=['9', 0], seed=seed, steps=steps, cfg=cfg,
                              sampler_name='euler', scheduler='simple', denoise=1.0,
                              positive=['4', 0], negative=['4', 1], latent_image=['8', 0]),
                  _meta=dict(title='flow-matching sampler, cfg 1')),
        '6': dict(class_type='VAEDecode', inputs=dict(samples=['5', 0], vae=['3', 0])),
        '7': dict(class_type='SaveImage', inputs=dict(images=['6', 0], filename_prefix=prefix)),
    }


def _wait(server, prompt_id, deadline):
    """-> the SaveImage outputs once the server reports the prompt done."""
    while time.time() < deadline:
        history = _rpc(server, '/history/%s' % prompt_id)
        entry = history.get(prompt_id)
        if entry:
            status = entry.get('status', {})
            if status.get('completed') or status.get('status_str') == 'error':
                if status.get('status_str') == 'error':
                    raise RuntimeError('comfyui error: %s' % json.dumps(status)[:1200])
                return entry['outputs']
        time.sleep(2.0)
    raise TimeoutError('prompt %s still running' % prompt_id)


def _fetch(server, node_outputs, out, width, height):
    """-> the saved image, pulled back over `/view` and resized to the plate size."""
    for node in node_outputs.values():
        for image in node.get('images', []):
            # ComfyUI 0.38 wants the subfolder as its own parameter: a joined
            # `filename=jdm/x.png` is not a path it will serve.
            query = '/view?' + urllib.parse.urlencode(
                dict(type='output', filename=image['filename'], subfolder=image['subfolder']))
            request = urllib.request.Request('http://%s%s' % (server, query))
            with urllib.request.urlopen(request, timeout=120) as response:
                body = response.read()
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(body)
            plate = Image.open(out).convert('RGB')
            if plate.size != (width, height):
                plate = plate.resize((width, height), Image.LANCZOS)
                plate.save(out)
            return out
    raise RuntimeError('history carried no saved image')


def render(server, name, spec, out, seed, deadline_seconds=1800):
    """-> the written plate path, or None when the material needs no model."""
    width, height = spec['size']
    # With cfg 1 the negative branch is never evaluated, so it is left empty
    # rather than loaded with a list of things to avoid: encoding it costs the
    # 8.9 GB text encoder for a conditioning vector that is thrown away.
    negative = spec.get('negative', '')
    prompt = '%s %s' % (spec['prompt'], spec.get('avoid', AVOID))
    payload = dict(prompt=graph(prompt, negative, width, height,
                                int(spec.get('steps', 28)), float(spec.get('cfg', 1.0)),
                                seed, 'jdm/%s' % name),
                   client_id='qwen-studio')
    answer = _rpc(server, '/prompt', payload)
    prompt_id = answer['prompt_id']
    outputs = _wait(server, prompt_id, time.time() + deadline_seconds)
    return _fetch(server, outputs, out, width, height)


# --------------------------------------------------------------------------- #
# tiling
# --------------------------------------------------------------------------- #
def tileable(plate):
    """-> a wrap-seamless mosaic of one plate, made by mirroring it into itself.

    A diffusion sample has no reason to tile.  Quartering the plate into a 2x2
    mirror repeats the same four edges against themselves, so the value is
    continuous across every wrap; the derivative is not, but grain does not need
    to be C1-continuous to read as a photograph.
    """
    return np.concatenate([np.concatenate([plate, plate[:, ::-1]], axis=1),
                           np.concatenate([plate[::-1], plate[::-1, ::-1]], axis=1)], axis=0)


#: The only crop offsets of a 2x2 mirror-fold that wrap seamlessly.
#:
#: `tileable` puts mirror axes between columns (size-1, size) and (2*size-1, 0).
#: A `size`-wide crop is wrap-continuous only if it is symmetric about one of
#: those axes, which means offset size//2 or size//2 + size -- and nothing else.
#: Cropping at an arbitrary offset is the natural thing to write and it quietly
#: destroys the seam the whole fold exists to create: the tile's first and last
#: column come from unrelated parts of the sample, and the map then shows a grid
#: of hard lines once it repeats across a wall.
SEAM_OFFSETS = (0, 1)


def crop_seamless(mosaic, size, offsets=(0, 0)):
    """-> a `size`-square crop of a mirror-folded `size`-sample, wrap-continuous.

    `offsets` picks a mirror axis per axis (see SEAM_OFFSETS); the crop wraps
    around the mosaic, so both axes are always in range.
    """
    height, width = mosaic.shape[:2]
    half = size // 2
    def axis(index, base):
        return np.arange(base + half, base + half + size) % index
    rows = axis(height, SEAM_OFFSETS[offsets[0]] * size)
    cols = axis(width, SEAM_OFFSETS[offsets[1]] * size)
    return np.ascontiguousarray(mosaic[np.ix_(rows, cols)])


def seam_metric(image):
    """-> wrap discontinuity over interior gradient; below ~1.0 reads seam-free.

    Deliberately the same formula as craft_textures.seam_metric, so a plate and
    the painted texture that consumes it are judged with one number.
    """
    sample = image.astype(np.float32)
    edge = np.abs(sample[0] - sample[-1]).mean() + np.abs(sample[:, 0] - sample[:, -1]).mean()
    interior = np.abs(np.diff(sample, axis=0)).mean() + np.abs(np.diff(sample, axis=1)).mean()
    return float(edge / max(float(interior), 1e-6))


def finish_plate(raw_path, out, name, spec, seed):
    """-> (tile path, seam metric) turning one rendered sample into a used plate.

    Runs offline on the saved PNG: a render costs ~100 s of GPU and a fold costs
    no time at all, so the fold has to be re-doable without the GPU -- which is
    also the only way to recover tiles after a crash took the working directory.
    """
    out.mkdir(parents=True, exist_ok=True)
    tile_path = out / ('%s.png' % name)
    if spec.get('use') == 'content':
        # A light box's face *is* its artwork: tiling a poster across itself turns
        # the lettering into a grid.  Ship the sample untouched.
        tile_path.write_bytes(Path(raw_path).read_bytes())
        return tile_path, None
    # ComfyUI's SaveImage writes RGBA.  Carrying that alpha through the fold makes
    # every plate a 4-channel file, which the build survives only because it
    # happens to convert; anything else that reads a plate -- a seam check, a
    # future importer -- meets a shape it did not ask for.  Plates are colour.
    plate = np.asarray(Image.open(raw_path).convert('RGB'), np.float32) / 255.0
    mosaic = tileable(plate)
    size = min(spec['size'])
    rng = np.random.default_rng(seed)
    tile = crop_seamless(mosaic, size, offsets=(int(rng.integers(0, 2)),
                                                int(rng.integers(0, 2))))
    Image.fromarray((tile * 255.0).round().astype(np.uint8)).save(tile_path)
    return tile_path, seam_metric(tile * 255.0)


#: Channel balance a real material sample cannot violate.
#:
#: Rendered at a conditioning scale this model was not distilled for, a sample
#: collapses into one saturated channel -- the first cloth plate measured mean RGB
#: 0.21/0.18/0.92, a blue field with a magenta bar, which folded into a tile that
#: then shipped as "awning canvas".  Picking `sorted(glob())[0]` handed that
#: artifact to the build without a word.  Genuinely tinted materials stay well
#: inside this bound (the blue diamond plate sits at 1.5), so the check reads the
#: failure rather than the palette.
MAX_CHANNEL_BALANCE = 2.5


def sample_is_broken(path):
    """-> True when one RGB channel dominates the way a mis-sampled latent does."""
    sample = np.asarray(Image.open(path).convert('RGB'), np.float32).reshape(-1, 3)
    means = sample.mean(axis=0)
    lowest = float(min(means))
    return bool(lowest <= 1e-3 or float(max(means)) / lowest > MAX_CHANNEL_BALANCE)


def raw_for(out, name, reject=None):
    """-> the saved sample for one material, whatever naming ComfyUI gave it.

    Candidates that fail `sample_is_broken` are reported to `reject` and skipped;
    if nothing passes, the first candidate is still returned so the failure stays
    visible in the tile instead of becoming a silent hole in the build.
    """
    candidates = []
    direct = out / ('raw-%s.png' % name)
    if direct.is_file():
        candidates.append(direct)
    # A render whose node prefix was the bare material name comes back as
    # `<name>_00001_.png`.
    candidates += [found for found in sorted(out.glob('%s_*.png' % name)) if found.is_file()]
    if not candidates:
        return None
    for candidate in candidates:
        if not sample_is_broken(candidate):
            return candidate
        if reject is not None:
            reject.append(candidate)
    print('plate: %-16s every sample failed the channel-balance check, using %s anyway'
          % (name, candidates[0].name), flush=True)
    return candidates[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--server', default=DEFAULT_SERVER)
    parser.add_argument('--out', type=Path, required=True, help='plate directory craft_textures reads')
    parser.add_argument('--only', default=None, help='comma list of material plates')
    parser.add_argument('--seed', type=int, default=4411)
    parser.add_argument('--dry-run', action='store_true', help='print the graph, render nothing')
    parser.add_argument('--from-raw', action='store_true',
                        help='skip the GPU: rebuild <material>.png from the raw-*.png '
                             'already in --out (folds and crops only, no render)')
    arguments = parser.parse_args()

    names = [name for name in PLATES if not arguments.only or name in arguments.only.split(',')]
    if arguments.dry_run:
        for name in names:
            spec = PLATES[name]
            print(json.dumps({name: graph('%s %s' % (spec['prompt'], AVOID), '', *spec['size'],
                                          spec.get('steps', 28), spec.get('cfg', 1.0),
                                          arguments.seed, 'jdm/%s' % name)}, indent=2))
        return 0

    if arguments.from_raw:
        rows = []
        for offset, name in enumerate(names):
            spec = PLATES[name]
            skipped = []
            raw_path = raw_for(arguments.out, name, reject=skipped)
            for bad in skipped:
                print('plate: %-16s rejected %s -- one channel dominates, mis-sampled'
                      % (name, bad.name), flush=True)
            if raw_path is None:
                print('plate: %-16s no raw sample in %s -- needs a render' % (name, arguments.out),
                      flush=True)
                continue
            path, seam = finish_plate(raw_path, arguments.out, name, spec,
                                      arguments.seed + offset * 17)
            rows.append((name, seam))
            print('plate: %-16s %-16s %s' % (name, path.name,
                                             'content' if seam is None else 'seam %.3f' % seam),
                  flush=True)
        scored = [seam for _, seam in rows if seam is not None]
        print('plate: %d folded, worst seam %.3f (target < 1.000)'
              % (len(rows), max(scored) if scored else 0.0), flush=True)
        return 0

    host, _, port = arguments.server.partition(':')
    try:
        with socket.create_connection((host, int(port or 8189)), timeout=5):
            pass
    except OSError as error:
        parser.error('ComfyUI is not listening on %s (%s); start it with '
                     './.venv/bin/python main.py --listen 127.0.0.1 --port 8189'
                     % (arguments.server, error))

    for offset, name in enumerate(names):
        spec = PLATES[name]
        started = time.time()
        path = render(arguments.server, name, spec, arguments.out / ('raw-%s.png' % name),
                      arguments.seed + offset * 17)
        print('plate: %-16s rendered %s' % (name, path), flush=True)
        tile_path, seam = finish_plate(path, arguments.out, name, spec,
                                       arguments.seed + offset * 17)
        print('plate: %-16s %s %.0f s -> %s %s'
              % (name, spec['size'], time.time() - started, tile_path.name,
                 '' if seam is None else 'seam %.3f' % seam), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
