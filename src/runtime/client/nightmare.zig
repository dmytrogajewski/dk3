// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const W = @import("weapon_catalog").nightmare;
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t, client: i32) !void {
    if (entity.frame < 0 or entity.frame > @intFromEnum(W.Phase.after)) return;
    const phase: W.Phase = @enumFromInt(entity.frame);
    const age = @max(0, now - entity.time);
    if (phase == .casting and entity.otherEntityNum == client) {
        var pent = std.mem.zeroes(c.refEntity_t);
        pent.reType = c.RT_MODEL;
        pent.hModel = try @import("models.zig").register(W.visual.pentagram);
        pent.renderfx = c.RF_DEPTHHACK | c.RF_FIRST_PERSON | c.RF_MINLIGHT;
        pent.origin = v.add(ref.vieworg, v.scale(ref.viewaxis[0], 13));
        pent.oldorigin = pent.origin;
        for (&pent.axis, ref.viewaxis) |*axis, view| axis.* = v.scale(view, 1.6);
        pent.nonNormalizedAxes = c.qtrue;
        const duration = @max(100, entity.time2 - entity.time - 100);
        pent.frame = @intCast(@min(51, @divTrunc(@as(i64, age) * 62, duration)));
        pent.oldframe = pent.frame;
        pent.shaderRGBA = .{ 255, 255, 255, 204 };
        _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&pent});
    }
    if (phase != .reaping and phase != .after) return;
    var reaper = std.mem.zeroes(c.refEntity_t);
    reaper.reType = c.RT_MODEL;
    reaper.hModel = try @import("models.zig").register(W.spec.visual.projectile_model);
    reaper.origin = entity.pos.trBase;
    reaper.oldorigin = reaper.origin;
    const basis = v.basis(entity.apos.trBase);
    reaper.axis = .{ basis.forward, v.scale(basis.right, -1), v.cross(basis.forward, v.scale(basis.right, -1)) };
    reaper.frame = if (phase == .after) 43 else @min(43, @divTrunc(age, 100));
    reaper.oldframe = reaper.frame;
    reaper.shaderRGBA = @splat(255);
    _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&reaper});
    const scale = 2 + 4 * @abs(15 - 0.5 * @as(f32, @floatFromInt(reaper.frame))) / 14;
    @import("sprites.zig").draw(try @import("sprites.zig").register(W.visual.flame), 0, reaper.origin, scale, true, ref);
}
