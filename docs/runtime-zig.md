# Native Zig runtime

Accepted 2026-09-26; implementation starts at **runtime-zig-217**. This decision
supersedes the general C/QVM requirement for dk3 gameplay, client and UI modules.
The Zig runtime is now the only source/build runtime; the old runtime is removed.
This is a development decision, not a claim of gameplay acceptance.
Implemented code and verified acceptance are tracked separately in the run log.

## Branch and layout

All unfinished runtime development is on `rewrite/native-zig-runtime`. `main` was
restored to the pre-rewrite working tree (`ed0755f`) by restoration commit `e3966c4`.
Do not merge or push this work to main without an explicit release/merge request.
The old-runtime removal decision applies to this feature branch.

The permanent source root is `src/runtime`, with `domain`, `ecs`, `engine`, `server`,
`client`, and `tests` layers. `build/runtime.zig` composes native modules and tests
from the same named dependencies. Class-owned catalogs live in `src/weapons`,
`src/actors`, and `src/items`. Architectural checks reject private gameplay headers
and engine/system imports from pure domain/catalog code. See
[`src/runtime/README.md`](../src/runtime/README.md) for ownership rules.

## Scope and boundaries

Replace all game-owned behavior, including Quake III game-module foundations under
engine/ioquake3. Retain engine rendering, audio, collision/BSP, platform, filesystem,
module-loading and other engine infrastructure. Retain existing Zig networking,
online services and guard; Python asset/development tooling stays supported.
Use Gold as private behavioral reference plus accepted fixes, never as imported
implementation. Preserve licenses and original installations/assets/saves.

Three native module entrypoints (server game, client game and UI) depend on explicit
engine adapters, shared domain rules and ECS infrastructure. Domain code cannot
import g_local.h, cg_local.h or engine globals. Engine-facing structs are transport
projections; authoritative state belongs to the server ECS. Client ECS owns replicated,
predicted and presentation state. Menu navigation uses ordinary typed state.
Pure weapon definitions and rules have one owner. Native ECS systems consume them
through engine adapters; do not maintain a second gameplay backend.

## ECS and scheduling

Use a project-owned archetype ECS with typed component registration, aligned chunks,
generational handles, independent persistent IDs and engine slots. No component
addresses or row indices cross structural barriers. Deferred create/destroy/add/remove
commands commit in deterministic system/job/entity order. Chunk storage and scratch
lifetimes are explicit and bounded. Authoritative capacity exhaustion is an error;
only documented cosmetic effects may be dropped.

Parallel systems declare component/resource reads, writes, dependencies and engine
thread affinity. Disjoint chunks may run concurrently; conflicts establish ordering.
All ioquake3 calls remain on the owning thread. Workers produce typed requests and
commands, engine queries resolve at barriers, and dependent work resumes in the same
step. Transactional pushing and order-sensitive gameplay commits stay serial.
Worker completion order cannot choose entity IDs, event order or RNG draws. Preserve
simulation time and input timing. dk3_jobs=0 runs inline; positive values select workers,
default CPUs minus one capped at eight. Join jobs before save capture, teardown/unload.

## SOLID / DRY / KISS

Each state and transition has one owner. Separate simulation, persistence and
presentation. Concrete actor/weapon policies satisfy checked contracts; shared
mechanisms do not become a universal behavior interpreter. Engine/test services obey
the same contracts. Separate collision/storage/audio/rendering interfaces; avoid a
service locator. Prefer compile-time composition and use runtime interfaces only at
real substitution boundaries. Share prediction/server rules and schemas. Keep the
ECS tailored to the game; no plugin or dependency-injection framework. Explicit state
unions, allocators and recoverable errors replace implicit flags/global mutation.

## Build and compatibility

Only the Zig runtime is built. The optional -Dgame-runtime=zig spelling remains
accepted for existing commands; legacy is rejected. Development installations require
their own prefix and isolated profile. There is no legacy gameplay fallback. ABI bridges remain mechanical and layout checked. Keep native module
exports and engine-facing layouts where practical; never expose Zig-native layouts.

