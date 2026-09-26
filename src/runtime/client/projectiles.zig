// SPDX-License-Identifier: GPL-2.0-or-later
const catalog = @import("weapon_catalog");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub fn decorate(rendered: *c.refEntity_t, entity: c.entityState_t, now: i64) !void {
    if (entity.weapon <= 0 or entity.weapon > 28) return error.InvalidProjectileWeapon;
    const spec = catalog.find(@intCast(entity.weapon)).?.spec;
    if (entity.generic1 == 0) if (spec.projectile.loop_sound) |name| {
        const handle = try engine.registerSound(name);
        if (handle != 0) _ = engine.gateway.call(c.CG_S_ADDLOOPINGSOUND, .{ @as(isize, entity.number), &rendered.origin, &entity.pos.trDelta, @as(isize, handle) });
    };
    if (spec.visual.projectile_scale != 1) {
        for (&rendered.axis) |*axis| axis.* = v.scale(axis.*, spec.visual.projectile_scale);
        rendered.nonNormalizedAxes = c.qtrue;
    }
    if (entity.generic1 != 0 and entity.time2 > now) rendered.shaderRGBA[3] = @intCast(@min(255, @divTrunc((entity.time2 - now) * 255, 1000)));
    if (spec.visual.glow and entity.generic1 == 0) {
        const color = spec.visual.color;
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &rendered.origin, engine.floatArg(120), engine.floatArg(color[0]), engine.floatArg(color[1]), engine.floatArg(color[2]) });
    }
}
