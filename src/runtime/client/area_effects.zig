// SPDX-License-Identifier: GPL-2.0-or-later
//! Snapshot-owned area effects survive save restoration without replaying a blast.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const W = @import("weapon_catalog").hammer;
const S = @import("weapon_catalog").shockwave;
pub fn shake(entities: []const c.entityState_t, position: v.Vec3, now: i32) v.Vec3 {
    var angles: v.Vec3 = @splat(0);
    for (entities) |entity| {
        if (entity.eType != c.ET_DK3_EFFECT) continue;
        const strength = if (entity.weapon == W.id) W.quakeStrength(v.length(v.subtract(position, entity.pos.trBase)), entity.time2 - now, entity.angles2[0], false) else if (entity.weapon == S.id) blk: {
            const distance = v.length(v.subtract(position, entity.pos.trBase)) * 0.7;
            const minimum = @max(0, @as(f32, @floatFromInt(now - entity.time2 - 50)) * (350.0 / 3000.0) - 20);
            break :blk @max(0, 350 - distance) * 0.2 * (if (minimum >= 200) std.math.clamp((350 - minimum) / 150, 0, 1) else 1);
        } else continue;
        for (&angles, 0..) |*axis, index| {
            const phase = @as(f32, @floatFromInt(now - entity.time)) * 0.071 + @as(f32, @floatFromInt(entity.number)) + @as(f32, @floatFromInt(index)) * 1.7;
            const scale: f32 = if (entity.weapon == S.id) (if (index == 0) 0.01 else if (index == 1) 0.005 else 0.05) else if (index == 1) 0.005 else 0.025;
            axis.* += @sin(phase) * strength * scale;
        }
    }
    return angles;
}
pub fn draw(entity: c.entityState_t, now: i32) !void {
    if (entity.weapon == S.id) return shockwave(entity, now);
    if (entity.weapon != W.id) return;
    const age = now - entity.time;
    if (age < 0 or age > 1125) return;
    const sprites = @import("sprites.zig");
    const visual = W.quake_visual;
    const media = try sprites.register(visual.sprite);
    for (0..visual.rings) |index| {
        const duration: f32 = visual.duration_ms + @as(f32, @floatFromInt(index)) * visual.duration_step_ms;
        const fraction = @as(f32, @floatFromInt(age)) / duration;
        if (fraction >= 1) continue;
        const position = v.add(entity.pos.trBase, .{ 0, 0, -11 + @as(f32, @floatFromInt(index)) * 1.5 });
        sprites.drawPlane(media, 0, position, visual.start_scale + fraction * (visual.end_scale - visual.start_scale), false, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 255, 255, 255, visual.alpha });
    }
}
fn shockwave(entity: c.entityState_t, now: i32) !void {
    if (entity.frame < 1 or entity.frame > 6) return error.InvalidWaveProjection;
    const sprites = @import("sprites.zig");
    const engine = @import("../engine/client.zig");
    const visual = S.ring_visual;
    const media = try sprites.register(visual.sprite);
    for (0..@intCast(entity.frame)) |index| {
        const offset = if (index < 3) entity.angles2[index] else entity.origin2[index - 3];
        const age = @as(f32, @floatFromInt(now - entity.time)) - offset;
        if (age < 0 or age >= visual.duration_ms) continue;
        var random: @import("../domain/components.zig").Random = .{ .state = @as(u32, @bitCast(entity.generic1)) +% @as(u32, @intCast(index)) *% 7919 };
        var angles: v.Vec3 = undefined;
        for (&angles) |*axis| {
            const start = random.next() * 180 - 90;
            axis.* = start + (70 + (random.next() * 2 - 1) * 270) * age * 0.001;
        }
        const basis = v.basis(angles);
        sprites.drawPlane(media, 0, entity.pos.trBase, visual.start_scale + (visual.end_scale - visual.start_scale) * age / visual.duration_ms, false, v.scale(basis.right, -1), v.cross(basis.right, basis.forward), .{ 255, 255, 255, visual.alpha });
    }
    const remaining = std.math.clamp(1 - @as(f32, @floatFromInt(now - entity.time)) / 3000, 0, 1) * 0.5;
    if (remaining > 0) _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &entity.pos.trBase, engine.floatArg(500), engine.floatArg(0.2 * remaining), engine.floatArg(0.2 * remaining), engine.floatArg(remaining) });
}
