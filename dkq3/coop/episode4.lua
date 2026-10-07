-- SPDX-License-Identifier: GPL-2.0-or-later
-- Episode 4 of the co-op bot's campaign route (see docs/coop-bot.md). Maps
-- without an authored route head for the forward exit (see advance()); the
-- run ends at the credits.
local chain = {
  "e4m1a", "e4m1b", "e4m2a", "e4m3a", "e4m3b", "e4m3c", "e4m4a", "e4m4c", "e4m5a",
  "e4m6a", "e4m6c", "credits",
}
for index = 1, #chain - 1 do
  local map, destination = chain[index], chain[index + 1]
  level(map, function() progress(destination) end)
end
level("e4m1c", function() progress("e4m1b") end)
level("e4m2b", function() progress("e4m2a") end)
level("e4m4b", function() progress("e4m4a") end)
level("e4m6b", function() progress("e4m6a") end)

level("credits", function()
  cinematic()
  finish()
end)
