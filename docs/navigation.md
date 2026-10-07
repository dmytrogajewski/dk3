# Native navigation

Ground actors and multiplayer bots use the bundled ioquake3 botlib and locally compiled
AAS. `dkq3/tools/navigation.py` runs the bundled GPL BSPC on converted maps. Flying and
swimming actors use authored graphs normalized by `dkq3/tools/nodes.py`; track graphs
are retained in the same format. Live bounding-box traces determine edge availability.
Swimming edges also require water along their length. No route disables collision or
teleports an actor through a locked passage.

The supplied `.nod` layout is little-endian: NUL-terminated `NODES:`, version 0, then
named ground/air/track node or path-table chunks. A node list contains version, count,
allocated count, and records. Each record stores index, position, type flags, data
version/payload, two length-prefixed target strings, and up to six distance/index links.
Payload version 0 occupies 32 bytes; version 1 contains three floats. Path tables contain
a version, dimension, and a square matrix of 16-bit indices. Unsupported chunks/versions,
truncation, invalid coordinates, duplicate indices and dangling links produce a named error.

The normalized `dk3_routes 1` file retains directed graph links, positions, flags and
target names. Its JSON companion retains the original payloads and stored link distances.
Ground/water/air/track use flag values 1/2/4/8; water nodes occur in the ground graph.
The runtime computes shortest paths with a binary heap and geometric edge distances.
Per-actor route caches expire in simulation time and are rebuilt after world initialization.
They are derived state and do not enter saves.

Format probes cover e1m1b, e1m5a, e1m7b, e2m2a, e3m1a and e4m1a. All 84 maps
have generated AAS, and running servers load their navigation. Bots use ioquake3
BotMoveToGoal and its walk, jump, teleport and elevator movement decisions. Multiplayer runs demonstrate movement, two uncontested CTF captures and deathtag captures through both courses, including submerged travel.
The revised direct-use eligibility requires fresh objective replays; complete
multiplayer acceptance remains open.
Dynamic doors, swimmer confinement, airborne pursuit and companion recovery still need
complete scenario coverage.

Authored teleporter destinations are raised only as far as a clear player landing requires,
within 64 units and without crossing an obstruction. BSPC uses the same clearance policy.
Vertical func_door entities can carry elevator reachabilities, including button-operated
lifts. Botlib identifies a waiting elevator through its existing blocked-entity result;
the game follows authored target links to a physical control and uses it only within reach.
The e1dt1 compiler probe adds both missing lift routes and all 29 teleport links. All 84 navigation files were regenerated after these compiler changes.
Bots can assign distant switches to an available teammate, retain nested switch
dependencies, dismiss monitors after their authored wait and allow pressed buttons
to reset before using them again. Lift descent has been exercised; reliable teammate yielding and the wider objective
matrix remain under scenario repair.

The compiler uses fixed-width 32-bit MD4 words so checksums agree on Linux x86-64.

Navigation has explicit easy, normal, hard, deathmatch, CTF and deathtag selections.
`bspc -dk3-mode <mode>` applies authored difficulty/mode exclusions to brush entities.
The converter groups selections with identical eligible brush sets and compiles only
distinct variants. `dk3/navigation/<map>.cfg` maps each selection to its AAS file;
the runtime chooses it using game type and campaign difficulty. Missing selection
metadata produces a rebuild diagnostic. The original BSP and its checksum stay intact.

This fixes e1m1c's easy-only ramp (*28, spawnflags 24576): navigation previously
offered a continuous walk across it on normal difficulty, where the wall correctly
does not spawn. Its easy profile retains that floor; normal/hard contain the gap.
Other dynamic obstacle and route scenarios still require running-game verification.

Unqualified `trigger_hurt` brushes exclude both teams in AAS routing rather than
masquerading as lava. Deathtag carriers may cross actual lava/slime, but their
environmental protection does not cover these damaging triggers. The e1dt1 capture
pit exposed this distinction during repeated bot runs.

