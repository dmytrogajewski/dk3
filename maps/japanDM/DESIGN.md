# japanDM — deathmatch map design

Status: authored in this directory (`materials.py`, `build_blender.py`); installed as
`japanDM` through `zz-dk3-japandm.pk3`. Nothing in the game's code, its preserved
installation, or its saves is touched by this map.

Setting: Mishima-heavy future Japan, the register of the shipped episode 4
(`e4m3a "Tower of Crime"`, `e4m4a "Mishima Labs"`, `e4dm2 "~Hard Lesson~"`). A
megacorp rooftop bazaar above a neon shopping street: an open plaza with a holo
pool, a market deck of stall counters at the level above, and a roof garden with a
vermilion torii and a monorail viaduct at the top. Dusk, light rain haze, signage
carrying most of the light.

## 1. Pattern research

Two inputs, kept apart on purpose: the first is a set of measurements taken from
the shipped maps in this repository, the second is the ordinary deathmatch mapping
doctrine that those measurements illustrate. Nothing below is an estimate: every
figure in the "measured" column came from reading a converted BSP's entity lump
with `dkq3/tools/entities.py`.

| map | spawns | brushes | bounds (x × y × z) | measured |
| --- | --- | --- | --- | --- |
| `e1dm1` | 15 | 3976 | — | 23 `item_health_25`, 82 `target_speaker`, 18 `func_wall` |
| `e1dm2` | 9 | 1485 | — | |
| `e3m1dm` | 29 | 5721 | — | |
| `e4dm1` | 11 | 571 | 2464 × 2928 × 1600 | 158 `light`, 12 health, 4 weapons tiers |
| `e4dm2` | 11 | 1302 | 1920 × 2112 × 1360 | 76 `light`, 34 `sound_ambient`, 6 `trigger_teleport`, 2 `trigger_push` |
| `slicedm1` | 5 | 244 | — | |

So the shipped future-Japan arena is 1.9–2.9 thousand units wide, 1.1–1.6 thousand
units tall, 11 spawns, and *dense with lights*: 158 of `e4dm1`'s 272 entities are
`light` (58 %), and `e4dm2` puts 76 of 207 there. Every row above was re-read
against the shipped archives before this map shipped -- spawns, brush counts and
censuses agree -- and the same read adds what the presentation section needs:
4,545 and 4,763 surfaces over 988 and 983 portal clusters, 23 lightmap images
each, and no deluxe lightmaps in any shipped arena.

`japanDM` deliberately keeps the footprint of `e4dm1` (so travel times stay in the
same band) and doubles its entity and brush budget for detail, not for area.

Player physics measured from the runtime (`src/runtime/player*`, `q_shared.h`):
speed 320 u/s, gravity 800, jump 270 impulse ≈ 44 u of clearance, acro jump ≈ 89 u,
step-up 18 u, player box −15..15 x/y and −24..+32 z around the origin, eye height
feet + 22 (two units *below* the spawn origin). Those numbers turn into rules:

* **A tread may rise 16 units and no more** — 18 is the step-up limit, and a bot
  walks a 16-unit tread the same way a player does. 256 units of height therefore
  cost 16 treads, or one ramp of 20° or less.
* **A gap a player must clear is at most 160 units**, and geometry that must not be
  skipped is never closer than 89 units to a jump-from surface.
* **Every level change needs two independent routes.** With 44 units of jump, one
  staircase is a chokepoint that a single camper owns.
* **Travel time is the real currency.** At 320 u/s a 500-unit lane is ~1.6 s, a
  2300-unit crossing of the whole map is ~7 s at a full strafe that no fight ever
  allows. Lane lengths of 250–600 units keep every route change inside ~2 s.

The doctrine those numbers serve, as practised on the Quake III / Unreal deathmatch
maps this engine's genre descends from (Q3DM17's layering, `q3t3tour2`'s vertical
rings, the CPM/QuakeCon "aerowrk" lineage of fast 1v1 arenas, and Daikatana's own
`e4dm2` teleport-and-push-pad pacing):

1. **Ring, not tree.** The walkable space must contain cycles, so that retreat is
   always possible and a fight never becomes a corridor. `japanDM` is a double ring
   (a plaza ring at the market-deck level, a street ring at ground level) joined by a
   spine (the skybridge) — a figure eight in plan and three storeys in section.
