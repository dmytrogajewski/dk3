// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed radial clearance selection for Reaper placement and Garroth summons.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const v = @import("../domain/vector.zig");
const engine = @import("../engine/server.zig");
pub fn choose(world: *data.World, victim: ecs.Entity, mask: u32) !v.Vec3 {
    const pose = (try world.get(victim, data.Transform)).*;
    const start = v.add(pose.position, .{ 0, 0, 10 });
    var clear: [32]f32 = undefined;
    var vectors: [32]v.Vec3 = undefined;
    for (&clear, &vectors, 0..) |*distance, *vector, i| {
        // Preserve the reference's cumulative yaw increments, including its repeated headings.
        const turn = @as(f32, @floatFromInt(i * (i + 1))) * (360.0 / 64.0);
        vector.* = v.basis(.{ 0, pose.angles[1] + turn, 0 }).forward;
        const hit = try @import("region_collision.zig").owned(world, .{ .start = start, .end = v.add(start, v.scale(vector.*, 300)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(victim, data.Binding)).slot, .mask = mask }, try world.persistentId(victim));
        distance.* = hit.fraction * 300;
    }
    var best: ?usize = null;
    for (clear, 0..) |distance, i| if (distance >= 50 and clear[(i + 31) % 32] >= 50 and clear[(i + 1) % 32] >= 50) {
        if (best == null or distance > clear[best.?]) best = i;
    };
    if (best == null) for (clear, 0..) |distance, i| {
        if (best == null or distance > clear[best.?]) best = i;
    };
    return vectors[best.?];
}
