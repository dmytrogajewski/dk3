// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
pub const c = @import("../abi.zig").c;
pub const v = @import("../vector.zig");
pub const white: v.Vec = .{ 1, 1, 1 };
pub const identity: [3]v.Vec = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
pub fn now() c_int {
    return c.cg.time;
}
pub fn byte(value: f32) u8 {
    return @intFromFloat(std.math.clamp(value, 0, 1) * 255);
}
pub fn sound(name: [*c]const u8) c.sfxHandle_t {
    return c.trap_S_RegisterSound(c.va(@constCast("sounds/%s"), name), c.qfalse);
}
pub fn localSound(name: [*c]const u8) void {
    if (name != null and name[0] != 0) c.trap_S_StartLocalSound(sound(name), c.CHAN_WEAPON);
}
pub fn worldSound(name: [*c]const u8, point: v.Vec) void {
    if (name != null and name[0] != 0) c.trap_S_StartSound(@constCast(&point), c.ENTITYNUM_WORLD, c.CHAN_AUTO, sound(name));
}
pub fn light(point: v.Vec, radius: f32, color: v.Vec) void {
    c.trap_R_AddLightToScene(&point, radius, color[0], color[1], color[2]);
}
pub fn sprite(path: [*c]const u8, frame: c_int, point: v.Vec, angles: v.Vec, scale: f32, alpha: f32, color: v.Vec, flags: c_int) bool {
    return c.DK_DrawSpriteAt(path, frame, &point, &angles, scale, alpha, &color, flags) != 0;
}
pub fn muzzlePoint(parent: *c.refEntity_t) v.Vec {
    for ([_][:0]const u8{ "hr_muzzle", "fire" }) |name| {
        var tag: c.orientation_t = undefined;
        if (c.trap_R_LerpTag(&tag, parent.hModel, parent.oldframe, parent.frame, 1 - parent.backlerp, name) == 0) continue;
        var tip = std.mem.zeroes(c.refEntity_t);
        tip.axis = identity;
        c.CG_PositionEntityOnTag(&tip, parent, parent.hModel, @constCast(name));
        return tip.origin;
    }
    return v.madd(parent.origin, 24, parent.axis[0]);
}
pub const Flash = struct {
    model: [:0]const u8,
    sequence: [:0]const u8 = "stand",
    shader: ?[:0]const u8 = null,
    scale: f32 = 1,
    alpha: f32 = 0.6,
    radius: f32 = 150,
    color: v.Vec = .{ 0.8, 0.4, 0.2 },
    offset: f32 = 0,
    sprite_model: bool = false,
};
pub fn flash(parent: *c.refEntity_t, fired_at: c_int, style: Flash) void {
    if (now() < fired_at or now() - fired_at > 50) return;
    const point = v.madd(muzzlePoint(parent), style.offset, parent.axis[0]);
    if (style.sprite_model) {
        var angles: v.Vec = undefined;
        c.vectoangles(&parent.axis[0], &angles);
        _ = sprite(style.model, 0, point, angles, style.scale, style.alpha, style.color, c.DK_SPRITE_ADDITIVE | c.DK_SPRITE_ORIENTED);
    } else {
        var entity = std.mem.zeroes(c.refEntity_t);
        c.DK_ModelAnimation(style.model, style.sequence, fired_at, c.qfalse, &entity);
        entity.origin = point;
        for (&entity.axis, 0..) |*axis, index| axis.* = v.scale(parent.axis[index], style.scale);
        entity.nonNormalizedAxes = c.qtrue;
        entity.reType = c.RT_MODEL;
        entity.renderfx = parent.renderfx;
        if (style.shader) |shader| entity.customShader = c.trap_R_RegisterShader(shader);
        entity.shaderRGBA = .{ 255, 255, 255, byte(style.alpha) };
        c.trap_R_AddRefEntityToScene(&entity);
    }
    light(point, style.radius, style.color);
}
pub fn strip(start: v.Vec, end: v.Vec, width: f32, color: v.Vec, alpha: f32, shader: c.qhandle_t) void {
    const along = v.sub(end, start);
    const eye = v.sub(c.cg.refdef.vieworg, start);
    var side: v.Vec = undefined;
    c.CrossProduct(&along, &eye, &side);
    if (v.length(side) < 0.001) return;
    side = v.normal(side);
    var vertices: [4]c.polyVert_t = undefined;
    for (&vertices, 0..) |*vertex, index| {
        const positive = index == 0 or index == 3;
        vertex.xyz = v.madd(if (index < 2) start else end, if (positive) width * 0.5 else -width * 0.5, side);
        vertex.st = .{ if (index < 2) 0 else 1, if (positive) 0 else 1 };
        vertex.modulate = .{ byte(color[0]), byte(color[1]), byte(color[2]), byte(alpha) };
    }
    c.trap_R_AddPolyToScene(shader, 4, &vertices);
}
pub fn model(comptime W: type, cent: *c.centity_t) void {
    const state = &cent.currentState;
    const color = W.spec.visual.color;
    if ((state.dk3EffectFlags & c.DK_FX_BUBBLE) != 0 and cent.trailTime < now() - 50) {
        var previous: v.Vec = undefined;
        c.BG_EvaluateTrajectory(&state.pos, now() - 50, &previous);
        c.CG_BubbleTrail(&previous, &cent.lerpOrigin, 16);
        cent.trailTime = now();
    }
    if (state.modelindex != 0 and c.DK_DrawSprite(cent) != 0) {
        light(cent.lerpOrigin, 400, .{ 0.15, 0.95, 0.35 });
        return;
    }
    const path = if (state.modelindex != 0) c.CG_ConfigString(c.CS_MODELS + state.modelindex) else W.spec.visual.projectile_model.ptr;
    var angles: v.Vec = undefined;
    c.vectoangles(&state.pos.trDelta, &angles);
    if (state.dk3Effect == c.DK_FX_SLUDGE or state.dk3Effect == c.DK_FX_PSYCLAW) angles = cent.lerpAngles;
    if (state.dk3Effect == c.DK_FX_CRYO or state.dk3Effect == c.DK_FX_SLUDGE) {
        c.DK_MonsterTrail(cent);
        if (state.dk3Effect == c.DK_FX_CRYO) return;
    }
    if (c.Q_stricmp(path, "models/e1/me_sludge.dkm") == 0 and state.dk3Effect != c.DK_FX_SLUDGE) {
        @import("../types/venom_client.zig").trail(cent);
        return;
    }
    if (path != null and path[0] != 0 and !sprite(path, @divTrunc(now() - state.time, 70), cent.lerpOrigin, angles, 1, 1, color, 2)) {
        var entity = std.mem.zeroes(c.refEntity_t);
        entity.reType = c.RT_MODEL;
        entity.hModel = c.DK_RegisterModel(path);
        if (@hasDecl(W, "projectileAnimation")) W.projectileAnimation(cent, path, &entity);
        entity.origin = cent.lerpOrigin;
        if (W.spec.visual.spin) angles[1] += v.f(now()) * 0.8;
        c.AnglesToAxis(&angles, &entity.axis);
        const scale = if (state.dk3Scale > 0) state.dk3Scale else 1;
        for (&entity.axis, 0..) |*axis, index| {
            const amount = if (state.dk3ModelScale[index] > 0) state.dk3ModelScale[index] else scale;
            axis.* = v.scale(axis.*, amount);
            if (amount != 1) entity.nonNormalizedAxes = c.qtrue;
        }
        entity.shaderRGBA = @splat(255);
        if (state.dk3Alpha > 0 and state.dk3Alpha < 0.999) {
            entity.shaderRGBA[3] = byte(state.dk3Alpha);
            entity.skinNum = 1;
        }
        c.trap_R_AddRefEntityToScene(&entity);
    }
    if (c.strstr(path, "we_dsbolt") != null) {
        _ = sprite("models/e1/we_dsboltf.sp2", 0, cent.lerpOrigin, angles, 0.85, 1, white, c.DK_SPRITE_ADDITIVE);
        light(cent.lerpOrigin, 150, .{ 0.8, 0.7, 0.2 });
        return;
    }
    light(cent.lerpOrigin, 70, color);
}
pub fn impact(comptime W: type, cent: *c.centity_t) void {
    const kind = cent.currentState.eventParm;
    const cue = W.impactCue(.{ .kind = kind, .entity = cent.currentState.number, .frame = cent.currentState.frame });
    worldSound(cue.sound, cent.lerpOrigin);
    if (kind != 1 and kind != 2 and cue.mark != null) c.CG_ImpactMark(c.trap_R_RegisterShader(cue.mark), &cent.lerpOrigin, &cent.currentState.origin2, cue.orientation, 1, 1, 1, 1, c.qtrue, cue.radius, c.qfalse);
}
pub fn fired(comptime W: type, cent: *c.centity_t) void {
    const cue = W.audioCue(.{ .entity = cent.currentState.number, .local_entity = c.cg.clientNum, .sequence = if (cent.currentState.number == c.cg.clientNum) c.cg.predictedPlayerState.dk3WeaponSequence else 0, .fired = cent.muzzleFlashTime, .now = now() });
    if (cue.fire != null and cue.fire[0] != 0) c.trap_S_StartSound(null, cent.currentState.number, c.CHAN_WEAPON, sound(cue.fire));
    if (cue.extra != null) c.trap_S_StartSound(null, cent.currentState.number, c.CHAN_AUTO, sound(cue.extra));
    if (@hasDecl(W, "eject")) W.eject(cent);
}