2. **Three or more routes between any two control points**, at least one of them
   hidden from the destination, so approach is a choice and not a reveal.
3. **Sightlines are budgeted, then measured.** A long sightline is a weapon for
   whoever holds the angle, so an arena wants a handful of them, each with an
   escape at the viewing end, and *none* of them pointing at a spawn point.
   `map_author.audit` reports spawn pairs with no intervening solid; the target is
   zero, and a separate sightline probe (`dkq3/tools/map_sightlines.py`) counts the
   long clear lines from a grid of eye-height samples.
4. **Item value is proportional to risk.** Small arms and small health sit on the
   exposed ring; the best weapon, armour, and the timed boosts sit where a fight is
   already happening or a hazard must be crossed. Respawn times come from the
   runtime (`domain/items.zig:respawnDelay`): weapons per-weapon, boosts and the
   golden soul 60 s, everything else 30 s — so a boost is a 60-second map control
   decision, not a pickup.
5. **Readability before density.** One landmark per district (pool / stall rows /
   torii / viaduct), one silhouette that is visible from most of the map, and a
   colour code per tier: wet asphalt at street level, warm metal on the market deck,
   green planting and vermilion lacquer on the roof.
6. **Nothing in the level may surprise the collision system.** Static collision
   only in v1: breakables and movers are excluded from the bot compiler's
   `NAVIGATION_BRUSHES` (`dkq3/tools/navigation.py`), so bots would path through a
   crate that a player can smash, and a `func_plat` would make an AAS floor that is
   not always there. Sealed shell, no leaks, no `hint` brushes in v1 — the ring
   itself is the visibility structure.
7. **Bot legibility is part of the design.** The AAS must reach every room, so
   rises are stairs or shallow ramps only, and the map is audited by area and
   reachability counts (`bspc` report) plus a live bot match, not by eye.

## 2. Layout

Plan is 2304 × 2304 (inner wall faces at ±1152), three walkable tiers plus a
viaduct: **T0 street 0**, **T1 market deck 256**, **T2 roof 512**, **viaduct 704**;
total height with the sky shell 960. The whole footprint is a floor slab at T0 and
every building is a solid placed on it, so the walkable space is the complement and
stays connected by construction.

| district | tier | what it is | control role |
| --- | --- | --- | --- |
| Plaza | T0 | octagonal open deck with the holo pool at the centre | contested middle; sightlines out along four streets, no cover at the very centre |
| Market alley (W) | T0 | stall counters, crates, awnings | close-range fight, three lanes through the counters |
| Vending alley (E) | T0 | machine wall, vending glow, stairwell mouth | the eastern route and the T1 back door |
| Service drive (N) | T0 | loading bays, pipes, the coolant chute | the hazard: `trigger_hurt` at the chute mouth, best ammunition behind it |
| Station mouth (S) | T0 | stairs up to the deck, under-bridge shade | the map's most open spawn area, so it is covered by geometry |
| Market deck | T1 | ring walkway around the open plaza, railings, overhead canopy | looks down on the plaza; three ways up, three ways down |
| Roof garden | T2 (W/N) | planters, koi basin, torii approach | the western high ground |
| Torii plaza | T2 (E) | vermilion gate on a raised pad | the eastern high ground and the map's landmark |
| Skybridge | T2 | glazed corridor from the garden to the torii | the spine: crosses the plaza, exposed on both flanks, one item inside |
| Viaduct | 704 | monorail deck on columns, guide beam, two stairs | the reward for holding T2, not a start: two entrances, one escape each, and no eye line on the deck clears its own rails |

Height budget: 256 units between tiers = 16 treads of 16, or a 550-unit ramp at
25°, both of which are used. The viaduct at 704 is 192 above T2 = 12 treads.

## 3. Spawns, items, sightlines

* 14 `info_player_deathmatch`, all on a real floor with ≥ 64 units of headroom,
  none on a shared sightline with another spawn (audit `spawn_pairs_without_cover`
  = 0), spread over the street, the deck and the roof -- the viaduct holds none, and
  section 7 says why -- and never in the open centre of the plaza.
