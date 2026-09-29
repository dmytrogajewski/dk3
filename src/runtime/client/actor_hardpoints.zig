// SPDX-License-Identifier: GPL-2.0-or-later
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
pub fn point(model: *const c.refEntity_t, name: [*:0]const u8) !v.Vec3 {
    return (try transform(model, name)).origin;
}
pub fn transform(model: *const c.refEntity_t, name: [*:0]const u8) !c.orientation_t {
    var tag: c.orientation_t = undefined;
    if (engine.gateway.call(c.CG_R_LERPTAG, .{ &tag, @as(isize, model.hModel), @as(isize, model.oldframe), @as(isize, model.frame), engine.floatArg(1 - model.backlerp), name }) == 0) return error.MissingAuthoredActorHardpoint;
    var origin = model.origin;
    for (model.axis, tag.origin) |axis, offset| origin = v.add(origin, v.scale(axis, offset));
    var result: c.orientation_t = .{ .origin = origin, .axis = undefined };
    for (&result.axis, tag.axis) |*destination, local| {
        destination.* = .{ 0, 0, 0 };
        for (model.axis, local) |axis, amount| destination.* = v.add(destination.*, v.scale(axis, amount));
    }
    return result;
}
