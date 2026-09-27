// SPDX-License-Identifier: GPL-2.0-or-later
//! The camera's yellow/red lamp communicates acquisition state.
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").cambot;
pub fn draw(parent: *const c.refEntity_t, entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    const alert = entity.time2 == policy.alert_tag;
    var tag: c.orientation_t = undefined;
    if (engine.gateway.call(c.CG_R_LERPTAG, .{ &tag, @as(isize, parent.hModel), @as(isize, parent.oldframe), @as(isize, parent.frame), engine.floatArg(1 - parent.backlerp), @as([*:0]const u8, "hr_light") }) == 0) return error.MissingCambotLightTag;
    var point = parent.origin;
    for (parent.axis, tag.origin) |axis, offset| point = v.add(point, v.scale(axis, offset));
    const sprite = try @import("sprites.zig").register(if (alert) policy.alert_light else policy.idle_light);
    @import("sprites.zig").draw(sprite, 0, point, 3, true, ref);
    const light = policy.searchlight;
    const color = if (alert) light.alert_color else light.idle_color;
    _ = engine.gateway.call(c.CG_R_ADDADDITIVELIGHTTOSCENE, .{ &point, engine.floatArg(225), engine.floatArg(color[0]), engine.floatArg(color[1]), engine.floatArg(color[2]) });
    const sweep = @mod(@as(f32, @floatFromInt(now - entity.dk3AnimationStart)) * light.sweep_rate, light.sweep_span * 2);
    var angles = @import("../engine/trajectory.zig").evaluate(entity.apos, now);
    angles[0] = light.pitch;
    angles[1] += -45 + if (sweep <= light.sweep_span) sweep else light.sweep_span * 2 - sweep;
    const direction = if (alert) v.normalize(v.subtract(entity.origin2, point)) else v.basis(angles).forward;
    const hit = try engine.collisionService().trace(.{ .start = point, .end = v.add(point, v.scale(direction, light.reach)), .mins = @splat(0), .maxs = @splat(0), .slot = @intCast(entity.number), .mask = c.MASK_SOLID });
    try @import("spotlights.zig").cone(point, hit.end, light.radius, color);
}
