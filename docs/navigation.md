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
