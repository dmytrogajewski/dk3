-- SPDX-License-Identifier: GPL-2.0-or-later
-- Episode 1: Japan, 2455. Coordinates and entity indices are authored map data
-- (dkq3/tools/coop_route_survey.py); waypoints follow the supplied ground nodes.

-- The Marsh, part 2: river, two turret controls, the bridge ambush and the
-- Thunderskeet whose death opens the north gate to part 3.
level("e1m1b", function(visit, resumed)
  if visit > 1 then return exit "e1m1c" end
  return stages {
    { "river", function()
      path { {-445, -1430, 536}, {-302, -1314, 581}, {-232, -1176, 624} }
      clear { radius = 250, timeout = 20 }   -- close attackers at the firing spot only
      shoot { index = 91 }                 -- first turret's control
    end },
    { "pond", function()
      path { {-232, -968, 648}, {-432, -880, 664}, {-660, -810, 664} }
      try(pickup, { index = 256 })         -- river health
      path { {-624, -648, 664}, {-398, -649, 633}, {-192, -704, 640}, {-112, -624, 640} }
      path { {-192, -704, 640}, {-398, -649, 633}, {-624, -648, 664}, {-720, -580, 664} }
    end },
    { "ford", function()
      path { {-797, -627, 664}, {-944, -616, 637}, {-1158, -624, 572}, {-1328, -688, 520},
             {-1342, -858, 497}, {-1406, -914, 474} }
      kill({ index = 387 }, { hold = true, timeout = 40 })   -- ford Crox, from the bank
      kill({ index = 419 }, { hold = true, timeout = 40 })
      path { {-1510, -914, 424}, {-1640, -904, 408}, {-1768, -888, 411} }
      -- Straight across the last of the ford: the area graph splits it into
      -- slivers whose seams lie a few units apart, and routed swimming
      -- circles between them.
      move({ -1904, -808, 408 }, { direct = true, radius = 24, timeout = 20 })
      path { {-2040, -680, 415}, {-2072, -520, 470}, {-2080, -464, 496} }
    end },
    { "tree", function()
      heal { index = 110 }
      path { {-2253, -612, 489}, {-2341, -419, 526}, {-2272, -328, 496}, {-2224, -328, 496} }
      -- West turret's control, from outside the rockgat's 512-unit reach.
      shoot({ index = 86 }, { from = { {-2240, -256, 496}, {-2184, -92, 479}, {-2288, 48, 472}, {-2411, 148, 472} } })
    end },
    { "climb", function()
      path({ {-2487, 360, 472}, {-2640, 463, 490}, {-2687, 607, 532}, {-2679, 743, 528}, {-2608, 944, 528} }, { direct = true })
      kill({ index = 425 }, { hold = true, timeout = 40 })
      path({ {-2384, 864, 472}, {-2272, 836, 472}, {-2120, 784, 472}, {-1972, 712, 472},
             {-1973, 581, 471}, {-1969, 396, 517}, {-1973, 294, 557}, {-1953, 198, 604},
             {-1834, 5, 705}, {-1800, -84, 774}, {-1775, -174, 823}, {-1659, -218, 824},
             {-1591, -51, 863}, {-1568, 159, 899}, {-1705, 306, 961}, {-1798, 463, 980},
             {-1751, 665, 986}, {-1648, 816, 984}, {-1616, 752, 984}, {-1548, 800, 984} }, { direct = true })
      kill({ index = 431 }, { hold = true, timeout = 40 })
    end },
    { "bridge", function()
      -- Crossing the span starts the authored timeline: the bridge breaks, a
      -- skeet formation arrives and the Thunderskeet follows. The far end is
      -- an authored laser barrier, so the fight is held on the span.
      path { {-1563, 622, 988}, {-1420, 640, 984}, {-1280, 640, 984}, {-1120, 640, 984},
             {-1010, 640, 984}, {-930, 640, 984} }
      wait_until(function()
        local boss = dk3.entity { class = "monster_thunderskeet" }
        return boss and boss.health > 0
      end, { timeout = 60, reason = "Thunderskeet arrival" })
      -- Fight from the middle of the open east plateau: clear of the west
      -- cliff, which blocks the firing line, and of the laser at x=-621.
      move { -792, 632, 984 }
      -- The arena keeps knockback clear of the laser barrier at x=-621.
      kill({ class = "monster_thunderskeet" }, { radius = 4000, hold = true, timeout = 300,
                                                 arena = { { -1000, 440 }, { -700, 800 } } })
    end },
    { "north", function()
      wait(3)                              -- sprays still falling after the kill
      -- The boss drops a Megashield where it dies; fetch it only if it landed on
      -- the plateau (elsewhere it strands the bot beyond the broken span).
      local shield = dk3.entity { class = "item_megashield" }
      if shield and shield.visible and (shield.x + 800) ^ 2 + (shield.y - 632) ^ 2 < 260 ^ 2 and shield.z > 940 then
        try(pickup, { id = shield.id }, { timeout = 15 })
      end
      -- Step off the plateau into the pool below, as the original driver did;
      -- the area graph routes a long climb with repeated fall damage instead.
      -- North-west corner, steered straight: after the collapse the plateau's
      -- area graph routes even short hops over the south cliff.
      move({ -880, 744, 984 }, { direct = true, radius = 48 })
      move({ -1283, 908, 520 }, { direct = true, radius = 192 })
      -- In the pool, swim the area graph's water route to the north bank; a
      -- straight line loses to the westward current.
      move({ -1322, 1242, 520 }, { radius = 64 })
      move({ -1333, 1347, 509 }, { direct = true, radius = 32 })
      path { {-1331, 1415, 543},
             {-1314, 1510, 591}, {-1314, 1578, 625}, {-1270, 1700, 661} }
      try(heal, { index = 106 })           -- north tree, opened by the boss's death
      path({ {-1047, 1676, 664}, {-900, 1600, 664} }, { direct = true, radius = 24 })
      exit "e1m1c"
    end },
  }(visit, resumed)
end)

local function z() local _, _, height = dk3.position() return height end
local function x() local value = dk3.position() return value end
local function opened(index)
  return function() local state = dk3.mover { index = index } return state == "open" or state == "opening" end
end

-- The Marsh, part 3 (factory): a pipe climb to the gate's overhead control,
-- the yard, the switch whose monitor shows the exit opening, the raised
-- platform, the liftmaster descent and the lower route to the authored cut.
level("e1m1c", function(visit, resumed)
  if visit > 1 then return exit "e1m2a" end
  return stages {
    { "outside", function()
      path { {-814, 1574, 664}, {-566, 1587, 641}, {-502, 1831, 633}, {-413, 2069, 632},
             {-217, 2027, 536}, {-134, 2003, 495}, {-48, 1971, 445} }
      path { {46, 1863, 412}, {128, 1800, 408} }
      heal { index = 195 }
      path { {46, 1863, 412}, {-48, 1971, 445}, {121, 2101, 408}, {194, 2173, 408},
             {414, 2256, 408}, {425, 2469, 376}, {461, 2510, 403}, {480, 2576, 408} }
    end },
    { "pipe", function()
      -- The gate's switch is on the upper pipe; climb the sloping pipe, crouch
      -- under the low joint, then make the running jump to the upper run.
      path { {461, 2510, 403}, {425, 2469, 376}, {406, 2256, 408}, {406, 2184, 444} }
      path({ {406, 2144, 464}, {480, 2144, 456} }, { crouch = true, radius = 12, direct = true })
      move({ 494, 2136, 456 }, { radius = 12, direct = true })
      path({ {530, 2144, 528}, {530, 2281, 529} }, { radius = 20, direct = true })
      move({ 548, 2330, 528 }, { radius = 8, direct = true })
      leap({ 522, 2353, 536 }, { 424, 2424, 584 })
      path({ {424, 2464, 600}, {424, 2504, 624}, {480, 2544, 648}, {488, 2568, 664} }, { radius = 12, direct = true })
      expect(z() >= 640, "the gate's firing position is on the upper pipe")
    end },
    { "gate", function()
      shoot { index = 130 }                -- overhead breakable starts the delayed gate
      wait_until(opened(132), { timeout = 25, reason = "factory gate" })
      path({ {370, 2460, 376}, {425, 2469, 376}, {461, 2510, 403}, {480, 2576, 408} }, { radius = 20 })
      path({ {504, 2656, 408}, {504, 2748, 408}, {555, 2748, 408} }, { radius = 20 })
    end },
    { "yard", function()
      path { {787, 2765, 408}, {969, 2701, 411}, {1139, 2565, 481}, {1260, 2526, 522},
             {1412, 2473, 568}, {1562, 2480, 613}, {1721, 2479, 660}, {1911, 2463, 708},
             {2112, 2373, 744}, {2208, 2178, 777}, {2202, 2037, 792}, {2072, 1976, 792},
             {1944, 1920, 792}, {1888, 1768, 792}, {1855, 1570, 792}, {1794, 1441, 785} }
      shoot { index = 113 }                -- yard control opens the interior door
      wait_until(opened(114), { timeout = 25, reason = "yard door" })
      move({ 1744, 1440, 792 }, { radius = 20 })
      heal { index = 122 }
    end },
    { "interior", function()
      path({ {1794, 1441, 785}, {1855, 1570, 792}, {1888, 1768, 792}, {1944, 1920, 792} }, { radius = 20, direct = true })
      local health = dk3.health()
      if health < 100 then
        path({ {1725.5, 1840.625, 792}, {1712, 1876, 792} }, { radius = 16, direct = true })
        heal { index = 428 }
        path({ {1725.5, 1840.625, 792}, {1944, 1920, 792} }, { radius = 20, direct = true })
      end
      -- The yard door swings slowly (85 degrees at 10 a second) across this
      -- way and shoves whoever is in its sweep: cross once it stands open.
      wait_until(function() return dk3.mover { index = 114 } == "open" end, { timeout = 20, reason = "yard door fully open" })
      path({ {2072, 1976, 792}, {2202, 2037, 792}, {2215, 1900, 824}, {2401, 1737, 806} }, { radius = 20, direct = true })
      move({ 2398, 1698, 816 }, { radius = 12, direct = true })
      use { index = 216 }                  -- the switch; its monitor shows the exit
      cinematic()
      for _, door in ipairs({ 313, 214, 215 }) do
        wait_until(opened(door), { timeout = 25, reason = "exit doors" })
      end
    end },
    { "departure", function()
      path({ {2401, 1737, 806}, {2215, 1900, 824}, {2214, 1696, 849}, {2206, 1560, 849},
             {2208, 1478, 852}, {2208, 1416, 852} }, { radius = 16, direct = true })
      wait_until(function() return z() >= 960 end, { timeout = 10, reason = "platform raises the player" })
      path({ {2177, 1394, 964}, {2096, 1472, 992}, {2032, 1496, 960}, {1984, 1600, 960},
             {1824, 1632, 984}, {1728, 1660, 968} }, { radius = 20, direct = true })
      use { index = 118 }                  -- liftmaster lowers the player
      wait_until(function() return z() <= 690 end, { timeout = 8, reason = "liftmaster descent" })
      move({ 1653, 1596, 680 }, { radius = 20, direct = true })
    end },
    { "lower", function()
      path({ {1592, 1384, 680}, {1574, 1286, 664}, {1511, 1232, 581}, {1748, 1202, 537},
             {1824, 981, 495}, {1710, 973, 511} }, { radius = 24, direct = true })
      kill({ index = 160 }, { hold = true, timeout = 40 })   -- dry-bank Crox
      path({ {1783, 769, 472}, {1645, 672, 472} }, { radius = 24, direct = true })
      exit "e1m2a"
    end },
  }(visit, resumed)
end)

