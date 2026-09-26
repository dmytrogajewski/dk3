# dk3 independent port run

- [seq:1] Resumed from the approved complete-port plan; revised the active roadmap into
  nine implementation areas followed by V1–V12 scenario verification. Prior tools publication
  evidence and the legacy port roadmap are preserved.
- [seq:2] Canonical working copy is `/home/dmitriy/sources/dk3`, copied from the initial
  reviewed publication checkout. Existing local game and saves remain in daikatana.
- [seq:3] Started bundled upstream engine and standalone Zig graph integration. No baseline
  lint/test suite or game acceptance run. Implementation status: Step 1 implementing;
  independent-runtime acceptance: unrun.
- [seq:4] Bundled 1,048 upstream files from the pinned source archive. Recorded its SHA256
  and per-file identities in `dk3/engine/UPSTREAM.json`; admitted 38 existing engine change
  rows into 20 ordinary source files, recorded in `engine/CHANGES.json`. No cache patcher
  or sibling checkout is required by the new build.
- [seq:5] Implemented the direct engine graph, reused source/flag mappings and GLSL
  conversion, native module foundations, and optional QVM tooling. Added explicit header
  inputs to QVM compilation. The default build includes dk3, dk3ded, both renderers,
  native foundation modules, and dkguard. Updated the existing CI dependency list.
- [seq:6] Targeted integration probes passed: `zig build engine qvm-tools`, `zig build qvms`,
  and the root `zig build`. These are compilation probes for the extracted graph, not
  gameplay acceptance. No full test/lint suite and no campaign scenario was run.
- [seq:7] Component review found LCC's separate sale restrictions in the upstream COPYRIGHT.
  Its tools remain optional; the default native build does not depend on them. Qualifying
  the all-open-source QVM path and the remaining component audit stay open. No publication
  or Git operations occurred.
- [seq:8] Evidence: `dk3/zig-out/reports/engine-foundation/build-evidence.json` and adjacent
  logs. Full upstream path/hash comparison passed. Runtime acceptance V1–V12 remains
  unrun. Continue the implementation pass with independent asset/profile/install work
  and native gameplay state; no broad-suite gate is required between those areas.
- [seq:9] Admitted offline format converters and their transitive Python dependencies.
  Replaced the fixed-size skin flood fill, lightmap packing/trace control flow, embedded
  missing-texture pattern and built-in lightstyle strings; removed translated font-width
  routines. Source identities: build/ASSET-SOURCES.json. Full release review remains open.
- [seq:10] Wrote retail/1.3 profiles with unified private input views, loose and entity/palette
  overrides, content fingerprints, resumable conversion, deterministic packages, raw
  scripts/routes/subtitles and normalized runtime tables. Corpus conversion remains unrun.
- [seq:11] Added assets/play-install/play. Install copies only this build's binaries/modules
  and private packages into an atomic generation with a separate home directory. Launcher
  and menu identify incomplete campaign support. Installation and launch remain unrun.
- [seq:12] Implemented native lifecycle integration, map-local stable entity IDs, delayed
  targets, killtargets, triggers, breakables, walls, teleports and authored exits. Shared
  ioquake3 movement now includes ladders. No Gold runtime/header/library is linked.
- [seq:13] Implemented original menus, scaled glyph/HUD rendering from supplied fonts,
  binding conflict feedback and converted-model resolution. Targeted `zig build game`
  identified missing external UI/client include paths; after correction it exits 0, with
  three modules in zig-out/lib/dk3. Log: /tmp/dk3-native-runtime-build.log. This is compile
  evidence only. No lint/full suite or client/server scenario was run.

- [seq:14] Added 28 weapon slots, shared switching/fire prediction, ammunition, attack
  families, status effects, keys/artifacts, experience/attributes and named transition
  records. Balance data is read from user tables. Weapon presentation, special attack
  interactions and item appearances still require completion and gameplay verification.
- [seq:15] Bundled BSPC commit 6c11357e6d79a89e88cda2fe0e67c99a8923e116 with licenses
  and source identities. Added its Zig target and deterministic navigation packaging.
  Targeted compilation exposed date macros, one missing declaration and private/shared
  global collisions. Fixes are in source; navigation generation remains unrun.
- [seq:16] Connected table-defined actors to native spawning, collision, combat, animation,
  AAS pursuit, authored path corners and companion commands/yielding. Added map event
  generators, monster spawners, counters and action triggers. Specialized actor abilities,
  companion persistence/progression and complete route recovery remain open.
- [seq:17] Implemented an original action grammar and normalized runtime scheduler. A
  focused format probe parsed all 15 supplied action files including shared includes.
  The e1m1b authored program contains 43 instructions covering ten mosquito spawns and
  aggressive state changes; no bridge gameplay acceptance is claimed.
- [seq:18] Added an original bounded version-15 cinematic reader and native playback:
  cast tasks, camera splines, explicit camera protocol fields, PVS origin, fades, sound,
  cinematic cleanup and authored post-cinematic exits. Three format probes (intro,
  e1m1_cinestart, e4m1_cinestart) resolved stored surplus segment data; normalized records
  retain it while playback uses the point count. Rendered verification remains unrun.
- [seq:19] Added portable typed save records with bounds/checksum/duplicate-field
  validation, plus a versioned engine service for private atomic writes and previous-save
  recovery. World reconstruction and scheduler/cinematic save integration remain pending;
  this is not yet a usable save/load feature. No broad tests or lint were run.

- [seq:20] Targeted `zig build engine game navigation-compiler` succeeds after BSPC
  declaration/linkage repairs. Logs: /tmp/dk3-save-interface-build.log and
  /tmp/dk3-bot-model-interface-build.log. Added native botlib navigation mode, ordinary
  client-command bots, supplied model animations, Hiro presentation and item bindings.
  These are compilation results, not gameplay acceptance.
- [seq:21] Widened native model/sound/event fields, configstrings and fragmented messages;
  removed gamestate baselines and set development protocol 1338. Added explicit team
  objective state, CTF/deathtag rules, team spawns, carrier HUD, objective bot goals and
  population adjustment. Native movers now interpret door/button/plat/rotation/train
  map semantics while using ioquake3 collision/pushing. Integrated engine/game/BSPC
  compilation succeeds: /tmp/dk3-objective-mover-build.log. Door linking, mover parenting
  and bot switch coordination still need implementation.
- [seq:22] Connected typed saves to named slot commands, preflight staging, map reload,
  entity/reference/resource reconstruction, event definitions, action stacks and cinematic
  cast/sound/camera state. Source review and integration continue; no save scenario or
  recovery acceptance has been run.
- [seq:23] Integrated companion inventory/progression, authored start anchors and sidekick
  triggers, doorway yielding, route recovery, transition/save records and HUD commands.
  Added entry autosaves, optional save-gem consumption and save/load menu paths. Targeted
  engine/game compilation exits 0: /tmp/dk3-companion-integration-build.log. Scenarios unrun.
- [seq:24] Added an original bounded authored-node converter and collision-aware graph
  search for air/water routes, retaining ground and track data. Format probes read six
  maps across four episodes; e1m5a retains 10 track nodes and e1m7b retains 6. Added native
  mover assemblies for parenttarget attachments and rider rollback through ioquake3's
  pusher. Route traversal, attachment motion and blocking remain unverified.
- [seq:25] Added supplied decoration-table normalization and native scenery, animation,
  breakage, physical movement and healing stations. Probes read 86/87 Episode 1 decoration
  rows for retail/1.3, then 74/59/42 for Episodes 2–4. Fixed headerless music table paths
  and zero-only decoration padding. Added map music, ambient/speaker activation and
  asset-backed subtitles. Protocol 1339 adds explicit model scale and alpha. Integration
  compilation succeeds: /tmp/dk3-world-media-integration-build.log. No broad suite, lint or gameplay acceptance has been run.

- [seq:26] Added host/join/LAN multiplayer menus and an asset-derived map catalog, control
  scrolling, inventory/attribute controls, temporary attribute boosts, episode-aware travel,
  secret doors, camera monitors, and actor trigger contact. Added sprite frame metadata and
  native quad rendering. These paths remain unverified in the running game.
- [seq:27] Added an original frame-table reader. Focused supplied-data probes normalize 854
  actor animation records per profile and report eight missing optional frame tables. Native
  attacks now select among the three supplied attack groups and deliver hits/sounds at their
  authored frames. Added sight memory, rail routing, alarms, hatching, resurrection, gaze,
  wraith summoning and wisp consumption. Game compilation exits 0 in
  /tmp/dk3-actor-behavior-build.log. Boss/campaign acceptance remains unrun.
- [seq:28] Added world weather/particle/light/beam/quake/debris descriptions and client effects,
  destructible brush handlers, supplied projectile/impact models and firing sounds, and held
  weapons on authored hardpoints. Protocol 1340 carries explicit effect fields. Save preflight
  now validates decorations/effects/speaker indices and rejects cyclic mover attachments.
  Targeted `zig build engine game` exits 0: /tmp/dk3-effects-protocol-build.log. No lint,
  broad suite, asset corpus conversion, client/server scenario, or campaign acceptance ran.
- [seq:29] Added bottle-bomb ingredient assembly and script key gating, objective team-card
  checks, complete named player travel parsing, carrier-aware companion readiness, bot
  physical-control discovery, escort/recovery roles, options and favorites controls.
  Targeted `zig build engine game` exits 0 in /tmp/dk3-campaign-state-build.log.
- [seq:30] Added simulation-time particle emission cycles/stop times, lightning strike
  durations/damage and attractor selection, rain streaks, client effect reset, carried
  objective tags, cloak/team presentation and supplied muzzle geometry. Added authored
  actor death drops (including Wyndrax/Nightmare pickups), gravity, roaming and leaps.
  Speaker volume/range/direction now have explicit protocol fields and a versioned
  cgame sound import implemented by software and OpenAL backends. Targeted
  `zig build navigation-compiler engine game` exits 0 in
  /tmp/dk3-effects-audio-navigation-build.log; subsequent entity-capacity and movement
  refinements have not yet been compiled. No running gameplay acceptance is claimed.
- [seq:31] Started the documented asset build with the private 1.3 inputs and an isolated
  Python environment containing pinned NumPy 2.4.3. Base, images, textures and all 84 BSPs
  converted; navigation generation stopped on credits. /tmp/dk3-assets-generation.log
  records the result. GDB identifies BSPC's 64-byte output path overflow at bspc.c:707;
  extended/bounded path handling fixes that access. The next probe identifies null-base
  size arithmetic in CopyWinding; replaced it with a size calculation. A subsequent
  credits conversion reaches an already-used parent partition plane; candidate selection
  now treats that plane as a boundary. The first output had zero reachabilities: inconsistent MAX_PATH definitions changed
  the shared aas_t layout between compiler and bot-library translation units. Aligning
  those definitions produces 6,834 areas and 14,666 reachability records for credits
  (/tmp/dk3-bspc-credits-layout-fix.log). These are implementation/build integration
  probes, not campaign or navigation acceptance.

- [seq:32] Extended AAS mover indices to nine bits below the signed contents bit. The old
  compiler traps in AAS_StoreAreaSettings on e1dt1 (305 submodels); GDB evidence is in
  /tmp/dk3-bspc-e1dt1-original-backtrace.log. The repaired compiler exits normally with
  6,872 areas and 11,459 reachability records (/tmp/dk3-bspc-e1dt1-backtrace.log; GDB's
  final bt has no stack after normal exit). Engine/game/navigation compilation exits 0
  in /tmp/dk3-capacity-navigation-build.log. Added AAS lump/link validation and per-map
  resume records. Asset orchestration reuses completed stages across compiler-only
  changes and runs navigation after independent conversions. The current asset build
  has converted shaders/models/sprites/HUD/sound/music/data; navigation remains running.
- [seq:33] Added Nharre's authored teleport-anchor selection, Wyndrax's authored charging
  source, and selection among equal-range actor attacks. Added trigger_change_sfx with
  persisted player/environment state, protocol 1342 and cgame sound-environment import
  701. Software sound uses damped delay lines; OpenAL uses EFX and falls back to software
  when EFX is unavailable. Music/voice streams bypass the room response. Integration
  compilation exposed a declared but unbound alSource3i in upstream qal; binding added.
  The repaired integrated build is running. No game scenario or broad suite has run.

- [seq:34] The complete 1.3 asset build exits 0 in /tmp/dk3-assets-complete-conversion.log:
  all 84 BSP/AAS pairs plus textures, shaders, models, sprites, fonts, sound, music and
  gameplay data. Installation checks exit 0 in /tmp/dk3-native-media-install.log.
  The full profile contains 1,145 actor frame records. Stage reuse now compares each
  converter's local import closure and dependent stage inputs; console-font/base-only
  changes reused the other conversions, including navigation.
- [seq:35] Native e1m1a reaches rendering. Replaced remaining stock media registration,
  loading presentation and scoreboard with dk3 presentation and supplied assets. Added
  a supplied-glyph console atlas, native module defaults, isolated save/config paths and
  standalone identity. TGA capture /tmp/dk3-native-bringup.png shows the world, actors,
  weapon and HUD. Its old run was inadvertently deathmatch: upstream SV_Map_f reset
  g_gametype 2 to 0. Standalone map commands now preserve the chosen mode, including
  campaign transitions and save restoration. This capture is not campaign acceptance.
- [seq:36] First campaign start exposed FOFS null-member arithmetic in native companion
  initialization (/tmp/dk3-campaign-opening-backtrace.log). Replaced FOFS with offsetof
  and removed the inherited game-source null/object-size sanitizer exclusions. Added
  bounded decoration frame overrides with map/entity diagnostics after supplied e1m1a
  requested frame 2 of a two-frame swamp model. Save validation now accepts valid static
  frame overrides. Replaced two signed JPEG DCT shifts with bounded multiplication
  after screenshotJPEG trapped in jpeg_fdct_islow. Affected startup/capture/save probes
  are running; broad lint/tests and campaign/multiplayer acceptance remain open.

- [seq:37] e1m1a now writes a manual save and JPEG capture without terminating
  (/tmp/dk3-campaign-opening.log). Save schema additions had stringified C member
  expressions containing dots and capitals; replaced them with explicit stable field
  names. JPEG's Huffman bit accumulator also used signed shifts; changed the accumulator
  to unsigned after /tmp/dk3-jpeg-second-backtrace.log identified emit_bits_s. A longer
  opening run writes and restores a mid-cinematic save, then fails on cine_hiro's neutral
  idle request (/tmp/dk3-cinematic-save-load.log). Chapter models containing only action
  poses now hold a neutral pose, play single cinematic animations once, and retain
  looping behavior for continuous-animation tasks. The repaired full opening is pending.
- [seq:38] Runtime AAS validation rejected generated navigation as out of date. BSPC's
  MD4 UINT4 was unsigned long, which is 64 bits on the initial Linux platform. Replaced
  it with uint32_t; generated e1m1a AAS and the engine's own checksum both read
  1524924515 for the converted product BSP. All navigation is being regenerated in
  /tmp/dk3-navigation-checksum-install.log; other stages reused their completed outputs.
  Game startup now names a navigation load failure rather than continuing to issue
  thousands of AAS_UpdateEntity errors. Added saved-map-aware cinematic model validation
  and stopped destination-free sidekick stop triggers from routing companions to zero.

- [seq:39] Regenerated all 84 AAS files and installed them successfully; e1m1a now loads
  navigation without AAS checksum/link-update errors. /tmp/dk3-opening-complete.log
  runs through opening shot 5 and writes opening-complete.sav; despite the probe name,
  snapshot inspection shows the cinematic still active at shot 5, elapsed 5.6 seconds.
  It does not prove the handoff to player control. Added larger scalable stat panels with
  supplied HUD icons, suppressed the irrelevant zero-ammo number for melee weapons,
  and removed Quake III's extra spawn health. Rendered rain revealed that RT_RAIL_CORE
  ignores entity radius and uses the global rail width in both renderers. Native rain
  and world beams now submit camera-facing quads at their own width with soft edges
  and a near-camera fade; the affected capture remains pending.

- [seq:40] Opening cinematic completion appears in /tmp/dk3-opening-handoff.log,
  but the intended movement commands preceded restoration; this is not control-handoff
  acceptance. Startup probes exceeded the engine's 32-command argument limit; moved
  scenario commands to private config files. Save loading now inserts its map command
  ahead of subsequent console commands. Selected dedicated maps previously failed
  allocating 176,160,832 bytes of snapshot records. Shared history capacity and a
  512 MiB standalone default hunk remove that failure in /tmp/dk3-native-map-capacity.log.
  e1m7b then exposes an authored model-free func_train carrying the sword decoration;
  added a non-solid invisible mover parent, preserving normal train and attachment logic.
- [seq:41] Rain still overflowed after increasing polygon constants. GDB in
  /tmp/dk3-rain-capacity-first.log reads max_polys=600 and max_polyverts=3000 from the
  installed renderer while the source header specifies 4096/16384. An immediate engine
  build reports cached renderer compilation in /tmp/dk3-engine-capacity-rebuild.log.
  The C-only build now includes bundled header contents in its command cache key,
  covering engine, native modules and BSPC. This avoids accepting stale header-dependent
  binaries. The rebuilt installation and affected rain/handoff scenario are pending.

- [seq:42] /tmp/dk3-opening-restored-controls.log exits 0: opening save restored,
  e1m1_cinestart completed, normal input moved from (1608,-2592,552) to
  (1586,-2361,552), and weapon_ionblaster was collected. Captures
  /tmp/dk3-native-bringup-data/dk3/screenshots/dk3-control-ready.jpg and dk3-walk.jpg
  show the HUD and narrow rain; no polygon-capacity warnings remain. opening-walk.sav
  contains health 100, both starting weapons and 40 ion rounds. Autoswitch still selected
  the disruptor because intervening predicted input replaced the server weapon before
  the inventory snapshot; selection now detects newly acquired inventory bits.
- [seq:43] /tmp/dk3-all-map-integration.log attempts all 84 maps once, exits 0, and
  reports four initialization failures: e1m3b/e1m6c/e1m7b decoration ranges ending at
  the model frame count, and e1m5a's parenttarget matching a relay before the train with
  the same name. Normalize the exact one-past endpoint with a diagnostic, and search
  for a mover parent among matching targets. All other maps initialize; missing authored
  routes and the unrecognized e1m2b func_areaportalass remain named diagnostics. This
  is startup coverage, not campaign progression, encounter or multiplayer acceptance.

- [seq:44] /tmp/dk3-map-animation-fixed.log confirms e1m3b, e1m5a, e1m6c and e1m7b
  initialize after the repairs. /tmp/dk3-ion-autoswitch-fixed.log shows restored opening,
  completion, ion pickup, automatic selection and successful save. View meshes already
  carry their camera offset; removed extra displacement after the ion mesh was below
  the visible viewport. /tmp/dk3-opening-fifo.log exercises normal turning/firing,
  enemy pursuit/damage, death, restored combat and pause-menu input. ion-encounter.sav
  records a slain slaughterskeet, 50 experience, health 93 and 22 ion rounds. The
  dk3-ion-encounter-1.jpg capture shows the encounter; this does not cover the bridge.
- [seq:45] The same client run loads and captures e2m5c, e4m2a and e2m4d, then exits 0.
  No gamestate overflow or bad command byte occurred. Remaining audio diagnostics name
  stock gurp sounds and an absent authored sounds/global/e_dripsc.wav. Water pain now
  uses supplied Hiro audio, and environmental protection refreshes the air reserve.
- [seq:46] Story-flow review found twenty authored exit `cinematic` bindings were not
  read, coop-only transitions were active in single player, and exits did not enforce
  their key requirement. Added the alternate cinematic key, mode/difficulty admission,
  keyed exits and immediate queued transitions. New campaign now starts at the supplied
  intro. Cinematic cleanup finishes before firing ending targets; unrelated movement
  remains active. Added full-map model variants and the supplied c_super naming for
  cine_superfly. These changes await connected intro/transition scenarios. Asset flag
  semantics were checked against private reference dk_sent.cpp and p_user.h; no source,
  headers, generated input or binary from that reference is compiled or copied.

- [seq:47] Reviewed all packaged cinematic task kinds and the missing cast identities.
  Added 16 fixed-order cinematic definitions, supplied model aliases and chapter-first
  model lookup (the extra e4m6c variants lack sequences used by e4m6 programs). Ignored
  unused finite allocator-fill operands while retaining numeric validation of active
  operands. Empty animation commands hold the pose; absent sequences name map/program,
  shot, actor, model and animation and hold instead of crashing. Sole-class fallback
  handles the supplied intro's oka1/osa1 identity disagreement without choosing between
  multiple actors. Private reference reads checked cast naming and task semantics;
  implementation, build and package inputs remain independent.
- [seq:48] /tmp/dk3-intro-timed-transition.log completes intro skip and follows the
  authored button/exit to e1m1a. Skip now advances timed actor queues within shot bounds:
  intro shot 80 has removals at 5.5 seconds beyond its 2.8-second cut, which must not run.
  The handoff screenshot/save commands reached the server before cgame was active, so
  they are not capture/save evidence. Full playback and an interactive handoff capture
  remain pending. The e2m5c/e4m2a/e2m4d client captures from seq:45 were inspected.
- [seq:49] /tmp/dk3-multiplayer-bots.log exercised DM bot joins, damage and a kill, but
  CTF/deathtag bots were spectators (team 3): native bot userinfo used team instead of
  ioquake3's teampref. Set explicit preferences and defer population maintenance until
  carried clients have reconnected. Added multiplayer team/spectator menu choices and
  a default userinfo preference; campaign/load actions reset it. Connected objective
  verification is running. Campaign difficulty labels now match Easy/Normal/Hard.

- [seq:50] Full intro playback under opengl2 initially trapped in
  RB_RenderDrawSurfList: /tmp/dk3-opengl2-intro-trap.log and disassembly show the
  incompatible-function-call sanitizer path through rb_surfaceTable. Replaced the
  function-pointer casts with uniform typed adapters in tr_surface.c, preserving
  instrumentation. /tmp/dk3-intro-renderer-fixed.log then plays intro, follows its
  authored exit to e1m1a and completes e1m1_cinestart. devmap enabled accelerated
  playback; no cinematic skip was used in this run. Captures dk3-intro-full-cast.jpg
  and dk3-intro-full-handoff.jpg were inspected; intro-full-progress and
  intro-full-handoff saves succeeded. This is cinematic/handoff evidence, not opening
  traversal or bridge acceptance. Missing authored animation names remain diagnosed.
- [seq:51] Team admission produces teams 1/2, but no objectives were scored in
  /tmp/dk3-multiplayer-teams.log. Added bounded bot_report routing output and exercised
  /tmp/dk3-multiplayer-routing.log. Bots were walking directly at remote flags:
  AAS_PredictRoute with maxareas=1 returns false for a useful partial route and never
  populates numareas. Both native bot and actor callers required those discarded
  results. A shared ground-waypoint query now accepts a completed first reachability;
  bots also request jumps for the corresponding travel flags. Verification pending.
  Supplied glyphs are normalized to 16 layout units; subtitle wrapping uses the same
  scale so small bitmap fonts remain readable. Rendered layout verification pending.

