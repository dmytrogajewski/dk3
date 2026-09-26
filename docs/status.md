# Game completion state

Feature branch `rewrite/native-zig-runtime` contains the incomplete native runtime;
`main` is restored to the working pre-rewrite tree. Sequence 225 replaces the temporary
source root with `src/runtime` and enforces domain/engine dependency boundaries.
Glock/Disruptor trace damage and Ion projectiles are connected. Four civilian classes
have authored metadata, animation, movement, death and witness panic; the e1m2a
worker scenario has passed with diagnostic positioning/equipment. Sequence 226 connects Mishima guard perception, retaliation, pistol/reload cycles
and player damage, with an authored guard scenario passing. Most weapon combat,
remaining actors/navigation, scripts/cinematics, save restore/travel, full presentation
and multiplayer integration remain open. See [runtime progress](runtime-zig.md).

The preserved installed game and saves are untouched. The results below describe
historical runtime versions and do not establish acceptance of the new runtime.

Sequence 203 is implementing the accepted [Zig multiplayer/Internet-room scope](multiplayer-zig.md).
The one-host IP deployment passes explicit-CA HTTPS verification and focused real
Internet scenarios: three encrypted clients, readiness, browser ping, reconnect,
vote bans, operator removal, coordinator outage continuity and worker restart.
SQLite backup/isolated restore and loss/reordering/tampering probes also passed.
The Zig message codec passed differential checks and the Internet lifecycle replay.
Focused captures demonstrate three character/color combinations and distinct music
through e1dm1, e2dm1, e3dm1 and e4dm1 transitions. The full appearance, music and
equipped-weapon matrix remains open. Sequence 209 adds configurable permanent
server-owned rooms: 16 total players by default, replaceable bots and ten-minute
map rotation. The unchanged sequence-208 RPM discovered and joined the live room
through its menu; bot replacement/refill and a full live rotation cycle passed.
See [hosting configuration](online-operations.md#permanent-rooms).
The complete migration and all-map/mode acceptance remain open. The broader
campaign/weapon snapshot below remains sequence 200.

Sequence 211 repairs called-lift dwell, mouse save selection, duplicate difficulty
options, Glock muzzle blending, configurable weapon shine, ion terminal audio,
actor timing and civilian witness alerts. Focused lift/UI/effect scenarios and
native timing/alert regressions pass; all-map and original-renderer parity remain
open. See the sequence-211 run log for evidence and limits.

Sequence 212 corrects the lift repair after reviewing Gold: waits belong to the
departure corner and apply after arrival. The owner's e1m3a lift therefore uses its
authored ten-second upper dwell, superseding sequence 211's three-second fallback.

Sequence 213 updates the normal `dk3` launcher's local installation to these fixes,
retaining its existing saves/settings and appearance overlay. Live multiplayer
servers still need matching gameplay rules.

Sequence 214 restores Gold crouch clearance and loads menu saves directly into
their saved map. The owner’s e1m3a triangular passage, mouse-only loading, corrupt
save rejection, previous-save recovery and visited-world preservation pass. Normal
`dk3` uses the updated build; its saves/settings remain unchanged.

Sequence 215 repairs the first Superfly encounter against Gold: script-only
companion spawning, authored spawn position, train attachment placement,
cinematic trigger isolation and unique-ID script uses. Existing save2, the first
conversation/rack crossing, keycard rescue and companion save/reload pass.
Normal `dk3` uses the repaired build; saves/settings remain unchanged.

Sequence 216 clears the stranded e1m3b laser damage field after all three beams
are removed. The owner’s existing quicksave, crossings from both ends at beam
height, fresh weapon-driven shutdown and save/reload pass. Normal `dk3` is updated
and existing saves/settings are preserved.

Sequence 217 begins the [native Zig replacement](runtime-zig.md): isolated native
entrypoints, ECS/job/scheduler infrastructure, map metadata, collision probes,
shared inventory rules and a save-record codec. **The replacement is not playable;
full migration and cutover remain open.** See the run log for foundation checks.
The normal launcher and owner saves remain on the existing runtime.

Sequence 218 continues native movement/prediction, shared input policies and tuning
for all 28 weapons, build-identity checks, binary movers and target routing. Native
client connection and focused movement/weapon/door checks have passed. Transactional
rider pushing and authored target progression remain unverified; native combat,
actors, persistence, presentation and UI are still unfinished. **Full migration and
cutover remain open.** The ordinary launcher remains on the existing runtime.

Sequence 219 adds train path/dwell transitions and attachment assemblies. The native
e1m3a lift carries the rider, holds its ten-second upper dwell and returns to lower
rest in the isolated replay. Compound obstruction, rotating riders and authored
progression remain unverified. Native gameplay migration is still in progress.

Updated 2026-09-26, through **runtime-zig, sequence 219 (active)**.

**dk3 is a playable development build, not a completed Daikatana port.** Independent
native systems exist across the game, but implementation and successful focused
scenarios do not establish a complete campaign. No full episode has passed an
end-to-end replay. There is no supported overall completion percentage.

This is the current summary. The [roadmap](rewrite-roadmap.md) defines the complete
scope; the [run log](../specs/runs/RUN-dk3-independent-port.md) records individual
inputs, failures, repairs and acceptance limits. An unverified path may already have
code; remaining work includes both implementation repairs and gameplay verification.

| Area | Implemented and demonstrated | Still required for completion |
|---|---|---|
| Engine and native build | Bundled ioquake3/BSPC, Linux client/server, both renderers, independent modules and Zig build. Earlier isolated native build/start passed without private reference files or existing caches; the latest integrated ReleaseSafe build passes. | Required toolchain qualification and final independence/provenance review. Native Zig weapons are not a qualified QVM target. |
| Assets and installation | Private 1.3 profile converted/installed: 84 maps and 97 difficulty/mode navigation variants. Runtime installation and local HD overlay exercised. | Retail-profile verification, complete conversion-loss review and a fresh full clone/build/assets/play acceptance run. Converted map counts do not measure playable campaign completion. |
| Campaign | Opening cinematic and bridge encounter exercised. Authored exits through e1m1b/e1m1c/e1m2a reached e1m2b; later recorded play there traversed pipes, combat and the submerged paddle/drain route. | Fresh continuous opening replay and the remainder of Episode 1; complete Episodes 2–4, bosses, puzzles, cinematics, timestream transitions and endings. The e1m2b evidence includes resumed development saves and is not a start-to-finish campaign run. |
| Weapons, combat and progression | All 28 selectable weapons execute in native Zig. Gold comparison corrections cover timing, ammunition, damage, projectiles and effects. All 28 authoritative firing paths pass; representative damage, liquid, network and save scenarios pass. Earlier pickup, level/attribute and sword progression checks are recorded. | Every weapon interaction and progression branch in campaign/multiplayer, full animation/effect/audio comparison and final balance acceptance. Flashlight is an intentional dk3 extension. |
| Actors, companions and navigation | Actor perception, attacks, abilities, gravity, animation events, routing and companion commands exist. Focused pod, rockgat, mosquito, frog, cambot, thunderskeet and companion-combat scenarios pass; navigation variants load. | All actor families and later-episode encounters; companion commands, blocked-route recovery, doorway yielding, pickups and campaign availability/transitions across the full game. |
| Saves and transitions | Named, validated saves, atomic replacement, checkpoint death recovery and visited-world persistence exist. Focused corruption/recovery, air deadline, mover/cinematic and weapon restores pass. Sequence 200 verifies C4, Hammer, Nightmare and Metamaser, including delayed launch and rebased lock deadlines. | All mid-encounter/controller phases and cross-episode state, plus broader archived-development-save compatibility. Omitting the two new optional weapon fields was tested with a fixture; this is not verification of every older save. Original Daikatana save migration is outside scope. |
| Multiplayer | DM, CTF, deathtag, bots and host/join flows exist. Recorded joins, deaths/respawns/reconnects and contested objectives pass. Latest delayed-network checks verify Shotcycler, Sidewinder, Trident, Ripgun and Kineticore. | Complete mode/map, team, bot, scoring, disconnect and protocol-error matrix. Focused successful matches do not certify all multiplayer behavior. Co-op is outside scope. |
| Presentation and UI | Supplied artwork, menus/HUD, loading, cinematic/audio/effect systems and multiple renderer repairs exist. Selected rendered comparisons, menu flows and mixer dispatch pass. | Remaining options/panels, actor scale and matched cinematic shots, lightstyles, all weapon trails/fragments/view kick and full sound mix. OpenGL2 yellow saturation near the marsh pool remains a recorded defect. Physical display/speaker behavior is not established by headless checks. |
| Release | Reviewed source and build/install documentation are published as development snapshots. Sequence 208 produced and verified a local asset-inclusive RPM with default Internet endpoint and CA. Sequence-209 broad checks passed: 44 Python tests and 138 Zig tests, after repairing a stale test-fixture declaration. | Complete V1–V12 acceptance, final source/license/publication review and verified new-game-to-ending installation path. RPM installation on the second physical machine is not verified here. A successful push is not a completed-game release. |

## Latest verified weapon pass

[Sequence 200](../specs/runs/RUN-dk3-independent-port.md#weapons-gold-review--sequence-200)
records the per-weapon corrections and exact coverage. Verification found and repaired
a missing Shotcycler decal shader, a nonexistent Ripgun spin-up pose, mover/controller
reference confusion in saves, Metamaser table-column selection and lock deadlines
that did not follow the restored simulation clock.

The C contract fixtures now explicitly enable assertions even in optimized builds.
The underwater runner verifies saved server water level, rather than inferring it
from a screenshot. These checks supersede the corresponding weaker claims in
sequence 199. The broad suite ran once after the affected scenario repairs; `make
lint`, `make test` and `zig build test` invoke the same suite.

Gold's Bolter water sound, `shared/bloop4.wav`, is absent from the supplied local
profile. Its conditional binding remains unavailable without that asset. An
intermittent empty-sound startup warning also remains recorded; the successful
weapon runs do not establish its cause.

Private captures, saves, logs and converted assets remain local under
`zig-out/reports/weapons-gold-200`; the public run log summarizes their results.
Latest verified local runtime generation:
`6a4d5a4263029b67c6f5618cd107e7cfef5923d89d35daf21ab845a6e3cb36b4`.

## Remaining acceptance order

1. Complete the connected actor, companion, script and presentation repairs and
   their scenario matrices, including the unresolved opening comparisons.
2. Replay the opening continuously, resume authored Episode 1 progression, then
   traverse Episodes 2–4 through their endings. Retain mid-action save/transition
   coverage as each subsystem is exercised.
3. Complete multiplayer and required-improvement coverage, then the retail/fresh
   installation, independence, toolchain and release checks in V1–V12.

Use the [implementation-first workflow](development-workflow.md): implement
connected changes, exercise their scenarios, repair observed failures, then run
the applicable broad checks once. Keep passing evidence until relevant inputs change.
