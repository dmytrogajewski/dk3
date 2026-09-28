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

Sequence 308 moves HD PNG decoding to background workers and repairs rejected
prefetch/save handling on `d3db13…`. Both renderers pass their affected contact
checks; final failure, visited-world/death and six-world restore checks pass.
**Seamless campaign acceptance remains incomplete.** Fresh opening development
reaches the bridge boss but fails there. Wider weapon interactions, navigation,
authored party actions, multiple portal views, seam qualification and remaining
admission stalls remain open. Supporting check counts do not measure completion.

| Milestone | Implemented | Contract-tested | Running native engine / connected play | Reference comparison and remaining work |
|---|---|---|---|---|
| Seamless connected regions | Region admission/ordinary exits, qualified collision, actor/projectile transfer, specialized weapons, party ownership and authored script scope | 402 Zig, 82 Python and actual C owner/collision/inline-handle contracts pass | On `187506…`: eleven weapon contact cases, selected controller restores, real turret/frog contact, both renderer combat paths, enemy/companion/player crossing and region save/death restoration | One reviewed corridor and selected interactions. Broader navigation/party actions, multiple views, seam qualification, eviction/admission stalls and fresh route remain open. [Evidence](#sequence-305--specialized-weapons-across-seams). |
| Weapons | All 28 class-owned controllers connected; 305 extends spatial and persistent ownership | Class roots and ownership/slot/cancellation contracts execute at 305 | Eleven controlled specialized weapon contacts across A/B; Wyndrax, Nightmare, Metamaser and pending Zeus restore on `187506…`. Three actual Trident tips confirmed | Not all interactions: Trident merge/water, Ballista carried crossing/pin restoration, destruction variants, return/pickup and complete audiovisual comparison remain open |
| Fresh opening gate | Intro, actors, authored controls, progression and saves connected | Applicable contract roots execute through 308 | **Not accepted:** fresh 305 and superseded 306 runs reach the bridge encounter and fail. A separate legitimate factory checkpoint reaches e1m2a alive | Full coherent New Game→M2 route still required; boss avoidance/firing-lane strategy remains a driver blocker. No modified inventory or assembled checkpoint chain qualifies. |
| All four episodes | Additional hostile/ambient/boss controllers, scripts, cinematics, companions, world effects and ending connected | Coding-pass contract roots pass at 285; connected scenarios unrun | No complete episode accepted on native runtime | Broader ability/task audit, connected boss/puzzle/companion traversal and ending remain |
| Saves and visited worlds | Schema-2 residents, typed references/time, archive migration, actor scope and recovery; unfinished unexposed preparations excluded from new saves | Affected runtime roots pass at 308 | On `d3db13…`, rejected future PNG preserves current play/save/load, independent A/B actor health and death restore pass, and six-world factory cinematic restores/completes. Earlier scoped controller/migration evidence below | Full party/controller combinations and fresh campaign restoration remain unverified. Historical state remains mandatory even when media preparation fails. |
| Multiplayer and bots | Native sessions, combat/respawn, advancement, pickups, DM, CTF/deathtag, bot input and rooms connected; protocol 1349 | Native wire and runtime roots pass at 305 | Two actual UDP clients replay movement/fire/death/respawn/spectate/rejoin/reconnect/fast restart on `187506…` | Complete CTF/deathtag, natural bot traversal, public admission/browser/authenticated rooms and full modes remain open. No online service deployment. |
| World/effects | Movers, controls, hazards, breakage/debris, lighting and sky bindings connected | Applicable contracts pass at 296 | Sequence 296 verifies bridge fragments/restoration, Cambot lamps and animated sky; see exact identity below | Target effects and ambient fish/seagulls now connect; the broader authored behavior audit continues; shared particle/beam/audio/PHS behavior requires replay |
| Presentation and cinematic input | Escape completion, supplied button/slider/loading art, authored frame timing and snapshot interpolation connected | 240 native contracts include captured-clock interpolation, clip timing, discontinuities and dialogue boundaries | 296 OpenGL2 real New Game/Escape/Marsh/save/load/pause passes; OpenGL1 opening captures verify actual intermediate motion. 304 replays six-world factory arrival restoration; the full fresh intro still needs replay | Behavior/art layout reviewed against private reference; full menu equivalence, all-class animation and audiovisual comparison remain unverified. OpenGL2 sky crash repaired and replayed. |
| Independent release | Bare `zig build play` builds/installs native code with the existing local cache | Build/contracts and installer preservation pass at 286 | Guarded native menu, e1m1a admission and actual save/load pass; explicit map and disabled intro | Full independent fresh-checkout/release and campaign qualification remain |

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
