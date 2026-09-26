# Complete dk3: implementation, then gameplay verification

## Current completion state

Sequence 217 begins the accepted [native Zig replacement runtime](runtime-zig.md):
archetype ECS, parallel systems, separate native modules and an isolated installation.
The existing runtime stays default until implemented-scope acceptance passes.
This supersedes the historical C/QVM game-module guidance below.

Sequence 209 adds [configurable permanent rooms](online-operations.md#permanent-rooms)
entirely on the server, retaining compatibility with the already distributed RPM.
Focused acceptance verifies 16-slot bot filling, human replacement/refill, local
rotation with a connected human, and live Internet menu joins and timed rotation.
This does not close the broader multiplayer migration or campaign acceptance.

The active sequence 203 implements the accepted [native Zig multiplayer and Internet
room plan](multiplayer-zig.md). This extends the multiplayer implementation scope;
acceptance remains open. [Operations](online-operations.md) records the one-host IP
HTTPS deployment and explicitly trusted test certificate.

As of **sequence 200 (2026-09-25)**, this is a playable native development build;
the full game is incomplete. All 28 weapons are implemented in Zig, the Gold
correction pass has focused acceptance, and the latest build and broad suite pass.
Recorded authored campaign traversal reaches partway into e1m2b; no complete
episode has passed. V1–V12 below remain open as complete acceptance groups.
See [current status](status.md) for the subsystem matrix, known defects and evidence
limits. Historical scenario results below are not a fresh replay of the latest build.

## Outcome and decisions

Deliver the complete Daikatana campaign and multiplayer on a bundled modified ioquake3
engine. The fresh-checkout path is **clone → build → supply legally acquired assets → play**.
Development uses the [implementation-first workflow](development-workflow.md).

- Canonical development checkout: `dk3`, outside generated build directories. Preserve
  the existing `daikatana` workspace, playable installation, settings, and saves.
- Bundle complete ioquake3 source under `engine/ioquake3`, starting from upstream commit
  `588393618dbc82e7207c21c6ddecca229944a03a`. Preserve notices and third-party licenses.
- Standalone dk3 may change engine interfaces and protocol; stock Quake III compatibility
  is not a release requirement. Required improvements are part of acceptance.
- Reuse ioquake3 and reviewed independent components. Replace Gold implementations,
  interface headers, DLL emulation, mechanically translated code, and generated dependencies.
  Gold is optional private reference material, never a public build/check/runtime dependency.
- Native C game and client/UI foundations; Zig 0.16 build/tools. The owner-authorized
  [complete weapons rewrite](weapons-zig.md) uses native Zig on server and client,
  including shared prediction. C UI remains compatible with QVM tooling; the native
  Zig weapon modules are not a qualified QVM target. Use ioquake3 lifecycle and services directly.
- New versioned saves with no legacy migration. Original saves stay with the preserved build.
- Linux x86-64. All four single-player episodes, companions, cinematics, endings,
  deathmatch, CTF, deathtag, and multiplayer bots. Co-op and other operating systems are outside scope.

## How to execute this roadmap

The active repair pass starts with a subsystem audit, not another list of isolated
screenshot fixes. Inventory supplied animation and sound bindings, effect types,
script operations and target relationships, and death/travel/save lifecycle paths.
Classify missing contracts and shared implementation gaps before editing them; then
repair connected systems together and replay their scenario matrix. The current
[runtime gap audit](runtime-gap-audit.md) records findings and verification status.
Asset coverage and source inspection identify work; neither counts as gameplay acceptance.

The implementation pass covers Steps 1–9 in dependency order. Implement connected systems
across steps without waiting for every earlier acceptance box to pass. Track written code
as **implemented; unverified**, then exercise it in the separate verification pass below.
There are no baseline suites, per-item lint/test gates, line limits, mandatory per-item FRDs,
or automatic retry stops. A targeted build/probe during implementation is appropriate only
when it resolves a concrete uncertainty obstructing useful work.

Use existing tooling and the [run log](../specs/runs/RUN-dk3-independent-port.md) with
commands, inputs, results, and evidence.
A failed scenario prompts diagnosis, fixes, and affected-scenario reruns. Passing results
remain valid until relevant inputs change. Broad checks run once at the end; deduplicate
`make lint`, `make test`, and `zig build test` when they invoke the same suite.

## Implementation pass

| Step | Work | Implementation status | Acceptance status |
|---|---|---|---|
| 1 | Canonical checkout, bundled engine, build graph, provenance | Implementing; engine/native/QVM build foundation written | Isolated fresh native build and dedicated startup passed; optional QVM qualification and provenance review open |
| 2 | Complete independent asset pipeline and installation | Implementing; profiles, converters and installation graph written; 1.3 corpus packages installed; difficulty/mode navigation generates 97 AAS variants for 84 maps | First private conversion/install passed; retail and independence checks unrun |
| 3 | Native ioquake3 runtime, shared movement, dk3 state/protocol | Implementing; native modules and world lifecycle compile; protocol, entity capacity and audio interfaces extended | 84 server map starts exercised; three large client maps rendered; full runtime scenarios open |
| 4 | Opening sequence through the e1m1b bridge encounter | Implementing; triggers, exits, teleports, breakables and bridge earthquake/debris handlers written | Opening cinematic, ion combat and authored e1m1a exit into the corrected e1m1b entrance exercised; river combat, health-tree use, ammo pickup, level gain and attribute allocation exercised; bridge destruction, timed ten-mosquito formation, aggressive thunderskeet and boss defeat observed; authored exit into e1m1c exercised; fresh full replay open |
| 5 | Complete weapons, inventory, damage, and progression | All 28 selectable weapons implemented in native Zig; Gold correction pass implemented; inventory, attributes, drops, quest and travel systems written | Sequence 200: all 28 firing paths, representative damage/liquid/network scenarios, prediction contracts and C4/Hammer/Nightmare/Metamaser restores passed. Full per-weapon interactions, audiovisual parity and campaign progression acceptance remain open |
| 6 | Navigation, actors, companions, and bot foundations | Implementing; frame-driven actor combat, gravity, roaming, leaps and several special abilities, companion state/commands, authored graph/rail routing, difficulty/mode navigation selection and bundled BSPC integration written | e1m1c difficulty-specific navigation selection exercised; complete variant conversion passed; partial bot movement/teleports; actors and companions remain open |
| 7 | Scripts, cinematics, saves, UI, and presentation | Implementing; interpreters, staged saves, autosaves, scenery, effects, music and subtitles written; weapon holds/controller links and packed deadline persistence corrected | Earlier cinematic/lift/corruption/recovery scenarios exercised; sequence 200 verifies mid-action weapon restores and omitted-optional-field compatibility. Complete script, UI, audiovisual and cross-episode persistence acceptance remains open |
| 8 | Episodes 1–4 and complete multiplayer modes | Implementing; DM bots, native CTF/deathtag objectives, team spawns, host/join menus, carrier attachments and physical switch-seeking bots written | DM combat, team admission, CTF pickups/returns, uncontested captures and a five-capture contested bot replay exercised; two captures each on blue/red deathtag courses, including submerged routes; contested captures exercised; real network join/respawn/reconnect, visible protocol errors and host/join menus exercised; authored e1m1c and e1m2a progression reaches e1m2b; e1m2a lifts, remote doors, pump/cart route, collapse, rubble bridge, flooded passage and staggered ladder exercised; phantom AAS floors and cancelled bot jumps repaired, with both teams capturing in the affected four-bot deathtag replay; all 97 regenerated navigation variants load in the server, including the narrow-portal endpoint refresh; teammate yielding, broader network cases and remaining campaign traversal remain open |
| 9 | Release/install path and publication preparation | Implementing; bundled-source setup, private installation and CI/build documentation written | Isolated native build/start passed; source/publication review and complete play path open |

### Step 1: Canonical checkout, engine, and build foundation

Implement in the stable `dk3` checkout. Admit complete pinned engine source and reviewed
engine changes as ordinary source files, including submodels, entity extensions, drawable
size, loading, and audio. Compile from bundled sources instead of a sibling checkout or
cache-only patch tree. Preserve upstream identity and notices with the recorded base.
Restore the client, dedicated server, renderers, native module foundations, QVM compiler,
and original tools in the Zig graph. Default `zig build` builds available products.
The current upstream LCC compiler has separate sale restrictions in its COPYRIGHT file;
keep it optional while qualifying the all-open-source QVM path. This remains an open
release requirement, not a reason to stop independent native-runtime implementation.

Record a disposition for reused components, including movement translation units, headers,
generated registries, embedded content, converters, diagnostics, and client/UI code. The
historical 238 Gold translation-unit count is not the full dependency audit. Keep unresolved
components out of the public source set; no Gold-shaped replacement architecture.

Dependencies: existing published tools and pinned upstream source.
Files: `engine/`, `build.zig`, `build/`, `build.zig.zon`, provenance and build docs.
Risks: hidden dependency or copied implementation; review actual sources and include/generation paths.
Verification: V1, V2, V12 below; implementation does not claim game readiness.

### Step 2: Assets and installation

Bring across reviewed BSP, textures, models, sprites, shaders, sound, music, fonts, scripts,
and table handling. Preserve geometry, verbatim entities, target links, animation sequences,
and local overrides. Deterministic packages use explicit paths and identified retail/1.3
profiles. Missing input names the required file/profile; no source archives or reference
executable is required. Original art, dialogue, subtitles, and text come from supplied assets;
embedded proprietary UI prose is replaced with original dk3 text.

Wire `zig build assets -DDK_DATA=…`, `play-install`, and `play`. Install checks verify the
required files. A launcher must identify incomplete gameplay and never substitute the legacy runtime.
Dependencies: build/tool foundations from Step 1.
Files: `dkq3/tools/`, `build/assets.zig`, `build/play.zig`, asset/profile/install docs.
Risks: override precedence, missing retail inputs, conversion loss; retain manifests and named diagnostics.
Verification: V2, V3, V12.

### Step 3: Runtime foundation and shared movement

Use ioquake3 allocation, linking, collision, snapshots, lifecycle, commands, events, movers,
triggers, trajectories, damage, pickups, projectiles, filesystem, sound, rendering, and networking.
Add dk3 player, inventory, campaign, progression, and actor state with stable entity IDs.
Replace Gold edict mirrors, DLL lookup/import tables, function-pointer saves, and translated
movement. Extend shared ioquake3 movement/prediction for Daikatana requirements. Document
versioned protocol/state extensions rather than hiding unrelated values in spare fields.

Dependencies: bundled engine; converted map inputs when exercising the runtime.
Files: game, cgame, shared state/movement, narrow engine interfaces.
Risks: prediction disagreement and changed state layouts; shared rules and explicit wire contracts.
Verification: V1, V4, V10, V11.

### Step 4: Opening playable sequence

Implement e1m1a through the e1m1b bridge encounter: spawning, movement, ladders, water, doors,
switches, lifts, pickups, damage, death, ion blaster, initial enemies, script spawning, and
actual level exits. The bridge must break, arrivals must be timed, ten mosquitoes must
appear, and the thunderskeet must attack. Stationary actors or map loads do not complete it.

Dependencies: runtime interfaces; coordinate combat/actor/script work with Steps 5–7.
Files: game movers/triggers, movement, weapons, actors, scripts, campaign flow.
Risks: authored trigger order and cinematic cleanup; preserve target relationships and script state.
Verification: V4, V5, V6, V8.

### Step 5: Weapons, inventory, and progression

All 28 selectable weapons now execute in native Zig concrete types, with compile-time
interface checks and shared components. Prediction, combat/controllers, view/world
presentation, weapon sounds/effects, inventory exceptions, and restoration dispatch
through those owners. The removed C implementations are not linked. This explicit
owner-authorized exception supersedes the earlier C-only subsystem guidance. See
[architecture](weapons-zig.md) and sequences 199–200 in the run log. Sequence 200
adds assertion-enabled prediction coverage, confirmed submerged-player checks and
Gold behavior/save repairs; it supersedes the corresponding weaker assurances in
sequence 199. Full combat/progression acceptance remains open.

Implement all campaign weapons and attack families using ioquake3 foundations: ammo,
switching, melee, ricochets, return paths, splash, status effects, armor, artifacts, keys,
save gems, experience, attributes, and Daikatana sword progression. Read balance values
from supplied tables via reviewed parsers. Preserve recognizable behavior without retaining
crashes, invalid indexing, or frame-rate-dependent timing.

Dependencies: runtime state and events; assets/tables from Step 2.
Files: game weapons/items/damage/progression, shared prediction, cgame effects and selection.
Risks: state loss at transitions and incorrect attack interactions; scenario coverage per weapon family.
Verification: V5, V8, V9, V10.

### Step 6: Actors, navigation, and companions

Implement original perception, pursuit, attacks, pain, death, special abilities, and scripted
behavior with shared actor code. Reuse botlib/AAS for ground routing and multiplayer bots;
bundle a pinned GPL BSP-to-AAS compiler from bnoordhuis/bspc and generate navigation locally.
Parse authored flying/swimming/scripted routes independently; use original graph search and
ioq3 collision. Movers and blocked passages update traversal availability.

Complete Superfly/Mikiko commands, combat, pickups, progression, transitions, and campaign
availability. Implement doorway yielding, blocked-route recovery, and visible command feedback
without bypassing locks or progression.
Dependencies: runtime collision/state, asset navigation, scripts and combat interfaces.
Files: actors, navigation, companions, bot integration, bundled bspc and build steps.
Risks: invalid routes or bypassed locks; check dynamic obstacles and authored progression constraints.
Verification: V6, V9, V10, V11.

### Step 7: Scripts, cinematics, persistence, and presentation

Implement original asset script interpreters supporting spawn, movement, animation, dialogue,
waits, triggers, cameras, cinematic cleanup, and story transitions. Use simulation-time
scheduling and persistent named state/actions. Implement versioned field-based saves for
campaign, entities/references, inventory, companions, and scripts. Validate before replacing
the world; write atomically and preserve a recoverable previous save.

Finish independent HUD, inventory/weapon selection, menus, subtitles, loading screens,
effects, music, voice, and credits. Include scalable HUD/subtitles, readable widescreen
layouts, resolution-independent input, and clear rebinding conflicts. Missing assets or
unsupported operations identify map, entity, and operation.
Dependencies: state contracts, assets, actor/combat interfaces.
Files: scripts/scheduler, save format, UI/cgame/audio/effects, campaign transitions.
Risks: dangling references, interrupted writes, lost pending actions; explicit IDs and validation.
Verification: V7, V8, V9, V11.

### Step 8: Full campaign and multiplayer

Complete Episodes 1–4 in order, including unique monsters, weapons, bosses, puzzles,
cinematics, timestream transitions, and endings. Adapt ioquake3 multiplayer lifecycle,
scoring, teams, and bots for deathmatch, CTF, and deathtag. Matching dk3 clients/servers
use the documented protocol; incompatible peers receive a clear version message.
Dependencies: gameplay and presentation from Steps 3–7; implementation may overlap those steps.
Files: episode rules/encounters, multiplayer/team/scoring/bots, network diagnostics.
Risks: apparently loaded maps with broken progression; traverse authored routes and objectives.
Verification: V9, V10, V11.

### Step 9: Release and publication preparation

Provide the complete clone/build/supply-assets/play instructions with bundled engine and
reviewed code, notices, synthetic public checks, and explicit current feature status.
Publish reviewed components continuously within user authorization; do not describe the
port as complete before acceptance passes. Review the complete source tree for proprietary
content, binaries, generated assets, and hidden dependencies. Preserve the legacy installation.
Dependencies: integrated public code and installer; verification results determine release claims.
Files: README, license/provenance records, CI, installation docs and release metadata.
Risks: overstated readiness or leaked content; inspect admitted paths and verify the fresh-checkout path.
Verification: V1–V12; publication and release acceptance remain distinct from written code.

## Verification and repair pass

The owner's [opening presentation/combat defects](../specs/bugs/BUG-opening-presentation-and-combat.md)
are the active repair batch. Pause campaign route advancement until its menu/HUD,
cinematic, animation, scale, weapon, damage, boss, bridge-light and death behavior
has been repaired and inspected in the running game. Earlier traversal does not
close these appearance or behavior requirements.

Use the owner's 1.3 build as the private visual reference for this repair batch.
Compare matching menu states, HUD values, weapons, actor poses and cinematic shots;
using the supplied artwork alone does not establish a match. Measure the rendered
camera rather than assuming the reference's entity angles are its view angles.
The first comparison corrected the Disruptor model, finite weapon animation,
standing eye height, HUD proportions and main-menu layout. Menu options, world
lighting, actor scale and complete cinematic/combat comparisons remain open.
Record those differences in the existing bug/run log, then continue scenario repair.
These private comparisons introduce no proprietary public build/check dependency.

The follow-up repair batch covers revisited-world persistence, ion cadence,
post-intro placement, default local HD textures, menu animation/audio, mosquito
perception and attack sounds, player pain/hit feedback, loading plaques and marsh
effects. Opening exits now archive and restore world state; full saves include
visited worlds. Intro handoff, 500 ms ion hits, repeated mosquito damage and
audio dispatch have running-client evidence. Repeated bot deaths respawned on
e1dm1 and e2dm1; the owner's stuck-dead case remains unreproduced. Moving skies and
sky flashes render in both OpenGL backends after repairing duplicate cloud geometry.
The installed binaries and applicable tests/formatting checks pass. These findings
extend V3/V5/V6/V7/V8/V10 without closing their complete acceptance matrices.

Use existing runners/scenarios and add focused cases where a required path is missing.
Record configuration, profile, inputs, logs/captures, result, and invalidating changes in
the run log. The rows remain open until their complete acceptance evidence exists; partial probes are recorded in the run log.

- [ ] **V1 — Dependency independence:** build engine/modules/tools from the public source
  tree with the reference workspace unavailable; no Gold headers, objects, generation,
  libraries, executable, or runtime fallback. Check native and QVM module loading.
- [ ] **V2 — Asset independence:** synthetic public fixtures plus private retail and 1.3
  profile conversion; deterministic packages, overrides, and named missing-input errors.
- [ ] **V3 — Installation/start:** fresh source build, asset conversion, installation check,
  launch/menu/new game, both renderers, and clear incomplete/unsupported-input diagnostics.
- [ ] **V4 — Movement/world:** shared prediction, spawn, ladders, water, movers, switches,
  doors, lifts, damage/death, and smooth transitions without false ladder/mover behavior.
- [ ] **V5 — Combat/progression:** each weapon family, ammunition/switching, hit/damage/status,
  pickups/inventory, artifacts/keys/save gems, experience/attributes, sword progression.
- [ ] **V6 — Actors/companions:** pursuit/attacks/pain/death/abilities, ground/flying/swimming
  routing, dynamic blockers, companion commands/combat/pickups/availability/transitions.
- [ ] **V7 — Scripting/presentation:** scripted actions/cameras/cleanup, dialogue/subtitles,
  HUD/inventory/menus/selection/loading/effects/audio/credits; inspect rendered outcomes.
- [ ] **V8 — Saves/transitions:** save/load mid-action and mid-encounter, restored references,
  inventories/companions/scripts, authored level exits, corruption diagnostics, interrupted
  write, previous-save recovery, and validation before replacing a running world.
- [ ] **V9 — Campaign:** traverse authored progression in all four episodes, including the
  e1m1b destruction/timed arrival/ten-mosquito/aggressive-thunderskeet encounter, every boss,
  puzzle, cinematic, timestream, and ending. No forced changelevel/census substitute.
- [ ] **V10 — Multiplayer:** joins, movement/prediction, damage/death/respawn, scoring,
  deathmatch, CTF/deathtag objectives, bots, disconnects, and clear protocol mismatch handling.
- [ ] **V11 — Required improvements:** ladder/mover transitions, doorway yielding and blocked
  companion recovery without bypassing locks, scalable UI/subtitles and rebinding feedback,
  deterministic scheduling, save resilience, and contextual unsupported-operation diagnostics.
- [ ] **V12 — Final checks/publication:** applicable broad checks once after scenarios pass;
  complete source/provenance/license review, private-data exclusions, preserved local saves,
  and verified README clone/build/assets/play path. Refresh only results invalidated by fixes.

## Existing evidence and migration

The initial tools publication remains recorded in `specs/dk3/ROADMAP.md` in the legacy
workspace: commit `4db26797aee81e1f0ef35a53332d13b0e2245cf2`, 38 files, 38 Python checks,
and the published component build. This evidence is historical, not acceptance of the
new runtime. The legacy source-list inventory counted 238 Gold translation units and
242,483 lines before headers; movement, headers, registries, patches, and embedded content
still require separate disposition. Legacy roadmap ticks and private game evidence are
preserved but do not close V1–V12.

This revision replaces per-item completion gates with the implementation/status table and
one explicit verification/repair pass. It preserves the full approved port scope.
