-- SPDX-License-Identifier: GPL-2.0-or-later
-- New Game campaign route for the scripted co-op bot (see docs/coop-bot.md).
-- Every map body ends at its authored forward exit. Most maps need only that:
-- the bot routes over AAS, fights what it meets, opens doors through their
-- authored controls and rides lifts. Map-specific steps are added where the
-- authored progression requires them.
-- The sewers are long and their sludgeminions hit hard, and the icelab's
-- fights are on narrow walkways over nitrogen: more restorations, each from
-- the latest healthy stage checkpoint.
settings { level_deaths = 12, map_deaths = { e1m2a = 16, e1m3b = 25, e1m4b = 30, e1m6a = 20, e1m6b = 30, e1m6c = 30 } }


level("intro", function()
  cinematic()
end)

level("e1m1a", function()
  pickup { class = "weapon_ionblaster" }
  exit "e1m1b"
end)

include "coop/episode1.lua"
include "coop/episode2.lua"
include "coop/episode3.lua"
include "coop/episode4.lua"