Shared ladder movement requires facing into the ladder for view-directed climbing;
explicit up/down input can attach from the side. Moving away detaches. Mere contact
while walking along a ladder brush uses ordinary movement. The e1dt1 side-girder
stalls exposed the former unconditional attachment behavior.

Local bot recovery also uses BotMoveInDirection prediction, including ledge and liquid
hazards. Pickup goals must have an AAS route. The goal's straight-line direction alone
is insufficient evidence of a safe local move.

The Q3 BSP reader reconstructs the compiler's internal ladder contents from
`SURF_LADDER` brush sides. That internal bit overlaps a different Q3 contents flag,
so raw brush contents alone cannot identify ladders. The repaired e1dt1 compiler
probe generates 521 ladder reachabilities; its lower pickup region can now reach
the team objective. All 84 navigation files have been regenerated with these ladder and hurt-volume
inputs. Full per-map navigation and companion scenarios remain open.

When a bot stands on physical floor outside AAS, recovery checks a bounded player-hull
path with step-height clearance and continuous ground support into a usable area.
It rejects hazardous liquid and hurt triggers, and emits normal movement input.
Optional pickups and wandering goals require a return route too: an item reachable
by dropping into a pocket is unsuitable when the only exit crosses unprotected slime.

Automatic unnamed platforms start and hold for players or actors whose ground entity
is that platform. Waiting beside or below a lift does not launch it or postpone its
return. This corrects e1m1c's approach-triggered departure and upper-stop stall.
Rotating movers test exact brush contact before pushing nearby non-riders, so an entity
intersecting unrelated world geometry cannot block a door merely by entering its
conservative rotation bounds. Authored stationary pickups are collection triggers and
do not obstruct movers; dropped pickups remain physical through their physicsObject
flag. These behaviors share ioquake3's collision/pusher path.

Movers remove a dead actor corpse only when it cannot be pushed out of their
path, matching ioquake3's blocked-object cleanup. Living actors and temporarily
downed actors still take normal crush damage and participate in reversal.

Step links now require a supported crossing through the source BSP collision.
The compiler samples the overlapping ground edges when their lowest projected
point is unsupported. Its collision probes include the same eligible static
brush models and rotating-door placement as AAS construction. At a real floor
covered by conservative AAS bounds, it uses botlib's initial four-unit upward
area lookup. Physical clearance and support are still required. This removes
phantom step links found near e1dt1's red-course ramp; the changed compiler
requires regenerated navigation packages. Full-map regeneration and objective
acceptance are recorded separately from compiler completion.

Bot stall recovery retains botlib's reachability timeout and failure history.
A three-second reset previously erased them before a five-second walking link
could expire. Recovery also preserves an already requested jump: replacing it
with a sideways walk prevented the blue-course barrier takeoff. Neither repair
changes the player's collision or moves a bot directly.

Navigation compilation uses BSPC's `-forcesidesvisible` option. The converted
BSP retains collision sides without matching rendered surfaces. BSPC's default
surface matching omitted some of those sides as partition planes, extending
solid regions beyond the physical brush. In e1dt1 this created a false raised
floor and repeated barrier jumps in the blue course. Keeping all brush sides
produces 8021 areas and 13865 reachabilities, and both teams complete captures
in the repaired two-bot and four-bot deathtag scenarios. Compiler options are
part of the resume identity so earlier navigation cannot be silently reused.
All 97 variants across 84 maps have been regenerated; the running dedicated
server loads every expected map/profile pairing. Broader actor, companion and
multiplayer navigation acceptance remains open.

Equal-floor crossings keep their end point inside the destination AAS area. BSPC
reduces its usual five-unit inset at narrow portals instead of steering beyond
them into a solid region. The e1m2a ledge probe preserves all 7,410 links and
repairs 704 end points whose previous area lookup differed from the destination.
The two ledge crossings from area 2881 now end in areas 2824 and 2855. This is
structural evidence; a running bot crossing and the wider navigation refresh
remain part of the gameplay repair pass.

