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
      -- The first room's station, health and ammunition: the pool and the
      -- shafts after it have little of either.
      recover(0.9, 900)
      resupply(40, 900)
      advance({ -1192, 2270, -816 })
      move({ -1192, 2270, -816 }, { timeout = 240 })
      tend(800, 0.8)
      recover(0.9, 900)
    end },
    { "pool", checkpoint = true, function()
      -- The door will not open from here: Superfly waits in the hall.
      -- The window's east end, away from Superfly: a rocket's splash.
      dk3.sidekick("all", "stay")
      shoot({ index = 111 }, { timeout = 30, around = { -990, 2340, -752 } })
      move({ -1177, 2471, -1160 }, { timeout = 60 })
      -- Out of the water at once (what swims here is fought from the rocks):
      -- up the rocks to the last before the gap over the waterfall's pool,
      -- a running jump across it, and on to the tunnel's mouth.
      move({ -700, 2930, -1020 }, { timeout = 90 })
      try(function() clear { radius = 500, timeout = 30 } end)
      move({ -640, 2900, -1030 }, { timeout = 30 })
      leap({ -616, 2842, -1041 }, { -595, 2700, -1060 })
    end },
    { "tunnel", checkpoint = true, function()
      -- Through the tunnel; its mouth lowers the door on the shaft above
      -- the flooded room it leads to.
      move({ -616, 2444, -1024 }, { timeout = 120 })
      move({ -599, 2279, -1072 }, { crouch = true, timeout = 60 })
      try(function() clear { radius = 500, timeout = 45 } end)
      -- Up the ladder in its east corner to the ledge by that door (the
      -- area graph has only the way down). Climbing never settles: timed.
      move({ -544, 2205, -1064 }, { direct = true, radius = 16, timeout = 20 })
      try(move, { -544, 2205, -900 }, { direct = true, radius = 8, timeout = 6 })
      move({ -530, 2184, -928 }, { direct = true, radius = 24, timeout = 10 })
    end },
    { "shaft", checkpoint = true, function()
      -- Round the loop to the ladder under the grate behind the locked door.
      move({ -699, 2190, -928 }, { timeout = 120 })
      try(function() clear { radius = 500, timeout = 45 } end)
      shoot({ index = 112 }, { timeout = 30 })
      try(move, { -704, 2228, -808 }, { direct = true, radius = 16, timeout = 8 })
      move({ -720, 2228, -816 }, { timeout = 20 })
    end },
    { "door", checkpoint = true, function()
      -- The control box over the door: its wires hold the plates shut.
      shoot({ index = 325 }, { timeout = 30 })
      try(use, { index = 48 }, { timeout = 20 })
      dk3.sidekick("all", "follow")
      try(regroup, 250, 90)
      progress("e1m5b")
    end },
  }(visit, resumed)
end)

local chain = {
  "e1m2a", "e1m2b", "e1m3a", "e1m3b", "e1m4a", "e1m4b", "e1m4c",
  "e1m5a", "e1m5b", "e1m6a", "e1m6b", "e1m6c", "e1m7a", "e1m7b", "e2m1a",
}
-- Maps without an authored route yet: head for the forward exit, operating
-- reachable controls when the area graph has no route (see advance()).
for index = 9, #chain - 1 do
  local map, destination = chain[index], chain[index + 1]
  level(map, function() progress(destination) end)
end