* Weapons by risk: `weapon_glock` + `ammo_bullets` and `weapon_ripgun` at T0;
  `weapon_slugger`, `weapon_novabeam` and armour (`item_kevlar_armor`,
  `item_ebonite_armor`) at T1; `weapon_metamaser` + `ammo_metamaser` at the torii,
  `weapon_kineticore` + `ammo_kineticore` on the viaduct; `weapon_cordite` and
  `ammo_cordite` behind the coolant chute. Health: four `item_health_25` spread one
  per tier-pair, two `item_health_50` at the contested edges.
* Timed rewards: `item_speed_boost` on the skybridge, `item_attack_boost` at the
  torii pad, `item_goldensoul` in the recess under the viaduct, `item_wraithorb` in
  a service alcove at T0. Boosts are 60-second controls and are deliberately off the
  direct line between the two high grounds.
* The coolant chute is one `trigger_hurt` volume: `damage 20`, `wait 0.5` — the
  runtime reads `wait` in seconds (`server/world_actions.zig`), so 0.5 s ticks cost
  40 damage per second of standing in it. Walking through to the ammunition is a
  deliberate trade, and it is survivable from full health with armour.
* No entity in this map carries spawnflag bit 15 or a `coop`/`ctf`/`deathtag`/
  `dedicated` key: `domain/spawn_filter.zig` drops bit-15 entities from deathmatch
  and drops mismatched mode keys entirely.

## 4. Presentation plan (why it should read as 2017, not 1999)

The engine already has the parts the 1999 game could not use: renderergl2
perpendicular-space normal and specular maps, `-deluxe` two-image lightmaps, a
light grid, additive glow stages and a six-sided sky. The plan therefore spends its
detail on those:

* every structural material is a 1024² set — albedo, tangent-space normal derived
  from a height field, derived specular — authored flat-lit and tileable;
* signage is emissive with an additive `_g` glow stage, so neon stays bright inside
  shadowed streets without a light entity, and `q3map_light` entities (60+, small
  radius, tinted) only put light where light *pools*: under awnings, inside the
  vending alley, on the torii pad;
* worldspawn fog (`fog_value`, `fog_start`, `fog_end`, `fog_skyend`, `_color`) for
  rain haze, on the same keys the shipped `e4dm1` uses;
* a generated dusk panorama reprojected into `env/japandm_*` so the skyline is a
  city, not a gradient;
* geometry detail as `dk3.detail` brushes: conduit runs, planters, bollards,
  awning frames, stall roofs — no shadow casting, no vis splitting.

## 5. Build and verification

`python3 -B dkq3/tools/map_build.py --map japanDM --stages author,compile,aas,package,install`
(model with Blender 5.1, compile with the pinned q3map2 in three separate passes,
`bspc` AAS per mode, then one loose `zz-dk3-japandm.pk3` into the development
installation). Files inside the package are lowercase; the playable name keeps its
spelling, and `dk3/navigation/japandm.cfg` is what lets the server load the bot
world at all (`engine/navigation.zig` reads it unconditionally).

Verification records live in `specs/runs/RUN-dk3-independent-port.md`: scene audit,
compile report, AAS counts, a headless 4-bot deathmatch through
`dkq3/tools/runtime_match_probe.py`, and GPU frames from `dkguard --gpu`. Anything
not observed is recorded as unverified rather than assumed.

## 6. What the light rig turned out to be

The plan above said the map would be lit by `q3map_light` entities. That is what
the shipped episode-4 arenas do, and it is what japanDM did first -- 53 capped
lamps -- and it is what made the map look like nothing. Measured from the engine's
own frames (`dkq3/tools/map_view_probe.py`, mean luminance over each 1280x720
capture, the same 14 starts every time):

| pass | what changed | the darkest starts (mean luma) |
| --- | --- | --- |
| A | lamps only, sky faces vertically mirrored | roof_n_w 0.034, w_lane_n 0.080, dock 0.089 |
| B | sky cube fixed, `q3map_skyLight` on **worldspawn** | roof_n_w 0.042 -- nothing happened |
| C | `q3map_skyLight` on the **sky shader**, emissives made into lights | roof_n_w 0.076, garden 0.276, torii 0.272 |
| D | starts re-aimed, texture scale halved | w_lane_n 0.233, dock 0.151, roof_n_w 0.102 |

