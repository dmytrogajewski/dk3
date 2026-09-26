// SPDX-License-Identifier: GPL-2.0-or-later
//! Snapshot-owned area effects survive save restoration without replaying a blast.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const W = @import("weapon_catalog").hammer;
pub fn shake(entities: []const c.entityState_t, position: v.Vec3, now: i32) v.Vec3 {
    var angles: v.Vec3 = @splat(0);
    for (entities) |entity| {
        if (entity.eType != c.ET_DK3_EFFECT or entity.weapon != W.id or now >= entity.time2) continue;
        const strength = W.quakeStrength(v.length(v.subtract(position, entity.pos.trBase)), entity.time2 - now, entity.angles2[0], false);
        for (&angles, 0..) |*axis, index| {
            const phase = @as(f32, @floatFromInt(now - entity.time)) * 0.071 + @as(f32, @floatFromInt(entity.number)) + @as(f32, @floatFromInt(index)) * 1.7;
            axis.* += @sin(phase) * strength * (if (index == 1) @as(f32, 0.005) else 0.025);
        }
    }
    return angles;
}
pub fn draw(entity: c.entityState_t, now: i32) !void {
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
