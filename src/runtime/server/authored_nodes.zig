// SPDX-License-Identifier: GPL-2.0-or-later
//! The reference AI ground-node graph of a map (dk3/routes/<map>.json, the
//! converted .nod file), for what the party still takes from it: sidekick
//! teleport nodes, and doors the graph walks a sidekick through that no
//! authored control opens. Loaded once per map; a map without one has none.
const std = @import("std");
const v = @import("../domain/vector.zig");
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const prop = @import("properties.zig");
const allocator = std.heap.c_allocator;

/// NODETYPE_TELEPORTSIDEKICK of the reference node format.
pub const teleport_flag: u32 = 0x01000000;
/// A sidekick teleport node: a player close to `position` sends the party to `point`.
pub const Teleport = struct { position: v.Vec3, point: v.Vec3 };
const Segment = struct { a: v.Vec3, b: v.Vec3 };
const Graph = struct {
    map: [64]u8 = undefined,
    map_len: usize = 0,
    segments: []Segment = &.{},
    teleports: []Teleport = &.{},
};
const Node = struct { index: u16, flags: u32 = 0, position: v.Vec3, data: ?v.Vec3 = null, links: []const [2]i16 = &.{} };
var graph: Graph = .{};

/// The current map's graph.
pub fn current() *const Graph {
    var buffer: [64]u8 = undefined;
    const map = @import("persistence.zig").mapName(&buffer);
    if (graph.map_len == map.len and std.mem.eql(u8, graph.map[0..graph.map_len], map)) return &graph;
    allocator.free(graph.segments);
    allocator.free(graph.teleports);
    graph = .{};
    const length = @min(map.len, graph.map.len);
    @memcpy(graph.map[0..length], map[0..length]);
    graph.map_len = length;
    load(map) catch |err| if (engine.integer("developer") >= 1) {
        var text: [160]u8 = undefined;
        engine.print(std.fmt.bufPrintZ(&text, "dk3 authored nodes: {s}: {s}\n", .{ map, @errorName(err) }) catch "dk3 authored nodes: unavailable\n");
    };
    return &graph;
}
fn load(map: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var path: [96]u8 = undefined;
    const bytes = try @import("../engine/files.zig").read(.server, &engine.gateway, arena.allocator(), try std.fmt.bufPrintZ(&path, "dk3/routes/{s}.json", .{map}), 4 * 1024 * 1024);
    const graphs = try std.json.parseFromSliceLeaky(struct { ground: []const Node = &.{} }, arena.allocator(), bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
    var segments: std.ArrayList(Segment) = .empty;
    errdefer segments.deinit(allocator);
    var teleports: std.ArrayList(Teleport) = .empty;
    errdefer teleports.deinit(allocator);
    for (graphs.ground) |node| {
        // A zero point teleports nobody (the reference only plays the node's line).
        if (node.flags & teleport_flag != 0) if (node.data) |point| if (v.length(point) > 0) try teleports.append(allocator, .{ .position = node.position, .point = point });
        for (node.links) |link| for (graphs.ground) |other| if (other.index == link[1]) {
            try segments.append(allocator, .{ .a = node.position, .b = other.position });
            break;
        };
    }
    graph.segments = try segments.toOwnedSlice(allocator);
    graph.teleports = try teleports.toOwnedSlice(allocator);
}

/// A door the party opens itself: one the reference graph walks a sidekick
/// through (a ground link crosses it) carrying an AI node name, named, and
/// with nothing that targets the name, so no authored control opens it
/// (e1m4b's "sfdoor" between the casket corridor and the keypad room, on
/// the way its sidekick teleport node sends Superfly).
pub fn partyDoor(world: *data.World, object: data.MapObject, absmin: v.Vec3, absmax: v.Vec3) bool {
    if (!std.mem.eql(u8, object.classname, "func_door") and !std.mem.eql(u8, object.classname, "func_door_rotate")) return false;
    const node_name = prop.text(object, "nodetargetname") orelse return false;
    if (node_name.len == 0 or object.targetname.len == 0 or targeted(world, object.targetname)) return false;
    const low: v.Vec3 = .{ absmin[0] - 1, absmin[1] - 1, absmin[2] };
    const high: v.Vec3 = .{ absmax[0] + 1, absmax[1] + 1, absmax[2] };
    for (current().segments) |segment| if (crosses(segment, low, high)) return true;
    return false;
}
fn targeted(world: *data.World, name: []const u8) bool {
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.MapObject)) |object| {
        if (std.mem.eql(u8, object.target, name)) return true;
        for ([_][]const u8{ "killtarget", "pathtarget", "deathtarget" }) |key| if (prop.text(object, key)) |value| if (std.mem.eql(u8, value, name)) return true;
    };
    return false;
}
/// Whether the segment passes through the box (slab test).
fn crosses(segment: Segment, low: v.Vec3, high: v.Vec3) bool {
    var enter: f32 = 0;
    var leave: f32 = 1;
    for (0..3) |axis| {
        const delta = segment.b[axis] - segment.a[axis];
        if (@abs(delta) < 1e-6) {
            if (segment.a[axis] < low[axis] or segment.a[axis] > high[axis]) return false;
            continue;
        }
        var near = (low[axis] - segment.a[axis]) / delta;
        var far = (high[axis] - segment.a[axis]) / delta;
        if (near > far) std.mem.swap(f32, &near, &far);
        enter = @max(enter, near);
        leave = @min(leave, far);
        if (enter > leave) return false;
    }
    return true;
}

test "a link through a door's box crosses it; one beside it does not" {
    const t = std.testing;
    const door: [2]v.Vec3 = .{ .{ 1736, 928, -552 }, .{ 1760, 976, -424 } };
    try t.expect(crosses(.{ .a = .{ 1624, 976, -528 }, .b = .{ 1848, 968, -520 } }, door[0], door[1]));
    try t.expect(!crosses(.{ .a = .{ 1624, 1076, -528 }, .b = .{ 1848, 1068, -520 } }, door[0], door[1]));
}
