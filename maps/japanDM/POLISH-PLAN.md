# japanDM polish plan — what actually makes it read as a place

Written after the owner ran the map and reported two things: oversized metal, and
"no small details, nothing gives me a sense that it is a real japan bazaar from the
future". Both are true, and the second is not a texture problem. Findings are
measured from the exported `.map` and the installed archive, not from impressions.

## 1. Findings

**1.1 The map is 807 axis-aligned boxes and nothing else.** Classifying all 4876
exported faces by normal gives, for every material, `side/up = 4.00` — the exact
signature of boxes-only geometry (1 top + 1 bottom + 4 sides). There is no cylinder,
no duct, no post, no cable, no frame, no curve, no bevel anywhere in the level. That
single fact is most of the answer to "no small details": the level contains no
*object-scale* forms at all, only architecture carved out of space.

**1.2 Materials are assigned per brush, so every roof shows its underside material.**
Because assignment happens on the object rather than the face, the top, bottom and
sides of a brush all take one material. Measured on downward-facing faces:
`roof_gravel` 38, `crate` 52, `plaza_stone` 30, `metal_deck` 76 — about 200 faces
where the surface a player sees from below is roof ballast or crate ply. The lumpy
dark ceiling in the owner's screenshot is `roof_gravel`, correctly drawn, on a
surface it was never authored for. This is an authoring bug, not a texture bug, and
no amount of new art fixes it.

**1.3 `metal_deck` was displaying a tread far coarser than a tread.** Its own recipe
comment concedes the point ("a real 1-unit lozenge… no 512 texel tile can hold") and
settled on a 21-unit emboss, then put `spec base 0.24 / gain 0.30` on top of it, so
under the market lamps a deliberately exaggerated emboss blows out to brass. Fixed
here: `cells` 6 to 14 (emboss 21 to 9 units, about 0.23 m), `normal` 2.2 to 1.6,
`spec` base 0.24 to 0.12, gain 0.30 to 0.16, extra_gain 0.36 to 0.18. Albedo mean is
unchanged at 0.200, so this is lighting-safe by the argument in DESIGN.md section 10.

**1.4 The violet the screenshot shows is local, not a global wash.** Averaging the 14
view-probe captures gives mean RGB (0.170, 0.157, 0.167) — a red:blue ratio of 1.02,
i.e. neutral. So the strong magenta is coming from particular emitters (the sky ring
low on the horizon, `ad_board`, the neon strips) plus fog, not from `q3map_skyLight`
tinting everything as it once did. Worth treating as emitter placement and fog range,
and worth confirming live before changing the light rig — an earlier build genuinely
did have a violet global cast, so it is reasonable to suspect and it measurably isn't.

**1.5 A prop cannot be an entity here.** The native Zig runtime is the only runtime,
and its entity table has items, weapons and movers — no `misc_model`, no
`misc_gamemodel`, no static render-model spawner. `misc_model` exists only in
`engine/ioquake3/code/game/g_misc.c`, which this build does not use, and the renderer
headers record the upstream intent anyway: "misc_models in maps are turned into
direct geometry by q3map". So **every decoration in this map must be world brushes**.
This is the binding constraint on the TRELLIS request, not a matter of taste.

## 2. Plan, in the order that buys the most per hour

**Step 0 — done.** `map_build.py --stages relight` runs `-light` against the already
vis'd BSP and re-derives package/install. Measured 57 s against 16 min for a full
compile, and it is not trusted: the existing gate still requires `visibility`, so a
relight that dropped the PVS fails. Texture-only iteration is now cheap enough to
actually iterate.

**Step 1 — per-face material assignment (needs one full rebuild).** Assign ceilings,
undersides and floor tops in `build_blender.py` instead of inheriting the object's
material: soffits get `concrete_panel`/`metal_column`, a crate's top gets its lid
face, ground planes keep `plaza_stone`/`asphalt`. This is the single change that
removes the most wrongness per line touched. Any BSP change invalidates vis, so
budget one full `-vis` pass.

**Step 2 — the object-scale pass, in boxes first.** TRELLIS is not what this level
is missing; *form* is. Add the mid-scale kit a market is made of, as authored
geometry: reveals and window frames inset a few units instead of painted flat,
canopy boxes on posts over the stalls, cable runs and conduit along deck edges, AC
condenser blocks on ducts, railing posts and top rails, kerbs and gutter recesses,
sign boxes with real depth instead of flat quads, steps and loading ramps, recessed
floor gratings, bins and shutters. Non-axis-aligned placement and small bevels,
because 1.1 says the level currently has no form a lamp can catch. This is authored
in Blender and is the pass that changes the owner's impression.

**Step 3 — TRELLIS.2 hero props, only after steps 1-2.** With 1.5 in force, a
generated mesh is only usable after it becomes convex brushes: generate, decimate
hard, convex-decompose (voxel/HACD-style) into a handful of brushes, emit into the
scene with a material slot. A lantern, a stall cart, a bundled awning, a scooter.
Two costs were *assumed* here and both were wrong (see 4.6): TRELLIS.2 is already
installed and qualified at `zig-out/neural-tools/` with its weights on disk, and it
never needed a new environment or a dependency risk. What is true is the cost per
prop: 421 s and a 34.8 GB peak of RAM per generation, which is why every run goes
through `dkq3/tools/run_capped.py`.

Fallback that costs no GPU time and no new environment: render TRELLIS (or Qwen)
turntables of a prop and place them as **decal/billboard** art on thin inset brush
cards. Not real parallax, but at market clutter scale it survives, and it can start
the same day.

**Step 4 — re-verify.** Gates as recorded in DESIGN.md section 5, plus a view probe at
the owner's screenshot position so the fix is confirmed against the frame that
prompted it rather than against a metric.