Two findings, both cheap and both invisible from inside Radiant:

* **`q3map_skyLight` is a shader keyword, not a worldspawn key.** It sits in this
  q3map2's shader-keyword table between `q3map_bounceScale` and
  `q3map_surfacelight` (read out of the binary with `strings`). Written on
  worldspawn it is ignored with no complaint and `-light` reports
  `0 sun/sky lights`; written on `textures/japandm/sky` the same map reports
  `197 sun/sky lights` and the open tiers become visible. Any ambient term this
  map had before that fix came from nowhere.
* **An emissive surface with `nolightmap` still emits.** `q3map_surfacelight` is
  read off the shader and takes its colour from the face's own texture, so the
  neon, the light strips, the ad boards and the holo pool became the light rig
  (527 point lights + 2291 area lights + 197 sky lights, 276 of them culled). The
  light pools now come from the rectangles the player sees glowing, in the same
  hues, which is the difference between a dark map with lamps in it and a
  signage-lit street.

The 53 hand-placed lamps stayed: they are still what puts a pool under an awning
and colour on the torii pad. Skylight was set to 260 with 8 samples because the
open tiers read as dusk at that value and the covered lanes, which cannot see the
sky, stayed lamp-lit -- the occlusion does the zoning that a light entity cannot.

## 7. A spawn must have something to look at

The old rule in section 3 -- "a solid within about 200 units so a spawn is never a
firing position" -- is half a rule. It says nothing about the direction the player
is facing, and measured against the finished geometry **11 of 14 starts had their
eye line land on a solid closer than 90 units**, one of them (`roof_n_w`) on a
tower wall 24 units away. Those frames were not dark because of the light; they
were one flat surface filling the view.

`dkq3/tools/map_spawn_aim.py` measures the three numbers that decide a start's
first impression -- the straight-ahead line, the worst ray inside +-25 degrees,
and the nearest solid behind the shoulders -- and `--solve` proposes the facing
that maximizes the first two while keeping cover in the 40..240 band. Applied to
japanDM: 11 blocked starts down to 1. The one exception was the viaduct, where
**every** facing is blocked by its own 44-unit rails and 40-unit guide beam, so no
angle solves it. What to do about that turned out to be the more interesting
question, and it is how this section ends.

One start needed a *position* rather than an angle, and it took four rules and
three moves to find one, because every rule is satisfied by a different spot.

* `deck_e` (940, 300) looked at a stall: no facing on that stretch reached 120
  units of clear line. It moved north along the same deck to (920, 536).
* (920, 536) then failed the *sightline* gate: it looked down 1400 units of open
  deck, and could be shot along that same line by a player on the west canopy walk
  (floor 384) 1900 units away. **57 vantages.** A start's best vista and its worst
  exposure are often one line seen from two ends, and this was that line.
