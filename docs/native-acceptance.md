# Native port acceptance

Development stays on `rewrite/native-zig-runtime`. Main, the installed game, user
saves and the online service are preserved. Full four-episode campaign, companions,
multiplayer modes/bots, persistence, UI and release remain in scope. Removed-runtime
results never transfer to native acceptance.

## Active implementation pass

Owner-directed broad coding pass (sequences 255–273): remaining episode and multiplayer
systems are developed together before consolidated verification and repairs. Opening
route driver iteration is paused. Complete four-episode/companion/multiplayer scope
and the fresh New Game→e1m2a integration gate remain required.

Written, **unverified**: factory monitors; actor action replacement/interrupt semantics,
script-owned actors, streamed dialogue and random/ordinal use programs; cinematic
program selection, actor borrowing, head tracks and attribute backup; companion
rescue/toggle/stop/teleport, orders, class-owned weapons, death failure/camera and
exit-selected party transfer; final ending intermission and authored credits travel.
Ground combat now includes Rage, Skeleton, Satyr, Column, Dwarf and Lycanthir policies,
with supplied attack events, Dwarf axe lifecycle and Lycanthir resurrection. Large and
small spiders have bite/leap/retreat controllers; Cryotech has timed combat and scripted
spray pulses; surgeon cowering and civilian panic pause/resume action scripts; lab monkeys own melee,
leap, hop and activation rules. Inmater and Lasergat connect their distinct attack
controllers to persistent lasers. Both episode-three knights now connect melee, fireball
and delayed lightning attacks to persistence and client effects. Patrolling hostiles now acquire targets before path
following, without consuming the combat controller's injury receipt. Episode decorations now
provide authored collision, animation, breakage, drops and debris; firefly emitters
create persistent swarms. Cinematic completion dispatches authored `cinetrigger` and
`cinekill` entities, including when playback is disabled. These are
active implementations, not complete class parity or campaign acceptance.

Multiplayer code connects native team/session lifecycle, authored spawning,
respawn/scoring, CTF/deathtag objectives and ordinary-input bots. Room admission,
identity-bound votes/bans, operator controls, presence, ready countdown, reconnect
scores, permanent-room fill/rotation, chat and scoreboard connect to existing native
online services. Native menus expose browser/create/private-room/LAN/player/lobby
controls; remote player skins use the admitted appearance catalog. Weapon classes
own remote grip selection; supplied character sequences drive movement, crouch, jump,
transitions and death. Objective drops toss physically, countdowns and capture bonuses
follow reviewed mode rules, and bots evaluate actual inventory/pickup eligibility and
release charged Hammer attacks. No live service,
installed profile or user save has been changed. Networking and room flows are unrun
on this candidate; earlier-runtime Internet acceptance does not transfer.

Coding-pass work remains: the broader dynamic-actor/ability audit and connected boss
progression, complete companion/cinematic progression, dynamic navigation/bot goals,
complete player/multiplayer presentation, CTF/deathtag interaction parity and
release integration. Unknown `monster_*` entities now fail admission with their
classname instead of silently disappearing. All four episodes and multiplayer remain
open as complete outcomes. There is no verified engine/asset identity for the current coding pass.
Targeted links establish compilation only. The sequence-256 checkpoint `a79d091`
linked all three modules in `/tmp/dk3-runtime-256-episode-link.log`. Sequence 257
adds Sludgeminion and the four episode-four gunners; its corrected link is
`/tmp/dk3-runtime-257-gunners-link-fixed.log`. The first link's client timestamp-width
error is retained in `/tmp/dk3-runtime-257-gunners-link.log`. No new contract suite,
engine scenario or connected playthrough has run in this coding pass. Sequence 258
connects Psyclaw, Doombat and Griffon, repairs generic pain and shared fireballs, and
links all three modules in `/tmp/dk3-runtime-258-griffon-link.log` (compile evidence only).
Sequence 259 connects Harpy, Dragon and flesh-fragment deaths; its coherent three-module
link is `/tmp/dk3-runtime-259-dragon-link.log`. Sequence 260 connects DeathSphere and
Chaingang; all three modules link in `/tmp/dk3-runtime-260-chaingang-link-fixed.log`.
Sequence 261 connects Buboid, ambient Wisp swarms and Wyndrax; its consolidated
link is `/tmp/dk3-runtime-261-consolidated-link.log`. Sequence 262 adds Garroth,
Stavros and their NPC meteor callback (`/tmp/dk3-runtime-262-meteor-link.log`).
No gameplay acceptance is added.

Shared changes invalidate prior script/cinematic, damage, actor perception,
restoration/travel and multiplayer coverage on the developing build. Sequence 258
additionally requires replay of Knight fireballs, Skeeter retreat, actor-attack callback
ordering, actor pain and psychic-effect restoration. Historical
manifests remain valid only for their recorded narrower builds and setups.

## Current outcome matrix

| Milestone | Implemented / contract-tested | Running native engine / connected authored gameplay | Blockers and evidence limits |
|---|---|---|---|
| Weapon controllers | All 28 class-owned policies connected; Zeus, Wyndrax, Nightmare and Metamaser included. | Focused interactions passed in sequences 232–243. Sequence 251 repairs and exercises close Ion aiming. | Dispatch coverage does not establish all weapon interactions. Most fixtures grant equipment/health or place targets. Trident merge setup and Sunflare bright sprite edges remain open. |
| Fresh opening campaign | Intro, opening actors, action programs, world controls and native saves connected. | **Full gate not accepted:** New Game → full intro → e1m1a → e1m1b bridge → e1m1c → authored e1m2a exit. | No coherent full-route build accepted. Checkpoint development now defeats the bridge boss, restores the defeated encounter, collects its authored Megashield and reaches e1m1c. The factory approach reaches the first gate. Factory traversal, authored e1m2a exit and a fresh consolidated replay remain. |
| Native restoration | Typed snapshots, controller state and visited archives have executing contracts. | Actor/action restoration has focused engine evidence. Arrival save/load exercised. | Connected natural death/reload has narrow sequence-253 evidence. Sequence 254 verifies C→B→C visited restoration after a disk load, including retained boss/control/pickup state; the current broad changes require replay. Sequence-241 travel is historical and needs replay after trigger-bounds changes. |
| Remaining campaign | Party triggers/travel, ending intermission and additional ground actor controllers written; no legacy backend. | Unrun on the current coding pass; no verified build/asset manifest. | Missing classes, abilities, bosses and connected progression. New class registration or reference-contract review does not count as encounter acceptance. |
| Multiplayer and online rooms | Session/objective lifecycle, bots, room membership/moderation/readiness, chat, scoreboard and native menus written. | Unrun on the current coding pass; no native network/room acceptance. | Animation/equipment presentation qualification, dynamic bot goals, full mode interactions and consolidated network/hosting replay remain. Live service is untouched. |

## Exact verified segments

Every cited `identity.json` records executable, all three modules, renderer, shaders
and the complete local package manifest. Different-build checkpoints are development
replays, never a fresh combined playthrough. Private reference contracts were reviewed;
these results do **not** claim comparison through reference playback.