- [seq:52] /tmp/dk3-save-ui-scenarios.log restores a mid-intro save across maps and
  returns to the e1m1a handoff save. A checksum-corrupted copy is refused without
  replacing the running world. A directory at the pending-file path causes a named
  write failure and leaves the current save hash unchanged. A later successful write
  preserves the original as `.previous`; loading that previous record restores the
  original position. The readable HUD capture was inspected; large-HUD/menu captures
  remain available for inspection. These partial scenarios do not close all V7/V8.
- [seq:53] /tmp/dk3-interrupted-save.log stops the writer with SIGKILL after writing
  all 1,684,983 pending bytes but before synchronization/commit. Current and previous
  save hashes remain unchanged, compared with /tmp/dk3-interrupt-before.json.
  /tmp/dk3-interrupted-recovery.log then restores the intact current save in a restarted
  client, writes the same slot successfully, removes the stale pending file through
  replacement, and captures dk3-interrupted-recovered.jpg. Scenario commands used the
  normal load/save path; the startup console needs a running campaign before `load`.
- [seq:54] /tmp/dk3-teleport-landing-compile.log generates e1dt1 with 29 teleport
  reachabilities (previously 17). Adding only the one-unit TeleportPlayer offset left
  six destinations overlapping hull-expanded solid. The compiler and game now search
  upward within 64 units with point and player-hull clearance; the targeted compile
  has no destination-in-solid diagnostics. The superseded all-map generation was
  cancelled; final all-map regeneration remains pending. Existing installed assets
  and their saves remain preserved.
- [seq:55] /tmp/dk3-botlib-movement.log explicitly loads the rebuilt native module
  from a private override and exercises BotMoveToGoal instead of manual first-waypoint
  driving. Both teams join and bots traverse teleports, but deathtag objectives remain
  unscored. Raw AAS reachability inspection finds each bomb platform has only six
  predecessor areas, disconnected from spawn. Authored lifts redlifty/bluelifty are
  vertical func_door entities; BSPC's elevator pass admitted only func_plat. Extended
  that pass and botlib mover recognition to vertical doors. Waiting elevators report
  their blocking entity so native bots can approach and use authored physical controls.
  Bot movement initialization now signals teleport-bit changes. These changes await
  targeted navigation generation and client/server scenarios.

- [seq:56] /tmp/dk3-vertical-lifts-compile.log generates two elevator routes, model
  86 and 217, and 29 teleports. A directed reachability traversal from spawn area 4160
  now reaches both bomb areas 4634 and 1439. This confirms graph connectivity only;
  physical button use and lift riding remain under test. /tmp/dk3-ctf-botlib.log
  demonstrates both opposing flag pickups and a kill, then reliable server-command
  overflow drops each bot. Native bot thinking now consumes BotGetServerCommand as
  upstream bot clients do, acknowledging announcements/config changes. Replaying
  connected modes after that repair. Inspected readable-menu, large-HUD,
  interrupted-recovered and intro-restored captures; the restored intro is rendered,
  but individual shot composition is not fully qualified.

- [seq:57] /tmp/dk3-objective-course.log repeats deathtag and CTF after reliable
  command acknowledgement. CTF demonstrates repeated kills, respawns, opposing pickups
  and dropped-flag returns without command overflow; captures remain unproven.
  Deathtag bots correctly discover the remote lift-door switches, but their raw brush
  centers sit below the standing hull and behind separately controlled doors. Added
  bounded goal-approach samples, allowing dynamic mover obstacles to be discovered by
  normal movement while refusing solid-world goals. Carriers may route through the
  lava/slime their deathtag protection explicitly covers. Bot movement handles are
  released before map_restart preserves the library. Replaying these connected changes.
- [seq:58] /tmp/dk3-opening-traversal.log restores ion-encounter and traverses the
  eastern slope, river and western bank with normal turn/forward commands. A first
  attempt died while standing in combat; restoring opening-river and continuing
  movement preserves health 93. opening-bank-run and opening-west-slope save through
  the ordinary client command. This is partial e1m1a traversal, not exit/bridge proof.
  Inspected captures show the supplied terrain, weather and ion view model. Pause-menu
  input is used between control batches. A music warning repeatedly rejected the label
  of non-22-kHz audio even though RawSamples already resamples it; replaced that warning
  with validation of supported PCM rate/channel/width before streaming.

- [seq:59] /tmp/dk3-solo-objectives.log exercises a single red bot in e1ctf1. It
  picks up the blue flag, carries it through normal movement to the red capture
  zone, and repeats. Final status reports score 10 (two five-point captures), with
  no kills or forced scoring. This isolates the capture path from combat already
  exercised in seq:57. The following deathtag segment repeatedly abandons an active
  switch route after 15 seconds; stopped after that evidence and changed expiry to
  an inactivity deadline renewed by movement. Native objective actions and captures
  now enter the server game log for explicit scenario evidence.
- [seq:60] /tmp/dk3-lifts-corpus-assets.log finishes successfully with all 84 rebuilt
  navigation files and generation 7a259755a6f66b367bcbc34b8e9f8dd08451098cd168400adead91eda78794b5.
  Its e1dt1 log records both elevator links and 29 teleport links. The prior play
  installation remains current so its gameplay saves can continue to be exercised.
  Final installation of the regenerated assets remains pending.
- [seq:61] The first opening-traversal client reached its guard timeout while paused;
  its ordinary saves remained usable. /tmp/dk3-opening-traversal-west.log resumes
  opening-west-slope. An attempted pause during the asynchronous load cancelled
  connection; the scenario now waits for the actual restore message before pausing.
  From the restored position, normal input reaches (776,-2017,384) with health 93
  and writes opening-sign. dk3-opening-sign-alive.jpg was inspected. Opening exit
  and bridge acceptance remain open. No view-angle restore defect was established.

- [seq:62] /tmp/dk3-deathtag-progress.log gets to the remote switch area but drops
  the original goal when a nested door control succeeds. Preserve up to eight
  physical control dependencies, reject repeated control IDs, and resume the parent
  control after a child opens its obstacle. /tmp/dk3-deathtag-nested-controls.log
  then shows control 578 opening door 392, followed by control 89 opening its original
  obstacle. The bot remains at (78,1872,187) because that switch also activates a
  security monitor. Bot thinking now dismisses it through the same StopMonitor path
  as Use, respecting the authored minimum viewing time. Affected replay is running.
- [seq:63] Normal e1m1a movement/fire in /tmp/dk3-opening-traversal-west.log reaches
  the western slope and first pod. The player uses four ion shots while retreating
  from pursuit, retains health 64, then passes the pod with health 57 and 14 rounds.
  Saves opening-rise, opening-pursuit-combat, opening-pod-path and opening-past-pod
  succeeded. A transient black/white surface obscures one close pod capture; subsequent
  views are normal, and its cause remains unclassified. These captures do not claim
  that the pursuers or pod died. The path to the authored exit remains in progress.

- [seq:64] /tmp/dk3-deathtag-monitor.log confirms monitor dismissal but no score.
  Repeated Use kept pressed buttons from resetting, and the ten-second remote gate
  closed before the lone bot returned. Bots now wait for a button to reset before
  pressing it, and request an available teammate to operate distant controls.
  /tmp/dk3-deathtag-team.log demonstrates nested switches, monitor dismissal, lift
  traversal and the first native deathtag pickup (team 2, client 1). The carrier
  then stalls on the raised lift and its fuse explodes; no capture is claimed.
  Read-only debugger probes identify ground entity 196, model *86, MOVER_POS1,
  at player height 120.125. The AAS drop ends below that raised platform. Added
  physical lift-control seeking for this descent; replay is in progress.
- [seq:65] /tmp/dk3-opening-traversal-west.log reaches MAX_REFENTITIES in the
  western ridge. The world particle pool admits 2048 sprites but render entities
  are limited to 1023; actors and weapons share that capacity. Particle sprites
  now submit camera-facing polygons with the same corners/UVs and vertex color.
  /tmp/dk3-opening-exit.log restores opening-over-ridge and traverses the ridge,
  lower path and exit ramp with no render-entity overflow. Inspected captures
  ridge-particles-fixed, ridge-downhill, ridge-drop, path-ramp and exit-path.
  A flat gray transient view on the lower path remains unclassified. A delayed
  pause after initial restore allowed a death; restoring and pausing on the
  actual restore message resumed the recorded health-52 state. Normal movement
  takes nine falling damage, reaches (-838,-1483,475) with health 43 and ammo 14.

- [seq:66] The ordinary e1m1a exit in /tmp/dk3-opening-exit.log loads e1m1b and
  preserves health 43, ion weapon 2, inventory bitset 6, ammunition 14 and XP 50.
  It incorrectly chooses the from_c entrance at (-2048,1424,528.125): the named
  from_a landing exists only on supplied coop markers. Spawn selection now honors
  a matching named marker after searching single-player starts, prefers a flagged
  default start when no entry matches, and diagnoses a missing named landing.
  The corrected authored exit is replaying from opening-exit-mouth.
- [seq:67] /tmp/dk3-deathtag-descent.log repeats pickup but seeking the lift switch
  below its raised platform does not resolve descent. Stopped after the repeated
  stall. The compiled ledge end (-297,-1400,8) is inside raised model *86; AAS
  omits the moving brush and the bot oscillates above it. Added bounded horizontal
  hull traces to a real platform edge and downward traces to a reachable landing,
  preserving collision and rejecting unsafe drops/hazards. Movement remains normal
  user commands. /tmp/dk3-deathtag-lift-edge.log is the affected replay.

- [seq:68] /tmp/dk3-bridge-progression.log replays the exit with the entry fix:
  e1m1b starts at from_a (-600,-1376,517.88), health 43, ion rounds 14, XP 50.
  dk3-e1m1b-from-a.jpg shows the correct tunnel. A temporary input controller follows
  the supplied ground waypoints using console turn/move commands and ordinary saves;
  it stops at death/collision and never changes player position directly. It reaches
  waypoint 61 but the rock turret's 70-damage projectile kills the health-43 player.
  Earlier waypoint saves retain the live state for replay; this is not bridge proof.
- [seq:69] Read-only debugger inspection of the rendered death reproduces NULL
  poly shader in CG_AddMarks: bloodMarkShader is zero while the supplied blood
  sprite shader is registered (421). Register the blood mark from that supplied
  shader. The first debugger attempt was terminated while a software breakpoint
  remained, causing SIGTRAP on resume; this is a probe-induced exit, not a game
  crash. Restarted from the preceding ordinary save. Subsequent debugger capture
  removed its breakpoints and detached normally. The mark repair awaits replay.

- [seq:70] /tmp/dk3-bridge-combat.log follows the eastern approach through supplied
  ground nodes 7 and 8, avoiding the earlier frontal rocket hit. The pursuing skeet
  blocks a return to node 9; ordinary aimed ion fire kills it, increasing XP from
  50 to 100. bridge-skeet-aimed retains health 17 and five rounds. Several earlier
  shots missed; these runs do not establish weapon accuracy or complete the encounter.
  A later advance dies to the turret. The authored shootable switch is model *24,
  health 100; its target destroys the turret support and removes the turret.
- [seq:71] Inspection of supplied entity descriptions establishes that targeted
  func_explosive brushes are not shootable. The runtime previously allowed damage
  to every explosive, permitting premature scripted bridge destruction. Corrected
  targeted damage admission, trigger-spawn visibility, nonsolid/no-chunk flags,
  material selection and brush-centered radius damage. Also preserve single-player
  spawn classnames in ioquake3 so the flagged default start can be selected. These
  changes compile; their affected gameplay scenarios remain open.
- [seq:72] /tmp/dk3-deathtag-edge-diagnostic.log shows the proposed lift edges are
  either walls or the same upper floor, not a descent. Reject same-height landings.
  The nearby teleporter is behind a 16-unit step omitted from the AAS route.
  /tmp/dk3-deathtag-teleport-detour.log demonstrates a collision-checked ordinary
  approach/jump through teleporter 111 after route failure, reaching the opposite
  base with the bomb. It then stalls against another obstacle and the fuse expires;
  no capture. Added ioquake3-style validated sideways avoidance and cleared detour
  state on death; affected replay is pending.

- [seq:73] The next deathtag blocker is model *303, func_door without a targetname,
  identified by /tmp/dk3-teleport-destination-obstacle.log. It accepts the player's
  nearby Use action, but bot oscillation never reached the old inactivity check.
  Botlib's blocked-entity result now prompts nearby direct door use, with visibility,
  range and key checks. /tmp/dk3-deathtag-direct-door.log is the affected replay.
- [seq:74] Frame-counted keyboard turning varies with rendered frame duration during
  software rendering. Added dk3_look yaw pitch to set input orientation through the
  ordinary client command path, accounting for server delta angles; it does not move
  the player or edit world state. This supports repeatable aiming in the existing
  console-driven scenarios. /tmp/dk3-bridge-aim.log exercises argument validation
  and aiming in the live turret approach. Broad checks remain deferred.

- [seq:75] /tmp/dk3-deathtag-direct-door.log records the first complete blue bot
  capture: DK3Capture: 0 2 1 1, followed by the planted bomb explosion. A second
  attempt and dropped-bomb recovery repeatedly die to MOD_TRIGGER_HURT. The
  e1dt1 capture pit has lethal trigger brushes; BSPC classified them as lava,
  which the carrier travel flags admit. Compiler navigation now excludes both
  teams from unqualified trigger_hurt brushes using existing AAS team restrictions,
  preserving carrier access to actual lava/slime. /tmp/dk3-hazard-navigation.log
  records regeneration; /tmp/dk3-deathtag-hazards.log is the affected replay.
- [seq:76] /tmp/dk3-bridge-aim.log rejects dk3_look nan 0 and demonstrates a normal
  ion shot killing slaughterskeet 190 (health -10, experience 100 in
  bridge-skeet-single.sav). The low-health player dies on subsequent movement.
  Restarted from bridge-route-8 and moved west while evading the turret; campaign
  progression remains open. No NULL poly shader diagnostic occurred in these
  deaths after the blood-mark registration repair.

- [seq:77] /tmp/dk3-deathtag-hazards.log replaces lethal pit shortcuts with routes
  around them, then stalls at a physical door with zero botlib movement direction.
  Bot Use now traces the same 96-unit sight ray as player Use; sideways avoidance
  falls back to the goal direction when botlib supplies zero. The next replay
  passes those doors but stalls in a submerged route. Removed unconditional
  upward swimming input; /tmp/dk3-deathtag-swim-direction.log includes direction,
  view and velocity diagnostics for the remaining underwater failure.
- [seq:78] /tmp/dk3-bridge-traverse-west2.log reaches e1m1b's lower river through
  ordinary movement. It collects the western health pod (43 to 68), then reaches
  route node 65 with 44 health and 14 ion rounds before dying on the next approach.
  Authoring data specifies a 512-unit default rocket-turret radius, but the runtime
  fallback was 1200 and ignored sight/range overrides. Added persisted per-actor
  sight and turret range, firing interval, base and random damage. Gameplay save
  schema is revision 2; earlier native development saves get a revision diagnostic.
- [seq:79] /tmp/dk3-closeup-surfaces.log identifies the large white/gray obstruction
  as a camera-adjacent RT_SPRITE with shader 0, radius 15: CG_DamageBlendBlob's
  unregistered viewBloodShader. Registered the supplied blood sprite for damage
  feedback. Runtime presentation replay remains pending.
- [seq:80] /tmp/dk3-actor-settings-route.log restores opening-exit-mouth using the
  preserved independent revision-1 module, then crosses the actual e1m1a exit.
  Atomic module replacement before that normal map reload admits the current
  revision-2 module for a fresh e1m1b world. bridge-entry-revision2.sav records
  current actor settings and targeted explosives without shootable damage flags.
  This is continued native development evidence, not fresh-checkout acceptance.

- [seq:81] The turret fallback also selected the wrong attack family: optional
  reference review identifies monster_rockgat as a chaingun turret with default
  base/random damage 1/1 and interval 0.13, not a Sidewinder rocket launcher.
  Replaced the fallback with native hitscan rounds and supplied firing audio.
  /tmp/dk3-corrected-turret-route.log repeats the actual exit into a fresh world;
  bridge-chaingun-entry.sav confirms damage 1/1, radius 512 and interval 130 ms.
  The revised route reaches the west health-pod approach.
- [seq:82] /tmp/dk3-deathtag-input-projection.log shows upward swimming intent
  and pitch while vertical velocity remains negative. Inspection finds a malformed
  #endif in the shared bg_pmove.c ladder insertion: the trailing water-branch
  source was discarded by preprocessing. Submerged players consequently ran
  ground/air physics. Restored the missing branch and scanned modified engine
  C/headers for similarly malformed directives (none found). Both game and cgame
  rebuild from the corrected shared movement; affected water scenarios are pending.

- [seq:83] The first corrected-turret route reached the west health pod approach
  but its client exited on SIGILL (/tmp/dk3-corrected-turret-route.log). A replay
  under GDB with the shared water dispatch repair instead collects the pod and
  continues to the lower river (/tmp/dk3-health-approach-crash.log). The SIGILL
  cause is unresolved; the absence on this replay does not close it. Later normal
  ion combat kills a froginator (30 to 0 health, XP 50 to 80), followed by an
  ordinary jump up the blocked slope.
- [seq:84] /tmp/dk3-deathtag-water-fixed.log is blocked before the underwater
  section by bots emitting zero movement at course geometry. Progress monitoring
  now detects zero-input stalls and oscillation across frames, with bounded
  movement-state reset. /tmp/dk3-deathtag-progress-recovery.log exercises this
  recovery but still has no capture. Deathtag repeat/course acceptance remains
  open; no water-flow success is claimed from these runs.

- [seq:85] /tmp/dk3-health-approach-crash.log exercises ordinary health-tree Use:
  four available fruit restore health from 2 to 100, followed by combat damage
  to 92 (bridge-healthtree-restored.sav). The subsequent route collects an ion
  pack (13 to 53 rounds) and kills the river froginator through normal firing.
  Unattended walking dies in the river; bridge progression remains open.
- [seq:86] Botlib's empty, non-failing airborne result now leaves local movement
  available. /tmp/dk3-deathtag-air-recovery.log traverses the submerged blue course
  and records DK3Capture: 1 2 1 1 with the corrected water movement. After the
  objective resets, bots stall returning to its pickup. A diagnostic replay
  (/tmp/dk3-deathtag-body-stall.log) instead cycles at the blue lift controls;
  repeated captures and both-team acceptance remain open.
- [seq:87] /tmp/dk3-bridge-upper-route.log reproduces SIGILL during normal ion
  combat near the river turret. The optimized client module merges sanitizer
  traps: its reported cg_view.c step-smoothing line is not a reliable originating
  operation. The actual trap is a floating conversion check. Client-game builds
  retain distinct sanitizer sites to make the affected replay diagnostic.

- [seq:88] BSP brush probes at (343,-1472,120) and (295,-1649,96) identify ladder
  sides adjacent to the deathtag stalls. Shared ladder code previously attached
  on any nearby ladder and turned forward input into ascent regardless of facing.
  Attachment now distinguishes moving into, along, and away from the ladder.
  /tmp/dk3-deathtag-ladder-facing.log clears the earlier climbing cycle and records
  another blue capture; the later return route remains blocked below the pickup.
- [seq:89] Normal river combat kills the pursuing crox and two slaughterskeets,
  reaches level 2 and applies `attribute vita` (bridge-bank-clear.sav, XP 360).
  Later save attempts refuse entity 493, monster_froginator. A read-only extraction
  of the running serializer buffer (/tmp/dk3-refused-river-snapshot.bin) records
  origin (-2316,-242,-1109963), velocity z -42160, health 30. Its authored origin
  intersects the assigned floor hull; actor physics previously advanced an
  all-solid trace and fell through it. Added bounded clear-space recovery, refusal
  to advance solid sweeps, and a named out-of-world diagnostic/removal. Fresh-map
  physics and save/load replay follow this repair; old traversal is partial evidence.

- [seq:90] /tmp/dk3-actor-floor-probe.log runs a fresh e1m1b dedicated world and
  inspects frogs at normal shutdown: actor 493 rests at (-2316,-242,474) with
  zero velocity and 30 health. Other listed frogs also rest in the map. The
  continued client restores bridge-bank-clear, reports/removes its already-lost
  actor 493, and successfully saves through bridge-route-126 and another frog
  kill (/tmp/dk3-bridge-hull-fixed.log). This continued save is not evidence of
  fresh campaign completion; the fresh spawn probe separately covers the repair.
- [seq:91] Offline inspection of e1dt1 AAS area 5422 reaches only 92 areas even
  with unrestricted travel; none reaches objective area 4611. The returning bots
  had fallen into this region through direct fallback steering. Item selection
  now requires reachable goals and local fallback/stall recovery uses ioquake3
  BotMoveInDirection collision and hazard prediction with a retained direction.
  /tmp/dk3-deathtag-safe-recovery.log records the affected replay.

- [seq:92] Bot goal points now remain inside their selected reachable area;
  final item approaches preserve trigger overlap instead of replacing a validated
  point with an unchecked center. /tmp/dk3-deathtag-goal-area.log exposes a carrier
  blocked by its teammate until detonation. Added normal-input teammate yielding;
  /tmp/dk3-deathtag-teammate-yield.log captures once, then still stalls returning.
- [seq:93] BSPC's Q3 reader stripped ladder contents without reconstructing the
  supplied SURF_LADDER faces. The prior e1dt1 AAS had zero ladder links. The fixed
  reader generates 521 (/tmp/dk3-ladder-navigation.log). Offline graph traversal
  from the previously isolated lower pickup region now reaches the team objective
  (new area 5423 to 4624). /tmp/dk3-deathtag-ladder-routes.log exercises this file;
  bot course completion remains open. All-map regeneration is still pending.
- [seq:94] /tmp/dk3-bridge-approach.log reaches the bridge by normal river/ramp
  movement after using the northern health tree. Crossing the bridge enters the
  authored event generator: bridge-triggered.sav records event cursor 3 of 16,
  one destroyed section and pending staggered destruction/beam relays. No forced
  event or level command is used. Arrival/combat and rendered destruction checks
  continue from this checkpoint.

- [seq:95] bridge-arrivals-early.sav records staggered mosquito pairs and all
  three bridge pieces unlinked. bridge-thunderskeet-arrival.sav records all ten
  named Skeet1a/b through Skeet5a/b and the moving thunderskeet; bridge-aggressive.sav
  records cleared ignore-player states and thunderskeet attack animation with
  player 1 as its enemy. Rendered captures show formation, broken bridge and
  close combat. The stationary observer loses health; combat completion and a
  fresh opening-to-bridge replay remain open. No forced spawns/targets are used.
- [seq:96] The updated AAS still excludes the physically standing bot position
  (315,-1142,40), while usable areas exist 48–64 units away. Added bounded ordinary
  input recovery with player-hull step/ground traces, hazard rejection, and a
  real AAS endpoint. /tmp/dk3-deathtag-area-recovery.log exercises it; full repeated
  course and both-team acceptance remain open. Route diagnostics distinguish
  botlib routing from local recovery.

