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
| Fresh opening gate | Intro, actors, authored controls, progression and saves connected | Applicable native contracts pass at 294 | **Not accepted:** fresh 294 completes all 115 intro shots, marsh, bridge encounter/boss, death/reload and C→B→C visited-world restoration on `4c2502…` | Driver then unnecessarily jumps while correcting a downhill waypoint, times out alive with 58 health. Evidence: `runtime-zig-294/fresh-opening/failure.json`. Sequence 293 checkpoint replay reaches e1m2a; this is not fresh acceptance |
| All four episodes | Additional hostile/ambient/boss controllers, scripts, cinematics, companions, world effects and ending connected | Coding-pass contract roots pass at 285; connected scenarios unrun | No complete episode accepted on native runtime | Broader ability/task audit, connected boss/puzzle/companion traversal and ending remain |
| Saves and visited worlds | Typed controller snapshots, rebased clocks, visited archives, validation/recovery | Snapshot and deadline contracts pass at 285 | Sequence 287 authored death/reload; 288 actual C→B→C after disk load retains bridge progress | Latest restoration replay is checkpointed; fresh consolidated campaign/death replay remains |
| Multiplayer and bots | Native sessions, combat/respawn, advancement, pickups, DM, CTF/deathtag, bot input and rooms connected | 233 native contracts pass on `a2f70c…`; wire contracts at 287 remain valid | Sequence 294 on `4c2502…`: two real UDP clients pass admission/movement/fire/death/respawn/spectator/rejoin/reconnect/fast restart; CTF passes four bots' movement/pickups/combat/respawn and one contested capture. Evidence: `lan-regression/`, `ctf-regression/` | Natural deathtag reaches carriers but cannot complete capture. Water-jump routing now passes the explicit slime-escape query; stationary lift waiting is repaired; the physical exit is an authored teleporter, but the new local passage recovery still fails to select it. Client-driver inputs are automated. Public admission, browser, authenticated reconnect/rooms and complete modes remain open |
| World/effects | Movers, controls, hazards, healing/breakage/debris, audio/lighting, emitters, lightning/attractors, rain/snow connected | World policy roots pass at 285; engine effects unverified | No new campaign or visual acceptance | Target effects and ambient fish/seagulls now connect; the broader authored behavior audit continues; shared particle/beam/audio/PHS behavior requires replay |
| Presentation and cinematic input | Escape completion, supplied button/slider/loading art, authored frame timing and snapshot interpolation connected | 233 native contracts include intermediate/reverse/final animation poses, discontinuities and dialogue surviving camera cuts | Sequence 294 real Escape → authored Marsh arrival → Escape → save/load/pause passes on both renderers; supplied Marsh loading art captured; factory monitor restoration and full e1m2a arrival replay pass | Behavior/art layout reviewed against private reference; full menu equivalence, all-class animation and audiovisual comparison remain unverified. OpenGL2 sky crash repaired and replayed. |
| Independent release | Bare `zig build play` builds/installs native code with the existing local cache | Build/contracts and installer preservation pass at 286 | Guarded native menu, e1m1a admission and actual save/load pass; explicit map and disabled intro | Full independent fresh-checkout/release and campaign qualification remain |

## Sequence 294 — current presentation integration

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