| Player outcome / subcase | Verified identity | Evidence | Setup limits / supersession |
|---|---|---|---|
| Fresh New Game, all 115 intro shots, arrival cinematic/save-load and ordinary Ion pickup | Full manifest: `runtime-zig-246/fresh-opening/identity.json` | `zig-out/reports/runtime-zig-246/fresh-opening/` | Route then failed a navigation waypoint. Later actor, script and Ion changes require relevant replay and ultimately a fresh consolidated gate. |
| Close skeet takes two ordinary Ion hits and dies; authored e1m1a exit reaches e1m1b | `fcec9367951d0aa5a7619003e8d32df28de584fc759a4ab3f05bce633eff376f` | `runtime-zig-251/marsh-ion-fixed/` result, traces, capture, `opening_bridge_arrival.sav` | Legitimate old marsh checkpoint, health 67 before the segment. Old saves lack actors admitted later. Subsequent build adds read-only attack-time diagnostics; full fresh replay remains required. |
| First bridge control takes four ordinary distant Ion hits, breaks and removes its linked Rockgat; close Ion skeet kill also observed | `35d1e516f54aca675bf7230a64f4364c23dfd6f513ea43405ebc1322d3f1e260` | `runtime-zig-251/bridge-fire-window/` inputs, control/encounter captures | **Narrow subcases only. Overall route failed** at low health before resupply. Latest `bridge-resupply-priority/` also failed a ledge-obstructed tree use. Neither is bridge traversal acceptance. |
| Normal health pickup and river approach | `fcec9367951d0aa5a7619003e8d32df28de584fc759a4ab3f05bce633eff376f` | `runtime-zig-251/bridge-resupply/`, `bridge_health_pickup.sav` | Legitimate checkpoint, ordinary inventory/input. River route failed while the driver waited for stillness in a current; later attempt stopped at low health after Crox contact. |
| Sloped and flat health trees settle and restore; partial fruit use restores | `a2335b58fb0761ca4ac551e49a172da257c49e554508340270f623104369131b` | `runtime-zig-252/tree-before/`, `tree-after/` | The old build fails the drift assertion. Diagnostic placement/health for use; floor settlement starts from fresh authored worlds. |
| River Crox kills, five tree uses, two Ion packs and western turret control | Same sequence-252 identity above | `runtime-zig-252/bridge-healthy-ammo/`, `bridge-upper-contact/`, `bridge-active-defense/` | Narrow connected segments from legitimate checkpoints. Earlier attempts fail later. Active-defense reaches the boss entrance with 83 health and 124 Ion rounds; whole bridge battle is not yet accepted. |
| Bridge boss defeat, ten authored skeets, safe defeated-encounter save/load and authored e1m1c entry | `3309ba59495aee2a771ce24f870c1f818adc7f1abfc19b549372fd3b3ce2a779` | `runtime-zig-253/bridge-clear-sprays/` | Legitimate bridge checkpoint. Ordinary Ion fire and movement; pending sprays must clear before stopping. Route fails later in e1m1c. Frog contact repair requires relevant route replay; not fresh campaign. |
| Boss Megashield pickup (400 armor), authored e1m1c entry, fruit resupply, combat and first gate approach | `26ae3d5bcffe24fcfa305d3c8807057772dc9798025d4ef518cd49910afeef2d` | `runtime-zig-253/bridge-reward-route/` | Legitimate defeated-boss checkpoint, unchanged supplies. Gate shot fails setup: driver is below the upper switch. No gate or factory traversal claim. |
| Froginator completes captured floor contact instead of rebounding forever | Full manifests in both reports; current modules match sequence-253 frog-fixed build above | `runtime-zig-253/frog-before-contact/`, `frog-after-contact/`, `frog-landings.json` | Same unmodified legitimate save SHA `26f2a9c7c891ebbd13de6202baaea4fb014485d2795bd60a8cfe38f5f8b1304f`. Old modules fail the actual landing assertion; repaired modules pass. Focused restoration fixture, not fresh gameplay. |
| Repaired frogs and authored marsh exit into the bridge | Same frog-fixed identity above | `runtime-zig-253/marsh-landed-frogs/` | Legitimate first-encounter checkpoint; actual A→B crossing and bridge pickup. Later combat driver assertion fails; full bridge route not passed. |
| Natural death and acknowledged restoration of living gameplay | Full manifest in `runtime-zig-253/bridge-open-water/identity.json` | `bridge-open-water/death-reload.json`, inputs and capture | Ordinary failed encounter, followed by reload of an earlier healthy checkpoint. The battle remains failed. Does not certify every death/restoration permutation. |
| Cambot acquisition/alarm restoration and four observed ten-health tree uses, partial/empty restoration | `7398a5842fa26b90bf0c52012167b8a910824c5c2037d003648d759f39a11496` | `runtime-zig-249/opening-actors-heal/` | Diagnostic placement/health. Alarm/dodge permutations and full presentation remain open. |
| Crox actual water level 3/swimming displacement, pending melee restoration/contact; Rockgat popup, burst restoration, lowering and lethal Ion contact/removal restoration | `282dd04dbfffddac553b953267f7575711f125a62d3f9d0e9c98237b4df08cd1` | `runtime-zig-250/crox-consolidated/`, `rockgat-contact/` | Diagnostic placement/equipment/health. Crox transitions/steering/avoidance, Rockgat authored toggle/death outputs and full presentation unqualified. |
| Bridge factory creates ten skeets plus Thunderskeet; paths/aggression restore | `b1a868d39f0d0e0c2242551e7b8deef800dc5a1691679b5a524640a5f741cf88` | `runtime-zig-247/bridge-first/` | Controlled activation and health 10000. No bridge combat, boss death outputs or connected traversal acceptance. |
| Remote angled-trigger rejection before/after load; actual exit contact works | `02a5fcdaf9752fbcfe8a91801ced0639e35ab6b07ab6d1ca986a3f664fba172c` | `runtime-zig-248/trigger-before/`, `trigger-after/` | Defective build fails the regression. Diagnostic placement; prior angled-trigger travel requires revalidation. |

Paths above are under `zig-out/reports/`. Historical detail and older identities stay
in [the journal](../specs/runs/RUN-dk3-independent-port.md), sequences 232–253.

## Current defects, limits and revalidation

- Sequence 251 close Ion defect: the old forward-direction guard discarded crosshair
  contact behind the muzzle. `marsh-exit/` captures the failing trace and undamaged
  target. Ion now owns direct convergence on that contact; the captured geometry has
  a contract regression. Other weapon aiming policies are unchanged. The existing
  muzzle-clearance trace remains; this is not a claim of full reference launch parity.
- Sequence 252 repairs health-tree toss settlement. Sliding actor movement let a
  tree drift down a walkable slope and disappear from its authored alcove. Class-owned
  floor contact now stops it, with flat/sloped stability and fruit restoration exercised.
  Existing displaced saves retain their positions; connected evidence enters a fresh
  bridge world on the repaired build. Other actor physics is unchanged.
- Driver navigation excludes deliberate stationary diagnostics from movement timeout
  accounting. Precise pickup approaches use ordinary walk input; fire events and target
  health establish contact. Idle visible enemies can be engaged before attacking.
  Hatching/expiring windows remain excluded. Low-health disengagement proved unsafe
  under active fire and has been replaced by active defense on the route to supplies.
- Sequence 253 repairs frog jump landing only: a half-unit ground probe accepts slow
  upward bounce motion (at most 100 units/second) on a walkable floor, as reviewed in
  private ground-contact and frog task contracts. The defective build remains in the
  focused regression evidence. No global actor physics, damage or geometry tuning.
- Driver attack tracking follows actual displacement and records fire/contact separately.
  Blind pause assumptions missed short frog attacks. Incoming boss spray observations
  guide ordinary movement; an observed zero pending count precedes save/load. The
  natural boss drop supplies armor for the factory route. Repeated low-health factory
  attempts are superseded by this legitimate resupply route.
- Next connected work: qualify the factory upper control route, yard, interior/lift,
  e1m2a exit and visited-world round trip; then finish the fresh consolidated gate.
  The sequence-253 fresh replay failed at river target priority after reaching the bridge; no fresh replay is currently running. All checkpoint results remain separate.
- Crox amphibious steering/avoidance, floor orientation and all attack poses; Cambot
  search cone, vertical avoidance, post-death wandering and inertia; Thunderskeet
  combat/death outputs; actor pain/gibs and complete audiovisual parity remain open.
  Rockgat fractional damage, death effects, tracers/sparks and authored toggle are open.
- Explicit compatibility departures: Cambot alarm recipients use PVS instead of PHS,
  dodge uses crosshair contact pending auto-aim; Thunderskeet's unsafe twelve-entry
  cycle is bounded. Reference source review is distinct from playback comparison.
- Pod shell monster/experience classification, complete triggered-cinematic progression,
  earthquake/debris presentation and later campaign classes remain implementation gaps. Shared action
  cleanup/body-control, death outputs, perception and travel need applicable regressions.
- Aggregate checkpoint `/tmp/dk3-runtime-253-aggregate.log`: 242 Zig + 54 Python
  checks, formatting and three modules passed. Assertions are enabled and all explicit
  test roots execute. Subsequent factory driver waypoint/crouch refinements remain
  under gameplay qualification; they do not alter the verified native build.



Sequence-255 compatibility details and limitations:

- Companion selectors interpret the authored `mikiko`/`superfly` name directly rather
  than reproducing the reference's inverted string comparison. Teleport search tests
  evenly spaced directions and keeps a blocked action pending; it does not reproduce
  cumulative-angle search or ignore failed clearance. Neither behavior is engine-qualified.
- Only companions requested by a submap exit are removed from its visited archive and
  transported. Other party members retain their local world state. This changes save
  and restoration coverage and requires both leave-behind and return-with-party replay.
- Ending intermission uses the first stable authored camera rather than a random one;
  target-facing, five-second input delay, frozen/invulnerable player and destination
  credits map follow the reviewed contract. It remains unrun, including reload during it.
- Column non-Hammer immunity avoids the reference's lethal-hit clamp-to-one anomaly.
  Complete Column reaction/quake presentation remains unfinished.
