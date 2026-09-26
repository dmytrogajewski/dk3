# Native runtime

`server.zig`, `client.zig` and `ui.zig` are native ioquake3 module entrypoints.
They compose the following layers; this is the game's runtime, not an alternate backend.

| Directory | Owns | Dependencies |
|---|---|---|
| `domain/` | Simulation values, rules, transitions and component schemas | Pure catalogs, math and ECS types; no engine calls |
| `ecs/` | Storage, identity, structural commands, jobs and scheduling | Zig standard library; no gameplay or engine state |
| `engine/` | Public ABI, syscalls, collision/filesystem services and transport projections | Public engine headers and domain values |
| `server/` | Authoritative systems and ordering, applying domain rules to ECS state | Domain, ECS and explicit engine adapters |
| `client/` | Snapshot presentation and local commands | Domain prediction and engine adapters |
| `tests/` | Differential fixtures and runtime contracts | Test-only references; never linked into products |

Weapon class definitions live in `src/weapons`; item metadata in `src/items`.
They own class-specific values and policies. Common systems consume those definitions
without weapon-ID switches or copies of class metadata. Runtime configuration and
local converted asset data provide numeric tuning and authored content.

Component pointers never survive structural mutations. Systems copy intent/state
before spawning entities, resolve persistent IDs at use time, and call ioquake3 only
on its owning thread. Engine structs are projections, not authoritative game state.

See [the runtime plan](../../docs/runtime-zig.md) for full scope and implemented versus verified status.
All development stays on `rewrite/native-zig-runtime`; `main` preserves the working game.
