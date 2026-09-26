# Native port acceptance

Current work: `rewrite/native-zig-runtime`. Main, the installed playable runtime,
user saves and the online service are preserved. Historical results from the removed
runtime are not evidence for this runtime. The complete four-episode campaign,
multiplayer modes/bots, persistence, UI and release requirements remain in scope.

## Current milestones

| Outcome | Implementation and contracts | Native engine / connected gameplay | Evidence and limits |
|---|---|---|---|
| Finish weapon controllers | Audit completed: 28 class-owned policies are connected, including Zeus, Wyndrax, Nightmare and Metamaser. Counts describe dispatch coverage only. | Several focused interactions exercised; no complete weapon acceptance. | Journal sequences 232–243. Diagnostic inventory, placement and sometimes health changes invalidate these as continuous campaign evidence. |
| Fresh opening campaign | Intro/cinematic execution, opening hostile classes and authored encounter scripts require implementation/audit. | **Unrun:** New Game → full intro → e1m1a → e1m1b bridge → e1m1c → authored e1m2a exit. No verified consolidated build yet. | Must use ordinary starting inventory, normal difficulty, one build and asset manifest. Include combat, pickups, controls, death/reload, save/load and visited worlds. |
| Native save and visited-world restoration | Typed native snapshots and visited archives implemented; focused contracts execute. | Sequence 241 travel diagnostic passes a limited e1m3b/e1m3a round trip. Connected campaign persistence unrun. | `zig-out/reports/runtime-zig-241/travel-regression/`; diagnostic placements, no companion/cinematic qualification. |
| Remaining campaign and multiplayer | Most actors, companion/cinematic progression and native multiplayer behaviors remain. | Unrun in this runtime. | Opening milestone is an integration gate, not completion of this scope. |

## Recorded build identities

Sequence 243 controller diagnostics use identity
`821eb42549316cb8e2dfb45134911c56ed76b372ecaa118127f815eb4b21302f`,
recorded in `zig-out/reports/runtime-zig-243/controllers-integrated/identity.json`.
This includes the executable, three native modules, shader and every asset package.
Wyndrax active/fading damage and saved target links, Nightmare casting/reaping saves
and two marked worker kills, and Metamaser arming/tracking/destruction saves and
expiry pass in that running build. Equipment, position and health are diagnostic.
Screenshots show the reaper and cube; full effects/audio comparison remains open.
The initial Nightmare visibility failure and erroneous six-charge fixture remain
in `controllers-first/` and `controllers-sight/`; neither is acceptance.


Sequence 242 isolated Zeus evidence: `zig-out/reports/runtime-zig-242/identity.json`
records module/package SHA-256 values. Modules: qagame
`754a2da49592d5edc2b8c01bb96c3028640d51d38e976d0fd0c1c55d8c8cdd25`,
cgame `ba42dbea6e7b591efc17a98b859b3aa38061042b0e7330a3b6f3b3055aa2b493`,
ui `d04f6b23ffcd0b76fc33d74b4afbd6ed4a2e670410e9fef40ef21593778ab521`.
Asset-package manifest digest:
`769468848b5a2e75bb40afcb6e9116c24bbd55650f88c3000ddcb6c5552935bc`.
Source base `e3bf72a` plus the recorded Zeus changes. ReleaseSafe keeps assertions
enabled. `build/runtime.zig` explicitly executes domain/ECS and separately imported
actor, weapon, inventory and item roots. Sequence 243 aggregate executes 224 Zig and 47 Python checks successfully. The
formatting gate initially failed, was corrected and separately replayed successfully.
Three native modules and 86 focused checks compile/pass. These counts do not
measure port completeness.

Zeus: pending strike and active-chain saves, two worker kills, ammo charge, closure
and free single-player miss exercised in `runtime-zig-242/zeus-first/`. Capture shows
blue lightning/flare; full sound/presentation comparison remains open. Twenty-target,
water and multiplayer interactions are not certified by this narrow scenario.

## Evidence rules and revalidation

Track independently: implemented; contract-tested; running native engine; connected
authored gameplay; reference behavior/presentation compared. Reference source review
alone is not a running comparison. Failed setup invalidates a scenario. Observe
connection, input processing, weapon readiness, actual attacks/contact, water level,
controller existence, save completion and restoration; commands issued are not proof.

Keep focused diagnostics separate from ordinary-input progression. The campaign
driver must use bounded event-based synchronization. Change an ineffective driving
strategy or use legitimate resupply/checkpoints without modifying game rules.

Shared pitched-muzzle Venom/status coverage replays successfully in sequence 243
`status-events/`. The prior driver missed flight because the restored projectile
hit before its second observation; the corrected check validates a pending saved
release and actual flight or confirmed contact. Personal-action cleanup and Ballista motion ownership need
the applicable active-action travel/actor regressions; sequence 241's narrow travel
replay does not close those permutations. Sunflare close-range bright sprite edges
remain an observed presentation defect. Trident merge setup failed and is open.
Earlier retired-runtime campaign rows in the roadmap are historical only.

After any change affecting an earlier route segment, record affected coverage,
replay that regression, then rerun the complete milestone on the consolidated build.
Run applicable aggregate checks at integration checkpoints, without duplicate suites.
