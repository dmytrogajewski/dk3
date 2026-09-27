// SPDX-License-Identifier: GPL-2.0-or-later
//! The camera's yellow/red lamp communicates acquisition state.
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").cambot;
pub fn draw(parent: *const c.refEntity_t, alert: bool, ref: *const c.refdef_t) !void {
    var tag: c.orientation_t = undefined;
    if (engine.gateway.call(c.CG_R_LERPTAG, .{ &tag, @as(isize, parent.hModel), @as(isize, parent.frame), @as(isize, parent.frame), engine.floatArg(0), @as([*:0]const u8, "hr_light") }) == 0) return error.MissingCambotLightTag;
    var point = parent.origin;
    for (parent.axis, tag.origin) |axis, offset| point = v.add(point, v.scale(axis, offset));
    const sprite = try @import("sprites.zig").register(if (alert) policy.alert_light else policy.idle_light);
    @import("sprites.zig").draw(sprite, 0, point, 3, true, ref);
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &point, engine.floatArg(225), engine.floatArg(0.65), engine.floatArg(if (alert) @as(f32, 0.15) else 0.65), engine.floatArg(0.15) });
}
