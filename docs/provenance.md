# Component dispositions

This record describes source admitted to the development checkout. The independent
runtime and release acceptance remain incomplete. The current source publication extends
the initial tools release with the bundled engines, runtime, converters and build graph.

| Component | Disposition | Evidence / remaining work |
|---|---|---|
| Complete pinned ioquake3 source | Retain with original notices | `engine/UPSTREAM.json`; GPL engine and separately licensed third-party code remain under their own terms |
| Existing engine extensions | Retain as ordinary source | `engine/CHANGES.json`: submodels, entity state/large gamestate handling, drawable dimensions, sound-update interface; no Gold includes or library imports |
| Zig engine source/flag mappings and GLSL generator | Retain independent tooling | `build/ioq3_sources.zig`, `ioq3_config.zig`, `stringify_shader.zig`; derived from ioquake3 build inputs, not Gold implementation |
| QVM build orchestration | Retain independent tooling | `build/qvm.zig`; compiler code is bundled upstream, optional targets only |
| Upstream LCC compiler | Preserve separate terms; qualification open | `engine/ioquake3/code/tools/lcc/COPYRIGHT` restricts sale; do not describe all bundled third-party code as GPL or declare the open-source-only release complete |
| Published dkguard and PAK/WAL/PK3 tools | Retain | Initial reviewed tools publication; existing synthetic fixtures |
| Offline asset converters and transitive imports | Admit reviewed format handling with replacements | `build/ASSET-SOURCES.json`; only Python/NumPy, local game data and ffmpeg inputs |
| Renderer-derived conversion routines and embedded patterns | Replaced/removed on admission | Independent background-color propagation, shelf lightmap packing and iterative intersection; original checker/lightstyle samples; removed translated font-width routines |
| Native dk3 world, menus, glyphs and build/install orchestration | Original implementation | `src/game`, `src/ui`, `src/cgame`, `src/shared`, `build/game.zig`, asset/install scripts; no Gold interfaces |
| Gold libraries, headers, DLL host, registry and patch implementation | Replace; excluded | No files admitted from the legacy runtime or Gold tree |
| Separate movement and mechanically translated game/client/UI code | Replace; excluded | Location outside the Gold directory does not establish independence |
| Other independent game/client/UI components | Review individually | No blanket admission from legacy source directories |
| Original/converted assets, text, saves, reference binaries | Local user inputs/reference only | Excluded from source and release packages |

The legacy inventory of 238 Gold translation units is not a complete provenance audit.
Review of remaining runtime components, generated inputs, and the release tree is an
explicit roadmap requirement. Compilation alone does not close that review.

`engine/CHANGES.json` records the initial engine import. `engine/DEVELOPMENT.json`
records subsequent ordinary-source changes against upstream, including conditional
native game hooks and the standalone protocol number. References to private source
locations in converter comments document past format research; they are not inputs
opened by the conversion or build graph. They do not establish independent provenance
by themselves. The release audit remains open.

The bot movement adapter also reuses the sideways movement decision from ioquake3
`BotAIBlocked` (`code/game/ai_dmq3.c`), with botlib collision validation. Its upstream
GPL notices remain in the bundled source.

The opening turret repair used optional local reference and supplied editor data
to identify behavioral facts: `monster_rockgat` fires chaingun rounds, defaults to
a 512-unit radius, low base/random damage, and a 0.13-second firing interval. The
native implementation uses the existing ioquake3 trace/damage path and simulation
deadlines. No reference turret implementation or interface is imported. Authored
`sight`, `range`, `fire_rate`, `basedmg`, and `rnddmg` override native actor settings.

Bot user-command projection adapts ioquake3 `BotInputToUserCommand` in
`code/game/ai_main.c`, including vertical movement and relative-axis normalization.
The upstream implementation and its GPL/copyright notice remain bundled.

The direct-use repair follows supplied editor descriptions of named doors and
optional reference observations of player interaction: remote targets stay remote,
physical buttons remain usable, and touch triggers are not use-ray controls.
The native eligibility predicate is shared by human and bot inputs; it introduces
no reference implementation, interface or generated dependency.

The C4 repair used optional reference observations only to establish contact explosions,
sticky proximity charges, damage-triggered chains and remote detonation. The replacement
uses native ioquake3 radius damage, entity damage callbacks, mover attachments and
simulation deadlines. No reference routines, interfaces or generated source are used.

The Gas Hands repair uses optional reference observations for behavior only:
campaign duration from the supplied lifetime table, extended by pickups,
camera-time suspension, and untimed multiplayer ownership. Its timer, shared
expiry, UI and persistence are independent implementations on native powerups.
Switching away retains the remaining timer instead of reproducing the reference
weapon-callback teardown behavior.

The extending ladder scenario exposed simultaneous movement despite per-rung
asset delays. The repair schedules native ioquake3 stop trajectories per door
part. Optional reference inspection confirmed delay-before-movement behavior;
no door implementation or data structures were imported.

The ion liquid-contact behavior and its 64-unit radius were checked against optional
private weapon reference material. The implementation uses native ioquake3 missile
content masks, point-content queries and radius damage; it imports no reference
implementation, interface, header or generated code.

