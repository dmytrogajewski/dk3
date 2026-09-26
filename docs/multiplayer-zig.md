# Native Zig multiplayer and Internet rooms

The owner accepted this scope on 2026-09-25. It overrides the general C guidance
for multiplayer, networking, and connected refactors, as the weapons migration did.
Implementation starts at sequence 203. The full scope is **unverified**.

## Accepted architecture

Concrete Zig 0.16 types own state and behavior. Use composition, tagged unions,
explicit allocators, error unions and compile-time contracts. Runtime interfaces
serve actual interchangeable dependencies; C adapters expose engine services.
Remove superseded C behavior from the active build as each connected subsystem moves.

Migrate modes, bots, sessions, admission, teams, spawning, scores, objectives,
match lifecycle, voting, client browser/lobby behavior and presentation. Migrate
engine socket/connection handling, channels, commands, snapshots, codecs,
prediction integration and replay files. Preserve authoritative combat timing.
Use protocol 1346 with explicit bounded schemas; reject old clients/demos clearly.
Preserve campaign saves and stable gameplay IDs, never native-memory serialization.

## Product

DM, CTF and deathtag; public/private player-created dedicated rooms; search and
filters, ping, favorites, lobby chat/readiness, teams, spectators, join-in-progress,
map rotation, moderation and reconnect. No accounts, social graph, voice, ranked
matchmaking, co-op, peer hosting/relays, or live match migration in this scope.

One persistent Zig coordinator with SQLite manages several approved Linux worker
hosts/regions. Each worker runs isolated, unprivileged game processes with resource
limits and read-only locally supplied assets. Allocation is transactional and
idempotent, with capacity reservations and generation-based reconciliation.
Coordinator outage pauses admissions/creation while established matches continue.
Worker failure ends the affected match; do not duplicate an uncertain allocation.

Persistent local Ed25519 guest keys authenticate single-use challenges over HTTPS.
Admission supplies single-use tickets and fresh directional gameplay keys to client
and worker over authenticated HTTPS. ChaCha20-Poly1305 protects public UDP packets;
unique counters, replay windows and fresh reconnect keys are required. Public
workers never downgrade to offline/LAN admission. Caddy terminates HTTPS.

Compatibility checks protocol/schema/rules and canonical gameplay manifests;
approved stock/HD cosmetics may differ. Native code loads only from trusted local
installations. Client hashes are compatibility claims, not anti-cheat attestation.
Validate authoritative inputs/actions, restrict hidden-state exposure and retain
bounded moderation evidence. Enforce identity/address/capacity quotas. Guest keys
can be replaced, so permanent exclusion is not guaranteed.

## Defaults and repairs

- One owned room per guest; other host quotas are explicit configuration.
- Reconnect grace: 60 seconds. Empty human room expiry: five minutes. Ownership
  transfers to the longest-present human after grace. Objectives drop immediately.
- Configured server-owned permanent rooms are exempt from empty expiry and human
  ownership transfer. Default population is 16, with bots replacing absent humans
  and humans displacing bots; default map rotation is ten minutes. Sequence 209
  implements this entirely in hosting services and the dedicated engine, preserving
  the existing client package. See [configuration](online-operations.md#permanent-rooms).
- Votes: one active, 30 seconds, 120-second caller cooldown, frozen human electorate
  excluding spectators and kick target; strict majority and at least two yes votes.
  Bind target identity, not reusable slot. Kick bans that identity for 15 minutes
  in the room. Operators have authenticated audited moderation; no owner immunity.
- One validated character/skin catalog serves humans, bots and rendering. Rotate
  bots across available combinations; preserve appearance through respawn/reconnect.
- Separate pickup and equipped weapon models. Gold omits the ordinary Disruptor
  attachment; remove the pickup-model attachment. Review related melee and sword
  presentation, attachment transforms and authored equipped frames.
- Give music transitions one owner. Preserve authored assignments/overrides;
  diagnose repeated playback and resolve missing tracks through an ordered episode
  fallback catalog, logging once. Silence if no fallback exists. Preserve saves.

## Implementation and acceptance

Implement connected gameplay/network/services/UI code before systematic scenarios.
Then verify all multiplayer maps and modes, appearances, both renderers, captured
music transitions, malformed/lost/reordered packets, reconnect and demo playback,
admission/content failures, vote abuse, quota exhaustion, worker/coordinator recovery,
backup/restore and two-host public Internet creation/search/join. Exercise campaign
movement/combat/save/media paths affected by shared changes. Run the broad suite
once after repairs; no duplicate per-item gates. Engine runs use dkguard and isolated
homes/saves. Record implemented versus verified separately in the existing run log.

Delivery includes build targets, protocol/API documentation, systemd units, HTTPS
configuration, worker enrollment/revocation, draining, metrics, health and backup.
Real Internet acceptance remains unverified until exercised on configured public hosts.

### Sequence 203 hosting decision

The owner supplied one Linux machine for both roles and selected its IP with an
explicitly trusted test certificate. Caddy, the coordinator and an enrolled worker now run there. CA-trusted HTTPS,
rejection without that CA, public room allocation and encrypted gameplay with
three human clients passed focused probes. Full Internet acceptance remains open. See [operations](online-operations.md).