- Dwarf axes use a launch-relative five-second expiry instead of inheriting an unset
  reference timestamp. Contact starts its own five-second fade lifetime. These native
  projectiles persist through saves although the reference marked them transient.
- Lycanthir recovery checks the full standing hull before rising, extending the
  reference's corpse-hull occupancy check to avoid materializing into a player/mover.
  Evasion, terminal gibs, sound parity and the complete encounter still require work.
- Ground attack events are delivered before ending an elapsed sequence; the previous
  ordering could lose a final strike on a long frame. Earlier ground-combat results
  require replay. A before/after regression is required at consolidated verification.


- Decoration hulls retain authored zero coordinates instead of the reference helper's
  zero-to-minus-sixteen substitution. Breakage retains an inert source identity for
  delayed target dispatch and visited-world persistence. Flesh debris currently uses
  the decoration fragment lifecycle; full gib behavior remains open.
- Firefly personalities are bounded below by 0.25, extending the reference reroll
  guard to initial spawn so its steering divisor cannot be zero.
- Hiro and Superfly supply no `bjump` sequences. Native moving jumps use their
  supplied `ajump` grip variants; Mikiko uses the authored `bjump` variants.
- Deathtag explosion attribution deliberately remains self-damage, as established by
  the reference contract. Armor/invulnerability now participate instead of being
  bypassed. Pickup/alarm/victory/return/tick sounds are class-mode selections; exact
  attenuation, heartbeat volume ramp and the layered polygon explosion remain open.
  Sequence 266 connects CTF/deathtag carrier attachment, skins and additional defensive bonuses; their runtime qualification remains open.
- Cryotech keeps separate 800 ms damage-pulse and 1500 ms particle lifetimes. Spray
  particles use the supplied atlas rectangle, color, spread and speed; post-half-second
  growth is elapsed-time based (60 units/second) instead of reference frame-count growth.
  Pain variants, absent authored `diec`, ambient audio and playback comparison remain open.
- Inmater/Lasergat lasers retain the scheduled ten-second lifetime (the reference
  also writes an unused three-second delay). Inmater crouched-target direct damage
  follows its reviewed callback; sweep yaw adjustments are unused in that reference
  callback. Muzzle attachment, robotic gibs and complete reaction/presentation remain
  open. Uncalled prisoner-execution routines were not invented as ambient behavior.
- Patrol acquisition changes invalidate authored path/aggression regression coverage.
  The repair and new classes have no running-engine acceptance yet.
- Surgeon cowering preserves its interrupted script timing. Broader worker alert,
  wandering and pain/gib behavior remain unqualified. These additions do not establish
  complete class parity or transfer campaign acceptance from another build.


- Knight2's supplied model/events have no `ataka` or `atakb`. Its native close
  punch uses the supplied `atakc` stroke and strike event; this is an intentional
  animation compatibility correction, not reference playback parity. Fireball world-X
  drift is retained but collision-traced; its first native drift tick is 100 ms.
  Knight lightning retains two captured-contact blasts, three 5-damage/90-radius ticks
  each, and separate 250 ms child lifetimes. Sword attachments, fire trails and exact
  subtractive-light presentation remain unqualified.
- Save admission now allows model-less Cryotech spray and typed knight effects.
  Actual restoration must be replayed; a compile result does not establish this path.
- Cerberus bite/leap and Pipe/Plague Rat combat, poison selection and amphibious
  locomotion are implemented, unverified. Shared water movement was extracted from
  Crox, invalidating its previous movement/restoration evidence for this build.
  Rat close/leap choice retains the reference's second probabilistic range check.

- Shark suspension uses actual water levels: stop pursuing a dry target; resume
  that target at level 3. Wet route filtering and movement prevent a route through
  air. Surface targets are approached at the shark's current depth. This is a narrow
  native containment correction; steering and exact water-boundary parity need replay.
- VenomVermin owns poison bite/leap bands and its seven-to-one missile acceleration,
  10 ms first update, 100 ms following updates and silent four-second expiry. Its
  supplied model lacks `atakd`; as in the reference's failed sequence change, the
  running sequence continues. A supplied `atakd` is used when present. Ranged cooldown
  and attack/missile state persist. Evasive targeting/actions, smoke trail, polygon
  explosion and full pain/presentation remain unfinished. No encounter claim is made.

- Sequence 256 continues the same broad coding pass after pushed feature checkpoint
  `54f15fe`. Rotworm ceiling admission/release, jump landing/bite and poison/spit are
  connected, unverified. An authored ceiling flag without a ceiling intersection is
  rejected instead of moving the actor outside the map. The supplied model lacks
  `jumpa`; the existing `atakb` sequence remains, as on the failed reference request.
  Spit poison applies only to players; bite poison uses the shared living-character
  contract. Rotworm generic pain, inertial impulse parity and tracked spit particles
  still require completion/qualification. No new campaign or restoration acceptance.

- Sequence 256 also connects Centurion/Fletcher shafts, Battleboar gun/rocket and
  Rocket Gang/Rocket MP controllers, authored attack events, projectile collision,
  client models/glows and saved state. Centurion uses the active throwing-knife
  contact contract: world embedding versus entity-contact falling, followed by fade.
  Fletcher arrows disappear on contact and silently expire after ten seconds.
  Battleboar fires one bullet trace despite its two muzzle flashes; its full-speed
  missile expires after five seconds. Gang/Vermin missiles use seven-to-one
  acceleration; MP missiles use four-to-one. MP's frame-zero second strike is retained.
- Evasion adds supplied hide-node flags, class admission chances, strafing, sidesteps
  and dodge destinations. Ground sidestep/strafe/dodge travel reserves the reviewed
  44-unit offset (52/36/84 units), superseding earlier distance descriptions. Native
  collision uses the full hull, continuous floor support and either clear side;
  this deliberately repairs the reference's rejected clear opposite side. Hide-node
  admission uses native graph reachability; weighted-path equivalence remains open.
  Player targeting currently retains Cambot's direct-crosshair contract, narrower
  than reference auto-aim. Exact cover scheduling and reaction/presentation remain
  unfinished. These are implemented paths, not claims of full class parity.
- Shared rocket/bullet extraction and sidestep correction require Vermin, Rockgat,
  Inmater, spider, rat and knight regressions. Authored movement dispatch no longer
  calls combat in place of motion for Rotworm/Vermin. Vermin missile origin now uses
  its active post-aim class offset. Save layout/controller changes supersede prior
  native restoration evidence. No installed or user saves were edited.
- Initial sequence-256 module linking failed on a removed Zig 0.16 enum conversion
  API (`/tmp/dk3-runtime-256-link.log`); corrected to `std.enums.fromInt`. A subsequent name-shadowing error was repaired; all three modules then linked in
  `/tmp/dk3-runtime-256-episode-link.log`. No new contract, engine or connected-campaign acceptance.

- The same checkpoint connects Thief knife/melee cadence, black/white prisoner
  punch/ballistic-rock selection and Femgang moving kicks/idle variation. Prisoner
  attack admission, two strike flags and distinct pain/death policies are explicit.
  A knife without contact expires after three seconds relative to launch; this avoids
  the reference's uninitialized absolute delay affecting freshly spawned projectiles.
  Contacted knives retain the five-second axe callback. No scenario acceptance yet.

## Sequence 257 implementation checkpoint

Sludgeminion connects fluid-only replenishment, two authored hand attacks, attack
floor pitch, idle choices, bouncing damaging globs, model/glow and persistent state.
Its particle trails/contact smoke and exact transitional/reaction presentation remain
unqualified. Shared NOLEAD extraction retains Rotworm's aiming contract and needs its
affected replay. A prisoner throw whose target moved to coincident XY now consumes
the undefined ballistic shot instead of terminating the game; ordinary throws retain
their existing solution. This narrow compatibility case still needs regression execution.

Seal Captain/Girl shotgun traces retain distance falloff; Seal Commando's two stationary
poses fire a first bullet plus five callbacks; Uzi Gang starts callbacks without an
initial bullet and stops at absolute model frame 80. Callbacks run every 100 ms, matching
the reference server tick despite its 10 ms requested deadlines. Authored chase/standing
transitions, injury/death choices, attachments, sounds and saved bursts are connected.
The supplied converted models contain the required muzzle tags (read-only asset audit).
The commando's first bullet deliberately starts at its owner's muzzle rather than the
reference temporary entity's unplaced world origin. Class-specific take-cover scheduling,
tracers and exact task/reaction timing remain incomplete/unqualified. No damage/geometry
changes were made to help an input driver. New contracts are written but unexecuted.

## Sequence 258 implementation checkpoint

