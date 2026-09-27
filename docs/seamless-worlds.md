# Seamless connected worlds

Sequence 297 begins the approved implementation on `rewrite/native-zig-runtime`.
**The feature is incomplete. Ordinary exits still perform their existing map load.**
Preparing collision geometry is not acceptance of a seamless crossing.

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

## Remaining implementation, in dependency order

1. Resolve actual seam geometry and portal transforms from the connection inventory
   and rendered/collision observations. Classify complete regions and authored cuts.
   For example, e1m1a's exit names `from_a`, which is absent in e1m1b; existing spawn
   fallback is not sufficient evidence for portal placement.
2. Add resident renderer contexts to both renderers: scoped inline models,
   lightmaps, fog, skies, visibility and portal clipping; shared image/model/sound
   assets; owner-thread incremental GPU admission. Give navigation its own world
   contexts and portal links. Remove remaining admission stalls rather than calling
   asynchronous file reads a completed asynchronous loader.
3. Move native server/client single-world ownership into map contexts. Add qualified
   snapshot/resource identities, version the changed wire protocol, and implement
   movement/prediction, actor transfer and cross-portal combat with ordinary inputs.
   Replace `map`/module shutdown/hunk clearing for intra-region crossings only when
   all participating owners exist and readiness is proven.
4. Capture resident-region state atomically, including transferred identities,
   pending actions and activation state. Add save-schema migration without changing
   original saves, full death/reload restoration and safe cancellation during loads.
5. Connect New Game/restore admission, region residency and transition preparation;
   integrate deterministic cut holds and failure reporting. Preserve multiplayer
   match semantics and map rotation rather than connecting separate arenas.

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
