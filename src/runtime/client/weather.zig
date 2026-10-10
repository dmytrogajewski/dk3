// SPDX-License-Identifier: GPL-2.0-or-later
//! Finite weather particles use authored brush columns and per-volume active density.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const policy = @import("../domain/weather.zig");
const particles = @import("fx_particles.zig");
const engine = @import("../engine/client.zig");
const Random = @import("../domain/components.zig").Random;
const Clock = struct { id: u32, tick: i64, seen_ms: i32, random: Random };
var clocks: [c.MAX_GENTITIES]?Clock = @splat(null);
pub fn reset() void {
    clocks = @splat(null);
}
fn frustum(state: policy.State, ref: *const c.refdef_t) bool {
    const horizontal = @tan(ref.fov_x * std.math.pi / 360.0);
    const vertical = @tan(ref.fov_y * std.math.pi / 360.0);
    for ([_]v.Vec3{ v.add(v.scale(ref.viewaxis[0], horizontal), ref.viewaxis[1]), v.subtract(v.scale(ref.viewaxis[0], horizontal), ref.viewaxis[1]), v.add(v.scale(ref.viewaxis[0], vertical), ref.viewaxis[2]), v.subtract(v.scale(ref.viewaxis[0], vertical), ref.viewaxis[2]) }) |normal| {
        var positive: v.Vec3 = undefined;
        for (normal, &positive, 0..) |axis, *point, i| point.* = if (axis >= 0) state.maxs[i] else state.mins[i];
        if (v.dot(v.subtract(positive, ref.vieworg), normal) < 0) return false;
    }
    return true;
}
pub fn emit(entity: c.entityState_t, now: i32, ref: *const c.refdef_t) void {
    if (entity.number < 0 or entity.number >= clocks.len or entity.time2 == 0 or entity.weapon < 0 or entity.weapon > 1) return;
    for (entity.origin2 ++ entity.angles2) |value| if (!std.math.isFinite(value) or @abs(value) > 1000000) return;
    const state: policy.State = .{ .kind = @enumFromInt(entity.weapon), .flags = @bitCast(entity.frame), .mins = entity.origin2, .maxs = entity.angles2 };
    if (!frustum(state, ref)) return;
    // Renderers that simulate weather on the GPU take the whole volume; the others decline and
    // the finite CPU particles below remain.
    if (engine.gateway.call(c.CG_DK3_R_WEATHER_V1, .{ @as(isize, entity.weapon), @as(isize, entity.frame), &state.mins, &state.maxs, @as(isize, entity.time2) }) != 0) return;
    const distance = policy.cornerDistance(state, ref.vieworg, ref.viewaxis[0]) orelse return;
    const width: i32 = @intFromFloat(@trunc(state.maxs[0]) - state.mins[0]);
    const depth: i32 = @intFromFloat(@trunc(state.maxs[1]) - state.mins[1]);
    var height: i32 = @intFromFloat(@trunc(state.maxs[2]) - state.mins[2]);
    if (state.kind == .snow and height == 0) height = 10;
    if (width <= 0 or depth <= 0 or height <= 0) return;
    const id: u32 = @bitCast(entity.time2);
    const tick = @divFloor(@as(i64, now) * 60, 1000);
    const cache = &clocks[@intCast(entity.number)];
    if (cache.* == null or cache.*.?.id != id or now < cache.*.?.seen_ms) cache.* = .{ .id = id, .tick = tick, .seen_ms = now, .random = .{ .state = id } };
    const clock = &cache.*.?;
    clock.seen_ms = now;
    clock.tick = @max(clock.tick, tick - 5);
    const maximum = policy.capacity(state.kind, width, depth, distance);
    while (clock.tick <= tick) : (clock.tick += 1) {
        const at: i32 = @intCast(@divFloor(clock.tick * 1000, 60));
        const count = policy.births(state.kind, maximum, particles.countOwner(id, at));
        for (0..count) |_| {
            var position: v.Vec3 = undefined;
            for (&position, [_]i32{ width, depth, height }, state.mins) |*axis, span, minimum| axis.* = minimum + @as(f32, @floatFromInt(integer(&clock.random, @intCast(span)))) - (if (state.kind == .rain) @as(f32, 8) else 0);
            var speed = policy.velocity(state.kind, state.flags, integer(&clock.random, 32768));
            if (state.kind == .snow and state.flags & 1 == 0) {
                speed[0] = @as(f32, @floatFromInt(integer(&clock.random, 40))) - 20;
                speed[1] = @as(f32, @floatFromInt(integer(&clock.random, 40))) - 20;
            }
            const distance_down = @as(f32, @floatFromInt(height)) - (state.maxs[2] - position[2]);
            const fall = if (state.kind == .snow) @trunc(distance_down) else distance_down;
            const until = at + @as(i32, @intFromFloat(fall / -speed[2] * 1000));
            particles.add(.{ .born_ms = at, .until_ms = until, .owner = id, .position = position, .velocity = speed, .acceleration = @splat(0), .color = @splat(1), .alpha = if (state.kind == .rain) 0.4 else 1, .fade = if (state.kind == .rain) 0.1 else 0, .size = 1, .kind = if (state.kind == .rain) .rain else .snow });
        }
    }
}
fn integer(random: *Random, limit: u32) u32 {
    return @as(u32, @intFromFloat(random.next() * 2147483648)) % limit;
}
