# dk3 protocol and native state

The standalone wire protocol is **1344**. Engine, server, game and client modules must
be built together. Upstream foundation modules remain separate development targets;
dk3 modules advertise game version `dk3-1`. Native gameplay state contains no Gold
edict mirror, import/export table or function registry.

The engine's standard model indices, entity frame, origins, trajectories, events and
collision fields retain their meanings. A game entity owns additional campaign data
inside `gentity_t.dk`. Its integer ID is map-local, allocated in spawn order, independent
of a recycled engine entity slot. IDs, rather than memory addresses, identify delayed
target owners and activators. Player IDs occupy 1 through MAX_CLIENTS.

Player state adds explicit delta-coded campaign fields: `dk3Inventory` (weapon bitset),
`dk3Experience`, `dk3Level`, five `dk3Attributes`, `dk3SwordExperience`, `dk3Keys` and
`dk3Status`. Inventory, experience and flag fields use 32 bits; level and attributes
use 8. The existing ammunition array retains its ammunition meaning and grows to
32 entries, with a 32-bit delta mask. Server and prediction share movement code.

These interfaces remain in development. Running native clients have joined a
separate server, received snapshots and scores, respawned and reconnected. A
controlled challenge with protocol 68 produces the matching-build error in the UI.
Campaign saves have restored actor and script state; corruption and interrupted-write
recovery have been exercised. The complete network and persistence matrix remains
open in the roadmap.

The weapon state also carries save gems, attribute points, artifact expiry times,
held attack state, burst count and charge. `ET_DK3_MISSILE` and `ET_DK3_ITEM` distinguish
native dk3 presentation from the upstream weapon/item enumerations. Combat beam/blast
notifications have explicit dk3 event identifiers.

Cinematic camera state has its own active flag, origin, angles, field of view and RGBA
blend. The server uses that origin for snapshot visibility while retaining the player's
physical location. The game freezes player movement and damage during playback; cgame
renders the supplied camera track. Camera transforms are not hidden in unrelated fields.

Game imports 700 and 701 implement save storage service **version 1**. Write accepts a
slot, a bounded buffer and length; read additionally selects current or previous. Slots
contain lowercase letters, digits, underscores and hyphens. Data lives beneath the
engine's private home-state game directory. Writes sync the pending file, preserve the
old inode as the previous save, atomically replace the current path and sync the directory.
A game module supplies and validates the versioned records; the engine does not know game
rules. The Linux x86-64 target implements the filesystem durability operations directly.

Protocol 1342 uses 9-bit model indices, 10-bit looping sound indices and 16-bit event
parameters. Models and sounds have separate limits of 512 and 1,024; configstrings have
4,096 slots and 128 KiB of text. Gamestate messages carry no entity baselines. Both sides
initialize them to zero, and new entities are encoded against zero in the first snapshot.
The reassembled message limit is 256 KiB. Fragment offsets use 32 bits; fragment lengths
remain bounded by the existing datagram fragment size. Earlier development builds
and stock Quake III peers must reconnect with matching binaries.

Team objectives use explicit player fields `dk3Objective` (0, red object, blue object)
and `dk3ObjectiveUntil` (simulation deadline). Entity `dk3Team` identifies objective
presentation. `GT_DK3_DEATHTAG` is gametype 8. CTF remains gametype 4; deathmatch is 0.
Both ordinary and external player event parameters carry 16-bit values.

Entity fields `dk3Scale` and `dk3Alpha` preserve decoration scale and transparency
without repurposing unrelated Quake III fields. Protocol 1342 includes both as floats.

Player state carries five temporary attribute deadlines (`dk3BoostUntil`) and the current
campaign episode (`dk3Episode`). Sprite orientation and additive blending use the two
low bits of `dk3RenderFlags`.

`ET_DK3_EFFECT` uses explicit effect kind/flags, simulation start/duration, emission rate,
velocity magnitude, spread, radius, color, volume bounds, endpoint and acceleration.
Game code owns activation, damage, earthquake impulses and target resolution; client code
owns bounded visual particles and interpolation. Effect definitions are saved as typed
entity fields. Protocol 1342 is a development interface; matching builds are required.

Protocol 1342 carries 11-bit entity numbers (2,048 slots), with matching engine and
client snapshot capacities. Supplied map data includes more than 1,000 entity records;
transient gameplay objects need capacity beyond those records. This is separate from
the removal of gamestate baselines. A mismatching standalone challenge fails with an
instruction to install matching dk3 builds.

