// SPDX-License-Identifier: GPL-2.0-or-later
//! Animated sword/eye attachments shared by the two authored Daikatana bosses.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const sprites = @import("sprites.zig");
const Random = @import("../domain/components.zig").Random;
const State = struct { serial: i32 = -1, next_ms: i64 = 0, eye_frame: u8 = 0, fraction: f32 = 0 };
var states: [2048]State = @splat(.{});
pub fn reset() void {
    states = @splat(.{});
}
pub fn draw(model: *const c.refEntity_t, entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    if (entity.number < 0 or entity.number >= states.len) return error.InvalidSwordAuraEntity;
    const state = &states[@intCast(entity.number)];
    if (state.serial != entity.time or state.next_ms > @as(i64, now) + 50) state.* = .{ .serial = entity.time, .next_ms = now };
    var random: Random = .{ .state = @as(u32, @bitCast(@divTrunc(now, 50))) ^ (@as(u32, @intCast(entity.number)) *% 2654435761) };
    state.next_ms = @max(state.next_ms, @as(i64, now) - 250);
    while (state.next_ms <= now) : (state.next_ms += 50) {
        const previous = state.eye_frame;
        state.eye_frame += 1;
        if (@as(f32, @floatFromInt(previous)) > 75 + 50 * random.next()) state.eye_frame = 0;
        state.fraction += 0.04;
        if (state.fraction > 1) state.fraction = -1;
    }
    const color: v.Vec3 = if (entity.legsAnim == 0) .{ 1, 0.1, 0.1 } else @splat(0.65);
    const flare = try sprites.register("models/global/e_flare4+.sp2");
    var handle = try @import("actor_hardpoints.zig").point(model, "sword1");
    var tip = try @import("actor_hardpoints.zig").point(model, "sword2");
    const direction = v.normalize(v.subtract(tip, handle));
    handle = v.add(handle, v.scale(direction, -2.2));
    tip = v.add(tip, v.scale(direction, 2.2));
    if (state.eye_frame > 50) {
        const eye = try sprites.register("models/global/e_flare4xo.sp2");
        for ([_][*:0]const u8{ "eye1", "eye2" }) |name| {
            const point = v.add(try @import("actor_hardpoints.zig").point(model, name), v.normalize(model.axis[0]));
            sprites.drawPlane(eye, 0, point, 0.08, false, v.scale(v.normalize(model.axis[1]), -1), v.normalize(model.axis[2]), rgba(color, 0.6));
        }
    }
    var side = v.cross(direction, .{ 0, 0, 1 });
    if (v.length(side) < 0.01) side = .{ 1, 0, 0 };
    side = v.normalize(side);
    const up = v.cross(side, direction);
    const angle = random.next() * std.math.pi / 2;
    for (0..4) |i| {
        const phase = angle + @as(f32, @floatFromInt(i)) * std.math.pi / 2;
        const base = v.add(handle, v.scale(v.add(v.scale(side, @cos(phase)), v.scale(up, @sin(phase))), random.next()));
        var tint = color;
        for (&tint) |*channel| channel.* += 0.4 * (random.next() * 2 - 1);
        tint = v.normalize(tint);
        const alpha = 0.6 * (1 + 0.2 * (random.next() * 2 - 1));
        const width = 0.8 * (1 + 0.2 * (random.next() * 2 - 1));
        const modulation = 0.5 * (1 + 0.9 * (random.next() * 2 - 1));
        var previous = base;
        for (1..9) |segment| {
            const fraction = @as(f32, @floatFromInt(segment)) / 8;
            var next = v.add(base, v.scale(v.subtract(tip, base), fraction));
            if (segment < 8) next = v.add(next, v.add(v.scale(side, modulation * (random.next() * 2 - 1)), v.scale(up, modulation * (random.next() * 2 - 1))));
            @import("beams.zig").draw("dk3/fx/ion-lightning", previous, next, width, rgba(tint, alpha * (1 - fraction)), ref);
            previous = next;
        }
    }
    for ([_]v.Vec3{ handle, tip }) |point| _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &point, engine.floatArg(100 + 20 * random.next()), engine.floatArg(entity.origin2[0]), engine.floatArg(entity.origin2[1]), engine.floatArg(entity.origin2[2]) });
    crossed(flare, tip, 0.075 + 0.075 * random.next(), rgba(color, 0.6), &random);
    if (state.fraction >= 0) crossed(flare, v.add(handle, v.scale(v.subtract(tip, handle), state.fraction)), 0.05 + 0.05 * random.next(), rgba(@splat(1), 0.6), &random);
    const scale: f32 = if (entity.legsAnim == 0) 0.3 else 0.2;
    sprites.drawPlane(flare, 0, handle, scale, false, v.scale(ref.viewaxis[1], -1), ref.viewaxis[2], rgba(@splat(1), 0.2));
    sprites.drawPlane(flare, 0, handle, scale, false, side, up, rgba(@splat(1), 0.2));
}
fn crossed(sprite: u8, point: v.Vec3, scale: f32, color: [4]u8, random: *Random) void {
    for ([_]v.Vec3{ .{ 0, 0, 0 }, .{ 0, 90, 0 } }) |angles| {
        var turned = angles;
        turned[2] = 180 * random.next();
        const basis = v.basis(turned);
        sprites.drawPlane(sprite, 0, point, scale, false, basis.right, v.cross(basis.right, basis.forward), color);
    }
}
fn rgba(color: v.Vec3, alpha: f32) [4]u8 {
    var output: [4]u8 = undefined;
    for (color ++ .{alpha}, &output) |channel, *byte| byte.* = @intFromFloat(std.math.clamp(channel, 0, 1) * 255);
    return output;
}