Psyclaw connects paired spheres, melee, ranged sidestepping, jump reduction, initial
immunity and eight-second player warping. Player movement interference, rendered FOV /
roll / color, loop sound and save/travel deadlines are connected. Compatibility changes:
the small sphere keeps the actual shooter instead of treating its parent projectile's
hook as an actor; flying spheres honor the otherwise unused eight-second lifetime;
the oscillation stays within twelve samples, and final FOV recovery cannot overshoot.
The supplied model has no `dieb`; normal death retains its available `diea` sequence.

Doombat connects bite/ranged health rules, retreat/hover, bobbing, collision response
and corpse bounce. Its percentage-versus-base-health comparisons are retained, including
the speed branch that is unreachable with the supplied base health. Griffon connects
air/ground pursuit, room/liquid checks, authored-node landing, retreat, ground leaps
and timed strikes. Its ten-unit launch lift is collision-traced. Air turning uses the
shortest wrapped yaw difference; retreat uses a bounded search and existing authored
graphs. These are native compatibility choices, not reference-playback acceptance.
Griffon/Harpy always-gib behavior was still missing at this checkpoint and is connected
in sequence 259 below; this does not claim complete actor parity.

Shared generic pain now preserves the ordinary first roll before the independent
heavy-hit wrapper roll. A light second-roll reaction retains its current animation
and attack cursor. Unrun regression contracts cover the light-hit defect and lock.
Shared fireballs now use point collision, radius 64, four secondary 30%-damage pulses
for full-size fireballs, and quiet five-second expiry; Doombat uses only the small
primary explosion. This supersedes the earlier Knight implementation. Fire trails
and detailed impact-light comparison remain open. Actor-attack callbacks now observe
the actor frame published during the same tick, repairing Uzi stop-frame ordering.

All three modules link in `/tmp/dk3-runtime-258-griffon-link.log`; the initial fireball
extraction's unused-variable compile error was corrected. New policy/pain tests are
included in explicit test roots but **have not run**. No running native-engine identity,
connected encounter, save restoration or private reference playback was established.

## Sequence 259 implementation checkpoint

Harpy now connects ground/air ranged combat, obstruction dodge, room-height terrain
selection, authored-node approach, forward/reversed `drop`, ascent and settling phases.
Its magic arrow reuses Fletcher's reviewed callback, including ten-second scheduled
expiry despite the unused three-second delay field. Private call-site review finds no
transition of Harpy into the hover movement mode required by its dormant swooping code;
native active flight attacks therefore remain stationary. Magic-arrow flight/contact
and the existing Fletcher scenarios require affected regression replay.

Dragon connects patrol sounds, random-duration hover, attack animation/sound, breath
warning and fireball release. The converted model contains `hr_muzzle`; both breath
and fireball particle effects are connected to the supplied atlas. Particles retain
their birth pose and continue after emission ends. Native emission is normalized to
60 Hz, uses a bounded 4096-particle pool and a regular radial emitter; these intentional
presentation departures from render-frame emission/private radial math need visual
qualification. No unused Dragon fly-away task is invented as an active combat loop.

Griffon, Harpy and Dragon now fragment on death unless the violence setting suppresses
that branch. The existing scenery lifecycle carries mass/mode-dependent flesh fragments,
class hulls, inherited motion, bounce, delayed fade and saved clocks. Corpse collision
clears immediately; the actor is removed after death outputs and the following tick.
The fragment cap is a strict 100 rather than the reference's off-by-one admission.
Blood clouds/decals, liquid float behavior and additional gib sounds remain presentation /
physics parity work. Other creature gib policies have not yet been connected.

Status remains **implemented; unverified**. `/tmp/dk3-runtime-259-dragon-link.log`
links all three modules; no new contract execution, engine scenario, connected campaign
or multiplayer run. Current engine/asset gameplay identity remains unestablished.

## Sequence 260 implementation checkpoint

DeathSphere connects charge, four-muzzle volleys with two extra frame-driven volleys,
aerial evasions/altitude checks, bobbing, hover audio and robotic fragmentation. Death
bolts own their three-second lifetime, health-contact-only radius damage, owner
immunity, gold sparks and contact sounds. World impacts do not deal splash damage.
Robotic fragments use the material read from the owning supplied MD3, with bounded
material parsing and cache invalidation; the inspected model names `skins/m_dsphere`.
No skin or private asset is embedded in game code. Bolt contact entities remain briefly
for native spark presentation although the reference deletes its projectile immediately.

Chaingang connects ground/hover admission, room/liquid transitions, ground-node dodge,
six-feeler aerial strafing/swoops, attack warmups, overlapping chaingun callbacks,
water-triggered node wandering and death variants. Gun damage/spread, speeds and
ranges come from class authoring. Saved phase, strafe and volley clocks resume through
the existing snapshot path. Its supplied muzzle tag is `hr_muzzle`. Jet smoke/debris,
sparks and light share the bounded particle renderer with Dragon; each emitter retains
its own clock. Takeoff/landing smoke bursts and tracer presentation remain finer
presentation work. Full wandering/path/task and pain interruption behavior need playback.

Reviewed reference quirks remain class-scoped: DeathSphere's floor "up" projection is
world +X; best-away selection applies its final turn to pitch; Chaingang's wall helper
passes .15 to an integer parameter. Its old 299/316 transition thresholds are below
supplied `flyb`/`flyc` starts (304/329), so those phases finish on their first tick and
the 293–294 start sound cannot occur. The death selector makes `dieb` unreachable;
only `diea` and `diec` are selected. These source findings are not playback comparison.

Compatibility details: initial temporary chaingun bullets use the actual owner's muzzle
(the previously recorded Commando correction); jet emission uses a fixed 60 Hz clock.
A full-hull slide still prevents physical penetration when the reference obstruction
branch leaves its requested direction unchanged. DeathSphere's interrupted attack
returns through a non-firing `flya` recovery; that task mapping needs qualification.
Mechanical damage classification, fragment liquids/decals and full sound parity remain
open. Shared bounce extraction affects Griffon leaps and Doombat corpses; shared escape,
gun callbacks and particle drawing affect Harpy, Commando/Uzi and Dragon. Replay those
regressions and all affected restoration scenarios at consolidated verification.

**Implemented; unverified.** Targeted three-module link:
`/tmp/dk3-runtime-260-chaingang-link-fixed.log`. Initial compile errors are retained in
sequence-260 logs. New volley/counter/material bounds contracts are included but have
not executed. No native-engine, connected campaign, multiplayer or reference playback
acceptance is added, and no current gameplay build/asset identity is established.

## Sequence 261 implementation checkpoint

Buboid connects coffin wakeup, melee, nonterminal collapse, ten-second resurrection,
second lethal-hit termination, melt immunity, alpha changes and holy-ground-aware
relocation. The collision adapter exposes the already-converted holy surface bit;
converter/engine semantics are unchanged. Standing placement is additionally checked
with the actual hull after the reference's enlarged search probe. This intentionally
avoids emerging inside an occupant/mover. Melt deadlines, alpha, corpse/recovery state
and permanent-death dispatch persist. Exact pain/script interruption and encounter
playback remain unqualified.

Ambient Wisp clusters connect authored counts, movement, alpha, sequential collection,
100-second regeneration, sound scheduling and a persisted delivery handshake. They
remain distinct from damageable attack Wisps. Initial ambient personalities use the
same minimum 0.25 guard as Fireflies, avoiding singular steering at spawn. Wyndrax
owns lightning above half health, Wisp ammunition below it, the named power station,
node/ground movement, collection loops and active-projectile retreat. Missing active
swarms cause wandering and rechecking rather than the reference's invalid enemy
access; no free ammunition is granted. The final collection waits for its monitor's
acknowledgement before retiring the source, preserving that last delivery on reload.
Wyndrax's special sequences are present in the model but absent from CSV; reviewed
frame-data initialization supplies their first+1 strike. Station arcs do not damage
the boss: the source's null owner suppresses that damage path.

NPC attack Wisps connect homing/oscillation, collision reflection, shootable health,
the class pain callback's second deduction, two-damage lightning ticks, world arcs,
owner death/expiry and shrinking fade. Wyndrax's discharge emits four arcs in two
pairs, with captured-contact radius damage and separate flare lifetimes. A missing
or dead target starts Wisp fade, avoiding a stale pointer. Typed effects and swarms
use existing ECS, projection and save mechanisms. New Buboid/Wisp damage regressions
are written and unexecuted. Beam/particle geometry, sound attenuation, full effect
comparison and dynamic summoner interactions still require qualification. Particle
emission uses the bounded native pool and fixed 60 Hz, rather than render-frame rate.

