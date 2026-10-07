-- SPDX-License-Identifier: GPL-2.0-or-later
-- dk3 co-op bot route language. A route script registers one body per map with
-- `level`. Every action yields to the native driver, which performs it through
-- ordinary player commands (movement, view, attack, use) until it completes.
-- Failures raise Lua errors that carry the script line of the failed action.
local yield = coroutine.yield
local levels = {}
-- deaths: run-wide cap (0 = none); level_deaths: restorations allowed per map.
local options = { deaths = 0, level_deaths = 3, level_saves = true }

-- Health worth a checkpoint counts armor too (it soaks up much of a hit).
local function sturdy(fraction)
  local health, maximum, armor = dk3.health()
  return health + math.min(armor or 0, maximum) * 0.5 >= fraction * maximum, health, maximum
end

local function seconds(value, default)
  if value == nil then return default end
  assert(type(value) == "number" and value > 0, "timeout must be positive seconds")
  return value
end

-- Actions of a restored stage that the saved world already reflects.
local skip = 0

local function act(spec, opts)
  -- Saves are not among the actions a restored world reflects: never skipped.
  if skip > 0 and spec.op ~= "save" then
    skip = skip - 1
    dk3.skipped()
    return "skipped (restored past it)"
  end
  opts = opts or {}
  spec.timeout = seconds(opts.timeout, spec.timeout or 60)
  if opts.fight ~= nil then spec.fight = opts.fight end
  for _, key in ipairs({ "radius", "around", "class", "map", "count", "hold", "direct", "crouch", "arena", "weapon", "cautious", "blast", "pace" }) do
    if opts[key] ~= nil and spec[key] == nil then spec[key] = opts[key] end
  end
  local ok, detail = yield(spec)
  if not ok then error(dk3.where() .. ": " .. spec.op .. ": " .. tostring(detail), 0) end
  return detail
end

-- A target is a targetname string, a point {x, y, z}, or a selector table
-- {name=, class=, id=, near={x, y, z}}.
local function target(value)
  if type(value) == "string" then return { name = value } end
  if type(value) == "table" and type(value[1]) == "number" then return { point = value } end
  assert(type(value) == "table", "target must be a name, a point or a selector")
  return value
end

function level(name, body)
  assert(type(name) == "string", "level name must be a map name")
  local function register(fn)
    assert(type(fn) == "function", "level body must be a function")
    assert(levels[name] == nil, "duplicate level " .. name)
    -- Each entry (not a checkpoint resumption) is saved once the arrival scene
    -- has released control, so a failed run leaves an ordinary restart point.
    -- Like a stage checkpoint, only in good health: a badly hurt arrival
    -- (say, into a guard post) keeps the previous map's checkpoint instead.
    levels[name] = function(visit, resumed)
      if options.level_saves and not resumed then
        cinematic()
        recover(0.6)
        local healthy, health, maximum = sturdy(0.6)
        if healthy then
          save("coop-" .. name)
        else
          dk3.log(string.format("arrival save skipped: health %d of %d", health, maximum))
        end
      end
      return fn(visit, resumed)
    end
  end
  if body == nil then return register end
  register(body)
end

-- A level body may be a list of named stages: `stages { {"river", fn}, ... }`.
-- Every game save (autosave or explicit) records the running stage, and a
-- restoration from that save resumes at the start of that stage. A stage
-- marked `checkpoint = true` saves as it begins (slot coop-<map>-<index>), so
-- a death later in a long level resumes there rather than at its arrival.
function stages(list)
  return function(visit, resumed)
    local first, done = 1, 0
    if resumed then
      first, done = dk3.checkpoint_stage()
      -- A save taken before the first stage (arrival) has nothing to skip.
      if first < 1 then first, done = 1, 0 end
    end
    for index = first, #list do
      local resuming = resumed and index == first
      dk3.stage(index, list[index][1])
      -- A checkpoint is only worth having in good health: restoring a badly
      -- hurt player again and again cannot succeed. Heal from what is near;
      -- if still hurt, keep the older checkpoint.
      if list[index].checkpoint and not resuming then tend() recover(0.6) end
      if list[index].checkpoint and not resuming and sturdy(0.5) then
        -- The save records the stage with none of its body's actions done
        -- (healing on the way here is not replayed on restoration).
        dk3.stage(index, list[index][1], true)
        save("coop-" .. dk3.map() .. "-" .. index)
      end
      skip = resuming and done or 0
      list[index][2](visit, resuming)
      skip = 0
    end
  end
