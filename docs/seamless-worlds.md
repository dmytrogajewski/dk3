# Seamless connected worlds

Sequences 297–302 implement connected owners on `rewrite/native-zig-runtime`.
**The feature is incomplete. Ordinary campaign exits now use resident ownership.**
Automatic handoff is not acceptance of portal views or cross-world combat.

## Accepted outcome

Players retain uninterrupted movement and rendering across physically connected
maps. Enemies, projectiles, hitscan, explosions, visibility and sound can cross
their boundaries. Class-owned behavior, authored locks and companion requirements
remain authoritative. This intentionally extends original encounter behavior.

Load the complete connected region before releasing control. Prepare subsequent
regions during play and authored cuts; an authored cut may remain held until its
destination is ready. No loading screen or waiting barrier is permitted within a
ready region. Longer initial preparation and increased memory use are accepted.
Insufficient resources must be reported before region entry.

Use world-local coordinates and explicit portal transforms; do not merge BSPs or
guess connections from map names. Separate map ECS/script namespaces retain
authored local identity; cross-world references include stable world identity.
Transfer entities exactly once while preserving their original persistent IDs.
Do not start unexposed encounters merely because their assets were preloaded.

## Connected implementation so far

- Collision contexts have generation-checked handles, individually owned geometry,
  hearing/visibility data, portal state and temporary hulls. Selecting or tracing
  one restores the prior selection; active contexts cannot be released. Full map
  resets invalidate all resident handles and release their allocations.
- The engine opens independent loose/PK3 read streams using ordinary search-order
  and purity rules. Workers read/decompress their own streams, publish completion
  atomically and avoid engine FS tables, allocators and logging. Release cancels
  and joins the worker. Native requests are bounded to four readers.
- Versioned game imports request/poll/release resident collision, inspect its
  entities and memory, and trace its static geometry. The native owner survives
  normal frames and releases preparations on module shutdown.
- Collision admission currently decodes one completed map on the owner thread per
  frame. Its duration is logged; this is **not** a frame-time guarantee or a fully
  asynchronous world loader. Renderer, navigation and gameplay readiness are not
  implied by `collision_ready`.
- `campaign_connections.py` inventories the supplied converted maps, exact BSP
  hashes, shaders, authored exit bounds, landing candidates and reciprocal exits.
  It retains distinct connections between the same maps and reports ambiguous or
  missing named landings. It includes transition/ending maps without episode name
  prefixes. Generated coordinates and manifests remain local asset-derived data.

Developer diagnostics (server console; controlled setup, not campaign acceptance):

```
dk3_runtime_resident prepare e1m1b
dk3_runtime_resident trace e1m1b "-600 -1392 524" "-600 -1392 12"
dk3_runtime_resident clear
```

Sequence 298 adds:

- Both renderers own separate geometry, visibility, fog, lightmaps/deluxemaps,
  lightstyle blocks, sun/cubemap state and inline model registries. Material and
  lightmap identities include their owning renderer context. Switching flushes
  queued scenes before changing backend world tables. Surface admission advances
  across frames; each batch checks elapsed work between surfaces. Individual
  texture work and other admission phases can still stall: the measured largest
  steps are 91 ms (OpenGL1) and 101 ms (OpenGL2), **not** frame-time acceptance.
- Server maps own stable spatial trees, entity projections and configuration
  tables. Preparing map resources does not publish them to the active connection.
  Native map-owned state now resides in `server/world_context.zig`; existing
  class-owned spawning creates each destination without stepping its encounters.
- AAS maps own geometry, linked entities, routing/alternative-route caches,
  temporary reachability data and mover model types. Selection follows server
  collision selection; releasing a prepared map preserves the active navigation
  world. Geometry uses releasable botlib allocations instead of initial-load-only
  hunk allocations. Physics tuning and bot library services remain shared.
- Supplied geometry around A↔B and both B↔C corridors supports identity transforms
  (424, 305 and 123 coincident nearby vertices). This is geometric evidence, not
  portal clipping/traversal acceptance. C→e1m2a uses an authored intermission;
  the inventory now classifies the flag with its named-landing exception rather
  than relying on map names: 32 cuts and 92 unreviewed connections.

Additional controlled diagnostics:

```
dk3_runtime_resident prepare-game e1m1b
dk3_runtime_resident inspect e1m1b "-600 -1392 524"
dk3_runtime_render_world prepare e1m1b
dk3_runtime_render_world preview e1m1b "-600 -1392 546" "0 0 0"
dk3_runtime_render_world close
```

Sequence 299 adds acknowledged, bounded reliable admission of actual map-owned
configstrings. Digest/order/completion validation and exact BSP checksums precede
client readiness; inline models, class-registered models/sounds and sky are admitted
before transfer. Renderer and prediction selections remain scoped to their owner.

Resident transfer copies every player component and preserves its birth ID, position,
command state, weapon action and inventory. Map-local ID allocation cannot consume
another namespace. Server spatial ownership, configstrings, renderer and prediction
switch without disconnecting or initializing a new game. Protocol 1348 carries the
active world identity and rejects cross-world snapshot delta bases. The independent
Zig codec and compatibility manifest use the same protocol; no service was deployed.