## Generic navigation (sequence 340, generic-navigation)

Owner request (2026-10-07): navigation should not depend on per-map waypoints in
co-op routes; robust generic navigation should take the bot (and multiplayer bots)
wherever the authored progression allows, with routes stating only what to reach
and what to do. Status: **implemented; unverified** except where evidence is named.

**Coverage report.** `dk3_runtime_navigation_coverage [grid] [jump]` floods the
space a player can reach from each map's player starts over static geometry, with
the native hulls and moves (standing step, crouched step or level crawl, standing
jump, any drop; brush entities unlinked as BSPC treats doors), and checks every
floor for an AAS area and an AAS route from the start that reached it. Floors are
classed routed, *gated* (routable only through a damaging volume), *uncovered* (no
area) or *unrouted* (no route), and gaps are grouped into regions.
`dkq3/tools/runtime_navigation_coverage.py` runs it per map in a fresh dedicated
server (`--overlay` stages a recompiled navigation package under test).

**Compiler fixes** (bundled BSPC, `engine/BSPC-CHANGES.json`), each found with the
report on e1m3a:

| Defect | Effect | Repair |
|---|---|---|
| BSPC's built-in Quake III crouch hull (maxs z 16) and step 19 | every crawlway 28–40 units high missing (e1m3a's vent and pipe room) | `dkq3/tools/dk3-aas.cfg`: native hulls (crouch maxs z 4) and step 18; botlib's crouch presence box likewise in both copies |
| converted trigger brushes keep solid contents; `trigger_hurt` only added team flags | every hurt volume compiled as a wall | hurt brushes carry only the no-entry team flags and are expanded like liquids |
| every `trigger_push` compiled as a Quake III jump pad | Daikatana's 40 targetless pushes (draughts, laser shoves) became dead-end areas without walking links | only a targeted push is a jump pad |
| triggered or toggled `func_wall` compiled solid | cell force fields and walls a scene removes cut routes for good | compiled as mover areas with their model number; non-solid (32) and CTF-only (64) walls left out elsewhere (the variant grouping applies the same flag) |
| a sideways-sliding thin `func_door` compiled as mover space | bridges and sliding floors had no floor | a door whose model is a thin wide slab is floor in its authored place |
| no lift links for `func_train` | Daikatana's train lifts unroutable | vertical legs of a train's path get elevator links; the rider floor is found in the train model at a column clear at both stops (a lift may ring a pillar) |
| elevator exits searched within 12 units, growing across probes | lifts stopping short of their landing unlinked | exits up to 96 units out, reset per probe, each required to stand on floor |
| a crawl-high gap from a decorated void to the outside leaked with the smaller crouch hull (e2m2c) | compile failure | on a leak, the space joined to the outside is sealed and the entity flood repeated |
| riser edges split by tiny crouch areas end a tenth of a unit off the riser plane (tolerance 0.1) | step and walk-down links dropped; with the smaller crouch hull e3m2a lost 25,000 floors behind one 16-unit step | when the strict pass finds no pair, edges within half a unit of the plane are compared (only as a fallback: the lowest pair is kept, so a wider pass everywhere let drops displace steps on e3m4a) |
| train lifts linked only upward; BSPC compiles the shaft empty | the way down was a fall into the shaft, impossible with the lift standing at the top (e1m3a's cell block 2 lift) | each train leg also gets the reversed elevator links; falls of more than 64 units and jumps landing in a train's swept shaft are dropped (the short step onto a lift resting in its pit stays) |

e1m3a, before and after (evidence below): 14,190 reachable floors; uncovered
245 → 9; unrouted 10,355 → 402; 1,537 floors are gated behind lasers and force
fields that the level switches off.

**Live gates** (`src/runtime/server/navigation_gates.zig`). The compiled AAS treats
every dynamic blocker as open; a gate is one such entity with the areas it fills,
disabled for routing (`AAS_EnableRoutingArea`) while it blocks: a damaging volume
dealing 10 or more while switched on, a toggled wall while it stands, a door opened
by an authored control until open, a sliding floor away from its place, a breakable
until broken. Player routes admit the no-entry team flags, so switched-off hazards
are routable. Gates are rebuilt per world and shared by every routed player.

**Planner** (`bot_routes.unblock`). When the live route fails, routing with every
gate open finds the first closed gate on the way; a moving gate means wait;
otherwise the authored control whose chain opens it (button, trigger, event
generator, relay; a breakable is shot) is chosen, preferring one reachable as the
gates stand and otherwise planning the gate in front of that control first. The
co-op motor asks it whenever navigation has no way to its goal; routes reach it as
`dk3.plan(goal)`, which `advance`/`progress` try before their nearest-control
heuristic, waiting for the gate to answer before planning again.
Multiplayer bots ask it too. A bot whose teammate already fetches the control, or
whose gate is already moving, waits at the gate's near side (the predicted route's
last open position before it): e1dt1's lift doors open from a button across the
map for ten seconds, so whoever crosses must already stand there.

