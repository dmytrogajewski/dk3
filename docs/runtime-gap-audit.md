# Runtime gap audit

Current completion summary: [game status through sequence 200](status.md).
The entries below are historical findings and repair evidence; an initial gap is
not necessarily still present after a later batch. Full campaign and audiovisual
acceptance remain open. The latest weapon state is summarized at the end of this audit.

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

### Combat, pickup bindings and trigger contact (second shared repair batch)

Reference inspection exposed three distinctions lost by the native generic paths:
perception versus shot collision, attack range versus projectile range, and trigger
bounds versus solid brush contact. The e1m1b red barrier's `trigger_hurt` (`*32`,
`dmg=5000`) has a contentless collision brush. Exact solid-brush contact consequently
never activated it. Native trigger admission now uses the authored bounds for players,
actors and bot hazard avoidance, including brush event generators. Stock baseq3 keeps
its own contact path. Toggle-disabled hurt volumes require both toggle and start-off
flags. This shared change needs broader later-episode traversal coverage.

The thunderskeet now approaches above its target, holds position for its late pair of
shots, then retreats through collision-tested flight and the existing authored air
navigation. The supplied `attack_distance` (600 here) governs approach, independently
of projectile range (2000). Other actors no longer obscure perception; projectiles keep
their own collision rules. Its green/yellow sprite pulses, travels toward the target at
160 units/s, lights a 400-unit area, and deals a 40-point/256-unit contact blast instead
of creating a persistent cloud. Native pain admission uses its 10-percent reference
chance; a pain interruption retains the pending retreat. Cambots seek a height 72 units
above the target and retain a 72–192 horizontal separation band while alerting allies.
These are independent state machines, not an assertion of identical original navigation.

Froginator spit now uses the poison attack and the supplied sludge carrier at scale0.15,
with a six-unit hull. Client inspection found that the carrier is effect-only: it is now
hidden behind green CP4 particles and darker smoke rather than drawn as a brown bullet.
Small robotic deaths use scaled metal fragments and both supplied metal variants; scale
survives the existing local-entity tumbling update. Exact 1.3 gib selection remains an
open visual comparison: the reference source's robot-gib filenames are absent from the
supplied asset profile, which provides `e_metal1` and `e_metal2` instead.

Weapon pickups/held models and ammunition models had reversed bindings across Episodes
1–4. Shared bindings now distinguish them, including the counterintuitive ripgun/slugger
ammo filenames. Pickup collision bounds follow the supplied mesh and stock item gravity
settles pickups, including existing saved map items. Known old swapped bindings are
repaired on restore without changing custom models. Experience awards now use one tenth
of monster health multiplied by episode, and cumulative promotion thresholds start at
500 XP. Native level1 remains displayed level0; existing earned levels are preserved.
Ion uses additive illumination at the reference radius300, so it can illuminate dark
surfaces rather than only multiplying their existing light. Menu music plays the supplied
converted intro/loop. FFA converts authored team starts to ordinary deathmatch starts,
allowing the menu's CTF edition of “Gibbler On The Roof” to work in deathmatch.

Verification and limits (private evidence: `zig-out/reports/combat-reference-04/`):

- Integrated ReleaseSafe build and final `make lint` pass; 41 Python checks plus the
  existing Zig checks. The added asset-free C fixture exercises contentless trigger
  overlap, non-trigger fallback, cumulative thresholds and weapon/ammo identities.
- Fresh e1m1b barrier contact, without god mode: health100 takes damage5000 and the
  normal death-checkpoint path restores the world. The earlier run crossed its bounds
  without ever setting the hurt cooldown. No converter or asset-generation change.
- The bridge encounter spawns its boss. Live attack/retreat samples show paired linear
  toxic projectiles, the aircraft leaving its firing position and re-approaching using
  flight navigation. Captured paired globs and green surface illumination inspected.
  A first repair still stalled behind a mosquito; a second still stalled on scenery
  after retreat. Those failures drove the perception and navigation corrections.
- Live Froginator frame-event dispatch creates poison weapon11 at supplied speed400,
  damage5–10 and range450; its carrier scale/hull are verified. A fired projectile was
  held for a diagnostic rendered comparison; the final frame shows green particles.