## 3. Decision needed before step 3 -- answered by measurement

The question was convex brush clusters versus inset decal cards, and it settled
itself: a decal card needs an entity to hang on, and `misc_model` was built and
measured (4.5) -- eight planar surfaces attached to no brush, shader `missing`,
non-solid, BSP brush count unchanged at 6. A generated prop is therefore usable
here only as convex brushes, so `map_prop_brushes.py` is the route and the decal
card is not available on this engine at all.

## 4. What was built and what was measured (this pass)

**4.1 The per-face material pass works, and the two censuses that said otherwise
were bad arithmetic.** `map_blender.paint(object, faces)` paints a primitive's own
caps (`prism` face 0 is the cap at `z0`, 1 the cap at `z1`) and `box`/`slab`/
`slab_with_voids` take `soffit=`/`crown=`. The exported `.map` now carries
`concrete_panel` on 89 downward faces against 78 upward, and `roof_gravel` on 38 up
against 28 down. The censuses that reported failure used (a) `cross(p1-p0, p2-p0)`,
which is not what q3map2's `PlaneFromPoints` does -- the outward normal here is
`cross(p2-p0, p1-p0)` -- and (b) `a[1]*b[2] - a[2]*b[1]`, which is the **x**
component of a cross product, so they were classifying walls as soffits. Brush names
do not survive into a `.map`, so any per-object census of one is meaningless.

**4.2 `scale` in a face line is world units per texel, read out of the compiler.**
`material_style` writes `repeat / texwidth`, which looked inverted against every
other convention in the project. In q3map2 `map.c:QuakeTextureVecs` the vectors are
built as `mappingVecs[i][j] = vecs[i][j] / scale[i]`, so one tile spans
`texwidth * scale` = `repeat` world units: the exporter is right. `ParseRawBrush`
also confirms the field order `shiftS shiftT rotate scaleS scaleT`, and that of the
three trailing integers only the first is read, as the `C_DETAIL` bit.

**4.3 A material's `repeat` is set by its motif, not by its texel density.** Both
metal surfaces were tiled at 128 units, which satisfies an 8-texels-per-unit budget
and still reads oversized, because a 1 m window then shows a quarter of a
composition -- one panel, half a seam, no tread. Reading a rendered 1 m window at
the capture's 14 display pixels per unit put `metal_deck` and `metal_column` at 32,
`grate` at 48 and `cloth` at 64. No image regeneration is involved: `repeat` is only
the UV projection, so the whole texture-only loop costs an export and a compile.

**4.4 `decorate` marked objects while the exporter read materials.** All 4876
exported faces shipped with content flags `0`, so not one brush in the map was ever
`detail` and the promise of "no vis splits, no shadows" was fiction.
`brushes_for_mesh` now reads `dk3.detail` off the object.

**4.5 `misc_model` does not work on this engine -- measured, not assumed.**
GtkRadiant 1.6.7 / q3map2 ydnar 2.5.17 accepts Wavefront input, but the test
prop compiled to eight planar surfaces attached to no brush, shader `missing`,
non-solid, with the BSP brush count unchanged at 6. Props must be authored
brushes, which is why 4.6 exists at all.

**4.6 TRELLIS.2 is installed, qualified and now used.** Weights and source live
under `zig-out/neural-tools/`; a generation is 421 s and peaks at 34.8 GB of *RAM*
-- RAM, not VRAM, is what has crashed this machine twice, so every run goes through
`run_capped.py`. `dkq3/tools/` gained `map_prop_concepts.py` (Qwen/ComfyUI concept
-> measured alpha matte), `map_prop_brushes.py` (GLB -> convex brush recipe, 4-9
brushes per prop) and `map_prop_palette.py` (mean linear albedo per crafted
material). Eight props generated and placed; `maps/japanDM/props.py` owns the
placement table, the chroma-based colour-to-material decision (the map's night
albedos average ~0.05 linear against a generated product shot's ~0.50, so a raw
distance match paints every prop asphalt), and the rule that most props stand off
recorded furniture rather than standing in an open lane. Result: 45 props, 263
brushes, every one `detail`.

**4.7 The placement loop belongs outside Blender.** `verify()` is the authority but
costs a Blender start per guess; pre-computing clearance against the
`DK3_BOXES_JSON` manifest took 264 props at 1565 brushes with eight collisions down
to 45 props at 263 brushes with zero, iterating in seconds instead of minutes. The
traps it caught were anchor globs (`stall_*` also matches a stall's awning, posts
and light strip, so one stall became six anchors) and space that reads empty in plan
but is not: the plaza's centre is a holo pool, its corners are benches, the north
stall rows run diagonally 32 units apart, and the east roof's centre line is the
torii pad.

**4.8 `detail` props are nearly free to compile.** With 263 more brushes the full
pass cost `bsp 25 s / vis 35 s / light 57 s` where this map previously needed an
884 s `-vis`. Detail brushes add drawn surfaces (3550) and not vis clusters, which is
what makes several hundred small objects affordable in this engine at all.

**4.9 Still open, in the order they now cost.** (1) The mid-scale authored kit --
window reveals inset instead of painted flat, canopy hoods on posts, conduit and
cable runs, kerbs and gutter recesses, recessed gratings, sign boxes with depth --
is the remaining half of 1.1: props are object scale, but the *architecture* is
still 800 axis-aligned boxes. (2) Props cast no shadows, which is why the table
seats them against lit surfaces; a hero prop in the middle of a light pool would
still read wrong. (3) `ac_condenser`, `pushcart` and `lantern` hulls are the softest
of the eight; `--pieces` is the dial, and a hero prop deserves its own pass.
