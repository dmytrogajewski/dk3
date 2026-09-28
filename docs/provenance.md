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

Sequence 288 repairs the bundled GPL botlib portal cache: route prediction read
a first-reachability index that the cache update never populated. The independent
repair stores the selected existing area-cache index with its travel cost and rejects
unavailable zero-cost portal routes. Six read-only e1ctf1 edge traversals retain two
unaffected local routes; the defective engine cycles in the other four, while the
repaired engine reaches all six goals. No private reference was needed or imported.
Server disconnect reasons are also printed locally for failed native-run diagnosis.
Original bundled notices remain unchanged.

Sequence 289 reviews the private reference's cinematic unique-ID dispatch and
missing-sound contract (`dlls/world/cin_playback.cpp`, `base/dk_/dk_cin_playback.cpp`,
and `base/Audio/DkAudioEngine_Miles/S_Calls.cpp`). Supplied e1m2 authoring references
`hiro1` under the misspelled `cien_hiro` label and requests absent media at
`globa/a_speedwhoosh.wav`. Independent native preloading now uses the existing
performer identity; failed audio registration logs the original path and leaves
playback running. There is no asset-name substitution or copied private code.
The small public test fixture is project-authored from the observed record contract.

Sequence 290 reviews absent cinematic records/recipients in the private reference
(`base/dk_/dk_gce_main.cpp`, `dlls/world/cin_playback.cpp`) and the missing-model
registration behavior (`dlls/world/cine_entities.cpp`, `base/ref_gl/gl_model.cpp`,
`base/ref_gl/gl_rmain.cpp`). Missing program files do not start playback, and commands
for absent actors have no recipient. Native handling now preserves those contracts;
empty, oversized and malformed supplied files remain errors. Unknown spawn classes
are still rejected. Empty unique IDs cannot bind unrelated unnamed performers.

The supplied credits program creates a timed door-use carrier whose computed model
is absent from both the original local archives and converted packages. Native code
permits missing media only when every task for the class is control/lifetime work
and at least one task uses a target. It preserves the authored timing and removal.
Intentional presentation correction: that control carrier is invisible rather than
using the reference renderer's missing-model marker. Actual character performances
still require their model metadata. No private implementation or asset is imported;
public parser fixtures are independently authored.

Sequence 291 reviews the bundled GPL engine's fast-restart contract in
`code/game/ai_main.c` and `code/server/sv_ccmds.c`: VM restart preserves the
engine hunk and navigation world. Native shutdown now retains botlib for that
boundary, releases bot input owners and clears stale navigation projections
before the next match. Full map admission still sets up and loads navigation.
The new LAN and bot diagnostics are project-authored; no private implementation
or assets are admitted. Lift approach routing uses actual collision and existing
authored controls, without changes to map geometry, damage or mover timings.

Sequence 292 compares supplied AAS reachability types and liquid contents with
the bundled botlib travel flags and the native player's existing swim/ledge
motor. Navigation now permits that supported water-jump operation; the existing
slime-escape policy and actual liquid damage remain unchanged. Local graph
reports and map geometry remain in ignored evidence, not public assets. Lift
waiting uses the native mover's actual motion/return deadline rather than
assuming a requested floor schedules movement. The contract fixtures are
project-authored; no private implementation is imported.


Sequence 293 examines the local supplied e1dt1 BSP/AAS and its native collision
traces. The raised objective room leaves through its authored teleporter after a
small supported step; three apparent direct exits are obstructed. The independent
bot recovery uses existing trigger bounds, destination lookup, player hull traces
and navigation. No private implementation, changed map data or synthetic passage
is admitted. This recovery remains unaccepted because the controlled bot replay
still fails to select the passage.

Sequence 294 reviews private behavior only for Escape completion and sound
lifetime (`base/client/keys.cpp`, `base/dk_/dk_gce_main.cpp`,
`base/dk_/dk_cin_playback.cpp`, `dlls/world/cin_playback.cpp`), loading-art layout
(`base/client/console.cpp`, `base/client/cl_scrn.cpp`) and menu controls
(`base/dk_/dk_menu_newgame.cpp`, `base/dk_/dk_menu_controls.cpp`,
`base/dk_/dk_menup.h`). Native implementations are project-authored. Original
images, font metrics, cinematic programs and animation records remain in the
local converted packages, excluded from publication.

The native completion path releases performers/viewer control and executes the
existing authored continuation. Camera cuts stop their loop and reset camera
interpolation while retaining streamed dialogue. Streamed MP3 entries keep their
authored replacement channel; ordinary WAV effects retain automatic concurrent
channels. Completion stops only the cinematic stream channels. The bundled GPL
engine adds that narrow local-channel stop in both its existing software and
OpenAL backends, plus Escape dispatch before the pause menu. Original notices
remain intact; changed engine hashes are recorded in `engine/DEVELOPMENT.json`.

