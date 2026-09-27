// SPDX-License-Identifier: GPL-2.0-or-later
//! Supplied aerial nodes, with live collision checks on links and endpoints.
const std = @import("std");
const v = @import("../domain/vector.zig");
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const Node = struct { index: u16, position: v.Vec3, links: []const [2]i16 };
pub const Routes = struct {
    nodes: []const Node = &.{},
    indices: [4096]?u16 = @splat(null),
    pub fn init(self: *Routes, allocator: std.mem.Allocator) !void {
        try self.initKind(allocator, .air);
    }
    pub fn initGround(self: *Routes, allocator: std.mem.Allocator) !void {
        try self.initKind(allocator, .ground);
    }
    fn initKind(self: *Routes, allocator: std.mem.Allocator, kind: enum { air, ground }) !void {
        var map_buffer: [64]u8 = undefined;
        const map = @import("persistence.zig").mapName(&map_buffer);
        var path: [96]u8 = undefined;
        const bytes = try @import("../engine/files.zig").read(.server, &engine.gateway, allocator, try std.fmt.bufPrintZ(&path, "dk3/routes/{s}.json", .{map}), 4 * 1024 * 1024);
        const graphs = try std.json.parseFromSliceLeaky(struct { air: []const Node = &.{}, ground: []const Node = &.{} }, allocator, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        self.nodes = if (kind == .air) graphs.air else graphs.ground;
        if (self.nodes.len > 4096) return error.AuthoredNodeCapacity;
        for (self.nodes, 0..) |node, i| {
            if (node.index >= self.indices.len or self.indices[node.index] != null or node.links.len > 6) return error.InvalidAirNode;
            for (node.position) |coordinate| if (!std.math.isFinite(coordinate) or @abs(coordinate) > 1048576) return error.InvalidAirNode;
            self.indices[node.index] = @intCast(i);
        }
        for (self.nodes) |node| for (node.links) |link| if (link[1] < 0 or link[1] >= self.indices.len or self.indices[@intCast(link[1])] == null) return error.InvalidAirLink;
    }
    pub fn nearest(self: *const Routes, point: v.Vec3) ?v.Vec3 {
        var distance: f32 = std.math.inf(f32);
        var result: ?v.Vec3 = null;
        for (self.nodes) |node| {
            const d = v.length(v.subtract(node.position, point));
            if (d < distance) {
                distance = d;
                result = node.position;
            }
        }
        return result;
    }
    pub fn waterPath(a: v.Vec3, b: v.Vec3, body: data.Body, slot: u16) !bool {
        return visible(a, b, body, slot, true);
    }
    fn visible(a: v.Vec3, b: v.Vec3, body: data.Body, slot: u16, water: bool) !bool {
        if (water) {
            const steps: usize = @intFromFloat(@max(1, @ceil(v.length(v.subtract(b, a)) / 16)));
            for (0..steps + 1) |i| {
                const point = v.add(a, v.scale(v.subtract(b, a), @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps))));
                if (try engine.collisionService().contents(point, slot) & c.MASK_WATER == 0) return false;
            }
        }

        const hit = try engine.collisionService().trace(.{ .start = a, .end = b, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_SOLID });
        return !hit.start_solid and !hit.all_solid and hit.fraction == 1;
    }
    pub fn next(self: *const Routes, position: v.Vec3, destination: v.Vec3, body: data.Body, slot: u16) !?v.Vec3 {
        return self.nextMedium(position, destination, body, slot, false);
    }
    pub fn nextWater(self: *const Routes, position: v.Vec3, destination: v.Vec3, body: data.Body, slot: u16) !?v.Vec3 {
        return self.nextMedium(position, destination, body, slot, true);
    }
    fn nextMedium(self: *const Routes, position: v.Vec3, destination: v.Vec3, body: data.Body, slot: u16, water: bool) !?v.Vec3 {
        if (try visible(position, destination, body, slot, water)) return destination;
        var from: ?u16 = null;
        var to: ?u16 = null;
        var start_distance: f32 = std.math.inf(f32);
        var end_distance: f32 = std.math.inf(f32);
        for (self.nodes, 0..) |node, i| {
            const a = v.length(v.subtract(node.position, position));
            const b = v.length(v.subtract(node.position, destination));
            if (a < start_distance and try visible(position, node.position, body, slot, water)) {
                from = @intCast(i);
                start_distance = a;
            }
            if (b < end_distance and try visible(destination, node.position, body, slot, water)) {
                to = @intCast(i);
                end_distance = b;
            }
        }
        const start = from orelse return null;
        const goal = to orelse return null;
        if (start_distance > 32) return self.nodes[start].position;
        var previous: [4096]?u16 = @splat(null);
        var queue: [4096]u16 = undefined;
        var read: usize = 0;
        var count: usize = 1;
        previous[start] = start;
        queue[0] = start;
        while (read < count) : (read += 1) {
            const node = queue[read];
            if (node == goal) break;
            for (self.nodes[node].links) |link| {
                const next_index = self.indices[@intCast(link[1])].?;
                if (previous[next_index] != null or !try visible(self.nodes[node].position, self.nodes[next_index].position, body, slot, water)) continue;
                previous[next_index] = node;
                queue[count] = next_index;
                count += 1;
            }
        }
        if (previous[goal] == null) return null;
        var next_index = goal;
        while (previous[next_index].? != start and next_index != start) next_index = previous[next_index].?;
        return self.nodes[next_index].position;
    }
};
