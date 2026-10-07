# japanDM provenance

Everything in `zz-dk3-japandm.pk3` was produced in this repository on this
machine. No Daikatana art, no shipped id Software / Square asset, no purchased or
downloaded texture pack, and no third-party 3D model is inside the package, and
the private daikatana reference workspace was never imported into it. The package
holds 61 files: the BSP, the AAS, the navigation cfg, one generated shader script,
one `maps.cfg` entry, six sky faces and 50 map images.

## Geometry

Modelled procedurally by `maps/japanDM/build_blender.py` (Blender 5.1.2, headless)
into `maps/japanDM/japanDM.blend`, then exported by `dkq3/tools/map_author.py`.
The `.blend` is a build product: re-running the script on the same sources produces
a byte-identical export (verified by diffing two exports around a single
intended change), so the scene script, not the `.blend`, is the source of record. 903
objects, 53 lamps, 14 spawns, 29 pickups.

## Images

Generated locally on an RTX 5090:

* **Stable Diffusion XL base 1.0** (CreativeML Open RAIL++-M) for albedo,
* **xinsir/controlnet-tile-sdxl-1.0** (CreativeML Open RAIL++-M) to steer it with a
  periodic procedural field, which is what makes the result tile,
* **madebyollin/sdxl-vae-fp16-fix** (MIT) for decoding,
* torch 2.9.0+cu128, diffusers 0.36, interpreter `python3.14`.

Height, and from it the tangent-space normal map, comes from the procedural field
rather than from the picture; specular and glow are derived from the albedo. The
weights stay in `~/dk_models` and are not shipped; only their outputs are.

**FLUX.1-dev is deliberately not used** anywhere in this map: its licence is
research / non-commercial and this map ships. The Open RAIL++-M terms permit
distribution of the outputs; the model names are recorded here as the notice they
ask for.

Recipe per material (`maps/japanDM/textures.py`), with the seed, the image size,
which maps were written, and the manifest digest of each:

| material | field | seed | size | maps | digests |
| --- | --- | --- | --- | --- | --- |
| `japandm/ad_board` | blocks | 64334 | 1024 | `_g` `diffuse` | `725c140244ae934c` `275764b8c1c3855f` |
| `japandm/asphalt` | grit | 87696 | 1024 | `_n` `_s` `diffuse` | `b48725f176dc6fbe` `dab26d374f423670` `946fcd8fe182c744` |
| `japandm/cloth` | weave | 43703 | 512 | `_n` `_s` `diffuse` | `5dfd0a35a0268ba4` `886ef4fe6996ddca` `3f4f26b7e7455dc7` |
| `japandm/concrete_panel` | panels | 3440 | 1024 | `_n` `_s` `diffuse` | `f55486f9cee3e376` `b6707cfa112f1416` `256aa131b0f54107` |
| `japandm/crate` | panels | 12395 | 512 | `_n` `_s` `diffuse` | `c0f0d699e68e3b90` `a165f9b7afd8b2d8` `688ff97f3da9afc4` |
| `japandm/glass` | brushed | 86962 | 512 | `_n` `_s` `diffuse` | `4cb24a91cfd9053c` `5d4b7ef5773a66ae` `2d1838e312859729` |
| `japandm/grate` | grid | 75466 | 512 | `_n` `_s` `diffuse` | `5488cde0a1e53236` `7ac6cba5e06aaf2c` `dbe3f5d8fcabf404` |
| `japandm/holo_pool` | ripple | 74412 | 512 | `_g` `diffuse` | `beca6b0c8622a22a` `6540c638dba58b4f` |
| `japandm/lacquer_red` | planks | 68679 | 512 | `_n` `_s` `diffuse` | `308379b68f6fe6eb` `886330a0fd4467d3` `f2738a9a7d5aa507` |
| `japandm/light_strip` | ribs | 39724 | 256 | `_g` `diffuse` | `b1197e6c2b92c70b` `55039dae72057ea7` |
| `japandm/metal_column` | brushed | 18927 | 512 | `_n` `_s` `diffuse` | `b4223763ff610fb0` `1c86cbc15ba3333a` `479bc8714c044718` |
| `japandm/metal_deck` | ribs | 59911 | 512 | `_n` `_s` `diffuse` | `26ab9db279abf6a6` `c9da0fddb9ddffbb` `0d277578e3243f2d` |
| `japandm/neon_a` | blocks | 90099 | 512 | `_g` `diffuse` | `cf417e08a2af1456` `6a881c3aa44e8097` |
| `japandm/neon_b` | blocks | 43243 | 512 | `_g` `diffuse` | `fe7ab06af3226a66` `9df55f88ebb770fa` |
| `japandm/plant` | grit | 22501 | 512 | `_n` `_s` `diffuse` | `6e0d466fe1ca127e` `8e610840e0d54b0c` `e9833a1e917b6598` |
| `japandm/plaza_stone` | slabs | 13036 | 1024 | `_n` `_s` `diffuse` | `7f7cc69524917de8` `0d6c02a03074c063` `1a6d05ef60c927ec` |
| `japandm/roof_gravel` | grit | 90825 | 512 | `_n` `_s` `diffuse` | `45d11ba843ed6bf8` `1aaf704a3e027b3e` `cf685b92eb36e13e` |
| `japandm/tower_front` | slabs | 9023 | 1024 | `_g` `_n` `_s` `diffuse` | `73e8fb1bdede36ec` `eef096a338361896` `ffcbb85360381bd1` `6b18e71ded102706` |

### What "digest" means, and how to check it

