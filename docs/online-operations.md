# Internet room operations

Sequence 203 remains in implementation. One provisioned Linux host runs Caddy, the
coordinator and an enrolled worker as separate services. Explicit-CA IP HTTPS,
public room creation/search, encrypted Internet joins, three human clients,
readiness restart, incompatible-rules rejection, reconnect, vote/room bans, operator
removal, coordinator outage continuity, worker restart and isolated backup/restore
have passed focused probes. The lifecycle replay also passed with the Zig message
codec, followed by an encrypted UDP loss/reordering/duplication/tampering probe.
Later shared networking migrations need their own replay. The full multiplayer migration and acceptance remain open;
see the [run log](../specs/runs/RUN-dk3-independent-port.md#multiplayer-zig-203--connected-implementation-and-ip-hosting).
Two-worker acceptance needs another supplied host.

## Build and services

`zig build online` builds `dk3-coordinator`, `dk3-worker`, `dk3-online` and `dk3-operator` using the
host SQLite SDK (`pkg-config sqlite3`). The operator tools target the host OS/libc
with a baseline CPU; the game build retains its separate target. On Linux install
SQLite development headers before building and the SQLite shared library at runtime.

The templates in [deploy/online](../deploy/online/) use `/opt/dk3/bin`, private state
under `/var/lib/dk3-coordinator` and `/var/lib/dk3-worker`, and configuration under
`/etc/dk3`. Separate unprivileged service accounts own each state directory. Only
root deploys binaries and approved private assets under `/opt/dk3/share/dk3`.
The worker runs each dedicated process through dkguard, with its own room home.
The supplied one-host unit caps the worker process group at 2560 MiB; adjust that
along with worker capacity and per-room dkguard memory when enrolling larger hosts.

The coordinator JSON accepts `database`, `admin_token`, `public_url`, loopback
`bind` (default `127.0.0.1:8090`), `max_rooms`, `rooms_per_address` and optional
`permanent_rooms` (described below). Generate
independent random operator and worker bearer secrets; keep configuration readable
only by root and its service account. Enroll workers through authenticated
`POST /v1/operator/enroll`, supplying the worker's address/port range, capacity,
region, approved maps/cosmetics and compatibility manifest. Re-enrollment of an existing ID requires a drained worker with every allocation
confirmed terminal. `drain` stops new allocations; `revoke` also disables its token.
Revocation alone cannot stop a disconnected worker: stop or fence its process group
before replacing the host. The authority retains uncertain capacity reservations.

## IP test certificates

Set `DK3_COORDINATOR_IP` in `/etc/dk3/proxy.env` and install the supplied Caddyfile
and proxy service. The proxy uses `tls internal`; Caddy issues and renews a certificate
for that IP. `skip_install_trust` keeps trust explicit. This follows Caddy's
[internal HTTPS model](https://caddyserver.com/docs/automatic-https).

Retrieve **only** the public root certificate through the authenticated SSH channel
from `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`. Preserve
Caddy's private state across restarts so it retains the same CA. Point the worker
and client `ca_file` at a local copy of this PEM certificate. No TLS verification
bypass is provided. A test CA is not a public trust certificate; each participating
client must explicitly configure it.

For the provisioned test host, local operator configuration and the public CA copy
live outside the checkout in `~/.local/state/dk3-online-203/`. The certificate probe
is recorded in `zig-out/reports/multiplayer-zig-203/tls.json`. It verified a successful
HTTPS `/healthz` request with the configured CA and certificate rejection using
default system trust. No credentials or private CA key belong in Git.

The proxy overwrites `X-Real-IP` with its peer address; the backend only listens on
loopback. Expose HTTPS and the enrolled UDP range, while keeping backend port 8090
and the Caddy administration endpoint private. The proxy never serves game assets.

## Guest client

For the provisioned local setup, `dk3` now opens the online development installation
under `zig-out/online/play/`. Its separate profile already selects the IP coordinator
and explicitly trusted test CA. Restart an already running game to use this build.
Choose **Multiplayer → Internet rooms** to select a room and join, or
**Multiplayer → Create Internet room → Create room and join** to host one.
An empty browser means no public rooms are currently available. The hosting worker
has capacity for two simultaneous rooms: one configured permanent room and one
player-created room. The current permanent room is **dk3 Always DM**.

Hold **Tab** during play to show scores; release it to return to the HUD. Score and
ping columns refresh while visible. The Keyboard menu exposes **Show scores (hold)**
for rebinding. Profiles from before this binding existed receive it once if Tab is
unused; existing custom bindings are retained. Death and intermission still show
the scoreboard automatically.

`dk3-preserved` opens the previous installation and its original profile/saves.
The online profile is separate; this setup does not migrate or overwrite campaign
saves. Sequence 205 verified creation, discovery and joining through actual menu
input on the provisioned Internet host; the full visual/UI matrix remains open.

The `dk3-online` client config contains `coordinator`, optional `ca_file`, a private
`identity_file`, and `compatibility`. Commands list public rooms, create a room from
JSON with an idempotency request ID, or join a room and write a private ticket file.
The persistent Ed25519 seed is created with mode 0600. Joining prints the endpoint;
packet keys remain in the ticket file. The native connection path loads that file
with `dk3_ticket` before connecting. The integrated browser uses the same guest/HTTPS implementation asynchronously.
Online settings accept the coordinator URL and explicit CA path. Browser rows show
UDP round-trip time; search, mode/region/availability filters and favorites narrow
the list. Room creation includes bot count/skill, privacy and a space-separated
rotation of approved map names. The lobby exposes readiness, chat, team/spectator
selection, reconnect and votes. Full visual/UI acceptance remains open.

The HTTPS client uses the engine's existing libcurl dependency (runtime >= 7.85,
thread-safe global initialization). Zig 0.16's certificate hostname verifier skips
IP-address SANs, so its standard HTTPS client cannot validate this IP certificate.
The adapter loads the system `libcurl.so.4` with the bundled reviewed curl headers;
it keeps both [peer-chain verification](https://curl.se/libcurl/c/CURLOPT_SSL_VERIFYPEER.html)
and [IP/hostname verification](https://curl.se/libcurl/c/CURLOPT_SSL_VERIFYHOST.html)
enabled. Redirects and environment proxies are disabled. Response bodies have a
4 MiB bound, connection establishment a five-second deadline and requests a
15-second deadline. Packet authentication remains in native Zig.

## Permanent rooms

Sequence 209 adds server-owned rooms without a client, game-module, protocol or
RPM update. The coordinator creates them automatically once an eligible worker
reports healthy. Empty rooms keep running; bots fill the configured population.
An authenticated human joining a full bot population replaces one bot. Departure
allows the ordinary bot controller to fill the vacated slot, normally on its next
one-second check. Initial startup fills bots progressively, so 16 bots take roughly
16 seconds. Map loading also has a short population transition.

Merge the `permanent_rooms` member from the
[example configuration](../deploy/online/permanent-rooms.example.json) into
`/etc/dk3/coordinator.json`. Preserve its other fields and private token. Each entry
requires a stable unique `id`, a display `name`, and an ordered nonempty `maps` list.
Every map must support the selected mode in the worker's approved catalog.

| Field | Default | Accepted values |
|---|---|---|
| `region` | `default` | Enrolled worker region |
| `mode` | `dm` | `dm`, `ctf`, `deathtag` |
| `players` | 16 | 2–32 total occupied slots, including connected spectators |
| `skill` | 3 | Bot skill 1–5 |
| `map_minutes` | 10 | 1–1440 minutes per map |
| `enabled` | `true` | Disable without deleting the configuration entry |

The dedicated server rotates at the configured elapsed time, wraps to the first
map, and retains connected humans across the normal map transition. Permanent
rooms start immediately and do not wait for ready votes. Their frag/capture limits
are disabled; the server controls the rotation deadline. The provisioned room uses
`e1dm1 → e2dm1 → e3dm1 → e4dm1`, 16 slots, skill 3 and ten minutes per map.

Configuration is read at coordinator startup. Restart `dk3-coordinator` to apply
edits. Changing, removing or disabling an entry drains its existing allocation,
which disconnects any players there; schedule such edits accordingly. An enabled
room is recreated after confirmed process exit and a 30-second restart backoff.
The stable room ID survives restarts, with a new allocation generation. An operator
`end` also allows recreation; disable the entry to stop it permanently. A missing
or unreachable worker retains its reservation until its process is confirmed
stopped. Capacity exhaustion leaves the configured room waiting for a suitable
worker; it never starts a duplicate uncertain match.

Upgrade coordinator, worker and dedicated binaries together before enabling this
policy. Old workers still receive their original response schema and cannot host
permanent assignments. Permanent rooms consume normal host capacity. The supplied
host now has worker capacity 2 and a 1 GiB per-room dkguard cap under its existing
2560 MiB service cap. Keep worker configuration and enrollment capacity in sync.

The existing client lists and joins permanent rooms normally. Its room count shows
**human occupancy** (for example `0/16` while 16 bots play), keeping replacement
slots available in the compatibility/availability filter. Use the in-game scoreboard
to see bots. Actual bot/human totals and the current map are also written privately
to each allocation's `dk3/permanent-status.json`; the worker updates the public
room's existing map field after rotation. No new client API fields are required.

## Operator controls and monitoring

Create a mode-0600 operator JSON file with `url`, `admin_token` and, for the test
certificate, `ca_file`. Keep it outside the repository. `dk3-operator CONFIG.json
status` returns worker heartbeat times, draining state, rooms, human counts,
pending admissions and pending controls. `audit` returns bounded operator history.
These authenticated endpoints exclude bearer tokens, room codes and packet keys.
A heartbeat older than 30 seconds makes a worker unavailable for new admissions
and allocations; it does not release its occupied ports. `/healthz` is a public
process/API health check, not a gameplay-readiness check.

Mutation commands take a JSON request file, avoiding secrets in command arguments:

| Command | Request fields | Effect |
|---|---|---|
| `enroll` | `worker`, `token` | Enroll or replace a fully drained worker |
| `drain` | `worker` | Reserve existing allocations; accept no new rooms |
| `revoke` | `worker` | Drain and invalidate the worker credential |
| `end` | `room`, `reason` | Stop an allocation, keeping capacity until exit acknowledgment |
| `kick` | `room`, `identity`, `reason`, optional `ban_seconds` | Identity-bound removal; default 900-second room ban, maximum 86400 |
| `ban` | `identity`, `reason`, `expires` | Block admissions globally; queue removal from current rooms; zero means no expiry |

Controls repeat until the game applies them, persists membership moderation and
writes a receipt. They bind room ID, allocation generation and identity. Operator
reasons never become executable engine commands. Pending delivery expires after
five minutes; inspect the audit and game service journal if the worker is offline.
Audit retention is the latest 2048 records. Terminal room metadata and idempotency
records expire after 24 hours. For player-created rooms, workers retain a bounded
tail of each completed engine log in the service journal before deleting its
private room directory. Permanent rooms stream engine output directly to the
service journal; this avoids growing a lifetime log to the service file-size limit.
Use `journalctl -u dk3-worker` and configure host journal retention as needed.

To upgrade, drain the worker, wait for its rooms to end or explicitly end them,
then confirm every allocation is `ended` or `failed`. Stop the worker, install the
new binaries/modules/compatibility manifest, enroll the new manifest and restart.
Never treat an enrollment conflict as success. A worker restart ends its prior
matches; those allocations are reported failed rather than recreated. The supplied
systemd unit kills the complete worker process group. If a host is unreachable,
fence it before recovering its reserved capacity.

## Backup and restore

Run as the coordinator service account while the service is running:

```sh
/opt/dk3/bin/dk3-coordinator /etc/dk3/coordinator.json backup /var/lib/dk3-coordinator/backup-203.sqlite3
```

The destination must not exist. The command creates a private, consistent SQLite
snapshot using the online backup API, including committed WAL state. The backup
is a single database file; do not copy a live main database without its WAL. Store
backups privately because sessions, private-room codes and pending ticket keys are
sensitive. Verify `PRAGMA integrity_check` and retain configuration and Caddy's CA
state through a private backup channel as well.

Restore into a separate private directory first. Set the test coordinator's database
path and an unused loopback bind port, start it, then verify `/healthz` and authenticated
`status`. Never let a restored authority allocate matches alongside the original:
keep workers attached to one authority, stop the old service for cutover and reconcile
or fence every uncertain worker allocation. Existing matches cannot be restored
from the coordinator database. Preserve Caddy's CA state to retain client trust.
The sequence-203 probe restored a live snapshot into an isolated local coordinator
and checked database integrity, health and retained room identities.
