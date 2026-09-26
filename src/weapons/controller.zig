// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared weapon transitions; adapters own input, collision, data and event delivery.
const catalog = @import("catalog.zig");
const state = @import("weapon_state.zig");
const Shot = @import("shot.zig").Shot;
pub fn owns(ps: anytype, weapon: i32) bool {
    return weapon > 0 and weapon <= 28 and (@as(u32, @bitCast(ps.dk3Inventory)) & (@as(u32, 1) << @intCast(weapon))) != 0;
}
pub fn switchTime(weapon: i32, raising: bool) i32 {
    const entry = if (weapon > 0 and weapon <= 28) catalog.find(@intCast(weapon)) else null;
    const duration = if (entry) |value| (if (raising) value.spec.animation.raise_ms else value.spec.animation.drop_ms) else 0;
    return if (duration > 0) duration else 250;
}
pub fn attackFactor(level: i32) f32 {
    if (level <= 0) return 1;
    return (@as(f32, @floatFromInt(level)) + @as(f32, if (level == 1) 1.5 else 1)) * 0.5;
}
pub fn release(self: anytype) void {
    self.ps.dk3AttackHeld = 0;
    if (self.ps.weaponTime > 0) return;
    self.ps.weaponstate = state.ready;
    self.ps.dk3NovaSpent = 0;
}

pub fn fire(self: anytype, comptime Weapon: type, shot: Shot) void {
    const weapon: usize = @intCast(self.ps.weapon);
    if (shot.cost != 0 and self.ps.ammo[weapon] < shot.cost) {
        self.noAmmo();
        self.ps.weaponTime = @max(300, if (self.ps.dk3Burst != 0) Weapon.spec.burst_recovery_ms else 0);
        self.ps.dk3Burst = 0;
        return;
    }
    if (self.ps.dk3Burst == 0) self.ps.dk3Burst = Weapon.spec.burst_shots;
    self.ps.ammo[weapon] -= shot.cost;
    if (shot.consume_clip) self.ps.dk3GlockClip -= 1;
    self.ps.dk3WeaponSequence = shot.sequence;
    if (self.ps.weaponstate != state.firing) self.ps.weaponTime = @max(0, self.ps.weaponTime);
    self.ps.weaponstate = state.firing;
    self.fireEvent();
    self.ps.weaponTime += shot.duration_ms;
    if (self.ps.dk3Burst != 0) {
        self.ps.dk3Burst -= 1;
        if (self.ps.dk3Burst == 0) self.ps.weaponTime += Weapon.spec.burst_recovery_ms;
    }
}

pub fn automatic(self: anytype, comptime Weapon: type) void {
    if (!self.pressed() and self.ps.dk3Burst == 0) {
        self.release();
        return;
    }
    self.ps.dk3AttackHeld = @intFromBool(self.pressed());
    if (self.ps.weaponTime <= 0) self.fire(Weapon, Weapon.predictionShot(self));
}

pub fn switchWeapon(self: anytype, selected: c_int) bool {
    if (self.ps.weaponstate == state.dropping and !catalog.isReloading(self.ps)) {
        if (self.ps.weaponTime > 0) return true;
        if (owns(self.ps, selected)) {
            self.ps.weapon = selected;
            self.ps.dk3Burst = 0;
            self.ps.dk3Charge = 0;
            self.ps.dk3NovaSpent = 0;
            self.ps.dk3WeaponSequence = 0;
        }
        self.ps.weaponstate = state.raising;
        self.ps.weaponTime = switchTime(self.ps.weapon, true);
        return true;
    }
    if (selected != self.ps.weapon and self.ps.weaponstate != state.dropping and
        owns(self.ps, selected) and self.ps.weaponTime <= 0 and self.ps.dk3Burst == 0)
    {
        self.ps.weaponstate = state.dropping;
        self.ps.weaponTime = switchTime(self.ps.weapon, false);
        return true;
    }
    return false;
}

pub fn tick(self: anytype) void {
    if (!self.canFire()) return;
    self.inventoryTick();
    self.ps.weaponTime = @max(self.ps.weaponTime - self.msec, -self.msec);
    if (switchWeapon(self, self.selection())) return;
    if (!owns(self.ps, self.ps.weapon)) return;
    catalog.update(self);
}

pub fn expireGas(ps: anytype) void {
    ps.dk3Inventory &= ~@as(i32, 1 << 7);
    if (ps.weapon != 7) return;
    var weapon: i32 = 1;
    while (weapon <= 28 and !owns(ps, weapon)) : (weapon += 1) {}
    ps.weapon = if (weapon <= 28) weapon else 0;
    ps.weaponstate = state.raising;
    ps.weaponTime = switchTime(ps.weapon, true);
    ps.dk3Burst = 0;
    ps.dk3Charge = 0;
    ps.dk3AttackHeld = 0;
}