-- Sewer System: the lift (button 312, train 313), the hatch event (button 109
-- and its monitor) and use-door 316 lead to the flooded drum room. Its east
-- grate is opened from the far side: down the tube, ride the cart (train 123)
-- to the pump rooms, press the C4 room's button 159, ride back up and cross
-- the drum room round its stationary paddles. The upper sewer's use-door 267
-- leads to the pod room button 48, which opens the west double door for ten
-- seconds; beyond it the rockfall tilts a slab into the canal, swum beneath
-- to the alcove where button 160 slides out the ladder rungs to the exit.
-- `coop_route_aas.py e1m2a path …` shows the area graph's view of each leg.
level("e1m2a", function(visit, resumed)
  if visit > 1 then return progress "e1m2b" end
  return stages {
    { "lift", function()
      use { index = 312 }
      ride { index = 313 }
      move({ -1430, -328, -344 }, { direct = true, radius = 24 })
    end },
    { "upper", function()
      path({ {-1360, -460, -344}, {-1232, -468, -328}, {-1104, -468, -312} }, { direct = true, radius = 24 })
      use { index = 109 }                  -- t10: opens the sewer1 hatch, shows its monitor
      cinematic()
      use { index = 316 }                  -- use-operated door to the hatch room
    end },
    { "pool", function()
      -- The hatch opens onto a flooded drum whose stationary west paddle
      -- splits the doorway: swim north of it and west of the north paddle
      -- into the north channel.
      move({ -1112, 30, -220 }, { radius = 40, timeout = 40 })  -- up the sloping channel
      wait_until(opened(234), { timeout = 25, reason = "sewer hatch" })
      path({ {-1072, 40, -224}, {-990, 48, -240}, {-800, 260, -240}, {-770, 400, -240} }, { direct = true, radius = 24 })
    end },
    { "sewer", function()
      -- North over the grate walkway, down the tube and east along the
      -- sewer to the cart's upper stop.
      move({ 560, 640, -504 }, { radius = 32, timeout = 90 })
    end },
    { "cart", function()
      -- The cart (train 123) waits over the drop to the pump room; its own
      -- button sends it round to the lower stop by the pumps.
      -- Press it from inside, close enough to reach past the cart's wall.
      move({ 650, 628, -504 }, { radius = 12, direct = true })
      use { index = 125 }
      ride { index = 123 }
    end },
    { "pumps", checkpoint = true, function()
      -- From the cart's lower stop through the pump rooms and up the stairs
      -- to the C4 room; its button opens the drum room's east grate.
      use { index = 159 }
      pickup { class = "weapon_c4viz" }
    end },
    { "return", function()
      -- The pump rooms are a pocket: back down to the cart and ride it up.
      move({ 898, 172, -648 }, { radius = 32, timeout = 60 })
      move({ 896, 256, -680 }, { radius = 24, direct = true })
      use { index = 385 }
      ride { index = 123 }
      -- Well clear of the cart: the area graph has no floor where it stands.
      path({ {560, 640, -504}, {500, 640, -504} }, { radius = 24, direct = true })
    end },
    { "east", checkpoint = true, function()
      -- Back up the tube (its top lip onto the walkway is a hop the area
      -- graph lacks); from the walkway's east end, swim round the north
      -- paddle to the open east grate.
      move({ -620, 740, -312 }, { radius = 64, timeout = 90 })
      path({ {-650, 690, -310}, {-700, 560, -280}, {-712, 430, -236}, {-712, 372, -204} }, { direct = true, radius = 24 })
      path({ {-695, 345, -204}, {-650, 250, -232}, {-560, 200, -232}, {-430, 40, -232}, {-390, 40, -210} }, { direct = true, radius = 24 })
    end },
    { "upper sewer", checkpoint = true, function()
      -- Up the ramp east of the grate; the upper sewer's sludgeminions wait at
      -- its top, and its health pack is close by.
      move({ 113, -81, -72 }, { radius = 48, timeout = 40 })
      clear { radius = 500 }
      local health, maximum = dk3.health()
      if health < 0.8 * maximum then try(function() pickup { index = 64 } end) end
      -- Round the upper sewer to its use-door; both leaves are separate.
      use { index = 267 }
      if dk3.mover { index = 268 } == "closed" then use { index = 268 } end
      -- The sludgeminion by the west ramp would catch the dash: hunt it first.
      kill({ index = 6 }, { radius = 2000, timeout = 90 })
      recover(0.6)
      -- The pod room button opens the far west double door for ten seconds:
      -- run over the walkway above the waterfall shaft and up the ramp.
      for attempt = 1, 3 do
        use { index = 48 }                 -- its monitor shows the doors open
        if try(function()
          path({ {-760, 1290, -208}, {-865, 1295, -208}, {-900, 1240, -216}, {-960, 1250, -200}, {-1050, 1290, -200},
                 {-1150, 1290, -190}, {-1206, 1260, -168}, {-1225, 1220, -150}, {-1233, 1150, -120}, {-1233, 1073, -89},
                 {-1233, 860, 24}, {-1265, 796, 48}, {-1310, 796, 56}, {-1348, 817, 56}, {-1348, 860, 80},
                 {-1348, 900, 88}, {-1398, 1024, 88}, {-1530, 1024, 88} },
               { direct = true, radius = 24, timeout = 6 })
        end) then break end
      end
      expect(x() <= -1490, "through the timed double door")
    end },
    { "canal", checkpoint = true, function()
      -- North past the rockfall and east along the ledge; its trigger drops
      -- the floor and tilts the rock slab into the canal. The surface is then
      -- blocked by the slab and, further east, by a barrier just under the
      -- water: slide down the slab and swim the deep passage beneath both to
      -- the basin below the ladder alcove.
      move({ -839, 1452, 72 }, { radius = 40, timeout = 60 })
      move({ -740, 1500, 80 }, { radius = 24, direct = true })
      wait(2)
      move({ -700, 1510, 80 }, { radius = 24, timeout = 20 })
      path({ {-560, 1530, -60}, {-480, 1540, -130}, {-400, 1560, -140}, {-330, 1560, -150},
             {-260, 1530, -150}, {-208, 1530, -170}, {-154, 1529, -196}, {-49, 1490, -225}, {-48, 1454, -260},
             {111, 1450, -260}, {146, 1519, -248}, {223, 1583, -240}, {385, 1604, -67}, {422, 1519, 8} },
           { direct = true, radius = 24, fight = false })
      move({ 470, 1320, 72 }, { radius = 24, direct = true })
    end },
    { "ladder", checkpoint = true, function()
      use { index = 160 }                  -- rungs slide out of the shaft wall in turn
      wait(5)
      move({ 512, 1322, 72 }, { radius = 12, direct = true })
      move({ 512, 1250, 440 }, { radius = 24, direct = true, timeout = 30 })
      exit "e1m2b"
    end },
  }(visit, resumed)
end)

