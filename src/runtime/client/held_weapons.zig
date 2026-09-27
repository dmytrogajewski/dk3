// SPDX-License-Identifier: GPL-2.0-or-later
//! Ordinary remote and companion weapons use their class-owned equipped model.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
var handles: [32]c.qhandle_t = @splat(0);
pub fn reset() void {
    handles = @splat(0);
}
pub fn draw(parent: *const c.refEntity_t, weapon: i32) !void {
    if (weapon < 1 or weapon >= handles.len) return;
    const entry = @import("weapon_catalog").find(@intCast(weapon)) orelse return error.UnknownRemoteWeapon;
    if (!entry.spec.equipped) return;
    const path = entry.spec.world_model orelse return error.MissingEquippedWeaponModel;
    const index: usize = @intCast(weapon);
    if (handles[index] == 0) {
        handles[index] = try @import("models.zig").register(path);
        if (handles[index] == 0) return error.EquippedWeaponModelUnavailable;
    }
    var model = std.mem.zeroes(c.refEntity_t);
    model.reType = c.RT_MODEL;
    model.hModel = handles[index];
    model.origin = try @import("actor_hardpoints.zig").point(parent, "hp_gun");
    model.oldorigin = model.origin;
    model.axis = parent.axis;
    model.nonNormalizedAxes = parent.nonNormalizedAxes;
    model.frame = entry.spec.equipped_frame;
    model.oldframe = model.frame;
    model.renderfx = c.RF_MINLIGHT;
    model.shaderRGBA = parent.shaderRGBA;
    model.skinNum = if (model.shaderRGBA[3] < 255) 1 else 0;
    _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&model});
}
