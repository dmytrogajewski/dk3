// SPDX-License-Identifier: GPL-2.0-or-later
//! Dragon breath and fireball particles. Emission uses 60 Hz simulation rather than
//! depending on display refresh; particles retain their own muzzle-space birth pose.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const Random = @import("../domain/components.zig").Random;
const Emitter = struct { serial: i32 = -1, next_tick: i64 = 0 };
var emitters: [2048]Emitter = @splat(.{});
pub fn reset() void {
    emitters = @splat(.{});
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
            @import("fx_particles.zig").cloud(point, direction, .{ 0, 0, 0 }, .{ 0.75, 0.35, 0.05 }, 4.25 + random.next() * 6.5, 4, 2, 200, .{ -direction[0] * 50, -direction[1] * 50, 0 }, 1, .smoke, at, &random);
            @import("fx_particles.zig").cloud(point, direction, .{ 0.7 + (random.next() * 2 - 1) * 0.15, 0.35 + (random.next() * 2 - 1) * 0.15, 0.05 }, .{ 0.65, 0.25, 0.1 }, 3 + random.next() * 8, 10, 2, 250, @splat(0), 0, .fire, at, &random);
        } else {
            @import("fx_particles.zig").cloud(point, direction, .{ 0.55, 0.3, 0.05 }, .{ 0.85, 0.45, 0.2 }, 6.25 + random.next() * 6.5, 4, 2, 400, @splat(0), 10, .fire, at, &random);
            @import("fx_particles.zig").cloud(point, direction, .{ 0.4, 0.15, 0.05 }, .{ 0.75, 0.45, 0.2 }, 2.75 + random.next() * 0.75, 2, 5, 375, @splat(0), 0, .smoke, at, &random);
        }
    }
}
