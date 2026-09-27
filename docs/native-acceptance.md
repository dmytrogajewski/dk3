# Native port acceptance

Current work: `rewrite/native-zig-runtime`. Main, the installed playable runtime,
user saves and the online service are preserved. Historical results from the removed
runtime are not evidence for this runtime. The complete four-episode campaign,
multiplayer modes/bots, persistence, UI and release requirements remain in scope.

## Current milestones

| Outcome | Implementation and contracts | Native engine / connected gameplay | Evidence and limits |
|---|---|---|---|
| Finish weapon controllers | Audit completed: 28 class-owned policies are connected, including Zeus, Wyndrax, Nightmare and Metamaser. Counts describe dispatch coverage only. | Several focused interactions exercised; no complete weapon acceptance. | Journal sequences 232–243. Diagnostic inventory, placement and sometimes health changes invalidate these as continuous campaign evidence. |
| Fresh opening campaign | Intro, pod/skeet/frog/Thunderskeet policies, opening action programs and health trees implemented. Cambot/Crox/Rockgat remain blockers. | **Unrun as a complete route:** New Game → full intro → e1m1a → e1m1b bridge → e1m1c → authored e1m2a exit. No verified consolidated build yet. | Must use ordinary starting inventory, normal difficulty, one build and asset manifest. Include combat, pickups, controls, death/reload, save/load and visited worlds. |
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

## Current opening integration batch (244–245)

Fresh intro runs found two authored cue cases, corrected against private reference
contracts: class fallback for queued actor IDs and ignoring absent animation cues.
A development replay from a legitimate earlier-build shot-20 checkpoint passed the
remaining intro and authored exit, then failed before e1m1a arrival because the
observation endpoint crashed during reconnect. The endpoint/driver correction is
implemented and awaiting replay. This is neither a fresh playthrough nor arrival
acceptance. Exact executable/modules/assets are recorded in
`zig-out/reports/runtime-zig-245/intro-checkpoint/identity.json`; its source is now
superseded by the handoff and frog additions. First failure logs/captures are retained
under `runtime-zig-244/intro-first/` and `intro-queue-lookup/`.

Protopod, Slaughterskeet and Froginator are implemented with class-owned behavior and
supplied tuning. Native interactions, saves during their actions and connected
encounters are unverified. Remaining opening classes and bridge scripts are blockers;
full cinematic task/presentation parity and further campaign/MP remain open. No
legacy acceptance transfers. Actor/component changes require affected combat,
body-control/status and persistence replay at the consolidated checkpoint.

The handoff correction passes a limited replay in
`runtime-zig-245/handoff-replay/identity.json`, identity
`254909c3925ff64a9907a99c33053fe7021153677a8b4ec80004208bda34de48`:
remaining intro from the old shot-80 checkpoint → authored e1m1a arrival → normal
control → save/load. Arrival remains health 100, Disruptor, normal difficulty.
Restored frame inspected. No connected combat/traversal and no fresh New Game claim.
Three modules/91 focused contracts pass on that build. Subsequent action/path changes
require revalidation. Sequence 246 connects actor action programs and paths; native
bridge verification is pending. Missing health trees were identified as a normal
resupply blocker; Cambot/Thunderskeet/Crox/Rockgat remain actor blockers. Ambient
fireflies and finer effects remain separately tracked presentation work.

Sequence 246 consolidated actor/action/resupply build passes three modules and 94
focused checks. Applicable aggregate passes 232 Zig + 48 Python checks and formatting
(`/tmp/dk3-runtime-246-aggregate.log`). The fresh run in `runtime-zig-246/fresh-opening/` completed all intro and arrival shots,
arrival save/load and Ion pickup, then failed its guessed navigation waypoint.
No full campaign gate passed.
Health trees now provide the finite authored campaign resupply with saved fruit state;
live use/restoration remain unverified. Scope beyond the opening gate is unchanged.

## Current connected coverage (247)

| Player outcome | Exact build/assets | Remaining blocker / limits | Evidence |
|---|---|---|---|
| Fresh New Game, full intro and e1m1a arrival; arrival save/load and ordinary Ion pickup | Sequence 246 `fresh-opening/identity.json` contains every executable/module/package digest | Route failed at a driver waypoint against rock; full opening gate remains failed/incomplete. Subsequent actor/spawn changes require replay. | `runtime-zig-246/fresh-opening/` logs, inputs, captures and failure record |
| Ordinary first Slaughterskeet encounter, rock-step jump and first marsh checkpoint, health 100 | `b1a868d39f0d0e0c2242551e7b8deef800dc5a1691679b5a524640a5f741cf88`; full asset manifest in `opening-jump/identity.json` | Development replay from legitimate sequence-246 arrival save; not a fresh route. Missing classes are not retroactively inserted into old saves. No complete map traversal yet. | `runtime-zig-247/opening-jump/result.json`, inputs, captures and checkpoint |
| Bridge's ten authored skeets plus Thunderskeet, paths, aggression and restoration after fresh map initialization | Same sequence-247 identity; `bridge-first/identity.json` | Controlled activation and health 10000. Combat, death outputs and connected bridge traversal unverified. | `runtime-zig-247/bridge-first/result.json` and saved `bridge_paths.sav` |

Sequence 247 connects the single-use authored monster factory, unique IDs, inherited
flags, deathtarget and item spawnname. Saved dynamically created actors now admit their
animation metadata before publication. Three modules and 96 focused checks pass in
`/tmp/dk3-runtime-247-bridge-rebuild.log`. Full aggregate is pending this integration
batch; earlier aggregate remains historical. Actor death output changes require
civilian/guard and applicable weapon/body-control regressions. Thunderskeet spray,
frog spit, health tree use/restoration and dynamic navigation need live qualification.
Reference contracts were reviewed, not compared through reference playback. Spray's
unsafe twelve-entry cycle is intentionally bounded at twelve; complete visual/audio
parity and all remaining campaign/multiplayer scope stay open.

Sequence 248 repaired a premature e1m1a exit caused by projecting a trigger's authored
angle as brush rotation. `runtime-zig-248/trigger-before/` detects the defect on the
previous build. `trigger-after/` passes remote-point rejection before/after save-load
and valid contact with the real exit, using identity
`02a5fcdaf9752fbcfe8a91801ced0639e35ab6b07ab6d1ca986a3f664fba172c`
(full executable/module/asset manifest alongside the result). Diagnostic placement
excludes connected traversal acceptance. Preserve previous angled-trigger travel rows
as historical and **requiring revalidation**. Aggregate passes 235 Zig + 48 Python
checks, formatting and all three native modules. The ordinary marsh replay is underway
in `runtime-zig-248/marsh-trigger-fixed/`; a fresh consolidated full gate remains open.