Current schema-5 saves and optional fields, persistent IDs, relative deadlines and
visited worlds require explicit record mappings. Validate staged state before publish;
never serialize pointers, chunk memory or jobs. Retain protocol layouts where practical,
but require matching verified runtime builds; mixed-runtime play is not required.

## Connected implementation stages

1. Boundary, alternative build/module entrypoints and baseline replay harness.
2. ECS, parallel scheduler, identity/time/RNG, movement/inventory and weapon adapters.
3. World spawning, movers, interactions, combat, actors/navigation, companions/bots.
4. Scripts, cinematics, progression, travel and persistence.
5. Prediction, model/animation/effects/audio/HUD and complete UI/multiplayer flows.
6. Complete gameplay acceptance and qualify installation/release flows.

Implement connected code before systematic scenarios. Required acceptance includes
ECS relocation/stale handles/capacity, scheduler conflicts and worker-count equivalence,
all 28 weapons, implemented campaign systems, saves/recovery/visited worlds, recorded
regressions (including lifts, crouching, menu loads, Superfly and lasers), both renderers,
input/audio/UI, matching-build dedicated/Internet rooms, bots/reconnect/rotation,
compatibility rejection, and repeated performance/memory/query measurements. Audit
replacement builds for legacy C behavior and domain imports. Run the applicable broad
suite after integrated repairs, not per-item duplicate gates. Engine runs use dkguard.
Full four-episode completion is separate from implemented-scope acceptance. Keep the old
installation for rollback and preserve user profiles throughout.

## Active decision: runtime-zig-223

The owner requested removal of the old runtime, not parallel maintenance. Remove its
C gameplay/client/UI, C-dependent Zig adapters and old-runtime tests from the active
checkout. Keep bundled ioquake3 infrastructure, native domain policies, networking,
online services and asset tools. Upstream movement remains a test-only differential
reference. Engine save-envelope validation stays engine infrastructure; native save
restoration remains open. Git history preserves retired independent implementations.

Development uses `zig build game test-runtime --prefix zig-out/replacement`, followed
by affected isolated native scenarios. Broad checks cover surviving components once
per integrated batch. Do not add legacy parity adapters or require old-runtime builds.
Keep original installations and saves untouched. Removing old tests does not certify
their scenarios: actor witnesses, laser shutdown, scripts, full weapon effects and
campaign progression still need native implementation and acceptance.

Next connected work: weapon events → hit/projectile simulation → damage/death → actor
reactions, with simulation rules owned by domain code and collision/audio/rendering
resolved by explicit adapters. Then progression/scripts, persistence/travel, and UI.
The following checkpoints are historical and their old-default statements no longer
apply to the source/build policy.

## Foundation checkpoint: runtime-zig-217 (historical)

**The replacement is not playable and cutover has not occurred.** The ordinary
`dk3` installation continues to use the legacy runtime. Server, client and UI
entrypoints reject unqualified gameplay explicitly; they do not delegate back to
legacy game code. `play` and `play-install` reject the replacement selection.

Implemented foundation:

- Native module build, public-header ABI boundary and layout checks.
- Archetype chunks, explicit component IDs, generational handles, persistent IDs,
  deferred structural commands and independent engine-slot allocation.
- Bounded persistent worker pool, access/dependency scheduler, frozen schedule
  contracts and owning-thread engine collision barriers.
- Ballistic probe through that scheduler, exact engine-frame clock and relative
  deadline helpers. These are not replacements for player movement or actor physics.
- Map metadata ingestion retaining all authored properties; entity behaviors remain
  to be implemented.
- Portable existing save-record codec and read-only exact-roundtrip inspector.
  Gameplay schema validation, staged ECS reconstruction and save/load remain open.
- One shared inventory acquisition transition used by the existing weapon backend
  and the replacement Inventory component. Weapon controllers, policies and
  presentation still require backend extraction.

Stages 1–2 are partially implemented. Stages 3–6, player movement, playable
client/UI, full weapon adapters, persistence restoration and cutover acceptance
remain open. Codec validation and bootstrap probes are not campaign acceptance.