- [seq:97] Ordinary aimed ion fire defeats the 600-health thunderskeet, earns
  level 3 and triggers its death targets (bridge-boss-aim-9.sav). The supplied
  megashield death drop appears. The rendered encounter and boss fight are
  observed; the lower exit route and fresh complete opening replay remain open.
- [seq:98] /tmp/dk3-deathtag-area-recovery.log records two blue captures, including
  objective reset and return through the switch/lift route. The helper then
  selects a C4 pickup in a one-way dry pocket: area 5424 can reach 28 dry areas,
  but escaping requires slime travel. Optional pickup/wander selection now checks
  a return route, preventing an unprotected bot from deliberately entering this
  dead end. Objective course behavior and both-team replay continue separately.

- [seq:99] /tmp/dk3-deathtag-red-return-routes.log records two red captures by
  different carriers, with objective reset, bomb detonation, death and respawn.
  /tmp/dk3-deathtag-contested-routes.log adds opposing bots and exercises damage,
  dropped objectives, returns and captures. Temporary teammate blocking remains
  visible in the contested run and is not counted as passing yielding acceptance.
- [seq:100] The ordinary level-gain center message renders beyond both screen
  edges and the inherited 50-character renderer discards its remaining text
  (dk3-bridge-exit-attempt.jpg). Native center messages now use supplied font
  metrics, viewport wrapping and HUD scaling. Subtitles share the wrapper, which
  retains characters when splitting a long word. /tmp/dk3-message-layout-build.log
  passes; rendered long-message and scale checks follow.
- [seq:101] After the boss death, ordinary movement and disruptor combat collect
  its megashield drop (bridge-shield-pickup.sav: armor 194, XP 1160). An earlier
  attempt to leave without collecting the shield dies to pursuers; this is a
  recorded combat outcome, not evidence of a traversal defect.

- [seq:102] The completed contested e1dt1 replay records three blue captures and
  one red capture, alongside opposing damage, kills, respawns, carrier drops and
  bomb detonation/reset (/tmp/dk3-deathtag-contested-routes.log). This establishes
  running objective flows for both teams; network clients and robust teammate
  yielding remain separate open checks.

- [seq:103] The ordinary lower exit reaches e1m1c from e1m1b with health 25,
  armor 124, ion ammunition 3, XP 1160 and level 3 preserved
  (e1m1c-authored-entry.sav; /tmp/dk3-bridge-approach.log). This continued traversal
  still does not replace the required fresh opening replay.
- [seq:104] Supplied e1m1c worker programs request aaeaa, absent from the supplied
  skinny-worker model's 73 sequence records and frame names. The interpreter now
  diagnoses this missing visual clip and continues subsequent commands instead
  of cancelling the complete job. Re-entering by the authored exit with the fix
  records actor 148 playing aafaa frames 19–32 and its pending WRKRralph_clip1 job
  (e1m1c-script-repaired-entry.sav; /tmp/dk3-bridge-onward.log).
- [seq:105] /tmp/dk3-network-{server,client}.log records a real UDP client joining
  127.0.0.1:27961, movement, firing, ordinary suicide/respawn, scoreboard snapshots,
  disconnection and reconnection. A controlled loopback challenge peer reports
  protocol 68; dk3 rejects it with the expected matching-build instruction.
  The initial UI hid com_errorMessage. The repaired UI displays a wrapped error
  panel (dk3-network-protocol-visible.jpg), with dismissal and scrolling controls.
  HUD scale 0.75 and 1.5 captures keep all four statistics visible at 960x540.

- [seq:106] Real keyboard input exercises Join with a typed localhost:27961 address,
  connection-error dismissal, and Host. The first Deathtag host selects e1ctf1
  because shared objective class names caused the catalog to advertise CTF maps
  as both modes. Catalog generation now recognizes the authored e1dt1 course.
  The corrected menu starts e1dt1 with NetworkPlayer and three bots
  (/tmp/dk3-network-host-menu.log; dk3-corrected-host-{menu,match}.jpg).
- [seq:107] Replaying the ordinary final thunderskeet shots produces the full
  wrapped level-gain instructions at HUD scale 1.5 and 960x540
  (dk3-level-message-large.jpg). The visible protocol error panel is dismissed
  with Return and the Join flow succeeds afterward. These checks cover those
  concrete paths, not the remaining subtitle, LAN or favorites scenarios.

- [seq:108] Full private 1.3 asset regeneration completes with the corrected map
  catalog and ladder/hurt-volume AAS compiler inputs. Generation
  a13b55b4223a3fef06ff17539d8e37fd88b64921872c70f8db1ec8f82218b19a
  contains the 84-map navigation package (/tmp/dk3-ladders-catalog-assets.log).
  The existing play installation stays in place for checkpoint continuity; this
  result does not claim fresh-install or full navigation acceptance.
- [seq:109] Ordinary movement, jump, disruptor combat and ion pickup reach the
  e1m1c canal (e1m1c-canal-climb.sav: 43 ion rounds). Direct Use incorrectly
  opens named lockeddoor entity 203, reserved for an authored trigger. Player
  and bot interaction now share a check that preserves named target chains,
  allows physical buttons and excludes touch triggers. Named automatic doors
  also retain their remote activation requirement. The attempted shortcut is
  not campaign progression evidence. Verification follows.

- [seq:110] Restoring the pre-use canal checkpoint with the interaction repair,
  facing the door and issuing Use produces “This is operated elsewhere.”
  e1m1c-locked-use.sav retains entity 203 in MOVER_POS1. Supplied map data
  connects destructible brush *29 to t103, whose six-second action opens the
  door. The positive authored-trigger scenario remains pending.

- [seq:111] The corrected direct-use build completes a blue deathtag capture in
  /tmp/dk3-deathtag-yield-fixedtime.log; the broader both-team acceptance must be
  refreshed after this progression fix. The reported teammate stall did not
  recur in these diagnostic replays, so yielding is still unqualified.
- [seq:112] Native damage previously emitted MOD_UNKNOWN for every weapon.
  Direct, splash and status damage now carry explicit native weapon causes.
  /tmp/dk3-damage-causes-client.log and the private damage-causes.log record
  C4 Vizatergo and Shotcycler-6 kills; the client displays the corresponding
  weapon names. A human killed by the bot's Shotcycler respawns through ordinary
  attack input (dk3-damage-causes-respawn.jpg). Suicide/environment causes retain
  their existing values. /tmp/dk3-damage-cause-build.log passes.

- [seq:113] A 1,369-file explicit source copy in /tmp/dk3-independent-checkout
  builds with zig build -j4 inside a bubblewrap filesystem containing /usr, /etc,
  /proc, /dev, private /tmp and the source copy. The reference workspace and
  prior compiler caches are unavailable, network access is isolated, and no
  assets are present. /tmp/dk3-independent-build.log completes successfully.
  This qualifies the default native compilation path; optional QVM compiler
  qualification and the full publication/provenance gate remain open.

- [seq:114] The isolated dedicated executable initially refuses startup without
  default.cfg, as expected. Generating the original base package from the isolated
  source copy provides it; /tmp/dk3-independent-server-base.log then reaches
  Common Initialization Complete and exits successfully. No game assets or
  reference files are mounted for either conversion or startup.
- [seq:115] Continued e1m1c play crosses the pool, climbs the eastern ramp, kills
  its pursuing mosquito, and uses the upper health tree
  (e1m1c-upper-tree.sav: health 120, ion ammunition 43). Authored monster-node
  centers do not provide every player route; the following input probe uses
  compiled AAS waypoints as navigation hints with ordinary view/movement input.

- [seq:116] The e1m1c upper-route probe exposed a navigation/world mismatch.
  World-brush collision has a gap at (480, 2278); brush model *28 is the ramp,
  carried by a func_wall with spawnflags 24576 (excluded on normal/hard).
  The normal-difficulty save correctly omits that wall. BSPC nevertheless uses
  its deathmatch func_wall rule, building continuous WALK reachabilities through
  it. This is a navigation compilation defect, not missing game collision.
  Explicit BSPC difficulty/mode filtering, deduplicated AAS variants and native
  selection metadata are implemented; targeted compilation and profile probes
  follow. No modified game geometry or save-state editing is used.

- [seq:117] zig build navigation-compiler game -j4 passes in
  /tmp/dk3-navigation-modes-build.log. The e1m1c conversion emits three distinct
  AAS files for six selections: normal/hard share one, DM/CTF/deathtag another.
  At (480, 2280, 550), easy has a grounded area and normal an air area; at z520
  easy is inside the ramp and normal is air. Runtime /tmp/dk3-e1m1c-mode-input-client.log
  selects and loads e1m1c-normal.aas both before and after ordinary save restoration.
  This probe uses a private navigation-package overlay with unchanged BSP bytes;
  full package regeneration is running. Engine input diagnostics build passes in
  /tmp/dk3-input-diagnostic-build.log. cl_debugMove 3 only reports input changes.

- [seq:118] cl_debugMove 3 confirms ordinary jump input and shared movement: a
  standing jump rises, while the failed late takeoff starts after stepping off
  the beveled ledge. A walking approach, earlier takeoff and air braking cross
  the normal-difficulty gap (e1m1c-braked-jump-gap.sav, grounded at
  417.54/2278.63/560.125, health 43). Normal input then reaches the upper control
  platform. Two upper froginators are defeated; the ion-ammunition pickup is
  collected. Four ion impacts break entity 201 and start t103's authored event
  sequence (e1m1c-explosive-broken.sav); the timed door observation follows.

- [seq:119] Full navigation conversion found empty spawnflags on e4m2a weather
  volumes. The variant planner now treats an empty numeric field as zero, as
  the runtime does, and groups only brush classes used by AAS_ValidEntity.
  BSPC distinguishes an explicitly empty mode key from an absent key. The
  targeted compiler build passes in /tmp/dk3-navigation-empty-flags-build.log.
  The corrected full conversion is in /tmp/dk3-navigation-modes-assets-repair.log.

- [seq:120] t103 activates the canal door after the explosive breaks, but the
  positive opening scenario fails: both e1m1c-remote-door-moving.sav and the
  later e1m1c-remote-door-open.sav retain MOVER_1TO2, zero rotation and a
  continuously postponed trajectory start. The latter slot name describes
  the attempted scenario, not a successful opening. The killtarget doorstop
  is absent as required. Mover blocker tracing is added under developer 2
  to identify the entity responsible before repairing forced movement.

- [seq:121] Mover tracing identifies ammo_ionpack 473 at 408/2736/400 as
  the false blocker for rotating canal door 203. G_MoverPush used a whole-world
  position test after its conservative rotating bounds test, so a pickup already
  overlapping unrelated map geometry could stop a distant door. The dk3 branch
  now uses trap_EntityContact against the moving brush for non-riders; rider
  handling and real push collision remain intact. The game build passes in
  /tmp/dk3-mover-contact-build.log. Replaying e1m1c-explosive-broken through t103
  produces e1m1c-canal-door-repaired.sav: door 203 reaches its stationary 85-degree
  endpoint and pickup 473 retains its original position. Physical traversal follows.

- [seq:122] The complete mode-aware navigation conversion passes in
  /tmp/dk3-navigation-modes-assets-repair.log, generation
  bb8bff4ad133fcd44eed35b0857e92877b78d3afcb8a83469734b04994d3f4ea.
  It contains 84 selection files and 97 distinct AAS products. This qualifies
  conversion, not all actor/bot routes; the campaign continuation still uses
  its recorded prior installation plus the private e1m1c navigation overlay.

- [seq:123] A screenshot exposed a blank 32-pixel debug graph covering HUD
  values when cl_debugMove 3 was enabled. SCR_DrawScreenField treated every
  movement diagnostic mode as graphical. It now draws that graph only for
  modes 1/2 (or explicit graph cvars); mode 3 remains textual. The targeted
  engine build passes in /tmp/dk3-input-overlay-build.log. Disabling the old
  process's diagnostic restores the full HUD immediately; the updated engine
  will be inspected on the next client launch.

- [seq:124] The rebuilt engine keeps the entire HUD visible with cl_debugMove 3
  (dk3-e1m1c-debugmove-hud.jpg, /tmp/dk3-e1m1c-canal-client.log). Continuing the
  canal route with ordinary input defeats submerged froginator 278 with an ion
  hit (25 to -5 health), retaining 7 player health in e1m1c-canal-frog-close.sav.
  Water jumping reaches the bank; traversal to the opened doorway is in progress.

- [seq:125] The repaired canal doorway is physically traversed in both
  directions with normal player input (/tmp/dk3-canal-door-passage.log and
  /tmp/dk3-canal-health-return.log). The route reaches 538/2699/408 beyond
  the door, defeating froginator 169 there; e1m1c-canal-door-frog.sav retains
  7 player health. Froginator 527 is also defeated and its in-flight attack
  dodged in e1m1c-canal-bank-frog-dodged.sav. Returning along the bank reaches
  the earlier health tree at 160/1752. This closes the specific timed-door
  regression, not e1m1c progression or the wider movement acceptance gate.

- [seq:126] Continued authored e1m1c traversal climbs the long eastern ramp,
  clears its froginator/mosquito encounters, rounds the upper courtyard corner
  and reaches health tree 499. The private input helper now stops when incoming
  damage interrupts an approach and refuses stale checkpoints after failed saves.
  e1m1c-upper-corner-dodge.sav records an ion kill and dodge at 3 health;
  /tmp/dk3-canal-ramp-route.log, /tmp/dk3-upper-ramp-progress.log and
  /tmp/dk3-upper-health-arrival.log retain route inputs/results. After clearing
  the courtyard attacker, ordinary health-tree use across its regeneration cycles
  restores health to 120 with 30 ion ammunition in e1m1c-courtyard-rested.sav.
  The canal client subsequently ends with dkguard's configured timeout, not a
  crash; continuation uses /tmp/dk3-e1m1c-courtyard-client.log. The lift and
  remaining e1m1c progression are next; no campaign gate is closed by this run.

- [seq:127] Door 185 correctly blocks the upper courtyard passage until its
  authored explosive control is destroyed. Normal movement reaches the exposed
  control at 2002/1452/900; two ion impacts reduce its 50 health below zero,
  remove rockgat 195 through killtarget killmegat, and start the door/earthquake
  target sequence. e1m1c-turret-control-broken.sav records the broken control,
  absent turret and moving door; its rendered capture shows the control removed.
  /tmp/dk3-turret-control-route.log and /tmp/dk3-e1m1c-courtyard-client.log
  retain the normal input flow. Passage and lift observation follow.

- [seq:128] Walking toward unnamed lift 290 reproduces a boarding failure:
  e1m1c-lift-walk-on.sav has the lift at its upper stop while the player remains
  on world ground at 2206/1463/848. Its return timer is continually renewed.
  DK_RunMovers applied the door's 48-unit proximity expansion to platforms,
  launching before boarding and including a waiting player below the upper stop.
  Automatic platforms now require an actual player/actor ground-entity rider
  to start or hold the platform. Named controls and door proximity retain their
  separate behavior. The same walk-on sequence is being replayed after the
  targeted game build; return/boarding acceptance remains open until observed.

- [seq:129] The repaired module builds successfully in
  /tmp/dk3-lift-boarding-build.log. The same ordinary walking input now boards
  lift 290: e1m1c-lift-walk-on-repaired.sav has the player grounded on entity
  247 at the upper stop, with health unchanged at 59. Dismounting onto the
  upper landing lets the empty lift return to -112 (e1m1c-lift-return-repaired).
  e1m1c-lift-midride.sav captures the ascending trajectory at -84.99 and its
  rider reference; ordinary load continues to the upper stop, retaining 59
  health and the rider reference in e1m1c-lift-midride-restored.sav. Rendered
  captures and /tmp/dk3-e1m1c-courtyard-client.log retain the results. Other
  platform/companion/multiplayer scenarios remain unqualified.

- [seq:130] Upper walkway doors 285/286 correctly require button 287 across
  the room. Normal walking and use activate its monitor view, delayed target1c
  door pair and target1b exit gate. e1m1c-door-pair-control.sav preserves the
  active monitor and moving doors; e1m1c-door-pair-open.sav has the pair at
  +90/-90 degrees and exits the monitor after its authored lock interval.
  The rebuilt lift boards again with normal forward input, retaining 59 health
  and ground entity 247 in e1m1c-control-lift-boarded.sav. An earlier short
  input stopped outside the lift; subsequent movement beneath it caused crush
  damage. The ordinary pre-approach checkpoint was restored for continuation.
  Physical upper-door passage and remaining e1m1c progression follow.

- [seq:131] Physical passage through the opened upper doors succeeds in
  /tmp/dk3-walkway-after-worker.log. Froginator 532 is defeated; civilian
  worker 426 blocked the narrow approach and was killed with normal ion fire
  after side-passage attempts failed. Peaceful passage there is unqualified.
  The upper liftmaster button exposes another pusher defect: lift 188 reverses
  on stationary health pickup 277 before reaching its lower stop. Native static
  pickups use collection bounds, yet the pusher admitted them as physical bodies.
  The candidate filter now retains actors, players and physicsObject drops while
  excluding stationary dk3 pickups. /tmp/dk3-stationary-pickup-mover-build.log
  passes. Replaying the same button input reaches offset -290 without health
  loss or moving pickup 277 (e1m1c-liftmaster-pickup-repaired.sav). Dismounting
  collects health and ion ammunition and defeats lower froginator 233;
  /tmp/dk3-bottom-lift-items.log retains the flow. Exit approach continues.

- [seq:132] The authored e1m1c exit reaches e1m2a after the lower mosquito,
  froginator and crocodile encounters. /tmp/dk3-crox-corner-fire.log records
  the crocodile's 150 health reduced to zero; /tmp/dk3-e1m1c-exit-final.log
  reaches the opened exit gate. The first transition fails when cinematic-only
  cine_gusagi is spawned: its supplemental definition lacked the sight defaults
  enforced by actor validation. Supplemental cast definitions now initialize
  sight/FOV like ordinary actors. The same run exposed doubled/backslash/leading
  separators in mover sounds. DK_SoundIndex now normalizes separators before
  prefixes, and movers, scripts and cinematics share that resolver.
  /tmp/dk3-e1m2a-entry-repair-build.log passes. Replaying from the ordinary
  pre-exit save reaches e1m2a's cinematic with cine_gusagi alive and the known
  mover sound load failures absent. e1m2a-authored-entry.sav preserves player
  health 7, ion ammunition 53 and level 4 across the authored transition.
  Cinematic playback/cleanup and further e1m2a progression remain in progress.

- [seq:133] Campaign continuation now overlays the complete regenerated
  navigation package (97 AAS products, 84 selection files), SHA256
  61518d44fb66f6ce88b08a373d1fa25598b7fdb8d515639e51a1abe90a6775a9,
  from generation bb8bff4ad133fcd44eed35b0857e92877b78d3afcb8a83469734b04994d3f4ea.
  It replaces the private e1m1c-only overlay at
  /tmp/dk3-native-bringup-data/dk3/zz-dk3-navigation-profile.pk3. The recorded
  installation identity and other packages remain at generation 4a4d3556.
  A complete fresh installation/replay remains separate acceptance work.

- [seq:134] e1m2_cinestart plays through after ordinary restoration of
  e1m2a-cast-save.sav. Captures show Hiro, the chapter-specific cinematic
  Gusagi actor and the camera sequence; e1m2a-cinematic-finished.sav has
  camera inactive, health 7 and normal gameplay control. The supplied program
  also contains globa/a_speedwhoosh.wav beside its correctly spelled use.
  The media resolver now maps that exact missing identifier to the supplied
  global/a_speedwhoosh.wav only when the latter exists; replay is pending.

- [seq:135] A multiline console batch truncated a screenshot name and issued
  its trailing characters as a command. ioquake3's non-TTY CON_Input discarded
  the last byte of every read, assuming each read ended at a newline. The
  bundled implementation now buffers a partial line, returns complete lines,
  accepts a final EOF line and rejects oversized lines without executing them.
  The engine/game build passes in /tmp/dk3-console-cinematic-audio-build.log;
  the corrected file-existence check builds in /tmp/dk3-cinematic-audio-alias-build.log.
  /tmp/dk3-console-input-probe.py passes against the real dedicated executable
  under dkguard, covering fragmented input, 40-line bursts, CRLF/blank lines,
  oversized rejection and EOF without newline. Its log is
  /tmp/dk3-console-input-probe.log. The rebuilt client continues from the
  mid-cinematic save in /tmp/dk3-e1m2a-client.log.

- [seq:136] The rebuilt client resolves the supplied speedwhoosh typo and
  completes e1m2_cinestart without that sound load failure. The multiline
  capture commands retain their names. The blind post-cinematic waiting probe
  then leaves the 7-health player idle until approaching mosquitoes kill him;
  e1m2a-ready is not a valid save. Continuation uses the earlier ordinary
  e1m2a-cinematic-finished save, which has camera inactive and no remaining
  cine_ actors. Its old unused configstring still names the pre-fix typo.
  Normal movement climbs the entry slope to -2511/-20/-740 through the
  cinematic's delayed opening sequence, preserving 7 health and 53 ion ammo
  in e1m2a-aas-3002. /tmp/dk3-e1m2a-start-passage.log records that approach.

- [seq:137] Ordinary ion combat defeats both e1m2a entrance mosquitoes,
  leaving 2 health and 49 ion ammunition. The authored south stair approach
  reaches the first button-controlled train; the earlier north approach was
  against a wall, not a movement defect. A normal jump exits the rising train
  onto the upper landing at -1498/-344/-344. The corresponding save is
  e1m2a-first-lift-jump-exit.sav. Walking dismount returned to the lower stop;
  its timing/geometry remains unqualified, with no speculative mover change.
  Continuation targets health supplies through the upper rooms.

- [seq:138] e1m2a's upper rooms, two froginators and use-operated door are
  traversed through normal inputs. Disruptor melee defeats the doorway frog
  without losing the remaining 2 health; earlier ion attempts die to attacks
  or close ricochets and are not port-defect claims. Button 180 starts the
  authored t10 event and monitor; sewer1's five parts reach 88/45-degree
  rotations and a -78 translation. e1m2a-sewer-open.sav and rendered captures
  preserve this progression. Use dismisses the monitor after its wait.

- [seq:139] The running world repeatedly reports train 302 blocked by dead
  worker 90 at -1034/1197/-744. Native MoverBlocked now removes unpushable
  dead actors, following ioquake3's Blocked_Door handling of remains;
  living/downed actors keep ordinary crush/reversal behavior. The targeted
  game build passes in /tmp/dk3-crushed-corpse-build.log. Ordinary restoration
  and continued simulation produce e1m2a-corpse-train-repaired.sav: worker 90
  is gone, train 302 has moved from Z -710 to -216 and is moving, and saving
  succeeds. /tmp/dk3-e1m2a-client.log records the failure and replay.

- [seq:140] /tmp/dk3-bot-yield-current.log reproduces deathtag teammates
  stationary together on the ramp: bot 2 at -100/-506/125 reports yielding
  with zero input while carrier 3 stays blocked behind it. LocalMove's
  explicit stand result was counted as successful yielding. The repair only
  marks an actual movement as yielding and reuses bounded hull/ground/hazard
  checks for a short retreat when botlib supplies none. The endpoint must
  retain a return route. /tmp/dk3-bot-grounded-yield-build.log passes;
  the affected match replay remains pending.