end

-- Run-wide policy: `settings { level_deaths = 3, deaths = 20 }` permits that
-- many checkpoint restorations per map (and in total) before the run fails;
-- `map_deaths = { e1m2a = 8 }` raises the allowance for long, hard maps.
function settings(values)
  for key, value in pairs(values) do options[key] = value end
end

function move(to, opts) return act({ op = "move", target = target(to) }, opts) end
function touch(to, opts) return act({ op = "touch", target = target(to) }, opts) end
function use(to, opts) return act({ op = "use", target = target(to) }, opts) end
-- `from = {spot, ...}` walks to each spot in turn and fires from the first one
-- with a clear lane (e.g. outside a turret's reach) instead of closing in.
function shoot(to, opts)
  if opts and opts.from then
    local rest = {}
    for key, value in pairs(opts) do if key ~= "from" then rest[key] = value end end
    for _, spot in ipairs(opts.from) do
      move(spot, rest)
      if dk3.visible(target(to)) then return act({ op = "shoot", target = target(to), hold = true }, rest) end
    end
    error(dk3.where() .. ": shoot: no firing lane from the given spots", 0)
  end
  return act({ op = "shoot", target = target(to) }, opts)
end
function pickup(to, opts) return act({ op = "pickup", target = target(to) }, opts) end
function ride(to, opts) return act({ op = "ride", target = target(to) }, opts) end
function kill(to, opts)
  return act({ op = "kill", target = to and target(to) or nil, timeout = 120 }, opts)
end
function clear(opts) return kill(nil, opts) end
-- Leaves by the exit to `map`, first collecting health and ammunition near
-- by: the next map may open on a fight.
function exit(map, opts)
  -- Up to the exit first: the health about it (a station by the door) is
  -- what the next map's arrival is fought with.
  local id = map and dk3.exit_to(map)
  local door = id and dk3.entity({ id = id })
  if door then try(move, { door.x, door.y, door.z }, { radius = 320, timeout = 60 }) end
  tend()
  recover(0.8)
  resupply()
  return act({ op = "exit", map = map, timeout = 180 }, opts)
end
function cinematic(opts) return act({ op = "cinematic", timeout = 900 }, opts) end
function look(yaw, pitch) return act({ op = "look", yaw = yaw, pitch = pitch or 0, timeout = 5 }) end
function weapon(id) return act({ op = "weapon", weapon = id, timeout = 10 }) end
function jump() return act({ op = "jump", timeout = 5 }) end
-- Running jump: walk precisely to `takeoff`, then run and jump toward
-- `landing`; succeeds only when the player lands there.
function leap(takeoff, landing, opts)
  return act({ op = "leap", target = target(takeoff), around = landing, timeout = 20 }, opts)
end
-- Shotcycler jump: from `takeoff`, fired at the floor as the player jumps
-- (again near the top of each rise) toward `landing`, over a fence a jump
-- alone does not clear; succeeds only when the player lands there.
function blastjump(takeoff, landing, opts)
  return act({ op = "leap", target = target(takeoff), around = landing, blast = true, weapon = 4, timeout = 20 }, opts)
end
function save(slot) return act({ op = "save", slot = slot, timeout = 30 }) end

-- Points the view at a target (a selector or a point), for orders that act
-- on what the player looks at (a companion's collect or attack order).
function point_at(to)
  local t = target(to)
  local x, y, z
  if t.point then
    x, y, z = t.point[1], t.point[2], t.point[3]
  else
    local found = dk3.entity(t)
    if not found then return false end
    x, y, z = found.x, found.y, found.z
  end
  local px, py, pz = dk3.position()
  pz = pz + 22
  local yaw = math.deg(math.atan(y - py, x - px))
  local pitch = -math.deg(math.atan(z - pz, math.sqrt((x - px) ^ 2 + (y - py) ^ 2)))
  look(yaw, pitch)
  return true
end

-- Has a companion pick up an item (a weapon for unarmed Superfly): from
-- where it is in sight, look at it and give the collect order.
function companion_take(item, who)
  if not dk3.entity(target(item)) then return false end
  if not dk3.visible(target(item)) then pickup_near(item) end
  point_at(item)
  dk3.sidekick(who or "all", "collect")
  return true
end

-- Walks to within sight of an item without taking it (stops short).
function pickup_near(item)
  local found = dk3.entity(target(item))
  if not found then return end
  try(move, { found.x, found.y, found.z }, { radius = 160, timeout = 30 })
end
function wait(duration) return act({ op = "wait", duration = duration, timeout = duration + 1 }) end

-- Walks the points in order, starting at the one nearest the player: a game
-- save restored partway along the path continues from where the player is.
function path(points, opts)
  local first, best = 1, math.huge
  local x, y, z = dk3.position()
  for index, point in ipairs(points) do
    if type(point) == "table" and type(point[1]) == "number" then
      local d = (point[1] - x) ^ 2 + (point[2] - y) ^ 2 + (point[3] - z) ^ 2
      if d < best then first, best = index, d end
    end
  end
  for index = first, #points do move(points[index], opts) end
end

-- Progress planner: while the area graph cannot reach `goal`, operate the
-- nearest reachable control not yet tried (button, touch trigger, breakable
-- control), then look again. Every operation is ordinary player input; the
-- log names each control tried so a route author can pin the sequence down.
function advance(goal, opts)
  opts = opts or {}
  -- Planning starts from the world as it stands: after a restoration its
  -- own operations are not replayed as skipped (it plans them again).
  skip = 0
  local tried = {}
  for round = 1, opts.rounds or 24 do
    if dk3.reachable(target(goal)) then return round - 1 end
    -- The navigation planner first: the closed gate on the way and the
    -- authored control that opens it (itself perhaps behind another gate).
    -- Crossing a mover over void (an extended bridge) the player has no area
    -- to plan from for a moment: look again before guessing.
    local step = dk3.plan(target(goal))
    for _ = 1, 6 do
      if step or dk3.reachable(target(goal)) then break end
      wait(0.5)
      step = dk3.plan(target(goal))
    end
    if not step and dk3.reachable(target(goal)) then return round - 1 end
    if step and step.wait then
      wait(1.5)                                -- a door in the way is opening
      goto continue
    end
    if step and not tried[step.id] then
      tried[step.id] = true
      dk3.event("advance", string.format("round=%d planned index=%d action=%s", round, step.index, step.action))
      try(function()
        local selector, limit = { id = step.id }, { timeout = opts.timeout or 90 }
        if step.action == "shoot" then shoot(selector, limit)
        elseif step.action == "touch" then touch(selector, limit)
        else use(selector, limit) end
      end)
      -- The gate may answer late (timed relays, slow doors): give it time
      -- before planning again.
      for _ = 1, 24 do
        wait(0.5)
        if dk3.reachable(target(goal)) then break end
        local next = dk3.plan(target(goal))
        if not next or next.wait or next.gate ~= step.gate then break end
      end
      goto continue
    end
    local x, y, z = dk3.position()
    local candidates = {}
    for _, control in ipairs(dk3.controls()) do
      if control.ready and not control.operated and not tried[control.id] then
        control.distance = (control.x - x) ^ 2 + (control.y - y) ^ 2 + (control.z - z) ^ 2
        candidates[#candidates + 1] = control
      end
    end
    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    local chosen
    for index = 1, math.min(#candidates, opts.candidates or 40) do
      local control = candidates[index]
      if dk3.reachable({ id = control.id }, control.kind) then chosen = control break end
    end
    if not chosen then error(dk3.where() .. ": advance: no reachable control left after " .. (round - 1) .. " rounds", 0) end
    tried[chosen.id] = true
    dk3.event("advance", string.format("round=%d %s index=%d kind=%s target=%s", round, chosen.classname, chosen.index, chosen.kind, chosen.target))
    try(function()
      -- Generous: a door on the way may first need its own control elsewhere.
      local selector, limit = { id = chosen.id }, { timeout = opts.timeout or 90 }
      if chosen.kind == "shoot" then shoot(selector, limit)
      elseif chosen.kind == "touch" then touch(selector, limit)
      else use(selector, limit) end
    end)
    wait(1.5)                                  -- let doors, lifts and relays move
    ::continue::
  end
  error(dk3.where() .. ": advance: goal still unreachable", 0)
end

-- Route authoring aid: logs which controls (and the exit to `map`) the area
-- graph can reach from the player's current position.
function survey(map)
  local x, y, z = dk3.position()
  dk3.log(string.format("survey from %.0f,%.0f,%.0f", x, y, z))
  for _, control in ipairs(dk3.controls()) do
    dk3.log(string.format("survey control index=%d %s kind=%s target=%s ready=%s reachable=%s at %.0f,%.0f,%.0f",
      control.index, control.classname, control.kind, control.target, tostring(control.ready),
      tostring(dk3.reachable({ id = control.id }, control.kind)), control.x, control.y, control.z))
  end
  if map then
    local destination = dk3.exit_to(map)
    dk3.log("survey exit to " .. map .. " reachable=" .. tostring(destination and dk3.reachable({ id = destination })))
    if destination then trace({ id = destination }) end
  end
end

-- Logs the area graph's predicted route to a target (from the player, or
-- from the point `from`) as a polyline, a dozen points per line.
function trace(t, from)
  local points = {}
  local route = dk3.route(target(t), from)
  if #route == 0 then return dk3.log("route none") end
  for index, point in ipairs(route) do
    points[#points + 1] = string.format("%.0f,%.0f,%.0f", point[1], point[2], point[3])
    if #points == 12 or index == #route then
      dk3.log("route " .. table.concat(points, " "))
      points = {}
    end
  end
end

-- Authoring log for places the area graph cannot answer (it is built without
-- movers, so a train of water or a sunk floor is invisible to it): a flood
-- fill of player-sized cells (`step`, default 24 units) inside `box` =
-- {x0, y0, z0, x1, y1, z1}
-- from the player, through air and water. Dry cells are entered level or
-- downward only; water is swum freely; a cell whose eye point is under water
-- costs three times as much, so routes come up for air where they can. Logs,
-- per goal, the cheapest route's turning points (`a` marks air) and its
-- longest stretch under water, in cells.
function flood(goals, box, step)
  step = step or 24
  local nx, ny, nz = math.floor((box[4] - box[1]) / step) + 1, math.floor((box[5] - box[2]) / step) + 1, math.floor((box[6] - box[3]) / step) + 1
  local function key(i, j, k) return (k * ny + j) * nx + i end
  local function centre(at)
    local k = at // (nx * ny)
    local j = (at % (nx * ny)) // nx
    return box[1] + (at % nx) * step, box[2] + j * step, box[3] + k * step
  end
  local function cell(x, y, z)
    return math.floor((x - box[1]) / step + 0.5), math.floor((y - box[2]) / step + 0.5), math.floor((z - box[3]) / step + 0.5)
  end
  local fits, air, wet = {}, {}, {}
  for k = 0, nz - 1 do for j = 0, ny - 1 do for i = 0, nx - 1 do
    local at = key(i, j, k)
    local x, y, z = centre(at)
    if not dk3.trace({ x, y, z }, { x, y, z }, true).start_solid then
      fits[at] = true
      wet[at] = dk3.contents({ x, y, z }) & 32 ~= 0
      air[at] = dk3.contents({ x, y, z + 26 }) & 32 == 0
    end
  end end end
  -- Dijkstra with a binary heap of {cost, cell}.
  local heap = {}
  local function push(cost, at)
    heap[#heap + 1] = { cost, at }
    local n = #heap
    while n > 1 and heap[n // 2][1] > heap[n][1] do heap[n], heap[n // 2] = heap[n // 2], heap[n]; n = n // 2 end
  end
  local function pop()
    local top = heap[1]
    heap[1] = heap[#heap]
    heap[#heap] = nil
    local n = 1
    while true do
      local small, l, r = n, 2 * n, 2 * n + 1
      if heap[l] and heap[l][1] < heap[small][1] then small = l end
      if heap[r] and heap[r][1] < heap[small][1] then small = r end
      if small == n then break end
      heap[n], heap[small] = heap[small], heap[n]
      n = small
    end
    return top
  end
  local px, py, pz = dk3.position()
  local start = key(cell(px, py, pz))
  local cost, previous = { [start] = 0 }, {}
  push(0, start)
  local moves = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
  while #heap > 0 do
    local item = pop()
    local at = item[2]
    if item[1] == cost[at] then
      local x1, y1, z1 = centre(at)
      local i, j, k = cell(x1, y1, z1)
      for _, m in ipairs(moves) do
        local a, b, c = i + m[1], j + m[2], k + m[3]
        local next = key(a, b, c)
        if a >= 0 and b >= 0 and c >= 0 and a < nx and b < ny and c < nz and fits[next] then
          local x2, y2, z2 = centre(next)
          local grounded = dk3.trace({ x2, y2, z2 }, { x2, y2, z2 - 20 }, true).fraction < 1
          local allowed = wet[next] or (m[3] <= 0 and (grounded or m[3] < 0 or wet[at]))
          if allowed and dk3.trace({ x1, y1, z1 }, { x2, y2, z2 }, true).fraction >= 1 then
            local total = item[1] + (air[next] and 1 or 3)
            if not cost[next] or total < cost[next] then
              cost[next], previous[next] = total, at
              push(total, next)
            end
          end
        end
      end
    end
  end
  for _, goal in ipairs(goals) do
    local gi, gj, gk = cell(goal[1], goal[2], goal[3])
    local found
    for r = 0, 2 do
      for dk = -r, r do for dj = -r, r do for di = -r, r do
        local candidate = key(gi + di, gj + dj, gk + dk)
        if not found and cost[candidate] then found = candidate end
      end end end
    end
    local label = string.format("%d,%d,%d", goal[1], goal[2], goal[3])
    if not found then
      dk3.log("flood " .. label .. ": no route")
    else
      local cells, at = {}, found
      while at do table.insert(cells, 1, at) at = previous[at] end
      local turns, last, under, longest = {}, nil, 0, 0
      for n, at in ipairs(cells) do
        under = air[at] and 0 or under + 1
        longest = math.max(longest, under)
        local direction = cells[n + 1] and cells[n + 1] - at
        if direction ~= last then
          local x, y, z = centre(at)
          turns[#turns + 1] = string.format("{%d,%d,%d}%s", x, y, z, air[at] and "a" or "")
        end
        last = direction
      end
      dk3.log(string.format("flood %s: %d cells, longest under water %d", label, #cells, longest))
      for n = 1, #turns, 10 do dk3.log("flood   " .. table.concat(turns, " ", n, math.min(#turns, n + 9))) end
    end
  end
end

-- Authoring log of where a player can get to from here in the live world
-- (doors, broken walls and movers as they stand now): a grid of `step` units
-- inside the box {x0, y0, x1, y1}. Each move sweeps a hull to the next column
-- and drops to the floor there (any fall; water is walked through as a
-- floor): standing over a step, crouched over a step or level under a low
-- ceiling (`opts.crouch`), and with `opts.jump` (the rise a jump clears)
-- standing at that height where a player has room to stand and jump. Logs
-- the floors reached by height band and, per goal {x, y, z}, the nearest
-- floor within 48 units across and 40 up or down with the route there (each
-- point prefixed c for crouched, j for jumped), or "unreached" with the
-- nearest floor reached. A boolean `opts` is `opts.crouch`.
function walkflood(goals, box, step, opts)
  step = step or 32
  if type(opts) ~= "table" then opts = { crouch = opts } end
  local px, py, pz = dk3.position()
  local function column(i, j) return box[1] + i * step, box[2] + j * step end
  local nodes, previous, queue, head = {}, {}, {}, 1
  local function add(k, node, from)
    if nodes[k] then return end
    nodes[k] = node
    previous[k] = from
    queue[#queue + 1] = k
  end
  -- Hull, rise and mark of each kind of move, tried in this order.
  local moves = { { true, 18, "" } }
  if opts.crouch then moves[#moves + 1] = { "crouch", 18, "c" }; moves[#moves + 1] = { "crouch", 1, "c" } end
  if opts.jump then moves[#moves + 1] = { true, opts.jump, "j" } end
  -- The player's own spot first; it steps to the columns around it.
  add("start", { x = px, y = py, z = pz, i = math.floor((px - box[1]) / step + 0.5), j = math.floor((py - box[2]) / step + 0.5), start = true, mark = "" })
  local ni = math.floor((box[3] - box[1]) / step)
  local nj = math.floor((box[4] - box[2]) / step)
  while head <= #queue do
    local k = queue[head]
    head = head + 1
    local node = nodes[k]
    local standing = not dk3.trace({ node.x, node.y, node.z }, { node.x, node.y, node.z }, true).start_solid
    for dj = -1, 1 do for di = -1, 1 do
      local a, b = node.i + di, node.j + dj
      if (node.start or di ~= 0 or dj ~= 0) and a >= 0 and b >= 0 and a <= ni and b <= nj then
        local tx, ty = column(a, b)
        for _, move in ipairs(moves) do
          local hull, rise, mark = move[1], move[2], move[3]
          -- A jump needs room to stand and to rise its full height.
          local up = (hull ~= true or standing) and (rise <= 18 or dk3.trace({ node.x, node.y, node.z }, { node.x, node.y, node.z + rise }, true).fraction >= 1)
          local sweep = up and dk3.trace({ node.x, node.y, node.z + rise }, { tx, ty, node.z + rise }, hull)
          if sweep and not sweep.start_solid and sweep.fraction >= 1 then
            local down = dk3.trace({ tx, ty, node.z + rise }, { tx, ty, node.z - 600 }, hull)
            if down.fraction < 1 and down.normal_z >= 0.7 then
              add(string.format("%d:%d:%d", a, b, math.floor(down.z / 8 + 0.5)), { x = tx, y = ty, z = down.z, i = a, j = b, mark = mark }, k)
            end
            break
          end
        end
      end
    end end
  end
  dk3.log(string.format("walkflood from %.0f,%.0f,%.0f: %d floors", px, py, pz, #queue))
  if opts.dump then
    for _, node in pairs(nodes) do dk3.log(string.format("walkflood node %.0f %.0f %.0f %s", node.x, node.y, node.z, node.mark ~= "" and node.mark or "-")) end
  end
  -- The floors reached, by height band of 32 units: extent and count.
  local bands = {}
  for _, node in pairs(nodes) do
    local band = math.floor(node.z / 32)
    local b = bands[band] or { n = 0, x0 = node.x, y0 = node.y, x1 = node.x, y1 = node.y }
    b.n = b.n + 1
    b.x0, b.y0 = math.min(b.x0, node.x), math.min(b.y0, node.y)
    b.x1, b.y1 = math.max(b.x1, node.x), math.max(b.y1, node.y)
    bands[band] = b
  end
  for band, b in pairs(bands) do
    dk3.log(string.format("walkflood   band z %d..%d: %d floors in %.0f,%.0f..%.0f,%.0f", band * 32, band * 32 + 32, b.n, b.x0, b.y0, b.x1, b.y1))
  end
  for _, goal in ipairs(goals) do
    local found, best, nearest, nearest_d
    for k, node in pairs(nodes) do
      local across = math.sqrt((node.x - goal[1]) ^ 2 + (node.y - goal[2]) ^ 2)
      local d = across + math.abs(node.z - goal[3])
      if across <= 48 and math.abs(node.z - goal[3]) <= 40 and (not best or d < best) then found, best = k, d end
      if not nearest_d or d < nearest_d then nearest, nearest_d = k, d end
    end
    local label = string.format("%d,%d,%d", goal[1], goal[2], goal[3])
    if not found then
      local node = nodes[nearest]
      dk3.log(string.format("walkflood %s: unreached; nearest floor %.0f,%.0f,%.0f", label, node.x, node.y, node.z))
    else
      local points, at = {}, found
      while at do
        local node = nodes[at]
        table.insert(points, 1, string.format("%s{%.0f,%.0f,%.0f}", node.mark, node.x, node.y, node.z))
        at = previous[at]
      end
      dk3.log(string.format("walkflood %s: %d steps", label, #points))
      for n = 1, #points, 12 do dk3.log("walkflood   " .. table.concat(points, " ", n, math.min(#points, n + 11))) end
    end
  end
end

-- Heads for the forward exit to `map`, operating controls on the way when the
-- area graph has no route yet.
function progress(map, opts)
  local destination = dk3.exit_to(map)
  if not destination then error(dk3.where() .. ": progress: no exit to " .. map, 0) end
  advance({ id = destination }, opts)
  return exit(map, opts)
end

-- Collects reachable health items on this floor within `radius` (nearest
-- first) until the player has `fraction` of its maximum health or none is
-- left, then walks back: the route continues from where it asked.
-- A pack is near in practice when the area graph's way to it stays on this
-- floor and is not much longer than the straight line (not round by a drop
-- into a shaft and the climb back).
local function handy(item, x, y, z)
  local straight = math.sqrt((item.x - x) ^ 2 + (item.y - y) ^ 2)
  -- Both ways: a pack down a drop (off a bridge into the chamber below) is
  -- reached at once but the way back is long or none.
  local function near(route, ox, oy)
    if #route == 0 then return false end
    local length, px, py = 0, ox, oy
    for _, point in ipairs(route) do
      if math.abs(point[3] - z) > 96 then return false end
      length = length + math.sqrt((point[1] - px) ^ 2 + (point[2] - py) ^ 2)
      px, py = point[1], point[2]
    end
    return length <= math.max(1.6 * straight, straight + 200)
  end
  return near(dk3.route({ id = item.id }), x, y) and near(dk3.route({ x, y, z }, { item.x, item.y, item.z }), item.x, item.y)
end

-- Fetches a pickup off the route and returns to where the player stood, back
-- along the way it went (straight between the area graph's points, which do
-- not re-plan through narrow doorways), or by the area graph if that fails.
local function fetch(item, timeout)
  local home = { dk3.position() }
  local way = dk3.route({ id = item.id })
  local ok = try(function() pickup({ id = item.id }, { timeout = timeout or 20 }) end)
  local back = try(function()
    for index = #way - 1, 1, -1 do move(way[index], { direct = true, radius = 32, timeout = 10 }) end
    move(home, { direct = true, radius = 32, timeout = 10 })
  end)
  if not back then try(function() move(home, { radius = 32, timeout = 30 }) end) end
  return ok
end

function recover(fraction, radius)
  local tried = {}
  for _ = 1, 6 do
    local health, maximum = dk3.health()
    if health >= (fraction or 0.8) * maximum then break end
    local x, y, z = dk3.position()
    local best, nearest
    for _, item in ipairs(dk3.pickups(radius or 640)) do
      local distance = (item.x - x) ^ 2 + (item.y - y) ^ 2
      if item.health > 0 and not tried[item.id] and math.abs(item.z - z) <= 96 and (not nearest or distance < nearest)
          and dk3.reachable({ id = item.id }) and handy(item, x, y, z) then
        best, nearest = item, distance
      end
    end
    if not best then break end
    tried[best.id] = true
    fetch(best)
  end
  -- Then a health station or tree in reach (stations hold a limited charge).
  for _, class in ipairs({ "misc_hosportal", "misc_healthtree" }) do
    local health, maximum = dk3.health()
    if health >= (fraction or 0.8) * maximum then break end
    local x, y, z = dk3.position()
    local found = dk3.entity({ class = class, near = { x, y, z } })
    if found and math.sqrt((found.x - x) ^ 2 + (found.y - y) ^ 2) <= (radius or 640) * 1.5
        and math.abs(found.z - z) <= 128 and dk3.reachable({ id = found.id })
        and handy({ id = found.id, x = found.x, y = found.y, z = found.z }, x, y, z) then
      local home = { x, y, z }
      if class == "misc_hosportal" then try(recharge, { id = found.id }) else try(heal, { id = found.id }) end
      try(move, home, { radius = 48, timeout = 30 })
    end
  end
  local health, maximum = dk3.health()
  return health >= (fraction or 0.8) * maximum
end

-- Collects reachable ammunition on this floor within `radius` (nearest first)
-- for every owned weapon holding fewer than `low` rounds, then walks back.
-- Fights drain the ion blaster; without it a bot meets guards at range with
-- only its fists.
function resupply(low, radius)
  local tried = {}
  for _ = 1, 6 do
    local x, y, z = dk3.position()
    local best, nearest
    for _, item in ipairs(dk3.pickups(radius or 640)) do
      local distance = (item.x - x) ^ 2 + (item.y - y) ^ 2
      if item.ammo > 0 and dk3.has_weapon(item.ammo) and dk3.ammo(item.ammo) < (low or 30) and not tried[item.id]
          and math.abs(item.z - z) <= 96 and (not nearest or distance < nearest)
          and dk3.reachable({ id = item.id }) and handy(item, x, y, z) then
        best, nearest = item, distance
      end
    end
    if not best then break end
    tried[best.id] = true
    fetch(best, 30)
  end
end

-- Eats from an authored health tree until healthy or the tree is bare.
function heal(tree, opts)
  for _ = 1, 12 do
    local current, maximum = dk3.health()
    local found = dk3.entity(target(tree))
    if current >= maximum or not found or (found.fruit or 0) == 0 then return end
    use(tree, opts)
  end
end

-- Takes health from an authored health station (hosportal): it gives while
-- the player stays at it facing it, until full or the station runs dry. A
-- press while the view is held (a monitor or scene) is not a press: wait
-- for control, and press again while the station gives nothing.
function recharge(station, opts)
  for _ = 1, 3 do
    wait_until(function() return dk3.mode() == "normal" end, { timeout = 30, reason = "control back" })
    local before, maximum = dk3.health()
    if before >= maximum then return end
    use(station, opts)
    local gave = try(function()
      wait_until(function() return dk3.health() > before end, { timeout = 3, reason = "station giving" })
    end)
    if gave then
      try(function()
        wait_until(function() local health, top = dk3.health() return health >= top end,
                   { timeout = (opts or {}).timeout or 15, reason = "healed at the station" })
      end)
      return
    end
  end
end

-- Polls `predicate` once per simulation frame while the bot holds position
-- (still defending itself unless fight=false).
function wait_until(predicate, opts)
  opts = opts or {}
  local deadline = dk3.time() + seconds(opts.timeout, 60) * 1000
  while not predicate() do
    if dk3.time() >= deadline then
      error(dk3.where() .. ": wait_until: " .. (opts.reason or "condition") .. " not reached", 0)
    end
    local ok, detail = yield({ op = "frame", fight = opts.fight })
    if not ok then error(dk3.where() .. ": wait_until: " .. tostring(detail), 0) end
  end
end

-- Optional steps: returns false (and logs) instead of failing the run.
function try(fn, ...)
  local ok, problem = pcall(fn, ...)
  if not ok then dk3.log("optional step failed: " .. tostring(problem)) end
  return ok
end

function expect(condition, message)
  if not condition then error(dk3.where() .. ": expectation failed: " .. (message or "?"), 0) end
end

-- Load-time composition: `include "coop/episode1.lua"`.
function include(path) dk3.include(path) end

-- Hands nearby health to a hurt sidekick (its death loses the level): the
-- collect order on the reachable pack nearest it, until it is healthy or
-- none is left near.
local function present(id, radius)
  for _, item in ipairs(dk3.pickups(radius)) do
    if item.id == id then return true end
  end
  return false
end
function tend(radius, fraction)
  radius = radius or 900
  for _, who in ipairs({ "superfly", "mikiko" }) do
    local tried = {}
    for _ = 1, 4 do
      local mate = dk3.entity({ class = who })
      if not mate or (mate.health or 0) <= 0 or mate.health >= (fraction or 0.6) * 100 then break end
      local _, _, z = dk3.position()
      local best, nearest
      for _, item in ipairs(dk3.pickups(radius)) do
        local distance = (item.x - mate.x) ^ 2 + (item.y - mate.y) ^ 2
        -- Never into a room still held by enemies.
        if item.health > 0 and not tried[item.id] and math.abs(item.z - z) <= 128
            and dk3.hostiles(600, { item.x, item.y, item.z }) == 0
            and dk3.reachable({ id = item.id }) and (not nearest or distance < nearest) then
          best, nearest = item, distance
        end
      end
      if not best then break end
      tried[best.id] = true
      dk3.log(who .. " sent for health " .. best.id .. " at " .. math.floor(best.x) .. "," .. math.floor(best.y))
      companion_take({ id = best.id }, who)
      try(wait_until, function() return not present(best.id, radius + 400) end,
          { timeout = 20, reason = who .. " took the health" })
    end
  end
end

-- Sets a sidekick on an enemy (the attack order on what the player looks
-- at) and waits until it is dead or `timeout` seconds pass; the sidekick then
-- follows again. A brawler the player cannot afford to trade blows with.
function sic(enemy, who, timeout)
  local found = dk3.entity(target(enemy))
  if not found or (found.health or 0) <= 0 then return true end
  if not dk3.visible(target(enemy)) then return false end
  point_at(enemy)
  dk3.sidekick(who or "all", "attack")
  local ok = try(wait_until, function()
    local now = dk3.entity(target(enemy))
    return not now or (now.health or 0) <= 0
  end, { timeout = timeout or 30, reason = "the sidekick's prey dead" })
  dk3.sidekick(who or "all", "follow")
  return ok
end

-- Waits until every living sidekick is within `radius` of the player (one
-- told to follow catching up through a door just opened for it).
function regroup(radius, timeout)
  return wait_until(function()
    local x, y, z = dk3.position()
    for _, class in ipairs({ "superfly", "mikiko" }) do
      local found = dk3.entity({ class = class })
      if found and (found.health or 1) > 0 and
         math.sqrt((found.x - x) ^ 2 + (found.y - y) ^ 2 + (found.z - z) ^ 2) > (radius or 160) then
        return false
      end
    end
    return true
  end, { timeout = timeout or 30, reason = "the party regrouped" })
end

function checkpoint(name) dk3.event("checkpoint", name) end
function log(text) dk3.log(tostring(text)) end
function finish(summary) act({ op = "finish", slot = string.sub(summary or "route complete", 1, 64) }) end

-- Native entry points.
function __dk3_level(name)
  return levels[name]
end
function __dk3_option(name, map)
  if name == "level_deaths" and options.map_deaths and options.map_deaths[map] then return options.map_deaths[map] end
  return options[name]
end
