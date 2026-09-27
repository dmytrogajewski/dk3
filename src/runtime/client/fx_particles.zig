// SPDX-License-Identifier: GPL-2.0-or-later
//! Bounded particles retain birth transforms independently of their emitters.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const Random = @import("../domain/components.zig").Random;
pub const Kind = enum { fire, smoke, bits, spark, blood1, blood2, blood3, blood4, simple, cp1, cp2, cp3, cp4, rain, bubble, sparkle1, sparkle2, snow, poison, blue_spark, ice, drip, splash1, splash2, splash3, cryo, spark1, spark2, beam_spark };
pub const Particle = struct { born_ms: i32, until_ms: ?i32 = null, owner: u32 = 0, classic_factor: ?f32 = null, last_position: ?v.Vec3 = null, position: v.Vec3, velocity: v.Vec3, acceleration: v.Vec3, color: v.Vec3, alpha: f32, fade: f32, size: f32, kind: Kind, shader: ?[:0]const u8 = null };
var particles: [4096]?Particle = @splat(null);
var cursor: usize = 0;
pub fn reset() void {
    particles = @splat(null);
    cursor = 0;
}
pub fn add(particle: Particle) void {
    particles[cursor] = particle;
    cursor = (cursor + 1) % particles.len;
}
pub fn countOwner(owner: u32, now: i32) u32 {
    var count: u32 = 0;
    for (particles) |maybe| if (maybe) |particle| {
        if (particle.owner != owner or now < particle.born_ms) continue;
        if (particle.until_ms) |until| {
            if (now > until) continue;
        } else if (particle.alpha - @as(f32, @floatFromInt(now - particle.born_ms)) * 0.001 * particle.fade <= 0) continue;
        count += 1;
    };
    return count;
}
pub fn cloud(point: v.Vec3, direction: v.Vec3, color: v.Vec3, alpha: v.Vec3, size: f32, count: usize, spread: f32, speed: f32, acceleration: v.Vec3, radius: f32, kind: Kind, now: i32, random: *Random) void {
    const angles: v.Vec3 = .{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi, 0 };
    const basis = v.basis(angles);
    const up = v.cross(basis.right, direction);
    for (0..count) |i| {
        const cone = spread * (if (radius > 0) @as(f32, 0.5) else 1);
        const flight = v.basis(v.add(angles, .{ (random.next() * 2 - 1) * cone, (random.next() * 2 - 1) * cone, 0 })).forward;
        const angle = 2 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count));
        const jitter: v.Vec3 = if (radius > 0) v.add(v.scale(basis.right, @cos(angle) * radius), v.scale(up, @sin(angle) * radius)) else .{ random.next() - 0.5, random.next() - 0.5, 0 };
        particles[cursor] = .{ .born_ms = now, .position = v.add(point, jitter), .velocity = v.scale(flight, speed * (0.55 + random.next() * 0.45)), .acceleration = acceleration, .color = color, .alpha = alpha[0], .fade = alpha[1] + random.next() * alpha[2], .size = size * 3 * (if (kind == .smoke) @as(f32, 7) else if (kind == .sparkle1 or kind == .sparkle2) @as(f32, 3) else 1.5), .kind = kind };
        cursor = (cursor + 1) % particles.len;
    }
}
pub fn draw(now: i32, ref: *const c.refdef_t) void {
    var shaders: [29]isize = undefined;
    inline for (.{ "dk3/fx/dragon-fire", "dk3/fx/dragon-smoke", "dk3/fx/jet-bits", "dk3/fx/jet-spark", "dk3/particle/blood1", "dk3/particle/blood2", "dk3/particle/blood3", "dk3/particle/blood4", "dk3/particle/simple", "dk3/particle/cp1", "dk3/particle/cp2", "dk3/particle/cp3", "dk3/particle/cp4", "dk3/particle/rain", "dk3/particle/bubble", "dk3/particle/sparkle1", "dk3/particle/sparkle2", "dk3/particle/snow", "dk3/particle/poison", "dk3/particle/blue-spark", "dk3/particle/ice", "dk3/particle/drip", "dk3/particle/splash1", "dk3/particle/splash2", "dk3/particle/splash3", "dk3/particle/cryo", "dk3/particle/spark1", "dk3/particle/spark2", "dk3/particle/beam-spark" }, 0..) |name, i| shaders[i] = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, name)});
    for (&particles) |*maybe| if (maybe.*) |particle| {
        const seconds = @as(f32, @floatFromInt(now - particle.born_ms)) * 0.001;
        const alpha = particle.alpha - seconds * particle.fade;
        if (seconds < 0 or (if (particle.until_ms) |until| now > until else alpha <= 0)) {
            maybe.* = null;
            continue;
        }
        const point = positionAt(particle, seconds);
        var color: [4]u8 = undefined;
        for (particle.color, color[0..3]) |value, *channel| channel.* = @intFromFloat(std.math.clamp(value, 0, 1) * 255);
        color[3] = @intFromFloat(std.math.clamp(alpha, 0, 1) * 255);
        if (particle.kind == .beam_spark) {
            if (particle.last_position) |previous| @import("beams.zig").tapered(particle.shader orelse "dk3/particle/beam-spark", point, v.add(point, v.scale(v.subtract(previous, point), 2)), particle.size, particle.size * 0.3, color, ref);
            maybe.*.?.last_position = point;
            continue;
        }
        if (particle.kind == .rain or particle.kind == .snow or particle.classic_factor != null) {
            // Weather and complex-emitter rain share the supplied triangular atlas
            // geometry. The reference renderer keeps rain vertical even for wind.
            var up: v.Vec3 = undefined;
            var right: v.Vec3 = undefined;
            if (particle.kind == .rain) {
                const across = v.cross(ref.viewaxis[0], .{ 0, 0, -1 });
                right = v.scale(if (v.length(across) > 0.001) v.normalize(across) else ref.viewaxis[1], -2.56);
                up = .{ 0, 0, -64 };
                color[3] = @intFromFloat(std.math.clamp(alpha * 0.5, 0, 1) * 255);
            } else {
                const depth = v.dot(v.subtract(point, ref.vieworg), ref.viewaxis[0]);
                const scale: f32 = if (particle.size > 1) particle.size else if (depth < 20) 1 else 1 + depth * 0.004;
                up = v.scale(ref.viewaxis[2], (particle.classic_factor orelse 2.3) * scale);
                right = v.scale(ref.viewaxis[1], -(particle.classic_factor orelse 2.3) * scale);
            }
            const anchor = v.subtract(point, v.scale(v.add(up, right), 0.33));
            var triangle: [3]c.polyVert_t = undefined;
            for ([_]v.Vec3{ anchor, v.add(anchor, up), v.add(anchor, right) }, [_][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 } }, &triangle) |position, uv, *vertex| vertex.* = .{ .xyz = position, .st = uv, .modulate = color };
            _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ shaders[@intFromEnum(particle.kind)], @as(isize, 3), &triangle });
            continue;
        }
        var vertices: [4]c.polyVert_t = undefined;
        for ([_][4]f32{ .{ -0.5, -0.5, 0, 1 }, .{ 0.5, -0.5, 1, 1 }, .{ 0.5, 0.5, 1, 0 }, .{ -0.5, 0.5, 0, 0 } }, &vertices) |corner, *vertex| vertex.* = .{ .xyz = v.add(point, v.add(v.scale(ref.viewaxis[1], corner[0] * particle.size), v.scale(ref.viewaxis[2], corner[1] * particle.size))), .st = .{ corner[2], corner[3] }, .modulate = color };
        _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ shaders[@intFromEnum(particle.kind)], @as(isize, 4), &vertices });
    };
}

pub fn positionAt(particle: Particle, seconds: f32) v.Vec3 {
    return v.add(particle.position, v.add(v.scale(particle.velocity, seconds), v.scale(particle.acceleration, 0.5 * seconds * seconds)));
}
test "complex particle acceleration is integrated once, with the half-square term" {
    const particle: Particle = .{ .born_ms = 0, .position = .{ 10, 20, 30 }, .velocity = .{ 20, 0, 40 }, .acceleration = .{ 0, 0, -250 }, .color = @splat(1), .alpha = 1, .fade = 0, .size = 1, .kind = .simple };
    try std.testing.expectEqual(v.Vec3{ 20, 20, 18.75 }, positionAt(particle, 0.5));
    try std.testing.expectEqual(v.Vec3{ 30, 20, -55 }, positionAt(particle, 1));
}