The alpha repair selects each converted MD3 surface's existing alpha material;
shaderRGBA alone did not blend implicit opaque skins. Robotic-fragment material
lookup now explicitly selects ordinary/alpha variants. Revalidate Buboid, fragments,
DeathSphere bolts, Psyclaw spheres, Dragon fireballs, Dwarf axes/arrows and player
projectile fades. Chaingang wandering now reuses the existing node selector and
requires its affected replay. All new damage, actor, script, effect and restoration
paths require consolidated regression and native/connected scenario verification.

**Implemented; unverified.** All three modules link in
`/tmp/dk3-runtime-261-consolidated-link.log`; earlier compile errors are retained in
sequence-261 logs. This establishes no running-engine or campaign acceptance and no
verified gameplay build/asset identity. Main, preserved installation, user saves,
private assets and live service are untouched.

## Sequence 262 implementation checkpoint

Garroth connects the reviewed melee/ranged admission gap, difficulty-dependent
selection, ordered weapon fallbacks, both authored strike events, death variants
and dynamic Buboid summoning. Summons share the existing radial clearance selector
with Nightmare while retaining each caller's mask. The selected location also passes
full standing-hull clearance; a blocked summon is consumed instead of creating an
actor inside occupied geometry. Death outputs are not inherited by a summoned Buboid.
Stavros connects pitch-facing, its supplied `ataka` event, one-percent pain admission
and meteor firing. Its supplied model has no `runa`; movement uses `walka`.

The shared NPC stave callback owns launch offsets, initial five-percent speed,
growth-conditioned acceleration/spin, twelve-second lifetime, impact and 4–6 fragments.
Parent damage and blast radius both use the authored base damage, as in the source
callback. Fragment spawn never assigns health in the reference; its explosion damage
therefore stays zero while its scaled radius and bounce/expiry lifecycle remain active.
No guessed fragment damage is introduced. This NPC callback is distinct from the
existing player Stavros weapon. Effects include the persistent launch flare, light,
particle trail, explosion disc/model, sprite, sound and world scorch. Full particle
atlas/attenuation/scale comparison remains open. Explosion projections briefly persist
for native delivery and save restoration, extending the deleted reference projectile.

The same reference physics inspection corrects NPC Wisp bounce damping to 0.75 and
its normalized-axis stop epsilon. The shared decal helper preserves the existing
weapon overlap/retention policy; radial-search extraction preserves Nightmare's
existing mask and cumulative headings. Revalidate those affected paths, new summon/
combat/restoration cases and all connected episode encounters. Range/fallback contracts
are written but unexecuted. Supplied authoring and private contracts were read locally;
no private source or assets were admitted.

**Implemented; unverified.** The coherent link is
`/tmp/dk3-runtime-262-meteor-consolidated-link.log`. No test suite, native-engine,
connected campaign/multiplayer or reference-playback acceptance was performed.
No verified gameplay build/asset identity is established for this coding pass.
Main, the installed game, user saves and the live service remain preserved.

## Sequence 263 implementation checkpoint

Hostile Mikiko connects all three sword attacks, authored/default strike events,
absolute-frame voices, direct dodge requests, swimming, pain, aura and loop-sound
lifecycle. The supplied model lacks `dieb`, retaining the already selected `diea`
when that reference sequence request fails. Its third attack has no CSV row and
uses the reviewed first+1 default. The class's one-shot aura/untrack quirk remains.
Mikiko, Kage and Medusa's visible `eye1`/`eye2`/`sword1`/`sword2` surfaces now produce
animated attachment tags; the previously installed conversion omitted them.
A rebuilt coherent asset manifest is required before engine verification.

Medusa connects poison bites/spit, probabilistic ranged admission, partial-cover
sidesteps, authored retreat nodes, rattle/gaze/recovery phases and mutual yaw/pitch
contact. Its flash clears after one server frame, following the reference's per-frame
alpha decrement. Petrification preserves the struck frame and solid body and still
dispatches death/progression. Armor/protection remains in damage accounting; no
special damage reduction is introduced for driver convenience. Dead petrification,
player input, actor body state and restored phases need replay. Native player gaze
uses the current fixed 90-degree gameplay view. Wraith/other target visibility and
encounter navigation still need connected qualification.

The shared venom callback retains the saved `rotworm_spit` union tag and defaults
old records to Rotworm; its implementation is now `server/venom_spit.zig`. Medusa
owns its model/scale, absence of Rotworm launch audio and particle colors. No generic
spit substitution is used. Direct pain uses one chance roll, separate from the generic
wrapper's heavy-hit roll. Existing evasion, melee, poison and movement adapters are
reused. Fine blade lightning, particle atlas, stone brightness/skin blending and
sound-volume comparison remain open. The eye-contact, direct-pain, petrification/protection and missing-attachment
regressions are written and unexecuted.

**Implemented; unverified.** All three modules link in `/tmp/dk3-runtime-263-boss-final-link.log`;
the first link's syntax error is retained. No tests, native-engine scenarios,
connected campaign/multiplayer or reference playback ran. This adds no verified
build/asset identity. Revalidate affected shared actor pain/evasion, poison,
petrification/death, converter attachments and save paths on the consolidated build.
Main, installed play, user saves and live service remain unchanged.


## Sequence 264 implementation checkpoint

Kage now connects sword strikes based on the victim's remaining health, authored
animation/sound events, finite smoke escapes, node-based return, twelve protector
summons, difficulty-owned recharge and damage refunds, sword aura and death inventory
removal. Recharge can suspend and resume a smoke task. Fractional refund health is
retained; lethal recharge hits do not dispatch a false death. Removing the first
player's sword ownership preserves its selected identity until normal weapon switching,
matching the reviewed inventory unlink; native ownership prevents further firing.

Summoned Ghosts connect wake/fade animation, aerial pursuit, their direct strike,
player-hit pain deduction, owner-phase cleanup and corpse-content collision. They
respect ordinary actor scripts and freeze ownership, cannot gib and suppress blood
particles while retaining weapon-owned impact audio/effects. Their supplied model
has no death sequence or CSV attack row; class-owned fading uses `flya` and the
reviewed default first+1 strike. The inactive, commented-out spiral task is not queued.
Rotating boss flares and smoke use persistent typed attack effects, with restored
clocks and client emission serials. No private implementation/assets were imported.

Narrow compatibility corrections reject blocked Ghost spawn hulls and Kage's snapped
return destination rather than embedding actors. A rejected protector still consumes
its authored summon attempt. Ghost ownership also bounds cleanup when summoned without
an enemy. Ghost sight audio retains the four-second same-class limit; the reference's
shared five-species sound-cache eviction is not reproduced. Fade/flare geometry,
particle scale, sound attenuation and overlapping hum/charge-loop mixing remain
presentation qualifications. The named sword/eye attachments still require the
sequence-263 asset rebuild.

**Implemented; unverified.** Three-module link evidence is
`/tmp/dk3-runtime-264-kage-consolidated-link.log`; the earlier declaration-shadow failure
is retained in `/tmp/dk3-runtime-264-kage-final-link.log`. New recharge, pain, immunity
and restoration regressions are written but unexecuted. No engine, connected campaign,
multiplayer or reference-playback acceptance was performed and no verified gameplay
build/asset identity is added. Revalidate damage/death, ordinary impact effects,
actor scripts, saved controllers, sword ownership and the new boss encounter on the
consolidated build. Main, installed gameplay, saves and online service remain preserved.


## Sequence 265 implementation checkpoint

Nharre connects both authored casting sequences, all three ordinary summons and the
reaper. Teleport points retain authoring order and the reference's final-point exclusion.
The boss fades out, waits until its selected destination hull is clear, relocates, fades
in and restarts its attack task; no extra dwell or alternative destination is inserted.
Pain/cooldown and the shared summon deadline persist. Retreat follows the reviewed
bounded outward node traversal, complete-hide checks and the historical pitch/yaw
fallback, including its integer-resolution quirk and node cursor behavior. Normal
movement, door use and reachability reuse native locomotion/navigation.

The NPC reaper owns a separate saved controller from the player Nightmare weapon.
It freezes one eligible victim, turns the view, delays appearance, strikes for the
reviewed 50 damage, pushes players, and releases control on strike, interruption,
owner death, victim death or removal. NPC velocity/collision mask and player view
height restore explicitly. Other NPCs can still target a player under this specific
freeze. Appearance audio, screams, flame, shrinking light, spiral particles, the
jittered column and earth-crack mark are connected. Player bodies hide during the
owned freeze. Private read-only source/contracts and supplied tables/models were
reviewed; no private code or assets were admitted.

