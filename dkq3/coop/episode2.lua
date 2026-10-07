-- SPDX-License-Identifier: GPL-2.0-or-later
-- Episode 2 of the co-op bot's campaign route (see docs/coop-bot.md). Maps
-- without an authored route head for the forward exit, operating reachable
-- controls when the area graph has no way there (see advance()).
-- The hub (e2m4a-e) and the timestream after it are revisited; each visit
-- goes on toward the next map of the authored order.
local chain = {
  "e2m1a", "e2m1b", "e2m1c", "e2m2a", "e2m2b", "e2m2c", "e2m3a", "e2m3b", "e2m3c",
  "e2m4a", "e2m4b", "e2m4c", "e2m4d", "e2m4e", "e2m5a", "e2m5b", "e2m5c", "e2m5d",
  "e2m5e", "e3m1a",
}
for index = 1, #chain - 1 do
  local map, destination = chain[index], chain[index + 1]
  level(map, function() progress(destination) end)
end

level("timestream23", function()
  cinematic()
end)
