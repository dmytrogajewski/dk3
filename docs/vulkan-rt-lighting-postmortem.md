# Post-mortem: lost detail in ray traced lighting (sequences 372–376)

Status: written after sequence 376. The fixes named here are implemented; owner acceptance is
open.

## Summary

The ray traced lighting (`r_vkLighting 1`, the remaster default) rendered whole classes of
surfaces too dark or wrongly coloured. The owner reported, over several sessions:

- black models;
- floors and walls lit by nothing while the fixtures beside them glowed;
- a green cast in rooms with no green light;
- dark interiors with outdoor maps too bright.

Detail was lost because light was missing. Texture, bump and colour vanish into black where
the irradiance is near zero.

There was no single cause. Four independent defects in the renderer stacked up. Three
measurement defects then hid them, and the process let them survive several rounds: we tuned
symptoms instead of finding causes.

## What went wrong in the renderer

1. **Inverted normals (largest; present since ray traced lighting was introduced).**
   - `stage.frag` flipped the shading normal when `gl_FrontFacing` was false.
   - The renderer draws with a negative-height viewport, Quake's clockwise winding and a
     counter-clockwise front face. Under that setup, ordinary visible faces report
     `gl_FrontFacing = false`.
   - So the flip inverted the normals of visible floors, walls and models. Every light in front
     of them failed the cosine test.
   - Their sky rays started on the far side of the surface and escaped through the floor, which
     made open ground look over-lit.
   - Baked lighting hid this: lightmaps barely use the normal, and the model light grid keeps an
     ambient floor.
   - Found only when a per-pixel probe printed a visible ground pixel with stored normal z = +1
     and `front = 0`.
   - Fix: shading normals now face the viewer (`dot(n, eye − p)`), for world and model surfaces.
