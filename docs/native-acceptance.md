# Native port acceptance

Development stays on `rewrite/native-zig-runtime`. Main, the installed game, user
saves and the online service are preserved. Full four-episode campaign, companions,
multiplayer modes/bots, persistence, UI and release remain in scope. Removed-runtime
results never transfer to native acceptance.

## Active implementation pass

Owner-directed broad coding pass (sequences 255–267): remaining episode and multiplayer
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
