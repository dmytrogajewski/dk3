# Native port acceptance

## Sequences 358–373 — vulkan-remaster — implemented; owner visual acceptance open

The owner directed the remaster roadmap in [vulkan-remaster.md](vulkan-remaster.md)
to completion after milestone 1. Every item below is implemented. Each one only
passed a lavapipe smoke run (`dkguard --headless`, 1280x720, e1m1a), which shows it
runs and composites. None is verified: the owner asked to judge visuals in game,
and the RT tier still needs a `--gpu` run on the RTX 5090.

Also fixed in this pass: the native client set `refEntity.dk3World` to the network
world id instead of the renderer's world handle (`client.zig`, `owner.render`).
The two numberings only matched under OpenGL, so Vulkan dropped every model
except the view weapon.

| # | Slug | State | Smoke evidence (`zig-out/reports/vulkan-remaster/`) |
| --- | --- | --- | --- |
| 358 | `vulkan-renderer-hdr-pbr-core` | Implemented | `rm1/` |
| 359 | `native-runtime-environment` | Implemented (underwater composite from brush contents) | `water1/` |
| 360 | `vulkan-renderer-water` | Implemented | `water1/` |
| 361 | `vulkan-renderer-volumetrics` | Implemented; extinction tuned against e1m1a fog | `vol2/`, `vol3/` |
| 362 | `vulkan-renderer-taa-fsr` | Implemented; `r_vkRenderScale 0.5` vid_restart smoke | `taa1/` |
| 363 | `vulkan-renderer-weather-gpu` | Implemented; new syscall `CG_DK3_R_WEATHER_V1` (716) | `wx1/`, `wx2/` |
| 364 | `vulkan-renderer-clustered-lights-shadows` | Implemented | `sh1/` |
| 365 | `material-sidecars` | Implemented: 3,960 sidecars, 3,851 normal maps in 6 s | `mat1/` |
| 366 | `vulkan-renderer-rt-shadows-reflections` | Implemented: lavapipe builds 16,208-triangle structures for e1m1a | `rt1/` |
| 367 | `vulkan-renderer-ddgi` | Implemented | `gi1/` |
| 368 | `lightmap-rebake-directional` | Implemented: 25 e1m1a pages baked progressively | `bk4/` (direction view), `bk5/` |
| 369 | `vulkan-renderer-path-tracing` | Implemented, off by default; ray facing flipped for Quake 3 winding (also fixes DDGI validity) | `pt3/` (mask, lighting), `pt4/` |
| 370 | `vulkan-renderer-m1-gaps` | Beams/rails/lightning and model shadows implemented; material scan Passed (`definitions=7086 unknown_keywords=0`, `final1/`); AVI Blocked: `demo` playback stops at once, so `video` refuses | `final1/`, `avi1/` |
| 372 | `vulkan-renderer-lighting-scale` | Implemented from the owner's second set of screenshots ("everything is white"): remaster lightmaps now normalise each texel like the original (`world.linearLight`, brightest channel capped at white with a quarter stop of headroom) instead of keeping the full x4 overbright range that lit surfaces up to 21x; dynamic lights add at that scale; the composite defaults to Khronos PBR Neutral without its black toe (`r_vkTonemap 0`, AgX stays as 1; `r_vkSaturation` 1); auto exposure adapts within [0.75, 1.25]; the baked-light sheen uses a roughness floor of 0.5; authored fog coverage is remapped to the original display-space blend with dynamic-light glow kept in its own froxel pair; opaque model pixels mark HDR alpha so TAA stops accumulating history over moving limbs. Headless e1m1a: mean luma 0.314 -> 0.124 (classic 0.086), saturation back to the classic range. A locally extracted validation layer (`val5/`) found two device-creation omissions, fixed: update-after-bind storage images and shader demote need their features enabled. PBR dynamic lights now cap at the light's own colour (they peaked at ~50x at the source). Against an OpenGL1 capture of the same cutscene shot (`cine-gl1b/`), the remaster character was ~1.4x too bright with grey hair and skin: the probe ambient now may at most double the grid ambient and emissive surfaces count at most 0.5 in the probe gather; model skins get specular 0.4; `r_vkDebugView 6`/`7` show texture colour / light only. Found on the RTX 5090 (`gpu*/`, `wf*/`): distant objects turned white from Schlick Fresnel rising to 1 at grazing angles (now limited by roughness and specular strength; model skins specular 0), and waterfalls were drawn as pool surfaces (vertical faces now keep their authored stages); both match OpenGL1 captures of the same views. Open: the intro map faults lavapipe in shader code after the froxel passes (`r_vkVolumetric 0` avoids it); the owner's screenshots show the same map rendering on the RTX 5090 | `wx4/`, `wx5/`, `val5/` |
| 373 | `vulkan-renderer-rain-realism` | Implemented: physical drops (1-3 mm, Gunn-Kinzer speeds, 1/30 s streaks, pixel-wide with coverage alpha), per-drop lighting with back-lit glints, distant rain as froxel fog under open sky, crown splashes, puddle-only ripples, porosity darkening, TAA motion mark. Also: crashes now write `crashlog.txt` with a backtrace (`crashtest/`); ion-blaster glow no longer floods the fog (`fire1/`) | `rain1/`, `rain2/` (RTX 5090) |
| 371 | `vulkan-renderer-rain-occlusion` | Implemented from the owner's first in-game screenshots: rain occlusion map (`shadows.rainCamera`, lower half of the shadow atlas) hides drops, flakes and splashes under roofs and lands splashes on the stored surface; only exposed surfaces get wet or snowed on. Also: procedural bump off for model skins and faded under magnification (blocky faces), wider baked-light specular lobe and glossy rather than mirror-like wet walls (white speckles), sky column fogged at the authored `fog_skyend` coverage, liquids translucent from below, and a dangling draw-list slice in `renderView` that the new pass exposed (segfault) | `wx3/` (no validation layer was installed on the dev host at the time, so the `r_vkValidation 1` run there proves nothing) |

Open:
- Owner in-game inspection.
- An RTX 5090 run of the ray-tracing tier and its performance.
- Brightness tuning of path tracing against the radiosity (`r_vkPtLightScale`).
- Alpha-tested foliage is outside the acceleration structures, so it neither
  casts ray-traced shadows nor blocks path-traced light.
- Skinned models are not in the acceleration structures: they get shadow-map
  shadows and DDGI ambient light instead.
- FSR 3.1 is not bundled; the in-house temporal upscaler covers render scaling.

## Sequences 347–357 — vulkan-renderer — milestone 1 implemented; owner visual acceptance open

`renderer_vulkan.so` (Zig 0.16, `src/renderer_vulkan/`) implements the complete
refexport v13 surface on Vulkan 1.3 and is now the default `cl_renderer`; OpenGL2
loads automatically when the module is missing or refuses the machine. Scope,
design and the later remaster roadmap: [vulkan-remaster.md](vulkan-remaster.md).
The native client again submits worldspawn fog (`client/fog.zig`), which also
restores fog in both OpenGL renderers. `r_mode -2` renders at the native,
high-DPI drawable; fullscreen is borderless desktop size.

| Evidence (`zig-out/reports/vulkan-renderer-357/`) | State | Limits |
| --- | --- | --- |
| `boot1/`, `boot-gl2/` | Passed: lavapipe boot, menu 2D, fonts and lit menu models inspected against OpenGL2 | `dkguard --headless`, 1280x720 |
| `map1/`, `map-opengl1/`, `map-opengl2/` | Passed: e1m1a lightmaps, rain, view weapon, HUD inspected; matches OpenGL1's overbright model | Single view; no RMSE tolerance recorded |
| `fog-vulkan/`, `fog-opengl1/` | Passed: e2m1a authored fog identical in both renderers | — |
| `preview-vulkan/`, `preview-opengl1/` | Passed: resident e1m1b preview from e1m1a, distinct inline handles | `runtime_render_world_probe.py` itself times out on both renderers: its ready-line wait predates region admission |
| `combat-vulkan/`, `combat-opengl1/` | Passed: glove fire view, 400x300 `dk3-save-*` preview, 128x128 levelshot | `video` only runs during demo playback: AVI capture unverified |
| `default-native/`, `fallback/` | Passed: default loads Vulkan with a native drawable; with every Vulkan driver disabled the client logs the refusal and runs OpenGL2 | — |

Open: owner in-game inspection on the RTX 5090; Khronos validation run (layer not
installed on the host); skeletal cinematic characters. `RT_BEAM`/rail/lightning
entities and model shadows are drawn since sequence 370.

## Sequence 342 — cinematic-performance-pivot — diagnostic gate implemented; new performance unverified

The default client now uses original vertex-model presentation for cinematic
source paths even with a skeletal package installed. Explicit native skeletal
previews use `cg_neuralCinematics 1`. Guarded native records with that package
present finish all 11 shots in both modes. Fallback yields 140 original frame
diagnostics and zero skeletal diagnostics. The paired review aligns 140 frames;
the audit compares actual skinned IQM geometry to original source frames and
50/50 linked Hiro frames fail on the rejected sequence-341 body. This is a
rejection gate, not a replacement performance.
[Data flow, commands and evidence](cinematic-performance-pivot.md).
`blender-shot-008-lit/` is a headless, hash-pinned 3D authoring stage at the
failed 51-second pose; it shows the original and actual skinned IQM meshes.
The integrated build and `test-runtime` pass; consolidated `zig build test
-Dpython=/usr/bin/python3` passes 318 Python and 453 Zig tests. A stale co-op
test fixture was fixed after the first broad run.

## Sequence 341 — cinematic-model-identity — failed visual candidate

The generated white-gi Hiro remains **Failed** after the owner inspected the
native opening scene. The approved facial mesh and texture were restored and
verified by hash, and all eleven preview shots ran, but head placement, raised
shoulders, arms and overall acting still look wrong. Passing clip validators
and package checks do not establish visual acceptance. The sequence-341 archive
is local diagnostic evidence and must not be installed or selected by default.

The next candidate uses the recorded original performance as a visual
reference, a newly calibrated character rig and authored skeletal acting.
Shot timing and choreography may change; dialogue and required story events
remain. See [cinematic model preservation](cinematic-model-preservation.md).

## Sequence 340 — generic-navigation — implemented; partially verified

Navigation now follows the world as it stands and routes state intent
([navigation](navigation.md#generic-navigation-sequence-340-generic-navigation),
[co-op bot](coop-bot.md)). Evidence is local under
`zig-out/reports/runtime-zig-340/`; the regenerated navigation package (all maps,
the bundled BSPC of this sequence) is `dk3-navigation-340.pk3` there and is not
installed into the preserved game.

| Scenario | State | Evidence and limits |
|---|---|---|
| Every supplied map loads in the native runtime | Passed | `coverage/navcov-final/`: 84/84 maps report (73 before). Fixed: satyr side-change poses optional (the supplied model has none), a map naming scripts without an action program loads (e1m7b), an empty authored `spawnflags` reads as 0 (e4m2a). |
| Navigation coverage, all maps | Passed (measured) | Same 73 maps as the original navigation: uncovered floors 26,378 → 3,550, unrouted 74,127 → 62,773. e4m4c, e1m2b (a flooded room), e1dm2 and e4m6b still route fewer floors than before. |
| Gates, planner, lifts, intent objectives | Implemented | Live gates (doors, walls, hazards, sliding floors, breakables; lifts excluded), planner with nested controls, train lift links both ways, lift boarding/operation from the shared `liftStep`, firing positions, touch points, use doors, crouch-only areas. |
| New Game → intro → e1m1a → e1m1b → e1m1c → e1m2a → e1m2b → e1m3a → e1m3b, continuous (Ronin, candidate navigation) | Passed | `coop/final7-newgame/`: no deaths, 1,719 s of game time to e1m3b (171 s wall); e1m3a played by its objective route. |
| e1m1a → … → e1m3b, continuous, same build | Passed | `coop/final7-chain/`: no deaths, 1,117 s of game time to e1m3b. Earlier builds in this sequence failed on the way (RUN log); each failure was fixed and the pair rerun. |
| Episode 1 on the installed (original) navigation | Not claimed | The objective e1m3a route needs this sequence's navigation (the crawlway into the pit, train lift links); with the installed package it stops in its first stage. The candidate package must be installed with the next asset build. |
| Deathtag e1dt1 with gates | Regression fixed; captures open | `match/mp-long-new/` (bots idle up to 110 s at gated lift doors) → `match/mp-final2/` on the final module: travel 593k vs the original build's 590k, longest stand 18.5 s, one objective carrier (two in `match/mp-final/`, three in the original). No run, the original build included, captures in 600 s. |
| Game crashes found by the bot | Fixed | A drained health station hit by a bolt (`MissingComponent`, `coop/crash2/` trace, `coop/crash4/` after); a hurt arrival no longer replaces a healthy death checkpoint (death loops at 2 and 10 health). |
| Build checks | Passed | `zig build test-runtime` (a leftover test print made the step fail although all 225 tests passed) and `zig build test -Dpython=/usr/bin/python3` (293 Python tests; four test modules imported a sibling by bare name). The shell's default `python3` here is an unrelated 3.12 environment without Pillow. |
| e1m3b onward by the bot | Unverified | e1m3b's planner now has a real goal (touchable exit, touch point), but the map needs route work (big door, laser dam, Superfly). |

## Sequence 339 — cinematic-body — visual acceptance failed

The owner rejected the delivered native result: swollen shoulders, broken neck,
smeared cloth and lapels, and poor hand geometry. The candidate is **Failed**;
the numerical and playback receipts below do not qualify its appearance. The
raw generated model retained better cloth and proportions than the delivered
repair. Sequence 341 investigates that loss before another cinematic build.

The original-body subdivision was rejected. A new white-gi body and 4096×4096
atlas are generated and rigged onto the captured cinematic bind. No original
body triangles or UVs enter it. The independent detailed head is retained with
an explicit collar cut, and original props/performance remain. See
[reproduction](generated-dojo-model.md) and the
[native review](../zig-out/reports/cinematic-body-339/cinematic-review.html).

| Scenario | State | Evidence and limits |
|---|---|---|
| New cosmetic master and frozen clip build | Passed | `package-proof.json`; 148,974 vertices, 108,341 triangles, 44 joints; 23 clips pass. New geometry/materials are admitted explicitly; subsequent clips freeze bind, geometry, weights, normals and UVs. Original body triangles: zero. |
| Mapping, timing, fallback and variants | Passed within fixture | Source-model mapping, compact clip table and authored scene bytes exact with 338; all entries retained, 931/940 original entries exact; alpha/fullbright variants retained. Actual original-only run excludes the optional archive. |
| Native GL2/GL1, restore and video | Passed | `owner-native/`, `owner-native-gl1/`, `owner-native-video/`, `native-legacy/`, `native-legacy-video/`; all eleven shots and release, both presentations restore active cinematics; exact recorded runtime/overlay identity replay. GL2 log admits 4096×4096 body/head textures with picmip 0. |
| Fresh-process reproduction and compilation | Passed | `reproduction-proof.json`: master, receipt and all 28 animation outputs exact. `idempotence-proof.json`: check-only passes; unchanged output retains inode/mtime. |
| Tooling and current runtime tests | Passed within recorded scope | `python-owner-candidate.log`: 293 tests. `zig-tests.log`: build exit 0, native C contracts and ragdoll debug-stderr warning; direct execution resolves it with 225/225 domain tests in `zig-domain-detail.log`. No runtime edits in this change. |
| Delivered visual quality | Failed | Owner screenshot retained in `visual-rejection/owner.png`; broken neck, inflated shoulders and smeared cloth were visible in the earlier captures and should have prevented delivery. |
| Remaining cinematics | Unrun | Facial acting, walking contacts, full opening/campaign reconstruction and campaign handoff remain unqualified. |

Evidence is under `zig-out/reports/cinematic-body-339/`; final local products are
under `zig-out/cinematic-body-339/reviewed-generated/`. Optional archive SHA-256:
`8f2abb082266c0af96f2d30ffc0cc5f1190eacee41e6dcef4627189ae87a73d2`.
Runs use an isolated dereferenced native installation; ordinary selectors,
retail assets and owner saves remain untouched. Generated binaries remain local.

## Sequence 338 — cinematic-fidelity — original-body candidate rejected; superseded by 339 candidate

The owner’s three review frames expose mismatched arm gestures, sideways sword,
neck/armor separation and the dojo costume mismatch. Sequence 337's mechanical
passes are retained; visual performance/model acceptance is **Failed**. Repair
uses actual source motion and a source-specific dojo replacement rather than
propagating that candidate into more scenes. Owner frames are retained under
`zig-out/reports/cinematic-fidelity-338/owner-{1,2,3}.png`.

## Sequence 337 — cinematic-performance — complete dojo block verified; full recreation and artistic acceptance pending

Original opening shots 15–25 are recorded with original models. A separate
64.8-second, eleven-shot scene preserves the two actors' original queues,
transforms, dialogue, door use and timing while replacing the camera curves.
Twelve Hiro and eleven Ebihara clips are reconstructed onto their frozen IQM rigs.
Measured head axes, hand/finger inheritance, loop-aware elbow poles, grouped prop
grips, staff orientation/floor contact and skinned boot sole placement are baked
offline. See [reproduction and limits](cinematic-reconstruction.md) and the
[interactive review](../zig-out/reports/cinematic-performance-337/cinematic-review.html).

| Scenario | State | Evidence and limits |
|---|---|---|
| Original reference and new scene with original models, GL2 | Passed | `original-recording/`, `original-video/`, `final-legacy/`, `final-legacy-video/`; eleven shots, release and active save/load; optional IQM archive actually absent. |
| Final deterministic IQMs, GL2/GL1 and replay | Passed | `deterministic-skeletal/`, `deterministic-skeletal-gl1/`, `deterministic-skeletal-video/`; eleven shots and camera release, GL2 active save/load; nineteen observed source ranges select declared targets at authoritative-duration-following rate 0. Four other aliases are offline-only. |
| Original actor/audio/use/timing contract | Passed | `performance-contract-final.json`; consumed fields equal; new camera curves excluded. Original empty negative-time animation is ignored as the runtime does; timed empty requests remain barriers. |
| Serialized motion and preservation | Passed | `deterministic-package-proof.json`; 23 clips pass unchanged limits; max sole height error 0.32942 (<0.5), grip 0.000801 (<0.02), staff floor 0.000817 (<0.1); 936/940 entries exact, two cinematic IQMs/table/provenance change; geometry, binds, weights, UVs, normals and textures exact. |
| Fresh-process determinism and unchanged output | Passed | `deterministic-reproduction-proof.json`: all 27 payloads plus receipt byte exact; generated channels canonicalized at twelve decimals to remove 1e-15 residual ranges. `deterministic-scene-proof.json`, `manifest-idempotence-proof.json`: scene program bytes exact; manifest output inode/mtime retained. |
| Headless inspection and review controls | Passed | `hiro-deterministic-blender/`, `ebihara-deterministic-blender/`: twelve CPU Blender 5.1.2 views; `browser-review.json`: three videos decode, paired seek/play/half speed and all eleven selectors exercised. Every native shot and exact full-body samples technically inspected; human artistic approval pending. |
| Tooling aggregate / retained runtime contracts | Passed within recorded scope | `python-aggregate-deterministic.log`: 256 tests, including 17 continuation regressions. Sequence 336 `zig-runtime-final.log`: retained 312/312 tests and C contracts; no Zig/runtime changes here, no duplicate broad suite or claim for other concurrent edits. |
| Rest of opening, other scenes and original campaign handoff | Unrun | Separate scene namespace; no campaign replacement, installation activation or original/save overwrite. Fixture keeps original geometry/control entities and exact rebuilt navigation; it does not prove the campaign's original entry/exit. |
| Facial/eye, expressive fingers, cloth/deformation, moving contacts | Unverified | Fixed rigs and materials retained. Walking plants are undeclared and unqualified; numerical success does not establish artistic quality. |

Evidence is under `zig-out/reports/cinematic-performance-337/`; final IQM build
and closed package are under `zig-out/cinematic-performance-337/deterministic/`.
The separately authored scene package remains `final/dk3-dojo-dialogue.pk3`.
Optional package SHA-256:
`907c6f6fcd9bb8e71a65c32577a0f1db4237ee33ec22e1cadef107a6d10622c8`.
Guarded software runs use immutable generation `0b3f6bbb…`, runtime identity
`87c4af02a78616375e32d0bb3abf1c86eff356e7e3c78d07c0a1cbc72cf0adef`.
Original master/installation inputs are hash-verified. Earlier fit, thumb, pole,
prop/floor/sole and reproduction failures remain retained. No original program,
normal selector, owner save, network or save representation is modified.

## Sequence 336 — cinematic-reconstruction — verified first slice; artistic and campaign acceptance pending

Original opening shots 12–14 are recorded with converted original models. A
hash-pinned surface-marker capture reconstructs three Hiro performances onto
the frozen IQM rig; a new 16-second dojo scene compiles to the existing cinematic
format and is packed separately. Full opening replacement, other actors, facial
acting, neutral-head calibration and hand-to-hilt fit remain open. See
[architecture and reproduction](cinematic-reconstruction.md) and the
[paired interactive review](../zig-out/reports/cinematic-reconstruction-336/cinematic-review.html).

| Scenario | State | Evidence and limits |
|---|---|---|
| Original shot reference, original models, GL2 | Passed | `cinematic-reconstruction-336/original-reference-nav/` and `original-video/`; original cameras/audio/tasks plus checked spawn; all three shots, release and active save/load. |
| New scene with optional models absent, GL2 | Passed | `retake-original/` and `retake-original-video/`; actual optional archive excluded in a disposable base path; all shots, release and active save/load. |
| New scene with reconstructed IQM, GL2 and GL1 | Passed | `retake-skeletal-final/`, `retake-skeletal-video/`, `retake-skeletal-gl1/`; GL2 active save/load; all three mapped ranges observed with source-duration-following rate 0. |
| Capture/serialized motion/package/reproduction | Passed | `package-proof.json`, `reproduction-proof.json`; max marker RMS 0.94482 units, max plant displacement 0.16271; all twelve payloads reproduce; 937/940 package entries exact, only cinematic IQM, clip table and metadata change; geometry/bind/weights/textures exact. |
| Headless Blender and browser inspection | Passed | `blender-job/result.json`, six CPU full-body views; `browser-review.json`, three videos decode, paired controls/half speed and all capture selectors exercised. Numerical/browser checks do not establish artistic approval. |
| Python and Zig contracts | Passed | `aggregate-refreshed.log`: 239 tests; `zig-runtime-final.log`: exit 0, 312/312 tests and C contracts (existing ragdoll debug stderr retained). |
| Full campaign reconstruction and original handoff | Unrun | Fixture substitutes only the BSP entity lump and rebuilds its exact navigation; original 16 geometric lumps stay byte exact. No campaign program, completion target, installation selector or owner save is changed. |

All evidence lives under `zig-out/reports/cinematic-reconstruction-336/`.
Engine jobs use dkguard software rendering and explicit immutable installation
`0b3f6bbb325cc304ec1be2254645af17afc34caf2e3273769a7d7ce80fb24b47`,
runtime identity `87c4af02a78616375e32d0bb3abf1c86eff356e7e3c78d07c0a1cbc72cf0adef`.
The latest source tests are separate from that installed runtime. Earlier failed
navigation, contact fitting and SIGTERM capture reports are retained. Local-only
scene and skeletal products are not activated in the ordinary installation.

## Sequence 335 — coop-bot — implemented; New Game through e1m2b passed headless (Ronin)

A scripted player bot plays the single-player campaign on a dedicated server at
13–22× real time with exact 50 ms frames (`fixedtime 50`, `timedemo 1`). It is the
ordinary slot-0 client: user commands, `use`/`save`/`load`/`attribute` client
commands, and the client's world-publication acknowledgements with digest and
runtime-identity validation. A sandboxed bundled Lua 5.4.7 route
(`dkq3/coop/`) chooses actions; staged level bodies resume after death
checkpoints. See [coop-bot](coop-bot.md). The campaign verification runs at
Ronin (`--skill 1`): Samurai's extra sludgeminions in e1m2b (authentic 275 hp,
10–30 per glob at 900 u/s) outlast the bot's ammunition; Samurai still passes
the opening and e1m2a. e1m3a is partly routed; later maps and episodes 2–4 have
no authored route yet.

| Scenario | State | Evidence and limits |
|---|---|---|
| New Game → full intro → e1m1a → e1m1b → e1m1c → e1m2a → e1m2b arrival, continuous, Samurai | Passed | `zig-out/reports/runtime-zig-335/newgame-e1m2b/` (final code and routes: 0 deaths through the whole of e1m2a, 1208 s game / 100.1 s wall, 12.1×; its saves include the `coop-e1m2b` arrival for route work), earlier `newgame-final/` and `newgame-opening-6/` (963 s game time in 71.3 s wall, 0 deaths, 201 completed actions); all 115 intro shots and every arrival scene played; both e1m1b turret controls destroyed, ford Crox, health trees, Thunderskeet boss killed with Ion fire, plateau drop and river swim; e1m1c pipe climb with running jump, gate, yard, switch and monitor, raised platform, liftmaster descent, authored cut. Module/server/route SHA-256 in `inputs.json`. Ends at e1m2b by design (no route). |
| Death checkpoint restoration mid-level | Passed | Bridge-stage deaths (e.g. `runs` of e1m1b with 1–4 restorations): the game reloads its checkpoint (full map load), the bot is re-admitted and resumes at the saved stage, skipping actions already reflected in the save. |
| Region admission and travel by the bot client | Passed | Identity seams, landings and the e1m1c→e1m2a cut all depart and admit with the bot answering `dk3_world_begin/data/patch` (digest-validated) through `BOTLIB_EA_COMMAND`. |
| Lua sandbox and budgets | Passed (unit) | `engine/lua.zig` tests: io/os/package/debug/load/dofile absent, `string.dump` rejected, instruction budget stops runaway loops, memory cap fails the script. 223/223 runtime tests pass when run directly; the `test-runtime` build step is reported failed by a concurrent work-in-progress `domain/ragdoll.zig` test that prints to stderr. |
| Runner evidence parsing | Passed (unit) | `dkq3/tools/tests/test_coop_bot.py` 4/4; architecture checks pass. |
| e1m2a (Sewer System), from its arrival save to the e1m2b exit, Samurai | Passed with restorations | `zig-out/reports/runtime-zig-335/e1m2a-sewers/`: lift, hatch event, flooded drum crossed round its stationary paddles, tube, cart ride to the pump rooms and back (train 123, buttons 125/385), C4 room button 159 opening the drum room's east grate, upper sewer, both leaves of use-door 267/268, pod room button 48 and the ten-second dash over the waterfall walkway through doors 250/251, rockfall slab and the deep canal passage, ladder rungs (button 160) climbed, travel to e1m2b; 6 deaths (upper sewer sludgeminions), each restored from the stage-9 checkpoint; 244 s game / 97 s wall. Runs are stochastic: other replays failed at the same fights before the per-map allowance (`map_deaths`) and the health-gated checkpoints. Continuous New Game through e1m2a: see the next row. |
| New Game → intro → e1m1a → e1m1b → e1m1c → e1m2a → e1m2b → e1m3a arrival, continuous, Ronin | Passed | `zig-out/reports/runtime-zig-335/ronin-newgame-e1m3a/`: 0 deaths, 1600 s game / 148 s wall (10.8×). e1m2b in full: off the gratings into the water chute (its trigger raises the sluice), over the falls into the flooded tank, under water through the submerged lower level to the control room (window broken with the glove, health packs, drain button), back over the spinning drum fan before the water falls, through the sunken hugedoor and the passage into the pit, up to the valve walkway (worker cleared from the wheel, wheel confirmed open), back over the beams to the timed west doors, the wading channels' sludgeminions fought from chosen spots, the hall, the lift, and the end room's single-player end button with its closing scene. The run then stops in e1m3a, whose old generic body cannot route the prison. |
| e1m3a (Solitary), from its arrival save | Implemented, unverified | Guard post button (cell block doors), back through the plate-operated hydraulic door, panel shot from the pit beneath it (crouching back out through its crawlway), cell block and stairs to platdoor (button either side), the big platform to the shaft top. Beyond the shaft top the area graph has no route to the e1m3b exit; not yet routed. |
| e1m3b onward | Unrun | Placeholder `progress` bodies only. |

