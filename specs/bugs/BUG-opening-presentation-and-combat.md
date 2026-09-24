# Opening presentation and combat repair

These are historical reports and the evidence available in each repair batch.
Later renderer, actor and weapon repairs supersede individual implementation notes
below, including the thunderskeet cloud and earlier Ion presentation. Consult the
[current game status](../../docs/status.md), [runtime audit](../../docs/runtime-gap-audit.md)
and run log for the latest state. The complete opening comparison remains open.

The owner reported twelve visible failures during play. This repair batch takes
priority over further campaign route verification. Earlier progression results
remain evidence of those inputs only; they do not establish presentation parity.

| Report | Inspection / repair | Verification |
|---|---|---|
| Original menu and HUD absent | Supplied art and measured 1.3 layout: left skill meters, six right weapon slots, difficulty figures, button/slider glyphs and numeric columns | Main-menu figure/button and three HUD value regions pass their recorded comparisons; native menu save/load, mouse volume drag and 1280×720 layout exercised. Missing options and remaining panels stay open |
| Ion bolts too small | Add supplied flare, threefold mesh scale and green light; vertex-colored SP2 polygons; correct animated impact sprite | Visible flare and rounded impact inspected in ion combat; size comparison with 1.3 remains open |
| Cinematic guards face incorrectly | Publish server facing in native angular trajectories | Worker yaw 94.9/105.35 reaches snapshots and rendered opening; matching 1.3 shot comparison pending |
| Cinematic Hiro floats | Restore actor gravity during camera control | Get-up actor settles from authored Z573.9 to Z552.125; rendered foot contact inspected; reference shot comparison pending |
| Slideshow/flickering animation | Explicit actor timing and interpolation; 50ms actor tick. First-person sequences finish and hold their last pose, with occasional finite idle animations; Disruptor interval covers its 600ms punch | Renderer trace records 218 Disruptor poses, all twelve attack frames and 67 fractional blends, then a held final pose. Actor/cinematic motion comparison remains open |
| Damage turns screen gray | Replace near-camera world sprite with bounded red screen tint | Damaged bridge frame retains visible world with mild red tint |
| Thunderskeet engages at eye level | Continuous overhead flight passes before generic ground pursuit, falling toxic projectiles and lingering poison cloud | Boss measured 214 then 297 units above player; cloud spawn/restore exercised; full encounter comparison pending |
| Bridge red firing lights always visible | Toggle-only func_wall incorrectly started visible. Honor trigger/toggle/start-on flags and nonsolid visibility independently | e1m1b big_beams entity205/model*37 hidden → on → off through authored relay; uses0/1/2 and firing/off frames retained |
| Corpses float | Set corpse contact from supplied final-frame model bounds and retain gravity | Crox496 dies to four ion hits, reaches frame131 on ground; other death poses pending |
| Campaign starts with wrong weapon | Remove stock client selection; select supplied w_tglove for the Disruptor | Fresh start selects weapon1/inventory2; corrected glove and punch inspected beside 1.3 captures. Exact pose/lighting comparison remains open |
| Enemy model scale wrong | Parse all three supplied axes and honor map scale; compare affected actors visually | Unrun |
| Enemies never break into pieces | Mechanical actors fragment on death; organic overkill and corpse damage fragment through native debris physics | Mosquito destroyed with visible metal fragments; crox corpse takes three further 30-damage hits and emits flesh fragments |

Code is independently written using ioquake3 services and supplied model/table
metadata. Optional private reference inspection establishes behavior and artwork
placement; no reference implementation, headers or executable enters the build.
Build the integrated engine/modules once this connected batch is in place, then
capture the opening menu, cinematic, combat and bridge encounter and repair their
observed failures. Broad suites remain deferred until the enclosing acceptance pass.

Private evidence: `/tmp/dk3-presentation-repair/`,
`/tmp/dk3-presentation-data/dk3/screenshots/` and named repair saves. Bridge
firing used diagnostic placement before traversing its real trigger, not an
authored campaign replay. Existing revision-2 combat saves retain their original
world state, including an already out-of-bounds frog; this is not a fresh-map
acceptance result.

The owner subsequently required direct comparison with 1.3. Fresh private
`dk3-reference-presentation`, `dk3-reference-singleplayer` and
`dk3-reference-disruptor` captures use the existing reference sandbox at 640x480.
Original installation digests remained unchanged. Existing menus-panels captures
provide the other panel layouts. These runs establish reference appearance; they
do not certify the native repair. Original-art presence and isolated function
tests are insufficient to close visual parity.

Retained comparison evidence is under `zig-out/reports/presentation-reference-01/`.
The installed `dk3` launcher uses the independent modules and latest checked asset
generation. The integrated build passed; subsequent game-module builds include
the reference-driven layout and animation corrections. No broad lint/test sweep ran.

The 640×480 main-menu comparison counts channel differences above 32. Difficulty
figures differ at 0.0017 of pixels (bound 0.02), difficulty buttons at 0.0002
(bound 0.04). The three HUD value regions pass the existing HUD scenario bounds;
their ratios are 0.1495 armor, 0.1867 health and 0.2136 ammunition. These limited
regions do not certify the full HUD, menu system or world rendering.

