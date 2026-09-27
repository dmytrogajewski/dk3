// SPDX-License-Identifier: GPL-2.0-or-later
//! Body-space navigation goals and collision-qualified locomotion steering.
const v = @import("vector.zig");
const collision = @import("collision.zig");
/// A pickup's render/physics origin is not the collector's navigation origin.
/// Put the collector's feet on the pickup's support plane without moving the item.
pub fn pickupPoint(position: v.Vec3, pickup_mins: v.Vec3, collector_mins: v.Vec3) v.Vec3 {
    return .{ position[0], position[1], position[2] + pickup_mins[2] - collector_mins[2] };
}
/// A downward search may begin inside an overhang and leave it before finding
/// the floor. Accept that floor only if the final standing hull is actually clear.
pub const Support = struct { floor: ?collision.Trace = null, obstruction: ?u16 = null };
pub fn supportedPoint(service: collision.Collision, request: collision.Request) !Support {
    const hit = try service.trace(request);
    if (hit.all_solid) return .{ .obstruction = hit.entity };
    if (hit.fraction == 1 or hit.normal[2] < 0.7) return .{};
    if (hit.start_solid) {
        var stationary = request;
        stationary.start = hit.end;
        stationary.end = hit.end;
        const clearance = try service.trace(stationary);
        if (clearance.start_solid or clearance.all_solid) return .{ .obstruction = clearance.entity };
    }
    return .{ .floor = hit };
}
pub fn crouch(service: collision.Collision, position: v.Vec3, destination: v.Vec3, mins: v.Vec3, standing: v.Vec3, slot: u16, mask: u32) !bool {
    const delta = v.subtract(destination, position);
    const flat: v.Vec3 = .{ delta[0], delta[1], 0 };
    const end = v.add(position, v.scale(v.normalize(flat), @min(32, v.length(flat))));
    const upright = try service.trace(.{ .start = position, .end = end, .mins = mins, .maxs = standing, .slot = slot, .mask = mask });
    if (!upright.start_solid and !upright.all_solid and upright.fraction == 1) return false;
    var low = standing;
    low[2] = 4;
    const ducked = try service.trace(.{ .start = position, .end = end, .mins = mins, .maxs = low, .slot = slot, .mask = mask });
    return !ducked.start_solid and !ducked.all_solid and ducked.fraction == 1;
}

/// Qualify a short ordinary walk through an AAS gap. Every hull sweep and
/// support interval must work; a clear endpoint alone cannot authorize a route.
pub const Bounds = struct { mins: v.Vec3, maxs: v.Vec3 };
pub fn walkPath(service: collision.Collision, request: collision.Request, forbidden: u32, hazards: []const Bounds) !?v.Vec3 {
    const delta = v.subtract(request.end, request.start);
    const distance = @sqrt(delta[0] * delta[0] + delta[1] * delta[1]);
    if (distance > 640) return null;
    const count: usize = @max(1, @as(usize, @intFromFloat(@ceil(distance / 16))));
    var position = request.start;
    for (1..count + 1) |index| {
        var across = v.add(request.start, v.scale(delta, @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(count))));
        across[2] = position[2];
        var segment = request;
        segment.start = position;
        segment.end = across;
        const direct = try service.trace(segment);
        if (direct.start_solid or direct.all_solid) return null;
        if (direct.fraction < 1) {
            segment.end = v.add(position, .{ 0, 0, 18 });
            const up = try service.trace(segment);
            if (up.start_solid or up.all_solid or up.fraction < 1) return null;
            segment.start = segment.end;
            across[2] += 18;
            segment.end = across;
            const raised = try service.trace(segment);
            if (raised.start_solid or raised.all_solid or raised.fraction < 1) return null;
        }
        segment.start = across;
        segment.end = .{ across[0], across[1], position[2] - 18 };
        const support = (try supportedPoint(service, segment)).floor orelse return null;
        if (@abs(support.end[2] - position[2]) > 18) return null;
        for (hazards) |hazard| {
            // Conservatively reject a hurt brush touching this short swept
            // interval, including the step clearance above the support plane.
            var overlaps = true;
            for (0..3) |axis| if (@max(position[axis], support.end[axis]) + request.maxs[axis] + (if (axis == 2) @as(f32, 18) else 0) <= hazard.mins[axis] or @min(position[axis], support.end[axis]) + request.mins[axis] >= hazard.maxs[axis]) {
                overlaps = false;
            };
            if (overlaps) return null;
        }
        position = support.end;
        if (try service.contents(v.add(position, .{ 0, 0, request.mins[2] + 1 }), request.slot) & forbidden != 0) return null;
    }
    return position;
}