Compatibility corrections cap the ten-point array and skip undefined empty-point
teleports; reject failed/uninitialized or blocked summon placements; isolate dynamic
summons from inherited boss death outputs; and prevent overlapping controllers from
stealing a victim. Release restores view height and cleans up dead victims instead of
retaining the reference's lost pointer/omitted restoration. Native navigation can differ
from the original node pathfinder. The spiral and frame-driven flame use bounded fixed
60 Hz cosmetic updates; exact particle atlas, attenuation, frame timing and visual
comparison remain open. The shared summon flares now use the supplied additive sprite
variant. Kage's Ghost and Nharre's Doombat begin their requested wake/flight poses at
spawn. The earth-crack decal variant requires another asset rebuild, together with the
sequence-263 attachment conversion.

**Implemented; unverified.** All three modules link in
`/tmp/dk3-runtime-265-nharre-consolidated-link.log`; the initial shadowed capture error
is retained in `/tmp/dk3-runtime-265-nharre-link.log`. Teleport occupancy, release
ownership, restored appearance/freeze boundaries and decal-admission regressions are
written and unexecuted. No tests, engine scenarios, connected campaign/multiplayer or
reference playback ran. No verified gameplay build/asset identity is added. Revalidate
shared perception, freezes/restoration, actor attacks, summon visuals, dynamic spawns
and the connected boss encounters on the consolidated build. Main, installation,
saves and live service remain preserved.


## Sequence 266 — multiplayer objectives and physical bot controls

**Implemented; unverified.** CTF now awards reviewed base/flag/carrier/escort
kill bonuses before objective release. Capture grants one team point regardless of a
pad's deathtag points field; shared pads remain deathtag-only, matching CTF admission.
Visibility uses opaque collision and the observer view offset. Objective hulls and
standing/carry frames use the supplied flag contract. Home objectives settle under
gravity, and return/capture restores the original spawn before settlement.

CTF uses `a_ctf_flagl`, its authored color and body-skin mapping. Both flags and
backpacks attach to each character's animated `ctf_flag` hardpoint. First-person
carriers do not render their own back attachment. The model converter now packages
eight explicit objective skins while preserving invisible helper surfaces. Current
asset packages lack these bindings; the consolidated conversion is required.

Bots seek a physically reachable use/touch/shoot control linked to the blocking mover,
including forwarding relay chains and key requirements. They submit actual `use`
client commands only after the current view trace reaches the control; shooting uses
the ordinary weapon controller. This is native bot strategy, not claimed source AI
parity. Bounded subgoal timeouts abandon unsuitable controls without changing puzzle
rules. Safe lateral yielding prioritizes human teammates and deterministically chooses
between bots. Goals prioritize recovering a stolen flag before an impossible capture,
choose nearby capture pads, reject unavailable pickup routes, and seek needed health
or ammunition. Dynamic route/mover, contested objective and network scenarios are unrun.

Code review also repaired Nharre reaper victim ownership admission: the existing saved
reaper test must pass through both the attack and body-owner validation paths. Its
regression is written but unexecuted. New scoring, control-chain/lock/cycle and skin
binding regressions are written and included in the intended roots, not yet run.

A targeted three-module link passed in `/tmp/dk3-runtime-266-multiplayer-link-fixed.log`
after correcting an optional error-union return; that compile failure remains in
`/tmp/dk3-runtime-266-multiplayer-link.log`. The final coding checkpoint includes bot
resupply and hazard rejection; all modules link in
`/tmp/dk3-runtime-266-multiplayer-consolidated-link.log`. No
engine, connected multiplayer/campaign, test-suite or reference-playback acceptance is
added. Scoring, team changes, objective settlement/attachment, bot controls/yielding and
Nharre restoration require consolidated replay. Main, installed game, saves and live
service remain untouched.

## Sequence 267 — companion combat, collection and body presentation

**Implemented; unverified.** Weapon definitions now own companion inventory slots,
pickup/ammunition permissions, empty-ammo melee eligibility, shot-clearance probes
and close-teammate restrictions. Enemy class policies own their selection exceptions
(e.g. Silverclaw against Lycanthir). The selector preserves the reviewed later-choice
priority instead of substituting player/bot damage ranking. Companions use ordinary
weapon switching/firing controllers and suppress fire across blocked traces or below
15 health. Empty Discus/Venomous selection approaches within melee reach; this narrowly
corrects the reference's overwritten melee-range calculation, without changing weapon
damage or collision.

Explicit collection rejects unsupported items, wrong episode weapons, unavailable
ammunition, unwanted health and carrying-Mikiko weapon use. Automatic idle collection
checks `itemspawnflags`, visibility, eligibility and a bounded route under 256 units;
explicit orders may override the authored companion exclusion bits as in the reference.
Actual overlap and the shared pickup policy grant items and own their audio. Bounded
failed collection returns to follow and reports failure for explicit orders. The AAS
route length is native navigation evidence, not claimed private-node path equivalence.
Companions yield an occupied movement lane and use physically encountered unnamed,
unlocked ordinary doors with their own activator/key checks. Neither path teleports
followers or remotely activates puzzle controls.

Companion body frames now use supplied character/grip idle/run/jump/attack sequences,
including the separate carrying model. Repeated attack decisions no longer restart the
body pose every frame. Remote players use actual fire timestamps for supplied standing
and crouched attack poses. Both remote players and companions attach the weapon-owned
world model/frame at `hp_gun`; unsupported/missing media raises a named error. Exact
attack/movement blending, jump timing and effect presentation need runtime qualification.

Collection/yield deadlines rebase in snapshots; travel and authored stop/teleport clear
local item/recovery references. New selection, item admission, bounded-route, clock and
firing-pose regressions are written and unexecuted. The targeted three-module link is
`/tmp/dk3-runtime-267-companions-link.log`; all three modules also link at the final
checkpoint in `/tmp/dk3-runtime-267-companions-consolidated-link.log`. No test suite or engine/connected scenario ran. No verified gameplay identity
or acceptance is added. Companion swimming, ladders, crouch navigation, full scripted
progression and their movement/persistence interactions remain coding-pass work, along
with the complete campaign/multiplayer/release outcomes. Revalidate companion orders,
collection, travel, combat and remote presentation on the consolidated build.

## Sequence 268 — companion-traversal (implemented; unverified)

Companions now submit routed commands to the existing native player motor for
water, ladders, jumps, crouching and scripted movement. The motor accepts supplied
class bounds and upward velocity while retaining existing player defaults. Saved
party state owns its motor independently of Player components; restoration rebases
command/jump clocks, while travel and authored teleport reset local movement state.
Bot and companion routes retain crouch/ladder travel flags; crouch steering requires
a clear crouched collision sweep. Companion collection can consider these routes.
Supplied crouch/walk/attack and swimming poses reflect actual motor state; weapon
controllers receive actual water and stance state. Carrying Superfly has supplied
crouch poses but no supplied swimming sequence; carrying presentation stays with
that model's authored movement poses instead of borrowing another model's frames.

Private reference inspection: `AI_File.cpp` AIATTRIBUTE_SetInfo applies authored
bounds/run/walk/jump values after Sidekick initialization; Sidekick enables swimming,
ladders and doors; AI crouching uses a four-unit top. This implementation reuses
independent native acceleration/step physics and requires movement parity qualification.
It is not an import of private AI tasks. New hull/jump/water, obstruction and restored
clock regressions are written and unexecuted. The shared player differential root
remains required at verification. The native three-module link completed in
`/tmp/dk3-runtime-268-traversal-link.log`; it is compilation evidence only.
No engine, connected gameplay, reference playback or fresh asset identity is accepted.
Revalidate player/bot/party movement, low passages, water combat and party restoration.
The broader audit also found absent native liquid/drowning damage; implementing
that authored contract is the next connected gameplay work.

## Sequence 269 — environment-hazards (implemented; unverified)

The native world now measures actual feet/waist/head liquid contents and applies
player/AI drowning, lava, slime, cold-water and nitro behavior through ordinary damage
and death scoring. Air reserves, damage cadence, cold exposure, fractional damage and
the companion nitro callback are saved/rebased. Players and land/aquatic actors retain
separate reviewed rules. Nitro's formerly discarded BSP content is now preserved at
`CONTENTS_DK3_NITRO`; it does not join the swimming mask. Robotic nitro immunity is
class-owned. Existing weapon-owned `protects_water` supplies Trident breathing.

Suit charge uses 400 authored units at the 100 ms gameplay cadence, pauses outside
exposure and persists across saves/travel. The existing transport deadline projects
remaining charge; old native timed suits migrate on their first environment update.
This follows the counter/cadence rather than the source's approximate one-minute
comment. Native integer health accumulates fractional drowning damage before applying
whole units instead of rounding every tick upward. Player fall damage uses reviewed
450 velocity threshold, 0.0625 scaling, acro reduction/boost exemption and the default-on
multiplayer `dm_falling_damage` option. Deathtag carriers receive reviewed self-hazard
protection without suppressing trigger or enemy damage. Cold water stops thawing while
submerged in episode three; existing freeze effects still own slowed movement/damage.