* (1016, -168) passed both of those and turned out to be **unseatable**: it sits 8
  units from a glass balustrade, and 8 units is legal for a *foot* (the sampling
  model's edge margin) and impossible for a *body* -- the engine puts a 30 x 30 x 56
  box around the origin, and its flank was 7 units inside the glass. The capture
  host spent 20 seconds refusing to put a player down there and then failed, which
  is the whole reason a capture is run at all: geometry agrees with itself and
  disagrees with the engine. That rule is measured in the tool now (`body_box`).
* (-520, 296) was seatable, unexposed and beautifully aimed, and the sightline
  probe reported `deck_w <-> deck_plaza` as a pair with no cover -- 420 units of
  straight ring walkway is one firing line between two spawns. So a proposed site
  may not be able to *see* an existing start either.

What survives all four rules is 33 of the 3643 walk-reachable eye samples: 12 on
the street, 3 on the deck, 18 on the roof. The fourth deck start is therefore
where the deck permits, and the best the deck allows is `deck_sw` at (-472, -760)
facing 205 degrees -- 609 units down the ring's south-west leg, a 345-unit cone,
cover at 38, nearest start 406 units away. The eastern deck is left without a
start on purpose rather than by oversight: every legal spot there looks at ~300
units of stall front, and `e_lane` already owns that district 306 units below
them.

The exception was settled by arithmetic rather than by another nudge. The deck
floor is 704, so a standing eye sits at 726; the rails are 44 tall on both edges
(crown 748) and the guide beam is 40 (crown 744), and the deck is 224 deep -- those
three surfaces bracket the eye line at 40 to 170 units in whatever direction a
player faces, and the widest cone the far lane offers measures 85 degrees against a
gate of 90. The same tool's `--propose-sites` mode, run over the viaduct's own
district (-900..120 x, 560..1150 y), offers 6 sites that survive every rule and
**not one of them is on the deck or its ramp**: all 6 are on the roof at floor 512.
A start there cannot be positioned, only rebuilt, and rails under 20 units above a
192-unit drop are not rails. So the monorail is the reward and not a start -- which
is what its own row in section 2 always said it was for -- and the fourteenth site
went to the best the roof has to offer instead: `roof_e` at (488, 680) facing 170
degrees, 721 units of clear line (the longest on the map), a 120-degree cone and
cover at 45.

Withdrawing that start then reported a defect nobody had been looking for.
`map_sightlines.py` calls an item stranded when no walk-reachable floor sits within
one sampling cell of it, and it immediately reported `weapon_kineticore` stranded:
the viaduct start had been *seeding* that lane. With it gone the flood has to climb
the two stairs and cross the guide beam at its crossings, and it cannot reach the
far lane at all, because the deck's lanes are 84 deep, a player's body is 30 wide,
and two props the exposure planner had placed as monorail dressing -- a 64 x 96
cabinet at x -496..-432 and a 64 x 64 signal box at x -140..-76 -- each span a lane
from the guide beam to the north rail. The power weapon had been standing in a
pocket sealed by its own scenery, reachable only by jumping a 40-unit beam, and the
match telemetry had already seen the consequence and misread it as preference: no
bot in any sampled match had spent one sample above 598 units. Both props came out
of the screen table -- with the start gone there is no long line left there to
break -- and the deck carries two 16-unit cable ducts in the same places instead,
under the engine's 18-unit step-up, so a player walks over them and both lanes run
open end to end.

Four rules, all four of them gates now: `map_spawn_aim.py` exits non-zero when a
start has nothing to look at **or cannot hold a player body**, and
`map_sightlines.py` exits non-zero when a start can be shot from 640 units away,
when two starts see each other, or when an item is out of reach. The measurements
of the shipped map are `zig-out/map-dev/japanDM/spawn-aim.json` and
`sightlines-48.json`: 14 starts, 14 aimed, 0 wedged, 0 exposed, 0 pairs and 0
stranded items over 3650 walk-reachable eye samples of 8285 and 58400 rays.
Withdrawing the viaduct start cost nothing in openness either -- 8409 clear lines
at 640 units against 8360 before, 1454 at 1536 against 1433 -- because the two
props that were blocking the lane had been put there to shield a start that no
longer exists.

## 8. Why the textures were two times too large

One generated 1024 image spread over `repeat` 256 world units is 4 texels per
unit. The engine captures at 1280 px and a 90-degree view at 45 units is 90 units
wide, so the eye resolves about 14 pixels per unit: every close surface was being
displayed nearly four times larger than the art in it, which is most of why a
generated texture that looks sharp in a viewer looked like stucco in the lane.
Asphalt, plaza stone, concrete panel, roof gravel and lacquer went from 256/192 to
128 (8 texels per unit).

Three of those sets were also regenerated (asphalt, concrete_panel, roof_gravel)
with a softer height field (grit 0.9/0.55/1.0 down to 0.45/0.28/0.55, normal gain
1.5/2.2/2.2 down to 1.0/1.3/1.4) and prompts that put the variation in stains and
streaks instead of speckle. Roof ballast clearly improved -- it now reads as stones
set in a membrane rather than as television static. The model's preference for a
bright mid-grey albedo did not go away, and it is recorded as a limitation rather
than as a fix: see `PROVENANCE.md`.

## 9. Played, not just compiled

Deathmatches run against the installed archive, with no placements and no grants
(the 93-second 4-bot survey quoted at the end is the pre-fix archive). The 4-bot run
passes the moment its evidence set is
complete -- all four moved, three picked an item up, one fired, one was hit, one
died and respawned -- and that happens after 30 seconds of match time, which makes
it an acceptance probe and not a survey. `--observe` was added to the probe for
exactly that reason: it keeps sampling after every requirement is met. With it, 8
bots were watched for 420 seconds of match time: 1429 snapshots carrying 11,192
bot positions.

Every number below is recomputed from those two `samples.json` files, and the first
revision of this section got several of them wrong -- it reported a tier split of
47.5 / 31.2 / 16.3 / 5.0 %, "all eight fired, all eight wounded, all eight
respawned" and a visited box of x -1008..1010. None of that reproduces from the
files, so it has been replaced by what is in them. One convention is needed to read
positions: the sampled `pos[2]` is the standing floor plus 24, which the same file
checks three ways -- bodies at rest report 24 over the `asphalt` whose top is 0, 216
over a tower crown whose top is 192 and 536 over the roof slab whose top is 512.

Split by the floor a bot stands on, the 420-second survey is **T1 market deck 54.0 %
(6041 samples), T0 street 28.9 % (3237), T2 roof 17.0 % (1899), viaduct stair treads
0.1 % (7 samples, bots 1 and 6) and the monorail deck itself 0.1 % (8 samples, all of
them bot 6)**. Weighted by travelled distance rather than by time standing still it
is 47.9 % T1, 41.3 % T0, 9.5 % T2, 1.1 % links and 0.2 % viaduct. Those deck samples
are one contiguous visit: bot 6 climbed the east stair between t=141.2 s and
t=148.2 s and walked x 563..739, y 616..811 at feet 704 -- the first time any bot had
stood on the viaduct in a sampled match. On the sealed geometry the highest reading
was 598 and every sample after it was on the stair below. The visited box is
x -1137..1137, y -1009..1009.

Combat was thinner than the earlier revision claimed, and the probe's own evidence
set says so: 6 of 8 bots moved and picked an item up, 5 fired, 5 were wounded, 4
respawned, and the 17 deaths are concentrated in the four bots that kept playing
(bot 7 finished on score 10 with 2 deaths, bot 6 on 3 with 5). The other three are a
finding in themselves -- bots 0, 4 and 5 stopped travelling and stayed put for the
rest of the survey (4,394 / 269 / 0 units of path over 420 s) while still alive and
still taking damage, two parked on the 192-unit tower crowns at x +/-1137 and one on
the roof at (-600, 1000). Nothing in the map prevents them leaving: this is bot
navigation behaviour, it is outside what this task may change, and it is why the
split above is a survey of where bots end up rather than a statement of where they
choose to fight.

The runs are not duration-matched -- 30 and 93 seconds against 420 -- so the
before/after on the viaduct is not proof by itself. What is not in doubt is the
cause: on the sealed geometry the deck's far lane was not walk-reachable in the
tool's model at all, and on the shipped geometry it is (section 7). An earlier
version of this section read that same 0 % as a bot preference and said so out
loud; it was reading a blocked route as a choice. What is genuinely left open is
not routing but taste -- whether a human climbs for the kineticore is not something
bots can answer, and no game code is in scope to make them want to.

## 10. Texture repair pass: what the seam metric could not see

The owner's complaint was a screenshot: textures that read as wrong, not missing.
Eighteen materials were rebuilt and three separate causes found. Only the first
one the existing metric could see.

**Seam discontinuity (found, already fixed).** `Mask.offsets` returned a flat list
of x-shifts while its own test read `min(box[0], box[1])` -- both axes in the
question, one axis in the answer. Every stamp clipped by a horizontal border was
never redrawn on the far side, so `crate` and `grate` failed their vertical seam
several times harder than their horizontal one. It returns `(dx, dy)` pairs now.
After that plus a wrap-distance band on `crate`, integer row pitch on `grate`, and
a periodic rewrite of `holo_pool` (it had been radial about the tile centre, which
is a starburst on a wrapping tile by construction), the worst remaining case is
`tower_front` at 1.58 and everything else is at or below about 1.03.

**Contrast, and a metric that was misread as a defect.** Every graded material used
to carry a target `std` as well as a target mean, which re-scaled the tile's spread
onto that number after the fact. Measured against the natural spread of the drawn
structure, `roof_gravel` looked crushed 4.3x and `plaza_stone` amplified 2.8x, and
the obvious conclusion was that the rescale was the bug. It is not, and the
arithmetic says so: `grade(albedo, mean)` is exactly a linear scale by
`mean / natural_mean`, so the spread follows it -- predicted and actual standard
deviation agree to 1e-7. A 0-255 material whose mean must sit at 36 cannot also
carry a spread of 69; that is darkening working correctly, not contrast being
destroyed. The `std` term was removed because it was an *arbitrary* second target
that overrode the structure in both directions, not because the ratio it produced
was pathological. Means are unchanged by this pass -- every shipped tile measures
its grade target to three decimals -- so baked light energy is untouched and the
light rig did not need re-tuning.

**What was actually wrong: grain that carried the plate's shape.** A diffusion
plate divided by its own mean still contains that plate's slow luminance swings.
Multiplying one in paints a bright column at a join and a soft bloom mid tile. The
seam metric is structurally incapable of reporting this: a slow bright band is
*continuous* across the wrap, so it scores 0.000 while drawing a visible grid line
once per repeat. That, not a discontinuity, is most of what the screenshot showed.
`borrow_detail` now divides by a wrap-blurred copy of the plate instead of by its
mean -- a high-pass, periodic by construction. Measured on `plaza_stone`: low
frequency energy 0.0183 to 0.0078, grain retained 0.0547 to 0.0467. Bloom down
58 %, structure down 15 %.

`pebbles` was rebuilt for the same reason one layer down. Ballast is drawn as
irregular 5-7 sided polygons each carrying its own grey and its own facet tilt,
with height from a barely-blurred coverage instead of a Gaussian crown; the crown
was the specific thing guaranteeing the rounded foam read no matter how good the
colour pass was. Pieces went from 420 stones of up to 24 texels to 1500 of up to
14, because at the old settings the tar between them opened into black cells the
size of a hand.

**Known limitation, not claimed fixed.** The plates are made tileable by
mirror-symmetric folding, which removes discontinuity completely and leaves
something else behind: mirror symmetry, which the eye finds on its own. It is
visible in a 2x2 tile view as a symmetric vignette. Tightening the high-pass band
from 0.045 to 0.010 of the tile changes the low/high ratio from 6.02 to 5.80 and
does not remove it, because it is the plate's *content* mirrored, not its exposure.
A better source of periodic microstructure would be a generative one; it is not
done here.

## 11. Where a material's scale is decided, and how it got lost

One generated image covers `repeat` world units, so `repeat` is a design decision
about the real-world size of a pattern, and `map_author` turns it into a UV scale
by dividing by the texel width. The number lived in `textures.py`, the value that
reached the engine lived in `materials.py`, and nothing reconciled them. They had
diverged on twelve of eighteen materials, in *both* directions:

* `neon_a` shipped `repeat=256` against the face survey's 64. The median `neon_a`
  face is 56 units across, so every sign displayed a 22 % crop of a kanji
  composition. That is the pink confetti the arena read as, and it was a scale bug
  wearing a taste complaint.
* `asphalt`, `plaza_stone`, `concrete_panel`, `roof_gravel` and `lacquer_red` were
  the opposite case: section 8's measured density fix had updated `materials.py`
  to 128 and left `textures.py` holding the superseded 256/192. Treating
  `textures.py` as authoritative without reading section 8 would have quietly
  doubled those surfaces again and put the stucco back.

`materials.py` now derives `texwidth` and `repeat` from `CRAFT` at import and
`CRAFT` carries the measured 128, so there is one table and one place to argue.
`_SIZES` additionally declared `metal_deck`, `metal_column` and `holo_pool` at 512
texels when the stored images are 1024, which made `q3map_textureSize` lie to the
compiler about three quarters of their pixels; that is corrected by the same
derivation. The exported `.map` was read back to confirm it took: `neon_a` carries
0.1250 where it carried 0.5, and the three 1024 materials declare 1024.
