# Runtime gap audit

The owner requests discovery by subsystem before grouped repairs. This audit compares
native code, supplied data and optional private 1.3 source observations. Reference code
is never an input to public builds or checks. Findings below supersede earlier isolated
presentation passes where those passes did not exercise the relevant lifecycle.

The initial private inventory covers 84 maps, 82 actor table definitions, 1,145 frame
event rows and 15 action-script packages. Of 244 event rows without a matching model
animation, 148 are sight cues across 57 class names: these are sound-only records,
not missing animation assets. The remaining rows need model/alias classification;
they must not all be called port defects. Eleven sound references have no matching
packaged path. Private detail and initial runtime observations are under
`zig-out/reports/gameplay-reference-03/`.

| System | Confirmed gap or observation | Repair and required scenarios |
|---|---|---|
| Animation lifecycle | Missing sequence requests silently select sequence zero. Rockgat has only `up`, so ordinary idle repeatedly raises it. Hatch uses a looping wait state. Leaps can be replaced by pursuit on the next tick. | Explicit closed/raising/open/lowering turret states; finite hatch and leap states. Pods also need their own 200/512-unit horizontal detection limits and collision-safe emergence space. Observe each transition and save/load while active. |
| Actor sound bindings | The loader discards sight rows without model clips; idle selection ignores supplied variant weights. Frog jump sounds are interrupted with the animation. | Independent sight cues, weighted ambient variants, uninterrupted action events. Exercise acquisition, pursuit, attack, pain, death and loss/reacquisition for representative actor families. |
| Item audio | Native pickup success changes inventory and hides the item but emits no pickup sound. | Bind sounds by pickup family; exercise health, armor, weapons, ammunition, boosts and artifacts, including rejected pickups. |
| Weapon impacts | Trace shots send no surface impact record. Projectile impacts lack weapon-specific contact sounds. Stock hit feedback adds an unrelated local sound. | Authoritative contact events with normals and weapon identity, supplied marks and impact audio; verify flesh, stone/metal, ricochet, water and no-impact surfaces. |
| Map particles | CP1/CP2/CP3/CP4 become generic smoke/sparks. Smoke grows despite no authored growth. All atlas particles use additive blending, accumulating excessive brightness. Quad rendering also samples neighboring cells in the overlapping triangular particle atlas. Direction spread is a perturbed vector rather than the authored angular cone. | Preserve particle type, blend, scale, direction and timing. Compare marsh waterfall mist and sparks, then non-marsh particle families. |
| Map lights | Episode flame classes all select one generic sprite. Flare model overrides and distinct flame/flare flag meanings are not retained. | Respect supplied models and class-specific activation. Exercise lit/off/toggled forms; lightstyle lightmap support remains a separate open contract. |
| Event generators | Touchable flag is checked in touch dispatch, but every brush generator is linked as a trigger. Generator audio is ignored; fired target diagnostics do not identify the activation chain. | Match touch/use admission, preserve authored sound and expose developer traces. Exercise delayed fan-out, one-shot reuse and save/load mid-sequence. |
| Bridge | Fresh e1m1b has all three bridge pieces and zero `doitall` uses. The touch brush is x[-962,-942], y[446,834], z[958,1090]. Both bridge cambots have authored `deathtarget=doitall`, intentionally allowing destruction before crossing if killed. | Verify normal crossing and cambot-death routes separately. Do not remove the authored early route to satisfy a screenshot. |
| Death and persistence | Single-player uses stock `ClientRespawn`, preserving the altered world. Reference single-player reloads its restart save; multiplayer respawns in the existing match. | Restore a validated campaign checkpoint on death; preserve map revisits independently. Exercise death after alarm/bridge activation, manual save/load, missing/corrupt checkpoint and DM bot respawn. |
| Script semantics | Supplied operations are recognized, but recognition alone does not establish correct waits, owner lifetime, activation or cleanup. Missing visual sequences are currently logged and skipped. | Trace complete opening programs and their target chains; classify missing clips per actor/model. Later episodes and full cinematic parity remain unverified. |

## First shared repair batch

Integrated engine/game and asset builds pass. Protocol 1344 adds weapon contact events
and reverse animation ranges; save schema 5 includes explicit turret state and campaign
death checkpoints. Sound-only sight cues, ambient variation, finite actor actions, pickup
sounds, impact marks/audio, supplied particle types/blending and event-generator admission
are implemented. Ion now uses the supplied firing sound, flyby loop, and three-contact
ricochet limit. The stock score-hit beep is replaced by weapon-specific contact feedback.

Private client evidence under `zig-out/reports/gameplay-reference-03/`:

