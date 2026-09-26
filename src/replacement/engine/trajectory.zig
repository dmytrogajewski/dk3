// SPDX-License-Identifier: GPL-2.0-or-later
const c = @import("abi.zig").c;
const v = @import("../domain/vector.zig");
pub fn evaluate(value: c.trajectory_t, now: i32) v.Vec3 {
    const elapsed = @as(f32, @floatFromInt(@as(i64, now) - value.trTime)) * 0.001;
    return switch (value.trType) {
        c.TR_STATIONARY, c.TR_INTERPOLATE => value.trBase,
        c.TR_LINEAR => v.add(value.trBase, v.scale(value.trDelta, elapsed)),
        c.TR_LINEAR_STOP => v.add(value.trBase, v.scale(value.trDelta, @max(0, @min(elapsed, @as(f32, @floatFromInt(value.trDuration)) * 0.001)))),
        c.TR_SINE => v.add(value.trBase, v.scale(value.trDelta, if (value.trDuration > 0) @sin(elapsed * 1000 / @as(f32, @floatFromInt(value.trDuration)) * 2 * @import("std").math.pi) else 0)),
        c.TR_DK_ACCEL_STOP, c.TR_DK_BOUNCE_STOP => blk: {
            const duration = @as(f32, @floatFromInt(value.trDuration));
            const fraction = if (duration > 0) elapsed * 1000 / duration else 1;
            const phase = @import("../domain/movers.zig").phase(if (value.trType == c.TR_DK_ACCEL_STOP) .accelerate else .bounce, fraction);
            break :blk v.add(value.trBase, v.scale(value.trDelta, phase * duration * 0.001));
        },
        c.TR_GRAVITY => blk: {
            var result = v.add(value.trBase, v.scale(value.trDelta, elapsed));
            result[2] -= 0.5 * 800 * elapsed * elapsed;
            break :blk result;
        },
        else => value.trBase,
    };
}