**Lifts.** Navigation waypoints mark lift links and carry the link's entrance.
The co-op motor boards a lift standing at (or level with) the entrance, operates
the control that sends it (or calls it down), holds at its middle while it travels
(trains included) and continues at the far stop; aboard a lift whose route goes on
far above or below inside its shaft, it sends the lift too. It never waits under
a raised lift. Lift handling also runs while the planner's control is pending (a
button the lift carries the player up to); a train control is done once the train
moves. Only something that lifts (a train, a vertically moving mover) is taken for
the lift, preferring the one underfoot.

**Objectives by entity.** A `use`/`shoot` objective needs a standing point from
which it works. Buttons are tried beside each face and corner; a shooter walks out
along eight directions in 16-unit steps from the target's edge, taking the first
point with a line to it (decorations are outside the shot mask, so a clear line
counts), outside half the blast of an explosive target (scenery 100, breakables
their radius). With no such point reachable as the gates stand, one is chosen as
if every gate were open and the planner opens the way to it. A short level walk
needs no route (a control carried on the lift underfoot lies in shaft space the
area graph leaves empty). Presses of other controls on the way do not count as
presses of the objective.

**Movement details found on e1m3a.** Waypoints crouch when the current or next
area is crouch-only (walking links into a crawlway are ordinary walks); the local
crouch test also tries a ducked step-up (a jammed door's lower half). A blocked
bot looks for the door ahead with a slim body when its hull grazes the jamb, so a
door opened only by use (no targetname, no touch flag: e1m3a's hidden door) is
operated. A breakable's gate takes only the areas centred where a player's hull
would meet its brush, not a corridor area that merely touches a wall panel.

**Found on the episode-1 chain.** The navigation service skips a route point the
player already stands on (thin water layers whose entry lies just below the feet:
e1m1b's ford). Lifts (vertical doors wide both ways) are not gates; multiplayer bots
ride them through the same `liftStep` as the co-op motor, wait at most 20 s at a
gate nobody opens, and pursue items while their objective has no route. A volume's
goal is a walkable point touching it (e1m3b's exit strip lies past the last area);
an exit another entity fires is never the one to walk into.

Evidence (local, `zig-out/reports/runtime-zig-340/`): with the regenerated
navigation (`dk3-navigation-340.pk3`, not installed) and the final build, a New Game
run plays intro → e1m1a → … → e1m2b → e1m3a → e1m3b continuously without a death
(`coop/final7-newgame/`), e1m3a by its objective route; so does a chain from e1m1a
(`coop/final7-chain/`). All 84 maps load and report coverage (`coverage/navcov-final/`).
Multiplayer comparison and remaining limits are in
[native acceptance](native-acceptance.md#sequence-340--generic-navigation--implemented-partially-verified)
and the RUN log.
