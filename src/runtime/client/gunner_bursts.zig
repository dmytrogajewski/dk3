// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").gunners;
pub fn draw(game: *const c.gameState_t, effect: c.entityState_t, entities: []const c.entityState_t, now: i32) !void {
    const kind = std.enums.fromInt(policy.BurstKind, effect.weapon) orelse return error.InvalidGunnerBurst;
    if (kind == .uzi and @mod(effect.time2, 2) != 0) return;
    var parent: ?c.entityState_t = null;
    for (entities) |candidate| if (candidate.number == effect.otherEntityNum) {
        parent = candidate;
        break;
    };
    const owner = parent orelse return;
    const axes = v.basis(@import("../engine/trajectory.zig").evaluate(owner.apos, now));
    const origin = @import("../engine/trajectory.zig").evaluate(owner.pos, now);
    const basis = [3]v.Vec3{ axes.forward, v.scale(axes.right, -1), v.cross(axes.forward, v.scale(axes.right, -1)) };
    const parent_model = try @import("models.zig").get(game, owner.modelindex);
    const count: usize = if (kind == .commando and effect.frame == 1) 2 else 1;
    for (0..count) |i| {
        var flash = std.mem.zeroes(c.refEntity_t);
        flash.reType = c.RT_MODEL;
        flash.hModel = try @import("models.zig").register(policy.flash_model);
        flash.origin = origin;
        flash.axis = basis;
        if (kind == .uzi) {
            flash.origin = v.add(origin, v.add(v.scale(axes.forward, 20), v.add(v.scale(axes.right, 6), v.scale(basis[2], 25))));
            flash.axis[1] = v.scale(flash.axis[1], 2);
            flash.axis[2] = v.scale(flash.axis[2], 2);
            _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &flash.origin, engine.floatArg(120), engine.floatArg(0.6), engine.floatArg(0.4), engine.floatArg(0.4) });
        } else {
            const name: [*:0]const u8 = if (kind == .commando and (count == 1 or i == 1)) "hr_muzzle2" else "hr_muzzle1";
            var tag: c.orientation_t = undefined;
            if (engine.gateway.call(c.CG_R_LERPTAG, .{ &tag, @as(isize, parent_model), @as(isize, owner.frame), @as(isize, owner.frame), engine.floatArg(0), name }) == 0) return error.MissingGunnerMuzzleTag;
            for (basis, tag.origin, owner.angles2) |axis, offset, scale| flash.origin = v.add(flash.origin, v.scale(axis, offset * scale));
            for (&flash.axis, tag.axis) |*axis, local| {
                axis.* = @splat(0);
                for (basis, local) |direction, weight| axis.* = v.add(axis.*, v.scale(direction, weight));
                axis.* = v.scale(axis.*, if (kind == .shotgun) 2.05 else 1.05);
            }
        }
        flash.nonNormalizedAxes = c.qtrue;
        flash.oldorigin = flash.origin;
        flash.shaderRGBA = @splat(255);
        flash.renderfx = c.RF_NOSHADOW;
        _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&flash});
    }
}