`dk3Quest` is a 16-bit player quest record; bit zero means the bottle bomb has been
assembled from its four ingredients. `dk3Carrier` names a carried objective's player
slot plus one. Zero means uncarried. Cgame attaches it to the supplied character tag.

Entity audio has explicit `dk3SoundVolume`, `dk3SoundMin`, `dk3SoundMax` and
`dk3SoundFlags` fields. Cgame import 700 is `CG_DK3_SOUND_PARAMS_V1`: entity number,
volume, full-volume distance, silent distance and flags. Maximum zero selects upstream
attenuation; flag one removes directional panning while preserving attenuation. Both
software and OpenAL mixers implement the authored gain curve. This import is in the
cgame namespace and is separate from game-module save imports.

The AAS mover contents field uses nine bits at shift 22 in both the bundled compiler
and bot library; navigation packages must be generated with this dk3 BSPC. Protocol
1342 adds explicit player sound-environment style (0–4), wet response and effect gain
(0–1). Cgame import 701 applies these through sound-environment interface v1. Full
saves preserve the values; map entry initializes a dry environment at full effect gain.

Snapshot history uses a shared ring sized for 32 full single-player worlds or 128
entities per client per history packet, whichever is larger. Large multiplayer views
may expire old deltas earlier; the existing sender then emits a complete snapshot.
This changes history retention, not the 2,048-entity snapshot limit. The standalone
engine defaults to a 512 MiB hunk. Both renderers reserve 4,096 polygon slots and
16,384 vertices for weather and beam quads alongside other scene geometry.

Death events reserve cause values 129–156 for the native weapon IDs added to base
128. Direct hits, splash and damaging status effects retain their weapon identity
in server logs and client death messages. Existing environmental causes keep their
ioquake3 values. This uses the existing event parameter without a wire layout change.

Game imports 700/701 (save write/read) and 702 (local world hold) take an explicit
version argument, currently 1, in both native and QVM call signatures. World hold
requires exactly one loopback client. It stops simulation and user-command movement
while still delivering the restored snapshot and reliable commands. Cgame acknowledges
`dk3_restore_ready` when processing that snapshot; the game releases the hold. The
engine discards loading-time catch-up, so restored deadlines remain unchanged until
the client is ready. Map teardown clears the hold. This is a loading service; game
rules and save validation remain in the module.

Powerup slot 15 (`PW_DK3_GASHANDS`) carries the campaign Gas Hands expiry in
simulation milliseconds. It uses the existing 16-entry powerup array; wire sizes
and prior slots are unchanged. Zero denotes the untimed multiplayer weapon.
Movement prediction and the server remove expired Gas Hands through the same
weapon-state function. The server pauses its remaining lifetime during cameras.

Protocol 1343 adds `dk3ModelScale[3]` and the actor animation start, first frame,
last frame, rate and loop fields. The game publishes these from authored scale
and saved logical animation state after each simulation frame. Clients evaluate
animation time continuously, without interpolating between unrelated sequences.
Actor position and facing use the native interpolated trajectories. Client and
server must both use the new protocol; existing asset packages remain usable.
These derived actor presentation fields require no new save records.

Configstring 28 carries the authored loading-screen name. Slot 27 remains the
upstream item-presence list; companion presentation uses slot 26. UI and cgame
share the supplied loading tiles and progress artwork. Resource registration
uses the existing cgame sound-update import so loading ticks reach the mixer.

`DK_FX_SPOTLIGHT` carries a collision-clipped cone endpoint, radius and color.
An ordinary cambot actor may publish that effect alongside its model; save
validation permits that explicit combination. Its flare follows the supplied
`hr_light` model tag. Other model entities cannot masquerade as world effects.

Cloud shader stages share one sky mesh in both renderers. The earlier upstream
loop appended unreferenced copies for every additional stage and could overflow
the vertex array when a three-stage sky covered several cube faces. Each stage
still applies its own texture transform and color/alpha waveform.

Protocol 1344 adds `EV_DK3_IMPACT`: weapon identifies the attack, `origin2` is the
contact normal, `otherEntityNum` is the contacted entity, and event parameter 0/1/2
means surface/damageable body/liquid. `dk3RenderFlags` bit 8 reverses the explicit
finite model animation range. Effect flags bits 8–10 identify CP1–CP4 atlas particles
(0 selects the existing simple/smoke/bubble flags). Matching modules are required.