Reviewed privately: client inertial/water/powerup routines; AI_CheckWaterDamage;
Sidekick nitro callback delay; artifact suit charge; deathtag damage flags. No private
implementation imported. The new engine header mapping has an updated provenance digest.
Written, unexecuted regressions cover actual liquid sampling, damage cadence, immunity,
falling, air/charge/clock restoration and preserved converter contents. The first native
link found a Zig nested-if assignment syntax error; the corrected three-module link is
`/tmp/dk3-runtime-269-environment-link-fixed.log`. Module SHA-256 identities are recorded
in `/tmp/dk3-runtime-269-link-identity.json`. This is compilation evidence only.
No contract suite or engine scenario ran; assets require regeneration for nitro as well
as prior boss/objective media changes. Water routes, damage, cold, falling, multiplayer
scoring and save/travel require consolidated replay. Detailed audiovisual parity,
horizontal inertial collisions and NPC escape behavior still require qualification.

The broader supplied-world inventory is `/tmp/dk3-runtime-269-world-classes.json`;
controls/properties are `/tmp/dk3-runtime-270-controls-authored.json`. Literal-owner
absence is an audit candidate, not proof of missing behavior: definition tables and
prefix owners must also be inspected. The audit confirmed missing teleports/push/timer/
secret and authored audio controls; continue their implementation next. Full campaign,
multiplayer and release acceptance remain open with no fresh verified gameplay identity.

## Sequence 270 — authored-controls-and-map-music (implemented; unverified)

Distinct saved control states now connect `func_timer`, `trigger_push`,
`trigger_teleport`, `trigger_secret`, `trigger_toggle`, `trigger_changemusic`,
`trigger_console` and `trigger_remove_inventory_item` to ordinary touch and target
activation. Timers use authored initial pause/delay, repeat variance and once/toggle
semantics; delay is not reapplied at every target firing. Push volumes use authored
angle/speed and enable/once flags. Sidekick-only toggle volumes retain their activator
and reviewed center/radius exit condition. Secrets count once and use episode audio.
Console controls recognize the three commands actually supplied by the corpus;
they do not execute arbitrary text in an engine command buffer.

Teleport destinations retain their authored 27-unit marker offset; normal transit
redirects entry speed, applies destination facing, clears ground and records a saved
700 ms cooldown/teleport snapshot bit. Named cinematic relocation is separate.
Occupied destinations damage intersecting bodies; map solids prevent relocation.
Full telefrag immunity/occupancy, visual fog, paired transit, bot routing and normal
campaign/cinematic traversal remain unverified. Those limits are not acceptance.

Map music now reads the converted `music` table; trigger changes persist and restore
through CS_MUSIC and the existing background-track service. The supplied trigger
volumes use full gain; intermediate authored gain and complete music/cinematic mixing
remain presentation qualification. Native user mixer settings are preserved. Selected
music follows the most recent saved trigger; map-table selection supplies initial play.
Inventory removal uses the trigger's authored `item`, intentionally correcting the
reference's erroneous check of the touching entity's `keyname`. Deleting a selected
weapon removes ownership without an invented forced switch; ordinary weapon rules
prevent firing it. The final sword trigger is the supplied affected case.

Private reference review covered Triggers.cpp and func_various.cpp contracts, and the
supplied entity/property inventory `/tmp/dk3-runtime-270-controls-authored.json`.
Native definitions use the existing ECS/target/collision/asset services. The final
available component slot holds distinct authored control variants; no ECS expansion.
Three modules link in `/tmp/dk3-runtime-270-controls-link.log` (before subsequent
music-path validation and test additions). Timer/restoration/inventory regression
roots are written and unexecuted. No tests, engine scenarios or connected acceptance
ran. Saved controls, traversal, music and affected prior campaign/multiplayer routes
require replay on the consolidated build. Authored speakers, healing portals, effects,
remaining world controls, campaign interactions and complete release remain work.

## Sequence 271 — authored-speakers-and-healing-stations (implemented; unverified)

`target_speaker` and `sound_ambient` now own first-six authored sound selection,
loop/toggle/start-off behavior, integer randomized delay, volume, distance and
non-directional parameters. Reliable speakers use reliable server commands; other
speaker events broadcast with client distance attenuation. Ambient defaults and
multi-sound loop disqualification follow reviewed authoring contracts. The supplied
volume `2` retains the original unsigned-byte gain, 254/255, instead of rejecting
maps. Mixer parameters persist on each emitter during spatialization, clear on client
restoration, and resume with saved loop/delay/random state. Resource indices, binding
admission and save clocks connect to the existing native snapshot mechanisms.

`misc_hosportal` and `misc_fountain` connect class models, stationary solid hulls,
continuous healing, depletion/recharge lockout, charge indicators, sounds and native
sparkle/spray presentation. Ordinary use requires range/facing and a living player
or companion; continuing transfer rechecks eligibility. The reviewed behavior starts
with 100 charge before parsing recharge capacity, transfers one health per 200 ms,
and recharges one per 100 ms. Supplied bestow/recharge/sound properties unused by
those reference classes remain unused. Horizontal FOV preserves the reference's
single-wrap comparison. Healing and emitter states persist across native restoration.

Contracts reviewed privately: world/target.cpp speaker/laser sections,
world/MISC.CPP ambient initialization, world/hosportal.cpp, ai_func.cpp FOV,
server/sv_send.cpp and qcommon/common.cpp gain encoding, client particle/Artifact_fx
contracts and atlas coordinates. Native implementation is independently written;
no reference code or assets were imported. Visual effects use the supplied local atlas
with native bounded/analytic particles; original frame-dependent densities and
acceleration remain presentation comparison work. Engine sound metadata services were
reused without engine changes. Directed regression roots for speaker cadence/gain,
healing eligibility/depletion and restoration clocks are written, unexecuted.

The initial targeted link caught type coercions, retained in
`/tmp/dk3-runtime-271-audio-healer-link.log`; corrected link evidence is tracked with
the journal. No engine scenario, audible/rendered comparison or campaign acceptance
is claimed. Fresh assets/build identity and all affected gameplay, restoration,
sound and multiplayer regressions remain required in the consolidated pass.

## Sequence 272 — authored-lasers-and-room-acoustics (implemented; unverified)

`target_laser` now performs the authored 2048-unit, 100 ms ray trace, damages eligible
bodies, continues through actors and stops at solid obstructions. Spawn-after-world
resolution, named tracking, on/off, change-triggered contact sparks, optional loop
sound and ray state connect to native persistence. Temporary trace exclusions always
relink penetrated bodies. The native beam uses the supplied laser texture and the
reference renderer's actual white half-alpha, radius-two taper; color/fat flags are
not substituted for behavior that the supplied renderer ignores. The four supplied
instances are 1000-damage hazards in e4m6c. Collision, disable/re-enable, multi-body
penetration and restoration still require engine scenarios; no laser acceptance yet.

`trigger_change_sfx` reads authored preset names case-insensitively, including e4m5a's
`fxStyle=2`. Listener selection travels in the existing player-state field, survives
save/load and clears on map travel. Intentional compatibility correction: the touching
listener owns room changes; the reference broadcasts every player's room to everyone.
User volume settings remain independent. Prior engine styles 0..4 retain their meanings;
styles 5..30 map the 26 authored IDs to the already bundled OpenAL EFX definitions.
OpenAL applies full EAX reverb when supported, with standard EFX common parameters on
backends lacking EAX. Software mixing derives bounded delay feedback, damping and gain
from those same presets; it is a distinct DSP realization, not claimed auditory parity.

Private contract review: target.cpp laser trace/start/use and Triggers.cpp room touch,
cl_ents.cpp actual RF_BEAM rendering, Audio.h preset numbering and sv_send.cpp broadcast.
Public preset definitions are included directly from the pinned, already admitted
OpenAL headers (`engine/UPSTREAM.json`); no private implementation was copied. Engine
changes and new header hashes are recorded in DEVELOPMENT.json. Supplied property
inventory: `/tmp/dk3-runtime-272-world-properties.json`, using the existing local asset
manifest. Player-state round-trip coverage now includes room selection (unexecuted).