-- Sewer System part 2: from the ladder top along the pipe corridor onto the
-- gratings over the pipe room, off their north edge into the water chute,
-- whose trigger raises the sluice at its foot, and over the falls into the
-- flooded tank (a train of water the area graph knows nothing of). Under
-- water to the control room, whose button drains the tank and sinks the
-- hugedoor; back over the spinning drum fan before the water falls; through
-- the hugedoor and the passage behind it into the pit below the pipe room,
-- up to the valve walkway; the valve opens the west doors for ten seconds;
-- the long way west to the lift; through the double door to the end room
-- and its end-of-level button, whose scene takes Larry's elevator up.
-- `flood(goals, box)` (prelude) maps the tank's swim routes in the live game.
level("e1m2b", function(visit, resumed)
  if visit > 1 then return progress "e1m3a" end
  return stages {
    { "pipes", function()
      -- The gratings over the pipe room are sealed; the way on is the water
      -- chute below their north edge, a drop the area graph never links (and
      -- a hard landing in its shallow water). Top up from the packs at the
      -- south end and clear the north end first.
      for _, item in ipairs({ 267, 208, 149 }) do try(function() pickup { index = item } end) end
      -- Already down the chute (a run to the edge can carry on over it):
      -- go on from its floor.
      if z() > 0 then
        try(function() move({ 1560, 1376, 344 }, { radius = 32, timeout = 60 }) end)
        if z() > 0 then
          try(function() clear { radius = 400, timeout = 30 } end)
          move({ 1560, 1480, -200 }, { radius = 48, direct = true, timeout = 10 })
        end
      end
      -- Down the chute floor; its trigger (t44) raises the sluice at the foot.
      path({ {1640, 1488, -244}, {1760, 1488, -304}, {1820, 1488, -325}, {1900, 1480, -340},
             {2060, 1480, -340}, {2150, 1480, -344} }, { direct = true, radius = 32, fight = false })
    end },
    { "tank", function()
      -- Over the falls into the flooded tank (the hugewater train). Its drain
      -- is reached under water: dive at the waterfall's foot and swim the
      -- submerged lower level south and east (some eleven seconds without
      -- air) to the air gap west of the control room.
      move({ 2272, 1448, -488 }, { radius = 32, direct = true, timeout = 15 })
      path({ {2368, 1376, -488}, {2368, 1376, -584}, {2392, 1352, -584}, {2392, 896, -584}, {2464, 824, -584},
             {3016, 824, -584}, {3016, 656, -596}, {3232, 656, -596}, {3232, 656, -488}, {3448, 640, -488},
             {3448, 560, -488} }, { direct = true, radius = 24, fight = false })
      -- The control room's west window is the short way back out. Break it
      -- with the glove (an ion bolt would discharge in the water), take the
      -- room's two health packs and come back up for air.
      path({ {3480, 560, -600}, {3510, 560, -636} }, { direct = true, radius = 16, fight = false })
      shoot({ index = 235 }, { weapon = 1, timeout = 10 })
      path({ {3600, 560, -636} }, { direct = true, radius = 24, fight = false })
      for _, item in ipairs({ 202, 273 }) do try(function() pickup({ index = item }, { fight = false, timeout = 10 }) end) end
      path({ {3600, 560, -636}, {3500, 560, -636}, {3448, 600, -440} }, { direct = true, radius = 24, fight = false })
    end },
    { "drain", function()
      -- The drain empties the tank and sinks the hugedoor (some twenty
      -- seconds). Dry, the control room's side is cut off by the drum fan
      -- spinning in the middle of the tank: press, swim back through the
      -- window and over the drum, under the low gap's ceiling, before the
      -- water falls (about seven seconds), then wait on the floor by the door.
      path({ {3500, 560, -636}, {3600, 560, -636}, {3664, 640, -640} }, { direct = true, radius = 24, fight = false })
      use { index = dk3.entity { index = 199 } and 199 or 402 }  -- one button per skill
      path({ {3600, 560, -636}, {3500, 580, -648}, {3200, 600, -648}, {3130, 600, -616}, {3060, 600, -608},
             {2990, 580, -605}, {2900, 420, -605} }, { direct = true, radius = 24, fight = false })
      wait_until(function() return dk3.mover { index = 31 } == "open" end, { timeout = 40, reason = "hugedoor" })
      move({ 2880, 400, -712 }, { radius = 24, direct = true })
    end },
    { "passage", checkpoint = true, function()
      -- West up the passage behind the hugedoor; its trigger opens the doors
      -- (t42) into the pit below the pipe room, whose ladder leads up to the
      -- valve ledge.
      move({ 2139, 367, -474 }, { radius = 32, timeout = 60 })
    end },
    { "valve", function()
      -- Through the doors (t42) into the pit, up its ladder and over to the
      -- platform above the central machine; the valve stands on the walkway
      -- above that, up a ladder the area graph does not link. The valve opens
      -- the doors (t40) west of the pit for ten seconds.
      -- Sludgeminions wade in the pit and lob sludge: fight them from its
      -- south end before walking up its length.
      move({ 1640, 400, -488 }, { radius = 48, timeout = 60 })
      try(function() kill({ class = "monster_sludgeminion" }, { hold = true, radius = 800, timeout = 45 }) end)
      -- Up the pit's west side and along its north end to the ladder: the
      -- spinning column in the middle (absent from the area graph) has a sump
      -- round its foot that traps a player.
      path({ {1600, 520, -488}, {1600, 945, -488}, {1720, 1060, -488}, {1833, 1105, -488} }, { radius = 40, timeout = 60 })
      -- The platform is a frame of narrow beams over the pit: walk the
      -- straight one along y 840 to the ladder, braking at each turn.
      local function climb()
        move({ 1550, 985, 24 }, { radius = 24, timeout = 120 })   -- stop short of the drop
        path({ {1545, 880, -8}, {1600, 850, -8}, {1900, 840, -8}, {1975, 860, 0} }, { direct = true, radius = 16 })
        move({ 2024, 880, 100 }, { radius = 24, direct = true, timeout = 15 })
      end
      climb()
      try(function() pickup({ index = 26 }, { timeout = 20 }) end)   -- ion ammunition for the way west
      -- A worker stands at the valve wheel, in every line to it.
      try(function() kill({ index = 50 }, { radius = 400, timeout = 20 }) end)
      -- Back to the doors the way up, over the beams: the area graph's way
      -- drops into the pit, a fall that costs a fifth of the player's health
      -- and the doors' ten seconds.
      local function back()
        -- Stop on the walkway's edge above the beam's widest end, then step
        -- straight down onto it (a running drop overshoots into the pit).
        path({ {2009, 1000, 72}, {2008, 864, 72} }, { direct = true, radius = 12, timeout = 6, fight = false })
        path({ {1978, 864, -8}, {1900, 840, -8}, {1600, 850, -8}, {1532, 900, -8} },
             { direct = true, radius = 16, timeout = 6, fight = false })
        leap({ 1530, 905, -8 }, { 1540, 960, 24 })
        -- The doors open once the wheel has turned: wait at them.
        move({ 1380, 1045, 70 }, { radius = 32, timeout = 20, fight = false })
      end
      -- A turn blocked part-way (the worker's body by the wheel) springs back
      -- without opening the doors: press until the wheel stays open.
      local function turn()
        for _ = 1, 4 do
          use { index = 112 }
          if try(function()
            wait_until(function() return dk3.mover { index = 112 } == "open" end, { timeout = 4, reason = "valve open" })
          end) then return end
        end
        error("the valve never stayed open", 0)
      end
      for attempt = 1, 3 do
        turn()
        if try(back) then break end
        if attempt < 3 then climb() end
      end
      expect(x() < 1420, "through the valve doors")
    end },
    { "west", checkpoint = true, function()
      -- Sludgeminions hold the long way west; their globs are dodged from a
      -- distance but land on a player running past: stand and fight each as
      -- it engages. The first wades by the pool with the health pack and sees
      -- the doors: fight it from inside them (they close behind the player),
      -- then take the pack.
      try(function()
        kill({ class = "monster_sludgeminion" }, { around = { 960, 1112, 152 }, radius = 250, hold = true, timeout = 40,
                                                  arena = { { 1150, 990 }, { 1405, 1130 } } })
      end)
      try(function() pickup({ index = 28 }, { timeout = 20 }) end)
      -- Out of the pool (if the pack took the bot in) over its north lip,
      -- facing the lip for the water jump.
      if dk3.position() < 1000 then
        try(function() path({ {930, 1105, 135}, {905, 1098, 150} }, { direct = true, radius = 16, fight = false, timeout = 8 }) end)
      end
      -- West along the wading channel, entered clear of the deep pool under
      -- the overhang east of it.
      path({ {880, 1075, 168}, {875, 1112, 152}, {760, 1112, 152} }, { direct = true, radius = 16, timeout = 15 })
      -- Each sludgeminion along the channels is fought from a chosen spot
      -- before the bend that brings the bot to it (spot, prey, arena).
      local function engage(spot, prey, arena)
        move(spot, { radius = 32, timeout = 90, cautious = true })
        try(function()
          kill({ class = "monster_sludgeminion" }, { around = prey, radius = 220, hold = true, timeout = 40, arena = arena })
        end)
      end
      engage({ 250, 1112, 152 }, { -83, 1034, 152 }, { { 100, 1092 }, { 450, 1132 } })
      engage({ -40, 1120, 152 }, { -152, 832, 152 }, { { -190, 1000 }, { -20, 1150 } })
      engage({ -152, 760, 152 }, { -264, 536, 152 }, { { -172, 640 }, { -132, 900 } })
      engage({ -300, 536, 160 }, { -736, 536, 280 }, { { -460, 516 }, { -280, 556 } })
      move({ -1471, 536, 280 }, { radius = 48, timeout = 300, cautious = true })
    end },
    { "hall", checkpoint = true, function()
      -- Into the hall (a froginator, sludgeminions and protopods), standing to
      -- fight as they come; then its health and ion ammunition.
      move({ -1356, 225, 360 }, { radius = 48, timeout = 180, cautious = true })
      for _, item in ipairs({ 203, 274, 265 }) do try(function() pickup({ index = item }, { timeout = 30 }) end) end
      move({ -1071, -768, 472 }, { radius = 48, timeout = 300, cautious = true })
    end },
    { "lift", function()
      ride { index = 198 }                 -- its trigger raises it to the upper floor
      for _, door in ipairs({ 232, 231 }) do
        if dk3.mover { index = door } == "closed" then use { index = door } end
      end
      move({ -1440, -768, 920 }, { radius = 24, direct = true })
    end },
    { "end", checkpoint = true, function()
      -- The end-of-level button on the end room's south wall (single player;
      -- its co-op twin, 413, opens Larry's elevator instead): the closing
      -- scene takes Hiro up in the elevator and travels on.
      -- Off the lift's landing first: a fight there leaves the player in
      -- the area over the shaft, whose way to the button is down the lift.
      move({ -1440, -800, 920 }, { direct = true, radius = 24, timeout = 10 })
      use { index = 135 }
      cinematic()
      wait(30)
    end },
  }(visit, resumed)
end)

-- Solitary: from the arrival corridor the guard post's button opens the cell
-- block doors (and calls its guards); in the cell block, breaking the panel
-- by the cells (explosive 16) starts the break-out: every laser goes off,
-- the cells open and the wall at the east laser falls.
level("e1m3a", function(visit, resumed)
  if visit > 1 then return progress "e1m3b" end
  -- Objectives only where navigation and its planner find the way (doors,
  -- lasers, the jammed door, the big lift): moves are spelled out only for
  -- the acro-boost climb and the fan draught, which the area graph cannot
  -- express, and the cell block 2 cage, which generic lift handling does not
  -- yet ride reliably.
  return stages {
    { "breakout", function()
      -- The cell block's control panel, in sight only from the pit below it:
      -- the planner opens the guard room and the hydraulic door on the way.
      shoot { index = 16 }
      wait(3)
      -- The pit's two health packs, before the released inmates arrive.
      for _, item in ipairs({ 263, 301 }) do try(function() pickup({ index = item }, { timeout = 10 }) end) end
    end },
    { "ramp", checkpoint = true, function()
      -- Access Granted at the top of the ramp round the lift shaft (through
      -- the lift room's platdoor), then the shotcycler on the ramp below:
      -- the guards and inmaters ahead fall far faster to it.
      use { index = 237 }
      try(function() pickup({ index = 164 }, { timeout = 30 }) end)
    end },
    { "broken door", checkpoint = true, function()
      -- The jammed door to Cell Block 2 sparks and shoves back anyone at it:
      -- blast the short-circuiting wires above the big lift's top landing.
      -- Its halves then stop apart, leaving a gap a crouching player fits.
      shoot { index = 122 }
      wait(3)
      -- Ion cells about the landing for the fights ahead.
      for _, item in ipairs({ 193, 155 }) do try(function() pickup({ index = item }, { timeout = 30 }) end) end
    end },
    { "hidden door", function()
      -- The block's main door is a dummy. The hidden door right of the green
      -- Mishima sign opens on a barrel of explosives against a cracked panel:
      -- blow both, from outside the barrel's blast.
      if not try(function() shoot { index = 214 } end) then shoot { index = 119 } end
      wait(2)
      expect((dk3.entity { index = 119 } or {}).health ~= 1, "the panel behind the barrel is broken")
    end },
    { "pipe room", checkpoint = true, function()
      -- Crawl through the hole into the red-lit pipe room, round its pipes to
      -- the ladder at the back and up onto the upper pipe. The acro boost
      -- lies on the floor in a pocket fenced by low pipes, open from the pipe
      -- tops: drop in for it, then the boosted jump clears the fence onto a
      -- pipe below the hatch and, from there, up through the hatch (the
      -- boost lasts thirty seconds).
      path({ {2400, 230, -168}, {2344, 168, -168}, {2344, 136, -168}, {2312, 104, -168}, {2328, 72, -168}, {2344, 40, -168} },
           { direct = true, crouch = true, radius = 16, timeout = 15 })
      path({ {2280, 56, -168}, {2264, 40, -168}, {2264, -184, -168}, {2296, -216, -168}, {2312, -216, -168}, {2344, -184, -168}, {2344, -136, -168}, {2360, -120, -168}, {2384, -120, -168} },
           { direct = true, crouch = true, radius = 12, timeout = 15 })
      move({ 2382, -150, -80 }, { radius = 16, direct = true, timeout = 10 })
      path({ {2360, -152, -72}, {2328, -136, -80}, {2296, -104, -72}, {2264, -72, -72}, {2264, -40, -72}, {2296, -40, -72} },
           { direct = true, crouch = true, radius = 12, timeout = 15 })
      move({ 2340, -30, -168 }, { radius = 16, direct = true, timeout = 8 })
      expect(not (dk3.entity { index = 216 } or {}).visible, "acro boost taken")
      leap({ 2336, 4, -168 }, { 2336, 72, -168 })
      local _, _, z = dk3.position()
      expect(z > -120, "on the pipe below the hatch")
      move({ 2336, 72, z }, { radius = 8, direct = true, crouch = true, timeout = 5 })
      leap({ 2336, 72, z }, { 2336, 20, -16 })
      _, _, z = dk3.position()
      expect(z > -30, "through the hatch")
    end },
    { "fans", checkpoint = true, function()
      -- Back along the platform, staying low under the fans, over the
      -- lowest pipe and into the pipe mouth at its end: its draught carries
      -- the player down and out into Cell Block 2.
      path({ {2232, 40, -16}, {2168, -24, -16}, {2088, -104, -16}, {2088, -296, -16}, {2088, -349, -16}, {2120, -376, -16}, {2152, -408, -16}, {2184, -392, -16}, {2216, -360, -16} },
           { direct = true, crouch = true, radius = 12, timeout = 15 })
      leap({ 2216, -360, -16 }, { 2300, -360, -24 })
      path({ {2280, -376, -24}, {2280, -456, -24}, {2340, -480, -24} }, { direct = true, crouch = true, radius = 12, timeout = 15 })
      leap({ 2340, -480, -24 }, { 2400, -480, -104 })
      path({ {2364, -480, -104}, {2330, -480, -168} }, { direct = true, crouch = true, radius = 16, timeout = 10 })
    end },
    { "cell block 2", checkpoint = true, function()
      -- Down the lift (a cage; its button rides on it) to the torture room and
      -- along past the cells to the control room: its computer extends the
      -- platform over the torture chamber and opens the door to it upstairs.
      -- Its health station before the guards upstairs, then back up the lift.
      -- The cage's rides stay explicit: generic lift handling does not yet
      -- ride it reliably (crushes at its landing edge).
      move({ 1864, -424, -168 }, { radius = 24, timeout = 60 })
      use { index = 268 }
      ride { index = 267 }
      use { index = 357 }
      wait_until(function() return dk3.mover { index = 206 } ~= "closed" or dk3.mover { index = 30 } ~= "closed" end, { timeout = 10, reason = "bridge moving" })
      recharge { index = 146 }
      move({ 1864, -424, -488 }, { radius = 24, timeout = 120 })
      use { index = 268 }
      ride { index = 267 }
    end },
    { "bridge", checkpoint = true, function()
      -- Along to the door the computer opened and over the extended platform
      -- (void to the area graph) to the door at its far end, open ten seconds
      -- from its button: crossed at once, which the planner does not time.
      wait_until(function() return dk3.mover { index = 206 } == "open" end, { timeout = 30, reason = "platform extended" })
      path({ {2088, -296, -168}, {2088, -8, -168}, {2040, 8, -168}, {1900, -8, -170}, {1760, 30, -170} }, { direct = true, radius = 24, timeout = 20 })
      use { index = 419 }
      wait_until(function() return dk3.mover { index = 287 } == "open" end, { timeout = 10, reason = "door 287" })
      path({ {1640, 64, -168}, {1584, 72, -160} }, { direct = true, radius = 24, timeout = 8 })
    end },
    { "out", checkpoint = true, function()
      -- Up the stairs past the guards and through the access door (its blue
      -- button beside it) to the control room: its keyboard unlocks the gates
      -- on the way out. A guard holds the far end of the corridor to the
      -- access door; an inmater waits along the catwalk beyond and follows
      -- (fight it there); a guard on the catwalk above the keyboard fires down
      -- (fight him from the floor west of the lift).
      try(function() kill({ index = 24 }, { timeout = 30 }) end)
      use { index = 27 }
      -- Held: chased, it leads back out through the access door, which then
      -- shuts behind the player.
      try(function() kill({ index = 254 }, { hold = true, radius = 600, timeout = 25 }) end)
      try(function()
        kill({ index = 165 }, { hold = true, radius = 700, timeout = 12, arena = { { 1380, 380 }, { 1530, 560 } } })
      end)
      try(function() pickup({ index = 270 }, { timeout = 15 }) end)
      use { index = 101 }
      -- Up the lift beside it (a plat the bot rides) to the catwalk, the
      -- health station by the gates before part 2's guards, then out.
      ride { index = 19 }
      try(function() recharge { index = 154 } end)
      advance({ id = dk3.exit_to("e1m3b") })
      exit "e1m3b"
    end },
  }(visit, resumed)
end)

-- Solitary, part 2: the console behind a typing worker opens the big door;
-- a shot at the lightning box above the laser corridor kills its beams and
-- opens the floor beyond; the cell keycard lets the bot into the torture
-- chamber scenes that free Superfly, who must be near at the exit.
level("e1m3b", function(visit, resumed)
  if visit > 1 then return exit "e1m4a" end
  return stages {
    { "guards", function()
      -- Two guards fire on the arrival ledge; a pack lies in the steam below it.
      -- Fought from the ledge: in the open below they hit twice as often.
      try(function() clear { radius = 450, timeout = 25, hold = true } end)
    end },
    { "console", function()
      use { index = 186 }
      wait_until(function() return dk3.mover { index = 255 } == "open" end, { timeout = 20, reason = "big door open" })
    end },
    { "lasers", function()
      -- Inmates come through the big door; the lightning box over the far
      -- end of the laser corridor kills its beams and opens the floor.
      -- The inmate past the beams (250 health, a slow laser of his own)
      -- comes once they die: met from the far side of the console room, at
      -- the range his laser takes long to cross.
      shoot { index = 125 }
      move({ 200, 1100, -168 }, { timeout = 20 })
      try(function()
        kill({ index = 167 }, { hold = true, radius = 1200, timeout = 60, arena = { { 120, 980 }, { 300, 1180 } } })
      end)
    end },
    { "floor drop", checkpoint = true, function()
      -- The opened floor beyond the dead beams drops to the level below
      -- (the area graph has that floor in place); its packs, then the card.
      wait_until(function() return dk3.mover { index = 208 } == "open" end, { timeout = 20, reason = "laser floor open" })
      move({ -144, 1180, -168 }, { radius = 24, timeout = 30 })
      move({ -144, 1250, -270 }, { direct = true, radius = 32, timeout = 10 })
      try(pickup, { index = 263 }, { timeout = 30 })
      try(pickup, { index = 219 }, { timeout = 20 })
      use { index = 33 }                     -- the hatch up the stairs
    end },
    { "pit room", checkpoint = true, function()
      -- West past the octagon and down the stairs south to the catwalk that
      -- ends short of the round pit room's outer walkway: jumped across
      -- (walked off slowly, the gap takes the player), then over the south
      -- bridge and round the inner ring to the button by the lift that
      -- opens the north door.
      move({ -404, 1328, -152 }, { timeout = 90 })
      move({ -960, 820, -232 }, { timeout = 40 })
      move({ -960, 860, -232 }, { direct = true, radius = 16, timeout = 10 })
      try(leap, { -960, 885, -232 }, { -960, 990, -280 })
      local _, _, z = dk3.position()
      expect(z < -270 and z > -300, "on the pit's outer walkway")
      path({ { -960, 1009, -280 }, { -960, 1060, -296 }, { -960, 1150, -296 }, { -1113, 1209, -296 }, { -1158, 1249, -296 } },
           { direct = true, radius = 24, timeout = 20 })
      use { index = 179 }
      -- Two packs on the ring's east side, for the fights at the lift ahead.
      try(pickup, { index = 256 }, { timeout = 20 })
      try(pickup, { index = 226 }, { timeout = 20 })
    end },
    { "card", checkpoint = true, function()
      -- North through the door it opened, west and round to the passage
      -- south to the lift: its switch starts the machinery in the passage
      -- (charges blow the way over the block). The lift (a train: a button
      -- at its foot, another on board) goes up to the cell keycard's floor.
      use { index = 198 }                    -- the console's operate button
      wait(5)
      use { index = 133 }                    -- the lever the broken machinery bared
      -- Guards and inmates hold the lift's top: the packs on this floor first.
      for _, pack in ipairs({ 409, 156, 212, 158 }) do try(pickup, { index = pack }, { timeout = 20 }) end
      wait(2)
      -- Under the jammed door it raised part way, crawling.
      move({ -1680, 1824, -296 }, { radius = 24, timeout = 30 })
      move({ -1632, 1824, -296 }, { direct = true, crouch = true, radius = 16, timeout = 15 })
      move({ -1580, 1824, -296 }, { direct = true, crouch = true, radius = 16, timeout = 15 })
    end },
    { "lift", checkpoint = true, function()
      -- An inmate and two guards wait at the top. First the mega shield
      -- behind the low fence here (a shotcycler jump over it, shells there
      -- for the jump back).
      if dk3.ammo(4) > 0 then
        move({ -1462, 1790, -296 }, { timeout = 30 })
        if try(blastjump, { -1462, 1858, -296 }, { -1462, 1936, -280 }) then
          try(pickup, { index = 94 }, { timeout = 10 })
          try(pickup, { index = 132 }, { timeout = 10 })
          try(blastjump, { -1462, 1925, -280 }, { -1462, 1830, -296 })
          move({ -1462, 1800, -296 }, { timeout = 20 })
        end
      end
      use { index = 357 }
      ride { index = 173 }
      -- Fought from inside the cage (its walls are cover), the inmate by
      -- the landing first.
      try(function() kill({ index = 64 }, { hold = true, timeout = 30 }) end)
      try(function() clear { radius = 700, timeout = 45, hold = true } end)
      -- Carried back down meanwhile (a press of its button in the fight).
      local _, _, z = dk3.position()
      if z < -100 then ride { index = 173 } end
    end },
    { "red room", checkpoint = true, function()
      -- Down the hall to the red room where Superfly hangs: his scene.
      touch { index = 50 }
      wait_until(function() return dk3.mode() == "normal" end, { timeout = 120, reason = "scene over" })
      try(function() clear { radius = 600, timeout = 30 } end)
    end },
    { "keycard", checkpoint = true, function()
      -- The power box near the ceiling, where the wires from the Mishima
      -- logo sign lead: shot, it blows the sign open on the prison keycard.
      shoot { index = 88 }
      pickup { index = 99 }
    end },
    { "superfly", checkpoint = true, function()
      -- Back to Superfly with the card: Hiro frees him, the door on opens.
      touch { index = 412 }
      wait_until(function() return dk3.mode() == "normal" end, { timeout = 120, reason = "scenes over" })
    end },
    { "out", checkpoint = true, function()
      -- Through the door that opened: inmates and guards hold the room
      -- before the exit; its packs (two up the ramp) after the fight.
      -- Superfly (unarmed, and the level is lost with him) waits outside.
      move({ -2150, 1504, -24 }, { timeout = 60 })
      dk3.sidekick("all", "stay")
      move({ -2240, 1504, -24 }, { timeout = 30 })
      try(function() clear { radius = 900, timeout = 60 } end)
      for _, pack in ipairs({ 211, 276, 201, 202 }) do try(pickup, { index = pack }, { timeout = 20 }) end
      dk3.sidekick("all", "follow")
      exit "e1m4a"
    end },
  }(visit, resumed)
end)

-- Crematorium, part 1: through the hall and the yard outside to the control
-- room's console (past the bar gate Superfly cannot duck under, and the
-- catwalk): its left keypad opens the loading dock, its right one the bar
-- gate for Superfly. Down the dock's ramp to part 2, Superfly along.
level("e1m4a", function(visit, resumed)
  if visit > 1 then return exit "e1m4b" end
  return stages {
    { "hall", function()
      -- Superfly is unarmed: he waits while the guards on the stairs are
      -- dealt with, then takes the ion blaster lying in the room.
      dk3.sidekick("all", "stay")
      try(function() clear { radius = 600, timeout = 40 } end)
      try(companion_take, { index = 32 }, "superfly")
      wait(4)
      dk3.sidekick("all", "follow")
    end },
    { "console", checkpoint = true, function()
      touch { index = 285 }                  -- the left keypad lights up
      use { index = 283 }                    -- loading dock door
      touch { index = 115 }
      use { index = 119 }                    -- bar gate
      dk3.sidekick("all", "follow")
    end },
    { "dock", checkpoint = true, function()
      -- The way out runs down into a hall under walkways held by guards (and
      -- a cambot): Superfly waits while it is cleared, takes the health by
      -- the stairs, and comes along to the door.
      dk3.sidekick("all", "stay")
      move({ -3, -719, -36 }, { timeout = 120 })
      try(function() clear { radius = 700, timeout = 60 } end)
      move({ 300, -928, -100 }, { timeout = 60 })
      try(function() clear { radius = 700, timeout = 60 } end)
      dk3.sidekick("all", "follow")
      tend(1600, 0.9)
      try(regroup, 250, 90)
      exit "e1m4b"
    end },
  }(visit, resumed)
end)

-- Crematorium, part 2: the keypad by the entrance opens the furnace hall;
-- its console runs the conveyor, and a shot at the smoking weak spot on the
-- pipe in the central recess floods it until the fan shorts out and blows
-- the conveyor door open. Beyond: a lift, a vent under the floor, beams over
-- a pit, and the control box over a keypad that opens the way on.
level("e1m4b", function(visit, resumed)
  if visit > 1 then return exit "e1m4c" end
  return stages {
    { "hall", function()
      -- Superfly waits at the corridor's far end while the hall beyond the
      -- garage door (guards, a turret on its ceiling) is cleared.
      dk3.sidekick("all", "stay")
      use { index = 287 }
      -- The turret first: from its ceiling it sees down the corridor to him.
      try(shoot, { index = 127 }, { timeout = 20 })
      try(function() clear { radius = 900, timeout = 60 } end)
      -- The garage door may have closed again: open it from this side (its
      -- other button) for Superfly, and wait for him; then the health about
      -- the hall is his.
      -- (It is slow and shuts again soon: go back through to him and come
      -- through together.)
      dk3.sidekick("all", "follow")
      if not try(regroup, 250, 3) then
        try(use, { index = 288 }, { timeout = 15 })
        try(move, { 610, -930, -152 }, { timeout = 30 })
        try(regroup, 120, 20)
        try(use, { index = 287 }, { timeout = 15 })
        try(move, { 780, -930, -152 }, { timeout = 30 })
        try(regroup, 200, 30)
      end
      tend(1200, 0.8)
    end },
    { "stock", function()
      -- Before the fight past the conveyor: the sidewinder and rockets in
      -- the small room by the entrance, its health station, and the
      -- chromatic armor behind the grate in the central recess (before the
      -- pipe floods the recess with charged water).
      try(pickup, { index = 91 }, { timeout = 40 })
      try(pickup, { index = 90 }, { timeout = 20 })
      try(pickup, { index = 500 }, { timeout = 20 })
      try(recharge, { index = 130 })
      try(shoot, { index = 63 }, { timeout = 30 })
      try(pickup, { index = 86 }, { timeout = 40 })
      try(pickup, { index = 30 }, { timeout = 30 })
    end },
    { "pipe", checkpoint = true, function()
      try(use, { index = 245 }, { timeout = 30 })
      wait_until(function() return dk3.mode() == "normal" end, { timeout = 60, reason = "conveyor scene over" })
      -- Superfly out of the recess with the player before the water comes.
      dk3.sidekick("all", "follow")
      try(regroup, 200, 30)
      shoot { index = 176 }
      wait(8)
    end },
    { "on", checkpoint = true, function()
      -- On past the conveyor, up the casket lift, through the vent and over
      -- the beams to the room with two doors: the box at the ceiling, where
      -- the keypad's wires lead, opens the one on.
      -- Superfly follows to the conveyor's door and waits there out of the
      -- fight below; he rejoins once the keypad's box opens the doors.
      dk3.sidekick("all", "follow")
      move({ 1528, -700, -134 }, { timeout = 90 })      -- along to the conveyor's door
      try(regroup, 200, 30)
      dk3.sidekick("all", "stay")
      move({ 1453, -420, -137 }, { timeout = 60 })
      move({ 1592, 700, -510 }, { timeout = 60 })      -- down the conveyor
      try(function() clear { radius = 300, timeout = 40 } end)
      -- The keypad room is reached the long way: the casket lift, the vent
      -- and the hall under the floor, the beams over the pit.
      -- The casket lift: its button is on board.
      ride { index = 146 }
      -- Off its top straight (the area graph knows only the shaft below).
      move({ 1064, 960, -320 }, { direct = true, radius = 24, timeout = 10 })
      move({ 1036, 1005, -320 }, { direct = true, radius = 24, timeout = 10 })
      -- Up the ladder on the north wall, at its west end, and along the lip
      -- under the west wall to the vent's mouth. (Climbing never settles:
      -- the climb is timed.)
      move({ 1035, 1060, -320 }, { direct = true, radius = 16, timeout = 10 })
      move({ 977, 1060, -320 }, { direct = true, radius = 16, timeout = 10 })
      try(move, { 977, 1072, -172 }, { direct = true, radius = 8, timeout = 5 })
      move({ 976, 1000, -216 }, { direct = true, radius = 16, timeout = 10 })
      path({ { 970, 1000, -200 }, { 888, 1010, -392 }, { 902, 1224, -392 },
             { 1177, 1224, -568 }, { 1300, 1224, -568 } }, { timeout = 60 })
      -- Crouched under the floor past both fans, down the hole and over the
      -- beams: the area graph knows the way (the crawl's trigger, just
      -- passed, lowered the block in it).
      try(pickup, { index = 87 }, { timeout = 60 })      -- the health at the hall's end
      move({ 2014, 999, -256 }, { timeout = 240 })
      -- Down through the hole at once: trading shots with the guards below
      -- from its edge only bleeds health (and a held fight there slides
      -- off it); the room's checkpoint is taken on landing, healthy. The
      -- ion blaster in hand: two guards meet the landing at close range.
      try(weapon, 2)
      move({ 1932, 1002, -528 }, { fight = false, timeout = 30 })
    end },
    { "box", checkpoint = true, function()
      -- The room with two doors: its guards, then the box at the ceiling.
      -- (Not the guards' nest to the north: it waits for the way on.)
      try(function() clear { radius = 300, timeout = 30 } end)
      shoot({ index = 383 }, { timeout = 60 })
      dk3.sidekick("all", "follow")
    end },
    { "nest", checkpoint = true, function()
      -- The second door, north: a guards' nest with a ragemaster beyond.
      -- Health first (the box opened the way to the pack by the conveyor),
      -- then open the door and hold the room while they come through it.
      -- Superfly rejoins through the opened doors, then waits in the keypad
      -- room while the nest is cleared.
      recover(0.9, 900)
      -- (The keypad room cleared first: a guard left in it meets him.)
      try(function() clear { radius = 400, timeout = 30 } end)
      dk3.sidekick("all", "follow")
      try(regroup, 250, 60)
      dk3.sidekick("all", "stay")
      move({ 1940, 1120, -528 }, { timeout = 30 })
      try(use, { index = 418 }, { timeout = 20 })
      move({ 1936, 1040, -528 }, { timeout = 20 })
      try(function() clear { radius = 450, timeout = 60 } end)
    end },
    { "ramp", checkpoint = true, function()
      -- From here on Superfly comes along and fights with the player.
      dk3.sidekick("all", "follow")
      recover(0.8, 700)
      try(pickup, { index = 22 }, { timeout = 30 })      -- the shotcycler
      try(pickup, { index = 80 }, { timeout = 30 })      -- rockets
      advance({ 2440, 1295, -499 })
      move({ 2440, 1295, -499 }, { timeout = 90 })
      try(function() clear { radius = 600, timeout = 45 } end)
    end },
    { "up", checkpoint = true, function()
      recover(0.8, 700)
      advance({ 2397, 640, -150 })
      move({ 2397, 640, -150 }, { timeout = 120 })
    end },
    { "tunnels", checkpoint = true, function()
      -- A ragemaster waits where the corridor turns west (340 health, a
      -- crushing reach): run past it into the tunnels (it is slower than a
      -- running player) rather than trade blows with it.
      recover(0.8, 700)
      move({ 2397, 473, -88 }, { fight = false, timeout = 60 })
      move({ 2031, 229, -8 }, { fight = false, timeout = 60 })
      advance({ 1713, 192, 120 })
      move({ 1713, 192, 120 }, { timeout = 120 })
    end },
    { "loop", checkpoint = true, function()
      -- The way on to the left of the intersection, south through the trash
      -- doors, the hall of guards and ragemasters, the far doors.
      recover(0.8, 700)
      -- Superfly (who has kept his health) takes the ragemasters on while the
      -- player, hurt, keeps back and helps from range.
      dk3.sidekick("all", "follow")
      try(regroup, 250, 60)
      move({ 1312, 95, 120 }, { timeout = 60 })
      try(sic, { index = 111 }, "superfly", 40)
      move({ 1312, -1300, 120 }, { timeout = 180 })
      try(function() clear { radius = 500, timeout = 45 } end)
    end },
    { "coffins", checkpoint = true, function()
      -- Up the steps (the trip there opens the blockers below) to the coffin
      -- room: its grate by the floor, the shaft, the drop and the ladder up.
      recover(0.8, 700)
      move({ 1312, -1440, 120 }, { timeout = 60 })
      move({ 1226, -1616, 192 }, { timeout = 60 })
      move({ 1092, -1559, 192 }, { timeout = 60 })
      try(shoot, { index = 94 }, { timeout = 30 })
      move({ 820, -1500, 192 }, { timeout = 60 })
      move({ 604, -1308, 128 }, { timeout = 90 })
      move({ 604, -543, 288 }, { timeout = 90 })
      try(function() clear { radius = 500, timeout = 45 } end)
    end },
    { "alley", checkpoint = true, function()
      -- Down into the alley: health and the hosportal, the grate at its end,
      -- the guards behind it; the door on the right (the button by it) opens
      -- the short way back for Superfly.
      move({ 783, -452, 128 }, { timeout = 60 })
      try(pickup, { index = 76 }, { timeout = 20 })
      try(pickup, { index = 69 }, { timeout = 20 })
      try(recharge, { index = 410 })
      try(shoot, { index = 95 }, { timeout = 30 })
      try(function() clear { radius = 500, timeout = 45 } end)
      try(use, { index = 358 }, { timeout = 30 })
    end },
    { "out", checkpoint = true, function()
      -- Superfly comes the long way round (the keypad room, the nest, the
      -- ramp, the tunnels); the juncture door shuts a few seconds after
      -- its button: press it again until he is through.
      dk3.sidekick("all", "follow")
      for _ = 1, 40 do
        if try(regroup, 300, 6) then break end
        try(use, { index = 358 }, { timeout = 10 })
      end
      exit("e1m4c")
    end },
  }(visit, resumed)
end)

-- Crematorium, part 3: through the halls to the small study; the vent above
-- its bookcase (reached from the table by the sign and the lamp on the west
-- wall) runs over the room below, and dropping through the grate in its
-- floor opens the doors on the way to the incinerator and the lift down.
level("e1m4c", function(visit, resumed)
  if visit > 1 then return exit "e1m5a" end
  return stages {
    { "halls", function()
      dk3.sidekick("all", "follow")
      advance({ -800, 2000, 24 })
      move({ -800, 2000, 24 }, { timeout = 240 })
      try(function() clear { radius = 500, timeout = 60 } end)
    end },
    { "study", checkpoint = true, function()
      -- Superfly cannot climb after the player: he waits here and comes
      -- round by the doors the drop opens.
      try(function() clear { radius = 500, timeout = 45 } end)
      dk3.sidekick("all", "stay")
      try(shoot, { index = 69 }, { timeout = 30 })
      -- Table, sign, lamp, bookcase: the last two are narrow ledges a
      -- running jump carries the player past, so those are short hops.
      -- A fall puts the player back on the floor: climb again.
      for _ = 1, 3 do
        move({ -806, 1775, 24 }, { timeout = 60 })
        try(leap, { -812, 1775, 24 }, { -850, 1775, 54 })
        try(leap, { -852, 1790, 54 }, { -860, 1820, 96 })
        try(leap, { -860, 1840, 96 }, { -860, 1880, 128 }, { pace = 0.25 })
        try(leap, { -862, 1886, 128 }, { -860, 1950, 152 }, { pace = 0.25 })
        local _, _, z = dk3.position()
        if z > 140 then break end
      end
      move({ -858, 2060, 152 }, { direct = true, radius = 24, timeout = 10 })
      move({ -915, 2080, 168 }, { direct = true, radius = 24, timeout = 10 })
    end },
    { "vent", function()
      -- Up the vent and round to the grate in its floor over the room
      -- below (no checkpoint up here: healing would go back down).
      move({ -576, 2430, 328 }, { timeout = 90 })
      shoot({ index = 70 }, { timeout = 30, weapon = 2 })
      move({ -576, 2368, 40 }, { direct = true, timeout = 30 })
      try(function() clear { radius = 500, timeout = 60 } end)
    end },
    { "out", checkpoint = true, function()
      dk3.sidekick("all", "follow")
      try(regroup, 250, 120)
      progress("e1m5a")
    end },
  }(visit, resumed)
end)

-- Processing, part 1: the hall west of the locked door, the windows over
-- the pool, the rocks and the tunnel to the flooded room under the far side
-- of the door; its ladder, the loop round the shaft and the ladder up through
-- the grate behind the door. The control box over it removes the plates that
-- keep the door shut, and Superfly comes through.
level("e1m5a", function(visit, resumed)
  if visit > 1 then return exit "e1m5b" end
  return stages {
    { "hall", function()
      -- (Nothing is cleared here: what is heard beyond the locked door is
      -- out of reach, and chasing it ends in a niche off the floor.)
      dk3.sidekick("all", "follow")
      -- The first room's ammunition (ion packs, shells, rockets in its far
      -- corner) and station: the pool and the shafts after it have little.
      for _, item in ipairs({ 83, 2, 84 }) do try(pickup, { index = item }, { timeout = 30 }) end
      recover(0.9, 900)
      -- The hall up the stairs is held by a deathsphere, a venomvermin and
      -- two laser turrets: stop and fight each as it shows.
      move({ -1192, 2270, -816 }, { timeout = 240, cautious = true })
      tend(800, 0.8)
    end },
    { "pool", checkpoint = true, function()
      -- The door will not open from here: Superfly waits in the hall.
      -- The window's east end, away from Superfly: a rocket's splash.
      dk3.sidekick("all", "stay")
      shoot({ index = 111 }, { timeout = 30, around = { -990, 2340, -752 } })
      move({ -1177, 2471, -1160 }, { timeout = 60 })
    end },
    { "tunnel", checkpoint = true, function()
      -- Out of the water (what swims here is fought from the rocks), up the
      -- rocks to the last before the gap over the waterfall's pool, a
      -- running jump across it, and a short hop from the far rock's south
      -- end into the pipe's mouth across a narrow channel. A miss lands in
      -- the water, whence the only way back is round the rocks again.
      local function across()
        move({ -700, 2930, -1020 }, { timeout = 120 })
        try(function() clear { radius = 500, timeout = 30 } end)
        -- Still, on the jump's line, before the run-up (momentum from the
        -- climb carries the player off the rock's east edge); off the flat
        -- before the rock's lip (running down it leaves the ground before
        -- any jump), to the far rock's tip.
        move({ -622, 2930, -1020 }, { direct = true, radius = 8, timeout = 15 })
        wait(0.5)
        if not try(leap, { -618, 2868, -1036 }, { -572, 2672, -1040 }) then return false end
        move({ -566, 2534, -1040 }, { direct = true, radius = 12, timeout = 10 })
        move({ -600, 2575, -1052 }, { direct = true, radius = 8, timeout = 10 })
        wait(0.3)
        -- Slowly: a full jump's head meets the pipe's upper lip; at this
        -- pace it tops out over the channel and is below the lip by the
        -- mouth.
        return try(leap, { -600, 2530, -1052 }, { -604, 2436, -1048 }, { pace = 0.4 })
      end
      local inside = false
      for _ = 1, 4 do
        if across() then inside = true break end
      end
      if not inside then error(dk3.where() .. ": tunnel: the pipe's mouth was never reached", 0) end
      -- Its mouth lowers the door on the shaft above the flooded room the
      -- pipe leads to.
      move({ -612, 2300, -1048 }, { direct = true, crouch = true, radius = 16, timeout = 20 })
      try(function() clear { radius = 500, timeout = 45 } end)
      -- The room's health and rockets: the hall behind the locked door is
      -- under a turret, a deathsphere and a guard when the player comes up.
      try(pickup, { index = 72 }, { timeout = 20 })
      try(pickup, { index = 73 }, { timeout = 20 })
      -- Up the ladder in its east corner to the ledge by that door (the
      -- area graph has only the way down). Climbing never settles: timed.
      move({ -544, 2205, -1064 }, { direct = true, radius = 16, timeout = 20 })
      try(move, { -544, 2205, -900 }, { direct = true, radius = 8, timeout = 6 })
      move({ -530, 2184, -928 }, { direct = true, radius = 24, timeout = 10 })
    end },
    { "shaft", checkpoint = true, function()
      -- Round the loop to the ladder under the grate behind the locked door:
      -- east through the lowered door, south, west and north again (from
      -- the ledge itself the area graph finds no way).
      path({ { -500, 2184, -928 }, { -290, 2184, -928 }, { -290, 1937, -928 },
             { -704, 1937, -928 }, { -699, 2180, -928 } }, { direct = true, radius = 24, timeout = 40 })
      try(kill, { index = 70 }, { timeout = 20 })       -- the venomvermin at its foot
      -- Right under the grate (from the shaft's edge it is out of sight).
      move({ -699, 2228, -928 }, { direct = true, radius = 8, timeout = 10 })
      shoot({ index = 112 }, { timeout = 30, hold = true })
      -- The hall's deathsphere comes over the opened grate: fought from down
      -- here, out of the hall turret's sight (up there it and the turret
      -- together take most of the player's health in two seconds).
      try(kill, { index = 92 }, { hold = true, timeout = 25 })
      -- Up the ladder on the shaft's west wall without firing: bolts loosed
      -- up the narrow shaft ricochet back down it. Out into the hall above,
      -- then fight.
      try(move, { -716, 2228, -808 }, { direct = true, radius = 12, timeout = 8, fight = false })
      move({ -745, 2228, -816 }, { direct = true, radius = 16, timeout = 10, fight = false })
      -- At once (the hall's guard and the turret high on its south wall are
      -- on the way): the control box over the door, whose wires hold its
      -- plates shut, and the door; back through it to Superfly, and the
      -- guard is fought there by both.
      shoot({ index = 325 }, { timeout = 30, fight = false })
      -- The door opens to touch now: straight through it.
      move({ -840, 2228, -816 }, { direct = true, radius = 24, timeout = 10, fight = false })
      dk3.sidekick("all", "follow")
      try(function() clear { radius = 500, timeout = 45 } end)
    end },
    { "door", checkpoint = true, function()
      -- East along the hall with Superfly (its choppers, guards, a
      -- venomvermin), fighting as each shows, to the station by its far door.
      dk3.sidekick("all", "follow")
      try(regroup, 250, 90)
      move({ 200, 2248, -816 }, { timeout = 240, cautious = true })
      try(recharge, { index = 91 })
      tend(800, 0.8)
    end },
    { "out", checkpoint = true, function()
      -- On past the fan and the guards to the Mishima door (the exit), a
      -- leg at a time, back to the station between legs while it has
      -- charge: part 2 opens on a guard, a turret and deathspheres with
      -- no health before the stairs down, so arrive whole.
      dk3.sidekick("all", "follow")
      for _, point in ipairs({ { 240, 1700, -760 }, { 330, 1596, -816 }, { 968, 1560, -816 }, { 968, 1420, -752 } }) do
        move(point, { timeout = 180, cautious = true })
        recover(0.95, 1300)
      end
      progress("e1m5b")
    end },
  }(visit, resumed)
end)

