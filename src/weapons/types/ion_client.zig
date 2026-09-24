// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const r = @import("../client/render.zig");
const c = r.c;
const v = r.v;
const p = @import("../client/particles.zig");
const Ring = struct { start: c_int = 0, active: bool = false, origin: v.Vec = v.zero, angles: v.Vec = v.zero };
var rings: [32]Ring = @splat(.{});
var next_ring: usize = 0;
pub fn reset() void {
    rings = @splat(.{});
    next_ring = 0;
}
fn sparks(random: *p.Random, origin: v.Vec, direction: v.Vec, count: usize, speed: f32, spread: f32, minimum: f32, maximum: f32, terminal: bool) void {
    for (0..count) |_| {
        const width = minimum + random.next() * (maximum - minimum);
        var angles: v.Vec = undefined;
        c.vectoangles(&direction, &angles);
        angles[0] += (random.next() - 0.5) * spread;
        angles[1] += (random.next() - 0.5) * spread;
        var velocity: v.Vec = undefined;
        c.AngleVectors(&angles, &velocity, null, null);
        velocity = v.scale(velocity, speed);
        p.add(.{ .start = r.now(), .end = r.now() + @as(c_int, if (terminal) 833 else 800), .origin = origin, .velocity = velocity, .radius = width, .color = .{ 0, if (terminal) 0.8 else 1, 0 }, .alpha = if (terminal) 0.75 else 0.8, .streak = !terminal, .shader = c.trap_R_RegisterShader(if (terminal) "dk3/particle/ion-sparkle" else "dk3/fx/ion-spark") });
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
        sparks(&random, v.madd(cent.lerpOrigin, -lag, cent.currentState.pos.trDelta), v.scale(v.normal(cent.currentState.pos.trDelta), -1), 4, 450, 5, 0.01, 0.3, false);
    }
}
pub fn impact(cent: *c.centity_t) void {
    const kind = cent.currentState.eventParm;
    var random = p.seed(cent.currentState.number, r.now());
    if (kind == 2) {
        rings[next_ring] = .{ .start = r.now(), .active = true, .origin = cent.lerpOrigin, .angles = cent.currentState.angles };
        next_ring = (next_ring + 1) % rings.len;
    }
    var direction = v.normal(cent.currentState.origin2);
    if (v.length(direction) == 0) direction = .{ 0, 0, 1 };
    sparks(&random, cent.lerpOrigin, direction, if (kind == 0) 10 else 25, if (kind == 0) 250 else 450, if (kind == 0) 120 else 360, if (kind == 0) 0.25 else 0.75, if (kind == 0) 0.5 else 1.5, kind != 0);
    if (kind == 0) {
        const effect: *c.localEntity_t = c.CG_AllocLocalEntity();
        const model = &effect.refEntity;
        const scale = 0.75 + random.next() * 0.5;
        effect.leType = c.LE_FADE_RGB;
        effect.startTime = r.now();
        effect.endTime = r.now() + 150;
        effect.lifeRate = 1.0 / 150.0;
        model.reType = c.RT_MODEL;
        model.hModel = c.DK_RegisterModel("models/global/we_ioexp.dkm");
        model.skinNum = 1;
        var angles: v.Vec = undefined;
        c.vectoangles(&direction, &angles);
        angles[0] += 90;
        c.AnglesToAxis(&angles, &model.axis);
        model.nonNormalizedAxes = c.qtrue;
        model.origin = v.madd(cent.lerpOrigin, 0.5, direction);
        for (&model.axis) |*axis| axis.* = v.scale(axis.*, scale);
        effect.color = .{ 1, 1, 1, 0.8 };
        model.shaderRGBA = .{ 255, 255, 255, 204 };
    }
}
pub fn frame() void {
    for (&rings) |*ring| {
        if (!ring.active) continue;
        const age = v.f(r.now() - ring.start) / 1000;
        if (age < 0 or age >= 2) {
            ring.active = false;
            continue;
        }
        for (0..2) |plane| {
            var model = std.mem.zeroes(c.refEntity_t);
            model.reType = c.RT_MODEL;
            model.hModel = c.DK_RegisterModel("models/e1/we_ionexp.dkm");
            model.origin = ring.origin;
            if (plane != 0) model.axis = c.cg.refdef.viewaxis else c.AnglesToAxis(&ring.angles, &model.axis);
            for (&model.axis) |*axis| axis.* = v.scale(axis.*, 0.05 + age);
            model.nonNormalizedAxes = c.qtrue;
            model.shaderRGBA = .{ 0, 255, 0, r.byte(@max(0, @min(0.2, 0.2 - age * 0.1))) };
            c.trap_R_AddRefEntityToScene(&model);
        }
    }
}
