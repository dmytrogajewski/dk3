# Native port acceptance

Development: `rewrite/native-zig-runtime`. Preserve main
`e3966c4d40678dbf91619034b5dcb33b763dcbed`, installed playable game, user saves and
live service. The removed gameplay backend remains disconnected. Complete four-episode
campaign, companions, multiplayer/bots, UI, persistence and independent release stay in scope.

Owner-directed cadence: finish the broad connected coding pass, then consolidate the
build/assets and run verification with repairs. No per-item suite/engine gates.
Implementation checkpoints 255–282 add no connected acceptance. No overall percentage
is inferred from class counts or test volume.

## Current outcome matrix

| Milestone | Implemented | Contract-tested | Running native engine / connected play | Reference comparison and remaining work |
|---|---|---|---|---|
| Weapons | All 28 class-owned controllers connected | Historical focused contracts; current shared changes unrun | Sequences 232–243/251 have narrow fixtures; no full interaction acceptance | Remaining interactions and visual/audio qualification; Trident setup and Sunflare edges open |
| Fresh opening gate | Intro, actors, authored controls, progression and saves connected | Earlier contracts; current candidate unrun | **Not accepted:** New Game → full intro → e1m1a → e1m1b bridge → e1m1c → authored e1m2a | Previous legitimate checkpoints reach defeated bridge boss/reward and first factory gate; complete fresh route required |
| All four episodes | Additional hostile/ambient/boss controllers, scripts, cinematics, companions, world effects and ending connected | New coding-pass regressions written, unrun | No complete episode accepted on native runtime | Broader ability/task audit, connected boss/puzzle/companion traversal and ending remain |
| Saves and visited worlds | Typed controller snapshots, rebased clocks, visited archives, validation/recovery | Historical executing contracts; current additions unrun | Sequence 253 narrow death/reload; 254 C→B→C visited restoration after disk load | Shared actor/world/script changes invalidate applicable earlier coverage; natural restoration replay required |
| Multiplayer and bots | Native sessions, combat/respawn, DM, CTF/deathtag, physical bot input, room controls and menus connected | New implementation unrun | Current candidate unrun; previous runtime results do not transfer | Complete mode/objective interactions, bot navigation, network/reconnect/browser/room scenarios and presentation remain |
| World/effects | Movers, controls, hazards, healing/breakage/debris, audio/lighting, emitters, lightning/attractors, rain/snow connected | Written policies and regression roots; coding-pass additions unrun | No new campaign or visual acceptance | Target effects and ambient fish/seagulls now connect; the broader authored behavior audit continues; shared particle/beam/audio/PHS behavior requires replay |
| Independent release | Bundled engine, native modules, converters and isolated build/install tooling | Historical public checks; current integration unrun | No accepted fresh-checkout full-play path | Regenerated assets, complete source/provenance review, independent build/install and release verification remain |

## Build and asset identity

**No verified engine/asset pair exists for the current candidate.** Latest targeted
module link: `/tmp/dk3-runtime-282-actor-audio-link.log`, exit 0, before final
companion cue sharing, guard completion, idle admission and restoration-validation edits. Latest engine/module link:
`/tmp/dk3-runtime-277-lightning-link-fixed.log`, exit 0. These are compilation evidence.
No tests or engine scenarios have run during sequences 255–282.

Authoring inventories used local asset manifest
`ba03d6e56c08eef76e9a79a32b2da6c223d68433293c9e4f3b2aecead0606dc3`.
It predates new actor/objective/nitro, shader/lightstyle, PHS and actor-event schema changes. Regenerate
assets and capture coherent binary/rules/asset hashes before engine acceptance.
Old converted maps without authored PHS now produce a regeneration diagnostic when
hearing is queried; old actor-event tables require regeneration.

Exact earlier verified segment identities, inputs, setup limits and superseded results
are retained in [the journal](../specs/runs/RUN-dk3-independent-port.md), including the
full historical acceptance ledger preserved at sequence 278. Evidence artifacts remain
under `zig-out/reports/runtime-zig-*/`. Controlled placement, grants and synthetic targets
remain subsystem diagnostics; none closes the continuous campaign gate.

## Revalidation and known limits

- Shared changes require affected script/cinematic, damage, perception, companion,
  restoration/travel and multiplayer replay. Cambot now uses authored PHS; merged map
  areas remain an acoustics limitation. Earlier narrower PVS alarm evidence is superseded.
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