- An ordinary Ion attack against a diagnostically positioned one-health frog produces
  its 3-XP kill award: XP497→500, native level1→2, one available attribute point. This
  tests real weapon/damage/death/progression delivery, not campaign traversal.
- A normal Ion shot kills a diagnostically positioned mosquito; the rendered death
  shows the smaller metal pieces after their tumbling update. Exact reference gib
  selection remains unverified as noted above.
- Restored Ion ammunition uses `wa_ion`, with model-derived bounds and settled ground
  entities. Narrowing the collision hull also lets the shelf-adjacent pack settle;
  the generic 32-unit hull had caught it on neighbouring geometry.
- Menu intro/loop decodes as 44.1kHz stereo Ogg and produces nonzero mixer samples.
  Audio runs use dummy SDL output; this establishes dispatch/decoding, not speaker quality.
- e1ctf1 with the player and seven bots reaches eight playing clients, combat and scoring
  without the reported spawn failure. An earlier run observes a bot alive after a death
  with its spawn count incremented. This does not close all multiplayer acceptance.

Public code still does not require the private reference source or executable. All
captures, saves and converted assets stay outside the public tree. Full campaign and
frame-for-frame presentation parity remain unverified.

### Ion surface-light regression repair

The additive-light change in the second repair batch bypassed the surface texture
in ioquake3's projected-light pass. A controlled Ion projectile at the marsh
waterfall reproduced the reported neon stripe on the slope. Private reference
inspection confirms that the original renderer adds dynamic illumination to the
surface lightmap before applying the material; it does not paint untextured green
onto the completed scene.

Both projected-light renderers now multiply additive illumination by the material's
animated diffuse texture, including its texture-coordinate modifiers. The existing
multitexture and GLSL paths supply this independently implemented correction. If a
suitable material or multitexture support is unavailable, the existing framebuffer
modulation path is used. Ion radius300 and colour(0,.8,0) are unchanged.

Matched camera/projectile captures show restored rock detail in OpenGL1 and OpenGL2
at the waterfall. OpenGL2's alternate forward-light path also renders successfully;
its existing attenuation is brighter and is not a visual-equivalence claim.
Live attack input consumes Ion ammunition and produces projectile/impact activity.
Private evidence: `zig-out/reports/ion-material-light-05/`. These are diagnostic
lighting scenarios, not an original-engine pixel match or campaign acceptance.

### Ion and rain source comparison (third presentation repair batch)

The supplied original screenshots expose effects missing beyond the surface-light
repair. Private reference inspection used `Projectile_fx.cpp` (`Proj_Ion_Fly`,
`Proj_Ion_Special`, `Proj_Ion_Die`), `ionblaster.cpp` (`blastTrack`, contact handling),
`cl_pv.cpp` (`CL_RainParticles`), `gl_particle.cpp`, and the beam texture bindings.
These supplied behaviour and asset contracts; no reference implementation was imported.

- Ion flight now composes four rotating, irregular lightning arms (24–32-unit reach,
  width6, initial alpha.75), the supplied .8-scale/.8-alpha flare, trailing beam sparks,
  and the source's150–450 green light variation. The tiny server-carrier mesh is no
  longer enlarged into the visible projectile. Rotation/emission use simulation time
  with a60Hz presentation reference rather than the original frame-dependent timing.
- Wall contact emits ten beam sparks and the supplied translucent `we_ioexp` mesh;
  terminal effects emit25 sparkle particles and a smaller, faint dissipating sprite.
  Beam textures come from supplied `w_zap001` and `beamspark` artwork. Liquid-discharge
  expanding rings and exact original beam tessellation remain outside this repair.
- Rain uses its atlas rectangle, a64-by2.56 triangular drop, initial effective opacity.2
  and age-based fading. Fall speed400, directional wind300, and area-based emission
  replace the generic glow ribbon and fixed700 speed. Rain parameters are refreshed
  when restoring old saves. Collision-triggered splashes use supplied atlas artwork.
  A bounded4096-particle pool and collision clipping are intentional implementation
  differences; exact original particle population/random phase is not claimed.