test "local walking recovery requires supported intermediate steps and rejects walls gaps and hazards" {
    const t = @import("std").testing;
    const Fixture = struct {
        wall: bool = false,
        gap: bool = false,
        hazard: bool = false,
        fn trace(raw: *anyopaque, request: collision.Request) !collision.Trace {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (request.end[0] != request.start[0]) {
                if (request.end[0] >= 32 and (self.wall or request.start[2] < 40)) return .{ .fraction = 0.5, .end = request.start, .normal = .{ -1, 0, 0 } };
                return .{ .fraction = 1, .end = request.end, .normal = @splat(0) };
            }
            if (request.end[2] < request.start[2]) {
                if (self.gap and request.start[0] >= 32 and request.start[0] <= 48) return .{ .fraction = 1, .end = request.end, .normal = @splat(0) };
                const height: f32 = if (request.start[0] >= 32) 40 else 24;
                return .{ .fraction = 0.5, .end = .{ request.end[0], request.end[1], height }, .normal = .{ 0, 0, 1 } };
            }
            return .{ .fraction = 1, .end = request.end, .normal = @splat(0) };
        }
        fn contents(raw: *anyopaque, point: v.Vec3, _: u16) !u32 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return if (self.hazard and point[0] >= 32) 4 else 0;
        }
    };
    var fixture: Fixture = .{};
    const service: collision.Collision = .{ .context = &fixture, .trace_fn = Fixture.trace, .contents_fn = Fixture.contents };
    const request: collision.Request = .{ .start = .{ 0, 0, 24 }, .end = .{ 64, 0, 40 }, .mins = .{ -16, -16, -24 }, .maxs = .{ 16, 16, 32 }, .slot = 0, .mask = 1 };
    try t.expectEqual(@as(?v.Vec3, .{ 64, 0, 40 }), try walkPath(service, request, 4, &.{}));
    try t.expectEqual(@as(?v.Vec3, null), try walkPath(service, request, 4, &.{.{ .mins = .{ 30, -8, 0 }, .maxs = .{ 34, 8, 80 } }}));
    fixture.wall = true;
    try t.expectEqual(@as(?v.Vec3, null), try walkPath(service, request, 4, &.{}));
    fixture.wall = false;
    fixture.gap = true;
    try t.expectEqual(@as(?v.Vec3, null), try walkPath(service, request, 4, &.{}));
    fixture.gap = false;
    fixture.hazard = true;
    try t.expectEqual(@as(?v.Vec3, null), try walkPath(service, request, 4, &.{}));
}

test "low passage steering requires a clear crouched sweep and never crouches for a wall" {
    const t = @import("std").testing;
    const Fixture = struct {
        wall: bool = false,
        open: bool = false,
        fn trace(raw: *anyopaque, request: collision.Request) !collision.Trace {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const blocked = self.wall or (!self.open and request.maxs[2] > 4);
            return .{ .fraction = if (blocked) 0.0 else 1.0, .end = if (blocked) request.start else request.end, .normal = .{ -1, 0, 0 } };
        }
    };
    var fixture: Fixture = .{};
    const service: collision.Collision = .{ .context = &fixture, .trace_fn = Fixture.trace };
    try t.expect(try crouch(service, .{ 0, 0, 24 }, .{ 64, 0, 24 }, .{ -12, -12, -24 }, .{ 12, 12, 30 }, 64, 1));
    fixture.wall = true;
    try t.expect(!try crouch(service, .{ 0, 0, 24 }, .{ 64, 0, 24 }, .{ -12, -12, -24 }, .{ 12, 12, 30 }, 64, 1));
    fixture.wall = false;
    fixture.open = true;
    try t.expect(!try crouch(service, .{ 0, 0, 24 }, .{ 64, 0, 24 }, .{ -12, -12, -24 }, .{ 12, 12, 30 }, 64, 1));
}

test "pickup approach shares the support plane for different item and collector bounds" {
    const t = @import("std").testing;
    for ([_]f32{ -8, 0, 1 }) |item_bottom| {
        for ([_]f32{ -24, -32 }) |collector_bottom| {
            const goal = pickupPoint(.{ 64, -128, 112 }, .{ -8, -8, item_bottom }, .{ -16, -16, collector_bottom });
            try t.expectEqual(@as(f32, 64), goal[0]);
            try t.expectEqual(@as(f32, -128), goal[1]);
            try t.expectEqual(112 + item_bottom, goal[2] + collector_bottom);
            // Raw model origins fail this contract, including floor-height weapons.
            try t.expect(goal[2] != 112);
        }
    }
}

test "control floor search can leave an overhang but must validate the final hull" {
    const t = @import("std").testing;
    const Fixture = struct {
        initial_solid: bool = true,
        final_solid: bool = false,
        all_solid: bool = false,
        fraction: f32 = 0.156,
        fn trace(raw: *anyopaque, request: collision.Request) !collision.Trace {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const stationary = v.length(v.subtract(request.start, request.end)) == 0;
            return .{ .fraction = if (stationary) 0 else self.fraction, .end = .{ 77, 1872, 152.125 }, .normal = .{ 0, 0, 1 }, .start_solid = if (stationary) self.final_solid else self.initial_solid, .all_solid = self.all_solid };
        }
    };
    var fixture: Fixture = .{};
    const service: collision.Collision = .{ .context = &fixture, .trace_fn = Fixture.trace };
    const request: collision.Request = .{ .start = .{ 77, 1872, 192 }, .end = .{ 77, 1872, -64 }, .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 32 }, .slot = 1, .mask = 1 };
    try t.expect((try supportedPoint(service, request)).floor != null);
    fixture.final_solid = true;
    try t.expect((try supportedPoint(service, request)).floor == null);
    fixture.initial_solid = false;
    try t.expect((try supportedPoint(service, request)).floor != null);
    fixture.all_solid = true;
    try t.expect((try supportedPoint(service, request)).floor == null);
    fixture.all_solid = false;
    fixture.fraction = 1;
    try t.expect((try supportedPoint(service, request)).floor == null);
}