The opening presentation repair uses supplied menu/HUD images, font metrics,
actor scale tables and model animation bounds. Native ioquake3 snapshots now
carry explicit actor scale axes and animation timing; the cgame interpolates
poses and uses vertex-colored sprite polygons. Actor floor contact, corpse
hulls, debris, thunderskeet flight/bombs, wall toggles, inventory panels and
menu interaction are independent implementations over engine services. Optional
private inspection established appearance and activation behavior only; no Gold
code, interfaces or generated implementation entered the dependency graph.

The follow-up repair adds independent visited-world archives and nested field
records, and compares movement spawn selection, weapon cadence, menu timing,
loading layout and sound names against optional private source. The cambot cone
uses ioquake3 collision traces, polygons and a supplied model tag. Cloud layers
use authored map parameters and supplied sky artwork with ioquake3 shader
projection and its noise-driven flash waveform. No original renderer, menu,
save or actor implementation is compiled or mechanically translated.


The complete weapons rewrite in sequence 199 uses Zig 0.16 implementations of all
28 selectable weapons, their server controllers and client presentation. Private
Gold source was consulted for behavioral facts, animation frames, effect parameters
and supplied asset names. No Gold runtime, implementation, generated translation or
interface is a build input. The existing ioquake3 C interfaces supply entity,
collision, damage, snapshot, renderer and audio services; original notices remain.
The owner's explicit native-Zig scope supersedes the earlier C-only weapons guidance.

Native-runtime sequences 244–248 independently implement opening cinematic execution,
Protopod/Slaughterskeet/Froginator/Thunderskeet policies, supplied actor action programs,
health trees, authored monster factories and death outputs. Private review established
contracts and asset names; private source, headers, binaries and generated translations
remain excluded. Trigger projection accounts for the reviewed difference between
reference SOLID_TRIGGER bounds and ioquake's rotated bmodel bounds. Current acceptance
is recorded separately in docs/native-acceptance.md; earlier runtime results above
are historical and do not qualify the new native runtime.

Sequence 249 Cambot behavior was established from optional private class contracts
and supplied tuning/model metadata. Native policy, ECS state, collision services and
client tag rendering are independently written. PVS alarm admission and direct
crosshair dodge qualification are explicit narrower compatibility departures, not
claimed reference equivalence. No private implementation is a project dependency.

Sequence 250 independently implements Crox and Rockgat class contracts established
from private behavior review and supplied authoring/model/event data. This includes
water sampling/attack variants, height-band wandering, turret deployment and shot
chains, and the class's extra pain deduction. Generic engine collision/navigation,
typed snapshots and native ECS remain the implementation mechanisms. No reference
source or runtime is admitted. Incomplete steering/effects and integer-versus-float
damage parity are explicit acceptance gaps.

Sequence 269 admits `CONTENTS_DK3_NITRO` at the unused native contents bit 0x0800
and its converter mapping. The engine continues ordinary numeric brush-content queries;
no private physics or implementation is imported. Authored nitro is separate from the
swimming mask. The updated header digest is recorded in `engine/DEVELOPMENT.json`.
Independent liquid/fall policies were written after reviewing private client/AI/artifact
behavior; that source remains outside the checkout and is not a build input.

## Sequence 275 — public default light animation samples

Reviewed and admitted only the thirteen default light animation strings (styles 0–11
and 63) from id Software's public GPL Quake II `game/g_spawn.c`. These replace the
project's earlier approximations in the converter and native lightstyle policy.
No private reference implementation or private patterns file is imported. The native
switch/ramp controllers and transport are independently written.

- Upstream: [id-Software/Quake-2, pinned g_spawn.c](https://raw.githubusercontent.com/id-Software/Quake-2/372afde46e7defc9dd2d719a1732b8ace1fa096e/game/g_spawn.c).
- Commit: `372afde46e7defc9dd2d719a1732b8ace1fa096e`.
- Source SHA-256: `4c401dfb37076aa1186bf1b321d4606a997a1324fd4c2c3afb933d0a045a0eff`.
- Copyright (C) 1997-2001 Id Software, Inc.; GPL version 2 or later, as stated in
  the source header. Copyright attribution accompanies both admitted tables; the
  project's [GPL text](../LICENSE) remains distributed.
- Review scope: the default strings only. No Quake II runtime, game assets, headers
  or unrelated code was admitted. Public data matches the reviewed behavioral
  pattern contract; rendered native/reference comparison is still pending.

### Native authored lightning and hearing (sequence 277)

The independent converter preserves supplied BSP PHS rows in a project-defined
DKPH/DKPT extension; runtime lookup uses the bundled ioquake collision tree. No private
implementation or new third-party code is admitted. Lightning/attractor timing, damage,
media selection and mathematical presentation behavior were reviewed privately; Zig
owners and the bounded transport/query integration were authored in this project.
Existing ioquake and project GPL notices remain in force. Supplied rows and media stay
local generated assets, excluded from publication.

### Byte-direction data (sequence 279)

`src/runtime/domain/direction_bytes.zig` admits only the 162 numerical direction vectors
from already bundled `engine/ioquake3/code/qcommon/q_math.c`, whose SHA-256 at review is
`f00e75f3ea0a59176d19b6328044b84e8dd5734af14a960e8ec10d79120a7cb3`.
Copyright (C) 1999–2005 Id Software, Inc.; GPL-2.0-or-later, preserved in the new file
and root LICENSE. Native lookup code is project-authored. This public data supplies
the authored effect's existing byte-direction behavior; no private table/function is
an input to generation, compilation or tests. Atlas coordinates and effect contracts
were privately reviewed as behavior; original particle images remain local assets.
