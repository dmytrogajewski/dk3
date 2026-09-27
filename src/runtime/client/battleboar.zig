// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
pub fn draw(parent: *const c.refEntity_t) !void {
    for ([_]f32{ -9, 9 }) |side| {
        var flash = std.mem.zeroes(c.refEntity_t);
        flash.reType = c.RT_MODEL;
        flash.hModel = try @import("models.zig").register("models/global/we_mflash.dkm");
        flash.origin = v.add(parent.origin, v.add(v.scale(parent.axis[0], 15), v.add(v.scale(parent.axis[1], side), v.scale(parent.axis[2], 14))));
        flash.oldorigin = flash.origin;
        flash.axis = parent.axis;
        flash.axis[1] = v.scale(flash.axis[1], 2);
        flash.axis[2] = v.scale(flash.axis[2], 2);
        flash.nonNormalizedAxes = c.qtrue;
        flash.shaderRGBA = @splat(255);
        flash.renderfx = c.RF_NOSHADOW;
        _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&flash});
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &flash.origin, engine.floatArg(120), engine.floatArg(0.6), engine.floatArg(0.4), engine.floatArg(0.4) });
    }
}
