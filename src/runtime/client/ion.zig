// SPDX-License-Identifier: GPL-2.0-or-later
//! Ion's electrical arms and trailing sparks, driven by its class-owned policy.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const Random = @import("../domain/components.zig").Random;
const policy = @import("weapon_catalog").ion.electrical;
var trails: [c.MAX_GENTITIES]struct { serial: i32 = -1, next: i32 = 0 } = @splat(.{});
pub fn reset() void {
    trails = @splat(.{});
}
pub fn draw(entity: c.entityState_t, point: v.Vec3, now: i32, ref: *const c.refdef_t) !void {
    if (entity.number < 0 or entity.number >= trails.len) return error.InvalidIonEntity;
    var random: Random = .{ .state = @as(u32, @bitCast(entity.number)) *% 2654435761 +% @as(u32, @bitCast(@divTrunc(now, 16))) };
    const length = policy.length + random.next() * policy.length_random;
    const direction = entity.pos.trDelta;
    const rotation = @mod(@as(f32, @floatFromInt(now)) * policy.degrees_per_ms, 360);
    const basis = v.basis(.{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi + rotation, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi, -rotation });
    const up = v.cross(basis.right, basis.forward);
    for (0..policy.arms) |arm| {
        var previous = point;
        for (1..policy.segments + 1) |segment| {
            const fraction = @as(f32, @floatFromInt(segment)) / policy.segments;
            var end = v.add(point, v.scale(if (arm < 2) basis.forward else up, (if (arm & 1 != 0) -length else length) * fraction));
            if (segment < policy.segments) for (&end) |*axis| {
                axis.* += (random.next() - 0.5) * policy.jitter;
            };
            @import("beams.zig").draw("dk3/fx/ion-lightning", previous, end, policy.width * 0.5, .{ 0, 204, 0, @intFromFloat(191.25 * (1 - @as(f32, @floatFromInt(segment - 1)) / policy.segments)) }, ref);
            previous = end;
        }
    }
    _ = engine.gateway.call(c.CG_R_ADDADDITIVELIGHTTOSCENE, .{ &point, engine.floatArg(policy.light + random.next() * policy.light_random), engine.floatArg(0), engine.floatArg(0.8), engine.floatArg(0) });
    const trail = &trails[@intCast(entity.number)];
    if (trail.serial != entity.time or trail.next > now or trail.next < now - 100) trail.* = .{ .serial = entity.time, .next = now };
    while (trail.next <= now) : (trail.next += policy.spark_interval) {
        const born = v.add(point, v.scale(direction, -@as(f32, @floatFromInt(now - trail.next)) * 0.001));
        const back = v.scale(v.normalize(direction), -1);
        for (0..4) |_| {
            const angles: v.Vec3 = .{ -std.math.atan2(back[2], @sqrt(back[0] * back[0] + back[1] * back[1])) * 180 / std.math.pi + (random.next() - 0.5) * 5, std.math.atan2(back[1], back[0]) * 180 / std.math.pi + (random.next() - 0.5) * 5, 0 };
            @import("fx_particles.zig").add(.{ .born_ms = trail.next, .until_ms = trail.next + 800, .position = born, .last_position = born, .velocity = v.scale(v.basis(angles).forward, 450), .acceleration = @splat(0), .color = .{ 0, 1, 0 }, .alpha = 0.8, .fade = 0, .size = 0.01 + random.next() * 0.29, .kind = .beam_spark, .shader = "dk3/fx/ion-spark" });
        }
    }
}
