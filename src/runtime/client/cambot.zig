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
    @import("sprites.zig").drawPlane(sprite, 0, point, policy.lighting.flare_scale, true, v.scale(ref.viewaxis[1], -1), ref.viewaxis[2], .{ 255, 255, 255, policy.lighting.flare_alpha });
    const light = policy.searchlight;
    const color = if (alert) light.alert_color else light.idle_color;
    const lighting = policy.lighting;
    _ = engine.gateway.call(c.CG_R_ADDADDITIVELIGHTTOSCENE, .{ &point, engine.floatArg(lighting.emitter_radius), engine.floatArg(color[0] * lighting.emitter_gain), engine.floatArg(color[1] * lighting.emitter_gain), engine.floatArg(color[2] * lighting.emitter_gain) });
    const sweep = @mod(@as(f32, @floatFromInt(now - entity.dk3AnimationStart)) * light.sweep_rate, light.sweep_span * 2);
    var angles = @import("../engine/trajectory.zig").evaluate(entity.apos, now);
    angles[0] = light.pitch;
    angles[1] += -45 + if (sweep <= light.sweep_span) sweep else light.sweep_span * 2 - sweep;
    const direction = if (alert) v.normalize(v.subtract(entity.origin2, point)) else v.basis(angles).forward;
    const hit = try engine.collisionService().trace(.{ .start = point, .end = v.add(point, v.scale(direction, light.reach)), .mins = @splat(0), .maxs = @splat(0), .slot = @intCast(entity.number), .mask = c.MASK_SOLID });
    if (hit.start_solid or hit.all_solid) return;
    try @import("spotlights.zig").beam(point, hit.end, light.radius, color, lighting.beam_alpha);
    if (hit.fraction < 1 and !hit.sky) {
        const distance = v.length(v.subtract(hit.end, point));
        const ratio = distance / lighting.falloff_distance;
        const gain = lighting.surface_gain / (1 + ratio * ratio);
        const radius = @min(lighting.maximum_radius, @max(lighting.minimum_radius, light.radius + distance * 0.2));
        // Keep the light on the visible side of the contacted surface, and
        // submit none at the end of a ray that hits only open air or sky.
        const pool = v.add(hit.end, v.scale(hit.normal, lighting.surface_offset));
        _ = engine.gateway.call(c.CG_R_ADDADDITIVELIGHTTOSCENE, .{ &pool, engine.floatArg(radius), engine.floatArg(color[0] * gain), engine.floatArg(color[1] * gain), engine.floatArg(color[2] * gain) });
    }
}
