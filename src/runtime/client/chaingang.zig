// SPDX-License-Identifier: GPL-2.0-or-later
//! Hover jets follow the actor; emitted smoke and sparks retain their birth pose.
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const Random = @import("../domain/components.zig").Random;
const particles = @import("fx_particles.zig");
var ticks: [2048]?i64 = @splat(null);
pub fn reset() void {
    ticks = @splat(null);
}
pub fn emit(model: *const c.refEntity_t, entity: c.entityState_t, now: i32) void {
    if (entity.number < 0 or entity.number >= ticks.len) return;
    const origin = v.add(model.origin, v.add(v.scale(model.axis[0], -10), v.scale(model.axis[2], 18.5)));
    const light = v.add(model.origin, v.add(v.scale(model.axis[0], -40), v.add(v.scale(model.axis[1], -0.5), v.scale(model.axis[2], 20.5))));
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &light, engine.floatArg(100), engine.floatArg(0.5), engine.floatArg(0.25), engine.floatArg(0.25) });
    const tick = @divTrunc(@as(i64, now) * 60, 1000);
    const clock = &ticks[@intCast(entity.number)];
    var next = clock.* orelse tick;
    if (next > tick + 1) next = tick;
    next = @max(next, tick - 5);
    while (next <= tick) : (next += 1) {
        const at: i32 = @intCast(@divTrunc(next * 1000, 60));
        var random: Random = .{ .state = @as(u32, @bitCast(at)) ^ (@as(u32, @intCast(entity.number)) *% 2654435761) };
        const smoke = random.next();
        spray(origin, .{ 0, 0, 3 }, @splat(0), .{ 0.1, 0.05 + smoke * 0.1, 0.05 }, 1 + smoke, 1, @floor((1 - smoke) * 3 + 2), 100.2, .smoke, at, &random);
        const bits = random.next();
        spray(origin, .{ 0.55, 0.55, -0.75 }, .{ 0.35 + bits * 0.2, 0.25, 0 }, .{ 0.45 + bits * 0.15, 0.35 + bits * 0.2, 0.15 }, 0.65 + bits * 0.65, 2, @floor((1 - bits) * 5 + 4), 640.2 + bits * 100, .bits, at, &random);
        const sparks = random.next();
        spray(origin, .{ 0.65, 0.25, -0.5 }, .{ 0.35 + sparks * 0.2, 0.25, 0 }, .{ 0.15, 0.35 + sparks * 0.2, 0.15 }, 7 + sparks * 3, 4, @floor((1 - sparks) * 5 + 4), 640 + sparks * 100, .spark, at, &random);
    }
    clock.* = next;
}
fn spray(origin: v.Vec3, direction: v.Vec3, color: v.Vec3, alpha: v.Vec3, size: f32, count: usize, spread: f32, speed: f32, kind: particles.Kind, now: i32, random: *Random) void {
    for (0..count) |_| {
        const position = v.add(origin, .{ (random.next() * 2 - 1) * spread - spread * 0.5, (random.next() * 2 - 1) * spread - spread * 0.5, 0 });
        const velocity: v.Vec3 = .{ (random.next() - 0.5) * speed * 0.25 * direction[0], (random.next() - 0.5) * speed * 0.25 * direction[1], speed * (0.15 + random.next() * 0.25) * direction[2] };
        particles.add(.{ .born_ms = now, .position = position, .velocity = velocity, .acceleration = .{ 0, 0, -speed / 8 }, .color = color, .alpha = alpha[0], .fade = alpha[1] + random.next() * alpha[2], .size = size * (if (kind == .smoke) @as(f32, 7) else 1.5), .kind = kind });
    }
}
