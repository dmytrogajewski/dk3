// SPDX-License-Identifier: GPL-2.0-or-later
//! Chest reveal and trap presentation share the bounded native effect services.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const Random = @import("../domain/components.zig").Random;
const Clock = struct { identity: i32, born: i32, next_tick: i64, seen_ms: i32, random: Random };
var clocks: [2048]?Clock = @splat(null);
pub fn reset() void {
    clocks = @splat(null);
}
pub fn draw(rendered: *c.refEntity_t, entity: c.entityState_t, now: i32) !void {
    if (entity.weapon == 2) {
        const age: f32 = @floatFromInt(@max(0, now - entity.time));
        const fraction = std.math.clamp(age / 300, 0, 1);
        const scale = 0.0007 + (5.6 - 0.0007) * fraction;
        for (&rendered.axis) |*axis| axis.* = v.scale(axis.*, scale);
        rendered.nonNormalizedAxes = c.qtrue;
        rendered.shaderRGBA[3] = @intFromFloat(std.math.clamp(1.1 * (1 - fraction), 0, 1) * 255);
        rendered.skinNum = 3;
        if (age < 200) {
            const sprites = @import("sprites.zig");
            const ring_fraction = age / 200;
            const alpha: u8 = @intFromFloat(std.math.clamp(1.1 * (1 - ring_fraction), 0, 1) * 255);
            sprites.drawPlane(try sprites.register("models/global/we_expdisc.sp2"), 0, rendered.origin, 0.0007 + (2.8 - 0.0007) * ring_fraction, false, .{ 0, -1, 0 }, .{ 0, 0, 1 }, .{ 255, 255, 255, alpha });
        }
        return;
    }
    if (entity.weapon != 1 or entity.number < 0 or entity.number >= clocks.len) return;
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &rendered.origin, engine.floatArg(165), engine.floatArg(-0.865), engine.floatArg(0.575), engine.floatArg(0.21) });
    const tick = @divFloor(@as(i64, now) * 60, 1000);
    const cached = &clocks[@intCast(entity.number)];
    if (cached.* == null or cached.*.?.identity != entity.time2 or cached.*.?.born != entity.time or now < cached.*.?.seen_ms or now - cached.*.?.seen_ms > 250)
        cached.* = .{ .identity = entity.time2, .born = entity.time, .next_tick = tick, .seen_ms = now, .random = .{ .state = @as(u32, @bitCast(entity.time2)) ^ @as(u32, @bitCast(entity.time)) } };
    const clock = &cached.*.?;
    clock.seen_ms = now;
    clock.next_tick = @max(clock.next_tick, tick - 5);
    while (clock.next_tick <= tick) : (clock.next_tick += 1) {
        @import("fx_particles.zig").cloud(v.add(rendered.origin, .{ 0, 0, 10 }), .{ 0, 0, 1 }, .{ 65, -1, 0.75 }, .{ 0.65, 0.75, 0.1 }, 2.1 + (clock.random.next() * 2 - 1) * 2, 20, 6, 100, .{ 0, 0, -100 }, 5, .cp4, @intCast(@divFloor(clock.next_tick * 1000, 60)), &clock.random);
    }
}
