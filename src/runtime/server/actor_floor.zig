// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub fn orient(world: *data.World, entity: ecs.Entity, pose: *data.Transform, pitch_speed: f32) !void {
    const axes = v.basis(pose.angles);
    const slot = (try world.get(entity, data.Binding)).slot;
    const directions = [_]v.Vec3{ v.subtract(axes.forward, axes.right), v.add(axes.forward, axes.right), v.scale(v.subtract(axes.forward, axes.right), -1) };
    var points: [3]v.Vec3 = undefined;
    for (directions, &points) |direction, *point| {
        const start = v.add(pose.position, .{ direction[0] * 8, direction[1] * 8, 32 });
        const hit = try engine.collisionService().trace(.{ .start = start, .end = v.add(start, .{ 0, 0, -64 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID });
        point.* = hit.end;
    }
    const slope = v.subtract(points[1], points[2]);
    const wanted = std.math.clamp(-std.math.atan2(slope[2], @sqrt(slope[0] * slope[0] + slope[1] * slope[1])) * 180 / std.math.pi, -45, 45);
    pose.angles[0] += std.math.clamp(wanted - pose.angles[0], -pitch_speed, pitch_speed);
}
