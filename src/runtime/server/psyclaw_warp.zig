// SPDX-License-Identifier: GPL-2.0-or-later
//! The psychic hit disrupts horizontal momentum while the view effect is strongest.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
pub fn step(world: *data.World, entity: ecs.Entity, state: *data.Ailments, now: i64) !void {
    if (state.warp) |*warp| {
        while (warp.next_ms <= now and warp.next_ms < warp.until_ms) {
            if (warp.until_ms - warp.next_ms >= 3000) {
                var random: data.Random = .{ .state = warp.random };
                const factor = 0.55 * (random.next() * 2 - 1);
                warp.random = random.state;
                if (world.get(entity, data.Velocity) catch null) |velocity| {
                    velocity.linear[0] *= factor;
                    velocity.linear[1] *= factor;
                }
            }
            warp.next_ms += 100;
        }
        if (now >= warp.until_ms) state.warp = null;
    }
}
