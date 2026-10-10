// SPDX-License-Identifier: GPL-2.0-or-later
//! Live navigation gates: botlib routing follows the world as it stands. The
//! compiled AAS treats every dynamic blocker as open (doors and toggled walls
//! as mover areas, damaging volumes as areas flagged no-entry, sliding floors
//! as floor in their authored place, breakables as empty space). A gate is
//! one such entity with the AAS areas it fills; while it blocks a player the
//! areas are disabled for routing (AAS_EnableRoutingArea), and enabled again
//! when it opens. Shared by every routed player (multiplayer and co-op bots).
//!
//!   damaging volume  blocks while switched on and dealing 10 or more a tick
//!   toggled wall     blocks while it stands (a cell's force field)
//!   remote door      blocks until open (a door its authored control opens)
//!   sliding floor    blocks the floor above it while away from its place
//!   breakable        blocks until broken
//!   tripwire         a touch control that switches a damaging volume on
//!                    (e1m3b's sweeping laser beams): blocks that volume
//!                    until an authored chain removes it
const std = @import("std");
const data = @import("../domain/components.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const allocator = std.heap.c_allocator;

pub const Kind = enum(u8) { hazard, wall, door, floor, breakable, tripwire, pool };
pub const Gate = struct { id: u32, kind: Kind, areas: []i32, closed: bool = false };
/// The first closed gate on a route, and where that route reaches it: the
/// predicted position in the last open area before the gate (the near side
/// of a door, where a player waits for it).
pub const Block = struct { gate: Gate, near: v.Vec3 };

const AREACONTENTS_MOVER = 1024;
const AREACONTENTS_NOTTEAM = 2048 | 4096;
const AREACONTENTS_MODELNUMSHIFT = 22;
const AREACONTENTS_MAXMODELNUM = 0x1FF;
const AREA_GROUNDED = 1;
pub const harmful_damage = 10;

pub const State = struct {
    gates: std.ArrayList(Gate) = .empty,
    built: bool = false,

    pub fn deinit(self: *State) void {
        for (self.gates.items) |gate| allocator.free(gate.areas);
        self.gates.deinit(allocator);
        self.* = .{};
    }
    /// Re-evaluates every gate and updates routing where one changed.
    pub fn step(self: *State, world: *data.World, projections: []abi.EntityProjection) !void {
        if (engine.gateway.call(c.BOTLIB_AAS_INITIALIZED, .{}) == 0) return;
        if (!self.built) {
            try self.build(world, projections);
            self.built = true;
        }
        for (self.gates.items) |*gate| {
            const entity = world.find(gate.id) orelse {
                if (gate.closed) self.set(gate, false);
                continue;
            };
            const closed = try blocks(world, entity, gate.kind);
            if (closed != gate.closed) self.set(gate, closed);
        }
    }
    /// The first closed gate along the route from `from` to `goal` that the
    /// route would take were every gate open (null: no route even then, or a
    /// live route exists already).
    pub fn blocking(self: *State, from: v.Vec3, slot: u16, goal: v.Vec3) ?Block {
        const navigation = @import("../engine/navigation.zig");
        const flags = navigation.travelFlags(true);
        var start = engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &from, @as(isize, slot) });
        const target = navigation.destinationArea(goal);
        if (start == 0 or target == 0) return report("no area", start, target);
        if (engine.gateway.call(c.BOTLIB_AAS_AREA_TRAVEL_TIME_TO_GOAL_AREA, .{ start, &from, target, @as(isize, flags) }) > 0) return report("routed", start, target);
        self.open();
        defer self.restore();
        if (engine.gateway.call(c.BOTLIB_AAS_AREA_TRAVEL_TIME_TO_GOAL_AREA, .{ start, &from, target, @as(isize, flags) }) == 0) {
            // A rider of a lift-like mover (a raised door) is placed in that
            // mover's elevator target area; where it stands may route on.
            // An airborne player (mid-jump on stairs) may be in an area
            // without links: look below for the floor it comes down on.
            var standing: isize = 0;
            for ([_]f32{ 0, 4, 12, -16, -32, -48, -64, -96 }) |rise| {
                const probe: [3]f32 = .{ from[0], from[1], from[2] + rise };
                const area = engine.gateway.call(c.BOTLIB_AAS_POINT_AREA_NUM, .{&probe});
                if (area == 0 or area == start) continue;
                if (engine.gateway.call(c.BOTLIB_AAS_AREA_TRAVEL_TIME_TO_GOAL_AREA, .{ area, &probe, target, @as(isize, flags) }) == 0) continue;
                standing = area;
                break;
            }
            if (standing == 0) {
                if (engine.integer("developer") >= 1) {
                    var message: [160]u8 = undefined;
                    engine.print(std.fmt.bufPrintZ(&message, "dk3 navigation gates: standing area={d} at {d:.0},{d:.0},{d:.0}\n", .{ standing, from[0], from[1], from[2] }) catch "");
                }
                return report("no route with every gate open", start, target);
            }
            start = standing;
        }
        var areas: isize = 1;
        var previous: i32 = @intCast(start);
        var near = from;
        while (areas <= 512) : (areas += 1) {
            var leg = std.mem.zeroes(c.aas_predictroute_t);
            _ = engine.gateway.call(c.BOTLIB_AAS_PREDICT_ROUTE, .{ &leg, start, &from, target, @as(isize, flags), areas, @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0) });
            if (leg.stopevent == c.RSE_NOROUTE) return report("route prediction lost the route", start, target);
            if (leg.endarea == previous) return report("route prediction stalled", start, leg.endarea);
            previous = leg.endarea;
            if (self.holding(leg.endarea)) |gate| return .{ .gate = gate.*, .near = near };
            if (leg.endarea == target) return report("no closed gate on the route", start, target);
            near = leg.endpos;
        }
        return report("route too long", start, target);
    }
    /// Gates whose areas include `area` (route planning: what holds this area shut).
    pub fn holding(self: *const State, area: i32) ?*const Gate {
        for (self.gates.items) |*gate| if (gate.closed and std.mem.indexOfScalar(i32, gate.areas, area) != null) return gate;
        return null;
    }
    /// Opens every closed gate for a route query that ignores them, and
    /// restores them afterwards (`restore`).
    pub fn open(self: *State) void {
        for (self.gates.items) |gate| if (gate.closed) for (gate.areas) |area| route(area, true);
    }
    pub fn restore(self: *State) void {
        for (self.gates.items) |gate| if (gate.closed) for (gate.areas) |area| route(area, false);
    }
    /// Gates may share areas (three beams in one volume): an area opens
    /// only when no other closed gate still holds it.
    fn set(self: *State, gate: *Gate, closed: bool) void {
        gate.closed = closed;
        for (gate.areas) |area| if (closed or self.holding(area) == null) route(area, !closed);
    }

    fn build(self: *State, world: *data.World, projections: []abi.EntityProjection) !void {
        // Mover areas by the inline model that fills them.
        var movers: std.AutoHashMapUnmanaged(u32, std.ArrayList(i32)) = .empty;
        defer {
            var lists = movers.valueIterator();
            while (lists.next()) |list| list.deinit(allocator);
            movers.deinit(allocator);
        }
        var area: i32 = 1;
        while (true) : (area += 1) {
            var info = std.mem.zeroes(c.aas_areainfo_t);
            if (engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ @as(isize, area), &info }) == 0) break;
            if (info.contents & AREACONTENTS_MOVER == 0) continue;
            const model: u32 = @intCast((info.contents >> AREACONTENTS_MODELNUMSHIFT) & AREACONTENTS_MAXMODELNUM);
            const entry = try movers.getOrPut(allocator, model);
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            try entry.value_ptr.append(allocator, area);
        }
        var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Binding }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject), view.read(data.Binding)) |entity, object, binding| {
            if (binding.slot >= projections.len) continue;
            const projection = projections[binding.slot];
            const kind = kindOf(world, entity, object, projection) orelse continue;
            var found: std.ArrayList(i32) = .empty;
            defer found.deinit(allocator);
            switch (kind) {
                .wall, .door => {
                    const model = inlineModel(object) orelse continue;
                    if (movers.get(model)) |list| {
                        try found.appendSlice(allocator, list.items);
                    } else if (kind == .door and (std.mem.eql(u8, object.classname, "func_door") or std.mem.eql(u8, object.classname, "func_door_rotate"))) {
                        // A door too thin for BSPC to give it areas of its own
                        // (e1m4b's dordon pair), or a remote rotating one: the
                        // doorway areas inside it.
                        try inside(&found, projection, 0);
                    }
                    // A bar high across a way (e1m4a's gate, the panel over
                    // e1m4b's crawlway) is ducked under: an area whose floor
                    // leaves a crouched player room beneath it is not shut.
                    if (kind == .door) {
                        var kept: usize = 0;
                        for (found.items) |doorway| {
                            var info = std.mem.zeroes(c.aas_areainfo_t);
                            if (engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ @as(isize, doorway), &info }) == 0) continue;
                            // (Area bounds are player origins: the floor is
                            // 24 below; a crouched player needs 48 above it.)
                            if (info.mins[2] + 24 < projection.shared.absmin[2]) continue;
                            found.items[kept] = doorway;
                            kept += 1;
                        }
                        found.shrinkRetainingCapacity(kept);
                    }
                },
                .hazard => {
                    try inside(&found, projection, AREACONTENTS_NOTTEAM);
                    try beside(&found, projection);
                },
                .tripwire => {
                    // The volume it switches on is where it bites.
                    var targets = world.queryAccess(data.World.mask(.{ data.MapObject, data.Binding }), 0, 0);
                    defer targets.deinit();
                    while (targets.next()) |hurts| for (hurts.read(data.MapObject), hurts.read(data.Binding)) |hurt, place| {
                        if (!std.mem.eql(u8, hurt.targetname, object.target) or place.slot >= projections.len) continue;
                        try inside(&found, projections[place.slot], AREACONTENTS_NOTTEAM);
                        if (found.items.len == 0) try inside(&found, projections[place.slot], 0);
                    };
                },
                .breakable => try inside(&found, projection, 0),
                .pool => try submerged(&found, projection),
                .floor => {
                    const mover = (try world.get(entity, data.Mover)).*;
                    const pose = (try world.get(entity, data.Transform)).*;
                    try above(&found, projection, v.subtract(authored(object, mover), pose.position));
                },
            }
            if (found.items.len == 0) continue;
            try self.gates.append(allocator, .{ .id = try world.persistentId(entity), .kind = kind, .areas = try allocator.dupe(i32, found.items) });
            if (engine.integer("developer") >= 2) {
                var line: [256]u8 = undefined;
                const head: []const u8 = std.fmt.bufPrint(&line, "dk3 navigation gate: #{d} {s} {s} targetname={s} areas", .{ (try world.persistentId(entity)) & 0xffffff, @tagName(kind), object.classname, object.targetname }) catch &.{};
                var cursor = head.len;
                for (found.items[0..@min(found.items.len, 12)]) |each| {
                    const piece = std.fmt.bufPrint(line[cursor..], " {d}", .{each}) catch break;
                    cursor += piece.len;
                }
                if (cursor < line.len - 1) {
                    line[cursor] = '\n';
                    line[cursor + 1] = 0;
                    engine.print(line[0 .. cursor + 1 :0]);
                }
            }
        };
        var counts = [_]usize{0} ** 7;
        for (self.gates.items) |gate| counts[@intFromEnum(gate.kind)] += 1;
        var message: [192]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 navigation gates: hazards={d} walls={d} doors={d} floors={d} breakables={d} tripwires={d} pools={d}\n", .{ counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6] }));
    }
};

