// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const W = @import("weapon_catalog").metamaser;
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const sprites = @import("sprites.zig");
pub fn draw(entity: c.entityState_t, snapshot: []const c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    const origin = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    if (entity.eType == c.ET_DK3_EFFECT) {
        if (entity.frame == 11) {
            @import("beams.zig").draw("dk3/fx/ion-lightning", origin, entity.origin2, 6, .{ 64, 115, 255, 180 }, ref);
        } else if (entity.frame == 10) {
            const age = std.math.clamp(@as(f32, @floatFromInt(now - entity.time)) * 0.001, 0, 2);
            const axes = @import("../domain/poses.zig").axes(entity.apos.trBase);
            const ring_origin = v.add(origin, v.scale(axes[2], 5));
            const media = try sprites.register(W.visual.ring);
            for ([_]f32{ -1, 0, 1 }) |offset| {
                const angle = offset * age * 5 * (std.math.pi / 180.0);
                const right = v.add(v.scale(axes[0], @cos(angle)), v.scale(axes[1], @sin(angle)));
                const up = v.add(v.scale(axes[0], -@sin(angle)), v.scale(axes[1], @cos(angle)));
                sprites.drawPlane(media, 0, ring_origin, 1 + age * 8 + offset * (0.1 + age * 0.2), true, right, up, .{ 255, 255, 255, @intFromFloat(@min(1, 2 - age) * 255) });
            }
            if (age < 0.5) {
                const blast = try sprites.register(W.spec.visual.impact_sprite);
                sprites.draw(blast, @min(sprites.count(blast) - 1, @as(usize, @intFromFloat(age * 20))), origin, 6, true, ref);
            }
        }
        return;
    }
    if (entity.generic1 == 0) return;
    sprites.draw(try sprites.register(W.visual.flare), 0, origin, 0.3, true, ref);
    const targets = [_]i32{ entity.otherEntityNum, entity.otherEntityNum2, @intFromFloat(entity.origin2[0]), @intFromFloat(entity.origin2[1]) };
    for (targets) |slot| {
        if (slot == c.ENTITYNUM_NONE) continue;
        for (snapshot) |target| if (target.number == slot) {
            const end = @import("../engine/trajectory.zig").evaluate(target.pos, now);
            @import("beams.zig").draw("dk3/fx/ion-lightning", origin, end, 4, .{ 0, 0, 255, 153 }, ref);
            break;
        };
    }
}