Runs are not bit-identical: resident-world preparation is paced by the wall clock,
so encounter timing varies; the opening passed repeatedly only after the motor
gained the recorded skills (fire discipline, ammunition reserve, threat-forecast
dodging, ledge/liquid/hazard guards, waypoint commitment, stall hops). Rendering,
audio and prediction are not exercised by this headless verification.

## Sequence 334 — animation-authoring — verified toolchain and isolated clips; visual acceptance partial

The authoring pass adds strict YAML clip and cinematic sources, a typed
headless Blender adapter, BVH/FBX motion interchange, directional retargeting to
the admitted IQM bind rigs, contact cleanup, loop/joint/attachment validators,
cosmetic packaging and generated native preview maps with demo-to-video capture.
The source recipes preserve authoritative animation ranges/rates and compile to
the current `neural-animations.cfg` and `dk3_cinematic 1` formats. Masked runtime
layers, facial channels and a new deformation rig remain separate migrations.

The [tool guide](animation-authoring.md) documents commands, formats, source
licenses and limits. Local evidence is under `zig-out/reports/animation-authoring-334/`;
`animation-review.html` includes the full native video, all GL2 captures, corrected
body/head material previews, recipes and unresolved source findings.

| Scenario | State | Evidence and limits |
|---|---|---|
| Licensed sources and motion interchange | Passed within selected-data scope | Pinned CMU 07_01 walk and 09_01 run plus full conversion notice. BVH imports retain actual 317/149-frame action ranges; FBX round-trip retains 317 walk frames, maximum 0.084 source-unit/0.648° error. FreeMoCap footage returns 403; CMU AVI reference downloads fail TLS chain verification and remain unadmitted. |
| Rig retarget, prop policy and serialized validators | Passed for three aliases | `qualified-build/build.json`: 63 neutral, 32 walk and 22 run frames at 30 Hz on the frozen 33-joint rig. Contact cleanup reduces final walk displacement 2.0204 → 0.4853 units, below 0.5; all declared contact, anatomy, fixed-length, loop and attachment checks pass. Hidden prop channels prevent a floating sword. Neutral remains procedural. |
| Source-performance audit | Failed for 12 original clips; retained | `source-anatomy-audit.json`: 12 of 42 original Hiro clips exceed the anatomical joint-step limit. Prop rotations are excluded from that body limit. No blanket repair/acceptance of original performances follows from the three new aliases. |
| Native compiled three-shot studio | Passed within isolated scope | `native-final/` and `native-final-gl1/`: exact final bundle on software GL2/GL1; all shots, measured-speed walk/run arrivals, camera ownership and normal release. `native-final-clip-proof.json` observes actual 30 Hz target ranges; GL2 active save/load resumes and completes. |
| Engine video and review | Passed | `video-final/`: receipt-matched native demo → AVI → 960×540 30 Hz H.264; `browser-review.json` checks decoded video, all shot/pose selectors and half-speed playback. Ten final Blender samples use separate head/body atlases; earlier single-atlas reviews were defective and remain retained. |
| Package/input preservation | Passed with measured frame re-encoding | `package-proof.json`: 940 entries, 937 payload hashes exact; one IQM and clip table change, provenance refreshed. Geometry/UVs/normals/weights/triangles/binds/parents/atlases exact. Original 955 frames re-quantize by ≤0.00097 rigid-joint units/0.00278°, scale exact. Original master inputs and installed source PK3 remain exact. |
| Aggregate and installation isolation | Passed within tooling scope | `aggregate-final.log`: 218 tests including 25 authoring regressions. `final-policy-proof.json` confirms the latest root/FPS handling reproduces every native-qualified payload byte. `qualification.json`: sequence-333 immutable selectors/launcher exact; all saves/runs in disposable profiles through dkguard. No runtime changes, duplicate native suite, installation activation or campaign acceptance. |

The separate candidate is `zig-out/animation-authoring/dk3-neural-qualified.pk3`,
SHA-256 `5bb319d0b57183aea2690b3b49b62b39c1af91a1a50ecba13ba9dd07fd216162`.
The reviewed normal generation remains `6ac17090…`. Early import dependencies,
padded holds, floating props, material assignment, missing studio navigation/trigger,
headless-X collision and fixture syntax failures retain their original reports;
affected runs and the invalid aggregate are refreshed after repairs.

The native task called `head` rotates the whole performer. The compiler correctly
emits absolute angles, smooth look curves and native yaw-rate compensation; no
independent head/eye layer is claimed. Open: original source failures, full story
and campaign visual playback, contact/acting quality beyond selected clips,
hardware rendering, masked layers, facial channels, new rigs and footage reconstruction.

## Sequence 333 — human-arms-locomotion — verified motion repairs; visual acceptance partial

The reported opening gate walk is reproduced in fresh authored shot 26. Hiro's
left wrist now follows the forearm instead of flipping upward; the elbow stays
beside the body. Cinematic fitting derives connected arm rotation from the solved
chain, constrains elbow planes, and bounds wrist bend separately from forearm
roll. Generated human palms follow the forearms while held weapons retain their
established axes. Gameplay retains full per-grip arm motion. Running has bent
elbows, opposed arm swing and a flight phase; player publication distinguishes
walk/run using character-relative horizontal speed. Cinematic movement selects a
run sequence when running is queued, retaining explicit authored animations and
fallback for classes without that sequence. Mishima and Usagi use their actual
rendered model's playback ranges. Five human NPCs receive refreshed idle/locomotion
on their admitted bind rigs; original authority intervals and events remain.

Evidence is local under `zig-out/reports/runtime-zig-333/`. The
`human-motion-review.html` page includes the owner's screenshot, the matching
rear gate capture, all five walk/run recordings, held weapons and paired model
contact sheets. The complete 102-model cinematic review inspects 206 paired
samples; five NPCs add 15. This is sampled deformation review, not full visual
acceptance of every clip or story scene.

| Scenario | State | Evidence and limits |
|---|---|---|
| Full opening and arrival | Passed within authored playback scope | `opening-gl2/result.json`: all 115 intro shots, seven e1m1a arrival shots, completed save/load and normal control on the final runtime. Ordinary dkguard software GL2. |
| Reported gate walk | Passed within sampled visual scope | `gate-walk-native/`: fresh opening, actual authored walking cameras; shot 26 at 8,000 ms matches the owner's rear view and shows the repaired wrist/elbow. `gate-replay-native/` and `gate-pan-native/` separately inspect restored gate dialogue and a complete camera pan. |
| Five multiplayer walk/run appearances | Passed within LAN scope | `network-run/` and `network-walk-fixed/`: Hiro, Mikiko, Superfly, Mishima and Usagi rendered remotely over UDP. Twenty samples each per mode; 24-frame walk and 15-frame run cycles at 30 Hz. Ordinary movement, fire, death/respawn, reconnect and restart checks also pass. Public-room acceptance is outside these runs. |
| Held sword/rifle/pistol | Passed within controlled grip scope | `held-weapons/`: real two-client remote ready and attack captures for Daikatana, Ion rifle and Glock. |
| Companion and five human NPCs | Passed within diagnostic scope | `companion-motion/` exercises live Superfly movement/save/load. `npc-native/` and `npc-dry-native/` exercise class-owned grounded fixtures and save/load for Cryotech, Mishima Guard, Fatworker, Skinnyworker and Surgeon; native loop mappings play at 30 Hz. Continuous campaign chase/navigation and every attack remain unqualified. |
| Asset preservation | Passed | `package-proof.json`: all 132 serialized IQMs compared; 115 motion outputs change, 17 remain exact. Vertex arrays, UVs, normals, weights, triangles, bind joints and parents stay exact for all 132. All textures, skins and model/physics mappings remain exact; all 15 character master inputs stay exact. |
| Aggregate checks | Passed | `aggregate-final.log`: 54/54 steps, 446/446 Zig tests, 193 Python tests and engine C contracts, including 21 anatomical/prop rig checks. |
| Reviewed installation | Passed | `install-final.json`: exact tested immutable generation active in native-dev and neural-monsters-dev, all 25 manifest files per prefix verified, 106 latest owner-state hashes exact, loose JapanDM preserved, launcher/main/online/previous generations exact. |

The installed development generation is
`6ac170908fc2ddd0a3b0536218b6349eb5e524857b49f8fc7a119cf9595c2825`;
the tested runtime identity is
`a9d6bbbc5a28a620d0e0bec883be5fbcaf955040513e1ba10c1b0fbd2893c5d0`.
The classic ZIP32 episode archive is 2,196,041,740 bytes, SHA-256
`59854041cfb853cc787a079efe593a13c0b87be33fdc3863dd66142604b3f564`.
Both development selectors use that exact tested generation; previous generations
and current owner state are preserved. An independently running launcher changed
the native selector and 14 save files during this pass; `concurrent-launcher.json`
records that change and the refreshed preservation baseline. Its dropped loose
JapanDM archive is restored in the installed native generation. Both canonical
install builds pass 43/43 steps, but picked up concurrent unrelated native/Lua
source edits and produced generation `8d61f363…`. `reviewed-activation.json`
records the locked atomic selection of the already staged, exact tested `6ac17090…`
generation. Concurrent source/build products and that unqualified generation stay
preserved. This sequence's aggregate/runtime evidence belongs to the tested
generation and does not qualify those unrelated later edits.

Earlier failed walk-driver filtering and the unavailable Python interpreter's
Pillow import remain recorded; the corrected walk probe and explicit system
Python aggregate pass. A rejected 34-unit run stride exceeded Superfly's existing
hip bound; the admitted 32-unit stride retains the flight phase and passes the
rig checks. No duplicate broad suite follows the valid final aggregate.

Open: Charon task/camera timing; cloth and extreme rolled/death pose fidelity;
Osaka/Casseti/Mikiko visual repair; full visual playback of every story scene,
hardware rendering and connected campaign completion. No facial morphs are added.

## Sequence 332 — cinematic-motion-publication — verified playback repairs installed; visual acceptance partial

The opening's reliable-command failures came from primary-world configstrings
bypassing the bounded regional publication stream. Primary updates now use that
stream too; repeated lightstyles coalesce and the four-command acknowledgement
window remains enforced. The engine retains the actual world registry for
gamestate/reconnection without also broadcasting ordinary `cs` commands.
Snapshots defer entities whose model or sound definition is still being published.
The separate transport flag preserves publisher visibility and collision links.
The actual server registry/broadcast C contract and native publication contracts
cover these boundaries. A fresh Superfly map exposed the missing primary snapshot
barrier; its original `InvalidSoundPath` failure is retained.

Two cinematic fits change. Ninja scale uses reviewed standing frame 143 rather
than a crouched reference. SHA-pinned anatomical source vertices keep torso
rotation from following the wrist during running/jumping. The female guard's
36 original short-blade triangles are recovered from the connected body and
attached as two independent weapons. Six ninja and four female-guard paired
frames were visually inspected against the original and exact serialized IQMs.
The final package contains those exact candidates; all 130 other IQMs, all master
geometry/atlases, both prisoners and model/physics mappings remain exact.
The 100 unchanged cinematic models retain sequence 330's sampled inspection.
Original frame/clip order and the approved artwork remain the input contract.

Cinematic performers now publish floor contact and ride moving brushes, including
borrowed actors. Pushing uses the cinematic rider's configured collision mask
instead of adding player-only clip geometry. A retained Charon trace records 511
blocked pushes before that correction; the final boat proceeds beyond the former
stall. Event-generator `cinetrigger`/`target` metadata no longer gets parsed as a
numeric timer; real custom delay fields remain strictly validated.

| Scenario | State | Evidence and limits |
|---|---|---|
| Complete opening and destination arrival | Passed within authored playback scope | `opening-final-runtime-gl2/`: final runtime, all 115 opening shots, actual handoff to e1m1a, all seven destination arrival shots, completed save/load and normal control. Ordinary guarded software GL2, without GDB. `opening-resource-barrier-gl2/` retains the earlier successful publication candidate replay. |
| Opening ninja performance | Passed within sampled visual scope | `opening-ninja-motion-gl2/`: eight in-shot captures spanning shots 95–100; paired review covers frames 12/46/85/143/150/162. Upright running torso/standing size repaired; cloth and legs still approximate the original. |
| Superfly full authored scene | Passed within diagnostic scope | `superfly-final-runtime-gl2/`: fresh map, diagnostic activation of the actual authored trigger, all 13 shots, cleanup and completed save/load. `superfly-resource-barrier-gl2/shots-contact.jpg` inspected. Copied historical active-save completion is separately retained; continuous rescue/current owner save acceptance is not claimed. |
| Copied historical active Superfly save | Passed within restoration scope | `superfly-historical-final-runtime-gl2/`: final runtime restores cursor 1, completes all remaining shots 1–12 and restores the completed scene with control released. Copied source save hash unchanged; no owner-state writes. |
| Charon arrival admission and boat motion | Passed within diagnostic scope | `charon-mask-final-gl2/`, `charon-all-shots-final-gl2/`: all 17 shots, completed save/load; recorded actor positions travel beyond the previous blocked push. Resident admission succeeds after event metadata repair. |
| Charon visual performance | Failed; further work required | All-shot native captures show the boat/actors in several views, but many cameras miss them and Hiro's queued movement trails the authored framing. Successful scene completion does not establish visual acceptance. |
| Episode-four boat arrival | Passed within diagnostic scope | `femaleguard-boat-final-gl2/`: all 19 shots, completed save/load; ten captures inspected, boat riders and arrival actors visible. This scene does not visibly exercise the repaired female guard's blades. |
| Female guard blade fit | Passed within serialized sample scope | Four paired frames 0/70/96/182 show both original short blades with independent hand attachment. Native blade scene remains unqualified. |
| GL1 opening regression | Passed within partial diagnostic scope | `opening-final-runtime-gl1/`: ordinary guarded software GL1 passes shots 10–18 beyond the prior overflow point. Complete GL1 playback remains unqualified. |
| Aggregate checks | Passed | `aggregate-resource-barrier-final.log`: 54/54 steps, 445/445 Zig tests, 190 Python tests and C contracts. Supersedes the aggregate before the primary snapshot barrier. |
| Authorized development installation | Passed within installation scope | `cinematic-user-install.json`: both development prefixes select the qualified generation; 25 manifest files verified per prefix, 106 owner-state hashes exact, launcher/main/online selectors and previous generation preserved. Native development's loose japanDM package survives activation. Both installs pass 43/43 steps. |

Episode package: 2,195,922,456 bytes, classic ZIP32, SHA-256
`e58108e57ef159b85003d8ab5c426b037f82e7a1dc5b9971a52d5c0769db52d6`.
Only two IQMs, four female-guard skins and the receipt change relative to 330.
Runtime/engine modules and compatibility records also change in the installation;
this is not an archive-only update. Installed generation:
`b895461e6ab7c59844540bac9d0b76c0adbca1a63b6cc9de86d98f8cac20ba6f`.

Evidence remains under `zig-out/reports/runtime-zig-331/`; sequence 331 in the
journal belongs to the concurrent japanDM task. See `cinematic-native-review.html`
for paired poses and actual native captures. Osaka/Casseti/Mikiko visual repair,
rolled/death poses, cloth, facial morphs, full visual playback of every story scene,
hardware rendering and connected campaign completion remain open. Engine runs
use dkguard `--headless` without `--gpu`. No Git operations.

## Sequence 330 — neural-visible-quality — reviewed replacements installed; cinematic acceptance partial

This is the historical checkpoint. Sequence 332 above supersedes its native
opening/Superfly playback failures and the two admitted ninja/female-guard fit
defects. Its other visual and campaign limits remain open unless qualified above.

The owner rejected the torn Toshiro forehead/neck, other facial artifacts and
cartoonish anatomy. Six dedicated reconstructions now replace Toshiro, Hiro,
Superfly, Usagi, Garroth and Charon heads with realistic proportions. Accepted
master concepts remain the style target. Closed geometry, local jaw/neck repairs
and anatomical head weights replace the failed portrait-fitting approach.
Five fixed mesh-conditioned camera guides paint separate 4096-pixel head atlases;
full combined-model depth limits projection visibility. Usagi's garment interior
uses a bounded two-sided collar painting exception. Body conversions remain
frozen parents, and the original joint/bind/frame channels stay exact.

Hiro's head is now 1.15 times the preceding replacement size. Eight actual albedo
and lit views and six serialized gameplay poses were inspected before admission;
the installed opening close-ups also show the larger head. Accepted body concepts
remain unchanged. Current front/quarter/both-side views and animated join reviews
identify each candidate by SHA-256. Admission copies those exact renders into the
gallery. All 37 masters and 11,458 frames pass the current structural/skinning
audit. The final aggregate passes 52/52 steps, 442/442 Zig tests, 173 Python tests
and C contracts in `aggregate-final-zip32.log`.
Duplicate gameplay pose blocks now share exact storage, keeping the high-detail
Superfly IQM within the engine's 16 MiB bound. Every named movement and attack
pose of the five gameplay masters remains bit-identical after serialization.

The cinematic fitter now keeps semantic head/torso/leg surfaces through source
deduplication, calibrates limbs from source anatomical landmarks and preserves
original prop rotations. Head orientation no longer follows an arm gesture.
Connected fixed-length IK constrains knees and ankles. Quantized hidden weapon
pieces and rigid long staffs are recovered; Toshiro's staff uses the standing
reference grip rather than a fallen wrist near the shaft end. Upright first poses
remain upright even when most source frames are recumbent. Source-pinned landmarks
restore Hiro's kneeling ending, and Charon's weapon is extracted from its connected
original hand mesh. Original clip/frame ordering and named hardpoints remain intact.

All 102 cinematic variants were rebuilt with matching skins. The paired review
viewer exports the original vertex animation and exact serialized replacement,
with every frame and clip available at a shared camera scale. Numeric joint-step
triage covers 55,604 frames and 2,081 clips, excluding clip boundaries. All 13
contact sheets were visually inspected: 300 samples cover every model's initial,
movement and flagged poses. This establishes sampled inspection of every model;
it does not establish full visual playback of every clip or native scene timing.

| Scenario | State | Evidence and limits |
|---|---|---|
| Six actual serialized face materials and motion | Passed within scope | `head-admissions.json`, per-actor `visual-review.json`, four albedo/four lit views and actual animated master renders. No facial morphs. |
| Current original image resolution | Passed | Head and body both upload at 4096 pixels. Fine faces previously occupied a small part of the whole-body atlas. Separate head atlases increase facial coverage. |
| Larger Hiro head | Passed within scope | `hiro-owner-size-admission.json`, `hiro-owner-size-eight-views.jpg`, `hiro-owner-size-gameplay-poses.jpg`; installed GL2 shot 14/15 close-ups inspected. |
| Toshiro/Hiro installed opening faces | Passed within sampled diagnostic scope | `installed-opening-heads-zip32-ack-debug/`: exact installed package, guarded software GL2 under GDB, shots 10–18 and animated samples. Hiro face/gesture and Toshiro shot-18 face inspected; both head images upload at 4096. This debugger replay does not qualify ordinary complete playback. Older direct previews remain identified separately. |
| All cinematic model sample inspection | Passed within scope | `all-cinematic-final-inspection.json`, `all-cinematic-sampled-review/`, `cinematic-pose-review.json`, `final-cinematic-candidate-proof.json`. All 102 models inspected in 300 paired samples; 2,081 clips receive numeric triage. |
| Usagi/Garroth authored scene samples | Passed within scope | `usagi-nomipmaps-paced-gl2/` confirms the affected Usagi face-filtering repair. `garroth-final-guarded-gl2/` shows authored scene samples from the earlier builder; final staff poses are reviewed in serialized samples. Complete native performances remain unqualified. |
| Superfly native movement, shadow and save | Passed within scope | `superfly-final-native-gl2/` direct isolated probe. Guarded copied active encounter captures show actual head motion, but the scene completion later exits on signal 4; completion is failed. |
| Charon native story presentation | Unverified | Diagnostic single-map scenes load the model/material but inspected authored cameras do not visibly show Charon. Serialized animated master review passes; actor binding/presentation does not. Resident-region admission also fails in the normal e2m2a scene. |
| Native filtering change | Passed within scope | `usagi-nomipmaps-paced-gl2/`: actual affected face/neck comparison inspected. Separate head shaders use `nomipmaps`; final installed Hiro/Toshiro retain sharp face detail. Body materials retain mipmaps. |
| Normal installed opening playback | Failed | `installed-opening-heads-zip32-gl2/` drops after shot 17 with “illegible client message”; `installed-toshiro-zip32-gl1/` drops during early practice with server-command overflow. The latter pending queue is dominated by ordinary `cs 29` lightstyle updates alongside bounded world patches. GDB does not reproduce the drop through shot 18; no playback repair or full-intro acceptance is claimed. |
| Remaining cinematic pose/prop repair | Open | Female guard weapon absent in affected samples; ninja crouched-reference size/airborne poses; rolled/death poses, torso lean, robes and cloth still approximate the original vertex performance. No facial morphs. |
| Remaining whole-gallery visual repair | Open | Osaka beard/hair shards, Casseti stretched beard projection and Mikiko style remain visible in the inspected side renders. They remain rejected, not visually accepted. |
| Final package and authorized installation | Passed within scope | `head-final-package.json`, `zip32-format-repair.json`, `head-user-install.json`; both development prefixes select generation `22352873871ec98a877aa919368ae48b05a45b40a6f609cc5ba7da28f46dc3e5`. Normal launcher remains guarded. Final install passes 43/43 build steps. Owner hardware testing is pending. |

Final episode package: 2,195,897,606 bytes, SHA-256
`cc2637bd3efcb4d3404c64d2312e965665c49e0f5f888407bafbb27906174267`.
It contains 132 IQMs: 110 character variants change and all 22 monster IQMs remain
exact relative to the fresh pre-repair package. Both prisoners, model/physics
mappings, engine, native modules, renderers and base content remain exact.
Only `share/dk3/zz-dk3-neural.pk3` changes in the installation. Previous generations,
package backups, owner state, launcher and preserved main/online selectors are
verified against `head-install.before.json` by `head-user-install.json`.

The first combined package crossed Python's conservative 2 GiB ZIP64 threshold.
The bundled ZIP32 reader misread the extra ZIP64 directory bytes and trapped while
listing shaders; the original failure and GDB trace are retained. The packager now
writes classic unsigned ZIP32 offsets below 4 GiB and rejects ZIP64 before admission.
All 939 reviewed payload hashes remain exact across this format-only repair.
Sparse-archive regression coverage exercises the actual boundary above 2 GiB.

Evidence and retained failures are under `zig-out/reports/runtime-zig-330/`.
New engine runs use dkguard `--headless` without `--gpu`; direct older preview
runs are identified separately. Full 115-shot intro, all story performances,
campaign completion, owner hardware rendering and higher-load software behavior
remain unverified. Both prisoners, previous immutable installations, owner saves
and preserved main/online installations stay protected. No Git operations.

## Sequence 329 — neural-face-quality — structural/scenario checks passed; visual acceptance reopened by 330

The close-up repair pass admits 19 closed-surface masters: the 15 character
identities and Mishima Guard, Fatworker, Skinnyworker and Surgeon. Their rebuilt
meshes and 4096-pixel atlases exactly reproduce the reviewed candidates. All 41
registered front/side views have a positive sampled Jacobian, with a minimum of
0.2377788665 on the 201-square grid. Topology and UV
checks pass; joint names, hierarchy, bind channels and animation channels are
unchanged, with zero measured frame-channel error. Both prisoners retain their
protected inputs and products.

The baker now rejects folded registrations, contributes no backward-facing camera
weight outside the named anterior orbital exception, and limits frontal eye
priority to measured anterior eye regions. Independent side portraits repair
ear/neck albedo. Corrected Tatsuo
glasses, jaw and collar landmarks remove the observed projected stripes. Candidate
and production evidence is under `zig-out/reports/runtime-zig-328/`, including
`texture-candidate-production-proof.json`, `registration-jacobians-final.json`
and `texture-quality-review/closed/`.

Packaging, isolated installation and serialized-pose review are complete. All
37 conversions retain their current products. The shared bounded baker also
refreshes Psyclaw's atlas while preserving its exact IQM and source texels outside
the face mask. Its refreshed eye/pose review and provenance are recorded separately.
The all-frame audit passes 37 masters and 11,458 frames; current render receipts
cover 217 sampled poses and 19 separately lit faces. Ten new independent side
portraits and their exact built-in imagegen prompts are recorded in
`texture-quality-review/closed/continuation-side-artwork.json`.

The isolated installation is
`d0d76e7161d12122ad295efa5948e2f0bfe67456112978e4d6a47fe82337354e`;
combined executable/module/asset identity:
`f159f7bccf495ac482c130e0117001156a9136fdabb14ae29b8fefa64a3c838c`.
Package: `zig-out/neural-monsters/episode1/dk3-neural-episode.pk3`,
1,875,536,283 bytes, SHA-256
`a3cce6c208de4e7977798ba2efd7959076ede55a48eb7990b2ff36466fde3ff1`.
It contains 132 IQMs: 110 character variants and 22 monsters. Compared with
sequence 328, 114 IQMs change and 18 remain byte-identical; the model/physics
mappings and both published prisoners remain exact. Executables, modules,
renderers and base content match the preceding qualified installation. At the
owner's explicit request, both `zig-out/neural-monsters-dev/play/current` and
`zig-out/native-dev/play/current` now select that installation. The normal `dk3`
command launches the native development prefix through its dkguard. The default
local neural-package selector also chooses this package for `zig build play`.
The previous native installation, preserved `zig-out/play/current` and
`zig-out/online/play/current` selectors, and all 120 snapshotted save/settings
files remain exact. Previous package and launcher bytes are retained; installation
proof is `zig-out/reports/runtime-zig-328/texture-user-install.json`. Owner manual
hardware testing is pending. No Git operations.

