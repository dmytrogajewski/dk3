# Native port acceptance

Development stays on `rewrite/native-zig-runtime`. Main, the installed game, user
saves and the online service are preserved. Full four-episode campaign, companions,
multiplayer modes/bots, persistence, UI and release remain in scope. Removed-runtime
results never transfer to native acceptance.

## Current outcome matrix

| Milestone | Implemented / contract-tested | Running native engine / connected authored gameplay | Blockers and evidence limits |
|---|---|---|---|
| Weapon controllers | All 28 class-owned policies connected; Zeus, Wyndrax, Nightmare and Metamaser included. | Focused interactions passed in sequences 232–243. Sequence 251 repairs and exercises close Ion aiming. | Dispatch coverage does not establish all weapon interactions. Most fixtures grant equipment/health or place targets. Trident merge setup and Sunflare bright sprite edges remain open. |
| Fresh opening campaign | Intro, opening actors, action programs, world controls and native saves connected. | **Full gate unrun:** New Game → full intro → e1m1a → e1m1b bridge → e1m1c → authored e1m2a exit. | No coherent full-route build accepted. Current checkpoint development clears the bridge river, uses the repaired health tree, collects ammunition and destroys both turret controls, climbs and triggers bridge destruction/boss creation. Boss combat, e1m1c and e1m2a exit remain. |
| Native restoration | Typed snapshots, controller state and visited archives have executing contracts. | Actor/action restoration has focused engine evidence. Arrival save/load exercised. | Connected death/reload and visited-world persistence remain unrun. Sequence-241 travel is historical and needs replay after trigger-bounds changes. |
| Remaining campaign and multiplayer | Partial native implementations; no legacy backend. | Unrun as complete native outcomes. | Most later actors, companions/cinematic progression, four episodes, multiplayer modes/bots, network and release acceptance remain open. |

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
| Cambot acquisition/alarm restoration and four observed ten-health tree uses, partial/empty restoration | `7398a5842fa26b90bf0c52012167b8a910824c5c2037d003648d759f39a11496` | `runtime-zig-249/opening-actors-heal/` | Diagnostic placement/health. Alarm/dodge permutations and full presentation remain open. |
| Crox actual water level 3/swimming displacement, pending melee restoration/contact; Rockgat popup, burst restoration, lowering and lethal Ion contact/removal restoration | `282dd04dbfffddac553b953267f7575711f125a62d3f9d0e9c98237b4df08cd1` | `runtime-zig-250/crox-consolidated/`, `rockgat-contact/` | Diagnostic placement/equipment/health. Crox transitions/steering/avoidance, Rockgat authored toggle/death outputs and full presentation unqualified. |
| Bridge factory creates ten skeets plus Thunderskeet; paths/aggression restore | `b1a868d39f0d0e0c2242551e7b8deef800dc5a1691679b5a524640a5f741cf88` | `runtime-zig-247/bridge-first/` | Controlled activation and health 10000. No bridge combat, boss death outputs or connected traversal acceptance. |
| Remote angled-trigger rejection before/after load; actual exit contact works | `02a5fcdaf9752fbcfe8a91801ced0639e35ab6b07ab6d1ca986a3f664fba172c` | `runtime-zig-248/trigger-before/`, `trigger-after/` | Defective build fails the regression. Diagnostic placement; prior angled-trigger travel requires revalidation. |

Paths above are under `zig-out/reports/`. Historical detail and older identities stay
in [the journal](../specs/runs/RUN-dk3-independent-port.md), sequences 232–252.

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
- Boss attempts `bridge-boss-battle/`, `bridge-boss-clear-lane/`, `bridge-arena-route/`
  failed: corpse obstruction, lethal splash on the narrow ledge, then an unsuitable
  submerged waypoint. Actual boss attacks/contact are observed, but no boss defeat.
  No gameplay tuning changed to accommodate these driver failures.
- Next connected work: finish the bridge encounter/death outputs, then e1m1c and e1m2a.
  The driver includes a candidate boss/exit route, **under development**. Resupply and combat from
  checkpoints do not establish the required fresh coherent New Game route.
- Crox amphibious steering/avoidance, floor orientation and all attack poses; Cambot
  search cone, vertical avoidance, post-death wandering and inertia; Thunderskeet
  combat/death outputs; actor pain/gibs and complete audiovisual parity remain open.
  Rockgat fractional damage, death effects, tracers/sparks and authored toggle are open.
- Explicit compatibility departures: Cambot alarm recipients use PVS instead of PHS,
  dodge uses crosshair contact pending auto-aim; Thunderskeet's unsafe twelve-entry
  cycle is bounded. Reference source review is distinct from playback comparison.
- Pod shell monster/experience classification, triggered cinematics, earthquake/debris
  presentation and later campaign classes remain implementation gaps. Shared action
  cleanup/body-control, death outputs, perception and travel need applicable regressions.
- Aggregate checkpoint `/tmp/dk3-runtime-252-aggregate-fixed.log`: 241 Zig + 52 Python
  checks, formatting and three modules passed. Assertions are enabled and all explicit
  test roots execute. The first run detected an incomplete driver test fixture; it was
  corrected to include actual actor state and to reject idle hatching as well. Later
  save/refusal handling passes nine focused driver checks. Latest boss navigation and
  swimming refinements await running-engine replay; they do not change module identity.

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