- [seq:141] The e1m2a sewer hatch and pump chamber are traversed by normal
  inputs. The stationary paddle requires the outer ledge at Y 326; the
  direct AAS line passes through it. The eastern slide assembly remains
  locked to its controls, so progression follows authored ground nodes
  107/40/41/90/89/91 through the northern descent. Froginator 281 is defeated
  in e1m2a-drain-single-shot.sav with 2 health remaining. Continued attempts
  die to the next mosquitoes. No balance/movement changes are based on these
  combat losses. Continuation restores the ordinary e1m1c-aas-2543 checkpoint
  to restock from health tree 265 before replaying e1m2a's known route.

- [seq:142] /tmp/dk3-bot-yield-grounded.log completes two blue captures but
  does not reproduce the earlier teammate obstruction. A replay with game
  initialization seed 7 set by the private GDB probe also captures twice
  (/tmp/dk3-bot-yield-seed7.log); seed control changes no positions or goals.
  The corresponding red-only pair repeatedly stalls near 109/963/35 while
  botlib returns no usable recovery direction. Supported local recovery now
  also applies after ordinary botlib stall recovery fails, retaining hull,
  ground, hazard and return-route checks. The targeted game build passes in
  /tmp/dk3-bot-supported-recovery-build.log. Specific yielding and red-course
  repair acceptance remain open pending the same-input replay.

- [seq:143] The e1m1c resupply replay defeats both ranged frogs after moving
  around the fallen mosquito obstructing the ion shots. Normal health-tree
  use/recharge restores 110 health in e1m1c-restocked-complete.sav. The
  authored exit preserves that health into e1m2a-restocked-handoff.sav;
  the ordinary cinematic skip is exercised on this replay. The entry corridor,
  south stairs and timed first-lift jump reach the upper rooms. The latest
  valid lift checkpoint is e1m2a-restocked-lift-jump.sav. Earlier failed
  dismounts are input timing evidence, not a claimed mover defect.

- [seq:144] The red-only bot replay still stalls after the direct-before-step
  local recovery change (/tmp/dk3-bot-clearance-red-seed7.log). The focused
  debugger trace /tmp/dk3-bot-reach-loop.log identifies repeated e1dt1 links
  5056/5078 to area 2703, whose endpoints lie outside that area, and a related
  link into a phantom AAS floor above actual BSP support. BSPC step generation
  now tests real BSP/static-model clearance and landing support, samples
  alternative crossings along the overlapping edges, and uses botlib's initial
  four-unit upward area probe when conservative AAS bounds cover a real floor.
  Static collision uses the same eligible models and rotating-door placement
  as AAS construction. The e1dt1 package has 6,858 areas and 11,686 links;
  both objective areas remain reachable, and the observed false step links
  are absent. /tmp/dk3-supported-step-compiler-build.log and
  /tmp/dk3-supported-step-conversion.log pass. Only e1dt1 is regenerated so far;
  full variant regeneration and campaign navigation refresh remain open.

- [seq:145] Native bot recovery no longer resets all botlib movement state
  every three seconds, which erased failure history before five-second walk
  links expired. /tmp/dk3-bot-retain-red.log progresses beyond the repeated
  stall through the submerged red course, but its bomb expires before capture.
  The newer four-bot replay reaches both courses and exposes a separate blue
  barrier failure. /tmp/dk3-bot-jump-recovery.log captures recovery replacing
  an actual upmove 127 with a non-jumping recovery at -1942.1/-433.0/-119.8.
  Recovery now preserves planned upward input. The targeted game build passes
  in /tmp/dk3-bot-preserve-jump-build.log; the affected match replay is running.
  Multiplayer completion is not claimed.

- [seq:146] Dedicated diagnostic replays now set the actual fixedtime cvar
  to 50 and timedemo to 1 through the private GDB initialization probe, with
  seed 7. This removes wall-clock pacing while retaining 50 ms simulation
  steps and normal bot user commands. Earlier +set com_fixedtime 50 spelled
  an unused cvar and did not fix simulation timing. The current probe is
  /tmp/dk3-bot-fixed-step.gdb; no position, objective or health is injected.

- [seq:147] /tmp/dk3-preserve-jump-blue-pair.log now shows actual repeated
  barrier jumps, but still no blue capture. The existing barrier-jump links
  near -1943/-425 target another unsupported AAS surface. An experimental
  extension of BSP landing checks to barrier links removes that loop but
  disconnects the blue objective; it is retained only in
  /tmp/dk3-barrier-reach-experiment.c and is not the admitted compiler change.
  The canonical compiler retains the supported-step repair with both objective
  routes reachable. Bot jump preservation and retained failure history remain
  admitted. Barrier-route repair and complete objective acceptance stay open.
  The targeted restored compiler build is /tmp/dk3-supported-step-final-build.log.
  No broad checks or full navigation regeneration have been run during repair.

- [seq:148] The resupplied campaign replay opens the upper use-door, physically
  presses button 180, observes/dismisses its sewer monitor, and crosses the
  opened hatch. e1m2a-restocked-sewer-complete.sav retains that operation;
  e1m2a-aas-3251.sav is the pump approach after ordinary mosquito combat.
  These are normal movement, use, firing and save commands. The driver must
  allow the new view angle to reach the server before issuing Use; batching
  both immediately caused missed button rays, not a verified button defect.

- [seq:149] The restocked e1m2a replay completes the northern descent, lower
  cart controls, ride and lower return corridor. e1m2a-aas-4015.sav is the
  control-room checkpoint. A mosquito obstructed the cart rider and caused
  crushing in the idle replay; ordinary ion combat clears it, after which
  e1m2a-lower-cart-stop.sav records the authored stop with 88 health.
  /tmp/dk3-cart-combat-next.log and /tmp/dk3-lower-return-puzzle.log retain
  the combat and traversal evidence. No mover change was made for this case.
- [seq:150] Unoptimized AAS inspection isolates e1dt1's false barrier floor:
  area 6016 extends the plane of BSP brush 1397 beyond that brush's clipping
  sides. BSPC surface matching omitted untextured sides as partition planes.
  Its existing -forcesidesvisible option removes the phantom floor and
  produces 8021 areas, 13865 reachabilities and 29 clusters. navigation.py
  now supplies that option and includes compiler options in resume identity.
  /tmp/dk3-all-sides-blue-pair.log and /tmp/dk3-all-sides-red-pair.log each
  record two captures; the production optimized package gives both teams a
  capture in /tmp/dk3-all-sides-four-bots.log. These are ordinary bot inputs
  with seed 7 and fixed 50-ms simulation. Full navigation regeneration runs
  under /tmp/dk3-all-sides-navigation.log; broader acceptance remains open.
- [seq:151] The lower control-room button activates the authored slide event
  and its monitor. e1m2a-slide-activated.sav preserves the in-flight door
  group; after ordinary restore and monitor dismissal, e1m2a-slide-complete
  retains the opened route. Health pickup 284 is collected through movement.
  The optional valve approach at (-112,95,-488) is obstructed; the replay
  returns through the known corridor/cart route rather than treating that
  approach as a progression failure. The earlier client run ended at its
  dkguard limit; its log is /tmp/dk3-e1m2a-through-slide.log.
- [seq:152] The cart's lower button starts its authored return legs through
  the flooded chamber and back up to the entry platform. The player boards
  through normal movement, retains 75 health and remains grounded on entity
  181 throughout the recorded legs (e1m2a-cart-return-boarded, -north, -west
  and -complete saves). The replay is returning to the newly opened slide.
- [seq:153] The all-sides navigation batch finishes all 97 AAS variants and
  84 selection files. /tmp/dk3-all-sides-navigation.pk3 has 181 entries and
  SHA256 ddf0f0b5b7007fd7d87ae19fe52bbe654cb6f8e323b96c1db43547fb720f1be2.
  /tmp/dk3-navigation-load.log records the running server loading all 97
  expected map/profile pairings in /tmp/dk3-navigation-load-cases.json, then
  exiting normally; there are no navigation errors. The new package replaces
  the private navigation overlay in campaign and multiplayer installations.
  Original installed asset identity remains unchanged for saved-game
  continuation. This checks loading, not complete per-map routing behavior.
- [seq:154] Normal combat defeats sludgeminion 155 through the opened slide,
  reaches the upper-area health pickup and defeats sludgeminions 296/357.
  e1m2a-upper-corner-fast-3.sav retains 44 health near the upper-door approach.
  The stationary combat driver died at the next doorway/stairs; its limited
  target range and short bursts were corrected, but that encounter still
  needs a successful replay. No gameplay balance change was made to pass it.

- [seq:155] Rebuilt-navigation CTF replay on e1ctf1, two red and two blue skill-3
  bots, records four red captures and one blue capture through normal bot inputs.
  /tmp/dk3-all-sides-ctf-four-bots.log ends normally with no runtime error.
  This extends contested objective evidence; teammate-yield and the remaining
  multiplayer matrix are still open.
- [seq:156] Combat review identifies C4 incorrectly entering the recurring
  beam-damage branch and sticking after direct damage to an actor. The repair
  separates contact explosions, wall attachment, one-second arming, visible
  actor proximity, shot-triggered blast chains and owner-only remote detonation.
  Native radius damage schedules chain fuses without recursive explosion calls.
  Attached charges reuse native mover assemblies; stationary missiles no longer
  re-trace and re-impact their attachment every frame. The Controls menu and
  default right mouse button expose detonate (c4_detonate alias accepted).
  Optional reference observations supplied behavioral facts only; implementation
  and callbacks use native services. zig build game -j4 exits 0 in
  /tmp/dk3-c4-repair-build.log; no broad checks were run.
- [seq:157] Running client C4 scenarios use ordinary weapon, aim, attack,
  movement, use, save/load and detonate commands in e1m2a. A contact blast
  deals 72 damage to a nearby worker and 36 splash damage to the player.
  c4-attached.sav contains a floor charge with 700 ms until arming;
  c4-armed.sav retains the armed charge and unchanged 59 player health.
  Remote detonation removes that charge. Restoring the deployed-charge save
  and placing a second charge produces c4-chain-ready.sav with charges about
  70 units apart. One ion hit deals 30 damage to the first 5-health charge;
  its blast deals 59 to the second, and both are absent afterward. The player
  remains at 59 health. Restoring both and walking into proximity removes
  both charges and leaves 18 health (e1m2a-aas-4600.sav). Logs/captures are
  /tmp/dk3-e1m2a-client.log, /tmp/dk3-c4-proximity.log and private screenshots
  named dk3-c4-*. These cases do not close the complete weapon gate.

- [seq:158] A C4 charge attached to door 339 follows its 37.515-unit translation
  exactly between c4-door-attached and c4-door-moving. Restoring the latter
  exposed a separate handoff defect: its remaining 250-ms arming deadline
  elapsed before the first restored client frame, damaging the player from
  44 to 14 during loading. /tmp/dk3-c4-gameplay.log retains that failure.
  World-hold service v1 now delivers the restored snapshot without advancing
  simulation or movement, then releases on the client's ready acknowledgement.
  Native and QVM save import signatures now both pass the explicit version;
  the prior assembly imports lacked the native wrappers' inserted argument.
  zig build engine game -j4 exits 0 in /tmp/dk3-restore-handoff-build.log.
- [seq:159] The repaired c4-door-moving restore holds and releases at server
  time 800, with 44 health. c4-door-ready.sav retains the charge at its saved
  position with exactly 250 ms remaining, after client readiness. GDB only
  logs hold/release state; it does not change game state. The near-impact
  e1m2a-upper-stairs-clear-5 restore likewise returns control at 5 health
  and simulation time 600, then dies from its saved projectile at 700 despite
  ordinary crouch/movement input. No damage precedes readiness. This repairs
  loading-time simulation loss without making a dangerous saved state safe.
  Evidence is /tmp/dk3-e1m2a-client.log and /tmp/dk3-restore-handoff.gdb.
  No full save, campaign or release gate is closed by these targeted cases.

- [seq:160] The campaign replay reaches the upper encounter by staying left
  of worker 93 instead of repeatedly running into its doorway position.
  e1m2a-aas-4705.sav retains 29 health in melee range of sludgeminion 77.
  Ordinary disruptor attacks defeat the remaining 215-health minion; a
  following disruptor hit defeats froginator 289. The final checkpoint
  e1m2a-frog-contact-finished.sav has 1 health. Froginator 290 remains alive
  near the stairs. /tmp/dk3-stairs-detour.log and
  /tmp/dk3-minion-close-approach.log retain movement inputs; combat is in
  /tmp/dk3-restore-handoff-client.log. No enemy or player state was injected.
  The replay follows a physical health detour. A running diagonal jump
  reaches AAS area 2881 at (-1167.125,1164.409,-87.875), recorded in
  e1m2a-health-diagonal-jump.sav. The earlier straight jump and overshot
  approach fell off the route; driver braking and jump direction were
  corrected. No movement/gameplay patch was made for those input failures.

- [seq:161] Repeated pause/resume during the health-ledge replay exposed client
  command timestamps moving backward (4170 to 4132), causing the server to
  discard newer movement releases. The local pause branch now removes menu
  elapsed time from serverTimeDelta. zig build engine -j4 passes in
  /tmp/dk3-pause-clock-build.log. /tmp/dk3-pause-clock-before.log preserves
  the failure. The first fixed ledge replay has 12 input transitions without
  backward timestamps; its 1-health player still dies from a saved projectile.
  A replay from e1m2a-upper-minion-melee aims the Disruptor at the frog's
  landing point after the saved cooldown, defeats it and retains 7 health.
  Normal movement then reaches the lower jump approach; the faster traversal
  avoids the prior stationary driver's death. The ongoing fixed-client log is
  /tmp/dk3-e1m2a-client.log, with route inputs/results in
  /tmp/dk3-health-route-fast-fixed.log. This does not close the campaign gate.

- [seq:162] The 7-health ledge continuation still fails under enemy fire;
  the route driver's short settling interval also carries momentum through
  narrow turns. Replay returns to the real e1m2a-aas-4702 checkpoint. An ion
  shot kills froginator 290 before the stair ascent. From the upper stair,
  ordinary ion fire kills minion 77 and frog 289; the resulting
  e1m2a-upper-minion-clear-ranged-2.sav retains 34 health and 23 ion rounds.
  /tmp/dk3-upper-minion-clear-ranged.log records the hits. Earlier firing
  from below the stair ricocheted into scenery, and the low C4 arc attached
  nearby and killed the player; those are failed combat attempts, not passes.
  The upper authored route reaches door group t57 at (-1476,1024,128).
  It correctly reports remote operation. Its authored button 119 is below
  at (-696,1188,-218); the replay is descending to that control and health
  pickup 358. /tmp/dk3-e1m2a-upper-route-continued.log records the upper route.

- [seq:163] Health pickup 358 is collected after moving around protopod 89,
  leaving 54 health in e1m2a-lower-health-contact.sav. Button 119 activates
  the authored t57 monitor and paired upper doors. After the monitor's
  minimum viewing interval, ordinary use dismisses it. The player runs the
  connecting lower corridor, ramps and stairs and crosses the timed door
  before it closes, reaching (-1514,1027,88). Evidence: saves
  e1m2a-t57-control-used, e1m2a-t57-run-start and e1m2a-aas-4972;
  /tmp/dk3-t57-timed-return.log and the corresponding client screenshots.
- [seq:164] The earlier thin-ledge route exposes an AAS endpoint defect:
  equal-floor links offset five units through the destination polygon and
  into solid. BSPC now halves that inset until the endpoint belongs to its
  destination area, preserving usable narrow crossings. The targeted compiler
  build and e1m2a regeneration pass. All 7,410 links and 5,735 areas remain;
  706 endpoint records change, including 704 previously outside the named
  destination. Both links from ledge area 2881 now end in their destination
  areas 2824/2855. /tmp/dk3-inset-endpoints.json records the comparison;
  /tmp/dk3-inset-navigation.log records conversion. The private overlay is
  installed for the next map reload. Bot traversal and the wider navigation
  refresh remain open; this structural probe alone does not close V6/V11.

- [seq:165] Ion combat defeats minion 291 beyond t57. The following trigger
  destroys corridor brush *16 and starts its authored five-second earthquake.
  The first moving replay is knocked through its turns and dies under frog
  fire. On replay, two C4 charges thrown north from the approach activate near
  frog 293 and chain-explode, killing it while reducing player health from
  42 to 41. The player waits out the quake and defeats frogs 292/493 with ion
  fire. The next collapse opens the rotating rubble route named target39.
  Ordinary movement along authored nodes 82 to 83 crosses that transformed
  brush into the upper supply room, which static AAS alone cannot route to.
  Health pickups 277, 477 and 359 raise health from 12 to 87. Evidence:
  e1m2a-quake-c4-clear, e1m2a-quake-corridor-safe and e1m2a-aas-5003..5005;
  /tmp/dk3-e1m2a-post-quake-route.log and /tmp/dk3-upper-health-authored.log.
  This extends C4 combat and dynamic-mover traversal evidence; the map exit
  and full campaign remain open.

- [seq:166] Collecting Gas Hands exposes its missing campaign lifetime.
  The repair reserves native powerup slot 15 without changing array/wire
  sizes, reads the duration from the supplied table, extends it on repeated
  campaign pickups, pauses it during cameras, and shares expiry/fallback
  weapon selection between prediction and server simulation. Multiplayer
  ownership remains untimed. HUD/inventory show remaining seconds; saves
  reuse relative powerup deadlines and travel records add gas_hands.
  zig build game -j4 passes in /tmp/dk3-gashands-lifetime-build.log.
  The rebuilt running client loads the pre-pickup checkpoint and collects
  the item normally: e1m2a-aas-5010.sav records 119850 ms remaining and the
  rendered HUD displays Gas Hands / 120s. Expiry, restore, cameras, travel
  and the remaining weapon scenarios are still being exercised. The prior
  campaign log is preserved as /tmp/dk3-e1m2a-through-gashands.log.

- [seq:167] Gas Hands restore and expiry pass in the running client. The
  picked and restored saves both retain 119350 ms, weapon 7 and 87 health.
  Ordinary simulation then expires the effect, removes its inventory bit
  and selects the owned Disruptor; e1m2a-gashands-expired.sav retains 87
  health and weapon 1. /tmp/dk3-gashands-lifetime-client.log and matching
  screenshots preserve the result. The first shorter wait is retained as
  e1m2a-gashands-countdown.sav, with 98750 ms remaining. No simulation time
  or player state was injected. The companion item filter now excludes
  Gas Hands; equipped native looping sound and client smoke use supplied
  media and ioquake3 effects. The targeted module build passes in
  /tmp/dk3-gashands-presentation-build.log. Visual inspection and campaign
  continuation follow; camera/travel/repeated pickup remain unverified.

- [seq:168] The campaign crosses the flooded passage, swims up the far ledge,
  operates the ladder button with space for the bottom rung, climbs and
  traverses the authored exit into e1m2b. No forced map transition or player
  state change is used. e1m2b-authored-arrival.sav retains 28 health, weapon
  7, inventory 142 and 69250 ms of Gas Hands; the preceding mantle save
  has 69700 ms. /tmp/dk3-e1m2a-authored-exit.log retains the client flow.
  Failed attempts include obstructing the bottom rung and missing the
  recessed button from the side. Input clearance resolves those failures.
  A separate defect is confirmed: all rungs extend together, ignoring their
  supplied 0..4.5-second delays. Binary doors now schedule native stop
  trajectories per part; shared velocity is zero before their start, and
  start sound is deferred using the saved action deadline. Return and
  obstruction reversal remain immediate. The targeted module build passes
  in /tmp/dk3-delayed-ladder-build.log; the staggered replay follows.
- [seq:169] The inset compiler refresh completes all 97 navigation variants
  for 84 maps. /tmp/dk3-inset-all-navigation.log and the package
  /tmp/dk3-inset-all-navigation.pk3 retain outputs. Private gameplay,
  navigation-load and bot-replay homes receive the refreshed overlay.
  Installed campaign asset identity remains unchanged. Runtime checks of
  the refreshed package and bot crossings remain open.

- [seq:170] The staggered ladder replay passes. At 300 ms after use, only
  the zero-delay rung is moving; the other rungs retain their future
  deadlines. At 3150 ms, the 3000-ms rung is moving while the 3500/4000/
  4500-ms rungs remain retracted. The delayed-ladder-start and restored
  saves preserve 700/1200/4200/200-ms deadlines exactly for rungs
  367/368/374/375. Those restore probes used a dangerous 1-health checkpoint
  after the driver left the new client unpaused; progression replays from
  the intact 71-health checkpoint. The player climbs the repaired ladder,
  strikes frog 295 with Gas Hands (1000 damage from the supplied table),
  and crosses the authored exit. e1m2b-staggered-arrival.sav retains
  37 health, inventory 142, weapon 7 and 69100 ms of Gas Hands.
- [seq:171] The refreshed navigation package loads all 97 distinct AAS
  variants in the running dedicated server and exits 0 with
  DK3_NAVIGATION_LOAD_COMPLETE. /tmp/dk3-inset-navigation-load.log has no
  runtime error. The four-bot contested CTF replay is running separately;
  map loading alone does not close navigation or multiplayer acceptance.

- [seq:172] The inset-navigation four-bot e1ctf1 replay completes with four
  contested captures: three blue and one red, plus kills, drops and
  respawns. /tmp/dk3-inset-ctf-four-bots.log exits normally. All 97 AAS
  names in the server-load log match the expected case order. The refreshed
  private package SHA256 is
  0738c22c3cb35e27298aa0982479f1aa10a2615d55b82eb56faac872e9dcd954.
  This extends the affected navigation evidence; it does not close all
  actor, bot or multiplayer scenarios.
- [seq:173] e1m2b's opening duct encounter kills the first low-health replay.
  The successful replay preserves Gas Hands readiness during the approach,
  aims through the leaping frog's descent, kills both frogs 394/284 and
  jumps aside. e1m2b-frogs-cleared.sav retains 20 health. The player then
  traverses the duct to its far ramp; e1m2b-aas-5111.sav preserves that
  position. Failed attacks were aimed above/below the moving frog or fired
  while out of range; no gameplay damage or collision patch was made.

- [seq:174] The upper supply route crosses the pipe platforms and collects
  health items 279/338, then ion ammunition 220 and C4 219. Gas Hands
  defeats the nearby pods and their spawned mosquitoes. The current
  e1m2b-aas-5281.sav retains 64 health, 42 ion rounds and 14 C4 charges.
  Failed attempts include a 24-damage projectile impact on the middle pipe
  and a turn that carries the driver off its intended ledge. Alternate
  movement and combat resolve those attempts without changing geometry or
  damage. The driver now reacts to nearby actors blocking a waypoint and
  accounts for melee cooldown. The game code also silently clears Gas Hands
  on death, avoiding the misleading lifetime-expired message caused by
  native death clearing all powerup deadlines; this small follow-up is
  written but not yet rebuilt or replayed.

