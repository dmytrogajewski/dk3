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
| Saves and visited worlds | Typed controller snapshots, rebased clocks, visited archives, validation/recovery | Snapshot and deadline contracts pass at 285 | Sequence 287 authored death/reload; 288 actual C→B→C after disk load retains bridge progress | Latest restoration replay is checkpointed; fresh consolidated campaign/death replay remains |
| Multiplayer and bots | Native sessions, combat/respawn, advancement, pickups, DM, CTF/deathtag, bot input and rooms connected | Native and wire contracts pass at 287 | Four-bot DM demonstrates natural movement/pickup/combat/respawn on `8dc7a3…`; CTF capture passes at 288; deathtag capture fails | Portal cache repaired with failing/passing regression; blocked deathtag routes remain. Human network/reconnect/browser/rooms remain unaccepted |
| World/effects | Movers, controls, hazards, healing/breakage/debris, audio/lighting, emitters, lightning/attractors, rain/snow connected | World policy roots pass at 285; engine effects unverified | No new campaign or visual acceptance | Target effects and ambient fish/seagulls now connect; the broader authored behavior audit continues; shared particle/beam/audio/PHS behavior requires replay |
| Independent release | Bare `zig build play` builds/installs native code with the existing local cache | Build/contracts and installer preservation pass at 286 | Guarded native menu, e1m1a admission and actual save/load pass; explicit map and disabled intro | Full independent fresh-checkout/release and campaign qualification remain |

## Build and asset identity

Current sequence-288 installation
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
  blocked corridors and a submerged route require diagnosis. This is not full
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
