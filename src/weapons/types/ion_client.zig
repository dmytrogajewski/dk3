// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const r = @import("../client/render.zig");
const c = r.c;
const v = r.v;
const p = @import("../client/particles.zig");
const Ring = struct { start: c_int = 0, active: bool = false, bounce: bool = false, scale: f32 = 1, origin: v.Vec = v.zero, angles: v.Vec = v.zero };
var rings: [32]Ring = @splat(.{});
var next_ring: usize = 0;
pub fn reset() void {
    rings = @splat(.{});
    next_ring = 0;
}
fn sparks(random: *p.Random, origin: v.Vec, direction: v.Vec, count: usize, speed: f32, spread: f32, minimum: f32, maximum: f32, terminal: bool, green: f32, alpha: f32) void {
    for (0..count) |_| {
        const width = minimum + random.next() * (maximum - minimum);
        var angles: v.Vec = undefined;
        c.vectoangles(&direction, &angles);
        angles[0] += (random.next() - 0.5) * spread;
        angles[1] += (random.next() - 0.5) * spread;
        var velocity: v.Vec = undefined;
        c.AngleVectors(&angles, &velocity, null, null);
        velocity = v.scale(velocity, speed);
        p.add(.{ .start = r.now(), .end = r.now() + @as(c_int, if (terminal) 833 else 800), .origin = origin, .velocity = velocity, .radius = width, .color = .{ 0, green, 0 }, .alpha = alpha, .streak = !terminal, .shader = c.trap_R_RegisterShader(if (terminal) "dk3/particle/ion-sparkle" else "dk3/fx/ion-spark") });
    }
}
pub fn draw(cent: *c.centity_t) void {
    var random = p.seed(cent.currentState.number, @divTrunc(r.now(), 16));
    const length = 24 + random.next() * 8;
    const rotation = @mod(v.f(r.now()) * 1.8, 360);
    var angles: v.Vec = undefined;
    c.vectoangles(&cent.currentState.pos.trDelta, &angles);
    angles[0] += rotation;
    angles[2] -= rotation;
    var axes: [3]v.Vec = undefined;
    c.AnglesToAxis(&angles, &axes);
    _ = r.sprite("models/e1/we_ionbf.sp2", 0, cent.lerpOrigin, angles, 0.8, 0.8, r.white, c.DK_SPRITE_ADDITIVE);
    const shader = c.trap_R_RegisterShader("dk3/fx/ion-lightning");
    for (0..4) |arm| {
        var previous = cent.lerpOrigin;
        for (1..5) |segment| {
            const fraction = v.f(segment) / 4;
            var point = v.madd(cent.lerpOrigin, (if ((arm & 1) != 0) -length else length) * fraction, axes[if (arm < 2) 0 else 2]);
            if (segment < 4) for (&point) |*axis| {
                axis.* += (random.next() - 0.5) * 6;
            };
            r.strip(previous, point, 6, .{ 0, 0.8, 0 }, 0.75 * (1 - v.f(segment - 1) / 4), shader);
            previous = point;
        }
    }
    c.trap_R_AddAdditiveLightToScene(&cent.lerpOrigin, 150 + random.next() * 300, 0, 0.8, 0);
    if (cent.trailTime > r.now() or cent.trailTime < r.now() - 100) cent.trailTime = r.now() - 33;
    while (cent.trailTime <= r.now() - 33) {
        cent.trailTime += 33;
        const lag = v.f(r.now() - cent.trailTime) / 1000;
        sparks(&random, v.madd(cent.lerpOrigin, -lag, cent.currentState.pos.trDelta), v.scale(v.normal(cent.currentState.pos.trDelta), -1), 4, 450, 5, 0.01, 0.3, false, 1, 0.8);
    }
}
pub fn impact(cent: *c.centity_t) void {
    const kind = cent.currentState.eventParm;
    var random = p.seed(cent.currentState.number, r.now());
    var direction = v.normal(cent.currentState.origin2);
    if (v.length(direction) == 0) direction = .{ 0, 0, 1 };
    switch (kind) {
        // Gold Proj_Ion_Special: wall bounce.
        0 => {
            sparks(&random, cent.lerpOrigin, direction, 10, 250, 120, 0.25, 0.5, false, 0.8, 0.75);
            var angles: v.Vec = undefined;
            c.vectoangles(&direction, &angles);
            angles[0] += 90;
            add(.{ .start = r.now(), .active = true, .bounce = true, .scale = 0.75 + random.next() * 0.5, .origin = v.madd(cent.lerpOrigin, 0.5, direction), .angles = angles });
        },
        // Gold Proj_Ion_Die: normal burst, or the water discharge rings.
        1 => sparks(&random, cent.lerpOrigin, direction, 25, 450, 180, 0.5, 1.0, true, 0.8, 0.75),
        else => {
            sparks(&random, cent.lerpOrigin, direction, 25, 450, 180, 0.75, 1.25, true, 0.8, 0.75);
            add(.{ .start = r.now(), .active = true, .origin = cent.lerpOrigin, .angles = cent.currentState.angles });
        },
    }
}
fn add(ring: Ring) void {
    rings[next_ring] = ring;
    next_ring = (next_ring + 1) % rings.len;
}
pub fn frame() void {
    for (&rings) |*ring| {
        if (!ring.active) continue;
        const age = r.now() - ring.start;
        if (age < 0 or age >= 200) {
            ring.active = false;
            continue;
        }
        const t = v.f(age) / 200;
        var model = std.mem.zeroes(c.refEntity_t);
        model.reType = c.RT_MODEL;
        model.origin = ring.origin;
        model.nonNormalizedAxes = c.qtrue;
        if (ring.bounce) {
            model.hModel = c.DK_RegisterModel("models/global/we_ioexp.dkm");
            model.skinNum = 1;
            c.AnglesToAxis(&ring.angles, &model.axis);
            for (&model.axis) |*axis| axis.* = v.scale(axis.*, ring.scale);
            model.shaderRGBA = .{ 255, 255, 255, 204 };
            c.trap_R_AddRefEntityToScene(&model);
            continue;
        }
        model.hModel = c.DK_RegisterModel("models/e1/we_ionexp.dkm");
        model.shaderRGBA = .{ 255, 255, 255, r.byte(1.1 * (1 - t)) };
        const scale = 0.0005 + 2 * t;
        for (0..2) |copy| {
            if (copy == 0) c.AnglesToAxis(&ring.angles, &model.axis) else model.axis = r.identity;
            for (&model.axis) |*axis| axis.* = v.scale(axis.*, scale);
            c.trap_R_AddRefEntityToScene(&model);
        }
        r.light(ring.origin, 200, .{ 0, 1, 0 });
    }
}
