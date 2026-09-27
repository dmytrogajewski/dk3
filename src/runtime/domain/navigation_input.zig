// SPDX-License-Identifier: GPL-2.0-or-later
//! Body-space navigation goals and collision-qualified locomotion steering.
const v = @import("vector.zig");
const collision = @import("collision.zig");
/// A pickup's render/physics origin is not the collector's navigation origin.
/// Put the collector's feet on the pickup's support plane without moving the item.
pub fn pickupPoint(position: v.Vec3, pickup_mins: v.Vec3, collector_mins: v.Vec3) v.Vec3 {
    return .{ position[0], position[1], position[2] + pickup_mins[2] - collector_mins[2] };
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
