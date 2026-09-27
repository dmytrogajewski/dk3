// SPDX-License-Identifier: GPL-2.0-or-later
//! Dragon breath and fireball particles. Emission uses 60 Hz simulation rather than
//! depending on display refresh; particles retain their own muzzle-space birth pose.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const Random = @import("../domain/components.zig").Random;
const Particle = struct { born_ms: i32, position: v.Vec3, velocity: v.Vec3, acceleration: v.Vec3, color: v.Vec3, alpha: f32, fade: f32, size: f32, smoke: bool };
const Emitter = struct { serial: i32 = -1, next_tick: i64 = 0 };
var particles: [4096]?Particle = @splat(null);
var emitters: [2048]Emitter = @splat(.{});
var cursor: usize = 0;
pub fn reset() void {
    particles = @splat(null);
    emitters = @splat(.{});
    cursor = 0;
}
pub fn breath(model: *const c.refEntity_t, entity: c.entityState_t, now: i32) !void {
    var tag: c.orientation_t = undefined;
    if (engine.gateway.call(c.CG_R_LERPTAG, .{ &tag, @as(isize, model.hModel), @as(isize, model.frame), @as(isize, model.frame), engine.floatArg(0), @as([*:0]const u8, "hr_muzzle") }) == 0) return error.MissingDragonMuzzleTag;
    var point = model.origin;
    for (model.axis, tag.origin) |axis, offset| point = v.add(point, v.scale(axis, offset));
    emit(entity, point, entity.origin2, now, true);
}
pub fn fireball(entity: c.entityState_t, now: i32) void {
    const direction = v.normalize(entity.pos.trDelta);
    const point = v.add(@import("../engine/trajectory.zig").evaluate(entity.pos, now), v.scale(direction, 35));
    emit(entity, point, direction, now, false);
}
fn emit(entity: c.entityState_t, point: v.Vec3, direction: v.Vec3, now: i32, breath_effect: bool) void {
    if (entity.number < 0 or entity.number >= emitters.len) return;
    const emitter = &emitters[@intCast(entity.number)];
    const tick = @divTrunc(@as(i64, now) * 60, 1000);
    if (emitter.serial != entity.time or emitter.next_tick > tick + 1) emitter.* = .{ .serial = entity.time, .next_tick = tick };
    emitter.next_tick = @max(emitter.next_tick, tick - 5);
    while (emitter.next_tick <= tick) : (emitter.next_tick += 1) {
        const at: i32 = @intCast(@divTrunc(emitter.next_tick * 1000, 60));
        var random: Random = .{ .state = @as(u32, @bitCast(at)) ^ (@as(u32, @intCast(entity.number)) *% 2654435761) };
        if (breath_effect) {
            cloud(point, direction, .{ 0, 0, 0 }, .{ 0.75, 0.35, 0.05 }, 4.25 + random.next() * 6.5, 4, 2, 200, .{ -direction[0] * 50, -direction[1] * 50, 0 }, 1, true, at, &random);
            cloud(point, direction, .{ 0.7 + (random.next() * 2 - 1) * 0.15, 0.35 + (random.next() * 2 - 1) * 0.15, 0.05 }, .{ 0.65, 0.25, 0.1 }, 3 + random.next() * 8, 10, 2, 250, @splat(0), 0, false, at, &random);
        } else {
            cloud(point, direction, .{ 0.55, 0.3, 0.05 }, .{ 0.85, 0.45, 0.2 }, 6.25 + random.next() * 6.5, 4, 2, 400, @splat(0), 10, false, at, &random);
            cloud(point, direction, .{ 0.4, 0.15, 0.05 }, .{ 0.75, 0.45, 0.2 }, 2.75 + random.next() * 0.75, 2, 5, 375, @splat(0), 0, true, at, &random);
        }
    }
}
fn cloud(point: v.Vec3, direction: v.Vec3, color: v.Vec3, alpha: v.Vec3, size: f32, count: usize, spread: f32, speed: f32, acceleration: v.Vec3, radius: f32, smoke: bool, now: i32, random: *Random) void {
    const angles: v.Vec3 = .{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi, 0 };
    const basis = v.basis(angles);
    const up = v.cross(basis.right, direction);
    for (0..count) |i| {
        const cone = spread * (if (radius > 0) @as(f32, 0.5) else 1);
        const flight = v.basis(v.add(angles, .{ (random.next() * 2 - 1) * cone, (random.next() * 2 - 1) * cone, 0 })).forward;
        const angle = 2 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count));
        const jitter: v.Vec3 = if (radius > 0) v.add(v.scale(basis.right, @cos(angle) * radius), v.scale(up, @sin(angle) * radius)) else .{ random.next() - 0.5, random.next() - 0.5, 0 };
        particles[cursor] = .{ .born_ms = now, .position = v.add(point, jitter), .velocity = v.scale(flight, speed * (0.55 + random.next() * 0.45)), .acceleration = acceleration, .color = color, .alpha = alpha[0], .fade = alpha[1] + random.next() * alpha[2], .size = size * 3 * (if (smoke) @as(f32, 7) else 1.5), .smoke = smoke };
        cursor = (cursor + 1) % particles.len;
    }
}
pub fn draw(now: i32, ref: *const c.refdef_t) void {
    const fire = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/dragon-fire")});
    const smoke = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/dragon-smoke")});
    for (&particles) |*maybe| if (maybe.*) |particle| {
        const seconds = @as(f32, @floatFromInt(now - particle.born_ms)) * 0.001;
        const alpha = particle.alpha - seconds * particle.fade;
        if (seconds < 0 or alpha <= 0) {
            maybe.* = null;
            continue;
        }
        const point = v.add(particle.position, v.add(v.scale(particle.velocity, seconds), v.scale(particle.acceleration, seconds * seconds)));
        var color: [4]u8 = undefined;
        for (particle.color, color[0..3]) |value, *channel| channel.* = @intFromFloat(std.math.clamp(value, 0, 1) * 255);
        color[3] = @intFromFloat(std.math.clamp(alpha, 0, 1) * 255);
        var vertices: [4]c.polyVert_t = undefined;
        for ([_][4]f32{ .{ -0.5, -0.5, 0, 1 }, .{ 0.5, -0.5, 1, 1 }, .{ 0.5, 0.5, 1, 0 }, .{ -0.5, 0.5, 0, 0 } }, &vertices) |corner, *vertex| vertex.* = .{ .xyz = v.add(point, v.add(v.scale(ref.viewaxis[1], corner[0] * particle.size), v.scale(ref.viewaxis[2], corner[1] * particle.size))), .st = .{ corner[2], corner[3] }, .modulate = color };
        _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ if (particle.smoke) smoke else fire, @as(isize, 4), &vertices });
    };
}