| Scenario | Result and limits |
|---|---|
| e1m1a pod proximity and blocked emergence | Egg87 opens once, holds frame22 with health1, and creates a mosquito that acquires/attacks player0. Both close-player obstruction and approach outside the old 80-unit perception limit exercised. Saving/loading the open egg preserves state2/frame22. |
| e1m1b rockgat lifecycle | Closed state0 holds frame0; raised state2 holds frame10; supplied fire audio reaches the mixer. Moving out of range returns state0/frame0 without looping. Occluded-target and mid-transition restore cases remain open. |
| e1m1b bridge touch route | Diagnostic placement before the bridge followed by ordinary forward input triggers `doitall` once; all16 actions complete, ten scripted mosquitoes arrive, and the thunderskeet spawns. This is an encounter probe, not continuous campaign traversal. |
| Death after bridge activation | Ordinary kill/respawn input reloads the manual checkpoint: all three bridge pieces and zero `doitall` uses return; the encounter thunderskeet is absent. Corrupting the private checkpoint produces a checksum diagnostic and keeps the player dead instead of respawning into the altered world. |
| Health pickup | Real touch of an e1m1b health25 item increases health and dispatches `global/a_hpick.wav`; other pickup families still need individual scenarios. |
| Disruptor surface contact | Normal attack input produces the supplied wall mark, inspected in a rendered frame, and dispatches `we_dglovehitc.wav`. Moving-brush marks remain open. |
| Ion contact audio | Four shots dispatch `we_ionshootb.wav` and electron-contact samples, with no generic flesh-hit beep in the firing interval. Liquid, flesh and third-ricochet boundaries need dedicated replay. |
| DM restart separation | e1dm1 AuditBot goes from health-999/PM_DEAD to health100/PM_NORMAL through its ordinary respawn input. This guards the new SP restart branch; the earlier intermittent bot report remains unreproduced. |
| Marsh visual comparison | Original 1.3 capture reached by movement, then native diagnostic camera placement at (1642,-2305.375,526.75), yaw37.7594/view pitch5.427246, 640x480 (the reference position command reports the reduced model pitch1.81). Comparison exposed atlas triangle/quad sampling after additive blending was repaired; the repaired triangular footprint is inspected in `audit-waterfall-final-pitch.jpg`, alongside `reference-waterfall-facing.jpg`. World textures/lighting and random particle phase differ, so this is not a pixel-parity claim. |

Audio evidence is software mixer dispatch with dummy SDL audio. Source inspection and
asset inventories do not establish complete actor behavior or script semantics. Remaining
unmatched animation rows include chapter-specific cinematic models and obsolete optional
clips; they must be classified individually before changing assets or inventing aliases.

Next audit batches cover all actor animation requests against the selected model, complete
weapon/material contact families, lightstyles and non-marsh effect classes, then script
owner/wait/cleanup lifecycles and companion/campaign progression. Full campaign acceptance
remains open. Keep this matrix as the discovery/repair record rather than opening an
isolated issue for every screenshot.


### Whole-level darkness (display-path repair verified; owner display unconfirmed)

The owner clarified that the entire level is dark. Their settings use HD textures,
fullscreen OpenGL1, gamma1 and overbright1. A private SDL fixture that accepts but
ignores gamma ramps reproduces a separate display/screenshot mismatch: GL1 halves
fullscreen lighting, expecting a display ramp to compensate, while screenshot encoding
applies that compensation itself. The fixture establishes the renderer failure mode;
it does not prove that the owner's display ignores ramps.

Standalone dk3 now selects the existing software texture-gamma path in both renderers.
OpenGL1 consequently keeps its full lighting in the framebuffer in fullscreen as it
already does in windowed mode. No display gamma ramp is required. Video settings expose
Brightness, with Apply reloading textures through the existing video restart. Existing
gamma preferences are retained; no arbitrary brightness boost is applied to all maps.

The original1.3 reference run reports vid_gamma0.659 and gl_modulate1; dk3 uses inverse
exponent gamma and converted gl_modulate2 lighting. These settings and different gamma
capture paths preclude using the old reference JPEG as a pixel-brightness oracle.
The e1m1a conversion still drops style6 on20 faces at x[-960,-768], y[-1536,-1280],
z[411,672], retaining both style0 contributions. That localized gap is separate from
whole-level brightness and remains open. Private reproduction and comparison evidence:
`zig-out/reports/marsh-darkness-02/`; original report: `marsh-darkness-01/`.

Verification: the integrated build and one `make lint` pass succeed (40 Python tests
and the Zig targets). The ignored-ramp fixture previously showed static-region luma
7.08 on the X11 display versus14.49 in the engine JPEG. After repair, a paused scene
with dynamic lights disabled measures14.35 versus14.32; JPEG loss accounts for small
pixel differences. Live frames are retained but are not paired pixel comparisons,
since dynamic light and particle phases change. The fullscreen render configuration
reports software gamma/zero overbright; the windowed control retains the same lighting.
Xvfb reports a fullscreen window-manager timeout, so this verifies the renderer path
and X11 pixels, not physical compositor scanout. Both renderers load the marsh and
brighten with gamma1.3 after restart. Ordinary keyboard selection in Video changes
Brightness from1.0 to1.3; Apply reloads the renderer and returns to gameplay. The menu
and resulting images were inspected. Existing saves remain compatible.
