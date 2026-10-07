# Multiplayer bot skill and sight

Owner request of 2026-09-30: multiplayer bots were too hard to play against, hosting
offered no usable difficulty choice, and bots saw everything around them. Sequence 322
implements one ten-level skill ladder and a real field of view. Status:
**implemented; unverified** — see [native acceptance](native-acceptance.md).

## Why the previous bots were "hardcore"

The whole bot brain is `src/runtime/server/bots.zig`: it picks goals and submits
ordinary user commands through the same player motor as humans. Its combat edge came
from perception and handling, not from better movement:

| Behaviour | Previous code | Effect in a match |
|---|---|---|
| Eyes in the back of the head | The target loop scanned every client, kept the nearest one within 1600 units and tested only a `MASK_SHOT` occlusion trace — never the bot's facing | Any enemy anywhere, including directly behind, was a valid target the instant line of sight opened |
| Perfect sight budget | Positions came straight from the ECS (`Transform`/`Health` of every client); area visibility and the bot's own view were not consulted | No distance or direction penalty; a bot never "missed" someone in a screen corner |
| Instant, perfect aim | The commanded view was `atan2` of the enemy centre each 50 ms tick, with no turn limit and no error | Snapped onto a target and hit the same tick it appeared |
| No reaction delay | The brain re-decided at 20 Hz and set `BUTTON_ATTACK` in the acquiring tick | A human turning a corner met live fire immediately, before their own input could respond |
| Continuous fire | `domain/bot_combat.zig:attack()` gates only range, ammo, splash and charge | No burst discipline; full weapon rate forever |
| Decorative difficulty | `add()` wrote a fixed `\skill\3\` and nothing read it; the LAN page only wrote `g_spSkill`; the Internet create page had no skill control at all | Difficulty could not be changed, and did not change bot behaviour if it was |
| Wrong scale for the value that existed | `g_spSkill` is the authored five-level single-player scale (save/persistence clamps 1..5) | A ten-level hosting ladder could not be routed through it |

## Ten-level ladder

`src/runtime/domain/bot_skill.zig` defines the ladder once. The hosting menu, the room
services and the server brain all use it, so a room created anywhere behaves identically.
Level 10 keeps roughly the previous perfect behaviour; level 1 is the least dangerous.
Default is 5.

### Perception

| Level | Tier | View cone | Sight | Proximity | Memory |
|---|---|---|---|---|---|
| 1 | Novice | 80° | 512 | 128 | 400 ms |
| 2 | Beginner | 90° | 640 | 144 | 500 ms |
| 3 | Casual | 100° | 768 | 160 | 600 ms |
| 4 | Average | 110° | 900 | 176 | 700 ms |
| 5 | Capable | 120° | 1024 | 192 | 800 ms |
| 6 | Skilled | 130° | 1152 | 208 | 1000 ms |
| 7 | Expert | 140° | 1280 | 224 | 1200 ms |
| 8 | Master | 150° | 1400 | 240 | 1600 ms |
| 9 | Elite | 160° | 1536 | 256 | 2000 ms |
| 10 | Merciless | 170° | 1792 | 288 | 2600 ms |

### Handling

| Level | Reaction | Turn rate | Aim error → 0 | Settle | Burst | Scan hold | Gunshot error | Alert |
|---|---|---|---|---|---|---|---|---|
| 1 | 700 ms | 140°/s | 9.0° | 1400 ms | 500 ms | 1100 ms | ±60° | 4000 ms |
| 2 | 560 ms | 180°/s | 7.5° | 1250 ms | 400 ms | 1000 ms | ±52° | 3600 ms |
| 3 | 450 ms | 220°/s | 6.0° | 1100 ms | 320 ms | 950 ms | ±44° | 3200 ms |
| 4 | 360 ms | 280°/s | 4.5° | 950 ms | 260 ms | 900 ms | ±36° | 2800 ms |
| 5 | 290 ms | 340°/s | 3.5° | 800 ms | 200 ms | 850 ms | ±30° | 2500 ms |
| 6 | 230 ms | 420°/s | 2.5° | 650 ms | 160 ms | 800 ms | ±24° | 2200 ms |
| 7 | 180 ms | 520°/s | 1.8° | 520 ms | 120 ms | 750 ms | ±18° | 2000 ms |
| 8 | 140 ms | 640°/s | 1.2° | 400 ms | 90 ms | 700 ms | ±12° | 1800 ms |
| 9 | 110 ms | 800°/s | 0.7° | 300 ms | 60 ms | 650 ms | ±8° | 1600 ms |
| 10 | 60 ms | 2400°/s | 0.2° | 200 ms | 30 ms | 600 ms | ±4° | 1400 ms |

Authored single-player actors keep their five-level scale: level 1..10 pairs to
`g_spSkill` 1/1/2/2/3/3/4/4/5/5. In a multiplayer match the population owner publishes
that pairing, so one hosting choice drives both the bots and any map actors.

## Field of view: bots must look around

- **Acquisition is inside the view cone.** A candidate is only considered when it is
  inside the level's cone around the bot's actual `Transform.angles`, within the sight
  range, or closer than the proximity radius (mirroring the existing actor sense, where
  someone next to you does not require facing). Occlusion is still an ordinary
  `MASK_SHOT` trace, now only for candidates already in view.
- **The view has a speed limit.** The commanded view turns at most `turn rate × dt`
  degrees per brain step, in yaw and pitch, so an enemy outside the cone cannot be
  aimed at until the bot has physically swept onto them. Measured time to notice an
  enemy standing directly behind, turning straight at them: 1.00 s at level 1, 0.40 s
  at level 5, 0.05 s at level 10.
- **A bot with nothing to look at searches.** While it is not fighting and not lining up
  on an authored control, the wanted heading adds one of the scan headings
  `{0, +40, -40, +80, -80, 0}` relative to travel, held for the level's scan period.
  This covers the sides while walking and leaves a blind wedge directly behind, which is
  the point. While it sweeps, locomotion stays projected onto the route heading rather
  than the view heading, so a bot checking its shoulder walks forward like a player
  edging around a corner instead of sliding sideways along its own view; fighting and
  control aiming keep the previously accepted view-relative movement.
- **Sight is not memory, and memory is not sight.** Losing a target inside the cone
  keeps its last position for `memory` only: the bot moves to where it last saw them and
  keeps searching, and cannot fire at what it cannot see.
- **Being shot is a cue, not sight.** A new `data.Hurt` receipt makes the bot face the
  shooter's bearing, wrong by up to the level's gunshot error, for the alert period.
  Low levels turn slowly and look in a roughly right direction; high levels turn almost
  at once. Fire discipline and the reaction timer still apply before it answers.
- **Nothing else about the bot changed.** Objectives, pickups, routes, lifts, doors,
  jump/crouch/ladder handling and the ordinary user-command path are untouched, so
  navigation regressions remain separately attributable.

## Selecting difficulty when hosting

- `ui_roomSkill` is the single hosting value, 1..10, shown as `Bot skill: N (Tier)` on
  **both** hosting pages: LAN and Create Internet room.
- LAN hosting writes `dk3_bot_skill` before `map`; the dedicated/Internet room path
  passes `+set dk3_bot_skill` from the room configuration, which the coordinator and the
  permanent-room policy validate as 1..10.
- `dk3_bot_skill` is registered `CVAR_SERVERINFO`, so it also appears in server browser
  info. Changing it mid-match applies to living bots on the next population pass and to
  new bots immediately; the bot's name keeps the tier it was created with.
- `dk3_bot_fov` overrides the cone for diagnosis only: 0 uses the ladder value, and any
  other value is clamped to 1..359, so `359` restores the old see-everything behaviour
  and `2` leaves only the proximity radius plus what is dead ahead.
- Room listings carry `bots` and `skill` so a player can see what they are joining.

## Diagnostics

`developer 2` prints one route line per living bot at 1 Hz, and the front of that line
is now vision evidence:

```
dk3 bot route: slot=0 skill=5 (Capable) fov=120 view=-13.0,-2.8 scan=-40 alert=0 target=585 seen_ms=2350 goal=… blocked=0 …
```

`view` is the yaw/pitch the brain last commanded, `scan` is the heading currently held by
the look-around sweep, `alert` is 1 while the bot is facing the bearing of the last
gunshot that hit it, `target` is the persistent id of the enemy it can see, and
`seen_ms` is the age of the last confirmed sighting — a non-zero `target` with a stale
`seen_ms` is "remembered, not visible", which is also why it will not fire.

## Sampled matches

`dkq3/tools/runtime_bot_skill_probe.py` plays a bot-only dedicated match, changes
`dk3_bot_skill` mid-match the way a host can, and summarises the `developer 2` telemetry.
Sampled smoke, not acceptance — see [`zig-out/reports/runtime-zig-322/`](../zig-out/reports/runtime-zig-322/README.md):

    python3 dkq3/tools/runtime_bot_skill_probe.py \
      --report zig-out/reports/runtime-zig-322/ladder --phases 10:34,5:34,1:34

On the compact FFA map e1dm2a with four bots, the share of samples where a bot held a
target fell monotonically with the ladder: 38% at level 10, 21% at level 5, 12% at level 1.
Pinning the cone to 2° with `dk3_bot_fov` (same levels, same map) took levels 5 and 1 down
to 2% while level 10 kept 27% — its 2400°/s snap recovers from an almost blind cone, which
is the intended "level 10 behaves as before" property. Views changed on essentially every
sample (79–90 distinct headings out of 84–92) and the sweep set cycled in every run, so no
bot keeps a locked-forward gaze; navigation telemetry stayed healthy in all runs (rare
`blocked`, 50–59 distinct waypoint edges, jumps and ladders still taken).

Two things these runs are not: a controlled measurement (unsupervised encounters dominate
the percentages) and a balance verdict. The pure policy tests, not the sampling, are what
pin the cone geometry itself.

## Shared pilot

Since sequence 342 the multiplayer bots fly the same pilot as the co-op bot and the
companions (`bot_pilot.zig`); `bots.zig` keeps only population, the ladder, goals
(objectives, pickups, resupply, chasing the last sighting, skipping an unreachable
objective) and team coordination, and submits the pilot's command through
`bot_input.zig`. The pilot runs with match options: enemy players by team (aimed at
the chest, no range limit beyond the ladder's sight), turning to gunfire, looking
around while walking, no ammunition hoarding, stepping aside for teammates, a
teammate's claimed control left to it while this bot waits at the gate, and a 16-unit
clearance from lethal volumes (the co-op bot and companions keep 48; inside the margin
a step may run alongside a volume but not close on it). With an enemy in sight and no
objective or resupply under way, a bot fights from a firing stand on a short tether
instead of running past.

Three ladder knobs shape the new handling. Level 10 is unchanged; the co-op bot and
the companions fly at level 10.

| Level | Dodging and strafing | Projectile lead | Fire within |
|---|---|---|---|
| 1 | no | 0 | 16° |
| 2 | no | 0 | 15° |
| 3 | no | 0.25 | 14° |
| 4 | no | 0.40 | 13° |
| 5 | yes | 0.55 | 11° |
| 6 | yes | 0.65 | 10° |
| 7 | yes | 0.75 | 9° |
| 8 | yes | 0.85 | 8° |
| 9 | yes | 0.95 | 7° |
| 10 | yes | 1.0 | 6° |

`developer 2` adds a `dk3 bot pilot:` line after each route line (hazard refused,
dodging, firing stand, route state, objective skip).

Sampled comparison (`zig-out/reports/mp-pilot/`, same probes as above): on e1dm2a
the target-held samples at levels 10/5/1 were 15/26/4 before and 35/25/7 after,
monotonic again, with navigation as healthy (0–2 blocked samples, 53–63 waypoint
edges); dodges occurred at levels 10 and 5 only. CTF e1ctf1 still makes its
contested capture; deathtag e1dt1 keeps three bomb carriers (and, as before, no
capture). Smoke, not balance: no human has played the new low levels yet.

## Companions

Superfly and Mikiko fly the co-op bot's pilot (`bot_pilot.zig`) at the top of the
ladder (level 10), through `companion_pilot.zig`. The pilot's command drives the
companion's own player motor with its class hull and speed; its trigger decision goes
to the companion weapon step, where the weapon's own leader-safety lane check stays the
last gate. Companions never operate controls, take teleporter passages or press use,
and keep out of any enabled hurting volume of 5 damage or more (the co-op bot: 25),
besides lava, slime, nitro, drops, currents beside drops and descending lifts. Weapons
are chosen by the bot scoring over what the companion carries, excluding those whose
splash or spread the reviewed companion rules keep away from the leader; an emptied
discus or venom still strikes up close.

`companion_brain.zig` decides the intent each frame:

| Situation | Behaviour |
|---|---|
| Following | A spot beside/behind the leader on the companion's own side, the other side, straight behind, or back along the leader's trail; each candidate must have level floor, no harmful liquid (water only when the leader is in it), no hazard volume, no descending lift above, and a way there. Settles within 64, sets off beyond 96. |
| Healthy, threatened | Hostiles hunting the companion or the leader, or seen: hold and shoot from a stand, or close in along the area graph, never beyond 512 of the leader (1024 under an attack order). |
| Below 50% health | No closing in; fires from the follow spot; detours to a reachable health pack it may take (never one past the enemy). |
| Below 25% health, or only a melee weapon while hunted | Falls back behind the leader away from the enemy, out of its line of fire, never by way of it; fires only when cornered (enemy within 192) or to finish an enemy at 15 health or less. |
| Off the area graph, or the leader where no route goes | After 2 s without headway, walks back to where a route last existed; with none, waits (4, 8, then 16 s) instead of hopping against the obstacle. |

Orders (`stay`, `move`, `attack`, `collect`), authored stops and teleports, item
collection and lane yielding keep their meaning. Planning state is transient (never
saved); a restore or an absence starts it afresh. `developer 1` prints a `dk3 sidekick:`
status line per companion each second (health, goal, fire discipline, enemy, route and
retrace state). `dk3_runtime_damage <amount> superfly|mikiko` hurts a companion for
diagnostics.

## Open work

No level has been played by a human against bots, and the balance of levels 1..3 on the
shipped maps is unreviewed. Encounter *frequency* on the larger maps is set by sight range
before it is set by the cone — on e1dt1 the four bots met far more rarely than on e1dm2a at
every cone width, so `sight_range` is the first knob to reach for if matches feel empty,
not the cone. The bot still knows item and objective locations without seeing them, and
teammate coordination is unchanged.