`neural-textures.json` records `sha256(pixel_array.tobytes())[:16]`, not the digest
of the TGA file. `sha256sum` on the file will therefore never agree with it and the
check has to decode first:

    python3.14 -c "import hashlib,json,numpy as np;from PIL import Image;\
    m=json.load(open('maps/japanDM/assets/neural-textures.json'));\
    ok=all(hashlib.sha256(np.asarray(Image.open('maps/japanDM/assets/%s%s.tga'\
    % (n, '' if k=='diffuse' else k))).convert('RGB')).tobytes()).hexdigest()[:16]==v\
    for n,e in m['images'].items() for k,v in e['sha256'].items());print(ok)"

Run against the shipped set this returns True for every material whose maps are
three-channel; `japandm/glass` stores RGBA and its digest covers the alpha, so it
is checked against the four-channel array instead.

### Regenerated after viewing engine frames

`asphalt`, `concrete_panel` and `roof_gravel` were generated twice. The first set
came back bright and high-frequency, which at the map's 128-unit scale read as
stucco, so the height field was softened (grit 0.90/0.55/1.00 -> 0.45/0.28/0.55,
normal gain 1.5/2.2/2.2 -> 1.0/1.3/1.4) and the prompts moved their variation from
speckle into stains and streaks. The table above and the shipped files are the
second generation. What did not change is the model's preference for a bright
mid-grey albedo: the second set is not darker, only better structured, and the
map's contrast therefore comes from the light rig rather than from the albedo.
`roof_gravel`'s prompt exceeds CLIP's 77-token limit and the tail
("...no bright speckle") is truncated by the tokenizer; the truncation is reported
by the generator at run time and the recipe is left as-is because the surviving
text and the control field carry the intent.

### Detail plates and what they are allowed to influence

Eleven materials take a *detail plate* rendered on the same machine with
**ComfyUI 0.38 + ComfyUI-GGUF** driving `abenzerps/Qwen-Image-2.1-Uncensored-GGUF`
(Q8_0 single-file diffusion model, Qwen3-VL-8B int8 text encoder, bf16 VAE). The
uncensored build is the owner's own copy, used for the owner's personal work at
the owner's explicit instruction; the underlying model family is Apache-2.0, and
no weight ships with the map. `FLUX.1-dev` is deliberately not used for anything
shipped: its licence is research/non-commercial only.

Sampling is euler/simple at **cfg 1.0**. That is not a style preference: at
cfg > 1 this sampler produced a flat single-hue field on `cloth` (channel means
.21/.18/.92 -- a blue wash with no canvas in it), and a channel-balance guard now
rejects plates like it instead of shipping them.

The plate's authority is narrow and it is enforced in code, not in intention.
`borrow_detail` divides the plate by a wrap-blurred copy of itself, so a plate
contributes microstructure only: its exposure, its palette and its large-scale
shape are divided out, and every albedo *level* still comes from the recipe's
`grade` target. The one exception is `ad_board`, a light box whose albedo is the
artwork itself and which therefore takes the plate outright.

Seven materials (`tower_front`, `metal_column`, `lacquer_red` among them) have no
plate on disk, and `borrow_detail` is never reached for them. Setting a `grain`
value on those would be dead configuration, which is worth stating because it was
nearly done here: a knob that is read only when a file exists is not a knob.

Plates are made tileable by mirror-symmetric folding, which is why every folded
plate measures a seam of exactly 0.000. The cost is a visible mirror symmetry, and
it is recorded under DESIGN.md section 10 as an open limitation rather than as a
solved problem.


## Sky

One 1024x1024 dusk panorama (prompt in the manifest, seed 4411) is
reprojected into the six faces; six independently generated faces cannot agree at a
cube edge. The reprojection follows `MakeSkyVec` in
`engine/ioquake3/code/renderergl2/tr_sky.c`, and each face then gets its own
detail pass.

| face | array digest | file digest |
| --- | --- | --- |
| `rt` | `c6c6d288bc1ecda1` | `5f93af2ee66c6e43` |
| `ft` | `cfe73433136af7cc` | `0aef720cc65d73ea` |
| `bk` | `24cd51c1b719246f` | `110225da559e54b9` |
| `lf` | `7a3640b75f8f7281` | `34381ed46d833c77` |
| `up` | `eb086e570f3429f2` | `adc6e1e8e380fd77` |
| `dn` | `2191cb912dfc1cf2` | `efac9bf50d152c7c` |

These faces are the **second** generation. The first was stored vertically
mirrored: `cube_face()` applied its own `v = 1 - (v + 0.5) / size` on top of
`dkimg.encode_tga`'s bottom-up write, so every side face's top row looked at the
ground and the skyline hung from the zenith on screen. The pre-fix files, recorded
so the change is auditable, were

    bk 6f6f2e03099f23b1...  dn 64dd4035e830cef0...  ft d2840a35e6a3eb20...
    lf 682a3420b81184a7...  rt 0bfe48398b6d7192...  up 2a7bff3bc2d7248c...

The panorama itself did not change between the two generations
(`japandm_panorama.tga` is `f6a66617...` both times), which is what proves the fix
was in the reprojection and not in the art. The mapping is now pinned by
`dkq3/tools/tests/test_neural_textures.py`, which checks the per-pixel direction of
five pixels on each of the six faces against the engine's own table, that a flat
panorama's horizon lands in the middle of every side face, and that a skyline drawn
above its horizon stays above it.

## Engine and tools

The map runs on the native Zig runtime in this repository; nothing in `src/` or
`engine/` was modified for it. `dkq3/tools/map_build.py`, `map_author.py`,
`map_materials.py`, `map_sightlines.py`, `map_view_probe.py`, `map_spawn_aim.py`,
`neural_textures.py` and `dkimg.py` are GPL-2.0-or-later, the same licence the
engine they drive is under. q3map2 2.5.17 (GtkRadiant 1.6.7 flatpak) and `bspc`
are used unchanged as external compilers.