`dk3_runtime_enter_world e1m1b` and `dk3_runtime_enter_world initial` exercise this
handoff after client admission, through host-console native single-player diagnostic mode. These are
controlled diagnostics, not an automatic authored seam implementation. Player
transfer does not yet qualify cross-map attacks or entity-local effects.

Sequence 300 adds schema-2 region saves. One atomic file includes the active world,
resident worlds, local ID allocation ranges, asset checksums, activation state,
resource identities and pending actions. Decoding validates unique identities and
references across explicit world/entity pairs. A hidden prepared context owns its
admitted saved state; control resumes only after all required client resources are
ready. Saved region loading currently restarts the connection, which is permitted
for load/death but does not establish uninterrupted travel. Actor state in both A
and B survives actual save/load and death/reload in both renderers.

Schema-1 single-world saves and flat visited archives remain readable; an actual
sequence-296 save was loaded and resaved. Converting old visited archives into
simultaneous resident namespaces remains open. Resident allocation namespaces and
frozen preparation clocks survive schema-2 restoration. The client now excludes
inactive connection snapshots before applying world identity or gameplay events;
the death/restore regression fails before this correction and passes afterward.

Sequence 301 connects automatic preparation to ordinary campaign exits. A local
asset-derived manifest retains every authored exit and distinct reciprocal path.
The reviewed opening seams are pinned to both BSP hashes; changed geometry loses
that qualification. Other connections retain their existing authored landing
contract. Cinematic controls invoking an exit establish a cut even without exit
flags: the inventory now contains 33 cuts and 91 unreviewed connections.

Initial control waits for its connected region's actual client readiness. Outgoing
regions prepare during play. Cut readiness waits retain the connection, and
existing companion checks, cinematic/ending rules and traveler policies precede
ownership commit. Opening corridor handoffs preserve pose, inventory, command
history and carried weapon actions. The class projection dispatcher is shared with
restoration. A→B→A automatic trigger touches are verified with controlled approach
placement; that does not qualify a fresh campaign route.

Restoring more than four member maps queues client admissions at the renderer's
reader limit. Renderer and navigation CPU allocations have independent tracked
heap lifetimes; server spatial owners also use releasable heap storage. This fixes
observed exhaustion of the old 48 MB single-map zone during region preparation.
The failed runs and repaired-build verification are recorded in native acceptance.

Renderer allocations are retained until region/renderer shutdown; fine-grained GPU
eviction is not implemented.

Sequence 302 assigns inline brush models to their renderer owner with checked
generation/owner/model handles. They no longer consume the shared 1,024-model
cache. This repairs the observed assertion while preloading beyond six maps.
Authored sound separator normalization resolves an existing doubled-slash path
without substituting another asset; restoration preserves old resource indices.

Flat visited native archives now migrate when their map is requested. The cold
archive remains untouched until admission. Explicit typed mapping qualifies entity
IDs, nested controller references and delayed actions, removes the stale traveler
copy and binds its references to the current hero. Snapshots retain unrequested
archives and serialize admitted maps once as schema-2 residents. This does not
preload every old visited map. Saves without historical asset checksums still
undergo class/resource admission; a checksum that exists must match.

The native client receives the reliable-command boundary of each new gamestate.
Obsolete resident commands cannot reactivate resources destroyed by a load, while
ordinary reliable commands retain the bundled engine’s existing handling. Current
evidence and remaining cross-world controller/residency work are in native acceptance.

## Remaining implementation, in dependency order

1. Resolve actual seam geometry and portal transforms from the connection inventory
   and rendered/collision observations. Classify complete regions and authored cuts.
   For example, e1m1a's exit names `from_a`, which is absent in e1m1b; existing spawn
   fallback is not sufficient evidence for portal placement.
2. Finish portal clipping, client map-owned presentation state and navigation
   portal links on the resident renderer/navigation contexts. Remove remaining
   admission stalls; staged surface work still contains synchronous texture and
   map work. Asynchronous file reads do not establish an asynchronous loader.
3. Complete native client map ownership and connect server context activation. Add qualified
   snapshot/resource identities, version the changed wire protocol, and implement
   movement/prediction, actor transfer and cross-portal combat with ordinary inputs.
   Replace `map`/module shutdown/hunk clearing for intra-region crossings only when
   all participating owners exist and readiness is proven.
4. Extend the admitted region persistence through live cross-map controllers,
   broader legacy archive fixtures and cancellation/failure scenarios. Preserve original
   saves. The current controlled two-map restore is not acceptance of every map,
   pending action or cross-map combat restoration.
5. Finish region residency/eviction, deterministic cut presentation and failure
   reporting around the connected New Game/restore/exit admission. Preserve
   multiplayer match semantics and map rotation rather than connecting arenas.

## Acceptance

Keep implemented, contract-tested, running-engine and connected-gameplay evidence
distinct in `native-acceptance.md`. Test both renderers with HD textures, actual
input processing and frame traces, reverse traversal, active combat, companions,
locked exits and region save/death/reload. A crossing fails if it synchronously
loads its destination, resets its connection, loses input or shows a loading screen.

Replay the fresh opening milestone with ordinary inventory and normal difficulty,
then all connected regions and authored cuts. Run relevant multiplayer regressions
and the aggregate suite at coherent checkpoints. Preserve main, the installed
playable game, user saves and the live service. `zig build play` remains available;
this work does not reduce the remaining complete-port requirements.