Build and exercise the isolated foundation with local converted assets:

```sh
zig build game runtime-audit --prefix zig-out/replacement -Dgame-runtime=zig
zig build test-runtime
python3 dkq3/tools/runtime_probe.py --engine zig-out/play/current --prefix zig-out/replacement
zig-out/replacement/bin/dk3-runtime-audit /path/to/existing.sav
```

The probe uses a temporary home, copies only the replacement server module, invokes
`dkguard`, and records logs/inputs in `zig-out/reports/runtime-zig-217`. It compares
0/1/4 workers and map restarts. The audit command only reads its input. Neither
command installs a replacement into the normal launcher or writes existing saves.

## Active implementation: runtime-zig-218

The native development client now connects with `dk3_runtime_probe=2`. All three
modules embed the same source rules identity; the UI advertises it before connect,
the server checks userinfo, and the client checks the server configstring. Normal
launch/install still uses the existing runtime. This is not a qualified playable
replacement, and the complete accepted migration remains active.

Implemented, with acceptance still incomplete:

- Shared native server/client player movement and collision adapters: crouching,
  stepping/sliding, jumping, water, ladders, gravity, spectator and noclip paths.
  ECS owns player, transform, velocity and weapon state; snapshots are projections.
- One pure catalog for all 28 weapon descriptions, input policies and supplied
  numeric tuning. Legacy and native adapters use the same firing/switching rules,
  inventory acquisition, sword calculations and special input transitions.
  Native shot events do not yet dispatch damage or projectile controllers.
- Native BSP/brush rendering, snapshot ingestion and command replay. Full HUD,
  model/animation/effect/sound presentation and actual UI screens remain absent.
- Binary translating/rotating doors, buttons and platforms, grouped travel,
  authored delays and dwell, accelerated/bouncing curves, transactional player
  pushing, use rays, rider-only automatic platform activation and door proximity.
- Bounded target routing and delayed actions, killtargets, repeated/once triggers,
  counters and relays. Authored key locks are preserved; key inventory, scripts,
  cinematics, trains, secret doors and other interactions remain open.

Focused evidence: 1,440 command frames agree with bundled movement on flat-ground
walking/diagonal motion/crouch/jump/gravity and shallow/deep-water swimming; weapon controller checks cover all 28
policies and specific burst/reload/charge/spin transitions. Isolated e1m3b client
connection, movement captures and repeated delayed-door activation have run.
These checks do not certify movement through all geometry, blocked assemblies,
rider transport, actor behavior, damage, progression or multiplayer parity.

The movement differential fixture links bundled GPL C movement **only into the
test executable**. Replacement products link no legacy gameplay C sources.
Adapted movement retains upstream attribution; no private reference source or
assets were imported.

Reproduce the native development client probe (local converted assets required):

```sh
zig build game --prefix zig-out/replacement -Dgame-runtime=zig
python3 dkq3/tools/runtime_player_probe.py --engine zig-out/play/current --prefix zig-out/replacement --mover 255
```

The script runs software rendering through `dkguard --headless`, uses a temporary
profile, and keeps inputs/logs/captures under the ignored report directory. The
optional mover assertion is specific to e1m3b's delayed door. Visual captures need
inspection; diagnostic command success does not establish scenario acceptance.

## Active implementation: runtime-zig-219

Train path legs, angular travel, departure-corner dwell, trigger-only stops,
redirected/elevator activation and teleport corners are connected. Persistent
parent IDs define bounded attachment hierarchies with cycle rejection. Initial
placement/teleports carry descendants; ordinary movement prepares complete poses
before collision and commits or delays the assembly together. Static brush parents
can own animated children. Arrival dispatch runs after both mover families finish.
These additions remain part of the unqualified replacement, not a production cutover.

Focused checks now total 26 replacement tests. The real e1m3a `bigplat` replay
carries the player upward, holds its authored ten-second dwell, descends and rests
at the lower trigger-only corner. The probe uses explicit diagnostic positioning
and activation; original saves are untouched. It does not certify the physical
button/trigger chain or full campaign progression. Multi-part obstruction, rotating
riders and compound attached-mover scenarios remain open.

