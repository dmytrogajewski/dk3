# Native multiplayer development

The rules below are implemented. Running scenarios cover bot joins, team admission,
movement, damage, kills, dropped-flag returns and CTF captures. A four-bot CTF
replay on rebuilt navigation records five captures with both teams scoring. Deathtag has two
uncontested captures on each course and a contested replay with three blue and one
red capture. A separate network client joins, moves, respawns, receives scores,
disconnects and reconnects. Teammate yielding and the full network/objective matrix
remain open. Use matching dk3 clients and servers; stock Quake III assets are not required.

Set `g_gametype 0` for deathmatch, `4` for CTF, or `8` for deathtag before loading a
converted map. `e1ctf1` and `e1dt1` are authored objective maps. Use `team red`,
`team blue`, or `team spectator`; use `addbot <name> <skill 1–5> [red|blue]` on the
server. `bot_minplayers` maintains a population; `bot_pause` pauses bot commands.
`fraglimit`, `capturelimit`, and `timelimit` use ioquake3's match lifecycle.

CTF carries the opposing flag to an authored capture brush while the home flag is
at its base. Teammates return a dropped home flag; an abandoned flag returns after
30 seconds. Death and disconnect drop the carried object.

Deathtag uses the authored switch/door course and the team's own backpack. Pickup
starts its 90-second fuse. A matching capture zone awards its authored points and
places the bomb with at most five seconds remaining. An opponent touching a dropped
bomb detonates it. Detonation damages players within 400 units and the backpack
returns after ten seconds. Carrying protects against falling, drowning, lava and slime.

Mode constants and entity meanings were reviewed as behavioral facts against optional
local reference material and supplied map/editor data. No reference implementation is
compiled, translated, generated, linked, or loaded by these native rules. Bots now trace authored target links back to physical controls when a mover blocks their
route, seek reachable switches, and assign carrier escort/home-flag recovery roles. They
never activate a remote relay directly. Both courses have completed; reliable coordination and broader match acceptance remain open.

The Multiplayer menu has host and join flows. Hosting selects a supplied compatible map,
mode, slot count, bot population/skill and friendly fire. Joining accepts a server address
or uses LAN discovery and the engine's favorites cache. The map catalog comes from supplied
map entities; it does not embed proprietary map descriptions in source. Running menu checks join a loopback dedicated server by a typed address and host
Deathtag on e1dt1 with three bots. The catalog distinguishes the authored deathtag
course from CTF maps that use the same objective class names. LAN discovery and
favorites still need running acceptance.

Server game logs record `DK3Objective` pickup/drop/return/explosion events and
`DK3Capture` with client slot, team, awarded points and resulting team score.

A mismatching server protocol returns an explicit version error. Connection errors
are shown in a wrapped menu panel; Enter or Escape dismisses it and Up/Down scrolls
long messages. Native development servers use `sv_pure 0` with matching local modules.