- [seq:175] The normal-input replay defeats minion 278 with ion fire and
  preserves 64 health in e1m2b-minion-cleared-ready.sav. The player crosses
  the northern pipes, descends behind the platform into the sloped channel,
  opens door 315 through its authored trigger, kills its blocking mosquito,
  and reaches e1m2b-aas-5504.sav with 30 health and 26 ion rounds.
  /tmp/dk3-e1m2b-northern-channel-client.log and the pipe/channel driver logs
  retain the flow. The northern platform itself is a dead end; the drop
  behind it is physically traversed. No geometry or navigation bypass is
  used. The private input driver now waits for each atomic save replacement
  before pausing; its former screenshot-first ordering could leave a save
  command pending, so missing driver checkpoints were not product save
  failures. The Gas Hands death cleanup builds and is installed. An ordinary
  kill while equipped produces no false lifetime-expired message in
  /tmp/dk3-gashands-death-cleanup-client.log. A separate intermittent empty
  sound warning is under observation with a conditional engine breakpoint.

- [seq:176] Underwater restore refilled air because ApplySnapshot assigned
  a fresh 12000-ms deadline. Gameplay revision 3 now requires a bounded,
  relative player_environment record; revision 2 development saves retain
  their documented old behavior because no air measurement exists in them.
  /tmp/dk3-air-save-build.log passes. The running client writes and restores
  exactly 8000 ms in e1m2b-air-countdown and its restored checkpoint.
  Exhausting that air applies 4 drowning damage (13 to 9 health). Restoring
  the drowning save preserves its 850-ms next deadline and subsequent
  6 damage (9 to 3 health), including the escalating entity damage field.
  A CRC-valid fixture with 13000 ms is rejected as invalid player air
  deadline before replacing the live 30-health channel world. Evidence:
  /tmp/dk3-air-deadline-restore-client.log and the named private saves.
  The first stationary probe was killed by rotating machinery; the actual
  air test uses the cleared submerged corridor. The underwater campaign
  route remains open: standing movement stalls at low passages, and the
  eastern fan approach is hazardous. Crouched swimming is the next replay.

- [seq:177] Ion bolts previously traversed liquids unchanged. Liquid contact
  now discharges them through native missile traces and radius damage,
  including moving liquids and restored bolts. The targeted module build
  /tmp/dk3-ion-liquid-build.log passes. One submerged shot consumes one
  round, applies 15 self-damage (63 to 48 health) and leaves no live ion
  bolt; the dry comparison consumes one round without damaging the
  64-health player. /tmp/dk3-ion-liquid-client.log retains both flows.
  Further water-entry, target-damage and AI weapon-choice cases remain open.
