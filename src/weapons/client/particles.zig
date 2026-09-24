// SPDX-License-Identifier: GPL-2.0-or-later
//! Bounded transient particles; no allocations or persistence pointers.
const std = @import("std");
const r = @import("render.zig");
const c = r.c;
const v = r.v;
pub const Particle = struct {
    start: c_int = 0,
    end: c_int = 0,
    origin: v.Vec = v.zero,
    velocity: v.Vec = v.zero,
    gravity: v.Vec = v.zero,
    radius: f32 = 1,
    color: v.Vec = r.white,
    alpha: f32 = 1,
    shader: c.qhandle_t = 0,
    streak: bool = false,
};
var particles: [2048]Particle = @splat(.{});
var next: usize = 0;
pub fn reset() void {
    particles = @splat(.{});
    next = 0;
}
pub fn add(value: Particle) void {
    particles[next] = value;
    next = (next + 1) % particles.len;
}
pub const Random = struct {
    state: u32,
    pub fn next(self: *Random) f32 {
        self.state = self.state *% 1664525 +% 1013904223;
        return v.f(self.state >> 8) / 16777216;
    }
};
pub fn seed(entity: c_int, time: c_int) Random {
    return .{ .state = @as(u32, @bitCast(entity)) *% 2654435761 +% @as(u32, @bitCast(time)) };
}
/// Gold CL_ParticleEffectSparks: a random burst whose count and speed grow
/// with the strength value, fading over about a second.
pub fn sparks(origin: v.Vec, direction: v.Vec, color: v.Vec, strength: u8, random: *Random) void {
    const power: f32 = v.f(strength & 31);
    const count: usize = @intCast((@as(u32, @intFromFloat(random.next() * 31)) * (1 + @as(u32, strength & 31))) & 63);
    const along = v.scale(v.normal(direction), power * power);
    for (0..count) |_| {
        const d: f32 = @floor(random.next() * 8);
        const velocity: v.Vec = .{
            along[0] + (random.next() * 2 - 1) * 100,
            along[1] + (random.next() * 2 - 1) * 100,
            along[2] + (random.next() * 2 - 1) * 100,
        };
        const life: c_int = @intFromFloat(1000 / (0.5 + 0.1 * d));
        add(.{ .start = r.now(), .end = r.now() + life, .origin = origin, .velocity = velocity, .gravity = .{ 0, 0, -400 }, .radius = @max(0.02, d * power * 0.005), .color = color, .alpha = 1, .streak = true, .shader = c.trap_R_RegisterShader("dk3/fx/ion-spark") });
    }
}
pub fn draw() void {
    for (&particles) |*particle| {
        if (particle.end <= r.now() or particle.start > r.now()) continue;
        const seconds = v.f(r.now() - particle.start) / 1000;
        const life = v.f(particle.end - r.now()) / v.f(@max(1, particle.end - particle.start));
        const point = v.madd(v.madd(particle.origin, seconds, particle.velocity), 0.5 * seconds * seconds, particle.gravity);
        if (particle.streak) r.strip(point, v.madd(point, -1.0 / 30.0, particle.velocity), particle.radius, particle.color, particle.alpha * life, particle.shader) else {
            var entity = std.mem.zeroes(c.refEntity_t);
            entity.reType = c.RT_SPRITE;
            entity.origin = point;
            entity.radius = particle.radius;
            entity.customShader = particle.shader;
            entity.shaderRGBA = .{ r.byte(particle.color[0]), r.byte(particle.color[1]), r.byte(particle.color[2]), r.byte(particle.alpha * life) };
            c.trap_R_AddRefEntityToScene(&entity);
        }
    }
}
