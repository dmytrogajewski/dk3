// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const sprites = @import("sprites.zig");
const policy = @import("actor_catalog").knights;
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !bool {
    const origin = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    switch (entity.frame) {
        1 => {
            const starts = [_]v.Vec3{ entity.angles, entity.angles2 };
            const births = [_]i32{ entity.time2, entity.legsAnim };
            for (starts, births, 0..) |start, born, i| {
                if (entity.otherEntityNum & (@as(i32, 1) << @intCast(i)) == 0 or now < born) continue;
                const delta = v.subtract(entity.origin2, start);
                const length = v.length(delta);
                const forward = v.normalize(delta);
                var side = v.cross(forward, .{ 0, 0, 1 });
                if (v.length(side) < 0.01) side = .{ 1, 0, 0 };
                side = v.normalize(side);
                const up = v.cross(side, forward);
                var random: @import("../domain/components.zig").Random = .{ .state = @as(u32, @bitCast(entity.number)) *% 1234567 +% @as(u32, @bitCast(@divTrunc(now, 50))) +% @as(u32, @intCast(i)) };
                const count: u16 = @intFromFloat(std.math.clamp(@ceil(length / 32), 1, 256));
                var previous = start;
                for (1..@as(usize, count) + 1) |n| {
                    var next = v.add(start, v.scale(delta, @as(f32, @floatFromInt(n)) / @as(f32, @floatFromInt(count))));
                    if (n < count) next = v.add(next, v.add(v.scale(side, (random.next() * 2 - 1) * 9), v.scale(up, (random.next() * 2 - 1) * 9)));
                    @import("beams.zig").draw("dk3/fx/ion-lightning", previous, next, 6, .{ 64, 115, 217, 153 }, ref);
                    previous = next;
                }
                if (now - born < 150) {
                    // Each flash is at the separate 24-unit attachment offset.
                    const base = v.add(origin, .{ 0, 0, -40 });
                    const flash = v.add(base, v.scale(v.subtract(start, base), 0.6));
                    const flare = try sprites.register("models/global/e_flblue.sp2");
                    sprites.draw(flare, 0, flash, 2.15, true, ref);
                }
            }
            return true;
        },
        2 => {
            if (now - entity.time < 500) _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &origin, engine.floatArg(240), engine.floatArg(-0.2), engine.floatArg(-0.2), engine.floatArg(-0.9) });
            return true;
        },
        else => return error.InvalidKnightAttackProjection,
    }
}
