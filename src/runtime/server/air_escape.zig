// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared authored aerial retreat search. Classes own distance and completion.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const v = @import("../domain/vector.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
pub fn find(world: *data.World, entity: ecs.Entity, pose: data.Transform, body: data.Body, enemy: v.Vec3, routes: *const @import("air_routes.zig").Routes, maximum: f32, fallback_height: f32) !?v.Vec3 {
    const escape = try choose(world, entity, pose, body, enemy, routes, maximum, fallback_height, 12, &.{ .{ 1, 0, 1 }, .{ 0, 1, 1 } });
    return if (escape) |value| value.point else null;
}
pub fn choose(world: *data.World, entity: ecs.Entity, pose: data.Transform, body: data.Body, enemy: v.Vec3, routes: *const @import("air_routes.zig").Routes, maximum: f32, fallback_height: f32, resolution: u16, axes: []const v.Vec3) !?struct { point: v.Vec3, distance: f32 } {
    const random = try world.get(entity, data.Random);
    const slot = (try world.get(entity, data.Binding)).slot;
    var selected: ?v.Vec3 = null;
    outer: for (axes) |axis| {
        var degrees = random.next() * 360;
        const step_degrees: f32 = @as(f32, @floatFromInt(resolution)) * (if (random.next() > 0.5) @as(f32, 1) else -1);
        var distance = maximum;
        while (distance > 100) : (distance *= 0.65) {
            for (0..@divTrunc(@as(u16, 360), resolution)) |_| {
                const direction = v.basis(.{ -20, pose.angles[1] + degrees, 0 }).forward;
                var point = v.add(pose.position, .{ direction[0] * distance * axis[0], direction[1] * distance * axis[1], direction[2] * distance * axis[2] });
                if (random.next() > 0.5 and pose.position[2] > enemy[2] + distance * axis[2] / 2) point[2] = pose.position[2] - direction[2] * distance * axis[2];
                const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = point, .mins = v.scale(body.mins, 1.25), .maxs = v.scale(body.maxs, 1.25), .slot = slot, .mask = c.MASK_SHOT });
                if (!hit.start_solid and hit.fraction == 1) {
                    selected = point;
                    break :outer;
                }
                degrees += step_degrees;
            }
        }
    }
    const point = selected orelse v.add(enemy, .{ 0, 0, fallback_height });
    // Each class decides how to handle an absent authored air destination.
    return .{ .point = routes.nearest(point) orelse return null, .distance = v.length(v.subtract(point, pose.position)) };
}