/// What kind of gate an entity is, if any.
pub fn kindOf(world: *data.World, entity: @import("../ecs/world.zig").Entity, object: data.MapObject, projection: abi.EntityProjection) ?Kind {
    if (has(world, entity, data.Hazard)) return .hazard;
    if (tripwire(world, object)) return .tripwire;
    if (has(world, entity, data.Wall) and object.flags & 3 != 0) return .wall;
    if (has(world, entity, data.Destructible)) return .breakable;
    const mover = world.get(entity, data.Mover) catch return null;
    // A lethal liquid that drains away (e1m6a's nitrogen under the labs, a
    // func_water BSPC leaves out of the area graph): shut while it stands.
    // (Its entity is linked solid: the liquid is in its brushes' contents,
    // sampled across its box at mid-depth: the brushes need not fill it.)
    if (std.mem.eql(u8, object.classname, "func_water")) {
        const low = projection.shared.absmin;
        const span = v.subtract(projection.shared.absmax, low);
        for (0..5) |i| for (0..5) |j| {
            const point: v.Vec3 = .{ low[0] + span[0] * (@as(f32, @floatFromInt(i)) + 0.5) / 5, low[1] + span[1] * (@as(f32, @floatFromInt(j)) + 0.5) / 5, low[2] + span[2] / 2 };
            const liquid = engine.collisionService().contents(point, c.ENTITYNUM_NONE) catch 0;
            if (liquid & (c.CONTENTS_DK3_NITRO | c.CONTENTS_LAVA | c.CONTENTS_SLIME) != 0) return .pool;
        };
        return null;
    }
    // A door the party opens itself holds no route shut.
    if (@import("authored_nodes.zig").partyDoor(world, object, projection.shared.absmin, projection.shared.absmax)) return null;
    // A remote rotating door (e1m3b's hatch over the stairs): BSPC leaves its
    // brush out of the area graph, so its doorway areas are the ones inside it.
    if (std.mem.eql(u8, object.classname, "func_door_rotate") and object.targetname.len != 0) return .door;
    if (!std.mem.eql(u8, object.classname, "func_door")) return null;
    if (slab(projection, mover.*)) return .floor;
    if (object.targetname.len == 0) return null;
    // A thin plate (a keypad cover set in a console's floor, e1m4a) is
    // stepped over or onto wherever it stands: never a gate.
    const extent = v.subtract(projection.shared.maxs, projection.shared.mins);
    if (extent[2] < 24) return null;
    if (lift(projection, mover.*)) return null;
    return .door;
}
/// A touch button whose every target is a damaging volume: touching it
/// switches the damage on (e1m3b's laser beams, swept up and down a corridor
/// on trains until a lightning strike removes them). Never a control.
pub fn tripwire(world: *data.World, object: data.MapObject) bool {
    if (!std.mem.eql(u8, object.classname, "func_button") or object.flags & 1 == 0 or object.target.len == 0) return false;
    var any = false;
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, target| {
        if (!std.mem.eql(u8, target.targetname, object.target)) continue;
        const hazard = world.get(entity, data.Hazard) catch return false;
        if (hazard.damage < harmful_damage) return false;
        any = true;
    };
    return any;
}
/// A vertical door wide both ways is a lift (BSPC links it as an elevator;
/// its rider is carried between floors, never shut out): Daikatana builds
/// lifts as func_door with angle -1/-2. A door is a thin slab across a way.
fn lift(projection: abi.EntityProjection, mover: data.Mover) bool {
    if (mover.angular) return false;
    const travel = v.subtract(mover.opened, mover.closed);
    if (@abs(travel[2]) <= @max(@abs(travel[0]), @abs(travel[1]))) return false;
    const size = v.subtract(projection.shared.absmax, projection.shared.absmin);
    return @min(size[0], size[1]) >= 48;
}
/// Whether a gate entity blocks players now (null: not a gate).
pub fn closedNow(world: *data.World, projections: []const abi.EntityProjection, entity: @import("../ecs/world.zig").Entity) ?bool {
    const object = (world.get(entity, data.MapObject) catch return null).*;
    const binding = world.get(entity, data.Binding) catch return null;
    if (binding.slot >= projections.len) return null;
    const kind = kindOf(world, entity, object, projections[binding.slot]) orelse return null;
    return blocks(world, entity, kind) catch null;
}
fn has(world: *data.World, entity: @import("../ecs/world.zig").Entity, comptime T: type) bool {
    _ = world.get(entity, T) catch return false;
    return true;
}
fn report(reason: []const u8, start: isize, target: isize) ?Block {
    if (engine.integer("developer") >= 1) {
        var message: [160]u8 = undefined;
        engine.print(std.fmt.bufPrintZ(&message, "dk3 navigation gates: blocking: {s} start={d} goal={d}\n", .{ reason, start, target }) catch return null);
    }
    return null;
}
fn route(area: i32, enable: bool) void {
    _ = engine.gateway.call(c.BOTLIB_AAS_ENABLE_ROUTING_AREA, .{ @as(isize, area), @as(isize, @intFromBool(enable)) });
}
fn blocks(world: *data.World, entity: @import("../ecs/world.zig").Entity, kind: Kind) !bool {
    return switch (kind) {
        .hazard => blk: {
            const hazard = try world.get(entity, data.Hazard);
            break :blk hazard.enabled and hazard.damage >= harmful_damage;
        },
        .wall => blk: {
            const wall = try world.get(entity, data.Wall);
            break :blk wall.visible and !wall.nonsolid;
        },
        .door => (try world.get(entity, data.Mover)).state != .open,
        .floor => blk: {
            const object = try world.get(entity, data.MapObject);
            const pose = try world.get(entity, data.Transform);
            break :blk v.length(v.subtract(pose.position, authored(object.*, (try world.get(entity, data.Mover)).*))) > 1;
        },
        .breakable => blk: {
            const state = try world.get(entity, data.Destructible);
            break :blk !state.broken and !state.hidden and !state.nonsolid;
        },
        // Removed (killtarget) once its chain has run.
        .tripwire => true,
        .pool => (try world.get(entity, data.Mover)).state != .open,
    };
}
/// A func_door that slides sideways and is a thin wide slab: a bridge or a
/// sliding floor (BSPC compiles it as floor in its authored place).
fn slab(projection: abi.EntityProjection, mover: data.Mover) bool {
    if (mover.angular or @abs(mover.opened[2] - mover.closed[2]) > 1) return false;
    const size = v.subtract(projection.shared.maxs, projection.shared.mins);
    return size[2] <= 24 and size[0] >= 48 and size[1] >= 48;
}
fn inlineModel(object: data.MapObject) ?u32 {
    if (object.model.len < 2 or object.model[0] != '*') return null;
    return std.fmt.parseInt(u32, object.model[1..], 10) catch null;
}
/// Where a door is authored: its closed position, or its open one when it
/// starts open (the runtime swaps them for START_OPEN, flag 1).
fn authored(object: data.MapObject, mover: data.Mover) v.Vec3 {
    return if (object.flags & 1 != 0) mover.opened else mover.closed;
}
/// Areas inside the entity's linked bounds (optionally only those carrying
/// the given area contents).
fn inside(found: *std.ArrayList(i32), projection: abi.EntityProjection, contents: i32) !void {
    if (projection.shared.linked == 0 and v.length(v.subtract(projection.shared.absmax, projection.shared.absmin)) == 0) return;
    const low = v.add(projection.shared.absmin, @as(v.Vec3, @splat(1)));
    const high = v.subtract(projection.shared.absmax, @as(v.Vec3, @splat(1)));
    if (contents != 0) return collect(found, low, high, contents, false);
    // BSPC leaves a breakable's brush empty, so the areas filling it can run
    // on into the open space beside it (a panel set in a corridor wall). Only
    // areas centred where a player's hull would meet the brush are its own.
    var touching: std.ArrayList(i32) = .empty;
    defer touching.deinit(allocator);
    try collect(&touching, low, high, 0, false);
    for (touching.items) |area| {
        var info = std.mem.zeroes(c.aas_areainfo_t);
        if (engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ @as(isize, area), &info }) == 0) continue;
        const centre: v.Vec3 = info.center;
        if (centre[0] < low[0] - 15 or centre[0] > high[0] + 15 or centre[1] < low[1] - 15 or centre[1] > high[1] + 15 or centre[2] < low[2] - 32 or centre[2] > high[2] + 24) continue;
        try found.append(allocator, area);
    }
}
/// Areas where a player stands with feet in a liquid volume (the floor of a
/// pool the area graph sees as dry).
fn submerged(found: *std.ArrayList(i32), projection: abi.EntityProjection) !void {
    var touching: std.ArrayList(i32) = .empty;
    defer touching.deinit(allocator);
    try collect(&touching, projection.shared.absmin, projection.shared.absmax, 0, false);
    for (touching.items) |area| {
        var info = std.mem.zeroes(c.aas_areainfo_t);
        if (engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ @as(isize, area), &info }) == 0) continue;
        // (Area bounds are player origins: the feet are 24 below.)
        if (info.mins[2] - 24 >= projection.shared.absmax[2] - 2) continue;
        try found.append(allocator, area);
    }
}
/// Areas beside a damaging volume where every position puts a player's hull
/// into it (BSPC splits areas at a trigger's own faces, not at a hull's width
/// off them): the thin strip between e1m4b's floor fan and the wall.
fn beside(found: *std.ArrayList(i32), projection: abi.EntityProjection) !void {
    const reach: v.Vec3 = .{ 15, 15, 0 };
    const low = v.subtract(projection.shared.absmin, reach);
    const high = v.add(projection.shared.absmax, reach);
    var touching: std.ArrayList(i32) = .empty;
    defer touching.deinit(allocator);
    try collect(&touching, .{ low[0], low[1], low[2] - 32 }, .{ high[0], high[1], high[2] + 24 }, 0, false);
    for (touching.items) |area| {
        var info = std.mem.zeroes(c.aas_areainfo_t);
        if (engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ @as(isize, area), &info }) == 0) continue;
        if (info.mins[0] < low[0] or info.maxs[0] > high[0] or info.mins[1] < low[1] or info.maxs[1] > high[1]) continue;
        if (info.mins[2] - 24 > projection.shared.absmax[2] or info.maxs[2] + 32 < projection.shared.absmin[2]) continue;
        if (std.mem.indexOfScalar(i32, found.items, area) != null) continue;
        try found.append(allocator, area);
    }
}
/// Grounded areas whose floor is the top of the entity in its authored place
/// (`offset`: from where it stands now to there).
fn above(found: *std.ArrayList(i32), projection: abi.EntityProjection, offset: v.Vec3) !void {
    const low = v.add(projection.shared.absmin, offset);
    const high = v.add(projection.shared.absmax, offset);
    var touching: std.ArrayList(i32) = .empty;
    defer touching.deinit(allocator);
    try collect(&touching, .{ low[0] + 1, low[1] + 1, high[2] + 1 }, .{ high[0] - 1, high[1] - 1, high[2] + 40 }, 0, true);
    // An area that only overlaps the slab's edge is mostly the solid ledge
    // beside it (e1m3b's walkway round the opened floor): it stays open.
    for (touching.items) |area| {
        var info = std.mem.zeroes(c.aas_areainfo_t);
        if (engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ @as(isize, area), &info }) == 0) continue;
        const centre: v.Vec3 = info.center;
        if (centre[0] < low[0] or centre[0] > high[0] or centre[1] < low[1] or centre[1] > high[1]) continue;
        try found.append(allocator, area);
    }
}
fn collect(found: *std.ArrayList(i32), low: v.Vec3, high: v.Vec3, contents: i32, grounded: bool) !void {
    var areas: [256]c_int = undefined;
    const count: usize = @intCast(engine.gateway.call(c.BOTLIB_AAS_BBOX_AREAS, .{ &low, &high, &areas, @as(isize, areas.len) }));
    for (areas[0..@min(count, areas.len)]) |area| {
        var info = std.mem.zeroes(c.aas_areainfo_t);
        if (engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ @as(isize, area), &info }) == 0) continue;
        if (contents != 0 and info.contents & contents == 0) continue;
        if (grounded and info.flags & AREA_GROUNDED == 0) continue;
        try found.append(allocator, area);
    }
}