Evidence: `zig-out/reports/runtime-zig-328/texture-final-evidence.json`,
`texture-native-review.html`, `texture-native-executions.json`,
`texture-package-diff.json`, and per-case commands/inputs/captures/receipts.
All engine runs use dkguard, isolated profiles and `--headless` without `--gpu`.
GL2 qualification uses 960×540 captures with two software workers; GL1 uses
960×540 with eight workers. Controlled setup and ordinary resulting actions
remain recorded separately by the existing probes.

| Scenario | State | Evidence and limits |
|---|---|---|
| All episode-one monsters | Passed | `texture-all-monsters-gl2/`: all 22 skeletal actors render and restore, including the frozen prisoners and updated Psyclaw atlas. Controlled worlds; no full level route. |
| Guard death and default fragments | Passed | `texture-guard-body-gl2/`: ordinary Glock death, articulated contacts, sleep and alive restoration in e1m3b. `texture-guard-gibs-gl2/` verifies the default class gibs. `texture-guard-body-gl1-opening/` qualifies articulated death/restoration in e1m1a on GL1. |
| Five UDP character appearances | Passed | `texture-network-characters-gl2/` and `texture-network-characters-gl1-workers/`: real client/server admission, 15-frame gait at 30 Hz, moving/stationary attacks, complete deaths, respawn, retained bodies, sleep and cleanup for Hiro, Mikiko, Superfly, Mishima and Usagi. |
| Held weapons, carry and companion | Passed | `texture-held-weapons-gl2/`, `texture-carry-gl2/`, `texture-companion-body-gl2/`: sword/rifle/Glock grips and attacks, carried Mikiko performance, companion articulated death and actual alive save restoration. |
| Intro motion and close face views | Passed within scope | `texture-intro-motion-gl2-standard/`: practice motion, early camera angles and Hiro face burst, playback through shot 35 and mid-cinematic save/load. Full 115-shot intro remains unverified. |
| Saved Superfly encounter | Passed | `texture-encounter-gl2/`: ordinary trigger contact, all 13 authored shots, retained torture apparatus, active/completed restoration and player control release. Source autosave is copied and remains unchanged. |
| Aggregate and asset provenance | Passed | One `zig build test` aggregate: 52/52 steps, 442/442 Zig tests, 130 Python tests and C contracts. Exact candidate/production, registration, render receipts, package lineage, conversion retention and prisoner proofs pass. |
| Higher-load software profiles | Failed; unqualified | The 1920×1080 intro capture overflows reliable server commands. Initial GL1 firing/gait windows expire; e1m3b guard replays also overflow commands, and drop cleanup reports `StaleEntity` in the reduced-size attempt. These failed reports remain preserved; opening-map and standard-size passes do not qualify those paths. |

The structural and scenario receipts above remain available. The owner's later
close-up test reopens visual acceptance in sequence 330 above.
Full campaign, every story performance, hardware rendering, higher-load software
behavior and reliable-command drop cleanup remain open. Body collision remains
approximate; runtime materials use base color and have no facial morphs. Concepts
remain 1280 pixels. Earlier pod, Crox, robot and Venomvermin scenario evidence from
sequence 328 retains its exact runtime geometry/materials and engine/module inputs.

## Sequence 328 — neural-characters-episode1 — first integration verified; close-up repairs superseded by 329

The owner reopened visual acceptance after finding eye placement, texture stripes
and ragged surface edges. The package/scenarios below record the completed first
integration, not acceptance of those defects. Further surface and registered
material repairs are completed by sequence 329 above under
`zig-out/reports/runtime-zig-328/texture-quality-review/`; the installed package
remains available as historical evidence.

The local pipeline photographs admitted original models, records reviewed detailed
concepts, runs the pinned TRELLIS.2 deployment on the RTX 5090 and converts the
inferred bodies to textured IQM. Its 37-master roster includes all 22 episode-one
monsters, the five established characters and ten additional story identities.
The prisoners retain their exact protected chained performances. Suitable bipeds
use the shared anatomical character rig and new motion; creature trajectories
retain authored frame/event intervals. Character variant construction preserves
cinematic props, hardpoints, carry performance, moving weapon stances, team skins
and face tint protection. Humanoid and generic creature physics use native Zig.

Completed: 35 new reconstructed masters and two protected prisoners; 132 published
IQM variants (110 character performances/appearances and 22 monsters). The final
structural audit checks 37 masters and 11,458 frames. Asset review records 217
sampled poses, 20 registered face/eye edits and 19 lit face reviews. Local deployment,
capture/concept intake, reconstruction, conversion, review, packaging and replay
instructions are in [the pipeline documentation](neural-monsters.md).

Visual repairs include neutral torso centering, source-faithful guard identity,
standing Toshiro alignment, robot frontal polarity, continuous robe hems and
released hands, rigid pod petals, measured mechanical arms, connected Venomvermin
quadruped motion, UV-seam welding before decimation, bounded face re-registration
and valid serialized lighting normals. The two face shapes that exceeded the seam
registration bounds received fresh registered edits. Normal reconstruction changes
only IQM normal/tangent arrays; binary proofs retain the other geometry/motion bytes.
The bundled engine's cumulative file-read counter now uses unsigned 64-bit
accounting: repeated large-package restoration previously overflowed its signed
32-bit counter and trapped in ReleaseSafe. Game/client/UI behavior remains Zig.

Final isolated installation:
`b39371cb7fb58d6c4a57b3c88af78c3061b5875da7b1770bf1b7b3e4138099a2`;
combined executable/module/asset identity:
`79582fa0f439d63a0ab768c1cdbe1ab155c0e98629fe971095322239d1bf9c08`.
Package: `zig-out/neural-monsters/episode1/dk3-neural-episode.pk3`,
1,874,338,862 bytes, SHA-256
`e58e1d7ca38e82b734032f328445c8547b0ae829704918d736dc563b625cf7c0`.
The current link now selects the sequence 329 installation above.
The preserved installation and original save remain untouched; no Git operations.

Evidence: `zig-out/reports/runtime-zig-328/final-evidence.json`, `native-review.html`,
per-scenario inputs/captures/receipts, and `zig-out/neural-monsters/verification/`.
All engine runs use canonical dkguard, isolated profiles and `--headless` without
`--gpu`. Controlled spawning, facing, health/equipment and fragment suppression are
recorded explicitly. Ordinary attacks, native animation events, contacts, respawn
and actual save/load provide the resulting behavior.

| Scenario | State | Evidence and limits |
|---|---|---|
| All episode-one monsters | Passed | `all-monsters-final-gl2/passed.json`: all 22 installed skeletal models render, each from an independently restored controlled world. Includes the two frozen prisoners. No full level route acceptance. |
| Living guard, body and default gibs | Passed | `guard-body-seams-gl2/`: ordinary Glock death with fragments disabled, 30 joints, 23 samples, 5,707 contacts, sleep and alive restore. `guard-gibs-seams-gl2/` separately verifies default class gibs and corpse retirement. |
| Generic Crox body | Passed | `crox-body-seams-gl2/`: seven joints, 23 samples, 98 contacts, sleep and alive restoration. |
| Mechanical bipeds | Passed | `sludge-body-seams-gl2/` and `rage-body-seams-gl2/`: 28 joints, 24 samples each, ordinary death and alive restoration; 10,313/3,518 contacts. Ragemaster sleeps; Sludgeminion is still awake at the end of this short sample. |
| Connected Venomvermin quadruped | Passed | `venom-body-final-gl2/`: 16 joints, 22 samples, 7,406 contacts, sleep and alive restoration. New run/strike pose reviews retain source event intervals; all-frame edge-stretch p99 is 1.92. |
| Protopod and mechanical mosquito | Passed | `pod-hatch-opening-gl2/`: grounded visible pod 343 in e1m1a hatches the separate `monster_slaughterskeet` actor 345, loads its own IQM, and records 12 hatch views. Existing hatch timing and child gameplay remain authoritative. |
| Five multiplayer characters | Passed | `network-characters-final-gl2/result.json`: two real UDP clients; Hiro, Mikiko, Superfly, Mishima and Usagi have 15-frame gait at 30 Hz, moving/stationary attacks, complete death playback before respawn, retained bodies and sleep. Final contacts are 2,462/3,023/2,360/3,020/1,979. Disabling ragdolls clears retained presentations. Four recorded map restarts use the same authored spawn for each appearance. LAN lifecycle checks also pass. |
| Held weapons and carry | Passed | `held-weapons-seams-gl2/`: remote sword, rifle and Glock grips/attacks. `carry-seams-gl2/`: carried Mikiko/Superfly performance, movement, shadows and alive save restoration. |
| Companion death/restoration | Passed | `companion-body-opening-gl2/`: ordinary Glock kills Mikiko; 30 joints, 24 physical samples, 2,960 contacts and sleep. Actual load restores her alive and clears the corpse. Collision-checked observer placement and torso aim are recorded. |
| Intro practice/dialogue | Passed within scope | `intro-motion-seams-gl2/`: Hiro/Usagi models, practice motion bursts, sampled poses through shot 35 and actual mid-cinematic save restoration. The complete 115-shot intro and all story performances remain unverified. |
| Saved Superfly encounter | Passed | `encounter-seams-gl2/`: copied autosave, ordinary trigger 50 contact, all 13 authored shots, original torture apparatus retained, active/completed scene restoration and player control release. Later rescue/full campaign remain unverified. |
| Final package lineage | Passed | `verification/package-quadruped-diff.json`: final correction changes only Venomvermin IQM and the manifest; all other 131 runtime models, textures, skins, shaders and physics mapping match the seam-qualified package. Engine/modules/base content also match the earlier passing scenario identities. Thus unchanged affected scenarios retain their exact qualified assets. |
| Broad aggregate | Passed | `aggregate-final.log`: 52/52 steps, 442/442 Zig tests, 125 Python tests and C contracts. Contracts cover anatomy, mechanical/pod rigidity, quadruped event/length preservation, bounded face registration, lighting-only byte changes, missing normals, frozen prisoners, stage invalidation and strict package reuse/admission. |
| Protected assets/state | Passed | `verification/protected-final.json`: prisoner inputs, concepts, prompts, conversion metadata, IQMs and atlases are unchanged; published prisoner meshes/atlases match. Source autosave SHA-256 remains `6241cc17800ea58c99d293e16173bb0f9163b6ce890b6434e591540d97b7355d`. |

Earlier failed diagnostics remain visible. The e1m3b pod fixture lacked authored
air routes for the child's later retreat; the successful replay uses e1m1a. An
intermediate `e1m1` spelling was not an installed map. The e1m3b companion fixture
lost its shot lane behind a pillar and a subsequent low-health ally could be killed
by surrounding enemies before the observer's shot; the isolated opening fixture
qualifies ordinary fire and restoration. A wall/stair-adjacent multiplayer Mishima
body remained awake after 8.4 seconds. Equal-spawn replay settles all five rigs;
general settling at that earlier placement remains a known physics limit. None of
these failed runs is counted as a passing complete scenario.

Physics is cosmetic and collision volumes approximate the skinned bodies. Exact
cloth/triangle/body-to-body collision, persisted physical poses, every placement,
all cinematic performances, full campaign and hardware rendering are not qualified.
Concept output is 1280 pixels despite the requested 2048; generated GLBs retain
4096-pixel PBR atlases, while runtime materials use base color and no facial morphs.

## Sequence 327 — skills-attachments-corpse-physics — verified on focused saved and multiplayer scenarios

Fresh multiplayer advancement starts with all five attributes at zero for every
appearance. Earned advancement still survives respawn. Timed skill pickups expose
level five through the shared character rules, movement parameters and HUD, without
changing permanent attributes; their existing expiry remains intact.

Attached models now sample their parent's pose at render time using persistent
parent/world identities, including nested attachments. Tossed pickups recover a
partly embedded hull before settling, keep the precise contact point, and follow
moving supports. Grounded pickups no longer repeatedly restart their gravity path.

Weapon damage carries cumulative, sequenced body impulses in snapshots. Dead players
and retained multiplayer bodies remain damageable, with score/death processing only
once. Respawn retains the same body identity in an ordinary entity slot. Powerful
lethal hits, substantial lethal explosions and sufficient overkill produce flesh
fragments, and fragmented bodies retire their cosmetic ragdolls. Body solvers inherit authoritative velocity, release
joint constraints gradually, and wake on localized subsequent impulses. Projectile
splash now admits dead bodies and uses the blast direction without duplicating the
shared death impulse. Console suicide retains its ordinary ragdoll path.

Engine and native entity delta schemas advance together to protocol 1351. Matching
client/server builds are required. Generated room compatibility metadata now uses
the same protocol instead of the stale 1349 literal. Original saves remain compatible;
source saves and the preserved installation are untouched. All runs use dkguard, copied state,
isolated profiles and software rendering. No Git operations or service deployment.

Final installation used by `zig build play`:
`81687de5a239474418de2ff1240c08e8f88d79d95733f1386d1e68ff18a6d49a`;
combined executable/module/asset identity
`d6d73498e12c6414fa05d1aa289e9ceeb2b43455174b637bad6023b32f4db0f1`.
Earlier focused scenario identities remain recorded in their own evidence files;
final refresh adds the matching protocol metadata and a test-literal correction.

Evidence: `zig-out/reports/runtime-zig-327/`. Reproducible scenario driver:
`dkq3/tools/runtime_physics_repair_probe.py`. Diagnostic placement, elevated health,
equipment and spawned pickups are recorded; contact, button use, attacks and respawn
use ordinary client input. These are focused defect checks, not continuous campaign
acceptance.

| Scenario | State | Evidence and limits |
|---|---|---|
| Five full-bar single-player pickups | Passed | `skills-final-gl2/` and the later `skills-admission-gl2/passed.json`: ordinary contact fills all five bars; inspected capture shows five segments per bar; save/load retains active boosts; expiry restores permanent zero attributes. |
| Autosave lift attachment | Passed | `saved-gl2/` and `saved-final-gl1/`: copied e1m3b autosave, ordinary t478 button use; 188.9/186.2 units of lift travel, zero X/Z offset range, three units of the button's own Y travel. Saved state reloads; original autosave hash remains `6241cc17800ea58c99d293e16173bb0f9163b6ce890b6434e591540d97b7355d`. |
| Grounded pickups near autosave | Passed | Same runs: four visible grounded pickups, including the health pack, show zero sampled position range. More maps/support geometries remain unverified. |
| Multiplayer skills, deaths and corpse hits | Passed | `network-final-gl2/` and `network-friction-gl1/`: two real UDP clients, zero bars across all five character selections; ordinary speed pickup fills the bar and expiry returns it to zero. Glock death produces an articulated body; respawn retains its identity; a later Glock hit wakes and moves it (GL1 pelvis displacement 0.573 units). Sidewinder hits fragment both the retained body and a living player; corpse hits do not award another kill. Screenshots inspected. |
| Single-player companion and restore | Passed | `companion-ragdoll/passed.json`: ordinary Glock fire kills grounded Mikiko, her bone solver settles with world contacts, and actual load restores her alive and removes the dead presentation. Existing fixture/movement/shadow captures retained. |
| Installed multiplayer checkpoint | Passed | `installed-network-gl2/result.json`: all multiplayer checks pass on the final play installation; combined identity matches the recorded installation identity. |
| Broad aggregate and focused repair | Passed | `aggregate.log`: all other targets pass (227 Zig tests, 113 Python tests and C contracts); runtime-root compilation caught an ambiguous new test literal. After its correction, `runtime-repair-checks.log` passes 64/64 steps and 302 runtime/catalog tests. There are 442 distinct Zig tests across these results, with the 87 catalog tests counted once. No duplicate whole-suite rerun. New contracts cover full-bar expiry, zero MP advancement, nested attachments, gib policy, corpse damage without another kill, gradual pose release/waking, and retained-body native save admission/rebasing. |
| Preserved state | Passed | `original-save.json`: original autosave is byte-identical. No Git, preserved-installation, or external-service mutation. |

The articulated bone solver remains cosmetic, with an approximate authoritative
corpse hull. Exact bone hit locations, identical articulated trajectories on every
client, all weapons/materials/maps and hardware rendering are not qualified here.
The sandbox-only first renderer launch could not connect to X11; approved virtual
display runs succeeded. `skills-gl2-approved/` retained a failed pickup setup after
the path reached a wall. The corrected driver returns to a known grounded origin
before each actual pickup; no attribute grant is used. `network-gl2/` exposed
the lethal-explosion threshold edge case (68 damage left −38 health without gibs);
the repaired weapon policy qualifies substantial lethal explosive hits. Its final
replay fragments that case. `network-final-gl1/` measured movement below an imposed
one-unit handgun slide threshold; floor friction arrested the body after a real
response. `network-friction-gl1/` checks motion above diagnostic resolution instead
of prescribing a fixed displacement for every weapon. Failed setup/assertion evidence
is retained and is not included in the passing results.

## Sequence 326 — superfly-encounter-prop — verified on the saved encounter

The owner's screenshot from reaching Superfly in e1m3b was reproduced through
ordinary contact with encounter trigger 50. The cinematic camera was looking
through giant limbs because the cosmetic package replaced the torture apparatus
`models/e1/d1_supertorture.dkm` with a generated Superfly body. The character
classifier admitted this multipart prop as a humanoid, and fitting to the whole
device produced a body with Z bounds −34.005 to 459.499. The converted apparatus's
own bounds are −23.726 to 106.274. Neither the authored camera nor the player's
death state caused this view; the player is alive and frozen for the scene.

The classifier now leaves this device with its converted prop geometry. Package
admission rejects that invalid body substitution, and the package tool can prune
it from an existing local overlay without refitting other performances. The
installed local overlay was repaired: its faulty IQM and four skins are removed,
the manifest/report hashes are refreshed, and all 594 other non-manifest entries
remain byte-identical. The original converted model package is unchanged; the
old local cosmetic overlay is retained in the report directory. Native movement,
actor placement, authored camera paths and saved model identities are unchanged.

Installed build
`925b35601295734af913ac3e57c14dd55e39cf2554b91107b6665ed2ac4dd7d9`;
combined executable/module/asset identity
`060db5bdb0e15f70909b02b9cb27352a44e2ae6f4c6b9c344e5778e20d15be13`.
Evidence: `zig-out/reports/runtime-zig-326/`. Driver:
`dkq3/tools/runtime_superfly_cinematic_probe.py`, through dkguard with isolated
profiles and software rendering. `zig build play-install -j8` refreshed the
installation used by ordinary `zig build play`.

| Scenario | State | Evidence and limits |
|---|---|---|
| Reported giant limbs | Expected defect reproduced | `encounter-before/`: prior installation and copied autosave; actual forward contact removes the first decorative stand-in and starts `e1m3_cinemid`. First-shot captures reproduce the supplied view; generated prop height exceeds 400 units. |
| Corrected encounter view | Passed | `encounter-final/`: inspected first-shot captures show the apparatus in place of the giant body. The apparatus remains an authored world entity; the trigger removes `superdeco` as authored. Subsequent Hiro/Superfly shots also captured and sampled visually. |
| Entire encounter and restoration | Passed | `encounter-final/passed.json`: all 13 encounter shots observed; saving/loading within the active first shot retains frozen viewer ownership and the corrected view. Natural completion returns normal control; saving/loading the completed encounter keeps it completed. Diagnostic placement outside the trigger, ordinary forward contact, original saved health/difficulty/inventory. This is the encounter cinematic, not the later four-shot rescue or full campaign. |
| Cosmetic package repair | Passed | `package-repair.json`: removes only the faulty prop IQM/four skins and updates the two manifests; 594 other entries match the old overlay byte-for-byte. Corrected overlay passes normal package admission against the same converted models. Old overlay retained as `neural-before.pk3`, local assets only. |
| Broad checks | Passed | `aggregate.log`: 52/52 steps, 435/435 Zig tests, 109 Python tests and C contracts. The new package regression rejects the invalid override, repairs a local overlay, and verifies unrelated performance bytes and admission integrity. |
| Original save | Passed | `original-save.json`: source autosave hash unchanged. No Git operations or preserved installation/main changes. |
| Other props/cinematics | Unverified | This repair excludes the identified multipart apparatus. It is not acceptance of the full cosmetic model classification or cinematic catalog, all facial performances, the later rescue sequence, or hardware rendering. |

## Sequence 325 — saved-button-travel-and-lift-carry — verified on copied Solitary saves

The fixes in sequences 323–324 did not repair existing native saves. The owner's
`save2.sav` still contained the old travel endpoints for all 25 e1m3a buttons;
`autosave.sav` retained them for all 14 e1m3b buttons. Restoring the saved mover
replaced the corrected fresh-map component, so a flush panel still travelled two
units behind its wall. Admission now recognizes that old hull-based formula,
repairs the endpoints and remaps the saved pose and trajectory together. A
`travel_version` marker makes this idempotent. Already-correct markerless saves
keep their endpoints; used latches, target delivery, travel timing and dwell
remain saved state. Explicit platform heights and angular travel stay intact.

Lift prediction had two faults. The server's pusher had already carried the player
to snapshot time, but command replay carried that origin again and tested against
brush geometry at render time. Replay now uses the snapshot's committed geometry,
then adjusts grounded presentation once from snapshot time to render time, including
render frames before the newest snapshot. Separately, a platform catching a falling
stationary player could turn a tiny outward collision residue into the full falling
speed upward. Ground movement now discards that residue when there is no tangential
motion. An engine replay measured the former −79 → +79 velocity reversal and lost
ground contact; the repaired landing keeps vertical velocity zero. Existing bundled
movement differential cases still pass; the new stationary-support case explicitly
corrects this edge case rather than asserting reference parity for it.

Saved movers also lacked the later authored audio fields. Restoration now resolves
those fields against the saved resource registry, with the active world's bindings
published before the initial gamestate. Leading slashes in authored sound paths are
normalized: restored resident maps exposed `sounds//doors/...` causing media admission
failure. Mixer audibility is **unverified in these saved-game runs**: ordinary load
disables cheats, so `s_show` rejects channel inspection. Sound dispatch and persisted
bindings alone are not evidence that a sample was heard.

Final play installation:
`d61c5af7426f2faccf5939b8f5e66735743dd525662c5cb88a05d84358e92109`;
combined executable/module/asset identity
`b6645c24846cf38389c047c0c3eea535d9049fb0d9225eeda58554d26549fcfe`.
`zig build play-install -j8` refreshed the isolated installation used by
`zig build play`. Evidence is under `zig-out/reports/runtime-zig-325/`;
the reproducible driver is `dkq3/tools/runtime_saved_mover_probe.py`.

| Scenario | State | Evidence and limits |
|---|---|---|
| Old saved endpoints | Expected defect reproduced | `saved-before-101/`: previous sequence-324 installation restores all 25 incorrect e1m3a button endpoints; flush terminal 101 still travels two units. This run's immediate pressed capture used the terminal's remote camera and does not prove disappearance visually. |
| e1m3a saved buttons | Passed | `save2-verified/`: all 25 endpoints match authored travel; ordinary use of flush terminal 101 keeps its face visible, including after actual save/load. The permanent used latch stays open and audio binding is retained. Captures inspected after the authored remote camera returns. Diagnostic placement, original saved inventory/difficulty. |
| e1m3b saved buttons | Passed | `autosave-verified/`: all 14 endpoints match; ordinary use of panel 357 leaves the triangle visible, also after save/load. Press travels three units rather than five. Captures inspected; restored press binding and sound dispatch recorded, audibility unverified. |
| Saved platform ascent and landing | Passed | `save2-verified/lift-frames.json` and `view-summary.json`: 751 rendered frames, 743 supported rider frames, zero feet/deck or camera/deck range and no authoritative-ground loss, including initial landing. 717 supported frames precede snapshot time. Living rider contact renews this platform's upper dwell; this is ascent/dwell acceptance, not a descended cycle. |
| Saved large lift ascent/descent | Passed | `save2-verified/big-lift-frames.json` and `view-summary.json`: 2,180 supported frames, 169 rising and 156 falling samples; feet/deck and camera/deck range below 0.0003 units, zero lost ground. Button 110 is pressed with ordinary use; elevated player health permits observation amid Inmater attacks. No trajectory or geometry fixture. |
| Fresh platform ascent and dwell | Passed | `fresh-lift-final/`: 705 rendered frames, 658 supported, 43 rising samples, zero camera/deck and feet/deck range, zero lost ground. Elevated health keeps the observation alive. The platform correctly holds its upper dwell while touched. |
| Broad checks | Passed | `aggregate-landing.log`: 52/52 build steps, 435/435 Zig tests including 208 runtime checks; 108 Python tests and C contracts pass. Compiler-cache writes initially failed in the sandbox; approved runs succeeded. |
| Preserved saves | Passed | `original-saves.json`: both source saves remain byte-identical. All engine runs use dkguard, isolated profiles and software rendering. No Git operation, main merge, preserved installation or service change. |
| Other mover/save cases | Implemented; unverified in engine | Recognized translating-door and implicit-platform save travel is admitted by the shared migration; other maps, parent-rotated saves, every mover class and hardware rendering are not qualified by these cases. Full campaign acceptance remains open. |

Failed setup and intermediate evidence is retained. `saved-final-101/` exposed the
leading-slash resident-media fault; `save2-final/` captured the actual landing bounce
before repair. `save2-landing-final/` passed the repaired panel and platform, but its
large-lift placement landed on the raised button instead of the deck and the player
died during the wait. The corrected fixture clears that button's hull and records
elevated health. `fresh-lift-verified/` crossed into the death camera, invalidating
its camera range; `fresh-lift-living-verified/` incorrectly required descent while
living contact held the platform open. Neither is accepted as a living full-cycle
test. Earlier `--audible` failures were unavailable cheat-protected instrumentation,
not demonstrated mixer silence. The final rows above supersede those outcomes and
the earlier saved-game/living-rider acceptance claims.
An additional `autosave-before-defect/` visual comparison could not start because
the previous immutable installation had been removed during subsequent installation
refreshes. It supplies no old-panel visual acceptance; the original expected-defect
endpoint report and final inspected panel captures remain the recorded evidence.

## Sequence 324 — Authored mover motion, settling and looping audio — verified on Solitary