```sh
python3 dkq3/tools/runtime_player_probe.py --engine zig-out/play/current --prefix zig-out/replacement --scenario lift
```

Combat/projectiles, actors/navigation, secret/continuous movers, scripts/cinematics,
save restoration/travel, full presentation/UI and overall acceptance remain open.


## Active implementation: runtime-zig-220

Two-leg secret doors and continuous rotating brushes now use the same transactional
attachment/pusher path as binary movers and trains. World-system ordering has one
coordinator; engine trajectory encoding is shared. Attached special movers sample
independent motion before parent composition and defer their motion clocks on rollback.

Focused real-map probes demonstrate e3dm1 secret door 43 opening both legs, waiting,
and retracing to its closed position; e1m3b rotating brush 72 starts, stops without
drift, and resumes. The affected e1m3a lift and e1m3b delayed door still pass. These
use diagnostic activation; shoot activation, rotating riders, sounds and compound
obstructions remain unqualified. Replacement modules and domain checks build.

Reproduce with `runtime_player_probe.py --engine zig-out/play/current --prefix
zig-out/replacement --scenario secret` (or `--scenario rotation`). The normal
launcher still uses the existing runtime. Combat, actors, inventory progression,
scripts/cinematics, restore/travel and full presentation/UI remain implementation work.


## Active implementation: runtime-zig-221

Native keys, weapon/ammunition pickups, health and armor are connected to floor
physics, MD3-derived bounds, model configstrings/rendering, visibility, respawn
policy, target dispatch and player-state projection. Key names unlock doors/buttons
through persistent player IDs. Weapon selection commands and server acquisition
selection are connected. Shared metadata serves C and Zig; shared ammunition and
Gas Hands duration policies avoid parallel weapon-rule implementations.

Map spawning now applies mode/difficulty restrictions before behavior registration,
without renumbering authored IDs. ECS relocation supports tagged component unions.
Native products and 37 focused tests pass. The e1m6a blue-card probe verifies floor
settlement, touch collection, rejection before key ownership and button/door activation
afterward. The affected lift and delayed-door probes still pass. Diagnostic placement
and activation are recorded; this is not a full authored route or cinematic replay.

```sh
python3 dkq3/tools/runtime_player_probe.py --engine zig-out/play/current --prefix zig-out/replacement --scenario inventory
```

Boost/status pickups, pickup audio/messages, moving-platform item transport, native
combat/actors, progression, scripts/cinematics, restoration/travel and full UI/HUD
remain open. The normal installation and saves remain untouched.

## Active implementation: runtime-zig-224–225

Normal fire events dispatch Glock/Disruptor hitscan and Ion projectile policies into
native damage. Ion bolts own persistent shooter identity, collision/bounce state and
lifetimes in ECS. Class metadata owns projectile tuning; the server owns collision
and event delivery. Native client models and sound events show those entities.
The other 25 weapon combat policies remain pending, even though their input
controllers and metadata exist. Full effects, knockback and Gold combat parity remain open.

Four civilian classes load supplied health, bounds, speed and animation sequences.
Workers/prisoners have native movement, damage receipts, death animation/target dispatch
and visible-death witness panic. Actor metadata is owned by world-system state and
allocated for the map lifetime. Movers can transactionally push actors/corpses using
the same assembly mechanism as players. Navigation, scripted actor control, hostile
attacks, actor sounds and final-pose corpse bounds remain open.

The e1m2a civilian scenario demonstrates Glock damage killing authored worker 10 and
worker 9 witnessing the death, entering flee and moving away. Player positioning and
equipment are diagnostic; this is not a campaign-route or full actor acceptance.

```sh
zig build game test-runtime --prefix zig-out/native-dev
python3 dkq3/tools/runtime_player_probe.py --engine /path/to/local/engine-generation --prefix zig-out/native-dev --scenario civilians
```
