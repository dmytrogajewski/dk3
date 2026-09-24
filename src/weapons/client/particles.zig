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