Actor, performer, scenery and remote-player presentation now consumes the
project's existing wire animation timing fields. Authored sequence rates and
snapshot positions drive independent render interpolation; physics, damage and
script clocks are unchanged. Teleports, camera cuts, missing snapshots and saved
world restoration delimit blending. No private renderer or animation code is
an input to compilation, conversion or testing.

The same sequence repairs an observed bundled OpenGL2 sky-buffer overflow.
`RB_ClipSkyPolygons` consumes the source geometry to compute visible face bounds;
subsequent generated sky faces now reuse that buffer rather than appending to
its occupied batch. The existing GPL renderer is the only implementation source.
The before/after native Marsh scenario preserves the failure and passing replay.

A subsequent native e1m3a UI-save replay exposes a project-owned presentation
tag collision between actor lasers and knight attacks. The knight class now owns
an unused value; its server and client already share that policy constant. A
catalog-wide uniqueness regression first fails on the real duplicate. This is
an independent transport correction, with no authored behavior or private code
changes. Native build identities continue rejecting mixed module installations.

Sequence 295 reuses the HD image overlay already admitted locally in sequence
183. Its 3564 texture PNGs remain outside Git; package SHA-256 is
`d2e8d95bdbcb52de5529d932d8a3be378b46ac293fe2ec15849c7ac2d299c645`.
Native play now discovers that shared cache by default, with the existing
image-only admission check. No reference runtime, source or additional asset
corpus is imported. The gameplay package identity is unchanged.

Sequence 296 connects missing native effects and gameplay contracts using existing
owned mechanisms. Main is read only: Ion electrical flight and camera searchlight
parameters, checkpoint behavior and actor fragmentation eligibility are reviewed
as independent-project reference. Private Gold inspection supplies behavior facts
for pod hatch timing/placement and func_explosive material flags, authored tuning
and fragment lifecycle; no source, headers, binary modules or new asset corpus are
admitted from that workspace. In particular, native hatching retains origin +10
rather than importing main's clearance workaround, and explosive flag 8 remains
stone rather than main's generic metal mapping. Existing local sky/HD shaders and
images are reused. The interpolation repair is based on captured native engine
clock values, not private renderer code. Focused verification and remaining visual
parity limits are recorded in sequence 296 and native acceptance.

Sequence 297 begins resident-world preparation using the bundled GPL engine only.
Collision allocation/selection, generation handles, independent background file
streams and versioned native imports are project-authored changes; upstream
notices remain intact and `engine/DEVELOPMENT.json` records source hashes.
The independent connection inventory reads already-admitted converted BSPs and
retains generated coordinates locally. No private source, new asset corpus or
reference implementation is introduced. Actual engine collision tests use small
project-authored synthetic BSPs, separately from the recorded four-map native
diagnostic. This is not provenance or acceptance for unimplemented seamless
rendering, navigation, cross-world gameplay or persistence.

Sequence 298 continues from the bundled GPL ioquake3 renderer, server and botlib.
World ownership, bounded surface batches, scoped registries and native preparation
are project-authored adaptations; existing upstream notices remain. The short
private authoring descriptions in `dlls/world/Epairs.h` and the changelevel
intermission decision in `dlls/world/Triggers.cpp` were inspected read-only to
establish flag behavior: a named landing retains direct single-player travel,
whereas an intermission exit without one uses a cut. No reference implementation
text or assets were copied into the project. The independent inventory expresses
that observed contract and tests both cases. Nearby vertex comparisons use only
the already-admitted converted map package and keep all generated geometry local.
These observations do not establish full original presentation or seamless play.

Sequence 299 implements resident admission and ownership transfer using this project's
existing component, resource, snapshot, renderer and collision contracts. Bounded
reliable configstring transport checks its digest and the supplied BSP checksum;
player copying retains birth identity and complete component values. Protocol 1348
adds the active map identity consistently to bundled-engine and independent Zig
message codecs. This is original integration code over the admitted engine, with
no additional private implementation consultation or import. Controlled A↔B transfer
in both renderers is distinct from authored seam, cross-map combat and region-save
acceptance; see `native-acceptance.md` for the exact build and local evidence.

