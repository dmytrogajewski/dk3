// SPDX-License-Identifier: GPL-2.0-or-later
const r = @import("../client/render.zig");
const particles = @import("../client/particles.zig");
const c = r.c;
pub fn trail(cent: *c.centity_t) void {
    if (cent.trailTime > r.now() - 40 and cent.trailTime <= r.now()) return;
    cent.trailTime = r.now();
    var random = particles.seed(cent.currentState.number, @divTrunc(r.now(), 40));
    for (0..3) |_| particles.add(.{ .start = r.now(), .end = r.now() + 450, .origin = cent.lerpOrigin, .velocity = .{ (random.next() - 0.5) * 120, (random.next() - 0.5) * 120, (random.next() - 0.5) * 120 }, .gravity = .{ 0, 0, -400 }, .radius = 1.25 + random.next(), .color = .{ 0.3, 0.85, 0.05 }, .alpha = 0.85, .shader = c.trap_R_RegisterShader("dk3/particle/cp4") });
    particles.add(.{ .start = r.now(), .end = r.now() + 600, .origin = cent.lerpOrigin, .velocity = .{ 0, 0, 2 }, .gravity = .{ 0, 0, -20 }, .radius = 1 + random.next() * 0.5, .color = .{ 0.2, 0.55, 0.01 }, .alpha = 0.35, .shader = c.cgs.media.smokePuffShader });
}
