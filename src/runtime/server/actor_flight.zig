// SPDX-License-Identifier: GPL-2.0-or-later
//! Collision movement shared by combat flight and authored actor paths.
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
pub fn move(pose: *data.Transform, body: data.Body, velocity: *data.Velocity, slot: u16, elapsed: u32) !void {
    var motion: @import("../domain/slide.zig").State = .{ .position = pose.position, .velocity = velocity.linear };
    var remaining = elapsed;
    while (remaining > 0) {
        const slice = @min(remaining, 50);
        remaining -= slice;
        var context: @import("../domain/slide.zig").Context = .{ .service = engine.collisionService(), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask, .delta = @as(f32, @floatFromInt(slice)) * 0.001, .gravity = 0 };
        _ = try context.move(&motion);
    }
    pose.position = motion.position;
    velocity.linear = motion.velocity;
}