The reference camera probe measures FOV 90×73.7398, view origin
(1608, -2592, 575.475), and view pitch/yaw 5.4272/107.7594. Its `getpos` reports
entity pitch 1.81 instead. Native standing view height is now 22 rather than the
upstream 26; the remaining reference eye offset includes its view motion. Native
diagnostic placement used a debugger and is not campaign traversal evidence.

Outstanding presentation work includes No Sidekicks/Bonus Gems options, voice
and chatter controls, full video/options panels, save previews/metadata/deletion,
inventory thumbnails and companion flaps, world lighting, matched cinematic shots,
actor scale and full boss/bridge playback. Do not close V7 on the partial matches.

## Follow-up gameplay and marsh repair

The owner identified the marsh as the location for missing effects. The follow-up
batch compares the following behavior with optional original-source reference.

| Report | Repair / finding | Current evidence |
|---|---|---|
| Monsters return on e1m1a/e1m1b revisits | Archive the complete departing world; restore it at the authored arrival. Full saves embed visited worlds in revision 4 | Mosquito stable ID273 is absent after two ion hits, the forward exit, the return exit, and loading the intervening e1m1b save before returning again. Protopod-created mosquitoes have distinct new IDs |
| Ion cadence too fast | Eight supplied firing frames at 50 ms plus 100 ms recovery: 500 ms between shots | Consecutive monster hits at 174800 and 175300 ms; two hit samples reach the mixer |
| Wrong place after intro | Use the original first authored spawn fallback, rather than the return spawn's flag. Attached truck decoration no longer accumulates gravity while following its mover | Full 115-shot intro, accelerated simulation, reaches e1m1a and completes its entry cinematic; Hiro is at (1608,-2592,552.125), holding weapon1 |
| Existing HD textures not default | Installer admits the local image-only HD package, includes it in the installation identity and launches with r_picmip0 | Installed overlay contains 3564 images; final private client uses the same package and full-resolution setting |
| Menu plates slow/silent | Hover pose1 over 175 ms; selected pose15 over 350 ms; supplied hover, rotation and open/close sounds | Selected Sound plate inspected; engine mixer trace records hover and both rotation samples |
| Mosquitoes sometimes ignore player | Acquire enemies before deciding to continue a patrol route | A nearby authored mosquito acquires Hiro and repeatedly attacks; health100 falls to86 in the first two measured attacks |
| No hit/player pain sounds | Count native actors as hit targets; bind supplied pain1–4 instead of grunt names | Hit counter reaches2; flesh-hit samples and all four Hiro pain samples reach the mixer |
| Missing monster attack sounds | Emit independent sound events so adjacent animation events cannot overwrite one another | Supplied mosquito attack, flight and pain samples reach the mixer during actual combat |
| Missing marsh effects | Cambot sweeping cone, tagged flare/local light; supplied atlas particles; authored moving clouds and sky flashes | Cone and weather inspected. Sky source inspection found a renderer-generated effect absent from entity census; final sky verification recorded in the run log |
| Bots remain dead | Native bots already send ordinary respawn input | Repeated death/respawn on e1dm1 and e2dm1; health100 and PM_NORMAL after the deadline. The reported failure remains unreproduced; no speculative bot patch |
| Original loading screens/animation missing | Shared original tiles, 32-pixel row overlap, original bar/blocks/tick sound; loading name has configstring28 | Native MARSH plaque and half-filled bar inspected; actual resource registration dispatches progression ticks. Fixed a collision with upstream CS_ITEMS27 |

Private evidence is retained in `zig-out/reports/gameplay-reference-02/`. Combat
and exit probes use debugger placement followed by normal weapons, damage and
authored exit triggers; they are not a continuous campaign traversal. Bot command
probes enter through the engine client-command service; the first C4 kill was
natural combat. Audio evidence is mixer dispatch under the dummy SDL driver,
not a recording of the user's speakers. Later monsters, other map effects and
complete visual parity remain open.


## Subsystem audit and shared repairs, sequences186–189

The next owner report exposed gaps behind the earlier isolated passes. The active
[runtime gap audit](../../docs/runtime-gap-audit.md) is the discovery/repair matrix.
It distinguishes sound-only actor cues from model clips, finite animation states from
loops, successful pickups from rejected touches, weapon contacts from score beeps,
and complete checkpoint restoration from multiplayer respawn.

This batch repairs pod perception/emergence, rockgat lift states, frog action/sight
sounds, pickup audio, surface contact marks/audio, Ion ricochets, effect blending/types,
event admission and single-player death recovery. Matched marsh camera comparison
also found a format-level rendering defect: particle atlas cells overlap and must
use their triangular footprint. Full quads sampled a neighboring effect inside the
smoke rectangle. Final captures no longer show the reported yellow bloom.

The bridge's two cambots have authored deathtarget=doitall, so killing them can
intentionally start destruction before crossing. The ordinary touch route and death
checkpoint recovery now have separate evidence. The cambot-death route still needs
its own complete replay; it was not removed or declared a defect from the screenshot.

Verification and exact limitations are recorded in the audit and run entries186–189.
The installed dk3 uses protocol1344 and save schema5; start a fresh campaign for this
asset/schema update. Earlier installations and saves remain available separately.
The port is still incomplete; these shared repairs do not certify later episodes,
all actor families, every weapon/material pair, or complete cinematic/effect parity.
