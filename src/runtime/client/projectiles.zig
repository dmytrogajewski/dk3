// SPDX-License-Identifier: GPL-2.0-or-later
const catalog = @import("weapon_catalog");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub fn sprite(entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !bool {
    if (entity.weapon <= 0 or entity.weapon > 28) return error.InvalidProjectileWeapon;
    const spec = catalog.find(@intCast(entity.weapon)).?.spec;
    const name = (if (entity.generic1 & 2 != 0) spec.visual.resting_sprite orelse spec.visual.projectile_sprite else spec.visual.projectile_sprite) orelse return false;
    const sprites = @import("sprites.zig");
    const media = try sprites.register(name);
    var rendered = @import("std").mem.zeroes(c.refEntity_t);
    rendered.origin = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    try decorate(&rendered, entity, now);
    sprites.draw(media, @as(usize, @intCast(@divTrunc(@max(0, now - entity.time), 50))) % sprites.count(media), rendered.origin, spec.visual.projectile_scale, spec.visual.sprite_additive, ref);
    return true;
}
pub fn decorate(rendered: *c.refEntity_t, entity: c.entityState_t, now: i64) !void {
    if (entity.weapon <= 0 or entity.weapon > 28) return error.InvalidProjectileWeapon;
    const spec = catalog.find(@intCast(entity.weapon)).?.spec;
    if (entity.weapon == catalog.c4.id and entity.time2 > 0 and now >= entity.time2 and now - entity.time2 < 100) {
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &rendered.origin, engine.floatArg(100), engine.floatArg(1), engine.floatArg(0), engine.floatArg(0) });
    }
    if (entity.generic1 == 0) if (spec.projectile.loop_sound) |name| {
        const handle = try engine.registerSound(name);
        if (handle != 0) _ = engine.gateway.call(c.CG_S_ADDLOOPINGSOUND, .{ @as(isize, entity.number), &rendered.origin, &entity.pos.trDelta, @as(isize, handle) });
    };
    const scale = catalog.flightScale(@intCast(entity.weapon), entity.generic1);
    if (scale != 1) {
        for (&rendered.axis) |*axis| axis.* = v.scale(axis.*, scale);
        rendered.nonNormalizedAxes = c.qtrue;
    }
    if (spec.visual.fade_stuck and entity.generic1 & 1 != 0 and entity.time2 > now) rendered.shaderRGBA[3] = @intCast(@min(255, @divTrunc((entity.time2 - now) * 255, 1000)));
    if (entity.weapon == catalog.stavros.id or entity.weapon == catalog.wyndrax.id) {
        for (&rendered.axis, entity.angles2) |*axis, factor| axis.* = v.scale(axis.*, factor);
        rendered.nonNormalizedAxes = c.qtrue;
    }
    if (entity.weapon == catalog.wyndrax.id) rendered.shaderRGBA[3] = @intFromFloat(@import("std").math.clamp(entity.origin2[2], 0, 1) * 255);
    if (spec.visual.glow and entity.generic1 == 0) {
        const color = spec.visual.color;
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &rendered.origin, engine.floatArg(120), engine.floatArg(color[0]), engine.floatArg(color[1]), engine.floatArg(color[2]) });
    }
}
