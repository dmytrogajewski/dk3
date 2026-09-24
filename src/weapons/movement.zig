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
    pub fn event(self: *const Controller, event_id: c_int) void {
        c.BG_AddPredictableEventToPlayerstate(event_id, 0, self.ps);
    }
    pub fn boost(self: *const Controller) c_int {
        return c.DK_Attribute(self.ps, 1, self.move.cmd.serverTime);
    }

    pub fn scaled(self: *const Controller, duration: c_int) c_int {
        const factor: f32 = 1 + 0.1 * @as(f32, @floatFromInt(self.boost()));
        return @intFromFloat(@as(f32, @floatFromInt(duration)) / factor);
    }

    pub fn pressed(self: *const Controller) bool {
        return (self.move.cmd.buttons & c.BUTTON_ATTACK) != 0;
    }

    pub fn release(self: *Controller) void {
        self.ps.dk3AttackHeld = 0;
        if (self.ps.weaponTime > 0) return;
        self.ps.weaponstate = c.WEAPON_READY;
        self.ps.dk3NovaSpent = 0;
    }

    pub fn fireEvent(self: *const Controller) void {
        self.ps.torsoAnim = ((self.ps.torsoAnim & c.ANIM_TOGGLEBIT) ^ c.ANIM_TOGGLEBIT) | c.TORSO_ATTACK;
        self.event(c.EV_FIRE_WEAPON);
    }

    pub fn fire(self: *Controller, comptime Weapon: type, shot: Shot) void {
        const weapon: usize = @intCast(self.ps.weapon);
        if (shot.cost != 0 and self.ps.ammo[weapon] < shot.cost) {
            self.event(c.EV_NOAMMO);
            self.ps.weaponTime = 300;
            self.ps.dk3Burst = 0;
            return;
        }
        if (self.ps.dk3Burst == 0) self.ps.dk3Burst = Weapon.spec.burst_shots;
        self.ps.ammo[weapon] -= shot.cost;
        if (shot.consume_clip) self.ps.dk3GlockClip -= 1;
        self.ps.dk3WeaponSequence = shot.sequence;
        self.ps.weaponstate = c.WEAPON_FIRING;
        self.fireEvent();
        self.ps.weaponTime += shot.duration_ms;
        if (self.ps.dk3Burst != 0) {
            self.ps.dk3Burst -= 1;
            if (self.ps.dk3Burst == 0) self.ps.weaponTime += Weapon.spec.burst_recovery_ms;
        }
    }

    pub fn automatic(self: *Controller, comptime Weapon: type) void {
        if (!self.pressed() and self.ps.dk3Burst == 0) {
            self.release();
            return;
        }
        self.ps.dk3AttackHeld = @intFromBool(self.pressed());
        if (self.ps.weaponTime <= 0) self.fire(Weapon, Weapon.predictionShot(self));
    }

    fn switchWeapon(self: *Controller, selected: c_int) bool {
        if (self.ps.weaponstate == c.WEAPON_DROPPING and !registry.isReloading(self.ps)) {
            if (self.ps.weaponTime > 0) return true;
            if (c.DK_HasWeapon(self.ps, selected) != 0) {
                self.ps.weapon = selected;
                self.ps.dk3Burst = 0;
                self.ps.dk3Charge = 0;
                self.ps.dk3NovaSpent = 0;
                self.ps.dk3WeaponSequence = 0;
            }
            self.ps.weaponstate = c.WEAPON_RAISING;
            self.ps.weaponTime = c.DK_WeaponSwitchTime(self.ps.weapon, c.qtrue);
            return true;
        }
        if (selected != self.ps.weapon and self.ps.weaponstate != c.WEAPON_DROPPING and
            c.DK_HasWeapon(self.ps, selected) != 0 and self.ps.weaponTime <= 0 and self.ps.dk3Burst == 0)
        {
            self.ps.weaponstate = c.WEAPON_DROPPING;
            self.ps.weaponTime = c.DK_WeaponSwitchTime(self.ps.weapon, c.qfalse);
            return true;
        }
        return false;
    }

    fn tick(self: *Controller) void {
        if (self.ps.pm_type != c.PM_NORMAL or self.ps.stats[c.STAT_HEALTH] <= 0 or
            (self.ps.pm_flags & c.PMF_RESPAWNED) != 0) return;
        registry.inventoryPrediction(self);
        self.ps.weaponTime = @max(self.ps.weaponTime - self.msec, -self.msec);
        if (self.switchWeapon(self.move.cmd.weapon)) return;
        if (c.DK_HasWeapon(self.ps, self.ps.weapon) == 0) return;
        registry.update(self.ps.weapon, self);
    }
};

pub fn run(move: *c.pmove_t, msec: c_int) void {
    var controller = Controller.init(move, msec);
    controller.tick();
}