Sequence 323 made the buttons of "Solitary" (e1m3a) audible and stopped them sinking into the
wall, and recorded the rest of mover audio as unread. This sequence reads that remainder: the
motion pair `sound_opening`/`sound_closing` and `sound_up`/`sound_down`, the settling pair
`sound_open_finish`/`sound_close_finish` and `sound_top`/`sound_bottom`, the authored loudness and
attenuation keys, and the looped form of a motion sound. Across the 84 converted maps 900 brushes
author `sound_opening`, 622 `sound_closing`, 551 the open-settling key and 508 the close-settling
key; 23 platforms use the up/down pair and 20 of those the top/bottom pair; the loop spawnflag sits
on 297 sliding doors, 110 rotating doors and 55 trains. Trains stay silent by authoring intent: no
reference train source reads any of these keys, so nothing is lost by not reading them here. The
door family and the platform family share one pair of slots, so a brush needs only the spelling its
classname uses. Authored `volume`, `min` and `max` reach the mixer when present and the ordinary
attenuation distances otherwise, which are also the distances the reference uses when a mover
authors none.

Two defects stood between those keys and the player's ear, and neither was about reading them.

A settling sound was started at the middle of the brush that owns it, which for a sliding panel is
inside the wall pocket it vanishes into. The server assembles each client's snapshot from the
potentially-visible set, so an entity outside that set is never transmitted at all, and the event
disappeared before any client could weigh it: a door closing behind the player, or one whose
settled position sits in a pocket the player cannot see into, was silent while the same brush's
start sound, emitted before it moved, came through. Sound events are now broadcast to every client
and the mixer decides audibility from the emitter distance, which is what the engine's own sound
entry point did before the native runtime replaced it. The position stays on the event; only the
visibility test moved to where the listener is. That is also what the reference produced, so a busy
scene now sends every sound to every client and lets the mixer discard what is too far away: no run
here came near the snapshot limit, and none reported an overflow.

A looping motion sound cannot ride the brush it belongs to. Compiled inline brushes here keep their
own world coordinates and leave the entity position at the map origin, so a loop offered on the
brush entity is heard from the origin of the level, and every looping mover sound in the game was
inaudible wherever the player actually stood. The reference reaches that same sample through the
entity's sound origin, which in its build is the middle of the brush. Motion loops now travel on a
carrier entity of their own, placed at the audible middle of the brush's committed bounds, following
the brush's own trajectory and withdrawn the frame the brush settles — the convention the authored
ambient emitters already use. `Mover.loop_carrier` names the carrier and is transient: a mover
restored in mid-flight simply regains one on the next frame, and a carrier whose mover vanished is
collected by the ordinary event expiry. The mover diagnostic reports `loop_offer` and `carrier`
rather than a loop flag on the brush, which is what the numbers below come from; the probes under
`dkq3/tools` read only the fields ahead of those, so they were unaffected.

`zig build test -j8` exits 0 with 204 runtime checks passing, one new among them: it pins that a
carrier starts at the middle of its brush, tracks the authored travel, and stops with the settled
brush rather than drifting past it. That check failed when first written, because the authored
travel of that brush is its extent minus the lip, not its thickness. Evidence is under
`zig-out/reports/runtime-zig-324/`, produced by build
`54ad4da4f8880812bc56e10625082b03d62d8d08f31efb12e105ea73a8ebd9a6` through dkguard with isolated
profiles; the preserved installation and saves are untouched. The drivers are kept in `tools/`.

Audibility is read from the mixer itself rather than from the sound-start trace: with `s_show 2` the
engine prints every audible channel each mixing frame, and a local addition (see the deviation row)
makes it report looping channels too, which stock reporting omits — without it a loop can only be
shown as submitted, never as heard.

| Scenario | State | Evidence and limits |
|---|---|---|
| Looping door (loop spawnflag) | Passed in engine | `mixer/mixer.json`, `mixer/mixer-report.txt`: while door 28 travels on button 27, `sounds/doors/e1/hydrolic2loop.wav` is reported as a looping channel on 245 mixing frames, peak 118 against the mixer's 127 master, carried by one entity throughout (`loop_offer=4`, `carrier=770`); `sounds/doors/e1/hydrolic2end.wav` then settles the open end. |
| One-shot door | Passed in engine | `sounds/doors/e1/celldoor1openloop.wav` mixed on 42 frames and `sounds/doors/e1/celldoor1openend.wav` on 20, with no loop offered and no carrier for door 259 — the unlooped form plays once per transition. |
| Authored lift platform | Passed in engine | Mover 19 (`func_plat`, height 120, speed 200) cycled closed → opening → open → closing → closed with the player riding it (ground entity 71 throughout): `sounds/doors/e1/lift1loop.wav` as a looping channel on 73 frames, on one carrier for the rise and a second for the fall (`carrier=803`, then `810`), and `sounds/doors/e1/lift1stop.wav` at both ends of the travel. |
| Settling sounds reach the player | Passed in engine, defect-driven | All three settling sounds above are heard from the settled brush, two of which sit inside their wall pocket. Before the broadcast change none of them reached the client at all, although the same brush's motion sound did. |
| Sequence 323 regressions | Passed | `sound/sound.json`: press audio still starts for buttons 75, 268 and 435. `travel/travel.json`: all 25 authored buttons match extent-minus-lip, mismatches 0. |
| Unit coverage | Passed | 204 runtime checks, exit 0, including the new carrier-trajectory check. One stray `failed command:` line still appears beside the ragdoll test's own raw diagnostics. |
| Engine fork deviation | Implemented, owner review requested | `tools/mixer-probe.diff` adds looping channels to the `s_show 2` debug report in `engine/ioquake3/code/client/snd_dma.c`, three lines, debug output only. Stock reporting cannot show a loop being heard, and a verification aid that is thrown away leaves no reproducible evidence behind. Revert it if the fork should stay closer to upstream. |
| Authored loudness on a mover | Implemented, not exercised | `volume`/`min`/`max` are resolved and sent on both the one-shot and the carrier path, but the movers driven here author none of them, so the authored values were not heard in engine. `func_train` also ignores them in the reference. |
| Rotating-door loop flag | Not exercised | The rotating-door loop spelling is read, and maps author it, but no rotating brush with it was driven in this run. |
| Save during a travel | Not exercised | A mover restored mid-travel resumes its motion but not its loop until the next transition; the carrier itself is never restored, by design. |
| Channel choice | Differs from reference | Motion and settling sounds use the automatic channel; the reference forces its own override channel, which this engine's sound interface does not offer, so two sounds can now share a brush where the reference would have cut one off. |
| Secret-door step lengths | Unchanged, approximate | As recorded in sequence 323: the reference drives that brush from an authored distance rather than brush size, and that path was deliberately left alone. |

## Sequence 323 — Solitary mover audio, button travel and ridden-lift camera — two verified, one sampled

Reported while playing the first chapter ("Solitary", e1m3a): wall buttons disappeared when
used, buttons and wall terminals produced no sound, and standing on a lift that travels
up or down made the view twitch.

Silence had two independent causes. The authored press and pop-back keys on a button were
never read anywhere in the runtime, so nothing was registered or started; and even once
registered, a brush entity's own origin is model-local, so an event placed at the entity
origin lands at the map origin, while one placed at the brush's audible centre but addressed
to a listener position is dropped by the audible-set filter — a player standing 56 units in
front of a panel heard nothing. `src/runtime/server/movers.zig` now resolves those two keys
through the map sound registry into two fields on the mover component
(`src/runtime/domain/movers.zig`) and starts them from the centre of the brush's committed
world bounds on the broadcast path. Archives written before the fields existed stay silent,
which the new `domain/snapshot` test pins.

The disappearing panels were a travel-distance defect. Mover travel is the brush extent along
the movement axis minus the authored lip, but that extent was taken from the clipper's hull,
which widens every inline brush by one unit per side; the reference server state derives its
mover size by contracting the loaded model hull by exactly that amount so that authored lips
behave as written. Every one of the 25 buttons on this map therefore pressed two units deeper
than authored, and six of them are authored with lip equal to their thickness, meaning they
were built not to move at all — those sank behind the wall surface and vanished. Travel now
uses the authored extents. `src/runtime/root.zig` also imports `server/movers.zig` for test
collection, because its checks had never been reachable.

The twitch was a prediction gap, not a mover defect: the server carries a rider positionally,
but client prediction had no notion of ground-mover motion, so the camera advanced at snapshot
rate while the ridden brush is trajectory-evaluated every frame. `src/runtime/client.zig` now
carries the ridden brush's trajectory inside each replayed command.

`zig build test -j8` exits 0; 203 runtime tests pass, including three new ones. Its progress
output still prints one stray `failed command:` line beside the ragdoll test's own raw
diagnostics; running that test binary directly reports `All 203 tests passed` with status 0.
Evidence is under `zig-out/reports/runtime-zig-323/`, produced by build
`c971f00b83361242f81073cccc435273cc072fcadf6a2147572da96690b80764` through dkguard with
isolated profiles; the preserved installation and saves are untouched.

| Scenario | State | Evidence and limits |
|---|---|---|
| Authored press and return audio | Passed in engine | `sound/sound.json` with `s_show 1`: `sounds/global/b_009.wav`, `sounds/doors/e1/button1in.wav` and `sounds/global/b_010.wav` start with the player 56 units in front of buttons 75, 268 and 435, and button 268's `button1out` follows after its dwell. The weapon-fire control line did not appear in the final run, so the channel proof rests on the button lines themselves. |
| Travel of every authored button on the map | Passed | `travel/travel.json`: all 25 `func_button` movers match the authored extent-minus-lip vector exactly (25/25, mismatches 0), taken from the map's own model bounds. Before the change all 25 were two units deep on the moving axis. |
| Panel stays visible while pressed | Passed, inspected | `visual/`: before/open/hold/after captures for buttons 27, 47 and 75 plus the pre-fix pair for 27, where the panel was gone. The drawn-brush count stays at 34 and 41 across the use, so the brush is still being drawn rather than culled. |
| Riding the authored lift | Sampled, not frame-complete | `lift/camera-series.txt`: 90 camera reports across 24 distinct rendered frames, monotone +79.3 units, one zero-motion frame and no reversal beyond two units; the earlier snapshot-rate staircase is absent. One +16.4-unit step at the ride boundary is unexplained — a per-frame comparison against the brush needed a temporary client probe that has since been removed, so no before/after exists on this build. |
| Unit coverage | Passed | 203 runtime tests, including authored travel from a real hull, a zero-travel button, silent pre-audio archives, and the newly reachable `server/movers.zig` root. |
| Other authored mover audio | Not implemented | `sound_opening`, `sound_closing`, the open/close finish pair and the train/platform up/top/down/bottom set are still unread, as are looping mover sounds. Buttons are the only class that emits. |
| Secret-door step lengths | Unchanged, approximate | `func_door_secret` still measures the spread hull, and the reference drives that brush from an authored distance rather than brush size. Left alone deliberately; not re-measured. |

## Sequence 322 — multiplayer bot skill ladder and field of view — implemented; unverified

Bots in a multiplayer match played at maximum strength: target choice ignored facing,
the commanded view snapped onto the enemy centre on the acquiring tick, the difficulty
value written into bot userinfo was never read, and only the LAN page had a control that
wrote the five-level single-player cvar. One ten-level ladder now defines view cone,
sight range, proximity radius, target memory, reaction delay, view turn rate, aim error
and settle, burst interval, search period and gunshot-bearing error. Selection lives on
both hosting pages, travels in the room configuration and reaches the server as
`dk3_bot_skill` (1–10, default 5), with `dk3_bot_fov` reserved for diagnosis.
Definitions, measured turn-to-notice times and the investigation are in
[bot skill and sight](bots-zig.md).

`zig build test -j1 --summary all`: 52 steps, 427 tests pass. The aggregate check had
been failing at its `zig fmt --check` step on `src/runtime/server/bots.zig`, not on a test
abort; the file is formatted and the whole graph runs. Sampled dedicated-match evidence is
in `zig-out/reports/runtime-zig-322/`, produced by the new
`dkq3/tools/runtime_bot_skill_probe.py` (parser covered by
`dkq3/tools/tests/test_bot_skill_probe.py`). Sampling also corrected three things written
earlier in this sequence: the `dk3_bot_fov` diagnostic wrapped 359° to 0° instead of
clamping, forward and right movement were projected onto the sweeping view so a bot
checking its shoulder walked sideways, and the report line printed the ladder cone instead
of the cone actually in force, so an override was invisible in its own evidence.

| Scenario | State | Evidence and limits |
|---|---|---|
| Pure ladder policy | Passed | `zig test src/runtime/domain/bot_skill.zig`: monotone 1→10, cone/proximity/range admission, rate-limited turning, an enemy at the bot's back is never visible without turning, bounded reproducible aim noise. Unit coverage only, not gameplay. |
| Cone acquisition in a real match | Sampled, unverified | e1dm2a FFA, four bots, levels changed live (`zig-out/reports/runtime-zig-322/ladder`): samples holding a target fell 38% → 21% → 12% across levels 10/5/1 with 0 faults. Same map and levels with `dk3_bot_fov 2`: 27% → 2% → 2%. Unscheduled encounters, so the gaps are indicative; the cone geometry itself is pinned by the policy tests. No human client involved. |
| Look-around search | Sampled, unverified | In every run the commanded view differs from the previous sample on 79–90 of 84–92 reports and the sweep headings {-80,-40,0,40,80} all appear, so the view is never locked forward. Not observed: a specific hidden enemy becoming visible only because a sweep reached it — that still needs a scripted approach from behind. |
| Difficulty selection while hosting | Unrun | Code path is in place on both pages (`ui_roomSkill` → `dk3_bot_skill` for LAN, `RoomConfig.skill` 1..10 for the coordinator, browser row carries `bots` and `skill`). Needs real menu input on the LAN page and the Create Internet room page to confirm the level reaches the server, the room record and the browser row. |
| Reaction and burst discipline | Unrun | Timed firefights at levels 1, 5 and 10 against a stationary and a moving human-controlled client are still required; sampled runs only show 1–5 hurt-alert turns per match. |
| Navigation regression with scanning | Sampled, unverified | Across the sampled runs `blocked` appeared in 0–2 reports per ~90 and 50–59 distinct waypoint edges were traversed, with jumps and ladders still taken. The accepted bot lift and deathtag course replays have not been re-run since the view became rate limited. |
| Level balance | Unrun | Owner review of playability at each level; not a decision this sequence makes. Encounter frequency on large maps is gated by sight range before the cone, so emptiness on big maps is a sight-range question. |


## Sequence 321 — stable skeletal geometry — focused scenarios passed

Ragdoll child anchors now remain connected through the skeleton hierarchy, so
physics constraint residuals cannot stretch the rendered bone chain. Local neural
weights are rebuilt around rigid segment targets and joint transitions, relaxed
on the welded surface to avoid sharp seams. The first strictly rigid/two-bone
attempt worsened boundary stretch and was rejected (`deformation-preview.log`).
The accepted candidate uses continuous surface transitions.

Evidence: `zig-out/reports/runtime-zig-321/`. Reviewed local package
`58a44924f8c91c20dbc86ed54477c2579bcb3d48f2fccecac9ca354a881a505e`.
`package-invariants.json` verifies 96 IQMs changed only in weights/indices and
bounds; 504 other entries are identical. Faces, motion bytes and props are retained.
`deformation-final.log` samples 20 gameplay frames per character: 99th-percentile
edge-length ratios decrease for all five (Hiro 1.486→1.451, Mikiko 1.808→1.265,
Superfly 1.614→1.340, Mishima 1.824→1.474, Usagi 2.968→2.170). These are deformation
diagnostics, not complete visual acceptance; isolated worst-case triangles remain,
and some maxima increase. Hard joint cuts, topology problems and every cinematic
performance are not claimed repaired.

| Scenario | State | Evidence and limits |
|---|---|---|
| Package preservation and weight regression | Passed | Exact byte-range comparison; rigid section, seam and joint-transition unit coverage. |
| Multiplayer deaths and lifecycle | Passed, sampled scope | `deaths/`: all five characters, stationary/moving attacks, physical falls/settling, retained bodies, disable/reset and complete LAN lifecycle. Rendered anchors follow the connected skeleton. |
| Cinematic and carrying presentation | Passed, sampled scope | `intro/`: Hiro practice motion bursts, Usagi scene through shot 35, actual save/load; `carry/`: combined Mikiko/Superfly body, movement and restoration. Textures/prop animation bytes are unchanged. Full cinematic catalog remains unverified. |
| Aggregate checks | Passed | `tests.log`: 52/52 steps, 426 Zig tests, 105 Python tests. Includes concurrent bot-skill unit coverage present when the suite ran. |

`cinematic-deformation.log` adds 24 sampled intro/carry poses: Usagi and carrying
improve their 99th-percentile edge ratios; Hiro's ratio slightly increases
(1.310→1.330), while its worst stretch and count above twice rest length decrease.
This is a targeted stability improvement, not an assertion of distortion-free
skinning. The initial combined `network/` run walked into blocking geometry before
its moving-attack assertion; the separate `deaths/` replay passes. Both are retained.
Only guarded software rendering was exercised for this pass. The old package is
retained locally as `dk3-neural-320.pk3`; the preserved game/saves were not changed.

The reviewed installation is `79a60df85f2bd04aafc79263deb82fb9d803f38a5e13d6673f4eba890512969a`.
A later normal rebuild failed in concurrently edited `src/online/worker_main.zig`
(import outside module root) and `src/runtime/ui/multiplayer.zig` (i32/f32 mismatch).
Those unrelated edits were preserved. The exact immutable build used by the
passing scenarios was published to native-dev after verifying every manifest hash
(`publish-tested.log`); this does not claim the current concurrent source tree
builds. State/save directories were not modified.

## Sequence 320 — physical skeletal deaths — focused scenarios passed

The native Zig client now simulates articulated ragdolls from the living pose,
with gravity, inherited movement, joint limits, world collision, friction and
settling. Both renderers accept owned live IQM skin matrices and physics bounds
(renderer ABI 13). Players and actors publish an explicit death flag. Retained
bodies survive multiplayer respawn and clear on presentation reset. No external
physics implementation or new asset package is admitted.

Evidence: `zig-out/reports/runtime-zig-320/`. The sequence-319 neural package is
unchanged (`d529be7652e69d1014f930d301e521c396ef37e1499cf2212d15d5178a56dd18`).
Installed build: `34026a8d5a8ae6664027ac8de7f453615a5a760b6229b767201288848f5c7a3c`.

| Scenario | State | Evidence and limits |
|---|---|---|
| Multiplayer physical deaths | Passed, sampled scope | `network-final/`: two real UDP clients, all five characters, live skin matrices, falling pelvis, world contacts and sleeping bodies after respawn. Includes e1dm1 stairway landings. Attacks, respawn, spectator/rejoin, reconnect and map restart also pass. |
| Campaign actor death and restore | Passed, sampled scope | `actor-mikiko/`: ordinary Glock fire kills a grounded Mikiko; physical collapse and sleep render in e1m3b. Loading the earlier save restores her alive and removes the ragdoll. Companion-death flow remains active. Other actor-specific death policies are not exhaustively replayed. |
| Renderer comparison | Passed, sampled scope | OpenGL2 multiplayer/actor captures and `network-gl1/` Hiro live-pose fall, contacts, settling and retained body. These runs use guarded software rendering, not hardware-GPU acceptance. |
| Solver terrain and transforms | Passed | Floor and slope settle; descending stair treads/landing reject particle penetration and retain limb lengths. 30/60-Hz presentation produces matching fixed-step results. Bind-matrix inversion and antiparallel limb rotations preserve positions/lengths. |
| Aggregate checks | Passed | `tests.log`: 52/52 build steps, 421 Zig tests, 104 Python checks. |

This is cosmetic character physics, not a general server physics replacement.
Classic vertex models and scripted cinematic/carrying models use authored death
poses. Exact corpse bone positions are not saved or synchronized between clients.
Collision volumes approximate the body; corpse-to-corpse pushing, post-death
weapon impulses, moving-platform wakeup and exhaustive campaign acceptance remain
outside this implementation. See [runtime details](neural-assets.md).
Earlier sliding/fixture failures remain in the report; `network-framed/` adds
camera inspection but exposed a probe selecting an older retained body's sleep
state. The installed replay (`network-installed/`) filters by victim identity and
explicitly requires all five new bodies to settle; those checks pass. Its final
disable check used a bare, unregistered cvar command and failed. The corrected
`set cg_ragdolls 0` check passes separately in `network-toggle/`, together with
Hiro death/settling and the complete LAN lifecycle on the installed build.
`ragdolls.mp4` retains the installed fall captures at their sampled timing. Visual review is not owner acceptance.

## Sequence 319 — character references, leg limits and combat motion — focused scenarios passed

Mikiko, Superfly, Mishima and Usagi receive reference-based face bakes; Hiro keeps
the accepted 318 atlas. All five rigs now constrain knee flexion, hip target
direction, ankle/toe rotation and leg twist during conversion. Moving multiplayer
attacks combine upper-body firing poses with the current leg cycle. Respawn waits
for the complete death animation plus a 300 ms final-pose hold.

Evidence: `zig-out/reports/runtime-zig-319/`. Package
`d529be7652e69d1014f930d301e521c396ef37e1499cf2212d15d5178a56dd18`;
installation `9695396d351af4d8435b824afd18c0a710eb6c966c54c2e7bb54f1c05e0502de`.

| Scenario | State | Evidence and limits |
|---|---|---|
| Reference face bakes | Reviewed | `face-edits.md` links the built-in imagegen outputs, exact prompts, final atlases and four-angle mesh reviews. Earlier patchy bakes are retained. Existing facial geometry and painted eyes remain limitations. |
| Remote attacks, deaths and LAN lifecycle | Passed, sampled scope | `network-final/`: two real UDP clients, all five appearances, stationary/moving attacks, 22–26 distinct death frames reaching the final pose with attack held to request respawn throughout. Respawn, spectator/rejoin, reconnect and restart pass. Captures and `remote-combat.mp4` retain observed timing. No ragdoll or slope-contact acceptance is implied. |
| Intro practice and restoration | Passed, sampled scope | `intro-final/`: 1920×1080 OpenGL2 playback through shot 36, timed practice poses, close-ups and actual mid-cinematic save/load. Forward knee bends reviewed. Full intro/later performances remain outside this sample. |
| Companions, carrying and Kage | Passed, sampled scope | `actor-*`: grounded Mikiko, Superfly, carrying and Kage in e1m3b, movement/shadow comparison; companions also save/load. Kage's translucent phase remains. These are presentation fixtures, not full campaign behavior acceptance. |
| Sword, rifle and pistol attacks | Passed, sampled scope | `held-weapons/`: remotely rendered ready/attack poses for Daikatana, Ion and Glock; hand attachments reviewed. Weapon contact behavior is outside this fixture. |
| Aggregate checks | Passed | `tests.log`: 52/52 build steps, 417/417 Zig tests and 104 Python checks. Includes planted feet, fixed lengths, extreme folded/twisted input rejection, attack/leg composition and death respawn timing. Native build and package validation pass. |

The animation constraints are offline pose limits, not a physics engine. The
procedural clips use Quake III naming conventions and contain no imported Quake
motion data. Full ragdolls, body-part collision and all cinematic performances
remain unverified/unimplemented as appropriate. Failed driver invocations before
the UDP run are retained in `network-path-error.log` and `network-combat.log`.
At sequence 319 the default local package and `zig-out/native-dev/play/current` selected this revision;
the preserved installation and saves remain untouched. Visual review is not owner
acceptance. Existing background geometry/MD3 prop problems are not repaired by
these character changes.

## Sequence 318 — Hiro eye placement — revised close-ups reviewed

The owner rejected 317's high eyes and downward appearance. The face bake now
lowers the orbital projection by up to 0.42 mesh units while leaving the nose,
mouth and forehead registered. A separate generated eye/brow edit reduces brow
thickness. Its admission mask replaces old dark eyebrow texels instead of
preserving them as hair, and excludes unwanted generated cheek changes. Lateral
hanging locks and multiplayer face color remain protected.

Evidence: `zig-out/reports/runtime-zig-318/`. Final package
`10ab7bc20741d08cfc2bf3d10d6805b30733d7407bc083d4a3fcdb205adaa08a`;
installation `6ded2e0b902f93357213c4d37343823e6a46bfcea062fefdff1833143bbe67ca`.
The stage retains the final atlas, bake provenance and face tint mask.

| Scenario | State | Evidence and limits |
|---|---|---|
| Actual mesh front and sides | Reviewed | `review-detail/`; lower eyes and reduced brows. Earlier `review*` retain failed mask/brow iterations. |
| OpenGL2 intro and save/load | Passed, sampled scope | `intro-final/`: playback through shot 15 and restored cinematic. Shot 14 and six subsequent camera samples show the reported angle; `intro-face/` is the superseded thick-brow attempt. Visual review is not owner acceptance. |
| Package and tooling | Passed | 102 Python checks, package validation, and final changed-entry audit. Only 13 Hiro PNG entries and metadata change; models, skeletons, clips and other characters match 317. No native changes; prior motion/runtime evidence remains applicable. |

Built-in imagegen outputs and both exact prompts are linked in local `face-edit.md`.
The original Hiro head texture was inspected read-only as an additional style
reference. Eyes remain painted on the existing mesh; facial animation is outside
this revision. No original installation, saves, or Git state was changed.

## Sequence 317 — reference Hiro face — eye placement rejected by owner

The owner subsequently rejected this revision: eyes sit too high, crowd the brows,
and appear to look downward. Sequence 318 addresses that defect. The scenario
results below establish playback and packaging only, not accepted eye placement.

The owner rejected the 316 face close-up: oversized eyes, soft features and a pale
jaw patch. The replacement uses the selected local `neural_experimental_assets/hiro.png`
identity reference, front/side skin projections, and a per-texel mask protecting
hair and multiplayer facial color. The eyes are narrower, the brow heavier and
the stubble follows the jaw. This remains a texture on the existing head mesh;
no animated eyes or facial morphs are introduced.

Evidence: `zig-out/reports/runtime-zig-317/`. Package
`fb2955550b41241213a4a9af622a8eecb60f682b0f838eb0b4880922e42df6ce`;
installation `60b7710b30a16609f5e20bb8cf3ac77cc7f006908906d5b9ea5d8e0d33f03395`.
Exactly thirteen Hiro texture entries and package metadata changed; all model,
animation, shader and other-character hashes match 316. That motion evidence
is unaffected. The new atlas/provenance/tint mask are retained in the staged mesh
folder so subsequent full builds retain this revision.

