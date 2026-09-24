// SPDX-License-Identifier: GPL-2.0-or-later
//! One animation player per weapon; its owner supplies action-specific transitions.
const std = @import("std");
const r = @import("render.zig");
const c = r.c;
const v = r.v;
pub var selected: c_int = 0;
pub var muzzle_weapon: c_int = 0;
pub var muzzle_offset: v.Vec = v.zero;
pub fn View(comptime W: type) type {
    return struct {
        const Self = @This();
        pub var instance: Self = .{};
        pose: ?[:0]const u8 = null,
        start: c_int = 0,
        end: c_int = 0,
        idle_at: c_int = 0,
        idle_variant: usize = 0,
        time: c_int = 0,
        state: c_int = c.WEAPON_READY,
        shot: c_int = 0,
        sequence: c_int = 0,
        rate: c_int = 20,
        pub fn play(self: *Self, name: [:0]const u8, start: c_int, rate: c_int) void {
            const duration = c.DK_ModelAnimationDuration(W.spec.animation.view_model, name, rate);
            if (duration <= 0) c.CG_Error("dk3: missing authored weapon pose %s:%s", W.spec.animation.view_model.ptr, name.ptr);
            self.pose = name;
            self.start = start;
            self.rate = rate;
            self.end = start + duration;
            self.idle_at = self.end + 2000 + @mod(start *% 7919, 6001);
        }
        pub fn isIdle(self: *Self) bool {
            const pose = self.pose orelse return false;
            for (W.spec.animation.idle) |idle| if (idle) |name| {
                if (std.mem.eql(u8, pose, name)) return true;
            };
            return false;
        }
        pub fn animate(self: *Self, ps: *c.playerState_t, entity: *c.refEntity_t) void {
            const shot = c.cg.predictedPlayerEntity.muzzleFlashTime;
            const reset = selected != W.id or r.now() < self.time or self.pose == null;
            if (reset) {
                self.* = .{};
                selected = W.id;
                self.shot = shot;
                self.play(W.spec.animation.ready, r.now() - c.DK_ModelAnimationDuration(W.spec.animation.view_model, W.spec.animation.ready, 20), 20);
                if (@hasDecl(W, "resetView")) W.resetView();
            }
            var handled = false;
            if (@hasDecl(W, "viewAction")) handled = W.viewAction(self, ps, shot, reset);
            if (!handled) {
                if (ps.weaponstate == c.WEAPON_FIRING and (self.state != c.WEAPON_FIRING or self.shot != shot)) {
                    if (@hasDecl(W, "startShotPose")) W.startShotPose(self, ps, shot, reset) else {
                        const cue = W.viewCue(ps.dk3WeaponSequence, ps.dk3SwordExperience);
                        const rate = if (cue.rate > 0) cue.rate else 20;
                        const factor = @import("../rules.zig").attackFactor(c.DK_Attribute(ps, 1, r.now()));
                        if (cue.pose != null) self.play(std.mem.span(cue.pose), r.now() + cue.poseStartOffsetMs, v.i(v.f(rate) * factor));
                    }
                } else if ((reset or ps.weaponstate != self.state) and ps.weaponstate == c.WEAPON_RAISING) {
                    self.play(W.spec.animation.ready, r.now(), 20);
                    if (W.spec.audio.ready) |name| r.localSound(name);
                } else if (ps.weaponstate != self.state and ps.weaponstate == c.WEAPON_DROPPING) {
                    if (@hasDecl(W, "dropPose")) W.dropPose(self, ps) else {
                        self.play(W.spec.animation.away, r.now(), 20);
                        if (W.spec.audio.away) |name| r.localSound(name);
                    }
                } else if (ps.weaponstate == c.WEAPON_READY and r.now() >= self.end and !self.isIdle()) {
                    if (W.spec.animation.idle[0]) |idle| self.play(idle, r.now(), 20);
                } else if (ps.weaponstate == c.WEAPON_READY and r.now() >= self.idle_at) {
                    var count: usize = 0;
                    for (W.spec.animation.idle) |idle| count += @intFromBool(idle != null);
                    self.idle_variant = if (count > 0) @as(usize, @intCast(@mod(r.now() *% 104729, 997))) % count else 0;
                    if (W.spec.animation.idle[self.idle_variant] orelse W.spec.animation.idle[0]) |idle| {
                        self.play(idle, r.now(), 20);
                        if (W.spec.audio.idle[self.idle_variant]) |name| r.localSound(name);
                    }
                }
            }
            if (@hasDecl(W, "viewFrame")) W.viewFrame(self, ps, entity) else if (self.pose) |pose| c.DK_ModelAnimationRate(W.spec.animation.view_model, pose, self.start, @intFromBool(self.isIdle()), self.rate, entity);
            self.state = ps.weaponstate;
            self.shot = shot;
            self.time = r.now();
            self.sequence = ps.dk3WeaponSequence;
        }
    };
}
pub fn draw(comptime W: type, ps: *c.playerState_t) void {
    if (W.spec.animation.view_model.len == 0 or c.cg.renderingThirdPerson != 0 or ps.pm_type != c.PM_NORMAL or c.cg_drawGun.integer == 0) return;
    var entity = std.mem.zeroes(c.refEntity_t);
    View(W).instance.animate(ps, &entity);
    if (entity.hModel == 0) return;
    entity.origin = v.madd(v.madd(v.madd(c.cg.refdef.vieworg, c.cg_gun_x.value, c.cg.refdef.viewaxis[0]), c.cg_gun_y.value, c.cg.refdef.viewaxis[1]), c.cg_gun_z.value, c.cg.refdef.viewaxis[2]);
    entity.axis = c.cg.refdef.viewaxis;
    entity.reType = c.RT_MODEL;
    entity.renderfx = c.RF_DEPTHHACK | c.RF_FIRST_PERSON | c.RF_MINLIGHT;
    entity.shaderRGBA = @splat(255);
    if (ps.powerups[c.PW_INVIS] > r.now()) {
        entity.customShader = c.trap_R_RegisterShader("dk3/fx/cloak");
        entity.shaderRGBA[3] = 100;
    }
    c.trap_R_AddRefEntityToScene(&entity);
    const offset = v.sub(r.muzzlePoint(&entity), c.cg.refdef.vieworg);
    for (&muzzle_offset, 0..) |*axis, index| axis.* = v.dot(offset, c.cg.refdef.viewaxis[index]);
    muzzle_weapon = W.id;
    if (@hasDecl(W, "muzzle")) W.muzzle(&entity, c.cg.predictedPlayerEntity.muzzleFlashTime);
    if (@hasDecl(W, "heldEffect")) W.heldEffect(&entity, ps.clientNum);
}
pub fn world(comptime W: type, parent: *c.refEntity_t, cent: *c.centity_t) void {
    if (W.spec.audio.hum) |hum| c.trap_S_AddLoopingSound(cent.currentState.number, &cent.lerpOrigin, &v.zero, r.sound(hum));
    const path = W.spec.world_model orelse return;
    if (path.len == 0) return;
    var entity = std.mem.zeroes(c.refEntity_t);
    entity.hModel = c.DK_RegisterModel(path);
    if (entity.hModel == 0) return;
    entity.reType = c.RT_MODEL;
    entity.axis = r.identity;
    c.CG_PositionEntityOnTag(&entity, parent, parent.hModel, @constCast("hp_gun"));
    entity.axis = parent.axis;
    entity.shaderRGBA = .{ 255, 255, 255, parent.shaderRGBA[3] };
    entity.renderfx = parent.renderfx;
    entity.customShader = parent.customShader;
    c.trap_R_AddRefEntityToScene(&entity);
    if (cent.currentState.number != c.cg.clientNum or c.cg.renderingThirdPerson != 0) {
        if (@hasDecl(W, "muzzle")) W.muzzle(&entity, cent.muzzleFlashTime);
        if (@hasDecl(W, "heldEffect")) W.heldEffect(&entity, cent.currentState.number);
    }
}