A preserved-original waterfall capture supplies direct rain evidence at the existing
comparison viewpoint. Its attempted weapon commands did not equip the Ion blaster;
that capture is not Ion-flight evidence. Ion comparison uses the supplied original
screenshots and the source contract above. Native OpenGL1 flight, rotated phases and
rain frames were inspected. In OpenGL2 an actual shot triggered wall contact at
(1684,-2272,511), normal(-.147506,.295012,.944039), and the impact/sparks were rendered.
One intermediate shader filename collision was fixed; final runs have no null-poly
shader or missing-image warnings. A debugger-terminated diagnostic caused the private
launcher's recovery dialog; dismissing it restored the OpenGL2 run. Failed probes are
not acceptance evidence. Private captures/logs: `zig-out/reports/ion-rain-reference-06/`.

Code-owned shader definitions now install with the runtime at
`share/dk3/scripts/dk3-projectile-weather.shader`; they reference existing supplied
artwork. Their hashes participate in runtime installation verification, separately
from gameplay asset identity. A synthetic regression verifies that updating these
shaders preserves that identity and that a damaged installed shader is rejected.

### Rain impacts on water (fourth presentation repair batch)

`CL_RainParticles` does not trace drops: they die at the volume floor (`height` below the
brush top), and splash sprites are scattered over that floor using `PARTICLE_SPLASH1`
or `PARTICLE_SPLASH3`, alpha .4, 101ms life, and a `4*(1+depth*.004)` leg length.
Authored e1m1a floors coincide with the water surfaces (352 and 288). Original volumes
use client-side lists culled only by horizontal distance, not PVS.

Three measured port defects prevented splashes on water:

- Drops traced solids only, so drops ending on the authored water floor never splashed.
  Rain now also stops at liquids, and drops reaching the floor unobstructed splash there.
  The per-drop trace is retained, so roofs still stop rain and receive splashes.
- Weather bounds used padded linked bounds (collision spread plus link spread): floors
  sat 2 units above the water and adjacent footprints overlapped. Authored bounds are used.
- The thin sky-level brushes were PVS-culled; at the waterfall only 12 of 45 volumes
  reached the client. Weather entities now link over their fall volume. Broadcasting
  was rejected because e1dt1 alone has 224 rain volumes.

Weather emission now scales by the fraction of the volume inside the ±512 emission
window and stops, like the original's exhausted list, instead of recycling drops that
have not landed. Old saves keep their saved bounds/linking until the map is reloaded.

Verified in native OpenGL1 and OpenGL2 at diagnostic noclip viewpoints over the e1m1a
pool: splash crowns render on the water surface; the pre-change installed build shows
none at the same viewpoint. Live client memory showed 45/45 volumes transmitted and 671
splash records at the water surface. A BSP check of 300 sampled splashes found 259 on
solids, 30 on liquids, 11 on volume floors and none beneath solid cover. The OpenGL2
yellow saturation near that pool also occurs with the prior installed build; it is a
separate, unresolved renderer defect. No ripples exist in the original rain path.
Exact original population, random phase and frame-dependent splash density are not
claimed. Private evidence: `zig-out/reports/rain-water-07/`.

## Native weapon review, sequences 199–200

All 28 weapon types now execute in native Zig. The Gold correction pass repairs
ammunition/cadence, damage and projectile behavior, supplied presentation bindings
and weapon-controller persistence. All 28 authoritative fire paths, representative
combat/liquid/network scenarios and C4/Hammer/Nightmare/Metamaser restores pass.
ReleaseSafe and one broad suite pass (43 Python tests plus Zig checks).

The initial C fixtures had assertions disabled by optimization; they now enable
them explicitly. The earlier liquid probe's position was outside the water volume;
the replacement asserts saved water level 3. Those historical checks must not be
used as evidence of contracts they did not actually test. Metamaser now reads its
supplied capacity/health/lifetime correctly and rebases packed lock deadlines;
Nightmare/controller links no longer masquerade as mover attachments.

See the [per-weapon matrix and evidence](../specs/runs/RUN-dk3-independent-port.md#weapons-gold-review--sequence-200).
Exhaustive target/material interactions, animation/audio/effect parity and all
campaign branches remain open. Bolter's water sound is absent from the supplied
profile. These repairs do not close the actor/companion, script, renderer or campaign
findings elsewhere in this audit.