Targeted compilation builds the native modules and bundled engine because this batch
changes their audio contract. The first link's missing import is retained in
`/tmp/dk3-runtime-272-laser-room-link.log`; the corrected attempt is
`/tmp/dk3-runtime-272-laser-room-link-fixed.log` (exit 0: all native modules and engine products linked). No tests or engine sessions run.
Consolidated verification must use the updated engine, modules and regenerated assets;
prior audio, beam, restoration and campaign/multiplayer results need affected replay.
Authored breakage/debris, effects, remaining dynamic behavior and full-port acceptance
remain open. Main, installed playable build, saves and live service are unchanged.

## Sequence 273 — medicine-boxes-and-grouped-wall-breakage (implemented; unverified)

Episode-four `misc_drugbox` now uses the existing native healing-object binding and
toss/contact path with its own class policy: open without healing, then three finite
ten-health doses, stage-specific cooldown/audio, supplied model frames and final fade
/removal. Full-health use can open the box but cannot consume a dose. Damage cannot
destroy it. Stage, deadlines and fade state persist. Existing health-tree fruit and
multiplayer regeneration remain separate behavior; drug boxes never regenerate.

`func_wall_explode` now admits authored shootable or use-only walls. Lethal hits on a
grouped higher section route to a lowest remaining section in that team; nonlethal
hits remain local. Destruction removes collision, dispatches targets and schedules
saved fragment/explosion bursts from the actual brush bounds. Authored wood/rock model
choices, chunk/velocity/sound/explosion flags, 10–20 second fragment lifetime and the
two supplied explosion sprites use existing native effects and physics services.
Reference quirks are retained: NO_CHUNKS also prevents burst explosions; the metal
flag does not override the class's actual rock defaults. Broken sources stay inert
for delayed targets and pending bursts. Common explosion presentation now resolves its
registered sprite and publishes the orange light rather than hardcoding one variant.

Private review: healthtree.cpp drug-box use/initialization/fade, Triggers.cpp grouped
wall death and fragment generation, MISC.CPP explosion dispatch, World.cpp media names,
and cl_tent.cpp actual explosion variants/sounds. Implementations are independently
written. The supplied inventory has five drug boxes and 64 exploding walls; these
counts are authoring inventory, not acceptance. Directed regressions cover real health
consumption/cooldowns and damage redirection versus unaffected walls (written, unrun).
No link/test/engine gate was run for this checkpoint. Drug-box animation timing and
wall debris contact/water behavior still need presentation/physics comparison; the
shared native fragment response is not asserted identical to the private callback.
Fresh campaign, restoration and multiplayer verification remain required. Continue
moving authored debris, gib emitters and the remaining world/campaign/full-port work.

## Sequence 274 — moving-debris-and-gib-emitters (implemented; unverified)

Authored `func_debris` and `func_debris_visible` now own their initial visibility,
delayed target/owner resolution, launch, momentum damage, angular motion, delayed hull
expansion, impact audio and finite settling. Moving inline models render independently
of their bounding-box collision representation. Activator/drop/water launch contracts
and the authored fan exception follow private behavioral review. The class's effective
momentum-damage divisor is three, including its reference assignment quirk; unused
quarter-size/no-rotation-adjust flags are not given invented behavior. Persistent
state retains launch/expansion clocks, destination, spin, activator and stopped pose.

`func_gib` now resolves its target after the authored randomized startup, clamps count
and speed, emits finite 800 ms bursts, and respects use/no-toggle scheduling. Start-on
scheduling remains distinct from the reference's initially clear toggle flag. Bone and
robotic bounce, supplied torso/bone models, sound variants/attenuation, global fragment
cap, violence preference and fragment fade use native services. Fragment visuals add
travel-sampled diminishing blood trails and bone smoke. Native saves intentionally
retain emitters and pending bursts instead of the reference's FL_NOSAVE exclusion.
No private implementation was imported. Reference review covered MISC.CPP debris,
physics bounce/masks, gib.cpp generator/lifecycle and cl_fx.cpp diminishing trails.

The three native modules, including sequence 273, link successfully in
`/tmp/dk3-runtime-274-debris-link.log` (exit 0), under `zig-out/native-dev`.
Written targeted policy regressions are unrun. No contract suite or engine scenario
ran, and no verified build/asset identity is issued. The local authoring inventory
remains `/tmp/dk3-runtime-272-world-properties.json` on manifest
`ba03d6e56c08eef76e9a79a32b2da6c223d68433293c9e4f3b2aecead0606dc3`.
Remaining contact splats/sounds and precise fragment water/presentation behavior need
completion/comparison; a compiling emitter is not torture-rack cinematic acceptance.
Earlier fragment, collision, restoration and shared particle scenarios need affected
replay. Earthquake/lighting/particle/weather behavior and the remaining full-port
campaign/multiplayer/release work continue. Main, install, saves and service untouched.

## Sequence 275 — authored-quakes-and-lighting (implemented; unverified)

Earthquakes now use the authored radius/severity/duration/damage aliases, 100 ms
player-only pulses, per-player view-kick messages, 50/100 ms view envelope, random
loop sound and terminal source removal. They do not apply generic actor impulses.
Loop sound and active deadlines persist; restoration clears stale client kicks and
resumes server pulses. The damage path retains normal protection/armor accounting.

`target_spotlight` resolves/tracks its target, traces through actors without damage,
and toggles two sixteen-sided translucent cones and their endpoint light. Endpoint,
activation, target and timing survive native saves. A narrow compatibility correction
uses the computed endpoint in native presentation: the reviewed target_spotlight
source writes mins while its renderer reads render_scale. The two intro instances
still require actual engine/reference comparison; written geometry is not cinematic
acceptance. No arbitrary beam dwell, damage or obstacle bypass was introduced.

Switchable lights, authored lightstyle strings, shared-style update precedence and
reversible ramps now drive the existing bundled DKLS renderer interface. Previously
native cgame supplied all-one lightstyle values. Flare and episode flame sprites use
the supplied frame assets and per-axis scales; flames animate as two crossed planes
and apply their class's two damage on actual contact with damageable entities. The
native flame callback does not reproduce the reference assignment that makes arbitrary
non-damageable objects damageable. Plain inert lights stay authored metadata, as their
runtime reference instances are removed. Ambient-sound fields remain preload-only,
matching the reviewed no-op reference AmbientSound; no invented loop was added.

The earlier approximate default flicker samples are replaced by the thirteen public
GPL Quake II animation strings. Admission, pinned source/hash and attribution are in
`docs/provenance.md`; no private implementation was imported. Converter and native
policy now use those exact public samples. Custom pattern phases, lamp state and
in-progress ramp clocks persist. Built-in periodic styles still follow engine time;
full visual phase restoration/comparison remains to qualify.

Three modules linked in `/tmp/dk3-runtime-275-lighting-quake-link-fixed.log` (exit 0)
after correcting two compile errors recorded in the original
`/tmp/dk3-runtime-275-lighting-quake-link.log`. That link precedes the final public
sample-table replacement and added restoration regression. Policy/clock regressions
are written but unrun; no suite, engine scenario, connected route or reference visual
comparison ran. No current verified build/asset identity exists. Authoring inventories:
`/tmp/dk3-runtime-275-lights-authored.json` and sequence-272 world properties, on local
manifest `ba03d6e56c08eef76e9a79a32b2da6c223d68433293c9e4f3b2aecead0606dc3`.
Regenerated assets/shaders and coherent build/replay remain required. Dynamic lights,
lightning/attractors, particle/weather emitters and the remaining full-port campaign,
multiplayer and release work continue. Main, installation, saves and service untouched.

## Remaining authored actor admission

Read-only inspection of supplied BSP entity data finds no unregistered names in
65 quoted `monster_*` strings, including factory/death-spawn values. Nharre and Kage
now have controllers; the dynamically summoned Ghost has its separate controller.
Firefly, Wisp and path-corner names use their existing native owners.
Inventory: `/tmp/dk3-runtime-265-authored-classes.json`, local asset manifest
`ba03d6e56c08eef76e9a79a32b2da6c223d68433293c9e4f3b2aecead0606dc3`.
This inventory is not an engine run, full ability audit or campaign acceptance.
Dynamic dependencies, task combinations and boss progression require the broader audit.

## Acceptance rules

Track **implemented**, **contract-tested**, **running engine**, **connected authored
play**, and **reference comparison** separately. Failed setup invalidates its scenario.
Observe connection/restoration, input processing, weapon readiness, actual attacks and
contact, water levels, controller existence and save completion. Preserve first useful
failure evidence. Do not certify whole weapons/maps/restoration from narrower tests.

ReleaseSafe/Debug assertions are enabled. `build/runtime.zig` explicitly executes the
runtime root and separately imported actor, weapon, inventory and item test roots.
After material shared changes, mark affected coverage for replay; run affected checks
and the applicable aggregate at coherent checkpoints, without duplicate broad suites.
