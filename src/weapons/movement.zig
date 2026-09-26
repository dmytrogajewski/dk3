// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared prediction control. Weapon-specific input and shot decisions are
//! dispatched to concrete types; this controller owns only engine state writes.
const c = @import("abi.zig").c;
const registry = @import("registry.zig");
const Shot = @import("shot.zig").Shot;

pub const Controller = struct {
    msec: c_int,
    move: *c.pmove_t,
    ps: *c.playerState_t,

    fn init(move: *c.pmove_t, msec: c_int) Controller {
        return .{ .msec = msec, .move = move, .ps = @ptrCast(move.ps) };
    }
    pub fn canFire(self: *const Controller) bool {
        return self.ps.pm_type == c.PM_NORMAL and self.ps.stats[c.STAT_HEALTH] > 0 and self.ps.pm_flags & c.PMF_RESPAWNED == 0;
    }
    pub fn inventoryTick(self: *Controller) void {
        registry.inventoryPrediction(self);
    }
    pub fn selection(self: *const Controller) i32 {
        return self.move.cmd.weapon;
    }
    pub fn noAmmo(self: *const Controller) void {
        self.event(c.EV_NOAMMO);
    }
    pub fn now(self: *const Controller) c_int {
        return self.move.cmd.serverTime;
    }
    pub fn ammoCost(_: *const Controller, weapon: c_int) c_int {
        return c.dk_weapons[@intCast(weapon)].ammoCost;
    }
    pub fn lifetime(_: *const Controller, weapon: c_int) f32 {
        return c.dk_weapons[@intCast(weapon)].lifetime;
    }
    pub fn interval(_: *const Controller, weapon: c_int) c_int {
        return c.dk_weapons[@intCast(weapon)].interval;
    }
    pub fn discusMelee(self: *const Controller) bool {
        var eye = self.ps.origin;
        eye[2] += @as(f32, @floatFromInt(self.ps.viewheight));
        var forward: [3]f32 = undefined;
        c.AngleVectors(&self.ps.viewangles, &forward, null, null);
        const end = @import("vector.zig").madd(eye, 100, forward);
        var hit: c.trace_t = undefined;
        self.move.trace.?(&hit, &eye, null, null, &end, self.ps.clientNum, c.MASK_SHOT);
        return hit.fraction < 1;
    }
    pub fn venomBite(self: *const Controller) bool {
        if (self.move.waterlevel > 1 or self.ps.ammo[c.DK_W_VENOM] < c.dk_weapons[c.DK_W_VENOM].ammoCost) return true;
        var eye = self.ps.origin;
        eye[2] += 4;
        var forward: [3]f32 = undefined;
        c.AngleVectors(&self.ps.viewangles, &forward, null, null);
        const end = @import("vector.zig").madd(eye, 150, forward);
        var hit: c.trace_t = undefined;
        self.move.trace.?(&hit, &eye, &self.move.mins, &self.move.maxs, &end, self.ps.clientNum, c.MASK_SHOT);
        return hit.fraction < 1 and hit.entityNum < c.ENTITYNUM_WORLD;
    }
    pub fn event(self: *const Controller, event_id: c_int) void {
        c.BG_AddPredictableEventToPlayerstate(event_id, 0, self.ps);
    }
    pub fn boost(self: *const Controller) c_int {
        return c.DK_Attribute(self.ps, 1, self.move.cmd.serverTime);
    }

    pub fn scaled(self: *const Controller, duration: c_int) c_int {
        const factor = @import("rules.zig").attackFactor(self.boost());
        return @intFromFloat(@as(f32, @floatFromInt(duration)) / factor);
    }

    pub fn pressed(self: *const Controller) bool {
        return (self.move.cmd.buttons & c.BUTTON_ATTACK) != 0;
    }

    pub fn release(self: *Controller) void {
        @import("controller.zig").release(self);
    }

    pub fn fireEvent(self: *const Controller) void {
        self.ps.torsoAnim = ((self.ps.torsoAnim & c.ANIM_TOGGLEBIT) ^ c.ANIM_TOGGLEBIT) | c.TORSO_ATTACK;
        self.event(c.EV_FIRE_WEAPON);
    }

    pub fn fire(self: *Controller, comptime Weapon: type, shot: Shot) void {
        @import("controller.zig").fire(self, Weapon, shot);
    }

    pub fn automatic(self: *Controller, comptime Weapon: type) void {
        @import("controller.zig").automatic(self, Weapon);
    }

    fn tick(self: *Controller) void {
        @import("controller.zig").tick(self);
    }
};

pub fn run(move: *c.pmove_t, msec: c_int) void {
    var controller = Controller.init(move, msec);
    controller.tick();
}