- [seq:178] The paddle route reaches the far chamber without damage, surfaces
  naturally to replenish air, breaks glass 306 with the Disruptor, collects
  health 344/273 and ammunition 335, and operates button 270. Water train
  101 moves downward at 15 units/second through its authored target chain.
  The return breaks glass 305 and reaches a real air pocket with 63 health,
  61 ion rounds and 14 C4 charges in e1m2b-drain-return-breath.sav.
  The repaired revision-3 air deadline persists through these checkpoints.
  The paddle approach was resumed from a revision-2 development checkpoint;
  a continuous replay from the channel entrance remains required. The
  [IGN route guide](https://doczz.net/doc/1251842/ign-walkthrough) clarified
  the intended paddle/control/return order; all positions and interactions
  were measured against supplied assets and the running game. Stationary
  eastern-fan probes and the attempted lower health shortcut were abandoned
  after collision evidence; no geometry changes were made for those attempts.

- [seq:179] Opening repair batch adds protocol1343 actor scale axes and animation
  timing, cinematic facing and gravity, pose-based corpse contact, mechanical
  and organic fragmentation, bounded damage tint, overhead thunderskeet passes
  and toxic bombs. The bridge's always-on red strips were toggle-only func_wall
  brushes initialized visibly, not lightning entities. Entity205/model*37 now
  follows its authored off/on/off relay (uses0/1/2). Sprite polygons used entity
  color shaders without a refEntity; converted SP2 stages now use vertex color.
  Ion impacts selected an electrical tile; use the supplied five-frame explosion
  and clamp transient frames. Actual mosquito death, crox death/final ground pose,
  corpse fragmentation, beam visibility and ion flare/impact frames are retained
  under /tmp/dk3-presentation-data/dk3/screenshots/. Native named menu save/load,
  conflict cancellation and scaled HUD flows were exercised. These are partial
  scenario results; they do not close opening or campaign acceptance.

- [seq:180] Owner inspection required a direct 1.3 appearance comparison. Private
  reference captures ran through the existing dkparity sandbox; its install digest
  stayed unchanged. Their 640x480 frames and existing menus-panels reference show
  left-stacked skill meters, six right-hand weapon slots, original button/slider
  glyphs and three difficulty figures. Native layout corrections are in progress.
  Disruptor view model selection incorrectly used w_disruptor; the supplied
  w_tglove is now selected. Actor tick is explicitly50ms: upstream FRAMETIME is
  100ms, so the prior alias did not speed it up. Full assets conversion completed
  generation fea5d2988a58b6ea7688fd8f772ce9264c702caede905621cf617e748e883faf.
  Integrated build and visual comparisons follow; no broad lint/test sweep run.

- [seq:181] Actual 1.3 captures now drive the opening presentation repair. The
  installed native main menu matches the difficulty figures (0.0017 differing
  pixels against a 0.02 bound) and buttons (0.0002 against 0.04); the three HUD
  value regions pass the existing HUD scenario bounds. Native menu quick save/load,
  relative-pointer volume drag and a 1280×720 menu run succeed. Absolute XTest
  motion was an unsuitable driver for SDL raw input, not evidence that dragging
  was broken. Zero mouse deltas no longer replace keyboard focus. Original options,
  other panels and complete presentation acceptance remain open.
  Disruptor uses w_tglove, finite 20fps sequences and a 600ms attack interval.
  READY no longer cuts off a sequence, and idle fidgets have a five-second rest.
  A renderer probe records 218 poses over 1803ms, all attack frames122–133 and
  67 fractional blends, followed by the held final frame. Reference view pitch is
  5.4272, despite getpos reporting body pitch1.81. Shared standing view height is
  now22 rather than26. Reference/native eye motion and world lighting still differ;
  matching entity coordinates alone does not establish a world-image match.
  Integrated build and affected module builds passed; the final installed generation
  is b087b0b23d3a9f7a817d7b2a7b29364bae8c1ed096dbf97a2f799f0a833d7339.
  The owner's local dk3 command launches that checked independent installation.
  Retained private images, input observations and traces are under
  zig-out/reports/presentation-reference-01/. Reference install digest remained
  5747565ec29e2f46e56f3afc9661c4766e502aaeefea08685f9b6c06a2cfe50e.
  No proprietary dependency or broad lint/test sweep was added. V1–V12 remain open.

- [seq:182] Follow-up repair compares opening behavior with the optional original
  source. Native saves now use gameplay revision4 and include visited worlds as
  bounded byte fields; complete saves stage an inactive map-cache bank before
  activation. e1m1a mosquito273 takes two ion hits 500ms apart and is removed.
  It remains absent after the real forward/backward exit triggers and after
  loading the intervening e1m1b save, then returning. Diagnostic placement reaches
  the triggers; this is not a continuous campaign replay. Corrupt outer and nested
  checksums are rejected before replacing the world. New worlds use the original
  first authored spawn fallback. Full115-shot intro playback at accelerated
  simulation reaches e1m1a, completes its entry cinematic, and leaves Hiro at
  (1608,-2592,552.125) with the Disruptor. That run exposed attached truck decoration
  accumulating gravity to Z-285137312; attached decoration now follows its parent
  without independent freefall. The original installation and saves are preserved.

- [seq:183] Presentation/audio batch restores 175ms hover and 350ms menu selection,
  supplied menu sounds, original loading tiles/bar/blocks, and resource-loading
  ticks. The first loading preview exposed an overlap seam and CS_ITEMS27 collision;
  tile rows now overlap32px and loading art uses configstring28. The native MARSH
  plaque is inspected. Existing local HD textures are installed as an image-only
  overlay; dk3 launches with r_picmip0. Mosquito patrol no longer skips perception;
  actual attack reduces health100→93→86 and continues. Mixer traces contain the
  attack/flight/pain samples, all four Hiro pain samples, and two flesh-hit samples
  at ion damage times174800/175300ms. Hit counter reaches2. Tests use dummy SDL
  audio; they prove dispatch rather than the user's physical audio output. Repeated
  e1dm1/e2dm1 bot deaths respawn to health100/PM_NORMAL; the user's stuck-dead case
  remains unreproduced. Direct optimized game-function debugger calls did not
  reliably deliver damage and are excluded; bot command probes use the engine's
  normal client-command service, alongside the earlier natural C4 kill.

- [seq:184] Marsh effects gain cambot sweeping cones, supplied tagged flares/local
  lights and particle-atlas sampling. Save validation explicitly accepts the actor
  spotlight combination; its first rejection is retained. Original sky flashes
  were renderer-generated, so entity census alone missed them. The presentation
  converter now emits authored cloud layers and independent sky-flash waveforms
  for53 supplied maps. A three-stage sky exposed upstream duplicate unreferenced
  cloud vertices; both renderers now build their shared mesh once. The first
  renderer error/frame is retained. Conversion caching now ignores worker counts
  for deterministic products; the final sky conversion reused maps/models/audio/
  navigation and rebuilt presentation assets. Final sky/client and broad-check
  results follow in the next entry. Evidence: zig-out/reports/gameplay-reference-02/.

- [seq:185] The repaired cloud mesh completes e1m1a entry playback and renders
  the marsh sky in OpenGL1 and OpenGL2. Captures retain moving layers and changing
  flash brightness; this does not certify pixel parity with 1.3's sky projection.
  Pre-registering the replacement as an unlightmapped shader removes the remap
  lightmap warning. Final asset generation is
  44ecb90cefd364c9c3b7d8bc32f26dde38a04773bcb49f0fe8ca4656675d0e73;
  only presentation and generation-identity data packages differ from the preceding
  batch. The integrated build passes and the installed generation is
  49c874285a4eecc7d717aad9f46b07b93c742cc26e267def4bae9e99f0af5453.
  Engine development hashes and installed binary hashes match. One make lint run
  passes125 Zig tests and40 Python tests, including conversion-cache regression
  cases; its formatting step identifies two Zig build files. Formatting those
  files and rerunning the full formatting check passes. The already passing test
  suites were not repeated. Saves still enforce the documented exact asset
  generation identity: use a fresh campaign for this asset update; older development
  saves/installations are preserved. Broader actor/effect and campaign acceptance
  remain open, and the reported bot respawn failure is unreproduced.
  The actual /home/dmitriy/.local/bin/dk3 launcher also passes an isolated-settings
  startup under dkguard/Xvfb, reports picmip0, and exits cleanly. Its normal settings
  and save directories were not used by the probe.


- [seq:186] Started the requested subsystem-first audit in docs/runtime-gap-audit.md
  and made it the active roadmap workflow. Private supplied-data inventory covers84
  maps,82 actor definitions,1145 frame-event rows and15 action-script packages.
  Of244 unmatched animation rows,148 are sound-only sight cues across57 classes;
  remaining96 need model/chapter/optional-clip classification. Eleven supplied sound
  references lack matching package entries. These are discovery findings, not gameplay
  passes. No reference code or assets enter the public dependency graph.

- [seq:187] Shared repairs add independent sight cues, weighted ambient sounds,
  finite leap/hatch/turret actions, successful-pickup audio, weapon-specific contact
  events/marks and Ion shot/flyby/contact behavior. Stock score-hit audio is disabled
  for dk3. Ion has a three-contact ricochet limit and speed gain. Rockgat has explicit
  closed/raising/open/lowering states. Pod verification exposed both a spawn hull
  blocked by Hiro and generic80-unit perception defeating its200/512-unit horizontal
  proximity rules; bounded clear emergence candidates and separate perception repair
  both. Pain cannot restart the turret lift or pod hatch. Protocol1344/save schema5
  record the new contracts. Single-player reloads a validated death checkpoint;
  multiplayer retains ordinary respawn. Map effects retain supplied particle types,
  class-specific flame art and event-generator admission/sound.

- [seq:188] Running native client evidence: e1m1a egg87 holds its completed frame22,
  health1, and creates an attacking mosquito with player0 as enemy; save/load preserves
  the opened egg. e1m1b rockgat holds frame0 closed, frame10 raised, dispatches its
  supplied fire sample, then lowers to frame0. Health25 touch dispatches a_hpick.
  Normal Disruptor attacks render supplied damage marks and dispatch contact audio;
  four Ion shots use shootb/electron contact sounds without the stock flesh-hit beep.
  Bridge diagnostic placement followed by ordinary forward input activates doitall
  once and completes16 actions, ten scripted mosquitoes and a thunderskeet spawn.
  Kill/respawn input restores the preceding manual checkpoint's intact bridge and
  zero event uses; checksum corruption instead keeps PM_DEAD with a load diagnostic.
  e1dm1 AuditBot kill/respawn returns health100/PM_NORMAL. These are targeted encounter
  probes, not a continuous playthrough. Audio evidence is software mixer dispatch.
  Evidence: zig-out/reports/gameplay-reference-03/.

- [seq:189] Compared original1.3 waterfall rendering with native diagnostic placement
  at(1642,-2305.375,526.75), yaw37.7594/view pitch5.427246,640x480. The original getpos
  reports reduced model pitch1.81; initial native captures used that value and are
  retained as unmatched probes. Source format review and rendered comparison exposed
  overlapping atlas cells: a full smoke quad also samples the neighboring CP1 cell.
  Native atlas particles now use the triangular footprint, correct scale and ordinary
  alpha blending. Final frames in both renderers show mist without the yellow bloom
  or neighboring cell. Texture/lighting and random-phase differences remain; full
  visual parity is not claimed. Final integrated build and one make lint pass succeed
  (including40 Python tests and the Zig targets). Engine development hashes and
  installed binary hashes match. Asset generation:
  1cd2b1ddc94af2f83983cd5a77700a9fab21f7647b7e81e2daf8b6d795977dcf.
  Installed generation:
  f7a2978b4620847af7fccd6c2d60b08b2ac5d2fa1ed3056c270062208148a126.
  The actual dk3 launcher starts successfully with isolated settings and picmip0;
  user settings/saves and prior installations are preserved. New gameplay schema
  requires a fresh campaign. The audit matrix names remaining weapon boundaries,
  actor/companion/script lifecycles, lightstyles and campaign acceptance explicitly.


- [seq:190] Whole-level darkness investigation separates a local style6 omission
  from global display handling. In a private SDL fixture that accepts but ignores
  gamma ramps, fullscreen GL1 reports hardware gamma/one overbright bit and the
  displayed rock-region luma is7.08 while the engine JPEG is14.49. The screenshot
  encoder applies a correction absent from display scanout. The original1.3 private
  settings probe reports vid_gamma0.659/gl_modulate1, whereas dk3 uses inverse gamma
  and converted modulate2; older unmatched captures cannot establish pixel parity.
  This establishes a renderer failure mode, not the owner's actual compositor cause.

- [seq:191] Both bundled renderers now use the existing software gamma path; GL1
  retains full framebuffer lighting in fullscreen without display-ramp compensation.
  Video exposes Brightness with Apply/vid_restart, preserving user gamma preferences.
  The ignored-ramp replay reports software gamma/zero overbright. A paused marsh
  scene without dynamic lights measures14.35 in X11 pixels versus14.32 in its JPEG.
  Windowed control and both renderers at gamma1/gamma1.3 were inspected; keyboard
  adjustment1.0→1.3 and Apply return to gameplay. Xvfb's fullscreen mode-switch timeout
  limits this to the renderer path, not physical compositor verification. Integrated
  ReleaseSafe build and one make lint pass succeed (40 Python tests and Zig targets).
  Engine/source and installed binary hashes match. Evidence:
  zig-out/reports/marsh-darkness-02/. Installed generation:
  1b0ec946b2294851aa667ce99b3e4fcd2bef522dce111be57f88111496011f1b.
  Assets, save schema, user settings and saves are unchanged. Local lightstyles,
  owner-display confirmation and the wider campaign audit remain open.


- [seq:192] Prepared the current implementation for the requested GitHub publication.
  The staged tree contains the bundled engine/navigation compiler, independent native
  modules, asset/build/install tooling and current documentation. Both pinned upstream
  inventories are complete; exact ignore exceptions retain nine previously ignored
  upstream inputs after hash verification. No original or converted game assets,
  saves, reference runtime, local agent configuration or generated build products are
  staged. Credential-pattern scan and public Markdown link checks pass. An export of
  the staged source builds ReleaseSafe with empty local/global Zig caches, without
  copying any assets or private reference files. The preceding make lint evidence
  remains valid for the unchanged implementation. Publication is a development
  snapshot; it does not close campaign, multiplayer or release acceptance.

- [seq:193] Compared the reported marsh/combat/DM failures with private reference
  behavior and supplied data, then repaired the shared runtime paths. Weapon/ammo
  bindings are corrected across episodes; pickups settle using mesh collision bounds;
  monster XP uses episode-scaled tenth-health awards and reference cumulative thresholds.
  Native level1/displayed level0 is preserved. The live weapon/death test awards3 XP
  for the frog and promotes497→500 exactly once. Frog spit is a green particle-only
  effect; robotic fragments are scaled through tumbling; Ion illumination is additive.
  Menu intro/loop decodes to nonzero mixer samples. Contentless trigger brushes now use
  authored volume overlap: e1m1b's red barrier deals5000 damage and restores the death
  checkpoint. Thunderskeet attack/retreat and cambot separation replace generic pursuit;
  live failures led to perception traces ignoring actors, the boss's late shot pair,
  pain admission and existing air-navigation recovery. Both projectiles and small
  mosquito fragments were inspected in rendered diagnostic scenarios. e1ctf1 supports
  the player plus seven FFA bots without the missing-spawn error, with combat/scoring.
  Final integrated ReleaseSafe build and make lint pass (41 Python checks plus Zig);
  pinned engine development hashes match. Installed runtime
  bf531d9072faa4834a500668795a44c16cd028e420550acad38f785747ea2dce is selected by
  the existing dk3 launcher; assets, HD override and save schema remain compatible.
  Evidence and rejected intermediate probes are private in combat-reference-04.
  See docs/runtime-gap-audit.md for scenario limits; this is not full campaign parity.

- [seq:194] Reproduced the reported Ion neon stripe at the e1m1a waterfall using
  audit-lighting and a stationary diagnostic Ion entity at
  (1752.193604,-2220.040039,523.508545). The prior additive projected-light pass
  added untextured RGB over the world; private reference inspection confirmed
  material-modulated illumination. Both renderer projection paths now sample the
  animated diffuse material with its tcMods, using the existing ioquake3 rendering
  infrastructure. No reference implementation was imported. Matched OpenGL1/2
  captures retain the rock detail; Ion radius300 and colour(0,.8,0) remain unchanged.
  OpenGL2 forward mode renders but retains its existing brighter attenuation.
  Actual attack input in OpenGL1 consumed40→39 ammunition and rendered the ball
  in flight and after a bounce. ReleaseSafe build and final make lint pass (41
  Python checks plus Zig). Engine development hashes match. Installed runtime
  148c876b28f0054a55061c96e67ee33a4731344385bd3296bd44620f635b155f matches the
  verified binaries and preserves the HD asset override. The owner's existing
  running game was left untouched; restarting dk3 selects the repair.
  Evidence: zig-out/reports/ion-material-light-05. This fixes the material wash-out;
  no exact original-renderer attenuation or full campaign parity is claimed.

- [seq:195] Implemented source-backed Ion composite flight, textured beam-spark trail,
  contact mesh/sparks and terminal sparkles; atlas rain drops, source speed/wind,
  area-based emission and collision splashes. Compared preserved-original rainfall
  capture and supplied Ion screenshots with the private source contracts. Actual
  native wall contact at1684,-2272,511 dispatched the new effect. Inspected OpenGL1
  and OpenGL2 frames. Corrected an intermediate shader-name collision and excluded
  failed reference-weapon/debugger probes from acceptance. ReleaseSafe build and
  make lint pass (42 Python tests plus Zig). Runtime shader installation has a
  synthetic identity/corruption regression; installed modules/shader and engine
  development hashes match. Gameplay assets/HD override and saves are unchanged.
  Installed 5aec4a76e3d4d6f0ac98029f162a94c83114336221bdc3621e38047b737cabb0.
  Evidence: ion-rain-reference-06. Exact beam tessellation, liquid rings and full
  effects parity remain unverified; see runtime-gap-audit.md for precise limits.

- [seq:196] Repaired the reported missing rain splashes on water. Private source shows
  floor-plane splashes; e1m1a floors lie on the water surfaces. Live client reads found
  solid-only drop traces, 2-unit padded weather bounds, and PVS-culled sky-level volumes
  (12/45 sent at the waterfall). Rain now stops at liquids and splashes at the floor,
  bounds are authored, weather links over its fall volume, emission scales to the view
  window and no longer recycles unlanded drops; SPLASH1/SPLASH3 sizing/alpha follow the
  source. Diagnostic noclip views over the pool in OpenGL1/2 render water splashes that
  the prior installed build lacks; 45/45 volumes sent, 671 water-surface splash records,
  0 of 300 sampled splashes under solid cover. Pre-existing OpenGL2 yellow saturation
  near the pool reproduced with the prior build and remains open. make lint pass (42
  Python tests plus Zig). Installed
  9d4f558c736cb039dc4a691aeb5edb3d4bdaf74fffbb9ae9b98bff2bfa4e56ff; assets/HD override
  unchanged. Evidence: rain-water-07.

- [seq:197] Repaired Gold weapon presentation from the private shotcycler, hammer and
  slugger source contracts. Shotcycler now fires at the six authored shoot frames
  (2, 8, 14, 20, 26, 32 at about 45 ms/frame), plays its 77-frame sequence once
  per burst, uses its `ambc` idle, ejects a supplied shell at a camera-safe position,
  and plays the six shell cues plus the terminal cycle cue. Hammer lift follows its
  charge through frame 18, then the strike advances at 25 ms/frame; its lift, drop
  and impact sounds use the supplied Gold bindings. Slugger and Cordite select the
  Gold `shootb` pose and their corresponding ripgun fire sounds. These are
  implemented; their full V5/V8/V9/V10 acceptance remains open.

  Scenario matrix: **Passed** — the shared timing regression demonstrated six
  shotcycler rounds and its recovery, plus hammer charge/release; an isolated
  e1m1a client under dkguard/OpenGL1 software rendering selected both weapons,
  fired them, rendered distinct hammer charge/strike frames, and completed with
  exit 0. A second live replay consumed all six shotcycler rounds (999 to 993)
  and the inspected shell capture shows the ejected model beside the gun at a
  plausible size. **Unrun** — audible mix and remote-player sound/visual parity,
  Slugger/Cordite live presentation, hammer target damage and other campaign
  weapon scenarios. Headless audio was dummy, so source bindings alone do not
  verify sound playback. ReleaseSafe build and one `make lint` pass (43 Python
  checks plus Zig). Evidence: `zig-out/reports/weapon-gold-08`.

- [seq:198] The live shotcycler flash capture exposed an opaque six-sided orange
  plate. Gold's `FLASH_SHOTCYCLER` uses `models/global/genflash.dkm` at scale 3,
  alpha 0.6 and an additive alpha-channel blend; the generic native flash had
  the Glock mesh and the first replacement drew the correct mesh without its
  alpha material. Added the reviewed `dk3/fx/shotcycler-flash` material and
  bound it only to the shotcycler. **Passed** — a fresh isolated e1m1a client
  fired the weapon and exited 0; inspected first-shot before/after frames show
  the solid polygon replaced by the transparent flame. ReleaseSafe build and
  refreshed `make lint` pass (43 Python checks plus Zig). Installed runtime
  `eae74b887e35ffc89bb121f6d3d46b5da9e6877b238f5ab4c5a21c372c9ab16b`.
  Evidence: `zig-out/reports/weapon-gold-08/shotcycler-flash-before.jpg`,
  `shotcycler-flash-after.jpg` and `flash-replay.log`. Audible and remote-player
  flash parity remain unrun.

## weapons-zig — sequence 199

Owner-authorized complete native Zig weapon rewrite, including adjacent modules
required for ownership. Coding pass: all 28 concrete types, shared prediction,
server combat/controllers, client presentation/effects, inventory and bot hooks.
Removed the C combat translation unit, C weapon table and movement include; weapon
presentation was removed from the C HUD file. Existing engine ABI, snapshot IDs
and save fields remain integration boundaries. No Gold implementation was copied.

Status: **complete native implementation; focused acceptance passed**. Architecture:
`docs/weapons-zig.md`. The broader campaign and exhaustive Gold visual/audio parity
remain separate, open acceptance requirements.

| Scenario | State and evidence |
|---|---|
| Integrated native build and source-path audit | Passed — ReleaseSafe qagame/cgame build; all 28 registered Zig types; removed dk3 C combat/table/movement files absent; no C source under `src/weapons`; bundled engine development hashes match. |
| Shared prediction, interruption and inventory contracts | Passed — every weapon fires, dead players cannot attack, deterministic replay of a mid-burst snapshot, six-round Shotcycler recovery, Hammer charge/release, Glock clip/reload/switch, Kineticore burst, Venom contact/water/ammo fallback, Flashlight edge triggering, sword levels, episode inventory transfer and invalid-charge validation. |
| All 28 selection/firing paths | Passed — local rendered groups plus `network2-server.log` assert authoritative fires for IDs 1–28; no panic or native module error. This is firing/presentation coverage, not exhaustive interaction coverage for every weapon. |
| Shotcycler/Hammer presentation | Passed — inspected additive Shotcycler flash/shell capture; charge/release captures at 30/60/144 fps and a 10 fps Shotcycler replay; half-charge release continues from the charged pose. Hammer strike is delayed to its damage frame. |
| Captured Shotcycler audio | Passed — demo replay produced 376 video frames and 201 audio blocks; PCM correlation identifies six fire samples at 2.183/2.403/2.717/2.953/3.253/3.503 seconds. Physical speaker playback and every weapon's final mix remain unverified. |
| Saved weapon state | Passed — saved Hammer charge 798 ms with attack held; Metamaser controller restored and continued damage; corrected C4 scenario asserts an attached charge in the save, restores it and reports `Detonating 1 C4 charge(s).` |
| Liquid and companion integration | Passed — e1m1a Ion discharge, Venom underwater melee without ammo consumption, Trident and Zeus firing; Zeus damage 300 to target 232; companion Ion damage after local firing stopped. Companion routing itself is outside this weapon acceptance. |
| Multiplayer and bot integration | Passed — independent dedicated server/client with 60 ms delay each way, all 28 authoritative fires, bot C4 fire, suicide and rendered respawn; shared replay regression checks deterministic prediction. Remote sound mix and all mode-specific weapon interactions remain unverified. |
| Applicable broad suite | Passed — one `make lint` (`zig build test`), 43 Python tests plus Zig checks. |
| Exhaustive Gold parity and authored campaign transitions | Unrun for this rewrite — do not infer full V5/V8/V9/V10 completion from these focused scenarios. Episode transfer rules have contract coverage; no new full campaign playthrough is claimed. |

Repairs made during verification: corrected ABI boundaries and native build inputs;
removed obsolete C policy APIs; made Hammer damage and release animation follow
its charged frame; restored Gas Hands lifetime when using the all-weapons grant;
moved remaining named impact/trail recipes into their weapon owners; removed a
render-timestamp event filter that could discard distinct shots in one frame.
The engine's existing event-sequence handling supplies replay suppression.

Rejected probes remain visible in the evidence: the first grouped client batch was
interrupted by its X display harness after weapon 26; subsequent isolated runs cover
27/28. Initial fixed-wait save captures raced loading. The first network driver's
setup commands hit flood protection; the corrected driver disables it and asserts
all 28 server fire IDs. The original C4 save contained no projectile, and the first
correction attempted firing in noclip; only the attached-charge assertion and
successful restored detonation count as acceptance. One startup empty-sound warning
appeared in local clients before firing; it was not reproduced in the dedicated
client, and these runs do not establish its origin.

Final installed runtime:
`c103168872563be1eca0a51093406e4586fdcc47fc413f7bafa7988aaf68ceb3`.
Existing asset/HD packages and save schema remain compatible. Private Gold source
was read for behavior and supplied asset bindings; no implementation was imported.
All runtime scenarios used dkguard, isolated homes/saves and software rendering.
Evidence, reproducible input drivers, inspected frames, demo/AVI, audio analysis,
logs and final check output: `zig-out/reports/weapons-zig-199`.


## weapons-gold-review — sequence 200

Resumed Cursor CLI session `f51a92b5-42a5-4f2d-9985-92fa7d8b09ca` from
its local transcript. Its latest owner request was a careful, individual comparison
of all 28 native Zig weapons with private Gold behavior. Earlier session work on
renderer/parity, saves and bots is retained. No Git operations or reference runtime
imports were performed.

Status: **weapon correction pass implemented; focused acceptance passed**. Recovered comparison reports
are private under `/tmp/dk3-resume-audits`; they are leads, not acceptance evidence.
New local evidence is under `zig-out/reports/weapons-gold-200`.

The resumed batch corrects Shotcycler victim accounting and aim; Sidewinder volleys;
Shockwave direct/splash/ring damage and flight; Gas Hands timer and attacks; Venomous
bite/poison/puddle behavior; Hammer quake damage; Trident ammunition, convergence and
supercharge; Zeus targeting and timed chains; Silverclaw timing; Bolter ammo/contact;
Stavros flight/fragments; Ballista pinning; Wyndrax acquisition; Nightmare reap timing
and holds; sword trace geometry/experience; Glock reload; Ripgun spin-up; Slugger
reach; Cordite fuse/contact; Kineticore acceleration; Novabeam budget; and Metamaser
supplied parameters. Shared self-damage is no longer halved a second time by the
engine, and power scales non-self damage after weapon-specific adjustments.

Nightmare holds use an optional relative-time entity save field, defaulting to zero
when absent. Controller references use a separate optional stable-ID field; mover
attachments retain their original contract. A fixture omitting both new fields
restores successfully. This demonstrates the missing-field path, not an exhaustive
replay of archived old saves.
Flashlight remains a documented dk3 convenience addition: the Gold implementation
was not part of its shipped weapon list. No change to its toggle contract is intended.

| Scenario | State and evidence |
|---|---|
| Integrated native build | Passed — final ReleaseSafe native build, formatting check and all engine provenance hashes match. |
| Prediction and inventory regressions | Passed with C assertions enabled. Existing optimized C fixtures had silently disabled assertions. Enabling them exposed and repaired first-shot cooldown and Hammer ready-state faults, and exposed the fixture's incorrect ammo requirement for free weapons. |
| All 28 local firing/presentation paths | Passed — authoritative IDs 1–28 across `selection-1-final.log`, IDs 15–21 in `selection-2-replay.log`, and repaired IDs 22–28 in `selection-2-final.log`. The latter replays resolve the Shotcycler shader warning and Ripgun missing pose. Inspected Shotcycler impacts/shells and Ripgun firing frames. This is selection/firing coverage, not exhaustive Gold presentation acceptance. |
| Damage, targeting, liquid and controller scenarios | Passed for the focused matrix — Venom bite reports 39 damage and health falls 50→8 including poison; Zeus chains to three actors; Nightmare reaps after its hold; Metamaser has 300 health/30 initial charges and damages after restore. `water.py` asserts saved water level 3 for Ion, Venom, Trident and Zeus, including no ammo cost for Venom. |
| Multiplayer integration | Passed — dedicated server/client with 60 ms delay each way; six Shotcycler shots, two Sidewinders, a Trident volley, Ripgun spin-up and five Kineticore shots. Bot and respawn frames recorded in `network-frames`. |
| Mid-action saves, optional-field compatibility and restores | Passed — attached C4 restores and detonates; Hammer restores an 801 ms charge; Nightmare restores a 4100 ms remaining hold, reaps and releases; Metamaser restores both a pending launch and an active cube, with post-load damage at simulation times 1700/2500/3500/4500. Both optional fields can be omitted in a compatibility fixture. |
| Supplied bindings | Model/sprite and sound names checked against the local packages. Gold's `shared/bloop4.wav` is absent; Bolter water sound remains unavailable unless supplied. |
| Exhaustive per-weapon audiovisual parity | Open; the recovered reports include additional detailed effects, view-kick, frame timing, target and sound branches. Selection/firing smoke checks do not close these. |
| Broad checks | Passed — one `make lint` (`zig build test`): 43 Python tests plus Zig checks; `lint.log`. |

Individual comparison coverage (behavior repairs; exhaustive Gold presentation is
not implied by this table):

| Weapon | Reviewed/corrected behavior |
|---|---|
| Disruptor | Retained Cursor's authored swings and impact marks; corrected boosted frame timing and shared inertial damage. |
| Ion blaster | Retained Cursor's collision, water-discharge and effect repairs; shared projectile boost and self-damage scaling apply. |
| C4 | Retained Cursor's attachment/detonation repairs; mover attachment IDs stay separate from weapon-controller links. |
| Shotcycler | Crosshair reach, two damageable victim slots, six shots, recoil and supplied bullet-hole material. |
| Sidewinder | Two individually charged rockets, partial-ammo volley, converged muzzle offsets, splash-only hits and recovery. |
| Shockwave | Delayed launch, direct/bounce/ring damage, six bounces, water behavior, one quake controller and silent flight-ring effects. |
| Gas Hands | Held-only timer, delayed contact attack, inertial hit, gas smoke and equipped sound. |
| Daikatana | Five-step swept contact geometry, kill experience, ready/away sounds and power applied after weapon damage adjustments. |
| Discus | Retained Cursor's Gold reflection, targeting and return corrections. |
| Sunflare | Retained Cursor's timed burn, bounce and liquid corrections. |
| Venomous | Free close/water bite, 39 base bite damage, poison cadence, ballistic spit and settled puddle. |
| Hammer | Release through cooldown, damage frame, charged self-hit, quake duration and grounded toss; restored ready state. |
| Trident | One/two/three-ammo volleys, three muzzle offsets, convergence, supercharge and liquid radius. |
| Zeus | Delayed target selection, branching timed bolts, per-zap damage bands, miss rules and tracked beam presentation. |
| Silverclaw | Per-swing frame durations and one delayed swing sound. |
| Bolter | Alternating ammo transaction, flesh removal, water speed; absent Gold water sound explicitly unresolved. |
| Stavros | Acceleration/growth, splash-only blast, bounded bouncing fragments and silent expiry. |
| Ballista | Authored launch frame, midsection test, authored mass hold, wall-angle pinning, secondary-hit explosion and unobstructed radius damage. |
| Wyndrax | Authored launch frame, creature-only four-target zaps, hover/back-off, blue model and damaging fade. |
| Nightmare | Entity-order marking, timed reaper, persisted holds, separate controller references and release after reap. |
| Glock | 500 ms cadence and automatic ten-round clip reload. |
| Ripgun | 350 ms spin-up through `shoota`, 100 ms shots, run-on, looping fire animation and authored `spdn`. |
| Slugger | 4000-unit pellet reach, cadence and final-pellet impact. |
| Kineticore | Five-shot burst, recovery, accelerating projectile, recoil and owner-hit adjustment. |
| Novabeam | Supplied lifetime, per-tick ammo, decaying damage budget and shutdown. |
| Metamaser | Authored launch frame, first-triple muzzle, second-triple capacity/health/life, cube size, target locks and persisted controller ownership. |
| Cordite | Three-second fuse, delayed gravity, actor contact versus world bounce and supplied sounds. |
| Flashlight | Preserved intentional dk3 toggle extension; not a shipped Gold weapon. |

Verification also found two false assurances in prior evidence: optimized C fixtures
had `NDEBUG` enabled, and a literal sprite file existing did not prove that its
`@mark` shader existed. Assertions are now explicitly enabled, and Shotcycler's
mark has a source-owned material. Rejected logs are preserved beside the replays.

Final verification repairs:

- Shotcycler now binds a material actually packaged by the native runtime; the
  initial `NULL poly shader` failure is preserved in `selection-1.log`.
- Ripgun uses Gold's looping `shoota` spin-up and authored `spdn`; no `spup` exists
  in the supplied model. The rejected group log retains that crash.
- Nightmare, Zeus and weapon rings no longer misuse mover `parentId`. Weapon links
  use optional `weaponParentId`, so mid-action saves satisfy attachment validation.
- Metamaser's first offset triple is the muzzle; the second contains 30 charges,
  300 health and 19 seconds in this profile. Packed lock deadlines are now relative
  to the saved projectile birth time. Older packed absolute-time cubes keep their
  health/charges/phase and re-acquire locks on the restored clock.
- The old liquid-test coordinate was beneath the water brush. The corrected runner
  uses BSP-confirmed deep water and asserts server water level in every snapshot.
  `rejected-water-position.log` is not liquid acceptance evidence.

The historical sequence-199 broad suite result remains historical; its C assertions
were disabled at that time. Its liquid screenshots also did not establish an actual
submerged player. The assertion-enabled tests and saved water-level checks in this
sequence supersede those particular assurances.

Installed independent runtime:
`6a4d5a4263029b67c6f5618cd107e7cfef5923d89d35daf21ab845a6e3cb36b4`.
The live `zig-out/play/current` points to this generation. All engine scenarios used
dkguard, isolated homes/saves, native modules and software rendering. No Git operation
or original game/save write occurred. Evidence and reproducible drivers:
`zig-out/reports/weapons-gold-200`.

Remaining acceptance limits: exhaustive frame-by-frame Gold animation, sound mix,
view kick, trails/fragments and every targeting/campaign branch remain open. The
Bolter water sound is absent from the supplied assets. The run does not close the
whole rewrite roadmap or claim full audiovisual equivalence.

## readme-gallery — sequence 201

Captured and inspected three 1280 × 720 JPEG frames from the sequence-200 native
runtime: e1m1a marsh, e1dm1 Shotcycler firing, and native difficulty selection.
Engine runs used dkguard, software rendering, isolated homes and the local 1.3/HD
asset profile. The marsh uses a positioned noclip camera; the weapon scene grants
weapons/ammo. No campaign acceptance claim follows from these staged captures.

The initial capture attempt used stale view offsets and selected a weapon before
the inventory snapshot arrived. The corrected driver separates those commands;
`gallery2.log` and `gallery2-inputs.txt` record the accepted run. Private drivers,
logs and captures remain in `zig-out/reports/readme-gallery-201/`. The three reviewed
frames are copied unchanged to `docs/screenshots/` for the GitHub README gallery.
Only documentation and these images changed; no game suite rerun is required.

## readme-gallery — sequence 202

The owner flagged the README firing frame's prominent muzzle flash. Checked its
capture provenance: it came from the sequence-200 installed runtime and already
includes sequence 198's transparent additive flash material. The installed cgame
binary matches the latest local build; no newer local fix was identified.

Replaced the README firing frame with a fresh e1dm1 capture of the Shotcycler at
rest, using the same native runtime through dkguard and an isolated home. This is
a gallery presentation change, not an additional muzzle-flash repair or visual
acceptance claim. Inspected the unretouched capture and recorded reproduction
inputs in `zig-out/reports/readme-gallery-202/arena-settled-inputs.txt`.

## multiplayer-zig-203 — connected implementation and IP hosting

The accepted scope is in `docs/multiplayer-zig.md`. Active changes include native
Zig objectives, shared appearance catalog and converted skin bindings, equipped
melee presentation policy, music resolution, fragment channel and authenticated
UDP admission, coordinator persistence, worker supervision, guest identity client,
room membership/readiness and identity-bound votes. Focused acceptance results are
recorded below; the complete accepted scope remains in progress. Bot decisions,
remaining engine network paths and the full UI/recovery matrix are still open.

The owner provided one machine for coordinator and worker, and explicitly selected
IP HTTPS with a trusted test certificate. Coordinator and Caddy run as separate
unprivileged services. Credentials remain outside the checkout. The private test
CA was retrieved through SSH and configured explicitly; no global trust change.

| Scenario | State | Evidence |
|---|---|---|
| IP HTTPS with explicit CA | Passed | `zig-out/reports/multiplayer-zig-203/tls.json`: `/healthz` returned API 1 |
| Same endpoint without test CA | Passed | TLS certificate verification rejected the connection |
| Public creation/search/admission/game traffic | Passed (focused) | One host, DM, three encrypted native clients; full map/mode matrix remains open |
| Votes, reconnect, readiness, worker/coordinator recovery | Passed (focused) | Three-client Internet lifecycle replay; full abuse/recovery matrix remains open |
| Appearance | Passed (focused) | Three rendered character/color combinations; all 36 and equipped weapons remain open |
| Music transitions | Passed (focused) | e1dm1 through e4dm1 captured audio matches four distinct assigned songs; full map/override/fallback matrix remains open |
| Equipped weapons and campaign regressions | Unrun | Implementation does not establish full acceptance |
| Two distinct worker hosts | Blocked | One machine supplied; same-host coordinator/worker is the selected first deployment |

The first native HTTPS request failed with `TlsInitializationFailed`. Source review
found that Zig 0.16 `Certificate.verifyHostName` handles DNS SANs but skips IP SANs.
The adapter now uses the already-admitted libcurl dependency with peer verification
and IP/hostname checks enabled. Replayed native `dk3-online ... list` returned `[]`
with the test CA, and `CertificateVerificationFailed` without it. This verifies the
native transport trust boundary, not room or gameplay acceptance.

The first real Internet room probe succeeded: the native guest client authenticated
by Ed25519 challenge, created a DM room, found it through the public service, waited
for worker ticket acknowledgment, and joined the remote dedicated process. The local
rendered client used dkguard software rendering. Movement/attack input, continuing
snapshots and a bot killing the human were observed. Server status reported one human;
server logs showed distinct Hiro and Mikiko bots. Evidence: `internet-1.log`,
`internet-1-inputs.txt`, and the local capture
`/tmp/dk3-multiplayer-zig-203/internet-1/dk3/screenshots/internet-room-203.jpg`.
This is one public host running coordinator and worker, not two-worker acceptance.
The capture includes the harmless result of issuing the local `status` command in a
remote client; use server/client-specific status commands in subsequent probes.

This probe does not certify voting, restart/readiness, content rejection, recovery,
packet-fault handling, the complete UI, or the wider Zig migration. A follow-up change
uses the standard acknowledged map restart after readiness and varies bot colors as
well as models in the first few assignments; those changes remain unverified.

The follow-up integrated build passed. Focused `zig build test-online` checks cover
single-use Ed25519 proof, idempotent allocation, sticky draining and reserved capacity,
transaction rollback on invalid worker reports, authorized moderation acknowledgments,
and AEAD replay/tampering/reordering. Seven checks passed after adding forged-counter, ciphertext, nonce exhaustion and reconnect-key cases. They do not replace native
packet-fault scenarios or the final broad suite.

The coordinator/worker upgrade drained the already-empty host, took a private SQLite
snapshot (`integrity_check = ok`) and re-enrolled the new compatibility manifest. An
additional live snapshot restored into a separate local coordinator, preserving room
IDs and returning healthy status. Evidence: `backup-restore.json` and
`restore-probe.log` under the sequence-203 report directory. Backups remain outside
the checkout because they contain private control state.

The first lifecycle sequence passed public allocation, mismatched-rules rejection,
three simultaneous encrypted clients and readiness-triggered match restart. The
browser step then exposed the engine startup argument parser treating `//` in the
HTTPS URL as a comment, leaving `https:`. First evidence is preserved in
`internet-lifecycle-attempt1.json` and `lifecycle-url-failure.log`. The startup argument
builder now quotes URLs/comment markers and empty values. Replay is in progress.

The URL-parser repair passed the full replay in `internet-lifecycle.json`. The
native browser listed the public room and measured UDP RTT; native fresh-ticket
reconnect retained guest identity. With the coordinator stopped, the client received
more than ten continuing authoritative snapshots; after restart the worker reconciled
three humans. A two-yes kick vote removed its identity-bound target, whose fresh-ticket
reconnect was then rejected by the persisted room ban. Authenticated operator removal
reached the game and cleared its pending acknowledgment. Restarting the worker ended
the match as failed without recreating it. Input/log evidence is `lifecycle-[1-3]*`,
`coordinator-outage-client.log` and the structured lifecycle result. These passing
cases apply to the pre-codec-migration build; network changes require relevant replay.

The remaining message codec migration now has Zig scalar/bit, user-command,
entity/extension and player-state schemas. The original licensed C codec is excluded
from the active engine build and retained only as a differential-test reference.
Huffman compression remains a reviewed upstream C dependency. Compilation and
wire-comparison checks are in progress; no gameplay acceptance is claimed for this
new codec yet. Remaining sockets, connections, snapshot scheduling, replay/prediction,
bot decisions and other accepted modules still require migration and verification.

The codec integrated build and all three differential/bounds checks passed. The
three-client public lifecycle sequence then passed again with Zig codecs on both
ends (`internet-lifecycle.json`; prior results retained separately). The bounded
UDP fault proxy passed: 284 dropped, 342 reordered, 123 duplicated and 131 tampered
packets, with 222 progressing client snapshots after movement/attack input.
Evidence: `packet-faults.json`, `packet-faults.log` and its input trace. A first proxy
fixture failed because a loopback-bound socket cannot send to the public server;
its log is retained, and the repaired fixture accepts client traffic only from
loopback while allowing the server reply address.

These results do not complete the remaining engine/gameplay migration, map/mode and
appearance matrix, both-renderer acceptance, vote-abuse cases, campaign replay or
final broad suite. Two-worker-host acceptance remains blocked by the single supplied
host. No preserved installation or saves were repointed or overwritten.

A focused appearance probe rendered Hiro/Gold, Mikiko/Blue and Superfly/Orange in
third person. The game log shows the population controller independently choosing
Mikiko/Blue and Superfly/Orange for its two bots alongside the human. Evidence:
`appearance-probe.json`, inputs and local screenshots under the isolated
`appearance-probe` home. This demonstrates distinct models and body colors, not all
36 catalog entries or complete equipped-weapon/rendering acceptance.

The music probe routes only the owned test game's playback stream to a private null
sink and compares captured PCM with the assigned local Ogg track. e1dm1 and e2dm1
matched distinct authored songs with correlations 0.9997 and 0.9994. The e3dm1 client
then trapped in the OpenGL 1 renderer before capture; `music-e3dm1-first-failure.log`
and `e3-codec-debug.log` preserve the failure. Renderer diagnostics now retain
individual sanitizer trap origins rather than merging unrelated failure sites.
The remaining music/map replay is in repair; the two passing audio results stand.

The unmerged renderer backtrace identified the actual fault in `R_CullModel`:
`models/e3/a3_hlth.dkm.md3` had a null detail-level-one pointer. The loader split at
the first dot, interpreting the independent `a3_hlth_2.dkm.md3` pickup as a detail
level, then counted two loaded files despite the hole. Both renderers now split at
the final extension, fill missing detail slots from an available model, discard failed
loads and require alternate levels to share the base animation frame count. The
integrated build passes. e3dm1 rendered and accepted movement with OpenGL 2; inspected
`e3-lod-repaired-opengl2.jpg` in its isolated home. OpenGL 1 music replay also reached
both e3dm1 and e4dm1 without the crash. `e3-model-origin.log` retains the named model,
null slot and backtrace; the broader renderer/map matrix remains open.

The repaired OpenGL 1 replay traversed e1dm1, e2dm1, e3dm1 and e4dm1 in one
client and captured each map's audio. Long-window correlation thresholds initially
misclassified e4dm1's noisy ambient mix; muting `s_volume` also muted music and was
discarded as an invalid fixture. The final analysis compares nine consecutive
one-second windows per map against all four reference songs. Every window selects
its assigned song, with matching source positions advancing at playback speed
(maximum timing spread 0.273 ms). `music-continuity.json`, `music-analyze.py` and
`music-transitions-filtered-inputs.txt` retain the measurements, method and game
inputs. Earlier correlation attempts remain recorded separately. This verifies
four distinct songs and map handoffs, not the full soundtrack, looping, authored
triggers, fallback behavior or physical-speaker mix.

Final hosting check: Caddy, coordinator and worker are active, explicitly trusted
HTTPS is healthy, and all test allocations are terminal (`final-host-health.json`).
The owned audio probe sink was removed; private recordings remain local. Canonical
play installation and saves remain unchanged. The complete accepted migration and
final broad acceptance suite are still pending.

## launcher-compatibility-204 — preserved installation launch

The user reported `dk3` failing because the preserved sequence-200 installation
has no `rules.json`. The current launcher incorrectly applied newly introduced
online metadata requirements to that older installation. Launch validation now
accepts legacy format-1 manifests without online metadata, while format 2 requires
both `rules.json` and `compatibility.json`. Transitional format-1 online installs
also verify both files. New installations write format 2. Missing or altered
required files still fail validation; no current metadata is copied into old builds.

Both focused runtime-media tests pass, including preserved launch, current and
transitional online metadata integrity, and shader updates preserving asset identity.
The existing fixture now supplies valid package archives and rules JSON.
The actual user `dk3` command rendered the main menu under dkguard software rendering
and exited normally, using an isolated home. Evidence is in
`zig-out/reports/launcher-compatibility-204/`, including the input command, log and
capture path. The first probe omitted its test home `dk3` directory and could not
create its command pipe; its log is retained. Creating that fixture directory
allowed the replay to pass. The preserved installation pointer, files and user saves
were not changed.

## online-menu-205 — launch the online build and exercise room controls

The user could not find Internet room controls because `dk3` still selected the
preserved pre-online build. Installed the verified sequence-203 runtime separately
under `zig-out/online/play/`, with its appearance bindings, existing local HD
artwork, compatible metadata and an isolated profile. The local `dk3` wrapper now
selects this installation. Its profile configures the provisioned IP coordinator
and explicit test CA. `dk3-preserved` retains the former command, installation and
saves; the old `zig-out/play/current` pointer is unchanged.

Using the actual `dk3` wrapper through dkguard software rendering and a separate
probe home, normal keyboard navigation opened Multiplayer, Create Internet room,
then Create room and join. The rendered client joined the public server. After
disconnecting, Internet rooms listed the allocation; selecting it and Join selected
room established another authenticated connection. Inspected the multiplayer,
creation, browser and join-action captures. The controlled test allocation was
ended afterward. Evidence: `zig-out/reports/online-menu-205/` contains installation
identities, input command, key trace, client log and scenario results. This verifies
the visible create/find/join paths, not every menu option or the complete port.

## scoreboard-206 — aligned values and hold-to-show controls

The reported scoreboard placed headers using spaces in a proportional font, while
rows used fixed coordinates: score values appeared beneath the Ping heading.
Headers and values now share column coordinates, and names are clipped to the
available name column. Visible multiplayer boards request refreshed authoritative
scores every two seconds, including automatic death/intermission views.

Tab now defaults to `+scores`, with a Show scores (hold) control in the Keyboard
menu. A one-time UI profile upgrade fills an unused Tab binding for existing asset
installations; it preserves custom bindings and later deliberate unbinding.
The native game-module build passed. Installed the updated client-game and UI
modules as a new immutable generation of the online runtime; protocol, gameplay
metadata, server processes, prior generations and user saves were unchanged.

The actual `dk3` wrapper ran an isolated local DM scenario under dkguard software
rendering. Real Tab key events displayed the board, a normal suicide changed the
authoritative score from zero to minus one while Tab remained held, and the board
remained visible through respawn. Releasing Tab immediately restored the HUD;
another press/release repeated that behavior. Inspected the aligned headers,
negative score and released-state captures. Separate startup probes verified a
custom Tab binding and an intentionally unbound upgraded profile survive startup.
Evidence: `zig-out/reports/scoreboard-206/` contains build/deployment identities,
input commands, key trace, logs, capture paths and binding results. No public match
was interrupted or restarted for this client presentation repair.

## empty-rooms-207 — explain empty Internet browser results

The user saw no room rows while the footer said to select a room. Authenticated
host status confirmed there were no active allocations. The browser now reports
no public rooms with guidance to return and create one, or no matching rooms with
filter/refresh guidance when returned rooms were filtered out. Nonempty results
retain the selection prompt. The engine build passed; the new client was installed
as another online runtime generation without changing the server or user profile.
Native empty-browser verification is recorded under
`zig-out/reports/empty-rooms-207/`.

A public `My room` allocation appeared during verification, so the original empty
server assertion no longer applied. The replay refreshed the populated browser,
then used an isolated-profile search that matched no rooms and verified the new
filter guidance in the rendered menu. The live user's room was not changed or
stopped. The no-public-room branch was built but was not replayed against an empty
live service after that allocation appeared.

## rpm-bundle-208 — local assets and default Internet service

The user requested an RPM including game assets and the default online server for
another machine. Added an RPM spec, desktop launcher and manifest-verified packaging
script. The local x86-64 bundle contains the current native runtime, converted game
packages, selected HD/appearance artwork, dkguard, online guest CLI, component
notices and public CA. Fresh per-user profiles receive the IP coordinator and CA
path; later settings remain editable. Credentials, identities and saves are excluded.
It does not install hosting services or change either development launcher/profile.

Built `dk3-0.1.0-208.fc43.x86_64.rpm` (1,756,097,472 bytes) under `zig-out/rpm/RPMS/`.
RPM digest verification passed; all 278 regular payload files matched their staged
hashes after extracting the finished RPM. Relative module links resolved, packaged
paths were limited to `/usr`, and the desktop entry validated. The first rpmbuild
attempt needed sandbox approval for its `/var/tmp` scripts; the approved replay
completed. No host installation was performed.

The extracted package launched under dkguard software rendering with fresh XDG
data/state directories. Its generated profile used the packaged IP endpoint and
CA. The first Internet request timed out; the log is retained. Direct HTTPS with
certificate verification then passed, and the unmodified packaged-client replay
successfully listed rooms and exited normally. Evidence is under
`zig-out/reports/rpm-208/`; the package has a SHA-256 sidecar. This verifies local
package integrity, startup and default HTTPS room access, not installation or a
new gameplay session on a second physical machine. Assets and the RPM remain local.

## permanent-rooms-209 — server-owned population and timed rotation

The owner requested configurable permanent rooms and explicitly required keeping
the distributed client unchanged. Implemented a private hosting policy in Zig,
coordinator reconciliation and worker capability negotiation, plus dedicated-only
engine hooks for bot replacement, population filling and elapsed-time rotation.
Public API structures, client/browser code, game module, compatibility metadata and
the sequence-208 RPM remain unchanged. Permanent assignments use stable room IDs
and monotonic generations; confirmed process exit and a 30-second backoff precede
recreation. Unreachable workers retain their reservations. Changed/removed config
drains the old allocation. Empty rooms do not expire or transfer to human owners.

The server fills 16 total occupied slots by default, counts connecting humans as
reservations, displaces a bot only after authenticated admission, and replenishes
vacated slots through the existing bot controller. Bot startup is progressive,
roughly one per second. The default ten-minute rotation uses normal map transitions
without waiting for ready votes. Public occupancy remains the existing human count
so the old client's availability filter still offers a room full of replaceable
bots. The browser's existing map field follows the actual rotation.

Deployed coordinator, worker and dedicated binaries to the idle provisioned host
after draining it and taking private config/binary/SQLite backups. Gameplay-module,
rules and compatibility file hashes matched before and after deployment. Configured
**dk3 Always DM** with 16 slots, skill 3 and `e1dm1 → e2dm1 → e3dm1 → e4dm1` every
ten minutes. Worker capacity is now two, with a 1 GiB per-room limit beneath the
existing 2560 MiB service cap, leaving one allocation for a player-created room.
Configuration and operating details are in
[online operations](../../docs/online-operations.md#permanent-rooms).

| Scenario | State | Evidence |
|---|---|---|
| Old worker response and client room schemas, empty expiry exemption, generation fencing/backoff, config removal and map validation | Passed | Ten focused online tests, including three new permanent-room cases |
| Empty local room fills 16 bots; unchanged RPM joins and replaces one bot; departure restores 16 bots | Passed | Isolated dkguard server/client, local status and logs |
| One-minute local rotation retains the connected human and wraps to the first map | Passed | `e1dm1 → e2dm1 → e1dm1`, 1 human and 15 bots |
| Distributed RPM discovers and joins live permanent room through actual Internet menus | Passed | Inspected room-list, join-action and 16-player scoreboard captures; 1 human/15 bots after join, 0/16 after departure |
| Live ten-minute rotation and continued empty-room operation | Passed | After 3270 seconds, generation 1 had traversed all four maps, wrapped and advanced again; coordinator and engine agreed on e2dm1, with 16 bots and no worker restart |
| Permanent allocation recreation and bounded service logging | Passed | With no humans or pending joins, ended generation 1 for the worker logging update; generation 2 returned after the backoff, filled 16 bots and wrote to the service journal without an engine.log file |
| Unchanged client delivery | Passed | Original public API/browser/client source hashes and 1.7 GB RPM SHA-256 all match; no client rebuild or reinstall |

The dedicated build initially used an unavailable filesystem function; changing the
private status writer to the engine's home-data file API fixed that build failure.
The first aggregate check found a stale `va(char *)` declaration in the synthetic
gameplay fixture, conflicting with the current `va(const char *)` engine header.
Corrected that fixture only. The replay passed all 44 Python tests; all 138 Zig tests
passed. Permanent workers also stream engine output into the bounded service
journal so an indefinitely running room does not hit the engine-log file-size cap.
The worker rebuilt successfully after this logging repair.

Evidence lives under `zig-out/reports/permanent-rooms-209/`: local and Internet
commands, input traces, scenario results, captures in isolated temporary homes,
deployment hashes, continuity history and broad-check logs. Full CTF/deathtag,
maximum-human/concurrent-join and multi-worker failover matrices remain unrun for
this policy. The complete multiplayer migration and second-physical-client-machine
acceptance remain open. No Git operations or client-package changes were performed.

## online-latency-210 — distinguish server timing from connection stalls

The owner reported delayed movement/hits and jumping players on the development
machine, and requested leaving Wi-Fi and VPN settings alone. Inspected the host
and reproduced the symptom using the unchanged sequence-208 RPM in temporary
profiles under dkguard software rendering. No gameplay code, installed profile,
RPM, server configuration or network configuration was changed.

| Measurement | Observed result |
|---|---|
| Dedicated host load | Game process about 4.5% CPU and 80 MB RSS; sampled host CPU 97–98% idle, no swap activity or observed steal time |
| Router reachability | Initial 30-probe sample had 1.6 ms minimum and 1166 ms maximum RTT; saved 40-probe replay had 10% unanswered probes and 298 ms maximum RTT |
| Direct server probes, explicitly bound to Wi-Fi | Saved 40-probe sample: 5.5 ms minimum, 311 ms maximum RTT and 15% unanswered probes |
| Actual server-to-client gameplay sends | 384 messages over approximately 20 seconds: 19.2/s, median spacing 50 ms, maximum 100.3 ms, no gap over 150 ms; about 8.7 KB/s UDP traffic |
| Actual inputs arriving at the server | Maximum inter-message gap 2052 ms; 27 gaps over 150 ms in the same capture |
| Client's default-setting gameplay sample | 320 decoded snapshots, maximum arrival/processing gap 1743 ms, median reported ping 216 ms |
| Higher client limits in an isolated profile | `rate 90000`, `snaps 60`, `cl_maxpackets 125` did not remove long gaps; the final sample still had a 2516 ms gap. These settings were not applied to the user's profile |

The server's regular sends do not explain the multi-second receive stalls. Router
and direct-server probes also show local network jitter independent of the VPN
route. This supports investigating the connection before changing simulation
timing; it does not prove a particular driver, power-saving or access-point cause.
During inspection, the normal route used `prrr0` and Wi-Fi power saving was on.
Before the owner's restriction, a live NetworkManager power-saving change was
attempted and rejected because reapplication was unsupported; no reconnect or
profile change occurred. Subsequent read-only checks confirmed the original route,
power-saving state and default profile setting. Wi-Fi/VPN changes were then excluded.

The first UDP discovery probe exceeded the server's per-address query allowance,
so its timeout count is not used as gameplay-loss evidence. An initial server
packet observer captured only incoming IPv4 traffic; the corrected ETH_P_ALL
observer distinguished directions and returned summary metadata without packet
payloads. One observer timed out on SSH, then a shorter capture completed. Client
ping values of 999 are fallback values when the sent-command history cannot match
the snapshot; they are not treated as measured 999 ms RTTs. Headless rendering is
not a measurement of the user's physical display performance.

Evidence: `zig-out/reports/online-latency-210/` contains host load, router/direct
probe logs, the final server timing summary, client snapshot traces and isolated
captures. The lag was reproduced and localized beyond normal server send timing;
it is **not fixed**. No speculative server tuning or client rebuild was deployed.

## gameplay-bugs-211 — lifts, save selection, effects and actor timing

Implemented the owner's connected gameplay/UI repair batch. Called vertical trains
whose automatic return corner omits a wait now dwell for three seconds; explicit
waits and button-only stops retain their authored behavior. Starting a train leg
clears its previous think deadline, and linked binary movers dispatch arrival
targets once through their master. Actor think runs each server frame and movement,
gravity, turning and corpse fade use elapsed simulation time instead of advancing
50 ms after an arbitrarily late think. Visible civilian witnesses can react beyond
the short voice-alert radius, with range and architectural occlusion retained.

Save rows commit selection on click; hovering another row or the Load button does
not replace it. Panel widgets take precedence over the overlapping menu-strip hit
area. Extra Options no longer repeats difficulty; it offers archived Shiny Weapons
Off/On/Enhanced settings, backed by a view-dependent additive reflection pass for
held weapons. This is an independent effect, not established original-renderer
parity. The Glock muzzle model explicitly uses its supplied texture with additive
blending. Ion terminal bursts select the supplied explosion sounds instead of
always layering the metallic ion-hit sample; flesh contacts emit one terminal
burst, while wall bounces retain their electrical feedback.

| Scenario | State | Evidence |
|---|---|---|
| e1m2a button lift t424: board, press physical button, ascend, dwell, return with rider | Passed | `lift-cycle`: `cin_skip`, test positioning at -1544 -335 -520, `dk3_look 270 8`, ordinary `use`; saved samples show z -552 → -376, a 3001 ms return deadline and return to -552. This is focused lift acceptance, not campaign traversal. |
| Click save row, hover Load at its right edge, click to restore | Passed | `probe-focus`, XTest mouse input on the dkguard-owned display; inspected selection and restored-game captures |
| Difficulty screen and Extra Options | Passed | Inspected three difficulty figures and options panel with no second difficulty control |
| Glock flash and weapon shine | Passed | OpenGL1 captures show additive flash without a black rectangle; Off/On/Enhanced captures show the held-weapon reflection levels |
| Ion hits on workers | Passed | `ion-workers.log`: 30-damage worker hits followed by `we_ionexplodeb/c`, no `we_ionhit.wav`; sound dispatch traced with `s_show 1` |
| Worker death with an uninjured surviving witness | Passed | `worker-panic-final`: aimed Slugger shot kills the first worker; the second remains at 50 health and enters flee state, confirmed in trace and save. |
| Actor elapsed-time gravity and witness occlusion/range | Passed | New native fixture calls actual actor physics: 400-unit fall/800-unit velocity after one second at 10/20/40/50 Hz. Actual alert code accepts a visible worker 450 units away and rejects walls/out-of-range witnesses. |
| Full campaign, every lift and original-renderer effect parity | Unrun | Focused repairs do not establish these broader acceptance groups. |

ReleaseSafe integrated build and development installation pass. `make test` passes
all 45 Python checks and its Zig checks; no duplicate broad suite was run. Evidence
is under `zig-out/reports/gameplay-bugs-211/`, with isolated homes under `/tmp`.
Initial driver failures are retained: X input required selecting/focusing the
isolated client and sending relative motion; e1m2a required skipping its camera,
waiting for save completion, and aiming at the actual button. Initial worker
shots missed moving actors or placed both workers on the same firing line; these
are not treated as witness-acceptance results. Shader/UI captures use software
OpenGL1, not the physical display or an OpenGL2 parity comparison. The supplied
private asset packages, preserved installation/saves, live online server and
published RPM were not replaced. No Git operations were performed.

The usual `dk3` launcher targets `zig-out/online`, whose live-room rules fingerprint
is older than this gameplay repair. It remains unchanged. Added `dk3-dev` targeting
the verified `zig-out/play/current` installation for the fixed campaign build;
existing development saves/settings remain in that prefix. No live-server update
or fingerprint bypass was performed. The fixed build needs matching gameplay
rules to join a multiplayer room. The successful worker replay used separate view
updates before spawning and selected the weapon after the give commands completed.

Owner follow-up identified the latest save. Inspected the actual online profile's
`save1.sav` (campaign e1m3a), copied it into the isolated `latest-save-lift` home,
and restored it with the repaired build. The nearby `bigplat` train travels between
`t539` (button-only lower stop, authored wait 10) and `t540` (automatic upper stop,
no wait). From the owner's unchanged saved position, aimed at the nearby button
with `dk3_look` and issued ordinary `use`. Recorded 21 saved samples: lift z -902 →
-274, 3001 ms top dwell, then return to -902 and button-only rest. Player snapshots
confirm the rider traveled with it. This verifies the owner's exact lift, not just
the earlier e1m2a analogue. No additional implementation changes or duplicate broad
checks were needed. Source save SHA-256 was checked before and after and matched.
Evidence: `latest-save-lift.py`, `latest-drive.py`, `latest-lift-cycle.json`, logs
and captures under the sequence-211 report/isolated home.

## train-wait-212 — correct departure-corner wait semantics

The owner's request to inspect Gold revealed the actual cause behind sequence
211's lift workaround. Private reference review of `dlls/world/DOOR.CPP`,
`train_next` (around lines 3137–3201) and `train_wait` (3305–3345), establishes that
train travel copies the departure corner's wait and applies it after arrival.
A positive wait is handled before the destination's WAITFORTRIGGER flag. Original
`train_use` ignores use while the train is moving. No reference implementation or
assets were imported into the independent project.

For the owner's e1m3a `bigplat`, departure t539 has wait 10; arrival t540 has no
wait. Original behavior therefore dwells ten seconds at the top, returns using
t540's zero wait, and stops at t539 until triggered. The earlier claim that the
missing upper wait explained original behavior was incorrect: sequence 211's
three seconds was an independent workaround, not parity. This section supersedes
that interpretation and dwell acceptance.

Implemented departure wait capture in the existing persisted train `wait` field,
removed the three-second fallback, retained positive-wait precedence, and made
ordinary use during travel leave the train moving. Initial train placement clears
the leg wait before dispatching its first movement. Implementation initially
unverified; focused replay results are recorded below.

| Scenario | State | Evidence |
|---|---|---|
| Owner's save1/e1m3a physical button activation | Passed | Restored an isolated copy; ordinary `use` at the saved position starts bigplat. |
| Departure wait survives save/load during ascent | Passed | Mid-motion save contains train wait 10; restored ascent reaches the upper stop with a 10001 ms think deadline. |
| Authored upper dwell and return | Passed | 42 recorded samples show z -274 held for ten simulation seconds, then return to z -902 with trigger-only rest and the rider carried throughout. |

ReleaseSafe build and development installation pass. `dk3-dev` now points to the
corrected generation. The source save hash is unchanged; online launcher/server
and RPM remain untouched. Evidence is under `zig-out/reports/train-wait-212/`.
Full train scripting, every authored route, and older mid-action-save migration
are not established by this focused replay.
The applicable `make test` aggregate passed after the replay (45 Python checks
and the Zig checks); no duplicate aggregate was run for this correction.

## launcher-fixes-213 — normal dk3 uses the repaired build

The owner correctly reported that `dk3` still launched the pre-repair online
installation. Updated that launcher's installation pointer to a new immutable
local generation containing the verified sequence-212 binaries/modules/shader.
Retained its appearance overlay and all 51 existing profile files (saves/settings
hashed before and after, unchanged); retained the previous installation. This
supersedes the sequence-211/212 decision to leave normal `dk3` on older code.
No game source or live-room server was changed. The new gameplay fingerprint
requires matching multiplayer servers; old live-room compatibility was not forged.
Evidence: `zig-out/reports/launcher-fixes-213/`.
Focused launch verification passed through the actual `~/.local/bin/dk3` command
under dkguard software rendering with an isolated profile. Checked the running
executable path against the new generation and restored a copy of the owner's
latest save successfully. No duplicate game build or broad suite was necessary
for this installation-only correction.


## crouch-load-214 — Gold crouch clearance and direct saved-map loading

The owner reported the e1m3a triangular opening as impassable while crouched and
Marsh loading before every requested saved level. Private Gold review of
`base/qcommon/pmove.cpp`, PM_CheckDuck around lines 1118–1167, confirms crouched
bounds z -24 to 4 and eye offset -2. The independent shared movement constants
previously used max z 16 and eye 12: a 40-unit body instead of 28, with the camera
14 units too high. Corrected the shared server/prediction bounds and eye height.
No private implementation or assets were imported.

The disconnected load menu explicitly started e1m1a to reach the server save
reader. Added an engine command that uses the existing portable save parser and
safe save-file interface to validate the slot/checksum, read campaign map/skill,
check map availability, stage the save and start the saved map once. Full game
schema validation and reconstruction remain in the game module. Menu resume also
stages the saved visited-world archives. Invalid preflight requests leave the
menu available and start no world; successful retries clear the error message.
The parser now builds in the engine client as well as the game module. Existing
in-game load behavior remains available.

Implementation initially unverified; integrated results:

| Scenario | State | Evidence |
|---|---|---|
| Owner save3 and pictured triangular opening | Passed | Restored an isolated copy of save3, navigated with ordinary movement, crouched through the exact red-corridor opening: (2341,207,-168) to (2341,136,-168), crossing y192. Entry/exit screenshots match the reported location; eye offset -2. No teleport, noclip or modified save used. |
| Low ceiling and safe crouch release | Passed | Shared PM_CheckDuck fixture rejects standing under a 32-unit ceiling, fits crouched, retains crouch under the ceiling, and stands again with clearance. |
| Disconnected mouse save selection then Load | Passed | XTest clicks the quick row, moves to Load, clicks it; one server initialization, e1m3a, no Marsh bootstrap. |
| Corrupt save and subsequent valid retry | Passed | Checksum failure starts no map; valid save3 copy restores directly into e1m3a once. |
| Previous-save recovery and visited worlds | Passed | Corrupt primary/valid previous restores directly; a subsequent save retains the six archived worlds (intro through e1m2b) unchanged. Initial evidence parser used the wrong field name; corrected it to snapshot and checked the existing saved result. |
| Normal dk3 launch installation | Passed | New immutable local generation retains the appearance overlay, previous installation and all 53 existing profile files, hashed unchanged. Actual launcher smoke verifies the executable and direct owner-save restore in an isolated profile. |

ReleaseSafe build and development installation pass. The applicable `make test`
aggregate passed once (46 Python checks and the Zig checks), including the new
clearance fixture. No duplicate broad suite was run. Initial scenario assertions
looked for an absent InitGame console marker; corrected to Server Initialization.
Early navigation captures were not acceptance of the exact doorway; the final
triangle-entry/triangle-passed captures and saved positions establish that result.

Local evidence: `zig-out/reports/crouch-load-214/`, with isolated captures/saves
under `/tmp/dk3-crouch-load-214/`. Normal installation generation:
`ed85b930d2cf0fdf50726846fff68389dbfa200f2abb967124a3f91212ff5d33`.
Full campaign traversal, every clearance shape, original-save migration and live
multiplayer server updates remain outside this focused acceptance.

Owner follow-up confirms the reported issues now work correctly in their own
play session and authorizes committing and publishing all pending project code.

## superfly-cinematic-215 — First conversation and rescue trigger parity

The owner clarified that Hiro dies after the **first** conversation with Superfly
on the e1m3b torture rack. Reproduced with a copy of the owner's save2: walking
past the rack spawns gameplay Superfly at world origin, then he falls below the
world and companion-death handling kills Hiro. The first-death baseline records
Superfly at z -400 immediately after crossing and below -131000 before failure.
No damage cheat or noclip was used. Localized `setviewpos` positions shorten the
route; ordinary forward input crosses the encounter/spawn volumes.

Private Gold reference review:

- `dlls/world/Sidekick.cpp`, trigger_superfly_spawn/use: nonsolid, use-only marker;
  spawn at the marker's upper world-space brush corner, not the activator.
- `dlls/world/DOOR.CPP`, train_find/train_next and hierarchy handling: child offsets
  derive from the train's authored origin and follow initial/teleport placement.
- `dlls/world/cin_playback.cpp`, QueueTriggerBrushUse and SpawnHiroActor: cinematic
  uses resolve unique IDs; the gameplay player becomes nonsolid and frozen.

Independent repairs make companion spawn markers script-only, restore those
callbacks/contents in existing saves, and use the authored world-space position.
Train initial placement and teleport corners now translate descendant attachments.
An optional `dk_assemblyversion` field allows conservative repair of identifiable
old, stationary initial placements without reinterpreting arbitrary saved motion.
Script uses resolve unique IDs as well as target names, retaining target-name
broadcasts without calling a doubly named recipient twice.

Zero-delay cinematic triggers begin immediately; player trigger processing stops
as soon as playback starts. Hiro becomes nonsolid during playback and manual use
is suppressed. Previously the adjacent rack-return trigger could activate while
the conversation was running, bringing its second prop into the scene too soon.
The rack-return trigger remains available after playback ends.
No private source implementation or assets were imported.

Implementation initially unverified; integrated scenario results:

| Scenario | State | Evidence |
|---|---|---|
| Existing owner save, first conversation | Passed | Original save2 loads without the new optional field. Attachment repaired to (-1980,456,88); three cinematic captures/snapshots show one cine_superfly, no initial superdeco and the replacement prop still at its waiting position. |
| First conversation then crossing spawn marker | Passed | Ordinary movement crosses the volume; no gameplay companion appears; Hiro remains at 93 health after 30 seconds. Baseline reproduced the fatal out-of-world spawn. |
| Later keycard rescue | Passed | Key pickup and normal trigger crossing run the rescue cinematic. Unique-ID uses reach killdeco2/spawnsuper; exactly one living Superfly remains, and Hiro retains 93 health after another 30 seconds. |
| Post-conversation rack return and save/reload | Passed | Returning through the adjacent trigger moves the single prop from z88 to z28 after playback. Rack crossing remains nonfatal. Rescued save reload retains one living gameplay Superfly, no rack prop/cinematic actor, and living Hiro after 30 seconds. |
| Regression fixtures and broad checks | Passed | Attachment initial/teleport placement, nested children, conservative idempotent old-save repair, unique-ID-only uses and target-name broadcasts. `make test` passes all 48 Python checks; Zig checks pass with the existing unavailable-systemd-scope skip. |
| Normal dk3 installation | Passed | Updated immutable local generation; all 58 profile files hashed unchanged and appearance overlay retained. Actual dk3 launcher smoke verifies the updated executable and direct e1m3b owner-save restore in an isolated profile. |

Local evidence: `zig-out/reports/superfly-cinematic-215/`; isolated saves/captures
under `/tmp/dk3-superfly-cinematic-215/`. Owner save bytes remain unchanged.
This focused repair does not establish full cinematic animation parity or a
complete campaign traversal.

ReleaseSafe build and independent development install pass. Initial broad checks
were blocked by sandbox read-only compiler-cache access in six native fixtures;
the approved unrestricted retry passes. No code repair or repeated broad suite
was needed after that environment correction.

Normal installation generation:
`7884920588b8e6a5716f15925e58a6b70edb37af25d8194add44b186e371c690`.
Existing running processes need a restart to use these modules.

## laser-shutdown-216 — Clear the disabled laser circuit's damage field

The owner reports dying while crossing the e1m3b laser corridor after destroying
its control box. The latest quicksave contains no laser1/laser2/laser3 brushes,
but laser_dam still has CONTENTS_TRIGGER and 100 damage. Replayed an isolated,
unchanged copy with normal forward input from the saved position; the old build
kills Hiro in the visibly disabled corridor.

Gold `Triggers.cpp`, trigger_hurt_use/touch, toggles a persistent enabled flag.
The map's three moving laser buttons target that shared field, while the shutdown
event removes the buttons at 0/2/4 seconds and omits a hurt-field reset. This is a
scoped circuit correction, not a claim that Gold explicitly resets this field.
It clears only e1m3b's laser_dam after all three beam buttons are absent. Any
remaining beam keeps normal damage behavior. Other hurt fields/maps are unchanged.
The correction runs with world updates and checks again before hurt contact, so
existing saves with the stranded enabled field become safe without editing them.
Disabled hurt volumes also reject direct touch callbacks. No save schema change.

Implementation initially unverified; integrated results:

| Scenario | State | Evidence |
|---|---|---|
| Owner quicksave baseline | Passed | Three beams absent, field active; ordinary forward crossing kills Hiro. |
| Owner quicksave repaired and reloaded | Passed | Field clears on load, forward corridor crossing keeps 100 health; repeated traversal and save/reload retain 100. Some return paths descend below beam height and are not sufficient by themselves for reverse-side acceptance. |
| Both directions at beam height | Passed | Localized positioning followed by ordinary movement reaches (-144,1088,-129) and (-144,1063,-128), inside the former hurt volume, with 100 health from each end. |
| Fresh circuit weapon shutdown | Passed | Fresh level with weapons supplied for the probe; ordinary fire destroys the control box. After all three shutdown stages no beams remain and the hurt field is disabled. Captured box before/after. |
| Native regression and broad suite | Passed | Fixture covers remaining beams, complete shutdown, old-save state, unrelated maps/fields and idempotence. ReleaseSafe build and make test pass (49 Python checks plus Zig checks). |
| Normal dk3 launcher | Passed | Installed generation 63f989b8918d99e59675a86b6f94f084980f094362343e2e061b9c5de3bc6491; retained appearance overlay and all 62 save/settings files, hashed unchanged. Actual launcher restores a copied quicksave directly into e1m3b using the updated executable. |

Local evidence: `zig-out/reports/laser-shutdown-216/` and isolated profiles under
`/tmp/dk3-laser-shutdown-216/`. The original quicksave is hashed unchanged.
The laser control box is distinct from the box that exposes Superfly's keycard
behind the Mishima logo upstairs.

The first beam-height probe read a save before writing completed; the corrected
runner waits for the save and both directions pass. No code change or repeat
broad suite was needed after the scenario correction.

## Runtime Zig foundation — sequence 217

Accepted architecture: [native Zig replacement](../../docs/runtime-zig.md). Full
replacement remains open. This checkpoint implements parts of stages 1–2, not a
playable game or acceptance cutover. Legacy remains the ordinary launcher runtime.

Implemented: isolated native server/client/UI build and public ABI adapters;
archetype ECS with aligned chunks, explicit component IDs, generational handles,
persistent IDs, deferred commands and independent engine slots; bounded workers,
access/dependency scheduling and owner-thread collision; exact frame clock and
relative deadline helpers; map metadata retaining authored fields; portable save
record codec and read-only audit tool. A shared inventory acquisition transition
now serves legacy weapon code and the replacement Inventory component. Client/UI
entrypoints explicitly reject use; gameplay, player movement, weapon backends,
world behaviors, staged save reconstruction and cutover are not implemented.

The worker scenario exposed a queue-handoff race: after clearing the job slice,
`next` retained the completed batch's index and an idle worker indexed an empty
queue (`index 8, len 0`). Resetting the cursor under the same mutex and checking
exhaustion with `>=` repaired it. A 1,024-batch changing-queue regression passes.
The legacy build caught an allowzero C-pointer adaptation error; the adapter now
copies selection into a typed local and writes the result back before weapon
acquisition hooks.

| Scenario | State | Evidence / limit |
|---|---|---|
| Native replacement builds and ABI | Passed | Three modules compile without legacy C gameplay sources; public entity projection layout checked. |
| ECS, workers, scheduling and codec contracts | Passed | 15 replacement tests, including stale handles, structural barriers, ordered commands, frozen access declarations, batch handoff, owner affinity and 0/1/4-worker equivalence. |
| Real engine bootstrap/collision/restart | Passed | `runtime_probe.py`, `e1m3b`, 456 authored objects, 128 probe entities × 20 steps; identical hash `d3bcc3f6a1f26070` with 0/1/4 workers before and after restart. Temporary home, dedicated engine under dkguard. No campaign behavior demonstrated. |
| Existing save record compatibility | Passed | 22 local saves parsed and reproduced byte-for-byte, including latest 20,638,706-byte quicksave; before/after source hashes unchanged. Gameplay restoration is not qualified. |
| Shared inventory in legacy game | Passed | Isolated headless legacy build under dkguard, `devmap e1m3b`, `give weapons`, save inspection: all 28 ownership bits, initial selection preserved, paired Cordite ammunition 2. Harness initially used the wrong save-field name; corrected inspection of the recorded save passed. |
| Premature installation guards | Passed | Replacement rejects default prefix and `play-install`; normal launcher installation unchanged. |
| Broad checks | Passed | `zig build test --summary all`: 153 Zig tests, 49 Python tests; legacy native game build passes after C-pointer repair. No duplicate broad suite. |
| Replacement gameplay/client/UI/save restoration | Unrun | Required implementations remain open; bootstrap and codec results do not establish this acceptance. |

Reproducible commands are in `docs/runtime-zig.md`. Local inputs/logs/results are
under `zig-out/reports/runtime-zig-217`; assets and saves remain private. No normal
installation was updated. Continue stages 1–2 with actual player movement, shared
weapon backend extraction and ECS persistence mappings before world/client/UI
migration and implemented-scope acceptance.


## runtime-zig — sequence 218 (active implementation)

Continues the accepted full native rewrite. This sequence does not close the task
or authorize production cutover. Normal launcher/profile/assets/saves are unchanged.

Implemented: shared player movement and prediction with public ABI projections;
all 28 pure weapon descriptions/input policies and shared supplied-data parsing;
ECS weapon state and shot event delivery; native BSP/brush rendering; matching
source-identity checks; binary movers with grouped trajectories, delays/dwell and
transactional player pushing; use/proximity/rider activation; target/delay/killtarget
routing and basic once/multiple/relay/counter triggers. GPL movement provenance is
retained. The C differential baseline is test-only. Native combat dispatch, actors,
trains/secrets, scripts/cinematics, restore/travel and full presentation/UI remain
implementation work, not failed acceptance claims.

| Scenario | State | Evidence / limit |
|---|---|---|
| Native shared movement vs bundled baseline | Passed | Six 240-command runs compare origins/velocities within 0.05 and exact eye height on flat ground and in shallow/deep water. Includes diagonal walking, crouch, jump, swimming and gravity; other geometry/ladders remain unrun. |
| Shared weapon input policies | Passed | All 28 policies exercised without legacy engine globals; dedicated assertions for burst continuation, ten-shot reload, charged release and spin-up. No native damage/presentation claim. |
| Native e1m3b connection/prediction | Passed | `zig-out/reports/runtime-zig-218/movement218.log`; matched identity in userinfo, supplied weapon table read and client/server movement active. Standing/crouching captures inspected. |
| Delayed door repeated activation | Passed | `movers218.log`: id 255 remains opening after second activation, progresses from z=0 through z=27.5 and reaches authored z=122. This uses explicit diagnostic activation, not an authored puzzle replay. |
| Group rollback, crushing and rider transport | Unrun | Implementation connected; blocked/rider scenarios required. |
| Trigger/target/delay/killtarget progression | Unrun | Implementation connected; authored scenario replay required. |
| Mixed native build rejection | Unrun | Server and client rejection paths implemented; matching-build connect passed, intentional mismatch still required. |
| Native complete movement/weapon/actor/UI/save parity | Unrun | Significant implementation remains. |

Local diagnostics and captures stay ignored. Reusable isolated client runner:
`dkq3/tools/runtime_player_probe.py`; no original or converted assets are committed.
Existing-runtime and replacement module builds passed during connected development;
the aggregate suite passed 159 Zig tests and 49 Python tests. Full runtime acceptance remains pending.


## runtime-zig — sequence 219 (active implementation)

Train path legs, angular timing, departure-corner dwell, trigger-only rest, redirected
activation/elevators and teleport corners are connected. Attachment parent IDs,
cycle checks, pose preparation/rebase and whole-hierarchy initial/teleport movement
are implemented. Collision publication is transactional; deadlines advance and both
mover families finish before arrival targets run. Static brush roots support animated
children. Existing target queue capacity is preserved at 256 delayed actions.

| Scenario | State | Evidence / limit |
|---|---|---|
| Replacement domain checks | Passed | 26 tests: adds departure dwell/retrigger, angular timing, parent pose composition, nested teleport/door endpoint rebase and cycle rejection. |
| First diagnostic e1m3a board attempt | Failed input; corrected | `rider219.log` and `rider219-diagnostic.log` retained. Bounding-box-center placement put the player below walkable world geometry. Collision held the lift and player at the bottom. The board helper now rejects obstructed placement. |
| Valid standing position, repeated ascent activation, upper dwell and return | Passed | `zig-out/reports/runtime-zig-219/lift/`: 47 recorded samples. Lift z -902 → -274, wait 10000 ms, fixed due 13801, observed upper hold 9750 ms between polling samples, then z -902 / paused. Player carried to upper stop and returned to the bottom landing. Upper capture inspected. |
| Nested attachment placement | Passed (domain) | Preparing poses leaves ECS untouched; commit moves child/grandchild and rebases child-door endpoint. Real cinematic assembly/rendering is not yet accepted. |
| Compound obstruction / rotating riders | Unrun | Complete collision transaction code exists; richer scene validation remains. |
| Physical button, path targets, script/cinematic progression | Unrun | Diagnostic activation isolates train behavior. Scripts/cinematics are still implementation work. |

Reproducer: `runtime_player_probe.py --engine zig-out/play/current --prefix
zig-out/replacement --scenario lift`. It copies only native modules into a temporary
profile, invokes dkguard headless software rendering and keeps logs/inputs/captures
local. No normal installation or existing save was written. Aggregate checks from
218 remain recorded; replacement tests and affected engine scenarios were refreshed.


## runtime-zig — sequence 220 (active implementation)

Implemented secret-door two-leg travel, inter-leg pauses, return/stay-open behavior,
continuous rotation toggling and attachment integration. World ordering and trajectory
projection now have shared owners instead of duplicated module-entrypoint logic.

| Scenario | State | Evidence / limit |
|---|---|---|
| Replacement build and domain checks | Passed | Native products build; secret-cycle, stopped rotation and attached-child proposal/rollback checks pass. |
| e3dm1 secret door 43 | Passed | Both opening legs, open dwell, both return legs and closed rest recorded in `runtime-zig-220/secret/`; diagnostic activation only. |
| e1m3b rotation 72 | Passed | Rotation advances, holds exact stopped angles across samples, then resumes in `runtime-zig-220/rotation/`. |
| Affected lift and delayed door | Passed | Refreshed `runtime-zig-220/lift/` and `client/` preserve upper dwell/rider transport and repeated delayed-door activation. |
| Shooting secret doors, rotation riders, compound obstruction | Unrun | Shooting depends on native combat; other scenarios remain required. |

All engine runs use dkguard headless software rendering and isolated profiles.
No normal installation or save was written. Earlier aggregate checks remain valid
for unchanged components; no duplicate broad suite. Full rewrite remains open.


## runtime-zig — sequence 221 (active implementation)

Implemented keys, weapon/ammunition, health and armor pickup policies; ballistic
floor placement/bounce with supplied model bounds; resource configstrings and item
models; acquisition visibility/target dispatch and respawn deadlines; key ownership
checks; explicit weapon selection and server acquisition selection. Metadata is
shared through reviewed source definitions. Ammunition saturation and Gas Hands
duration policies are shared with the existing Zig weapon backend. Spawn mode/skill
filters now precede behavior registration while preserving map persistent IDs.
Tagged components no longer require meaningless zero initialization during relocation.

| Scenario | State | Evidence / limit |
|---|---|---|
| Domain/build checks | Passed | 37 replacement tests, native modules built. Covers union relocation, metadata/key composites, bounded acquisition, gas timing, model bounds and spawn exclusions/ID stability. |
| Initial e1m3b key/button diagnostic | Failed scope; corrected | `runtime-zig-221/inventory/` records collection and activation, but source review identified button 423 as co-op-only. Missing mode filtering was repaired; this result is not single-player progression acceptance. |
| e1m6a blue card and locked button | Passed | `runtime-zig-221/blue-card/`: item 2 settles, touch changes key mask to 1 and hides the item; button 85 stays closed before collection and opens afterward, activating four-way door 82. Explicit diagnostic placement/activation; key capture inspected, normal walking/cinematic path not certified. |
| Affected lift and delayed-door paths | Passed | `runtime-zig-221/lift/` and `client/`; same isolated runners after map-filter/item integration. |
| First aggregate build | Failed; repaired | C pointer nullability in `DK_AddAmmunition` adapter prevented legacy compilation and two Python contract tests. Fixed by validating the C pointer and passing a local typed value to shared rules. All 175 Zig checks had already passed. |
| Aggregate checks after adapter repair | Passed | `zig build game test --prefix zig-out/legacy-check -Dgame-runtime=legacy --summary all`: existing modules build, 175 Zig and 49 Python tests pass. |
| Pickup audio, boosts/statuses, platform-carried items, full progression | Unrun | Remaining implementation/acceptance; ordinary launcher stays legacy. |

All probes use dkguard and temporary profiles. Private assets, saves and captures
remain local. This is continuing implementation, not full rewrite completion.


## runtime-zig — sequence 222 (character state and sound events)

Implemented native character attributes/boost deadlines, protection/status pickups,
ring damage reduction, armor/protection accounting, and snapshot sound events.
Player snapshots project character state; domain movement parameters use attributes.
Weapon and ammunition pickup sounds now come from weapon audio definitions: reviewed
Gold defaults plus Ion/Shotcycler/Sidewinder/Shockwave ammunition overrides. Item
systems do not switch on weapon IDs for audio. No private code/assets were imported.

| Scenario | State | Evidence / limit |
|---|---|---|
| e4m4b speed and invincibility pickups | Passed | `runtime-zig-222/effects/result.json`: boost active then expired, protection blocks diagnostic damage then permits it after expiry; two snapshot sound dispatches. Diagnostic positioning/damage; physical audio and actual combat unqualified. |
| Native policies and projections | Passed | 41 native tests include character snapshot roundtrip, protection accounting and pickup class audio resolution. |
| Full weapon combat, actor reactions, HUD/status presentation | Unrun | These paths remain implementation work. |

## runtime-zig — sequence 223 (single runtime)

Owner explicitly requested removal of the old runtime. Removed C game/client/UI,
legacy module entrypoints, C-dependent weapon/multiplayer adapters and seven old
implementation fixtures. Pure weapon classes/policies, appearance metadata, online
services and networking remain. The engine builds client/server/renderers only;
legacy native/QVM module build paths are gone. Engine save-envelope validation moved
into engine infrastructure. Bundled movement is retained solely as a test reference.
Only Zig gameplay modules are built; legacy selection is rejected. Development play
uses a separate prefix/profile, explicit map and native development mode. The
preserved installed game, private reference, assets and saves were not modified.

| Scenario | State | Evidence / limit |
|---|---|---|
| Engine build after removal | Passed | `/tmp/dk3-native-only-engine.log`, client/server/both renderers, 14 build steps. |
| Integrated native modules and surviving suite | Passed | `/tmp/dk3-native-only-suite.log`, 179 Zig tests (including 41 runtime tests), 42 Python tests; all three native modules built. |
| Native client on rebuilt engine | Passed | `runtime-zig-223/client`: connect, movement/crouch/jump diagnostics and repeated delayed-door activation. New engine plus native modules, only asset packages reused, temporary profile; full campaign unqualified. |
| Retired fixture scenarios | Unrun for native acceptance | Actor witnesses, scripts, laser shutdown and full weapon firing remain open; deleting old fixtures is not a passing result. |
| Asset install/interactive play flow | Unrun | Build graph admits an isolated native prefix; full menu and campaign acceptance remain open. |

Architecture priority: connect native weapon events to hit/projectile simulation,
damage/death and actor reactions; then scripts/progression, restoration/travel and UI.
No legacy backend parity work remains in the development cadence.
