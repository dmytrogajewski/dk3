// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
var serials: [2048]i32 = @splat(-1);
pub fn reset() void {
    serials = @splat(-1);
}
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    const point = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    if (entity.weapon == 2) {
        if (entity.number < 0 or entity.number >= serials.len or serials[@intCast(entity.number)] == entity.time) return;
        serials[@intCast(entity.number)] = entity.time;
        if (now - entity.time > 800) return;
        var random: @import("../domain/components.zig").Random = .{ .state = @as(u32, @bitCast(entity.time)) ^ @as(u32, @intCast(entity.number)) *% 2654435761 };
        for (0..10) |_| {
            const tint = 0.2 + 0.1 * (2 * random.next() - 1);
            @import("fx_particles.zig").add(.{ .born_ms = entity.time, .position = v.add(point, .{ random.next() * 5 - 2.5, random.next() * 5 - 2.5, random.next() * 5 - 2.5 }), .velocity = .{ 0, random.next() * 50, random.next() * 50 }, .acceleration = .{ 0, 0, 50 }, .color = @splat(tint), .alpha = 1, .fade = 1.4 + random.next() * 0.2, .size = 10, .kind = .smoke });
        }
        return;
    }
    const angles = @import("../engine/trajectory.zig").evaluate(entity.apos, now);
    const axes = v.basis(angles);
    const roll = angles[2] * std.math.pi / 180;
    const right = if (entity.time2 != 0) axes.right else v.add(v.scale(ref.viewaxis[1], -@cos(roll)), v.scale(ref.viewaxis[2], @sin(roll)));
    const up = if (entity.time2 != 0) v.cross(axes.right, axes.forward) else v.add(v.scale(ref.viewaxis[1], @sin(roll)), v.scale(ref.viewaxis[2], @cos(roll)));
    const sprites = @import("sprites.zig");
    sprites.drawPlane(try sprites.register(if (entity.weapon == 1) "models/global/e_flblue.sp2" else "models/global/e_flred.sp2"), 0, point, 1, false, v.scale(right, entity.angles2[0]), v.scale(up, entity.angles2[1]), .{ 255, 255, 255, @intFromFloat(std.math.clamp(entity.origin2[0], 0, 1) * 255) });
}
