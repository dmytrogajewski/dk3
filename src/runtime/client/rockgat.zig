// SPDX-License-Identifier: GPL-2.0-or-later
//! Class-bound muzzle model communicates the active chaingun burst.
const std = @import("std");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
pub fn draw(parent: *const c.refEntity_t) !void {
    var tag: c.orientation_t = undefined;
    if (engine.gateway.call(c.CG_R_LERPTAG, .{ &tag, @as(isize, parent.hModel), @as(isize, parent.frame), @as(isize, parent.frame), engine.floatArg(0), @as([*:0]const u8, "hr_muzzle") }) == 0) return error.MissingRockgatMuzzleTag;
    var flash = std.mem.zeroes(c.refEntity_t);
    flash.reType = c.RT_MODEL;
    flash.hModel = try @import("models.zig").register(@import("actor_catalog").rockgat.muzzle_model);
    flash.origin = parent.origin;
    for (parent.axis, tag.origin) |axis, offset| flash.origin = v.add(flash.origin, v.scale(axis, offset));
    flash.oldorigin = flash.origin;
    for (&flash.axis, tag.axis) |*axis, local| {
        axis.* = @splat(0);
        for (parent.axis, local) |basis, weight| axis.* = v.add(axis.*, v.scale(basis, weight));
    }
    flash.shaderRGBA = @splat(255);
    flash.renderfx = c.RF_NOSHADOW;
    _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&flash});
}
