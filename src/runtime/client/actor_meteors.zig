// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const sprites = @import("sprites.zig");
const Random = @import("../domain/components.zig").Random;
var emitters: [2048]struct { serial: i32 = -1, next: i64 = 0, impact: bool = false } = @splat(.{});
pub fn reset() void {
    emitters = @splat(.{});
}
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !bool {
    const point = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    if (entity.weapon == 2) {
        const angle = @import("../engine/trajectory.zig").evaluate(entity.apos, now)[2] * std.math.pi / 180;
        const right = v.add(v.scale(ref.viewaxis[1], -@cos(angle)), v.scale(ref.viewaxis[2], @sin(angle)));
        const up = v.add(v.scale(ref.viewaxis[1], @sin(angle)), v.scale(ref.viewaxis[2], @cos(angle)));
        const sprite = try sprites.register("models/e3/we_blackhole.sp2");
        sprites.drawPlane(sprite, @min(10, sprites.count(sprite) - 1), point, entity.angles2[0], false, right, up, .{ 255, 255, 255, 191 });
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &point, engine.floatArg(@max(0, 300 - @as(f32, @floatFromInt(now - entity.time)) * 0.3)), engine.floatArg(-1), engine.floatArg(-0.5), engine.floatArg(-0.5) });
        return true;
    }
    if (entity.weapon == 3) {
        try explosion(entity, point, now, ref);
        return true;
    }
    if (entity.weapon < 0 or entity.weapon > 1) return error.InvalidMeteorProjection;
    sprites.draw(try sprites.register("models/e3/we_fglow.sp2"), 0, point, entity.origin2[0], false, ref);
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &point, engine.floatArg(if (entity.weapon == 0) @as(f32, 100) else 125), engine.floatArg(if (entity.weapon == 0) @as(f32, 0.55) else 0.85), engine.floatArg(0.35), engine.floatArg(0.15) });
    if (entity.number >= 0 and entity.number < emitters.len) {
        const emitter = &emitters[@intCast(entity.number)];
        const tick = @divTrunc(@as(i64, now) * 60, 1000);
        if (emitter.serial != entity.time or emitter.next > tick + 1) emitter.* = .{ .serial = entity.time, .next = tick };
        emitter.next = @max(emitter.next, tick - 5);
        while (emitter.next <= tick) : (emitter.next += 1) {
            const at: i32 = @intCast(@divTrunc(emitter.next * 1000, 60));
            var random: Random = .{ .state = @as(u32, @bitCast(at)) ^ (@as(u32, @intCast(entity.number)) *% 2654435761) };
            const old = v.subtract(point, v.scale(entity.pos.trDelta, 0.035));
            const direction = v.normalize(.{ random.next() * 2 - 1, random.next() * 2 - 1, random.next() * 2 - 1 });
            @import("fx_particles.zig").cloud(old, direction, .{ 0.85, 0.15, 0.05 }, .{ 0.75, 0.95, 0.1 }, 1 + random.next(), 5, 360, 150, .{ 0, 0, -20 }, 0, .fire, at, &random);
            const other = v.normalize(.{ random.next() * 2 - 1, random.next() * 2 - 1, random.next() * 2 - 1 });
            @import("fx_particles.zig").cloud(old, other, .{ 0.85, 0.15, 0.05 }, .{ 0.65, 1.45, 0.1 }, 4 + random.next() * 2, 5, 360, 200, .{ random.next() * 40 - 10, random.next() * 40 - 10, random.next() * 40 - 10 }, 0, .fire, at, &random);
        }
    }
    return false;
}
fn explosion(entity: c.entityState_t, point: v.Vec3, now: i32, ref: *const c.refdef_t) !void {
    const age = now - entity.time;
    if (age < 0) return;
    const scale = entity.angles2[0];
    const normal = v.normalize(entity.origin2);
    const orientation: v.Vec3 = .{ -std.math.atan2(normal[2], @sqrt(normal[0] * normal[0] + normal[1] * normal[1])) * 180 / std.math.pi, std.math.atan2(normal[1], normal[0]) * 180 / std.math.pi, 0 };
    const axes = v.basis(orientation);
    if (age < 200) {
        const fraction = @as(f32, @floatFromInt(age)) / 200;
        const sprite = try sprites.register("models/global/we_expdisc.sp2");
        sprites.drawPlane(sprite, 0, point, scale * (0.001 + (4 - 0.001) * fraction), false, axes.right, v.cross(axes.right, axes.forward), .{ 255, 255, 255, @intFromFloat(std.math.clamp(1.1 * (1 - fraction), 0, 1) * 255) });
    }
    if (age < 300) {
        const fraction = @as(f32, @floatFromInt(age)) / 300;
        const size = scale * (0.001 + (8 - 0.001) * fraction);
        var model = std.mem.zeroes(c.refEntity_t);
        model.reType = c.RT_MODEL;
        model.hModel = try @import("models.zig").register("models/global/we_expball.dkm");
        model.origin = point;
        model.oldorigin = point;
        const basis = v.basis(v.cross(axes.right, axes.forward));
        model.axis = .{ v.scale(basis.forward, size), v.scale(basis.right, -size), v.scale(v.cross(basis.right, basis.forward), size) };
        model.nonNormalizedAxes = c.qtrue;
        model.skinNum = 3;
        model.shaderRGBA = .{ 255, 255, 255, @intFromFloat(std.math.clamp(1.1 * (1 - fraction), 0, 1) * 255) };
        _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&model});
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &point, engine.floatArg(@as(f32, @floatFromInt(entity.time2)) * (1 - fraction)), engine.floatArg(0.85), engine.floatArg(0.35), engine.floatArg(0.15) });
    }
    if (entity.number >= 0 and entity.number < emitters.len) {
        const state = &emitters[@intCast(entity.number)];
        if (state.serial != entity.time) state.* = .{ .serial = entity.time };
        if (state.impact) return;
        state.impact = true;
        if (age > 300) return;
        if (entity.otherEntityNum != 0) _ = try @import("impacts.zig").decal(point, normal, 16, "models/global/we_scorch.sp2/0@mark", 0, entity.time);
        var random: Random = .{ .state = @as(u32, @bitCast(entity.time)) ^ (@as(u32, @intCast(entity.number)) *% 2654435761) };
        @import("fx_particles.zig").cloud(point, normal, .{ 0.65, 0.635, 0.15 }, .{ 0.75, 0.75, 0.1 }, 2 + random.next() * 0.75, 5, 35, 150, .{ random.next() * 40 - 10, random.next() * 40 - 10, random.next() * 40 - 10 }, 0, .fire, entity.time, &random);
        @import("fx_particles.zig").cloud(point, normal, @splat(0.01), .{ 0.75, 0.65, 0.1 }, 5, 10, 65, 150, .{ 0, 0, 50 + random.next() * 20 }, 0, .smoke, entity.time, &random);
    }
    _ = ref;
}
