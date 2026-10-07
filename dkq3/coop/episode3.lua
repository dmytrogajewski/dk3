-- SPDX-License-Identifier: GPL-2.0-or-later
-- Episode 3 of the co-op bot's campaign route (see docs/coop-bot.md). Maps
-- without an authored route head for the forward exit (see advance()).
local chain = {
  "e3m1a", "e3m2a", "e3m3a", "e3m3b", "e3m3c", "e3m4a", "e3m4b", "e3m5a", "e3m6a",
  "e4m1a",
}
for index = 1, #chain - 1 do
  local map, destination = chain[index], chain[index + 1]
  level(map, function() progress(destination) end)
end
-- The side wings of e3m1a lead back to it.
level("e3m1b", function() progress("e3m1a") end)
level("e3m1c", function() progress("e3m1b") end)

level("timestream34", function()
  cinematic()
end)
