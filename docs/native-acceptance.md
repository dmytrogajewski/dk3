# Native port acceptance

Development: `rewrite/native-zig-runtime`. Preserve main
`e3966c4d40678dbf91619034b5dcb33b763dcbed`, installed playable game, user saves and
live service. The removed gameplay backend remains disconnected. Complete four-episode
campaign, companions, multiplayer/bots, UI, persistence and independent release stay in scope.

Owner-directed cadence: finish the broad connected coding pass, then consolidate the
build/assets and run verification with repairs. No per-item suite/engine gates.
Implementation checkpoints 255–284 add no connected acceptance. No overall percentage
is inferred from class counts or test volume.

## Current outcome matrix

| Milestone | Implemented | Contract-tested | Running native engine / connected play | Reference comparison and remaining work |
|---|---|---|---|---|
| Weapons | All 28 class-owned controllers connected | Class contract roots pass at sequence 285; full interactions unverified | Sequences 232–243/251 have narrow fixtures; no full interaction acceptance | Remaining interactions and visual/audio qualification; Trident setup and Sunflare edges open |
| Fresh opening gate | Intro, actors, authored controls, progression and saves connected | Current applicable contract roots pass at 285 | **Not accepted:** New Game → full intro → e1m1a → e1m1b bridge → e1m1c → authored e1m2a | Previous legitimate checkpoints reach defeated bridge boss/reward and first factory gate; complete fresh route required |
| All four episodes | Additional hostile/ambient/boss controllers, scripts, cinematics, companions, world effects and ending connected | Coding-pass contract roots pass at 285; connected scenarios unrun | No complete episode accepted on native runtime | Broader ability/task audit, connected boss/puzzle/companion traversal and ending remain |
| Saves and visited worlds | Typed controller snapshots, rebased clocks, visited archives, validation/recovery | Snapshot and deadline contracts pass at 285 | Sequence 253 narrow death/reload; 254 C→B→C visited restoration after disk load | Shared actor/world/script changes invalidate applicable earlier coverage; natural restoration replay required |
| Multiplayer and bots | Native sessions, combat/respawn with retained advancement, death drops, DM, CTF/deathtag, physical bot input, room controls and menus connected | Initial-state/objective policy contracts pass at 285 | Current candidate unrun; previous runtime results do not transfer | Complete mode/objective interactions, bot navigation, network/reconnect/browser/room scenarios and presentation remain |
| World/effects | Movers, controls, hazards, healing/breakage/debris, audio/lighting, emitters, lightning/attractors, rain/snow connected | World policy roots pass at 285; engine effects unverified | No new campaign or visual acceptance | Target effects and ambient fish/seagulls now connect; the broader authored behavior audit continues; shared particle/beam/audio/PHS behavior requires replay |
| Independent release | Bare `zig build play` builds/installs native code with the existing local cache | Build/contracts and installer preservation pass at 286 | Guarded native menu, e1m1a admission and actual save/load pass; explicit map and disabled intro | Full independent fresh-checkout/release and campaign qualification remain |

## Build and asset identity

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
launcher map/save replay passes. The fresh intro replay and bot scenario remain under
verification. Bots admit successfully after message acknowledgement, but the observed
match has not established pickup/combat/respawn. No full connected gate is accepted.
The earlier inventory manifest `ba03d6e56c08eef76e9a79a32b2da6c223d68433293c9e4f3b2aecead0606dc3`
is superseded for new native engine scenarios.

Exact earlier verified segment identities, inputs, setup limits and superseded results
are retained in [the journal](../specs/runs/RUN-dk3-independent-port.md), including the
full historical acceptance ledger preserved at sequence 278. Evidence artifacts remain
under `zig-out/reports/runtime-zig-*/`. Controlled placement, grants and synthetic targets
remain subsystem diagnostics; none closes the continuous campaign gate.

## Revalidation and known limits

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