| Scenario | State | Evidence and limits |
|---|---|---|
| Front and both side mesh views | Reviewed | Four fixed orthographic views in `review-final`; earlier mask failures retained in `review*`. |
| Actual intro close-ups and save/load | Passed, sampled scope | `intro-face`: 1920×1080 OpenGL2 captures through shot 15 and restoration. Shot 14 reproduces the owner's reported angle; shots 6/13 show front and opposite side. `intro-closeups` adds camera-motion samples through shot 9. Visual review is not owner acceptance or full cinematic qualification. |
| Asset/tool checks | Passed | 102 Python tests; includes unchanged protected face pixels across all eleven tinted variants while armor still changes. Package validation and the changed-entry audit pass. Native code is unchanged; the 316 Zig results remain applicable. |

The three exact built-in imagegen prompts, selected projection outputs and baked
atlas are recorded in `face-edit.md` and `prompts.json` in the local report.
Blender's local OCIO data/runtime version mismatch required a report-local profile
override; system files were not modified. No original assets or user saves changed.

## Sequence 316 — skeletal motion and face repair — focused scenarios passed

The owner rejected 315's animation quality: floating swords, slow multiplayer
motion and Hiro's missing eyes. This pass replaces all five experimental skeletons
and weights with reviewed anatomical rigs, authors new fixed-length IK clips, and
keeps loop cadence independent of the old vertex-animation frame count. The client
interpolates clips and blends sequence changes; gameplay/contact clocks stay on
the server. Held props use hand transforms, split cinematic sword pieces share one
grip, and the gameplay sword has a measured handle offset. Hiro's local atlas now
contains a repaired face with visible eyes; facial morphs remain unsupported.

Local package `281e53a5ceb65913d2224b88f320a30641c435801707b957bc9246f388fe4d2a`
contains 94 replacements and two additional multiplayer bodies, with 60 skins.
All 96 IQMs have finite animation channels and normalized weights. Sources and
converted assets remain local. See [tooling and limits](neural-assets.md).

Evidence is under `zig-out/reports/runtime-zig-316/`. Final native grip build:
`a429afe57550787fb0066e9fef7dbe362b8c0af3f3227a3ca6ea3ce8b8f99f9a`.
This build is installed as `zig-out/native-dev/play/current`; the default local
package is selected by `zig build play`. The prior `84420b…` build has identical
rigs, timing and cinematic code; only the
class-owned gameplay sword offset differs. Its unaffected results remain valid.

| Scenario | State | Evidence and scope |
|---|---|---|
| Remote gait and LAN lifecycle | Passed | `network-motion`: all five appearances over real UDP. Actual rendered run frames follow 30 Hz / 15-frame loops across 595–732 ms of settled motion per character; captures and `remote-gaits.mp4` retain measured timing. Fire, respawn, spectator/rejoin, reconnect and restart pass. |
| Cinematic practice and restoration | Passed, sampled scope | `intro-final`: playback through shot 36, 36 timed motion captures, nine shot captures, actual save/load. Practice sword remains hand-attached in reviewed poses; Hiro's face has visible eyes. Full intro and all later performances are not qualified by this sample. |
| Gameplay weapon grips | Passed, sampled scope | `held-weapons-fixed`: remote sword, Ion and Glock ready/attack captures. Sword handle offset removes the observed gap. These are presentation fixtures, not weapon contact acceptance. |
| Companions, carrying and Kage | Passed, sampled scope | `actor-*`: grounded Mikiko, Superfly, carried Mikiko and Kage in e1m3b, movement and shadow comparison; companions also save/load. Mikiko replays on OpenGL1. Kage retains his authored translucent phase. This is not full companion/boss behavior acceptance. |
| Aggregate checks | Passed | `tests.log`: `zig build test --summary all`, 52/52 build steps, 417/417 Zig tests and 101 Python tests. Includes planted-foot/fixed-bone checks across five rigs, clip cadence, released props and split-sword visibility. |

Retained failures: `network-preview` reached a wall before recording enough gait
samples; `network-final` sampled less than the required settled interval. Combined
render/diagnostic captures repair the driver without weakening timing assertions.
`held-weapons` exposed the gameplay sword's offset mesh origin; the class-owned
handle correction and replay address it. Black/angular background geometry in
intro/arrival images also occurs without neural assets (315 stock comparison);
it is not accepted as repaired here.

## Sequence 315 — neural skeletal characters — superseded visual result

The optional skeletal package, native routing, five appearances and shadow bounds
were implemented. Local load, selected cinematic/companion and LAN lifecycle
checks passed, but the owner rejected animation and face quality. Successful
registration and still images did not establish motion acceptance. Sequence 316
replaces the rig/clip conversion; historical evidence remains under
`zig-out/reports/runtime-zig-315/`.

Development: `rewrite/native-zig-runtime`. Preserve main
`e3966c4d40678dbf91619034b5dcb33b763dcbed`, installed playable game, user saves and
live service. The removed gameplay backend remains disconnected. Complete four-episode
campaign, companions, multiplayer/bots, UI, persistence and independent release stay in scope.

Owner-directed cadence: finish the broad connected coding pass, then consolidate the
build/assets and run verification with repairs. No per-item suite/engine gates.
Implementation checkpoints 255–284 add no connected acceptance. No overall percentage
is inferred from class counts or test volume.

## Current outcome matrix

Sequence 309 repairs the shared actor ground-departure check, camera mode
transport and multiplayer weapon presentation lifetime, and adds worker fear,
party-health autosaves and softer Cambot lights. Sequence 310 adds the installed-map
picker for Internet Create and LAN hosting. Sequence 311 repairs pickup raises,
first-person stair/duck smoothing, pickup rotation/lighting and weapon shine.
Sequence 312 repairs saved-region loading, worker ZIP cleanup and wet-floor
robot navigation. Sequence 313 enables model silhouette shadows and makes the
launcher explicitly select OpenGL2. Sequence 314 gives the multiplayer Load menu
a local campaign transition. Latest coherent build: `a429af…`,
protocol 1350; earlier gameplay evidence retains its recorded identity below.
**Seamless campaign acceptance remains incomplete.** Fresh opening development
reaches the bridge boss but has not completed the milestone. Ground-controller
changes require replay of earlier encounter/route evidence. Wider weapon
interactions, navigation, party actions, multiple views, seam qualification and
remaining admission stalls stay open. Supporting checks do not measure completion.

