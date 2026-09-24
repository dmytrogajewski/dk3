# Game completion state

Updated 2026-09-25, through **weapons-gold-review, sequence 200**.

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
| Release | Reviewed source and build/install documentation are published as development snapshots. Latest broad suite passes: 43 Python tests plus Zig checks. | Complete V1–V12 acceptance, final source/license/publication review and verified new-game-to-ending installation path. A successful push is not a completed-game release. |

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