Sequence 300 extends the project's portable snapshot format to explicit resident
members and world-qualified reference validation, with schema-1 reading preserved.
Actual A/B save/death restoration and a sequence-296 schema-1 fixture are replayed
on the exact build recorded in `native-acceptance.md`. The inactive-snapshot repair
uses the public `SNAPFLAG_NOT_ACTIVE` contract and the existing bundled GPL
`code/cgame/cg_snapshot.c` initialization behavior; no private implementation was
consulted or imported. Generated save/geometry evidence remains local. Old visited
archive conversion and fully connected traversal/combat remain separate open work.

Sequence 301 derives local campaign admission metadata from supplied converted BSP
entities. Exact opening BSP digests pin the prior geometry review; generated manifests
remain local and are included in installation/evidence identity. Cinematic-controlled
exits are classified from authored target relationships. No private reference
implementation was consulted or copied for this sequence. New engine owned_memory.h
is independent GPL-2.0-or-later code; reviewed renderer/navigation/server allocations
retain their existing owners and explicit shutdowns. Engine file hashes and pinned
upstream identities are recorded in engine/DEVELOPMENT.json.

Sequence 302 independently maps native visited-save identities from the project’s
existing typed components. No private implementation or original save codec was
consulted or imported. Local sequence-294/301 native fixtures supply regression
evidence and remain outside public sources. The renderer’s inline handle codec is
independent GPL-2.0-or-later code. The reliable boundary repair follows the bundled
engine’s CL_ParseGamestate and CL_InitCGame contracts; it preserves ordinary
reliable handling. The doubled sound separator is verified against the supplied
local sound package. Updated engine file identities are in engine/DEVELOPMENT.json.

Sequence 307 reuses the bundled `engine/ioquake3/code/thirdparty/zlib-1.3.1/`
in both renderer PNG loaders. Its six existing inflate/checksum/allocation source
files and the notice in `zlib.h` were reviewed; no new external component is added.
The existing GPL PNG decoder/filter/pixel conversion remains attributed. The new
allocation bound and chunk handling are project changes. Invalid zlib headers or
checksums now reject a PNG instead of being ignored; valid pixels remain covered
by independent synthetic fixtures. No original game asset is part of those tests.

Sequence 308 separates that existing decoder into a pure, bounded CPU entry point
and its renderer adapter. Project-owned pthread preparation uses immutable input,
owned pixels and atomic completion; engine filesystem/renderer calls stay on the
owner thread. Existing material lookup and format preference remain authoritative.
The worker contracts use independent synthetic PNGs; the corrupt-world scenario
writes only a temporary profile override. No private implementation or additional
third-party component is admitted. Updated renderer identities are recorded in
`engine/DEVELOPMENT.json`.

Sequence 309 uses local private reference behavior only for worker fear: the
skinny-worker hide/cower callbacks, fat-worker callbacks and common cower dispatch.
Recorded facts are the ten-second retreat/cower bounds, skinny model poses
`gamba`/`gambc`, the 300-unit visible-threat retry, active-distance release, and
class-specific probabilistic vocal choices. Native code is independently written;
no private implementation or assets are copied into this repository. Existing
native AAS/collision routing remains in use; original hide-node route equivalence
is not claimed. Fat workers use their ambient fallback when retreat is blocked.

The shared ground correction follows the already admitted ioquake3 slide/player
contract (`bg_pmove.c` ground departure test): separating overclip residue is not
a jump. The new regression exercises the native actor motor with a captured
0.04 upward resting velocity; reinstating the defective strict sign check in a
temporary source copy makes that regression fail. Camera modes and player event
ordering use the project's own native transport. Autosave health rules and softer
Cambot surface pools are owner-requested additions, not claims of reference parity.

Sequence 311 uses the preserved main branch and admitted ioquake3 camera contract
for first-person stair/duck presentation: 200/100 ms decay, accumulated steps
bounded to 32 units, and no duplicate steps during prediction replay. The native
implementation is independent Zig code; collision and movement rules are unchanged.
Private reference inspection supplied only pickup behavior facts: ordinary armor,
souls, save gems, wraith orbs and the bottle rotate; ammunition and health packs
retain their placed angles; world weapons rotate in multiplayer. Default rotation
is 100 degrees per second. Custom boost assemblies and authored rotation overrides
are not claimed as covered by this correction.

The reference's pickup glow and minimum model light informed the readability fix.
Native pickups use a raised light sample and the existing RF_MINLIGHT flag; both
bundled renderers now honor that flag with a 30-percent per-channel ambient floor.
This is an intentional readability correction, not reproduction of the original
pulsing glow. Enhanced weapon shine is a project-owned, neutral modulation of the
lit skin rather than the former blue additive overlay; exact reference material
equivalence is not claimed. No private implementation, texture or other asset was
imported. Engine file hashes are recorded in `engine/DEVELOPMENT.json`.