| Milestone | Implemented | Contract-tested | Running native engine / connected play | Reference comparison and remaining work |
|---|---|---|---|---|
| Seamless connected regions | Region admission/ordinary exits, qualified collision, actor/projectile transfer, specialized weapons, party ownership and authored script scope | 402 Zig, 82 Python and actual C owner/collision/inline-handle contracts pass | On `187506…`: eleven weapon contact cases, selected controller restores, real turret/frog contact, both renderer combat paths, enemy/companion/player crossing and region save/death restoration | One reviewed corridor and selected interactions. Broader navigation/party actions, multiple views, seam qualification, eviction/admission stalls and fresh route remain open. [Evidence](#sequence-305--specialized-weapons-across-seams). |
| Ground actors and workers | Floor-departure and wet-floor routing repairs; worker retreat/cower and fear audio connected | Settled-motor/jump, capability exclusions and class roots pass through 312 | On `268649…`, Sludgeminion pursues from the unchanged user save; guard dry-ground pursuit/fire replays. Worker/Crox evidence retains its 309 identity | Private ground/water behavior inspected. Full ground-class/worker/campaign routes remain unverified; earlier affected route evidence requires revalidation |
| Weapons | All 28 class-owned controllers connected; 305 extends spatial and persistent ownership | Class roots and ownership/slot/cancellation contracts execute at 305 | Eleven controlled specialized weapon contacts across A/B; Wyndrax, Nightmare, Metamaser and pending Zeus restore on `187506…`. Three actual Trident tips confirmed | Not all interactions: Trident merge/water, Ballista carried crossing/pin restoration, destruction variants, return/pickup and complete audiovisual comparison remain open |
| Fresh opening gate | Intro, actors, authored controls, progression and saves connected | Applicable contract roots execute through 308 | **Not accepted:** fresh 305 and superseded 306 runs reach the bridge encounter and fail. A separate legitimate factory checkpoint reaches e1m2a alive | Full coherent New Game→M2 route still required; boss avoidance/firing-lane strategy remains a driver blocker. No modified inventory or assembled checkpoint chain qualifies. |
| All four episodes | Additional hostile/ambient/boss controllers, scripts, cinematics, companions, world effects and ending connected | Coding-pass contract roots pass at 285; connected scenarios unrun | No complete episode accepted on native runtime | Broader ability/task audit, connected boss/puzzle/companion traversal and ending remain |
| Saves and visited worlds | Region recovery, autosaves, bounded loading work, actual progress and owner-thread ZIP finalization | Runtime/party-health and actual concurrent ZIP/CRC/cancellation contracts pass at 312 | On `268649…`, user autosave/save2 restore via both menus and death recovery in both renderers with all 10/12 resident worlds; original files preserved | Full live-party autosave and fresh campaign restoration remain unverified. 309 autosave timing retains its identity; historical state stays mandatory. [Evidence](#sequence-312--native-restoration-wet-ground) |
| Multiplayer and bots | Native sessions/modes/bots; spawn-aware shared weapon presentation; protocol 1350 | Wire, counter-wrap and respawn contracts pass at 309 | Final 309: two actual UDP clients show advancing attack frames before/after respawn and pass spectate/rejoin/reconnect/restart | Every weapon interaction, full CTF/deathtag, public admission/authenticated rooms and full modes remain open. No service deployment |
| World/effects | Authored controls, hazards, debris, lighting and sky connected; softer Cambot lights and default model silhouettes | Applicable aggregate contracts pass at 313 | Final 313: character floor/wall shadows and restoration in both backends; armor/ammunition shadows and resident combat in OpenGL2. Earlier Cambot/sky evidence retains its identity | Full material/terrain, foreign-view shadow generation, brush casting and performance remain open; Cambot enhancement is not a shadow-mapped spotlight |
| Presentation and cinematic input | Menus/loading art, interpolation, cinematic input and all camera modes connected | Three-bit camera modes survive actual message encoding at 309 | Final 309: ordinary e1m1c button use, remote door view, release and finished-scene save/load. Earlier intro/menu evidence retains its recorded identity | Full fresh intro, all authored scenes, menu equivalence and audiovisual comparison remain unverified |
| Pickup and first-person feedback | Shared class-owned raise transition, stair/duck offsets, selected rotating pickups, minimum model light and neutral shine | Acquisition/queued-input, rotation exclusions and camera replay/boundary contracts execute at 311 | Final 311: one actual Ion pickup draw, smooth crouch/stand and ready-weapon restore in both renderers; three actual e1m1c step rises; armor/ammo/shine captures inspected | Main camera timing and private pickup behavior inspected. Controlled setup; broader weapon interactions, custom rotation overrides and exact glow/material parity remain open |
| Independent release | Bare `zig build play` builds/installs native code with the existing local cache | Build/contracts and installer preservation pass at 286 | Guarded native menu, e1m1a admission and actual save/load pass; explicit map and disabled intro | Full independent fresh-checkout/release and campaign qualification remain |

## Sequence 314 — native-host-to-save

Build `83d6e0d090472eed29e915d8da2a30db37ca0e3fdbc14812c3acc2d05641a4bb`;
combined identity `be918e9f14163e479fcbafa82bdfe73360d933f8bed38a44587bc9bf44249dc8`.
Protocol 1350, renderer ABI 12, assets, shadows and renderer defaults are unchanged.

The native Load menu validates the selected save before closing. During a hosted
or remote match it now disconnects and starts the local saved campaign through
`dk3_loadmenu`, which stages the save and selects single-player mode. An active
local campaign keeps its existing `load` path. Previously the menu forwarded
`load` to the match; the actual hosted reproduction refuses it with
`SaveRequiresSinglePlayer`.

The reported screenshot also showed missing 2D HUD art/text while 3D inventory
models remained visible. The owner clarified that this happened immediately
after Escape → Load in a hosted match and recovered about a minute later.
That transient rendering symptom has **not been reproduced or independently
confirmed fixed**. No speculative renderer change is included in this sequence.

Evidence is under `zig-out/reports/runtime-zig-314/`. All runs use dkguard and
isolated profiles with copied saves; the owner's live files remain untouched.
The original autosave advanced during investigation, so later probes retain a
frozen `source.sav` and its digest rather than assuming the live slot is unchanged.

| Evidence | State and result | Limits |
|---|---|---|
| `build-approved.log` | Passed: integrated native installation, 43/43 build steps | Initial sandbox build lacked writable Zig compiler cache; no duplicate broad suite |
| `direct-old/` | Failed as expected: real hosted Escape → Load refuses the save with `SaveRequiresSinglePlayer` | Reproduces the menu routing defect, not the transient missing HUD |
| `direct-fixed/`, `direct-e1m2b/` | Passed: actual hosted Escape → Load restores copied e1m3a/e1m2b saves, confirms `g_gametype 2`, draws the loading screen and complete HUD when gameplay resumes | OpenGL2 software. Inspected captures plus fixed POWER-label pixel checks across 20/12 subsequent samples at two-second intervals; not proof of the original transient symptom's cause |
| `baseline-restore/`, `baseline-multiplayer/`, `baseline-bots-complete/`, `loading-baseline/`, `background-baseline/`, `loading-opengl1/` | Completed: copied-save restoration from a disconnected menu, loading/background observations in software | Pre-change investigations; both renderers represented. Initial `baseline-bots/` used an insufficient observation timeout |
| `hardware-baseline/` | Completed on NVIDIA RTX 5090 Laptop GPU: disconnected restore retains HUD | Pre-change OpenGL2, console transition, copied settings; no desktop input injection |

## Sequence 313 — native-model-shadows

Build `aa5a4cb4bcf90ec1a1492b265ec393e9217b7f34c6166a500d14b149944bc1cd`;
combined identity `b8934fe160e3976b7751d679773e3bb9d659cabfbeef6ca4ee2f57cded6a49c5`.
Protocol 1350, renderer ABI 12 and local asset packages are unchanged.

The default `cg_shadows 1` now
selects model silhouette shadows in both backends: stencil volumes in OpenGL1,
projected shadow maps in OpenGL2. Video settings expose an archived Model shadows
On/Off control. Opaque actors, corpses, pickups, held weapons and ordinary model
props participate; first-person weapons, fading models and effect overlays do not.
OpenGL2 validates MD3 frame indices before shadow bounds reads, covers both
animation poses and nonuniform scale, and excludes other resident worlds.
Both backends bias low light directions upward to retain a ground silhouette.
OpenGL2 uses a consistent orthographic depth range and compares receiver depth
against the caster; the old occupancy-only lookup could shadow surfaces in front
of the model. The launcher selects OpenGL2 even with an older saved renderer
setting; an explicit trailing `+set cl_renderer opengl1` still takes precedence.

| Evidence | State and verified outcome | Limits |
|---|---|---|
| `aggregate.log` | Passed: 52/52 steps, 415 Zig tests, 87 Python tests and existing actual C contracts | One consolidated suite after renderer/scenario repairs; no full campaign or hardware-performance claim |
| `final-solid-opengl1/`, `final-solid-opengl2/` | Passed: default On, Off/On captures with inspected character silhouettes on floor/wall, save/load and restored rendering in both backends | Diagnostic grounded worker in e1m3b, player placement/health. Lightmap-only views separate shadow geometry from authored textures; timed lighting still advances |
| `final-solid-opengl2/pixel-evidence.json` | Shadow floor sample attenuates to 0.339 of its Off value versus 0.734 in the unshadowed control | Fixed small image regions corroborate inspection; not a whole-image or performance claim |
| `final-pickups-opengl2/` | Passed: authored armor/ammunition Off/On captures inspected; visible armor footprint and ammunition shadows on alcove rock | Controlled crouched viewpoints; not every pickup/prop |
| `launcher.json` | Passed: ordinary launch selects OpenGL2, explicit OpenGL1 argument wins | Captured actual launcher arguments with a temporary synthetic installation |
| `final-resident-opengl2/` | Passed: foreign target rendering, late model registration and Glock/Ion/Sidewinder contact through the resident aperture; view inspected | Controlled two-world setup; destination shadows remain suppressed rather than borrowing source-world maps |

Foreign portal views suppress source-world shadow maps; destination-view shadow
generation remains open. Static BSP lighting remains baked; this does not add
dynamic brush casting or a shadow for the omitted local first-person body.
OpenGL2 retains the bounded 16-map shadow budget. Transparent receivers and
fading casters, all terrain/material cases and hardware performance are not
qualified by these focused scenes.

Evidence is under `zig-out/reports/runtime-zig-313/`. Initial worker setup used
the wrong class assertion, and the first software run could not open X inside
the sandbox. A slow-timescale comparison stalled and is not acceptance. Early
captures retain the missing ground projection and incorrect shadow-depth lookup;
the final renderer scenes supersede those appearances. Full campaign acceptance
remains open.

## Sequence 312 — native-restoration-wet-ground

Build `26864935fe82571da35369cc415d47920647333b6d74d38998ad7db711cf1ca0`;
combined executable/module/asset identity
`4144b1501f1e32fe307155cc2258d8c80f5bb8e95a68d87d1b56e52442f521eb`.
Protocol 1350 and renderer ABI 12 remain unchanged. Each final report's
`identity.json` records every admitted asset hash; base/HD/region manifest remain
at sequence 311 identities. Evidence: `zig-out/reports/runtime-zig-312/`.

Loading a saved region previously consumed a frame for every preparation step
and kept its progress bar empty. Loading now processes at most 64 steps or an
8 ms scheduling budget per frame; individual engine calls retain their existing
limits. Ordinary background prefetch still yields after one step. Progress counts
actual admitted resources/worlds, and restoration still requires every saved world.
A reproduced loader crash exposed background ZIP closure freeing the engine zone
from workers. Stream finalization and CRC validation now follow the reader join on
the engine owner thread; no zone-size increase or discarded history masks the issue.

The reported robot is an authored Sludgeminion. The supplied hull has valid floor
support, but the old ground routing flags reject water areas, including walkable
shallow floors. Native AAS now allows water areas for ground walking without
adding swimming, water-jump, ladder, elevator or hazardous-liquid capabilities.
Class-owned speed, collision, damage and authored geometry remain unchanged.

| Evidence | State and verified outcome | Limits |
|---|---|---|
| `aggregate.log` | Passed: 52/52 steps, 415 Zig tests, 87 Python tests and actual C contracts, including the new background ZIP reader root | Assertions enabled; runtime root explicitly includes navigation and client admission tests |
| `read-fixed.log`, `read-defective.log` | Actual bundled minizip/shared reader passes concurrent completion, repeated polling, cancellation, size rejection and CRC failure; moving cleanup back to the worker fails the owner-thread assertion | Synthetic local ZIP, no private assets or alternate runtime |
| `wading-before-defect.json`, `robot-diagnostic/` | Expected defect reproduced: living chasing robot remains horizontally stationary across actual engine samples | Intermediate build `ff196a…` with loader diagnostics, preceding navigation repair; not product acceptance |
| `wading-final/` | Passed: untouched autosave's robot 83886443 moves 28 units during measured pursuit at supplied speed 80; actual AAS travel cost is 0 without water admission and 1377 with it | User's saved easy difficulty and inventory retained; player position unchanged during pursuit. Camera placement occurs only after acceptance. Not fresh traversal |
| `ui-autosave-input-fixed/` | Passed: real mouse selection and Load from paused/main menus, visible nonzero progress, restored input and actual death recovery in e1m2b, OpenGL2 | Untouched copied user autosave with ten resident worlds; menu loads 7.21/6.59 s, death recovery 10.61 s including death delay. Local software-renderer timings, not a performance guarantee |
| `ui-save2-opengl1/` | Passed: same menu/death sequence using untouched copied save2 in e1m3a, OpenGL1 | Twelve resident worlds; menu loads 9.66/7.60 s, death recovery 11.62 s. Both save scenarios assert retained dead actors and restored player identity/weapon |
| `ground-regression/` | Passed: authored guard navigates around occlusion, moves over 32 units and fires | Controlled last-seen goal/player placement; unaffected dry-ground regression, not campaign completion |
| `region-save-isolated/` | Passed: independently changed actor health in e1m1a/e1m1b, active world/player identity and inventory restore after explicit load and death in the other world | Controlled health/placement and resident transfer; not connected campaign traversal |

The initial console reproductions could restore the user saves but required long
admission waits. `robot-wading-isolated/` preserves the pre-cleanup-fix real zone
allocation crash. Failed UI setup runs did not exercise Load: one shared display
received another window's input, and another used relative mouse grab with an
absolute XTest driver. The corrected driver uses the existing ungrabbed UI test
mode and asserts actual pause before clicking. Concurrent display teardown also
invalidated `region-save-regression/`; engine regressions run alone afterward.
None of those failed setups counts as acceptance.

Original save files remain byte-identical; main, the preserved installation and
online service are unchanged. Full campaign, broader ground-actor/worker routes,
all weapon interactions and multiplayer qualification remain open. Earlier route
results affected by shared navigation changes still require replay.

## Sequence 311 — native-pickup-view-feedback

Build `e1e3c7fd4ac9f463c5e75d8368463f1d9038b5a68a75ae87830ac0a608f6b78a`;
combined identity `f626e617c965cccbdf342c9e92cd395c2ff6148be5d09d7a18354ea39b6ac446`.
Base, HD and region manifest remain at sequence 306 identities; protocol 1350
and renderer ABI 12 are unchanged. Evidence: `zig-out/reports/runtime-zig-311/`.

Weapon acquisition now enters its class-owned raise transition, preventing queued
old-selection input from starting another draw. Ammunition pickups preserve the
current transition. Restoration initializes the presentation incarnation once.
First-person stairs and crouch follow main's admitted 200/100 ms presentation
contract; predicted command replay cannot accumulate the same step twice.
Collision, damage and player speed are unchanged.

Armor and the reviewed rotating pickup classes use the existing angular trajectory;
ammunition and single-player world weapons retain placed orientation. Pickups sample
light above their base and request minimum light, now honored by both renderers.
Neutral texture-modulated shine replaces the blue additive veil. These lighting
changes are documented enhancements, not complete original-material equivalence.

| Evidence | State and verified outcome | Limits |
|---|---|---|
| `aggregate.log`, `runtime-approved.log` | Passed: aggregate 50/50 steps, 413 Zig and 87 Python tests plus actual C roots; affected runtime 273/273 | Assertions enabled, new roots execute. Controller fixtures explicitly begin already equipped; acquisition has its own regression |
| `pickup-defect/` | Reproduced defect on prior native `e2df24…`: ordinary contact produces two Ion ready animations | Expected-defect run, not product acceptance; combined identity `0c2bbf287f59879aa0cb4be92856e979b7e669258bcba3d6617559c922fac8b9` |
| `view-final-opengl1/`, `view-admitted-opengl2/` | Passed on final build: actual pickup contact produces one ready animation, crouch/stand include intermediate eye heights, save/load does not duplicate the ready animation. Fixed-camera armor rotation, readable alcove armor/ammo and Off/Original/Enhanced shine captures inspected | Diagnostic positioning/health, ordinary pickup contact, isolated profiles. Actual crouch and grounded alcove setup asserted. Not a fresh playthrough or every pickup class |
| `stairs-final-opengl1/` | Passed: ordinary walking climbs three authored e1m1c step rises, with negative camera offsets that decay to zero | Diagnostic placement, no jump or geometry changes; not full traversal or frame-time qualification |
| `network-final/` | Passed on final build: two real UDP clients move/fire with advancing weapon frames, respawn, spectate/rejoin, reconnect and restart | Ordinary DM inventory; commanded death. Affected shared-presentation regression, not complete multiplayer or every weapon interaction |

Failed setup runs remain invalid: early input observations preceded the final region
admission event; initial item viewpoints intersected rock, and the first stair
route was a ramp. The driver now waits for final admission and asserts walkable
placement. The first renderer correction was excluded by build flags; final
lighting captures supersede it. Existing `d1_swp3` out-of-range frame warnings are
still visible with developer diagnostics and remain a separate presentation issue.
Earlier local report directories disappeared during this session; sequence-311
evidence above was recreated. Historical journal outcomes retain their identities,
but missing artifacts are not treated as fresh native acceptance. No preserved
installation, saves, main branch or service was changed. Full-port and connected
campaign acceptance remain open.

## Sequence 310 — native-multiplayer-map-picker

Build `e2df24ee6037eda462fc9d81f3482d609e560337ff884c46f1533f1ec4e36d0b`;
combined identity `48e0b439886dd6c50e4c17efa4b5f7a45909d6d04b480b6b96d1df4039855666`.
Base, HD and region manifest remain at sequence 306 identities; protocol 1350 and
renderer ABI 12 remain unchanged. Evidence: `zig-out/reports/runtime-zig-310/`.

Internet Create and LAN hosting now share a paged map picker instead of requiring
a typed map identifier. Names, titles and mode capabilities come from the existing
local `dk3/maps.cfg`; only mounted BSPs are offered. Mouse or keyboard selection
persists in the existing room-map setting. Changing mode retains a compatible
selection or chooses the first available map. Missing/incompatible selections
cannot launch a room. Mode labels now show Deathmatch, CTF and Deathtag directly.

| Evidence | State and verified outcome | Limits |
|---|---|---|
| `build-approved.log` | Passed: 62/62 build/check steps, 270 Zig tests and actual C runtime roots; map-catalog root explicitly executes | Applicable runtime suite and native installation only; no duplicate broad suite |
| `map-picker-approved/` | Passed: actual XTest mouse and keyboard selection, paging, Escape cancellation, DM/CTF/DT filtering, selection shared by Create/LAN and a real e1dm1 LAN launch with processed player input. Captures inspected | Isolated profile, OpenGL1 software rendering. Internet Create selection is verified; no Internet room was submitted. This is UI acceptance, not broader multiplayer/campaign acceptance |

The first build could not write the compiler cache inside the sandbox. The first
engine setup could not access its virtual X display and exercised no menu. Both
failures are retained; the approved replays above completed outside that sandbox
using dkguard and temporary profiles. No private reference source/assets, preserved
installation/saves or live service were changed. Earlier gameplay evidence keeps
its recorded build identity; complete-port acceptance remains open.

## Sequence 309 — native gameplay feedback and grounded actors

Build `18681cf879b513dd84b471dd4e6b9cfe6d0c0cf9356badfa7fb353e29b4282d5`;
combined identity `a7211a68e66400d48df29e744ecf970c732b5e79b443e590a2edf4799936b0d0`.
Base, HD and region manifest remain at the identities recorded in sequence 306.
Protocol 1350, renderer ABI 12. Evidence: `zig-out/reports/runtime-zig-309/`.
Native clients and servers must use the matching protocol; the live service is
unchanged. `zig build play` selects this isolated development build with HD assets.

The actor motor no longer mistakes the 0.04 upward velocity left by floor
collision for an actual jump. Its departure rule matches the admitted slide/player
contract. Worker-specific fear consumes witnessed injury/death and existing
navigation, vocal and animation services; blocked/finished retreat stops in an
authored cower/ambient pose. Private reference behavior was inspected, without
importing implementation. Original hide-node route equivalence remains unverified.

Monitor mode 2 and ending mode 4 previously vanished in a one-bit snapshot field,
while the server correctly used the remote view for visibility. Three bits retain
all modes. Multiplayer already uses shared class-owned weapon controllers; the
repair gives presentation a spawn lifetime and consistent 16-bit shot ordering.
It does not create separate single-player/multiplayer weapon implementations.

Playable arrivals write `autosave-arrival`; periodic saves write `autosave` after
60 simulation seconds, only when Hiro and every recruited companion exceed 90%
of their own maximum health. Stopped/carried members and connected neighboring
worlds participate. Successful saves also refresh death recovery; manual slots
are untouched. Cambot lights use a small emitter, a softer beam and a contact
surface pool with range attenuation; this is an enhancement, not a shadow-mapped
spotlight or a claim of original rendering parity.

| Evidence | State and verified outcome | Setup limits |
|---|---|---|
| `aggregate-final.log` | Passed: 93/93 build/check steps, 409 Zig, 87 Python and actual C roots | Assertions enabled; explicit worker, companion-health, camera-wire and movement roots execute |
| `ground-defect.log`, `ground-defect.json` | Passed regression sensitivity: restoring the strict upward-sign rejection in a temporary copy fails the actual actor-motor test | Captured resting velocity, ordinary slide collision; no production source mutation |
| `ground/`, `crox-ready/` | Passed: actual guard pursuit around occlusion and subsequent fire; Crox swimming, restored pending melee and real contact | Ground-equivalent build `21d238…`, combined `ec768240c73d1296d224f65ff92df1227a4b204759c08f219025fa2c49fbe036`; diagnostic positioning/health, no route acceptance |
| `monitor-final-opengl1/`, `workers-final-opengl1/` | Passed on final build: ordinary button use selects the actual remote camera, releases input and restores a finished scene; witnessed worker injury/death dispatches fear vocals, settles into the stopped pose and restores fear state | Diagnostic placement/equipment. Fat worker uses ambient fallback; skinny cower frame ranges appear during the living victim's injury. No full cinematic/task parity claim |
| `lighting-final-opengl1/`, `lighting-final-opengl2/` | Passed on final build: Cambot acquisition, actual lamp submission and inspected close/wide captures | Enhanced appearance, not full renderer equivalence or independent shadow/occlusion qualification |
| `multiplayer-final/` | Passed on final build: two real UDP clients advance/interpolate attack frames before and after respawn, then spectate/rejoin/reconnect/restart | Ordinary starting weapon; this does not qualify every weapon interaction or multiplayer mode |
| `progression-final/`, `region-save-final/` | Passed on final build: ordinary movement across both authored A/B exits retains identity/input and creates a B arrival autosave; independent actor states and active world survive save/load and death recovery | Controlled approach/state changes; no fresh playthrough. `arrival-b.sav` and `.info` retain the actual boundary evidence |
| `autosaves-final-opengl1/` | Passed on final build: actual arrival save, real 60-second eligibility boundary rejects 90% health, saves at 91% and restores 91% after subsequent damage | Controlled health setup; companion maximum/ownership/stopped/carried eligibility is contract-tested, not yet exercised as a complete live party autosave scenario |

Earlier successful `monitor-input/` and `autosaves-ready/` use `6201ad…`, combined
`1d6004cdfc56d92014bb8734ab308b2f3482a0c22098f6f3931661a5cd834295`.
`workers-terminal/`, `multiplayer-input/` and initial `lighting/` use `21d238…`;
the latter's close-range pool was too bright and is superseded by reduced gain.
Failed setup runs remain: early monitor aim preceded floor settling, multiplayer
held attack through the normal respawn guard, initial world readiness timed out,
and a killed worker was correctly retired before the driver's next sample.
These invalidate those scenarios; later runs require actual input/attack, camera,
readiness, contact and save-completion evidence. Ground contract fixture failures
preceded correction of its contact-depth tolerance; final assertions and the
negative mutation both execute. Fresh intro/campaign, broad ground-class traversal,
full multiplayer modes and the complete independent port remain unaccepted.

## Sequence 308 — background PNG preparation and recoverable lookahead

Final build `d3db133f78affc07113642a685d540a4a20ef01d19144ead550a9219d82a5813`;
combined identity `940837b5c7363d6a6ea9923efba3054b3488daf6295323170b31ddc52b23c4c9`.
Base, HD and region manifest identities remain those recorded at 306; protocol
1349 and renderer ABI 12 are unchanged. Evidence: `zig-out/reports/runtime-zig-308/`.
`zig build play` installs this isolated native implementation with HD enabled.

World surface admission discovers each actual material's PNG inputs using the
existing shader definitions and backend format preferences. Independent file reads
feed pure CPU decode workers; completed pixels are consumed by the ordinary owner
thread material compiler and GPU uploader. Each material has a 128 MiB pixel bound;
cancellation joins before releasing input/output. No engine filesystem, renderer
allocation, logging or GL calls occur on decode workers. Other image formats,
generated normal maps, GPU uploads, collision decode and gameplay admission still
include synchronous work. This is not complete loader/frame-time acceptance.

Rejected lookahead no longer crashes the current world. A required failed
destination is refused before traveler ownership changes, including a pending
cut; a held source resumes its clocks and input. New saves exclude unfinished
preparations with no exposure or restored/migrated state. Already exposed or
historical worlds remain mandatory; no existing gameplay history is discarded.

| Evidence | Verified outcome | Limits |
|---|---|---|
| `async-opengl1/`, `async-opengl2/`, `admission-summary.json` | Both renderers admit A/B/C and pass actual foreign Glock/Ion/Sidewinder contacts, owned portal presentation and late resources. Each prepares 189 PNGs; measured surface peaks 8/11 ms. GL2 aperture inspected | Renderer-consolidated build `af21d5416d577bdf23d259d4fa3615cd83afa90290b41411cf1b46d3598e1216`, combined `efcc2d9468dd22191f26c800f12a33f31195ff4a880a302d2bb6d398fb38a8a1`, precedes server failure repairs. Renderer code is unchanged in final build. Controlled setup, not fresh campaign acceptance. |
| `failed-prefetch-save-boundary/` | On final build, a confirmed corrupt future PNG fails admission while current identity, connection and processed movement survive. Current save/load succeeds; a new failure is observed after restoration, entry into the failed factory region is refused, and ordinary control remains available | Temporary profile-only PNG override, recorded in `setup.json`; diagnostic placement/health. Original assets/saves untouched. |
| `region-save-final/`, `restore-final/` | On final build, both A/B actor states survive actual load and death/reload; the unchanged six-world save admits all five resident members, completes its arrival cinematic and permits normal movement/saving | Controlled/historical fixtures. No fresh traversal acceptance; simultaneous final restore runs are not used for frame-time comparison. |
| `aggregate-failure-repair.log`, `runtime-final.log`, `png-asan-final.log`, `worker-defect/` | Repair aggregate: 50/50 steps, 403 Zig and 87 Python plus actual C roots. Final save-boundary change: affected runtime suite 19/19 steps, 264 Zig and C roots. Worker/cleanup ASAN passes. Inline dispatch in a temporary source copy fails the required non-owner-thread assertion | Assertions enabled. Unaffected aggregate roots are retained rather than rerun. Tests exercise actual decoder pixels, two owners, cancellation during read/decode, prepared-cache consumption, corrupt input and budget failure. |

Failed evidence remains: `failed-prefetch/` incorrectly equated renderer/server
handles (invalid setup); `failed-prefetch-owner/` exposed the actual fatal future
admission; `failed-prefetch-recovered/` exposed a saved unfinished second map that
later failed restoration. All remain failed, superseded by the final recovery run.
The latter uses build `4f46b1…`; positive six-world `restore-opengl2/` on `af21d5…`
is superseded by `restore-final/`. No acceptance is transferred from the removed
runtime. Wider seam qualification/transforms, multiple views, navigation, residency,
remaining admission work and the fresh campaign gate are still open.

## Sequence 307 — HD PNG admission and collision forecasting

Build `99ea9654869df4e10be7ddc2eed76e49bbe91da4eaa034a255cf9ffb98293123`;
combined identity `499e7f690756d540e13b8aba24c3d6687835c6079392851c015c045773cb3028`. Base, HD and region manifest
identities are unchanged from 306. Protocol 1349 and renderer ABI 12 unchanged.
Evidence: `zig-out/reports/runtime-zig-307/`.

The actual image timings identify PNG read/decode as the dominant HD material
stall. Both renderers now use the already bundled zlib inflater once, with an
exact scanline allocation bound, retaining the existing pixel/filter/alpha
conversion. Empty IDAT chunks consume their CRC; oversized palettes are rejected.
The zlib header/checksum is now validated, a deliberate stricter malformed-input
contract. No private runtime, assets or new third-party component is admitted.

| Evidence | Verified outcome | Limits |
|---|---|---|
| `png-opengl1/`, `png-opengl2/` | Both actual renderers admit A/B/C, display an owned portal and record actual foreign Glock/Ion/Sidewinder contact; HD textures enabled | Controlled setup. Surface phase peaks 26/33 ms respectively, versus 107–111/101–107 ms in 306 final runs. Decoding/upload still occur on the owner thread; no frame-time or full asynchronous-loader claim. GL2 aperture inspected. |
| `aggregate-final.log`, `png-contract.log`, `png-defect/` | 50/50 steps, 402 Zig, 87 Python and actual C roots pass; synthetic PNG checks exercise filters, alpha, bit depths, Adam7, empty/split IDAT, malformed streams and cleanup | Initial aggregate had a missing SDL include in the new C root; fixed. The unmodified prior public decoder fails the valid empty-IDAT fixture. Assertions enabled. |
| `bridge-collision-forecast/` | Read-only forecast copies the actual spray controller and traces the existing geometry; six eventual impacts match within 0.008 units and 8–35 ms frame quantization | **Failed boss encounter** on earlier `4fd0ae…`, combined `d69b3e…`; Hiro dies with boss health 270. Forecast validity does not establish successful avoidance or campaign traversal. No gameplay damage/rule changes. |

`306/fresh-opening/` is now a failed superseded-build development route: full
intro/arrival, marsh and ordinary bridge progression reach the boss; the driver
falls into water and loses its firing lane. `305/fresh-opening-defenders/` also
fails at the boss. Neither is a fresh complete milestone. Checkpointed factory
exit evidence remains narrow. Next work removes remaining decode stalls and
uses a materially different legitimate encounter route before replaying the gate.

## Sequence 306 — incremental lightmap admission

Build `96438935d3357b5ea701fa315569de849be720e40110ca43cf2b9c0d47c87073`;
combined identity `825ee3cbe14bc71fce6672b97b9f92aaeb58bbb3a8e625c23a4a0634c783a428`.
Base assets `e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`;
HD `d2e8d95bdbcb52de5529d932d8a3be378b46ac293fe2ec15849c7ac2d299c645`;
region manifest `f0cb127dcc3fa705a51cc5d9fd597960396e7bfdc3ca2cc55e709998e6a1368d`.
Protocol 1349 and renderer ABI 12 unchanged. Evidence:
`zig-out/reports/runtime-zig-306/`. `zig build play` uses this isolated installation.

Both renderers retain per-world lightmap upload progress and yield between uploads
at the existing four-millisecond work target. GL2 retains merged-page allocation
progress. Definitions, lightmaps and fog have separate admission phases; reported
phase peaks distinguish the remaining synchronous surface/texture work. GL1's
single-lightmap workaround duplicates the supplied image instead of reading past
its lump; both lightmap converters supply an explicit alpha byte for RGB pixels.

| Evidence | Verified outcome | Limits |
|---|---|---|
| `loader-final-opengl1/`, `loader-final-opengl2/` | Actual region admission, owned portal presentation/late resources and Glock/Ion/Sidewinder foreign contact pass on the consolidated build | Controlled synthetic target/equipment. Inspected GL2 aperture frame; no full reference comparison. Lightmap phases peak at 2–4 ms, but surface phases still reach 111 ms across these two runs. |
| `restore-final-opengl2/` | Immutable six-world save restores its five resident members, arrival cinematic finishes, ordinary movement and saving resume | Historical controlled fixture; includes cancelling initial preparation. No fresh traversal claim. |
| `region-save-final/`, `crossing-final/` | Actual A/B save/death restoration and retained-connection A→B→A movement pass | Controlled actors/placement/health edits and one corridor. |
| `aggregate.log`, `python-final.log`, `lightmap-defect/` | 48/48 steps, 402 Zig, original 85 Python tests and both new actual C renderer roots pass. Subsequent driver batch: 86 Python tests pass. Removing only GL1's upload yield in an isolated source copy fails the interleaving assertion | Assertions remain enabled. C roots check interleaved owner uploads/pixels, merged deluxe pairs and a guard-page-protected single-lightmap lump. No production mutation for the defect run. |
| `bridge-retreat/`, `bridge-open-bank/` | Failed legitimate-checkpoint boss encounters | Driver no longer loops at the northern obstruction; avoidance still fails to keep Hiro alive. No damage, geometry or class-rule change. Improve prediction or use a legitimate supply route before further retries. |
| `fresh-opening/` | Failed ordinary-input development replay on **superseded** `258815…`, combined `e537ba…` | Full intro/arrival and bridge progression reach the boss; driver falls into water and loses its firing lane. Cannot establish the consolidated-build fresh milestone. |
| `lan-final/` | Two real UDP clients pass movement/fire/death/respawn/spectate/rejoin/reconnect/fast restart | Existing lifecycle scope; no target-contact, full modes/bots or public-service acceptance. |

Campaign driver repairs distinguish a terminal damage event from an actor leaving
the local owner, maintain combat during health-tree climbs, observe a health pickup
and its consumption despite damage during the approach, and try one ordinary jump
at a confirmed blocked bank lip. The actual final-bank replay on unchanged `187506…`
reaches e1m2a alive with all nine arrival shots and retained identity/connection:
`runtime-zig-305/factory-bank-input/`. Checkpoint progress never transfers to a fresh
run. Full-route acceptance now separately requires all ten observed bridge wave
actors; a checkpoint encounter reports only the waves actually observed.

Earlier `loader-opengl1/`, `loader-opengl2/`, `restore-opengl2/` results belong to
`258815…` and are superseded by the final replays above. The remaining texture
admission stalls, unreviewed seams/transforms, multiple portal views, wider actor
navigation/party interactions, residency and full campaign/multiplayer remain open.

## Sequence 305 — specialized weapons across seams

Immutable build `18750658f9ccb2d67fe6f782a277dcb754fafadbeb26058e236ec474171c5c13`;
combined identity `abaccd1628f849daca0e1c96b1df01de9232dc33543e2ad466baf63dbed7ada3`.
Base assets `e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`;
HD `d2e8d95bdbcb52de5529d932d8a3be378b46ac293fe2ec15849c7ac2d299c645`;
region manifest `f0cb127dcc3fa705a51cc5d9fd597960396e7bfdc3ca2cc55e709998e6a1368d`.
Evidence: `zig-out/reports/runtime-zig-305/`. Protocol 1349 and renderer ABI 12
unchanged. The native build is coherent; diagnostic setups are not campaign play.

| Evidence | Verified outcome | Setup and limits |
|---|---|---|
| `nightmare-final/` | Real attack captures the required B-owned worker, transfers the ritual into B, restores the same ritual/victim and actual body freeze, then damages/releases that victim and completes | Controlled dry grounded worker, player placement, health and equipment. The ritual processes its other acquired actors first; bounded driver wait follows the actual required victim. |
| `wyndrax-final/` | A-owned wisp acquires the B worker, saves/loads with the same controller identity, then damages the required foreign target | Real class actor and input; controlled placement/equipment. Not every fade, bounce or cancellation interaction. |
| `metamaser-final/` | Thrown cube moves A→B, reaches tracking, saves/loads the same controller and damages the B worker afterward. Original save inspection also proves the B cube damaged and retained a lock on A-owned fly 357 before saving | `saved-owners.json` retains actual physical owner, lock and Hurt receipt (source Hiro, weapon 26, damage 40), rather than inferring ownership from birth ID. Post-load fly contact is logged but its then-current physical map is not separately asserted. Not destruction-controller acceptance. |
| `zeus-final/` | Pending chain saves/loads with the same identity, then ordinary delayed strike damages the B worker | Pending phase only; not a restored expanded branch graph. |
| `trident-final/`, `ballista-final/` | Actual three-tip Trident launch contacts the B worker. Ballista contacts and reports skewer of that same real foreign actor | Dry, uncharged Trident contact; not merge/water. Ballista contact/skewer only, not carried crossing, pinning or active transport restoration. |
| `discus-final/`, `c4-final/`, `sunflare-final/`, `stavros-final/`, `shockwave-final/` | Each ordinary attack damages the required B-owned worker while Hiro remains in A | Controlled setup and actual qualified target ray/contact; no blanket return/pickup, remote chain, water, secondary blast or reference presentation claim. |
| `sentry-final/`, `spit-final/` | Real Rockgat attack and identified Froginator spit again contact Hiro across the seam | Controlled class placement; frog setup checks grounded, dry and actual attack occurrence. |
| `foreign-final-opengl1/`, `foreign-final-opengl2/` | Glock/Ion/Sidewinder qualified foreign contact, owning model registry and late resource publication replay in both renderers | Synthetic target/equipment and one aperture. |
| `region-save-final/` | Independently modified A/B actors and player state restore after real save/load and death/reload | Diagnostic placements, ownership and health edits. |
| `pursuit-final/`, `companion-final/`, `crossing-final/` | Real Slaughterskeet pursuit and Superfly follow cross B→A and restore their identities/health/authored home. Ordinary player A→B→A movement retains connection, input and identity | Controlled initial placements and class spawns; one corridor. |
| `lan-final/` | Two actual UDP clients pass movement/fire/death/respawn/spectate/rejoin/reconnect/fast restart | Existing lifecycle scope, not full modes/bots or public service acceptance. |
| `legacy-visited-final/`, `cinematic-restore-final/` | Unmodified older archives restore all 53 checked actors at installation; schema-2 migration/reload and obsolete-command rejection replay. Six-world factory cinematic restores/completes and ordinary movement/saving resumes | Historical immutable fixtures, not fresh campaign traversal. |
| `aggregate-final.log`, `python-final.log`, `c4-regression/` | 44/44 steps, 402 Zig and original 81 Python tests pass; actual C contracts execute. After the driver correction, all 82 Python tests pass. Removing neighbor detonation from a temporary source copy fails the C4 assertion (`expected 2, found 1`) | Runtime/catalog roots use ReleaseSafe assertions, other roots Debug. Production code was not modified for the defect run. The 18 affected driver contracts also pass in `driver-regressions.log`. |
| `fresh-opening/` | **Failed driver observation:** ordinary New Game reaches living normal e1m1a after intro/arrival; it stops before saving because sampled shot 69 was missed | `observation-diagnosis.json` records actual server transition evidence. Finished cursor 115 cannot replace a missing shot. This run remains failed. |
| `fresh-opening-events/` | Full intro/arrival and save/load pass; route fails at the first tree while a live mosquito blocks the jump | Driver had disabled combat on the supply climb. Game build unchanged; this remains a failed fresh run. |
| `factory-checkpoint/`, `factory-retirement-events/` | First run fails when a killed mosquito retires between observations. Corrected replay uses the tree, operates both factory controls, restores the monitor, rides both lifts and defeats the lower Crox; movement stops at the final bank lip | Legitimate checkpoint development, not fresh acceptance. The lip rises above its destination waypoint; driver repair/replay pending. |
| `marsh-defender-events/` | Both marsh health-tree climbs and retained A→B crossing complete from a legitimate checkpoint; bridge health check fails under a pursuing Crox | Actual samples show the 25-point pickup, masked by damage over the whole approach. Driver must fight the visible Crox and confirm item consumption plus the observed heal. |
| `fresh-opening-defenders/` | Fresh normal-input route reaches the bridge boss, then dies during combat | Immutable `187506…`; full intro, arrival restore, marsh supplies, ordinary A→B crossing and bridge controls traversed. Failed full milestone. |
| `bridge-defender-events/`, `bridge-local-tracking/` | First run loses local tracking of an actor near the seam; repaired run collects health/ammo and reaches the boss, then gets stuck retreating at the northern edge | Legitimate checkpoint development. Missing local actors never imply death; retain actual terminal damage or lost-target evidence. |
| `factory-bank-input/` | Actual lower-bank movement, Crox encounter, authored e1m2a exit and all nine arrival shots complete alive with retained connection/identity | Unmodified legitimate factory checkpoint on `187506…`, not fresh campaign acceptance. |

Implementation also covers Hammer radius recipients, NPC offset muzzle ownership,
Metamaser destruction controllers, class-owned liquid/visibility masks, projectile
step guards and global cancellation. Lightning hops attach to their physical
source separately from player ownership. Persistent references remap after all
foreign presentation slots exist; Metamaser laser endpoints remain coordinates.
These paths have only the contract/runtime coverage stated above.

Failed setups and superseded builds are retained. The first worker-health setup
could not address a foreign actor; read-only/controller diagnostics and the
explicit health fixture now resolve persistent identity. The next Nightmare
driver timeout expired while earlier acquired victims were being processed;
Wyndrax's post-restore driver awaited damage logging with `developer` disabled.
Both driver repairs preserve class timing, damage and acquisition. No failed
setup is counted as weapon acceptance.

Selected weapon screenshots were inspected. Developer output still reports an
invalid frame on a marsh swap model (`d1_swp3.dkm.md3`); finer presentation remains
open. No private reference implementation or original assets enter the source tree.

## Sequence 304 — actor and party ownership

Immutable build `0262fb30b698ef5ff862e23df2f37ae32fcb4adf210c3250477a99a9ac4dedef`;
combined identity `d2bb6e1d893f014c64c65bfd4f69cec75b95d97d24dade5c4186b8ba118ee710`.
Base assets `e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`;
HD `d2e8d95bdbcb52de5529d932d8a3be378b46ac293fe2ec15849c7ac2d299c645`;
region manifest `f0cb127dcc3fa705a51cc5d9fd597960396e7bfdc3ca2cc55e709998e6a1368d`.
Evidence: `zig-out/reports/runtime-zig-304/`. Protocol 1349 and renderer ABI 12
are unchanged. Original saves and the installed game were not modified.

| Evidence | Verified outcome | Setup and limits |
|---|---|---|
| `sentry-final/`, `spit-final/` | A real B-owned Rockgat acquires and hits Hiro in A. A real Froginator launches an identified spit controller which contacts Hiro and deals damage across the seam. | Controlled placement, real class spawns and player health. Frog additionally uses explicit seed 1 and checked dry grounded setup. Class decisions, damage, geometry and puzzle rules unchanged; no authored encounter claim. |
| `pursuit-final/`, `companion-final/` | Slaughterskeet pursuit and normal Superfly follow input physically cross B→A, preserving identity, health, threat/party ownership and authored home. Both actually save/load with those properties retained. No connection restart during crossing. | Controlled starting positions/spawns. One corridor; not broad ground/air/swim navigation, rescue/cut scripts or full saved-controller acceptance. Initial rendered enemy/companion frames were inspected. |
| `foreign-final-opengl1/`, `foreign-final-opengl2/` | Existing confirmed foreign-target ray, ordinary Glock/Ion/Sidewinder input, damage, owning renderer and late resource definition replay. | Synthetic target/equipment, one aperture; not all specialized weapons or reference presentation. |
| `crossing-final/` | Ordinary movement through the actual A→B→A brushes retains identity, input, health and connection; save succeeds. | Controlled initial approach. |
| `region-save-synchronized/` | Modified authored actor health in both A/B worlds, hero inventory/health and identity restore after actual save/load and death/reload. | Diagnostic placements, health edits and ownership commands; not continuous campaign traversal. |
| `legacy-visited-final/` | Unmodified sequence-294 flat archives restore all 53 A/B actor identities/health before simulation; later class-owned retirement, controlled visits, schema-2 reload and obsolete-handoff rejection replay. | Original fixture untouched; not fresh traversal. |
| `cinematic-restore-final/` | Unmodified six-world fixture restores, factory cinematic completes, ordinary movement resumes and saving succeeds during preparation. | Same sequence-301 controlled fixture as 303; no fresh intro/factory progression. |
| `lan-final/` | Two real UDP clients replay movement/fire/death/respawn/spectate/rejoin/reconnect/fast restart. | Existing LAN lifecycle scope; full modes and public service remain unverified. |
| `aggregate-final.log`, `trigger-regression/` | 44/44 steps, 400 Zig and 81 Python tests pass. Runtime/catalog roots execute with ReleaseSafe assertions; other roots use Debug. Actual C contracts also execute. A temporary defective trigger comparison fails the new owner assertion. | The first aggregate had one undersized test fixture (`Capacity`); its repair and focused runtime replay are in `checks/`. Production capacity was unchanged. |

Implementation also connects class-owned ranged/melee effects, qualified radius
recipients, accepted-motion ownership through alternate step probes, attached
bursts/personal actions, typed clock restoration, cross-world use/order targets,
party exit capture and map-owned named/script/death outputs. These are
implemented/contract-tested where covered above, **not blanket engine acceptance
of every class or authored action**. Script programs remain local converted
assets, loaded by authored home; no private reference implementation is imported.

Earlier failures are retained. `spit-initial/` used a fixture that jumped and bit,
so it cannot establish spit behavior; `spit-final/` checks grounded/dry setup and
actual launch/contact. `region-save-final/` used a pre-region driver timeout before
initial admission completed. Its synchronized replay waits for the real admission
event and removes the redundant preload request; no game loading behavior was
changed for that driver. The initial three narrow passing actor cases used build
`22c438…`; final cases above replay them on `0262fb…`.

Remaining work includes specialized player weapon interactions and muzzle-origin
ownership, authored party pickup/teleport/cut coverage, broader navigation and
witness/hearing behavior, multiple/recursive views, remaining seam qualification,
resource eviction/admission stalls, fresh campaign and complete multiplayer modes.

## Sequence 303 — connected views and qualified combat

Immutable build `f9ba99b696f7ac14bf84776586b4affcee55b42b27c439690e26c30e319b6b11`;
combined identity `5f174004f53ad81db214e07b8c84591e34358b03c99e30a0600715426c20c9cd`.
Base assets `e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`;
HD `d2e8d95bdbcb52de5529d932d8a3be378b46ac293fe2ec15849c7ac2d299c645`;
local region manifest `f0cb127dcc3fa705a51cc5d9fd597960396e7bfdc3ca2cc55e709998e6a1368d`.
Evidence: `zig-out/reports/runtime-zig-303/`. No fresh campaign route is claimed.

| Evidence | Outcome | Limits |
|---|---|---|
| `foreign-final-opengl1/`, `foreign-final-opengl2/` | Qualified ray confirms B-world target contact while the hero stays in A. Normal attack input from Glock, Ion and Sidewinder reduces health. Target model is submitted through its owning renderer; a newly registered episode-two model reaches B while the hero remains in A. Normal/destination-only screenshots retained. | Diagnostic placement, equipment and synthetic `runtime_target`; one aperture, no authored encounter/pursuit, fresh route or reference-presentation acceptance. |
| `crossing-final/` | Ordinary movement after controlled approach enters B and returns to A with retained identity, health, input and connection; region save succeeds. | No continuous opening campaign route. |
| `legacy-visited-boundary/` | Unmodified sequence-294 fixture restores all 17 A and 36 B actors with exact health at the actual installation boundary. Hero identity/health, controlled visits, schema-2 save/reload and obsolete-handoff rejection pass. | 36 already-dead actors subsequently retire through observed class-owned gib cleanup; their later absence is not presented as restoration loss. Fixture unchanged. |
| `cinematic-restore-final/` | Six-world saved factory arrival restores, cinematic completes, movement resumes and saving succeeds during further preparation. | Earlier controlled fixture, not full intro or fresh factory traversal. |
| `lan-final/` | Two real UDP clients exercise the complete existing lifecycle scenario on protocol 1349. | Full multiplayer modes/online service remain unverified. |
| `aggregate-final.log` | 44/44 steps, 398 Zig and 81 Python tests pass; actual C owner/collision/inline-handle checks execute. New ownership, slot leases, aperture, cycle, config/ack and party contracts execute explicitly. | Supports the narrow engine cases; it is not campaign acceptance. |

Useful earlier failure/repair evidence is preserved:

- `foreign-combat-grounded/`, build
  `9add9da80de1d5f3dfa3963db9a91d6b0a2f75aeeb86a0e7e61c0aa6b1431322`:
  a checked trace reaches the target's actual B-world slot while the player remains
  in A. Ordinary Glock, Ion and Sidewinder attack input reduces its health without
  a handoff or reconnection. No rendering claim on this build. The preceding
  `foreign-combat-initial/` setup failed while aiming during a fall and is invalid.
- `aperture-opengl2-debug/`, build
  `3cbfe91cb550c02318b1e718720904c4300f0f23d89f58b701a46308046f6f21`:
  actual GL2 crash backtrace reaches `R_DlightBmodel` through the resident portal.
  A source brush was indexed against destination surfaces. Both renderers now
  filter scene entities and polygons by checked owner before generating surfaces.
- `qualified-snapshots-opengl2/`, build
  `1e648c7718893d0ba5aea08debe9ea8ec48f2ec7179950cafcf86aec2d2ee73c`,
  combined identity `efc1aea42f1f0ce7f3ee040bce21691848b68c5ff3752a9ac2e3cfee2cb87e25`:
  the same attack diagnostic passes with the foreign target actually submitted
  through its own model registry. Normal and destination-only screenshots were
  inspected: the target is visible beyond the seam. This establishes that narrow
  view, not multiple simultaneous/recursive portal composition or actor pursuit.
- `foreign-combat-config-opengl1/` and `foreign-combat-config-opengl2/`, build
  `08d9e620a0d0a55bfa25bbddadce8b13cd9b62ba9c0883d19a1a3c7a7b2fc93d`:
  resource-publication regression fails with `InvalidSoundPath` and reliable
  command overflow respectively. Repairs preserve newer active configstrings,
  prioritize resource definitions and bound outstanding update chunks by actual
  client acknowledgements. The scenario now also demands a model newly registered
  in B while the player stays in A; the final replay above proves its delivery.

Protocol 1349 carries each entity's resource owner and persistent identity.
Foreign presentation borrows transport slots without duplicating ECS actors or
solids. Owner-scoped media, interpolation keys, transient effects and collision
queries prevent local slot/resource aliases. Ordinary multiplayer arenas retain
match boundaries. Party birth-ID rebinding and all specialized cross-world weapon,
actor/companion/navigation, multi-aperture, resource eviction and further seam work
remain separately unverified or incomplete; earlier full scenarios need revalidation.

`legacy-visited/` and `legacy-visited-lifecycle/` used observations after gameplay
resumed, so ordinary corpse removal raced the assertion and even the requested
save. The final runner requires an opt-in, read-only ECS audit before simulation,
then accepts later absence only with an actual class-owned retirement event. All
restored health is checked before that allowance. No damage, corpse lifetime or
world simulation was changed to make this probe pass.

The first aggregate passed all 398 Zig checks but caught an engine config helper
inside the pure domain layer. It now lives in the client adapter; the final suite
passes without weakening the architectural boundary check. Main, preserved game,
user saves and live service remain unchanged.

## Sequence 302 — visited migration and admission lifetime repairs

Consolidated installation `10b056cafcf909dd3114a3e6dd97bd40bfe302de30a00daffdfbf5b4595f7581`;
combined identity `93ed84bcc6e64b701b3991e8176d4111adf9a1600df61401c53f0e350bad4733`.
Base assets `e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`;
HD `d2e8d95bdbcb52de5529d932d8a3be378b46ac293fe2ec15849c7ac2d299c645`;
local region manifest `af0c2eea2324fd08577c5db4a0293175424540d1b94e3b3f1babd843d8835320`.
Evidence: `zig-out/reports/runtime-zig-302/`.

| Evidence | Outcome | Limits |
|---|---|---|
| `legacy-visited-final/` | Unmodified sequence-294 save loads into C with hero 574 at health 89. A/B archives become namespaces 1/2, preserving all 53 recorded actors' health (42 dead), without stale player copies. Both maps are inspected in-engine, schema-2 save/reload succeeds, and a handoff plus load in one command batch correctly discards obsolete world commands. Original fixture hash remains `7e3a04f8e4dcb4c7eaae9ede1c41f71941a369d0109526b6288a4b76dd5dbf73`. | Controlled transfers/placement for inspection; no ordinary traversal or fresh campaign claim. Broader saved controller/party combinations remain unverified. |
| `cinematic-restore-final/` | Six-world save restores in GL2; the saved factory arrival cinematic advances through completion, normal movement resumes, and saving succeeds while the next region preloads. Final rendered frame inspected. | Immutable controlled sequence-301 fixture, hash `4d04edef2e1f2d2cbaca9a0ace7610fc48c3b72b0609e6d670fa597c91271b73`; not full intro or connected factory progression. |
| `automatic-crossing-final/` | GL1 automatic A→B→A authored touches preserve identity, health, input and connection after inline-model ownership changes. | Controlled initial approach; no portal view or cross-world combat claim. |
| `lan-final/` | Two real UDP clients pass movement/fire/death/respawn/spectator/rejoin/reconnect/fast restart with the new cgame initialization boundary. | Full multiplayer modes remain open. |
| `aggregate-final.log` | 44/44 steps, 387 Zig and 81 Python tests pass; actual C collision/owner-allocation/inline-handle contracts execute with assertions enabled. Migration roots explicitly execute. | Contracts support the narrower running scenarios above. |

Before/after evidence is retained. The additional sequence-301
`six-world-cinematic-restore/` run fails on the renderer's shared 1,024-model table.
`cinematic-restore-inline-models/` on `63d52…` passes that allocation point, then
fails on the supplied `global//e_forcefield.wav` spelling. Map-owned brush handles
and sound separator normalization repair those defects; no substitute asset or
raised global model ceiling is used. `cinematic-restore-normalized-sounds/` on
`2f4b6…` first passes complete cinematic restoration; the consolidated run above
replays it after the reliable-command repair.

`legacy-visited/` has an invalid driver timeout: root restoration completes before
required region admission releases input. The driver now waits for actual processed
input with the bounded restoration timeout. `legacy-visited-synchronized/` then
preserves and inspects both worlds but fails its second load with `WorldNotAdmitted`:
an unexecuted world-entry command belonged to the old gamestate. The final replay
explicitly queues that race and records the obsolete command's sequence before the
new gamestate boundary. Current-map readiness errors remain strict.

The full fresh opening milestone, portal clipping and qualified cross-map gameplay,
other seam geometry, party identity/transfer, residency eviction, admission stalls
and complete campaign/multiplayer acceptance remain open. Earlier broad scenarios
are historical evidence and require replay after the shared owner/restore changes.

## Sequence 301 — automatic region progression

Current installation `af499dc7237f74b162e5a6d49ea7b55758c1b2b22b2440bc5a07335833c945c9`,
combined identity `ff127b1a20c07fc3fcfdcb16b395773f8899ddcd837cb447db239dad637012e7`.
Base assets `e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`;
HD SHA `d2e8d95bdbcb52de5529d932d8a3be378b46ac293fe2ec15849c7ac2d299c645`.
Local region manifest SHA `af0c2eea2324fd08577c5db4a0293175424540d1b94e3b3f1babd843d8835320`.
Evidence: `zig-out/reports/runtime-zig-301/`.

| Evidence | Outcome | Limits |
|---|---|---|
| `automatic-crossing-owned-memory/` | A→B→A authored touch handoffs retain player 341, health, command time and ordinary movement, without Server Initialization or ClientBegin. | Controlled approach placement; not continuous campaign acceptance, portal views or cross-map combat. |
| `authored-cuts-opengl2/` | Skipped intro invokes its authored exit, all seven A arrival shots complete, and the C exit reaches prefetched e1m2a. Connection retained through both cuts; six worlds save and reload. | Explicit transfer to C and placement inside its exit brush. Final restored sample is in the saved M2 arrival cinematic; full intro, factory puzzle and complete cinematic restoration are not inferred. |
| `lan-owned-memory/` | Two real UDP clients pass movement/fire/death/respawn/spectator/rejoin/reconnect/restart after allocator changes. | Full multiplayer modes remain open. |
| `six-world-restore-owned-memory/` | Actual saved e1m2a plus intro/A/B/C/e1m2b restore after cancellation of initial preparation. Every member reaches client readiness; player 433 retains health 100 and processed input; resaving succeeds. | Immutable controlled save from `authored-cuts-controlled-overlap/`, not fresh campaign evidence. |
| `aggregate-final.log` | 44/44 steps, 384 Zig tests, 81 Python tests and actual C collision/owned-memory checks pass. | Assertions enabled; all intended roots execute. |

Regression history is retained. `authored-cuts-cinematic/` on `6eb60…` exhausts
OpenGL2's fixed zone while preparing the next region. `authored-cuts-controlled-overlap/`
on `6b260…` completes both cuts and saves, then the fifth restored map exceeds the
four-reader admission limit. `six-world-restore-window/` on `efc409…` restores all
members, then navigation exhausts the fixed zone while preparing the next region.
The final replay repairs both ownership capacity defects and the admission queue.

`authored-cuts-initial/` has cinematics disabled and is invalid setup.
`authored-cuts-renderer-memory/` samples the single normal handoff frame before
arrival playback, then transfers during that cinematic: invalid setup.
`authored-cuts-synchronized/` reaches the unchanged locked factory door, which blocks
its diagnostic approach. The focused cut test explicitly places inside the supplied
exit brush; it does not qualify unlocking or traversing the door.

`geometry-candidates.json` and its recorded analysis driver retain registration
candidates for other exits, not admitted portal transforms. Prior campaign and
cross-world action scenarios need applicable replay. No fresh opening or full
campaign acceptance is inferred from these subsystem results.

## Sequence 300 — resident region save and death restoration

Verified installation `c8b457464b3fdf7d48dd3de77248314667a744a39872e5c8c970da7fbcc4d118`,
combined identity `9d91f01c0fc2fbdd98c24261c3c465c4ab3a38900416aba4f941c246718727fe`.
Base assets `e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`;
HD SHA `d2e8d95bdbcb52de5529d932d8a3be378b46ac293fe2ec15849c7ac2d299c645`.
Evidence is under `zig-out/reports/runtime-zig-300/`.

| Evidence | Verified outcome | Limits |
|---|---|---|
| `region-save-active-snapshot/`, `region-save-opengl2/` | A actor 9 and B actor 16777312 have saved health 37/53. After changing both to 9/7, actual load restores both. Player 341 saves in B with health 73, dies in A, and recovers in B with health 73; returning to A retains its saved actor state. Native input resumes after client readiness. Captures inspected. | Controlled placement, health and transfer commands. Saving/reloading a region restarts the connection and asynchronously prepares its member maps before control; this is not seamless travel or continuous campaign acceptance. |
| `legacy-schema-one/` | Actual sequence-296 single-world save restores health 73 in A and can be resaved by schema 2. Original fixture remains unchanged; source hash and driver recorded. | Old flat visited archives remain readable, but their conversion into simultaneous region namespaces is still open. |
| `lan-regression/` | Two UDP clients pass movement/fire/death/respawn/spectator/rejoin/reconnect/fast restart after the snapshot admission correction. | Other modes and full campaigns remain open. |
| `aggregate.log` | 44/44 steps, 383 Zig tests, 79 Python tests and actual-engine collision contracts pass with assertions enabled. | Contract evidence supports these narrow scenarios. |

The regression detects `SnapshotWorldMismatch` on build `b26e55…` in
`region-save-opengl1/`. Native cgame previously ingested `SNAPFLAG_NOT_ACTIVE`
loading frames before ClientBegin. The fix follows the bundled engine's existing
connection contract, retains active-world validation, and the repaired runs observe
the actual inactive frames before both successful restorations.
`region-save-initial/` is invalid setup: a sloping placement enters the return trigger.
`region-save-safe-setup/` stops at the diagnostic's old `sv_cheats` restriction after
load. These results do not count as region restoration passes.

## Sequence 299 — resident client admission and player transfer

Verified installation `3647922bc510e353c08ae9c595919a33685146e3eb6dbe8607e1c35fe533c429`,
combined identity `ba5b77659ac22f9925c747c93c75521af2079ca766d12f90741ba8c3c615a114`.
Base assets `e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`;
HD SHA `d2e8d95bdbcb52de5529d932d8a3be378b46ac293fe2ec15849c7ac2d299c645`.
Evidence is under `zig-out/reports/runtime-zig-299/`.

- `transfer-initial/passed.json` (OpenGL1) and `transfer-opengl2/passed.json`:
  actual checksum/media readiness precedes three transfers. Player 341 retains
  health 100, weapon/ammunition and monotonic command time. Position is copied
  without a landing teleport; gravity continues normally during observations.
  Client prediction and ordinary movement work in B, without server initialization
  or ClientBegin. Captures inspected. Controlled placement and explicit transfer
  commands make these subsystem diagnostics, not authored campaign acceptance.
- `aggregate.log`: 44/44 steps, 381 Zig tests, 79 Python tests and actual engine
  collision contracts pass with assertions enabled and all intended roots executed.
- `lan-regression/result.json`: two actual UDP clients pass movement, firing,
  death/respawn, spectator/rejoin, reconnect and fast restart on protocol 1348.
- Earlier `admission-initial/` verifies B/C/e1m2a admission on installation
  `e3a84ae8830e937d778531ca931a8d0f31d3cba4096103598a19e909176437e4`.
  It predates the wire/transfer changes and does not extend the coherent transfer
  result to all three destinations.

Protocol 1348 explicitly qualifies the active snapshot world and forbids cross-world
delta baselines. Live service is unchanged. Full campaign, remaining multiplayer modes,
restoration and effects require applicable replay after these shared changes.
Region save/restore and active encounters across boundaries remain unimplemented;
the diagnostic transfer is not exposed as ordinary travel yet.

## Sequence 298 — resident rendering and gameplay ownership

Verified installation `046e4b21e4992c3983ee9cd5a50c96bb0237341e845ead17c53a515c2d88b599`,
combined identity `06da21e56dd1705e128883060e48949ce8e14144e2333016868767568ff687e8`.
Base assets `e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`;
HD SHA `d2e8d95bdbcb52de5529d932d8a3be378b46ac293fe2ec15849c7ac2d299c645`.
Evidence below is under `zig-out/reports/runtime-zig-298/`.

| Evidence | Verified outcome | Limits |
|---|---|---|
| `world-contexts-contacts/passed.json` | A retains input and save/load while B/C/e1m2a retain 518/518/455 entities. All 27/81/65 actors return actual dynamic collision contacts in their owning world; navigation queries return 6098/3961/315. Dormant actor health/position hashes survive repeated selection, A movement and A restoration. Releasing all three preserves A. | Controlled preparation, not traversal or region-save restoration. |
| `render-staged-opengl1/`, `render-staged-opengl2/` | Both neighboring static maps render with distinct inline handles; original A view restores. Captures inspected. Surface preparation yields across frames. | No portal clipping, actor transfer or frame-time acceptance. Largest steps: B 26 ms in both; C 91/101 ms. |
| `lan-regression/result.json` | Two actual UDP clients retain movement, fire, death/respawn, spectator/rejoin, reconnect and fast restart after server/AAS ownership changes. | Existing arenas; full modes remain open. |
| `presentation-opengl2/passed.json` | Real New Game, intro skip, native Marsh presentation, save/load and pause pass on the same build. | Full intro and connected campaign were not replayed. |
| `aggregate.log` | 44/44 steps, 379 Zig tests, 79 Python tests and actual-engine collision executable pass with assertions active. | Supporting contracts, not campaign acceptance. |
| `connections.json`, `seam-vertex-evidence.json` | All 84 maps inventoried; 32 authored cuts, 92 geometry-unreviewed exits. Opening corridor geometry supports identity transforms. | Four missing named landings remain; no seamless portal qualified. |

The initial `world-contexts-opengl1/` failed a navigation setup assertion: the
literal e1m2a start sample was outside an AAS area. Its replay uses z=441, inside
area 315; this changes only the diagnostic sample. Earlier `3c96d…` renderer and
`bd44be…` gameplay-context results are superseded by the consolidated identity above.
Existing full campaign results require replay after these shared ownership changes.
Ordinary exits still load maps. Player/world transfer, qualified snapshot/resource
identities, portal rendering/combat and atomic region persistence remain unimplemented.

## Sequence 297 — resident collision preparation

Verified installation:
`zig-out/native-dev/play/feeda104ab302c3a0aac69c07ccaa6bb2a4ba553e8239a88f6584600b2b348bc`.
Combined engine/modules/renderers/assets identity:
`1ee73a1054d8554a6e6b14f1d07bc838f944147761413f5bc029b5174c9b594b`.
Asset generation remains
`e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`;
default HD overlay remains `d2e8d95b…645` from sequence 295.
Evidence root: `zig-out/reports/runtime-zig-297/`.

| Evidence | Exact outcome / limitations |
|---|---|
| `resident-opengl1/passed.json` | Four separately owned maps reach collision readiness while e1m1a remains active. Floor traces hit each actual destination; normal movement, save/load, release and generation reuse pass. Controlled preparation commands, not a campaign crossing. Owner-thread admission measures 7–9 ms; no frame-time guarantee. |
| `presentation-opengl2/result.json` | Existing real New Game, intro/arrival Escape, movement snapshot presentation, save/load and pause pass after the shared collision allocation change. Full intro is skipped. |
| `lan-regression/result.json` | Two real UDP clients pass movement/fire/death/respawn, spectator/rejoin, reconnect and fast restart. Existing match semantics; no connected multiplayer maps. |
| `aggregate.log` | 379 Zig tests, 78 Python tests and the standalone actual-engine collision contract executable pass; 44/44 build steps. Contract checks remain active independent of C `NDEBUG`; Zig roots use Debug/ReleaseSafe. |
| `connections.json` | Local inventory of all 84 supplied maps and 124 exits: 22 explicit authored cuts, 102 geometry-unreviewed exits, four missing named landings. No portal admitted as seamless. The initial episode-name filter omitted transition maps and was corrected before retaining this inventory. |

Ordinary exits still use the existing map-loading path. The accepted continuous
movement/cross-boundary combat plan is **incomplete**, not replaced with file-cache
warming. Collision preparation is opt-in through developer diagnostics until the
remaining owners exist; ordinary play remains available via `zig build play`.
No save schema or wire format changed in this slice. Prior connected campaign and
collision-dependent encounter results require replay on the eventual consolidated
region build; these diagnostics do not transfer that acceptance. The withdrawn
death-restoration report produced no gameplay change in this sequence.

## Sequence 296 — opening repair acceptance

Exact native installation `0c6cc7ebd055e0dcd902d2605d8c4c2389fd3642344066f1b34170282dca43b5`,
combined identity `bc98d6be01d9c0b82c99df73adf400061c264d478721e6a66844ed927cd9e2dd`.
Base manifest `e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff` and
HD SHA `d2e8d95bdbcb52de5529d932d8a3be378b46ac293fe2ec15849c7ac2d299c645` are unchanged.
All evidence below is under `zig-out/reports/runtime-zig-296/`.

| Outcome | Running evidence | Limits / remaining blockers |
|---|---|---|
| Ion electrical flight/light; Cambot lamp; smooth actor motion | `opening/`: real shots, rendered effects and intermediate positions inspected | Controlled placements/equipment; fine impact parity and all-class animation comparison open |
| Protopod hatches and enemy fragments render | `opening/`: actual authored pod spawns hostile skeeter; real shot kills pod and produces mechanical gibs | Close acquisition contract checked; not all actor deaths or gore presentation compared |
| Crox swims and attacks | `crox/`: observed water state, movement, pending-attack restoration and real 25.69-damage contact | Controlled position/health; not full amphibious traversal |
| Fire/jump reloads death checkpoint | `opening/`: actual deaths restore entry health 100 and manually saved health 73 after the four-second delay | Internal slot only; connected campaign death/visited-world replay still required |
| Destroyed bridge produces saved stone chunks | `bridge-camera/`: ten chunks visibly fly, then survive save/load | Diagnostic activation; connected encounter needs revalidation |
| Moving cloud/lightning shader active | `sky-repaired-driver/`: fixed camera, 12 captures, visible motion and illumination variation | Original lightning timing remains unqualified |
| Menu/cinematic/restore regression | `presentation-opengl2/`: real New Game/Escape, loading artwork, animation, save/load/pause | Intro skipped; not fresh campaign acceptance; existing `d1_swp3` invalid authored frame remains open |
| LAN regression | `lan-regression/`: two actual UDP clients, movement/fire/death/respawn/reconnect/restart | Full modes/public service acceptance still open |
| Applicable aggregate | `aggregate.log`: 379 Zig + 75 Python pass; five native roots execute 240 tests | Counts are supporting evidence only |

`82e96c…` / `presentation-initial/` is superseded and records the real incorrect
snapshot clock. `bridge/` lacks an aimed visual capture; `bridge-camera/` supplies it.
`sky/` fails driver setup before observation (missing Pillow); no product failure or
acceptance is inferred. The repaired driver uses installed ImageMagick. The full
[sequence journal](../specs/runs/RUN-dk3-independent-port.md#sequence-296--opening-gameplay-and-effects-repairs)
records implementation/reference boundaries. **The fresh opening gate is still not
accepted; earlier connected results require replay after these shared changes.**

## Sequence 295 — default HD textures

Plain `zig build play` now selects the admitted local HD image package from
the build prefix or shared `zig-out/hd-textures` cache. An explicit
`-Dhd-textures` package takes precedence. The isolated development installation
is `d9159285c80cceffca37abbe0d5ab582d260967db4964b1a780c25cdd29740dc`,
combined identity `2e0054e56e2893e26bdc08524ded2a47aa7c145bec9b413329e899dad10e4db5`.
Native code, both renderers and gameplay asset identity are byte-identical to
`a2f70c11…`; only the HD overlay and cosmetic compatibility field change.
The base asset manifest remains `e7dbc256…` below.

`runtime-zig-295/hd-default-repaired/` passes actual default-launcher admission
to e1m1a, full resolution despite saved `r_picmip 2`, and 22 renderer image
uploads matching the HD package dimensions above the original dimensions
(for example `mossrk_02`: 1024×1024 versus 256×256). The capture is inspected.
Six installer/media tests pass, including lookup precedence and unchanged
gameplay compatibility. The first `hd-default/` setup exceeds the engine's
32-startup-command limit and never loads the map; it is not acceptance.
No campaign or complete visual-parity acceptance is transferred by this check.

## Sequence 294 — presentation integration

Latest repair installation:
`a2f70c11a6a0395d5fc6041869f100394c3cf0eac41bac4b763b2f043ac0ba98`;
combined identity `af35d8e2c6c2e4a4d6d78065416b2d77d7fda48f11333adf448202bdefd1f22f`.
It passes **233** native contracts (150 runtime, 49 actor, 24 weapon, 2 inventory,
8 item). A subsequent e1m3a menu-save check exposed the laser/knight render-tag
collision; the new catalog uniqueness regression fails on that real duplicate,
then passes after assigning the knight policy its own tag.
`ui-saves-paused-fixture/` passes mouse-select-then-click Save/Load, corrupt-slot
rejection, actual health restoration and direct main-menu e1m3a load without a
Marsh detour. This uses explicit diagnostic placement, health and damage.
`ui-saves/` retains the renderer crash; `ui-saves-effect-tag-repaired/` invalidates
its setup because an actual enemy hit the player before the fixture established
its health. The final setup establishes and observes health while paused.
The changed tag affects knight attacks and unblocks actor lasers; earlier
all-class visual results remain unverified. The failed fresh opening used
one immutable `4c2502…` build below; it is not assembled from these runs.

`ui-menus/` on `4c2502…` also passes actual setting changes, binding conflict
cancel/replace and difficulty selection; its final Escape captures are not pause
acceptance, which belongs to the synchronized presentation probe. Seventeen
input-driver/evidence contracts pass. UI probes now record installation identity,
verify staged bytes and reject disabled assertions or existing evidence.

The integrated `zig build test --summary all` passes all 42 build steps,
372 Zig tests and 74 Python tests (`aggregate-passed.log`). The first aggregate
run retains a setup failure in the media-installer fixture: it mocked package
validation but omitted the completed asset manifest required at admission.
The repaired fixture provides that manifest without weakening the installer.

Consolidated installation:
`4c25028796de74cce9737556b75a39bc3292f7fdbd22c5d29103381f92f35314`.
Combined executable/modules/assets identity:
`1194391e024e485761e5da742dc7604d20433f37b8182a911a3996dcfd64690c`.
Asset manifest remains
`e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`.
Evidence is under `zig-out/reports/runtime-zig-294/`.

| Player outcome | State and evidence | Limits / remaining work |
|---|---|---|
| Select normal difficulty, skip intro and arrival with real Escape, resume with 100 health/ordinary glove, save/load and pause | Passed: `presentation-final-opengl1/`, `presentation-opengl2-sky-repaired/` | Skipped intro is a focused input regression, never full campaign acceptance |
| Original button and slider artwork, supplied Marsh loading plaque and progress, smooth intermediate model poses | Rendered/captured in the same two runs; images inspected; actual differing frames and fractional blends observed | Covers New Game/sound menus and one authored animated Hiro shot. Full menu layout, all actors and audiovisual reference comparison remain open |
| Restore an active factory monitor, operate both lifts, reach the authored e1m2a exit, finish its nine arrival shots | Passed: `monitor-factory-regression/`; living final state 89 health, 13 armor, 94 Ion | Legitimate sequence-293 console checkpoint; no earlier campaign acceptance transferred |
| Open the factory gate, clear the blocked doorway, cross the yard, use health trees, restore the active monitor, ride both lifts and reach e1m2a | Passed: `factory-gate-combat/` on `4c2502…`; all nine arrival shots finish with 89 health and 95 armor | Starts from the legitimate upper-control checkpoint. Earlier slope and pipe fixes have narrow evidence in separately failed runs, not a continuous factory or fresh-campaign pass |
| New Game → full intro → marsh → bridge encounter → factory → e1m2a | Failed: `fresh-opening/` on the consolidated installation above completes the intro, bridge and visited-world round trip, then the driver fails a factory slope jump assertion | Ordinary inventory/difficulty, no grants/placement or checkpoint substitution. Alive at failure; the complete fresh milestone remains unaccepted |
| Actual LAN client lifecycle / contested CTF after shared rendering and bot changes | Passed: `lan-regression/` exercises two real UDP clients through admission/movement/fire/death/respawn/spectator/rejoin/reconnect/fast restart; `ctf-regression/` records all four bots moving, picking up weapons, firing, receiving opponent damage and respawning, plus one contested capture | Does not close natural deathtag or complete multiplayer/public-room scope |

The 232 contract results (150 runtime, 48 actor, 24 weapon, 2 inventory, 8 item)
use installation
`6bf5b349dcffd1ea4ed5dffb744021242a52886f7dfde1388672a8f549cacbac`;
combined identity
`65468105f6a50c4160aa6010704bfa5e9ff2242f62f6069ffa3c981147cd49da`.
OpenGL1 presentation and the monitor checkpoint also ran there. Comparing the
installed manifest bytes shows the final `4c2502…` changes **only**
`bin/renderer_opengl2.so`; gameplay/client/UI, OpenGL1 and assets are identical.
The final OpenGL2 replay uses the actual OpenAL backend with its null output
device; this establishes execution, not listening-based sound qualification.

Failures retained: `presentation/` queried held establishing poses before any
authored animation and is invalid setup. `presentation-authored-pose/` confirms
that the original Escape hook was compiled out and opened pause instead of
skipping. `presentation-escape-repaired/` successfully skips the intro but the
driver presses Escape during the next connection and cancels it; the synchronized
replay passes on that same build. `presentation-final-opengl2/` reproduces
`SHADER_MAX_VERTEXES hit in DrawSkySideVBO()` on entering Marsh. The repaired
renderer reuses the source-polygon buffer after computing sky-face visibility;
its identical scenario now passes. Assertions remain enabled and the added
animation, interpolation and cinematic-audio roots execute.

The fresh route's slope failure is retained. `factory-slope-walking/` clears
that slope and resupplies, then misses the raised pipe joint. The repaired
`factory-joint-waypoint/` proves supported takeoff, actual jumping and gate
operation, then stalls against Froginator 456 while combat is disabled on the
doorway approach. `factory-gate-combat/` enables the existing ordinary combat
policy there and passes from the unmodified upper-control save through e1m2a.
These corrections affect only the input driver. They do not renew the failed
fresh route or change gameplay rules.

Actor/performer/scenery/remote-player rendering changed in this sequence.
Earlier broad visual results need affected revalidation; they are not renewed
by the single interpolated Hiro sample. Supplied decoration frames can still
produce renderer warnings (for example `d1_swp3` frame 2 with two model frames).
Complete weapon/actor interactions, remaining episodes, companion routes,
multiplayer/public rooms and independent release acceptance stay open.

## Sequence 293 — checkpoint progression and unresolved bot departure

`runtime-zig-293/visited-return-driver/` passes legitimate bridge-reward
checkpoint → resupply → C→B→C visited-world restoration → factory controls/pipe/
monitor/lifts → authored e1m2a exit and all nine arrival shots. Final state:
89 health, 13 armor, 100 Ion ammo. Installation `57afcd…`, combined identity
`97ba4cb3c64e3f917322ff90f092d9a1b35efc3260ff4fe0aea1d38f6df7d9ee`;
229 contracts pass. Exact full installation IDs are in the sequence-293 journal.
This does not repeat the boss/death encounter before the checkpoint.

`lift-exit-geometry/` records real westward walking through the authored
teleporter; its requested lower-floor assertion was unsuitable, so it remains
failed. `lift-teleporter-recovery/` on `57afcd…` and
`lift-trigger-contact/` on `512eb1…` both carry the controlled bot on the lift
but still fail to select the departure passage. No natural capture is accepted.
No geometry, damage, enemy or puzzle rules were changed for driver convenience.

## Sequence 292 historical integration evidence

All runs retain the asset manifest below. `zig build play` continues to build and
launch the native development installation with separate saves.

- Water-jump installation
  `de45755964a5b0c6cc489ee4d7036c07be80b5461dd6ce787e24ab34382d2f22`
  passes 228 native contracts; combined identity
  `17b3120f52ffb5788525f65ca1d20e46eeff95249db099cb9b169e0d71235ba1`.
  `runtime-zig-292/ctf-waterjump-regression/` passes all four bots' movement,
  pickups, attack, opponent damage and respawn, plus one contested capture.
  `deathtag-waterjump/` still fails capture after carriers appear. The outbound
  path requires damaging slime as well as water-jump travel; the first read-only
  route diagnostic omitted that explicit permission and remains failed.
- Read-only route-observation installation
  `c81263026da2d17e2bfe5cbc8d7f9143f8321d05bf4b26446681c296f46bbab9`, combined
  identity `9372e4fc48deab295c802c877fdabb3108aad82f8cf6f8d4e248243881dd7596`:
  `deathtag-slime-waterjump-routes/` reaches all three destinations (90/60/1
  edges) with explicit slime permission. Supplied-graph analysis confirms no
  outbound path without both permissions. This is route feasibility, not actual
  water contact or completed traversal. `fresh-opening/` completes all 115 intro
  shots, marsh, bridge boss/all ten waves, reward contact, death/reload, the
  north-tree resupply and first factory arrival. After disk save/load and an
  authored return to the bridge, restored progress matches. The driver then
  oscillates outside its 32-unit return waypoint and times out, alive with 75
  health. **Fresh gate failed; driver failure, not game death or disconnection.**
- Scheduled-lift installation
  `08642247fd1ef54fb7b40b95260b81984f7b44053e0531583d1eb7699c8f6450`
  passes 228 native contracts. Lift centering now requires actual motion or a
  scheduled return that approaches the requested floor. The added stationary
  carrier regression rejects the former indefinite wait. `lift-departure-before/` reproduces the carrier waiting on the raised lift.
  `lift-departure-after/` selects the real lower route but still cannot depart;
  `deathtag-scheduled-lift/` remains a failed natural match. No departure/capture
  acceptance is claimed. Campaign behavior is unaffected.
- Descent-observation installation
  `da72b58b1c975b939f5118988f11654ab253d772155beaeec13e9c308176e647`
  passes 228 native contracts and its affected `ctf-lift-regression/` passes.
  Downward floor changes now seek a physical controller, preserving the vertical
  trace when standing on a mover. `lift-departure-floor-trace/` still fails:
  the controller search selects a remote prerequisite behind the same descent.
  The observed AAS waypoint lies beneath the raised platform. A locally clear
  route off its edge must be established before further natural deathtag replay.
  The intermediate `8496ea…` build was contract-tested only. Seventeen driver/
  evidence checks pass. The fresh campaign retains its unchanged `c81263…`
  installation; these later bot-only changes do not alter its gameplay.
- `factory-walking-takeoff/` fails because it jumps before reaching the raised
  pipe joint. `factory-joint-takeoff/` observes the supported joint, crosses the
  pipe, opens the gate, traverses the yard, operates/restores the monitor and
  rides both lifts, then dies to a Froginator near the lower landing. Both use
  legitimate checkpoints on `0bfdec…`, not fresh acceptance. `factory-side-tree/`
  starts from the legitimate yard checkpoint on `c81263…`, successfully uses
  authored tree 428 and rides both lifts with 58 health, then dies to Crox 160
  in the lower pool. `factory-lower-crox/` clears that Crox from the dry bank
  with actual contact, reaches the authored e1m2a exit and completes all nine
  arrival shots alive with 58 health. These are checkpoint results. No damage/
  geometry/enemy/puzzle rules were changed for these driver corrections.

## Build and asset identity

Sequence 291 separates ordinary play from controlled damage/lift diagnostics.
All installations below use asset manifest
`e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`.

- Read-only damage/ground observation installation
  `2b7895321ce99ca74d8214edcf60b9655009de6ce38976c4e4d5b3247b94b60c`, combined
  identity `4e0a777ef0d07adb0f27f5d9cc08039589e073f46bfe61f48e88b07ebe5065b5`:
  `runtime-zig-291/fresh-opening/` reaches the bridge boss from New Game, normal
  inventory/difficulty and all 115 intro shots, then dies at the authored
  5000-damage barrier (source 126). Reload restores living arrival state; the
  route remains failed. `arena-damage/` defeats the boss and collects its 400 armor
  shield with **explicit 10000 health**, proving damage receipts/reward contact
  only. `bot-lift-controlled/` places one equipped bot on the lowered lift and
  verifies actual riding/objective contact. Neither diagnostic is campaign/match
  acceptance. `ctf-control-regression/` passes all four bots' movement, weapon
  pickups, attacks, opponent damage and respawns, plus one contested capture.
- Restart repair installation
  `b5cc3d6b5d59b73d8f03b34a0bef7e03efcee15b8fad3c1aa1463e1f7bf1fd10`, combined
  identity `177866301449b33451876b314a9418ad9f54a466479d1241d486babe55ce733d`:
  `lan-restart-repaired/` passes two actual UDP clients through the lifecycle
  above; rendered post-restart frames are inspected. `lan-synchronized/` retains
  the pre-repair `SV_Bot_HunkAlloc: Alloc with marks already set` crash. Earlier
  `lan-clients/`, `lan-clients-corrected/`, and `lan-lifecycle/` are driver setup,
  status parsing and reliable-command-throttle failures, respectively. LAN
  reconnect starts a new session; authenticated identity restoration is untested.
  `bridge-boundary-retreat/` starts from this fresh run's legitimate boss checkpoint,
  avoids the lethal east crossing but dies from boss spray; it is not completion.
- Bot ascent repair installation
  `0bfdec9bd5a2a4d75ff206012a608212175412050723bcfefe3a33607a4afa9d`, combined
  identity `f1ce5450bb03ed4935ea9b993a467ae685cf71aa571b40583f84fe09eb0303c9`:
  `bot-lift-approach/` reproduces oscillation below the raised lift and a later
  crushing death on `2b789…`. `bot-lift-ascent-repaired/` uses the same
  controlled gate/placement/equipment setup and verifies a real button press,
  lift travel and carried objective. No door timings or gameplay rules change.
  `ctf-ascent-regression/` passes all four participants' movement/pickups/attacks/
  opponent damage/respawns and one capture. `dm-restart-admission/` repeats real
  movement/pickups by all four bots, combat by slots 0/3 and respawn by slot 0
  after repopulating a fast restart. `dm-fast-restart/` was invalidated by the
  driver's admission counter retaining the first match's sample count.
  `deathtag-ascent-repaired/` fails capture after actual carriers appear.
  `deathtag-carrier-routes/` demonstrates no outbound route from area 6435 to
  3956 while its reverse and an adjacent control route pass. The supplied graph
  needs two water-jump edges, supported by the motor but omitted from route flags.
  `bridge-observation-batch/` uses fewer query round trips, defeats the real boss
  with ordinary checkpoint health/inventory, collects the shield and verifies
  death/reload plus C→B→C persistence. It later dies approaching the factory tree
  with four incoming health. `bridge-exit-resupply/` then uses the actual north
  bridge health tree, reaches 100 health, repeats the factory/visited-world
  transition and reaches the upper pipe with 71 health. Its failure is driver
  overshoot at a straight pipe waypoint. The safe approach region now retains
  actual height/ground assertions. `factory-pipe-approach/` passes that approach
  and the supported takeoff, then overshoots the upper landing after its jump.
  No fresh campaign result is assembled from these checkpoints.
  Consolidated checks: 228 native contracts and 17 driver/evidence checks pass.

Sequence-290 consolidated installation
`b55eef1a5de4fe3fdbb54020b83889f649264cb3b8a650690b19d9b868710e54`
uses unchanged manifest
`e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`.
Its 228 native contracts and 17 driver/evidence checks pass. Immutable-run combined
identity: `f31deb83ece0f3de17e7730797d948b1fb17131af838145e90051051842c602a`.

- `runtime-zig-290/cinematic-before-{e3m4b,e3m6a,credits}/` reproduces the three
  admission failures on the preceding `c3908767…` installation. The repaired
  `cinematic-after-e3m4b/` admits the map, retains normal control and restores a
  completed save. e3m6a then completes all 16 shots of its diagnostically activated mid-cinematic and restores; credits completes both shots and restores. These pass admission/playback/control restoration, not full boss/credits presentation or campaign completion.
  Explicit map admission and diagnostic triggers are not connected traversal.
- Item projections now clear a preceding sound event's frame/flags before publishing
  a reused slot. The poison-frame contract passes; running spawned-pickup rendering
  remains to be inspected. Earlier broken-ammo frames are not accepted presentation.
- `bridge-second-pool/` clears the omitted Crox from the dry bank and reaches the boss
  through ordinary movement. It then fails a blocked firing line. `bridge-open-bank/`
  and `bridge-east-plateau-coherent/` retain distinct failed combat strategies; neither
  is a completed bridge result. `bridge-wave-defense/` reaches the authored east 5000-damage barrier because its patrol is too wide. `bridge-barrier-clearance/` defeats the boss but dies to remaining attacks before collecting its shield. `bridge-reward-resupply/` retains another combat death before the reward becomes available; no bridge completion is accepted. Further combat diagnosis needs actual damage-source evidence before another route replay. No gameplay rules were changed for these driver failures.
- `bridge-east-plateau/` is **invalid setup**: a mutable build prefix changed while
  modules were staged. Its guarded process group was terminated and all acceptance
  rejected. Campaign/match runners now default to immutable installation files,
  verify identity and copied bytes, and explicitly label mixed diagnostic modules.
  A regression reproduces replacement between hashing and staging.
- `deathtag-control-continuation/` uses a recorded Debug diagnostic combination and
  demonstrates real prerequisite/final presses on both authored control chains.
  `deathtag-lift-rider/` on `c3908767…` still fails: all four bots move, collect weapons,
  fire, receive opponent damage and respawn, but no carrier appears. Rider centering
  is contract-tested; its complete lift/objective route remains unaccepted. No further
  unchanged long match is running. CTF needs affected replay after these bot changes.

Latest bot consolidation installation
`edf131c18aecec693aaae945bb0ab7dd9983a23781867eedaf7d7fd07a2b60b3`
passes 222 native contracts. `runtime-zig-289/ctf-consolidated/` revalidates actual
pickup, movement, attack, opponent damage and respawn by all four bots, with one
contested capture. Exact combined identity:
`b9cbc6d200b60bb8f8f5beddf68e60abfca67fd33cd2cbc997e92379c67f5331`.
`deathtag-consolidated/` failed its carrier/capture requirement. The fresh campaign below retains its
original immutable `0490b…` installation and staged modules; the later changes
affect bot control and optional pickup routing, not its campaign behavior.

Sequence-289 cinematic repair installation
`0490b20023b7306d69ee4088db4e70a5dc706cf4fdd45851afd67f7c8ce5f159`
uses the unchanged asset manifest below. `runtime-zig-289/factory-arrival-repaired/`
verifies normal contact with the authored factory exit, e1m2a admission, all nine
arrival shots and release alive with incoming health/armor/ammunition. It starts
from an unmodified legitimate factory checkpoint: no fresh gate is claimed.
Exact combined identity: `31b5d79d732239f1dd02c127318a39e597c6bdd4c6bee9dcd6e5a1c85f22e2ce`.
`factory-departure/` retains the former class-admission failure and demonstrates
the platform, upper passage, controlled descent and lower route on `fa467c…`.
`factory-exit-repaired/` retains the subsequent missing-sound client failure.
The preload repair follows unique-ID binding; absent authored sound media is
reported without aborting playback, matching the reference contract.
The native contract batch passes 222 tests; the driver batch passes 16.
`fresh-opening/` is a failed full campaign replay on `0490b…`: all 115 intro shots, arrival restoration, marsh traversal and bridge resupply run, then the driver enters the second pool with Crox 425 alive. Hiro still had 135 Ion rounds before death; the death state clears the inventory. Its automatic arrival reload verifies restoration only.

Read-only deathtag diagnostics under the same sequence establish separate failures:
closed lift doors whose buttons sit behind another named door, and a dry ledge
whose escape crosses slime. The observed player water level is **zero**, correcting
the earlier inference of a submerged player. `deathtag-controls-repaired/` proves
that accepting an initially solid floor trace alone does not clear the button
approach: the final standing hull intersects the second door. Debug-module
`deathtag-control-chain/` and `deathtag-control-escape/` demonstrate movement toward
prerequisite controls and combat/respawn by all four bots; the 120-second diagnostic
still has no carrier. These are diagnostic build combinations, not mode acceptance.
The latest safe-return pickup policy is contract-tested; deathtag capture remains open.

Sequence-288 installation
`fa467c30668dee2537bd194a18c872f57c3eb7d22f6bf1408655eaf743b48344`
uses unchanged asset manifest
`e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`.
Its 220 native contracts and 12 input-driver checks pass. Exact engine/module/asset
identities accompany each report under `zig-out/reports/runtime-zig-288/`.

- `visited-admission-repaired/` verifies same-map saved-resource admission, actual
  bridge surfacing, authored e1m1c arrival and C→B→C after disk save/load. Boss death,
  broken controls, remaining fruit and consumed reward persist. The later factory
  pipe driver fails while correcting a small overshoot; its legitimate takeoff
  checkpoint is replaying in `factory-pipe/`. No fresh gate is accepted.
- `portal-regression-before/` reproduces four AAS routing cycles on the old engine
  with the new read-only diagnostic module; it is deliberately a diagnostic build
  combination. Two unaffected local routes pass. `portal-regression-after/` reaches
  all six destinations on the coherent repaired build (up to 77 edges).
- `ctf/` verifies ordinary four-bot weapon pickups, actual combat/contact, deaths,
  respawns and one contested flag capture. `deathtag/` still fails: all bots collect
  weapons and move, combat/respawn occur, but no bomb carrier appears. Its remaining
  blocked corridors and an apparent submerged route required diagnosis (corrected
  above by actual water-level and collision evidence). This is not full
  multiplayer or human-network acceptance.

The prior surfacing repair (`5414bcb6…`, sequence 287) exposed reliable-command
exhaustion while restoring the visited bridge. Initial sequence-288 replay
`visited-restoration/` also failed same-map saved-resource replacement. Both failures
are retained separately; the successful replay above supersedes their repaired
restoration cases only.

Sequence 287 protocol repair installation
`807f488be71e81716955e106b77363730afe74bfd2a168f4a0e2ede6d1ea4a08`
uses the same asset manifest below. The snapshot wire now preserves native effect
tags and persistent identities; protocol 1347 rejects the incompatible older layout.
232 applicable native/codec/online contracts and 11 input-driver tests pass. The new
wire regression fails against the defective layout (`10002` becomes `18`). Evidence:
`zig-out/reports/runtime-zig-287/consolidation/`. The checkpoint bridge replay has
passed the former lightning/scorch client crash and collected health/ammunition,
cleared both ford Crox, defeated the boss and verified death/reload; it later failed
in campaign surfacing audio as described above.
Exact identity/inputs/frames: `runtime-zig-287/bridge-wire-repaired/` under the reports root.
Native effects and visual dispatch require revalidation after this shared wire repair.

The prior sequence-287 installation
`8dc7a3d6883645b84dc2b4ca8c52189b4a177ec245aedccafd4330761acf4053`
demonstrates natural four-bot DM movement, weapon collection, combat damage, kill and
respawn (`runtime-zig-287/dm/`). It does not establish complete DM or human networking.
CTF and deathtag fail their contested-capture requirements in separate directories;
deathtag does demonstrate combat/respawn. Read-only navigation diagnostics establish
that weapons and resting objectives need collector body origins, not model origins.
All eight CTF objective route lookups fail at raw positions and succeed with actual
body-bottom alignment (`runtime-zig-287/objective-navigation/`, Debug diagnostic only).
The subsequent `ctf-repaired/` and `deathtag-repaired/` replays on installation
`a501b7e9d11f623625cbe03ba3a63c668c2c393caeb86a56bc6933a8b87adfe7`
still fail natural captures. No carrier is observed. Short read-only route diagnostics
replace further unchanged long matches.

Sequence 286 launcher/save fixture uses installation
`ef7a0c105d1454316b4f6cc9793fb2dfe8be1e48143ede5aad255749ef75e04b`
and regenerated 1.3 asset manifest
`e7dbc2565c3c1f9ce1add690e6d713841d55d9ef740b3be85de7f4a3375df9ff`.
`zig build play` now rebuilds into the isolated `zig-out/native-dev` prefix and reuses
that completed local cache. The guarded launcher fixture opens native menus, admits
e1m1a, saves and restores gameplay, and exits cleanly. It disables cinematics and
selects the map explicitly: **launcher/save coverage, not campaign acceptance**.
Exact module/engine hashes, inputs and frames: `zig-out/reports/runtime-zig-286/play-final/`.
Preserved game/online installation links remain unchanged.

The coherent build and 216 native contracts pass, including map-spawn and telefrag
query regressions, chest/reveal rebasing, and save admission of non-solid world effects.
Three installer checks cover immutable generations, unchanged saves and refusal of
incomplete/corrupt inputs. Previous aggregate results for unaffected roots remain at
285 (138 other Zig tests and 64 earlier Python checks); no duplicate broad run.
Assertions are enabled. Evidence: `zig-out/reports/runtime-zig-286/consolidation/`.

First engine attempts exposed and retained two ECS query assertion failures, missing
non-solid effect save admission, and bot reliable-command overflow. These are repaired;
launcher map/save replay passes. The fresh normal New Game run observes all 115 intro
shots, saves at shots 20/50/80, restores arrival and collects/fires the Ion Blaster.
It fails at a lower marsh ledge with health 100 (`runtime-zig-286/fresh-opening-repaired/`).
Corrected normal-input routing reaches the authored e1m1b exit from a legitimate
checkpoint, then exposes the client wire defect (`runtime-zig-287/marsh-checkpoint/`).
These are distinct results across different builds, not one fresh completed playthrough.
No full connected gate is accepted.
The earlier inventory manifest `ba03d6e56c08eef76e9a79a32b2da6c223d68433293c9e4f3b2aecead0606dc3`
is superseded for new native engine scenarios.

Exact earlier verified segment identities, inputs, setup limits and superseded results
are retained in [the journal](../specs/runs/RUN-dk3-independent-port.md), including the
full historical acceptance ledger preserved at sequence 278. Evidence artifacts remain
under `zig-out/reports/runtime-zig-*/`. Controlled placement, grants and synthetic targets
remain subsystem diagnostics; none closes the continuous campaign gate.

## Revalidation and known limits

- Sequence 287 fixes the native effect snapshot field, bot/companion pickup goals and
  resting objective goals. Revalidate native effect rendering, companion item pursuit,
  multiplayer captures and the complete fresh campaign route on the consolidated build.
  Earlier effect screenshots with truncated tags cannot establish correct dispatch.
- Campaign surfacing audio no longer requires multiplayer Session. Revalidate actual
  swimming/surfacing on the consolidated build; sequence 287 verifies the repaired
  surfacing path before its separate visited-world failure. Character-specific
  multiplayer voice contracts remain covered.
- The marsh input driver now follows the lower west ledge after a fall. Engine/client
  disconnects invalidate the scenario immediately; a menu process is not a live server.
- Sequence 286 turns episode-three wooden/black chests into usable solid containers,
  with one-use opening, class rewards, delayed black-chest reveal and 25-damage trap.
  Contracts pass; authored use/reward/trap/save scenes remain unrun. Trap wood fragments
  and explosion particle presentation remain open; the supplied private `throw_debris`
  helper has no definition, so its launch motion is not claimed as qualified parity.
- Sequence 286 fixes wisp spawn and multiplayer telefrag queries, non-solid effect save
  admission and bot reliable-message acknowledgement. Intro and gameplay saves require
  replay; the repaired launcher fixture is the only completed current engine result.
  A rendered e1m1a fixture also reports out-of-range swamp-decoration animation frames;
  authored animation metadata/dispatch needs inspection.

- Shared changes require affected script/cinematic, damage, perception, companion,
  restoration/travel and multiplayer replay. Cambot now uses authored PHS; merged map
  areas remain an acoustics limitation. Earlier narrower PVS alarm evidence is superseded.
- Sequence 284 connects class-owned weapons-stay/respawn policy, actual-ammo death
  drops, player pain/death voices, saved damage blends, retained multiplayer attributes
  and credited kill rewards. Replay death, respawn, pickups, progression and restores.
- Sequence 283 adds companion injury receipt handling, grip-specific pain poses,
  retaliation and injury/death voices. Replay pain during scripts, combat and restore.
- Sequence 282 adds authored sight/frame sounds and weighted idle selection. Revalidate
  attack audio/timing, companion movement/fire poses and consumed-cue restoration.
- Sequence 281 prevents retained e1m2b editor-portal metadata from becoming a solid
  brush. Authored traversal at that location remains unrun.
- Sequence 280 adds fish/Dopefish/seagull controllers. Aquatic wandering now selects
  reachable water nodes; replay Shark/Crox wandering as well as the new fauna.
- Sequence 278 repairs the attractor query and half-square particle acceleration.
  Replay attractor linking, actor/weapon clouds, gibs, complex emitters and lightning
  sparks. Weather brushes now have no collision; verify physical traversal and visuals.
- Driver progression must synchronize connection, restoration, input processing,
  weapon readiness and save completion. Failed setup invalidates a scenario. Do not
  repeatedly replay unsuitable low-health checkpoints or change rules to assist inputs.
- Private behavior review guides contracts; it is not running reference comparison.
  Explicit compatibility corrections and finer presentation limits are recorded by
  sequence in the journal. Private implementation/assets are not public dependencies.

Debug/ReleaseSafe assertions remain enabled. `build/runtime.zig` explicitly executes
the native root and separate actor, weapon, inventory and item roots. Run one applicable
aggregate suite at the consolidated checkpoint; `make lint`, `make test` and
`zig build test` duplicate that suite. Replay affected regressions after repairs.
