# Seamless connected worlds

Sequences 297–307 implement connected owners on `rewrite/native-zig-runtime`.
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

Sequence 303 adds qualified sweeps through the six reviewed opening brushes.
Collision results retain the actual world handle and local contact slot; a nearer
wall wins. Generic hitscan/melee, Ion and ordinary projectile/explosion paths use
those results, while controllers retain their class-owned damage and interactions.
Moving projectiles relocate with their birth ID and map-local resource projection.
Exposed connected worlds continue simulating; preparation alone does not start them.
Specialized weapon and actor/companion behavior across seams remains incomplete.

Both renderers use the measured rectangular brush faces for resident portal views.
Scene entities and polygons retain renderer ownership, preventing source brush
surface indices from being evaluated in the destination map. The current engine
path still supports one portal view per scene and excludes recursion; multiple
simultaneously visible apertures remain open. One opening view and foreign target
are verified in both renderers; this is not complete regional presentation.

Protocol 1349 carries entity resource owner and persistent identity. Neighboring
presentation borrows transport slots without creating duplicate gameplay actors or
solids. Visibility sampling uses the supplied aperture and actual collision/PVS;
resource lookup, interpolation, particles/decals and prediction retain their owner.
Late configstring updates are digest-checked, chunked and bounded by actual client
acknowledgements; snapshots defer foreign resource references until their complete
update is queued before that snapshot. Ordinary arena boundaries remain unchanged.

Cut/landing party selection preserves authored companion masks and arrival models,
then rebinds the arrived incarnation to its continuing birth ID and retires the
source copy. These paths and natural companion seam pursuit need running coverage.
Restore diagnostics can report actual actor identities/health at the installation
boundary, before ordinary corpse retirement or encounter simulation resumes.

Sequence 304 connects actor perception, class-owned attacks and radius recipients
through explicit world/entity references. Ground, flight and swimming queries
retain ownership across accepted movement while rejected slide/step probes do not
commit transfers. A saved per-actor step clock prevents a crossing from simulating
the actor twice in one region frame. Body-attached actions move with their owner;
free missiles retain the owner reached by their accepted sweeps.

Moved actors retain their authored map separately from physical ownership. Named
outputs, script programs and delayed references use that scope; restored script
cursors are admitted against their actual program. Continuing party lookup/capture
and ordinary use/order targets resolve actual owners without borrowing local slot
numbers. Class damage, attack timings, door/key rules and party distance rules are
unchanged. Cross-seam pursuit intentionally extends the reference's map boundary.

Controlled native evidence now includes real Rockgat/Froginator contact across
A/B, Slaughterskeet pursuit and Superfly following into A, and save/load of both
crossed actors. The aggregate and affected player/render/save/LAN scenarios replay
on build `0262fb…`; see native acceptance for exact identities and limitations.
This does not qualify every actor/controller, party script or campaign route.

Sequence 305 extends specialized player controllers: Trident groups, Wyndrax
targets, Zeus branches, Nightmare victims, Metamaser locks/destruction, Ballista
transport, Discus return/pickup, C4, Sunflare, Stavros, Shockwave and Hammer.
Accepted motion determines physical ownership; class-owned damage, timing,
visibility/liquid masks and acquisition rules remain authoritative. NPC muzzle
offsets also resolve their actual world without changing the authored offset.
Lightning-hop attachment is distinct from attack ownership, and disconnect
cleanup resolves personal controllers across ready maps. Controller presentation
references are mapped only after foreign transport slots have been assigned.

On `187506…`, eleven controlled weapon scenarios establish actual contact;
selected active controllers restore, and affected renderer/actor/save checks
replay. These are scoped diagnostics, not full interaction or campaign acceptance;
see `native-acceptance.md`. The current manifest has 124 exits: six qualified
identity seams, 33 authored cuts and 85 unreviewed landings. The raw inventory's
91 geometry-unreviewed rows include the six subsequently qualified seams.

Sequence 306 splits renderer lightmap admission across polls, preserving each
world's registry, uploaded tile index and GL2 merged/deluxe page progress. Both
actual renderer contracts interleave owners and check uploaded pixels; GL1's
single-lightmap workaround no longer reads a nonexistent second image. RGB input
provides an explicit alpha byte. Independent admission-phase timing identifies
surface/texture preparation as a remaining source of long stalls. Final build
`964389…` replays both renderer portals/foreign contact, six-world restoration,
region save/death, ordinary controlled crossings and LAN lifecycle. Lightmap
phases measure 2–4 ms, while surface steps still exceed 100 ms. This is not a
complete asynchronous loader or fresh campaign acceptance.

Sequence 307 replaces the PNG decoder's two inflation passes with the engine's
bundled zlib and an exact scanline bound, retaining existing filter/pixel conversion.
Both HD renderer/contact scenarios pass; measured surface peaks fall to 26/33 ms.
Individual image decode/upload still occurs synchronously and remains a loading
stall. Read-only spray forecasting improves diagnostics but its boss replay fails;
no fresh campaign gate is accepted. Exact build/evidence are in native acceptance.

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
