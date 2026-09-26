# Native save records

Persistence integration is in progress. Running-client evidence covers cinematic/mover
restoration, corruption diagnostics, previous-save recovery, interrupted writes and
representative weapon controllers. Complete campaign, companion and mid-script
persistence acceptance remains open; see [current completion state](status.md).
Original Daikatana saves remain with the preserved installation and are not migrated.

The menu exposes quick save, quick load, the previous quick-save copy and the map-entry
autosave. `dk3_autosave 1` enables entry saves. `dk3_unlimitedSaves 1` is the default;
setting it to 0 consumes one save gem after a successful manual write. Companion state
includes inventories, ammunition, attributes and campaign travel records for companions
currently absent from the map.

Format version 1 is a bounded little-endian record stream. Its 24-byte header contains an
8-byte signature, version, total byte length, record count and CRC32 of the record data.
A record carries its total byte length, a stable numeric identifier, field count and named
kind. Fields have explicit names, types and element counts. Supported values are signed
32-bit integers, IEEE binary32 floats, length-delimited text and opaque bytes.
Byte fields contain nested visited-world records, never executable code. No host structures,
addresses, padding, callback names or function pointers are written.

The reader rejects truncated data, trailing bytes, incompatible versions, mismatched
checksums, invalid names/types/counts, duplicate fields, embedded text NULs and non-finite
floats. Gameplay schemas require every mandatory field and reject unknown fields.
Explicitly optional fields have documented defaults when absent. Validation works
against separate storage before any live object is updated.
Simulation timestamps are encoded relative to the save point; an explicit sentinel means
an inactive timer. Rebased timestamps must fit the simulation's integer range.

Storage service version 1 is documented in [protocol.md](protocol.md). Current and previous
files are private loose files, never loaded from user asset packages. The converted data
package includes its generation identity so the gameplay layer can reject incompatible
asset inputs before replacing a world.

During a local campaign, `save quick` writes a named slot, `load quick` validates and
stages that slot, and `load quick previous` selects its recovery copy. A load requests
the saved map only after structural, schema, asset identity and reference validation.
The newly initialized game restores fields, resources and entity references before play
resumes. The internal resume slot is reserved and cannot be selected by these commands.

Records contain campaign metadata, entities, stable references, player state, resource
bindings, delayed targets, authored event definitions, action program positions, and
cinematic camera/cast/sound state. Immutable script instructions are read from the same
asset generation; they are never accepted as executable instructions inside a save.
Cinematic and action validation use separate metadata storage to avoid mutating live
execution state. Gameplay schema revision 5 is checked independently of codec version 1. It requires a
`player_environment` record containing the remaining air deadline. Drowning damage and
its pain deadline remain in the existing entity record. Underwater restoration must not
refill air or reset escalating damage. Earlier development schemas are not the current gameplay schema; use the preserved
installation for those saves.

Map-transition records use named fields and require each field exactly once. Integer
parsing rejects overflow, missing fields and unknown names. Inventory, quest ingredients,
assembled items, attributes, experience, armor and remaining artifact/boost times carry
within an episode. Entering another episode resets its keys and arsenal while retaining
character and sword progression. Ongoing poison/burn/freeze effects end at a transition;
full saves preserve those effects. Authored death drops and effect emission timers are
part of entity saves. Opening forward/backward exits and restoration of the visited-world archive have running-client evidence; later campaign transitions remain open.

Native integration evidence covers the opening cinematic, delayed ladder and moving lift,
plus corruption and interrupted-write recovery. Full persistence acceptance remains open,
including later campaign and companion state.
Save fields use explicit lowercase identifiers; runtime C member expressions are not
field names. Cinematic model validation resolves the saved chapter before accepting
animation bounds, independently of the currently running map.

A successful local restore holds simulation until cgame has processed the first
restored snapshot and its resource bindings. Loading time does not consume projectile
travel, fuses, cinematic actions or mover deadlines. Resume then continues the saved
situation; a dangerous save can still be lethal after control returns.

Gas Hands uses the existing relative powerup deadlines in player records. Loading
retains its remaining simulation time; transition records include `gas_hands`.
An episode change clears this episode-specific effect. Development saves made
before the lifetime repair that own Gas Hands without a deadline lose the expired
weapon on the next campaign frame; the original save file is preserved.

Delayed binary-door movement uses the native trajectory start time, saved relative
to simulation time. Each linked part keeps its own authored delay. The saved
action deadline defers its start sound. Restore preserves both deadlines without
serializing a callback; blocking reversal and automatic return begin immediately.

Level exits atomically archive the departing world, including dead or removed enemies,
pickups, movers and script state. Returning restores that world and places the incoming
player at the authored entry. Companion travelers replace their archived instances.
Starting a new campaign clears the active archive index.

A manual or automatic save embeds earlier worlds as `visited_level` records. It remains
one portable file; internal `dk3-m0-*` / `dk3-m1-*` files are a working cache, not save dependencies.
Loading validates every embedded world before staging a separate cache bank and switching
the active index. Failed staging preserves the current bank. Worlds are limited to 32 MiB
each; a complete save is limited to 256 MiB and 128 visited worlds. Older development
revisions do not carry all current state fields; use their preserved installation.

Single-player death reloads a separate validated checkpoint, including world state and
visited levels. Entry, successful manual save and successful load establish that checkpoint.
The optional visible autosave setting does not disable death recovery. A missing or corrupt
checkpoint keeps the player dead and gives a load/new-game diagnostic; it never silently
respawns into the altered world. Multiplayer continues to respawn within the match.
Schema revision 5 includes each turret’s lift range and toggle state. Earlier development
saves remain with their previous installation; the new schema requires a new campaign.

## Weapon controller extensions, sequence 200

The weapon review retains the codec and gameplay schema revision. It adds optional
entity fields `dk_weaponholduntil` (relative simulation deadline) and
`dk_weaponparentid` (stable controller ID), both defaulting to zero. Controller links
are validated independently of `dk_parentid`, whose targets must remain movers.
A fixture omitting both optional fields restores successfully; this does not imply
compatibility with all earlier gameplay schema revisions.

Ballista, Wyndrax and Metamaser launch delays are saved entities. Metamaser packs
lock deadlines relative to its saved birth timestamp; slot 31 identifies this
representation. Legacy absolute-time cubes retain their phase, health and charges
and re-acquire target locks on the restored clock.

Focused running scenarios verify attached C4 detonation, Hammer charge, Nightmare
hold/reap/release and both pending and active Metamaser restoration. The active cube
must damage after loading, not merely have a damage record before saving. Full
weapon/controller phase and cross-episode coverage remains open. See
[sequence 200](../specs/runs/RUN-dk3-independent-port.md#weapons-gold-review--sequence-200).

Sequence 215 adds optional entity integer `dk_assemblyversion` (absent means 0).
New trains write 1. Loading an older save repairs child positions only when an
initialized, paused, stationary train still matches the freshly initialized map
and a child exactly matches the old unshifted initial placement. Arbitrary saved
mid-motion or scripted poses are retained. Existing companion spawn markers also
restore their use-only callbacks and nonsolid contents.
