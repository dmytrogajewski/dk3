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
