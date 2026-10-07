// SPDX-License-Identifier: GPL-2.0-or-later
//! Navigation coverage: where can a player actually go, and does the compiled
//! AAS know it? Floods the space reachable from the map's player starts over
//! static geometry with the native hulls and moves (a standing step, a crouched
//! step or level crawl, a standing jump of the compiled barrier height, any
//! drop), then checks every floor reached for an AAS area and for an AAS route
//! from the start whose flood reached it. Brush entities (doors, lifts, breakables) and bodies
//! are unlinked for the flood, as BSPC treats doors as open, and relinked
//! before returning. Diagnostic only: run on a map loaded for the report.
const std = @import("std");
const data = @import("../domain/components.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const allocator = std.heap.c_allocator;

const mins: v.Vec3 = .{ -15, -15, -24 };
const standing: v.Vec3 = .{ 15, 15, 32 };
const crouched: v.Vec3 = .{ 15, 15, 4 };
const max_nodes = 600_000;

const Move = enum(u8) { start, step, crouch, jump };
// gated: routed only through a damaging volume (compiled as an area no route
// enters; many are lasers and force fields the level switches off).
const Class = enum(u8) { routed, gated, uncovered, unrouted };
// seed: the player start whose flood reached this floor first; routes are
// checked from that start (a map's starts need not reach one another).
const Node = struct { position: v.Vec3, i: i32, j: i32, move: Move, seed: u8 = 0, area: i32 = 0, class: Class = .routed, cluster: u32 = 0 };

pub const Options = struct { step: f32 = 16, jump: f32 = 33 };

fn key(i: i32, j: i32, z: f32) u64 {
    const bin: i32 = @intFromFloat(@floor(z / 8 + 0.5));
    const pack = struct {
        fn field(value: i32) u64 {
            return @as(u64, @intCast(std.math.clamp(value + (1 << 20), 0, (1 << 21) - 1)));
        }
    };
    return (pack.field(i) << 42) | (pack.field(j) << 21) | pack.field(bin);
}
fn columnKey(i: i32, j: i32) u64 {
    return key(i, j, 0) & ~@as(u64, (1 << 21) - 1);
}
fn trace(start: v.Vec3, end: v.Vec3, maxs: v.Vec3) !@import("../domain/collision.zig").Trace {
    return engine.collisionService().trace(.{ .start = start, .end = end, .mins = mins, .maxs = maxs, .slot = c.ENTITYNUM_NONE, .mask = c.MASK_PLAYERSOLID });
}

pub fn run(world: *data.World, projections: []abi.EntityProjection, options: Options) !void {
    // Static geometry only: unlink everything linked, relink afterwards.
    var unlinked: std.ArrayList(u16) = .empty;
    defer unlinked.deinit(allocator);
    for (projections, 0..) |*projection, slot| if (projection.shared.linked != 0) {
        try unlinked.append(allocator, @intCast(slot));
        engine.unlink(projection);
    };
    defer for (unlinked.items) |slot| engine.link(&projections[slot]);

    var nodes: std.ArrayList(Node) = .empty;
    defer nodes.deinit(allocator);
    var index: std.AutoHashMapUnmanaged(u64, u32) = .empty;
    defer index.deinit(allocator);
    const step = options.step;
    var origin: ?v.Vec3 = null;
    var seeds: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.read(data.MapObject), view.read(data.Transform)) |object, pose| {
            if (!std.mem.startsWith(u8, object.classname, "info_player")) continue;
            const base = origin orelse pose.position;
            origin = base;
            // Starts stand on the floor below their authored origin.
            const down = try trace(v.add(pose.position, .{ 0, 0, 1 }), v.add(pose.position, .{ 0, 0, -256 }), standing);
            if (down.start_solid or down.fraction >= 1) continue;
            const i: i32 = @intFromFloat(@round((pose.position[0] - base[0]) / step));
            const j: i32 = @intFromFloat(@round((pose.position[1] - base[1]) / step));
            try nodes.append(allocator, .{ .position = down.end, .i = i, .j = j, .move = .start, .seed = @intCast(@min(seeds, 255)) });
            seeds += 1;
        };
    }
    const base = origin orelse return error.NoPlayerStart;
    if (seeds == 0) return error.NoPlayerStart;
    const hazards = c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO;
    var head: usize = 0;
    var truncated = false;
    while (head < nodes.items.len) : (head += 1) {
        const node = nodes.items[head];
        const room = !(try trace(node.position, node.position, standing)).start_solid;
        var dj: i32 = -1;
        while (dj <= 1) : (dj += 1) {
            var di: i32 = -1;
            while (di <= 1) : (di += 1) {
                if (di == 0 and dj == 0 and node.move != .start) continue;
                const a = node.i + di;
                const b = node.j + dj;
                const target: v.Vec3 = .{ base[0] + @as(f32, @floatFromInt(a)) * step, base[1] + @as(f32, @floatFromInt(b)) * step, node.position[2] };
                const moves = [_]struct { hull: v.Vec3, rise: f32, move: Move }{
                    .{ .hull = standing, .rise = 18, .move = .step },
                    .{ .hull = crouched, .rise = 18, .move = .crouch },
                    .{ .hull = crouched, .rise = 1, .move = .crouch },
                    .{ .hull = standing, .rise = options.jump, .move = .jump },
                };
                for (moves) |candidate| {
                    if (candidate.move != .crouch and !room) continue;
                    if (candidate.move == .jump and candidate.rise <= 18) continue;
                    const lifted = v.add(node.position, .{ 0, 0, candidate.rise });
                    if (candidate.move == .jump) {
                        const up = try trace(node.position, lifted, standing);
                        if (up.start_solid or up.fraction < 1) continue;
                    }
                    const over = v.add(target, .{ 0, 0, candidate.rise });
                    const sweep = try trace(lifted, over, candidate.hull);
                    if (sweep.start_solid or sweep.fraction < 1) continue;
                    const down = try trace(over, v.add(over, .{ 0, 0, -4096 }), candidate.hull);
                    if (down.start_solid or down.fraction >= 1 or down.normal[2] < 0.7) break;
                    if (try engine.collisionService().contents(v.add(down.end, .{ 0, 0, -23 }), c.ENTITYNUM_NONE) & hazards != 0) break;
                    const slot = try index.getOrPut(allocator, key(a, b, down.end[2]));
                    if (!slot.found_existing) {
                        if (nodes.items.len >= max_nodes) {
                            truncated = true;
                            _ = index.remove(key(a, b, down.end[2]));
                            break;
                        }
                        slot.value_ptr.* = @intCast(nodes.items.len);
                        try nodes.append(allocator, .{ .position = down.end, .i = a, .j = b, .move = candidate.move, .seed = node.seed });
                    }
                    break;
                }
            }
        }
    }

    // The compiled navigation, not the live gates: open every area a gate
    // disabled for these route checks, and close them again afterwards.
    var disabled: std.ArrayList(i32) = .empty;
    defer {
        for (disabled.items) |area| _ = engine.gateway.call(c.BOTLIB_AAS_ENABLE_ROUTING_AREA, .{ @as(isize, area), @as(isize, 0) });
        disabled.deinit(allocator);
    }
    {
        var area: i32 = 1;
        while (true) : (area += 1) {
            var info = std.mem.zeroes(c.aas_areainfo_t);
            if (engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ @as(isize, area), &info }) == 0) break;
            if (engine.gateway.call(c.BOTLIB_AAS_ENABLE_ROUTING_AREA, .{ @as(isize, area), @as(isize, -1) }) != 0) continue;
            _ = engine.gateway.call(c.BOTLIB_AAS_ENABLE_ROUTING_AREA, .{ @as(isize, area), @as(isize, 1) });
            try disabled.append(allocator, area);
        }
    }
    // AAS presence and routing from the start whose flood reached each floor.
    const flags = @import("../engine/navigation.zig").travelFlags(true);
    var routes: std.AutoHashMapUnmanaged(u64, Class) = .empty;
    defer routes.deinit(allocator);
    // Each start's routing origin: the first floor with an area its flood reached.
    var start_areas = [_]i32{0} ** 256;
    var start_points: [256]v.Vec3 = undefined;
    for (nodes.items) |*node| {
        const probe: [3]f32 = .{ node.position[0], node.position[1], node.position[2] + 1 };
        node.area = @intCast(engine.gateway.call(c.BOTLIB_AAS_POINT_AREA_NUM, .{&probe}));
        if (start_areas[node.seed] == 0 and node.area != 0) {
            start_areas[node.seed] = node.area;
            start_points[node.seed] = node.position;
        }
    }
    const start_area = start_areas[0];
    var counts = [_]usize{0} ** 4;
    var moves = [_]usize{0} ** 4;
    for (nodes.items) |*node| {
        moves[@intFromEnum(node.move)] += 1;
        if (node.area == 0) {
            node.class = .uncovered;
        } else if (node.area != start_areas[node.seed]) {
            const from = start_areas[node.seed];
            const known = try routes.getOrPut(allocator, (@as(u64, node.seed) << 32) | @as(u32, @bitCast(node.area)));
            if (!known.found_existing) {
                const travel = struct {
                    fn time(origin_area: i32, point: *const v.Vec3, to: i32, mask: i32) bool {
                        return engine.gateway.call(c.BOTLIB_AAS_AREA_TRAVEL_TIME_TO_GOAL_AREA, .{ @as(isize, origin_area), point, @as(isize, to), @as(isize, mask) }) > 0;
                    }
                };
                const point = &start_points[node.seed];
                known.value_ptr.* = if (from == 0) .unrouted else if (travel.time(from, point, node.area, flags)) .routed else if (travel.time(from, point, node.area, flags | c.TFL_NOTTEAM1 | c.TFL_NOTTEAM2)) .gated else .unrouted;
            }
            node.class = known.value_ptr.*;
        }
        counts[@intFromEnum(node.class)] += 1;
    }
    var message: [512]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&message, "dk3 navcover: seeds={d} nodes={d} routed={d} gated={d} uncovered={d} unrouted={d} crouch={d} jump={d} start_area={d} step={d:.0} jump_height={d:.0} truncated={d}\n", .{ seeds, nodes.items.len, counts[0], counts[1], counts[2], counts[3], moves[@intFromEnum(Move.crouch)], moves[@intFromEnum(Move.jump)], start_area, step, options.jump, @intFromBool(truncated) }));

    // Group uncovered and unrouted floors into regions of neighbouring floors.
    var columns: std.AutoHashMapUnmanaged(u64, std.ArrayList(u32)) = .empty;
    defer {
        var values = columns.valueIterator();
        while (values.next()) |list| list.deinit(allocator);
        columns.deinit(allocator);
    }
    for (nodes.items, 0..) |node, n| if (node.class != .routed) {
        const entry = try columns.getOrPut(allocator, columnKey(node.i, node.j));
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.append(allocator, @intCast(n));
    };
    const Region = struct { class: Class, count: usize, low: v.Vec3, high: v.Vec3, sample: v.Vec3, crouch: usize, jump: usize };
    var regions: std.ArrayList(Region) = .empty;
    defer regions.deinit(allocator);
    var stack: std.ArrayList(u32) = .empty;
    defer stack.deinit(allocator);
    for (nodes.items, 0..) |*seed, n| {
        if (seed.class == .routed or seed.cluster != 0) continue;
        const id: u32 = @intCast(regions.items.len + 1);
        var region: Region = .{ .class = seed.class, .count = 0, .low = seed.position, .high = seed.position, .sample = seed.position, .crouch = 0, .jump = 0 };
        seed.cluster = id;
        try stack.append(allocator, @intCast(n));
        while (stack.pop()) |current| {
            const node = nodes.items[current];
            region.count += 1;
            for (0..3) |axis| {
                region.low[axis] = @min(region.low[axis], node.position[axis]);
                region.high[axis] = @max(region.high[axis], node.position[axis]);
            }
            if (node.move == .crouch) region.crouch += 1;
            if (node.move == .jump) region.jump += 1;
            var dj: i32 = -1;
            while (dj <= 1) : (dj += 1) {
                var di: i32 = -1;
                while (di <= 1) : (di += 1) {
                    const list = columns.get(columnKey(node.i + di, node.j + dj)) orelse continue;
                    for (list.items) |other| {
                        const neighbour = &nodes.items[other];
                        if (neighbour.cluster != 0 or neighbour.class != seed.class or @abs(neighbour.position[2] - node.position[2]) > 40) continue;
                        neighbour.cluster = id;
                        try stack.append(allocator, other);
                    }
                }
            }
        }
        try regions.append(allocator, region);
    }
    std.mem.sort(Region, regions.items, {}, struct {
        fn larger(_: void, a: Region, b: Region) bool {
            return a.count > b.count;
        }
    }.larger);
    for (regions.items[0..@min(regions.items.len, 60)]) |region| {
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 navcover: gap class={s} floors={d} crouch={d} jump={d} box={d:.0},{d:.0},{d:.0}..{d:.0},{d:.0},{d:.0} at={d:.0},{d:.0},{d:.0}\n", .{ @tagName(region.class), region.count, region.crouch, region.jump, region.low[0], region.low[1], region.low[2], region.high[0], region.high[1], region.high[2], region.sample[0], region.sample[1], region.sample[2] }));
    }
    engine.print(try std.fmt.bufPrintZ(&message, "dk3 navcover: regions={d} complete\n", .{regions.items.len}));
}