-- Processing, part 2: the catwalk and its turret, the spiral stairs down,
-- the rooms south and west to the stairs up to the console that unlocks the
-- freezer door; back to the freezer and on to the Mishima logo (the exit).
-- Deathspheres hold most rooms: each leg is fought cautiously, with the
-- stations at the bottom of the stairs and by the south room's stairs.
level("e1m5b", function(visit, resumed)
  if visit > 1 then return exit "e1m6a" end
  return stages {
    { "catwalk", function()
      -- Hold the arrival corridor first: its guard, the catwalk's
      -- deathspheres and a venomvermin come to it one by one (chased, they
      -- are met all at once with the turret at the catwalk's end).
      dk3.sidekick("all", "follow")
      try(function() clear { radius = 900, hold = true, timeout = 15, arena = { { 1220, 1300 }, { 1300, 1445 } } } end)
      -- The corridor's door opens to use only.
      try(use, { index = 30 }, { timeout = 15 })
      for _, item in ipairs({ 91, 92 }) do try(pickup, { index = item }, { timeout = 20, fight = false }) end
      move({ 1460, 1887, -608 }, { timeout = 120, cautious = true })
      try(kill, { index = 45 }, { hold = true, timeout = 30 })   -- the catwalk's turret
      -- The two deathspheres by the catwalk's far door: Superfly's
      -- shotcycler takes them on while the player holds mid-catwalk and
      -- shoots what comes into sight.
      for _, sphere in ipairs({ 361, 78 }) do
        for _ = 1, 3 do
          if try(sic, { index = sphere }, "superfly", 20) then break end
          wait(1)
        end
        try(kill, { index = sphere }, { hold = true, timeout = 20 })
      end
      move({ 1949, 1952, -648 }, { timeout = 120, cautious = true })
    end },
    { "spiral", checkpoint = true, function()
      dk3.sidekick("all", "follow")
      move({ 2228, 1785, -896 }, { timeout = 180, cautious = true })
      try(recharge, { index = 104 })
      try(pickup, { index = 103 }, { timeout = 20 })
      tend(800, 0.8)
    end },
    { "south", checkpoint = true, function()
      dk3.sidekick("all", "follow")
      move({ 2304, 1300, -896 }, { timeout = 120, cautious = true })
      try(pickup, { index = 87 }, { timeout = 20 })
      move({ 2281, 623, -896 }, { timeout = 180, cautious = true })
      try(recharge, { index = 75 })
      tend(800, 0.8)
    end },
    { "console", checkpoint = true, function()
      -- West through the side door, up the stairs north to the hall over
      -- the console room, down into it.
      dk3.sidekick("all", "follow")
      move({ 1920, 536, -896 }, { timeout = 120, cautious = true })
      move({ 1760, 862, -896 }, { timeout = 120, cautious = true })
      -- Up the steps west (door slabs a button lowers into a secret: on
      -- them the area graph places the player in the vent below).
      -- North along the corridor over the secret vent (above it the area
      -- graph places the player in the vent too) to past its end.
      path({ { 1640, 850, -840 }, { 1563, 945, -826 }, { 1620, 955, -808 }, { 1632, 1185, -808 } },
           { direct = true, radius = 24, timeout = 15 })
      move({ 1644, 1388, -808 }, { timeout = 180, cautious = true })
      -- Two deathspheres and a venomvermin hold the room below the ledge
      -- (two deathspheres' volleys together take a full health in a
      -- second): show at the ledge, fall back down the corridor and fight
      -- them there as they come through it one by one.
      move({ 1640, 1560, -800 }, { direct = true, radius = 16, timeout = 10 })
      for _ = 1, 4 do
        if dk3.hostiles(500, { 1640, 1750, -850 }) == 0 then break end
        try(use, { index = 26 }, { timeout = 8 })
        try(function()
          kill({ class = "monster_deathsphere" }, { around = { 1640, 1750, -850 }, radius = 500, hold = true, timeout = 20,
                 arena = { { 1612, 1530 }, { 1668, 1590 } } })
        end)
        try(function()
          kill({ class = "monster_venomvermin" }, { around = { 1640, 1750, -850 }, radius = 500, hold = true, timeout = 15,
                 arena = { { 1612, 1530 }, { 1668, 1590 } } })
        end)
      end
      -- Down the door-slab steps into the cleared room, the health in the
      -- passage east of it, and across to the console.
      try(use, { index = 26 }, { timeout = 8 })
      path({ { 1640, 1655, -812 }, { 1640, 1730, -848 } }, { direct = true, radius = 24, timeout = 10, fight = false })
      try(pickup, { index = 363 }, { timeout = 40 })
      move({ 1340, 1640, -832 }, { timeout = 60 })
      use({ index = 168 }, { timeout = 60 })
      cinematic()
    end },
    { "soul", checkpoint = true, function()
      -- Back the way the route came (the steps by the vent walked
      -- straight) and east to the stairs short of the freezer: the golden
      -- soul in the secret under their landing, off its edge at a walk
      -- into the slot beneath it.
      dk3.sidekick("all", "follow")
      try(regroup, 300, 60)
      move({ 1632, 1185, -808 }, { timeout = 120, cautious = true })
      path({ { 1620, 955, -808 }, { 1563, 945, -826 }, { 1640, 850, -840 }, { 1760, 862, -896 } },
           { direct = true, radius = 24, timeout = 15 })
      move({ 2342, 336, -808 }, { timeout = 120, cautious = true })
      move({ 2323, 352, -820 }, { direct = true, radius = 4, timeout = 10 })
      move({ 2325, 372, -896 }, { direct = true, radius = 10, timeout = 10, pace = 0.3 })
      path({ { 2327, 330, -896 }, { 2327, 292, -896 }, { 2260, 296, -896 } }, { direct = true, radius = 12, timeout = 10 })
      path({ { 2327, 292, -896 }, { 2331, 360, -896 } }, { direct = true, radius = 12, timeout = 10 })
    end },
    { "freezer", checkpoint = true, function()
      -- The freezer the console unlocked: its inner door opens to use. The
      -- deathsphere over its far side comes to the doorway and is met from
      -- the stair landing (not backed off it: its side drops into a corner
      -- nothing leads out of), where the open door's edge keeps the
      -- lasergat hung mid-room from a clear shot either way; then the
      -- lasergat from just inside, where its lane is clear.
      dk3.sidekick("all", "follow")
      local landing = { { 2645, 380 }, { 2695, 420 } }
      move({ 2669, 416, -740 }, { timeout = 120, cautious = true })
      for _ = 1, 3 do
        try(use, { index = 25 }, { timeout = 8 })
        if try(kill, { index = 364 }, { hold = true, timeout = 20, arena = landing }) then break end
      end
      tend(800, 0.6)
      for _ = 1, 3 do
        try(use, { index = 25 }, { timeout = 8 })
        move({ 2730, 415, -744 }, { direct = true, radius = 12, timeout = 5 })
        if try(kill, { index = 44 }, { hold = true, timeout = 20, arena = { { 2712, 392 }, { 2770, 440 } } }) then break end
      end
      recover(0.9, 600)
      move({ 2669, 416, -740 }, { timeout = 60, cautious = true })
      try(use, { index = 25 }, { timeout = 8 })
      try(function() clear { radius = 700, hold = true, timeout = 30, arena = landing } end)
      try(pickup, { index = 74 }, { timeout = 30 })   -- the shockwave
    end },
    { "hall", checkpoint = true, function()
      -- South up the freezer's ramp, through the guards' rooms to the use
      -- door into the great hall under the exit. What comes to the doorway
      -- is met there; the rest of the hall (its two deathspheres, the
      -- lasergat on the central pillar, the guard on the floor) mostly
      -- stays put and is hunted one by one, with the health on its floor
      -- between; then up round the walkways to the exit door (the armour
      -- below the exit's corridor is left: the way back up from it is a
      -- ladder).
      dk3.sidekick("all", "follow")
      move({ 2368, -560, -496 }, { timeout = 180, cautious = true })
      local doorway = { { 2340, -585 }, { 2396, -540 } }
      for _ = 1, 2 do
        try(use, { index = 22 }, { timeout = 8 })
        if try(function() clear { radius = 900, hold = true, timeout = 20, arena = doorway } end) then break end
      end
      tend(900, 0.6)
      for _, foe in ipairs({ 113, 366, 46, 114 }) do
        try(kill, { index = foe }, { timeout = 30 })
        recover(0.7, 900)
      end
      for _, item in ipairs({ 70, 69 }) do try(pickup, { index = item }, { timeout = 40 }) end
      progress("e1m6a")
    end },
  }(visit, resumed)
end)

-- Icelab: the decontamination corridor's door opens a while after its
-- button; the sprays along it cycle. The four-way door at its end opens to
-- the blue control card, in the control room past the denied keypads.
-- Through the cryotechs' rooms, down into the lab over the nitrogen pool
-- (across the gap in its walkway): its valve drains the pool, whose floor
-- leads to the lift up to the exit's rooms.
level("e1m6a", function(visit, resumed)
  if visit > 1 then return exit "e1m6b" end
  return stages {
    { "lab", function()
      dk3.sidekick("all", "follow")
      recover(0.8, 900)
      use { index = 64 }
      wait(11)
      pickup { index = 2 }
      try(recharge, { index = 29 })   -- the station in the card's room
      use { index = 85 }
    end },
    { "valve", checkpoint = true, function()
      -- The lab's cryotechs spray a freezing fluid at close range. Down the
      -- ladder shaft (the room's way down) to its foot, a floor cut off
      -- from the rest by a gap over the nitrogen: what shows across it is
      -- shot from well back off its edge. Then a running leap over the gap
      -- (the area graph's jump falls short) and the rest held off there.
      dk3.sidekick("all", "follow")
      move({ 1455, 250, -24 }, { timeout = 180, cautious = true })
      move({ 1574, 305, -24 }, { timeout = 30, radius = 16 })
      move({ 1590, 345, -240 }, { direct = true, radius = 24, timeout = 10 })
      move({ 1600, 300, -240 }, { direct = true, radius = 16, timeout = 10 })
      try(function() kill({ class = "monster_cryotech" }, { around = { 1450, 470, -248 }, radius = 450, hold = true, timeout = 15,
                              arena = { { 1580, 230 }, { 1615, 345 } } }) end)
      move({ 1600, 220, -240 }, { direct = true, radius = 16, timeout = 10 })
      for _ = 1, 3 do
        if x() < 1440 then break end
        try(leap, { 1548, 220, -240 }, { 1385, 220, -240 })
      end
      -- North along the west floor, clear of the gap's edge.
      path({ { 1350, 225, -240 }, { 1340, 300, -248 }, { 1340, 407, -248 } }, { direct = true, radius = 20, timeout = 10 })
      -- (Ones not yet roused are not counted hostile: each by name.)
      for _, foe in ipairs({ 7, 104, 6, 8, 351, 352 }) do
        try(kill, { index = foe }, { hold = true, timeout = 15, arena = { { 1320, 380 }, { 1370, 430 } } })
        try(kill, { index = foe }, { timeout = 15 })
      end
      move({ 1380, 560, -248 }, { timeout = 60 })
      try(pickup, { index = 23 }, { timeout = 20 })
      use { index = 97 }
      wait(15)
      try(regroup, 250, 60)
      progress("e1m6b")
    end },
  }(visit, resumed)
end)

-- Icelab, part 2: the door on along the walkway opens only from beyond it.
-- The way there is a running drop off the walkway's end onto the round
-- platform standing in the nitrogen, its ladder, and the hatch at the top;
-- the button there opens the door. Superfly waits at the drop (a sidekick
-- following falls short into the nitrogen) and comes through the door.
level("e1m6b", function(visit, resumed)
  if visit > 1 then return exit "e1m6c" end
  return stages {
    { "shield", function()
      -- The megashield at the far end of a pipe over the nitrogen, by the
      -- ladder down from the alcove off the walkway: fetched while
      -- Superfly waits on the walkway.
      dk3.sidekick("all", "follow")
      move({ 1650, -1040, 40 }, { timeout = 120, cautious = true })
      dk3.sidekick("all", "stay")
      try(pickup, { index = 13 }, { timeout = 120 })
      move({ 1650, -1040, 40 }, { timeout = 120 })
    end },
    { "ramp", checkpoint = true, function()
      -- The console by the door on along the walkway opens the door up the
      -- ramp (and lets two deathspheres out of hatches by it): Superfly's
      -- way round to the far side, kept open.
      dk3.sidekick("all", "stay")
      use { index = 70 }
      -- (Held well back on the walkway: its edges drop to the nitrogen.)
      move({ 1630, -900, 40 }, { timeout = 30, radius = 24 })
      for _, foe in ipairs({ 98, 149 }) do
        try(kill, { index = foe }, { hold = true, timeout = 20, arena = { { 1600, -1000 }, { 1660, -760 } } })
      end
      tend(900, 0.6)
    end },
    { "platform", checkpoint = true, function()
      -- Alone over the platform in the nitrogen: a running drop off the
      -- walkway's end, the ladder, the hatch, the guards in the room above
      -- it, its lift up, and those on the floor at the top; then Superfly
      -- comes round through the ramp door (the door from the walkway to
      -- the hatch room shuts again a moment after its button).
      move({ 1650, -1040, 40 }, { timeout = 120, cautious = true })
      dk3.sidekick("all", "stay")
      move({ 1672, -1060, 40 }, { direct = true, radius = 8, timeout = 10 })
      move({ 1912, -1185, -256 }, { direct = true, radius = 40, timeout = 10, fight = false })
      -- Up the ladder to the hatch over it, opened by hand from the rungs.
      try(move, { 1920, -1150, 38 }, { direct = true, radius = 12, timeout = 8 })
      for _ = 1, 3 do
        if opened(24)() or opened(22)() then break end
        try(use, { index = 24 }, { timeout = 6 })
        try(use, { index = 22 }, { timeout = 6 })
      end
      for _, foe in ipairs({ 275, 274, 60 }) do try(kill, { index = foe }, { timeout = 20 }) end
      move({ 1912, -1393, 248 }, { timeout = 60 })
      for _, foe in ipairs({ 10, 59, 276, 317 }) do try(kill, { index = foe }, { timeout = 25 }) end
      recover(0.8, 600)
      dk3.sidekick("all", "follow")
      try(regroup, 250, 120)
      tend(900, 0.6)
    end },
    -- The long way round to the exit, in legs: east along the gallery and
    -- south, the loop of halls west, the rooms on west to the drop to the
    -- floor below, and north over it to the exit.
    { "east", checkpoint = true, function()
      dk3.sidekick("all", "follow")
      move({ 2383, -1104, 344 }, { timeout = 120, cautious = true })
      move({ 2383, -1900, 344 }, { timeout = 120, cautious = true })
      recover(0.8, 900)
      tend(900, 0.6)
    end },
    { "loop", checkpoint = true, function()
      dk3.sidekick("all", "follow")
      move({ 1504, -1969, 344 }, { timeout = 120, cautious = true })
      move({ 1472, -2600, 392 }, { timeout = 120, cautious = true })
      move({ 1284, -2863, 376 }, { timeout = 120, cautious = true })
      move({ 1252, -2111, 344 }, { timeout = 120, cautious = true })
      recover(0.8, 900)
      tend(900, 0.6)
    end },
    { "west", checkpoint = true, function()
      dk3.sidekick("all", "follow")
      move({ 1121, -2127, 344 }, { timeout = 120, cautious = true })
      move({ -15, -2399, 344 }, { timeout = 120, cautious = true })
      move({ 79, -1747, 344 }, { timeout = 120, cautious = true })
      recover(0.8, 900)
      tend(900, 0.6)
    end },
    { "lower", checkpoint = true, function()
      -- The floor below is held by guards and cryotechs: Superfly waits
      -- while the bot goes down and clears it, then comes after.
      dk3.sidekick("all", "stay")
      for _, foe in ipairs({ 318, 144, 101, 50, 49, 48 }) do try(kill, { index = foe }, { timeout = 30 }) end
      recover(0.8, 900)
      resupply(30, 900)
      dk3.sidekick("all", "follow")
      move({ 352, -1599, -48 }, { timeout = 120 })
      try(regroup, 250, 120)
      move({ 352, -1183, 16 }, { timeout = 120, cautious = true })
      recover(0.8, 900)
      progress("e1m6c")
    end },
  }(visit, resumed)
end)

-- Icelab, part 3: the room past the first door holds two inmaters, a
-- ragemaster on the catwalk and a deathsphere overhead. The shockwave is
-- fired in from the doorway (the bot backs out of its rings), the rest held
-- off from the door while Superfly waits behind.
level("e1m6c", function(visit, resumed)
  if visit > 1 then return exit "e1m7a" end
  return stages {
    { "arena", function()
      dk3.sidekick("all", "stay")
      try(use, { index = 59 }, { timeout = 10 })
      try(use, { index = 61 }, { timeout = 10 })
      -- They keep to their beat on the catwalk: hunted one by one, met at
      -- range (the brutes hit hard up close) with Superfly kept back.
      for _ = 1, 2 do
        for _, foe in ipairs({ 172, 21, 32 }) do try(kill, { index = foe }, { timeout = 30 }) end
      end
      -- The deathsphere over the ring is awaited at the catwalk's near end:
      -- chased, it leads off the catwalk into the nitrogen under the ring.
      move({ 352, -90, 200 }, { timeout = 30, radius = 24 })
      try(kill, { index = 31 }, { hold = true, timeout = 30, arena = { { 320, -110 }, { 400, -60 } } })
      recover(0.8, 900)
    end },
    { "doors", checkpoint = true, function()
      -- Round the ring to the buttons of the doors on (not the chromatic
      -- armour on the catwalk's far side: the way to it drops into the
      -- nitrogen).
      dk3.sidekick("all", "follow")
      try(regroup, 250, 60)
      use { index = 125 }
      try(use, { index = 44 }, { timeout = 30 })
      tend(900, 0.6)
    end },
    { "west", checkpoint = true, function()
      -- The catwalks and rooms west (a battle boar, an inmater, cryotechs,
      -- guards, deathspheres) over the nitrogen, while Superfly waits. The
      -- battle boar charges and knocks a player off the narrow catwalk: it
      -- and the inmater are let come to the floor by the buttons.
      dk3.sidekick("all", "stay")
      for _, foe in ipairs({ 190, 20 }) do try(kill, { index = foe }, { hold = true, timeout = 30, arena = { { 150, 1330 }, { 260, 1420 } } }) end
      for _, foe in ipairs({ 190, 20, 58, 28 }) do
        try(kill, { index = foe }, { timeout = 40 })
        if dk3.health() < 50 then recover(0.8, 900) end
      end
      recover(0.8, 900)
    end },
    { "far west", checkpoint = true, function()
      dk3.sidekick("all", "stay")
      -- Deathspheres come to the bot; the cryotechs are met from range.
      for _, foe in ipairs({ 14, 187 }) do try(kill, { index = foe }, { hold = true, timeout = 25 }) end
      for _, foe in ipairs({ 54, 57, 29, 14, 187 }) do
        try(kill, { index = foe }, { timeout = 40 })
        if dk3.health() < 50 then recover(0.8, 900) end
      end
      recover(0.8, 900)
      dk3.sidekick("all", "follow")
      try(regroup, 250, 120)
    end },
    { "prison", checkpoint = true, function()
      -- Up the platforms to the inmaters by the door to Mikiko's prison.
      dk3.sidekick("all", "stay")
      for _, foe in ipairs({ 192, 173, 19 }) do try(kill, { index = foe }, { timeout = 40 }) end
      recover(0.8, 900)
      dk3.sidekick("all", "follow")
      try(regroup, 250, 120)
      -- The doors open to a trigger before them; the exit is the line just
      -- past them (the area graph ends at the grate beyond it).
      try(touch, { index = 25 }, { timeout = 60 })
      move({ -300, 485, 472 }, { timeout = 30 })
      exit "e1m7a"
    end },
  }(visit, resumed)
end)

-- The vault: up the stairs, through the big doors, the halls of the trap
-- and the ladder; the diagonal door below the cage lift opens only from
-- beyond. The cage lift rises to the keypad cage (its lock shot away): the
-- keypad opens the doors to beyond for a while, reached by jumping off the
-- catwalk; there the keypad by the diagonal door lets the sidekicks in.
level("e1m7a", function(visit, resumed)
  if visit > 1 then return exit "e1m7b" end
  return stages {
    { "halls", function()
      dk3.sidekick("all", "follow")
      -- The golden soul and the plasteel armour by the start, past the
      -- start room's door.
      try(use, { index = 568 }, { timeout = 20 })
      for _, item in ipairs({ 80, 609, 88, 83 }) do
        if dk3.reachable({ index = item }) then try(pickup, { index = item }, { timeout = 30 }) end
      end
      advance({ 300, -2300, 338 })
      move({ 300, -2300, 338 }, { timeout = 120, cautious = true })
      -- The deathsphere hovering over the floor above sees down the trap's
      -- corridor: met from its east end first.
      try(kill, { index = 109 }, { hold = true, timeout = 15 })
      -- Along the walkway and off its end to the floor below (the area
      -- graph waits there for the corner lift, which no one calls).
      move({ 25, -2276, 344 }, { timeout = 60 })
      move({ -60, -2150, 216 }, { direct = true, radius = 24, timeout = 10 })
      advance({ -337, -2103, 216 })
      move({ -300, -2110, 216 }, { timeout = 120, cautious = true })
    end },
    { "ladder", checkpoint = true, function()
      -- The keypad by the far end slides a ladder's rungs out of the wall:
      -- up it alone (the sidekicks have no way up a ladder the area graph
      -- never had), the guards on the floor above, the cage lift down to
      -- the far side of the diagonal door, which its keypad opens for them.
      dk3.sidekick("all", "stay")
      -- (Pressed from a stride back: from right against it a press fails.)
      move({ -20, -2104, 216 }, { timeout = 60, radius = 8 })
      look(0, 0)
      for _ = 1, 3 do
        if opened(122)() then break end
        try(use, { index = 118 }, { timeout = 8 })
        wait(1)
      end
      expect(opened(122)(), "the ladder's rungs did not come out")
      wait(3)
      -- The corner lift up to the narrow walkway along the walls (the area
      -- graph has no way along it), round to the ladder's foot.
      ride { index = 7 }
      path({ { -15, -2300, 344 }, { -12, -2040, 344 }, { -150, -2012, 344 }, { -268, -2012, 344 } },
           { direct = true, radius = 12, timeout = 10, fight = false })
      move({ -272, -2012, 470 }, { direct = true, radius = 16, timeout = 15 })
      move({ -240, -2100, 486 }, { direct = true, radius = 24, timeout = 10 })
      -- West along the corridor to the cage lift's top (the area graph has
      -- the shaft's way through the diagonal door below).
      -- (Held: hunted, a guard leads off the floor's edge to the floor below.)
      local block = { { -268, -2255 }, { -222, -2080 } }
      for _, foe in ipairs({ 108, 583 }) do try(kill, { index = foe }, { hold = true, timeout = 15, arena = block }) end
      move({ -600, -2190, 486 }, { timeout = 60 })
      local corridor = { { -620, -2200 }, { -540, -2165 } }
      for _, foe in ipairs({ 108, 583 }) do try(kill, { index = foe }, { hold = true, timeout = 15, arena = corridor }) end
      ride { index = 148 }
      use { index = 732 }
      dk3.sidekick("all", "follow")
      try(regroup, 250, 90)
    end },
    { "cage", checkpoint = true, function()
      -- Back up alone: the cage's lock shot away, its keypad opens the
      -- doors below for a while; off the corridor's edge to them, the
      -- ragemaster and guards beyond, and their keypad lets the sidekicks in.
      dk3.sidekick("all", "stay")
      ride { index = 148 }
      -- The cage's lock is a wire at the corridor's far end, with a worker
      -- sat in front of it.
      try(kill, { index = 603 }, { timeout = 20 })
      try(shoot, { index = 53 }, { timeout = 30 })
      use { index = 612 }
      -- Out of the cage, off the corridor's north edge to the floor below
      -- and through the doors before they shut (10 s).
      path({ { -660, -2160, 480 }, { -620, -2080, 216 }, { -605, -1960, 216 }, { -605, -1880, 216 } },
           { direct = true, radius = 24, timeout = 6, fight = false })
      try(function() clear { radius = 700, timeout = 60 } end)
      use { index = 610 }
    end },
    { "pipe", checkpoint = true, function()
      -- The door across the catwalk is dead: down off the catwalk to the
      -- channels below it, the keypad that opens the round hatch in their
      -- floor, and the flooded pipe under it to the grate at its far end
      -- (alone: the sidekicks wait).
      dk3.sidekick("all", "stay")
      move({ -700, -1390, 96 }, { timeout = 60 })
      use { index = 208 }
      move({ -230, -1440, -30 }, { timeout = 60 })
      try(shoot, { index = 211 }, { timeout = 20 })
      -- Up the ramp past the save gem: the fan's mechanism, shot from in
      -- front of it, stops the fan, and the way drops past it.
      move({ 300, -880, 216 }, { timeout = 60, cautious = true })
      try(shoot, { index = 436 }, { timeout = 20 })
      -- Into the duct behind it (its floor a hop up, its roof low: ducked)
      -- and down out of its far end into the hallway.
      -- (A hop up into it, timed: the lip is a jump up, the roof low.)
      for _ = 1, 4 do
        if x() < 240 then break end
        try(move, { 300, -800, 216 }, { direct = true, radius = 12, timeout = 5 })
        try(move, { 270, -800, 250 }, { direct = true, radius = 12, timeout = 5, crouch = true })
        jump()
        try(move, { 180, -800, 250 }, { direct = true, radius = 16, timeout = 8, crouch = true })
      end
      expect(x() < 240, "not into the duct behind the fan")
      move({ 170, -800, 88 }, { direct = true, radius = 24, timeout = 8 })   -- down its shaft
    end },
    { "hatch", checkpoint = true, function()
      -- West along the hallway (its guards on the way) to the ladder at its
      -- end and the hatch at the ladder's top, opened by hand.
      path({ { 0, -780, 88 }, { -500, -780, 88 }, { -864, -790, 88 } }, { direct = true, radius = 24, timeout = 20 })
      move({ -864, -872, 88 }, { direct = true, radius = 12, timeout = 10 })
      try(move, { -864, -880, 200 }, { direct = true, radius = 16, timeout = 8 })
      local hx, hy, hz = dk3.position()
      dk3.log(string.format("ladder top at %.0f,%.0f,%.0f hatch=%s", hx, hy, hz, tostring(dk3.mover({ index = 76 }))))
      try(use, { index = 76 }, { timeout = 10 })
      dk3.log("hatch after use: " .. tostring(dk3.mover({ index = 76 })))
      progress("e1m7b")
    end },
  }(visit, resumed)
end)

local chain = {
  "e1m2a", "e1m2b", "e1m3a", "e1m3b", "e1m4a", "e1m4b", "e1m4c",
  "e1m5a", "e1m5b", "e1m6a", "e1m6b", "e1m6c", "e1m7a", "e1m7b", "e2m1a",
}
-- Maps without an authored route yet: head for the forward exit, operating
-- reachable controls when the area graph has no route (see advance()).
for index = 14, #chain - 1 do
  local map, destination = chain[index], chain[index + 1]
  level(map, function() progress(destination) end)
end