2. **Guessed light data instead of the original data.**
   - The first ray traced lights used:
     - entity `light` and `_color` only;
     - emitting faces guessed from texture names;
     - a sky coloured by the sky box picture and scaled from a lightmap percentile.
   - The original maps carry the real data, which we did not read:
     - texinfo SURF_LIGHT value and `extsurfinfo` colour per face;
     - an emitting-sky value per map, or none;
     - `cap` on 8,053 lights;
     - colours normalised to their brightest channel.
   - Results:
     - green rooms (e1m4a's green sky box lit an open-roofed room);
     - over-lit capped fill lights;
     - glowing fixtures that lit nothing (guessed strength 80–600 instead of value × area);
     - sky light on maps whose sky emits nothing.
   - Fix: `surface_lights.py` sidecars, `cap`, normalised colours, data-driven sky, sun, styles.
3. **Shadow heuristic.**
   - Only the four strongest lights in a cell got shadow rays. All other lights were scaled by
     the fraction of those four that was visible.
   - A big emitter in the next room, blocked by a wall, therefore darkened every light that did
     reach the pixel.
   - Full light cells kept lights by raw power, not by light delivered to the cell.
   - Fix: lights are ranked by contribution per cell and culled by PVS. A visibility cache marks
     lights no ray from the cell reaches. Two importance-sampled rays cover the rest without
     bias.
4. **Wrong order of operations against the original encoding.**
   - The original lightmaps sum all light in radiosity units, then apply one curve (scale,
     overbright, gamma).
   - Ray traced lighting converted direct light first, then added sky and probe bounce as
     separate linear terms.
   - A dim bounce of 20 radiosity units became about 0.02 linear and vanished. That was the
     detail in shaded areas.
   - Partial sky was overstated on the other side of the curve.
   - Fix: sky × visibility and the probe bounce are converted back to radiosity units and summed
     before the one conversion.

## What went wrong in measurement

- **Screenshots were taken one command late.**
  - `screenshotJPEG` captures the frame rendered after the next queued command.
  - The survey switched modes immediately after each capture, so every RT/baked ratio before
    `survey9/` was inverted.
  - We drew conclusions such as "indoors fine, outdoors 10× too bright" from swapped labels.
- **Calibrated against an artifact.**
  - The first sky calibration (0.4 × value) was fitted while defect 1 still sent sky rays
    through floors.
  - It was redone against the traced cosine-weighted visibility: 0.6 × value (e2m2a 0.59,
    e2m1a 0.65, e3m1a 0.93).
- **Captures disturbed by the game.**
  - Monsters attacked the probe player, and placements without a fixed view angle hit
    different walls each run.
  - `dk3_runtime_clear_actors` destroyed actor entities that other systems still referenced.
    The game then segfaulted on e1m1a. On the NVIDIA path, that crash mid-frame preceded the
    machine freeze of 2026-10-10 00:19.
  - Replaced by `dk3_runtime_pacify_monsters`, which only sets `ignore_player`. Lavapipe runs
    reproduce and confirm the crash and its fix without risking the host.
- **Eyeballing instead of numbers.**
  - For most of the work, visual comparisons of a few screenshots decided what was wrong.
  - The decisive evidence came only from numbers:
    - CPU replays of the original lightmaps (cap plateau, spot cones, surface-light falloff,
      sky per visible fraction);
    - CPU shadow traces against the converted triangles;
    - finally `r_vkDebugView 19`, which prints the centre pixel's four lights, distances,
      blockers, normal and facing.

## What went wrong in the process

- **Symptoms were compensated instead of explained.**
  - Each was tuned against the visible result rather than traced to a cause:
    - a light-grid minimum on black world surfaces;
    - a wider auto exposure range;
    - firefly clamps;
    - sky percentiles.
  - Each tweak made a few views acceptable and masked defect 1.
- **Assumptions about the original tool were not checked early.**
  - The Quake 2 radiosity model was assumed. The baked data showed three differences:
    - targets do not make spotlights;
    - `cap` clamps a light's contribution;
    - colours are normalised.
  - Checking took minutes once the CPU luxel tools existed. They should have come first.
- **A positive result was taken as validation.** When the camera-facing fix lit the e1m4c
  shaft, it was applied to world surfaces only, and the root cause (`gl_FrontFacing` under the
  flipped viewport) was not followed through to models until a black model was reported.

## What went well

- The original maps already held everything needed: surface light values, colours, sky values,
  caps and styles. Extracting them needed no change to the converted maps, so save checksums
  hold.
- Small, targeted instruments paid off quickly:
  - lightmap luxel replays;
  - the converted-triangle tracer;
  - the per-pixel probe;
  - categorical debug views (15 unshadowed direct; 17 shadow ray categories; 18 blocker
    albedo).

## The host freeze (2026-10-10 00:19) — open

- **What happened.** The machine froze about 30 s into a GPU capture of e1m1a. That run used
  the first, destructive monster command.
- **Destructive command.** `dk3_runtime_clear_actors` destroyed actor entities; on lavapipe
  that run segfaults. It was replaced by `dk3_runtime_pacify_monsters`.
- **Volumetric fault.** On lavapipe a second fault remains in the froxel volumetric pass:
  - it is a segfault in JIT code, at a fixed offset (0xa) into one function, on every worker
    thread;
  - it reproduces on e1m3a with default settings;
  - it disappears with `r_vkVolumetric 0`.
- **Bisect so far.** With ray tracing off, it needs the dynamic-light loop in
  `froxel_inject.comp`. With ray tracing on, it also occurs without that loop.
- **Ruled out:**
  - the parameter layout;
  - the light upload;
  - the stream allocator;
  - the rain boxes;
  - the grid volumes.
- **Hypotheses not yet separated:**
  - lavapipe's worker stack overflowing on the larger shader variants. The fixed function
    offset suggests a stack probe; a raised `ulimit -s` was not confirmed to reach the game
    under dkguard.
  - a real out-of-bounds read that NVIDIA would turn into a device fault.
- **Guard added.** A failed dynamic-light upload now drops that frame's lights. Every consumer
  then sees a count of 0, never address 0.

## Remaining risks and open items

- `shadeLiquid` still flips its base normal on `gl_FrontFacing`. Liquids use the normal for
  wave bases and reflections; check them against the same convention.
- Models in ray traced lighting take two shadow rays and the probe field. The e1m1a swamp
  platform is visible now but about 1.8× darker than baked.
- Survey (11 maps, `survey13/`, before the facing and bounce fixes): RT/baked luminance
  0.37–1.65, median 0.89. Re-measure after them.
- `r_vkDebugView 19` needs `fragmentStoresAndAtomics`, now enabled on every device. Keep it or
  gate it behind a development build.

## Rules we keep

1. Read the original data before modelling it. A CPU replay of the shipped lightmaps settles a
   lighting question in minutes.
2. Measure with numbers at a known pixel before tuning anything. Every lighting fix starts with
   a probe reading.
3. Never fit a calibration while a known defect is open.
4. Captures pause after each screenshot. Monsters are pacified, never removed. Views are placed
   with explicit angles.
5. Risky renderer changes are smoke-tested on lavapipe before the GPU.
