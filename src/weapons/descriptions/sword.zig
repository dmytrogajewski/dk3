// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 8;
pub const spec: profiles.Spec = .{
    .companion_pickup = false, // sword
    .world_model = "models/global/a_daikatana.dkm",
    .audio = .{ .ready = "global/we_swordwhoosha.wav", .away = "global/we_swordwhooshc.wav" },
    .animation = .{
        .view_model = "models/global/w_daikatana.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "ataka",
        .idle = .{ "amba", null, null },
        .raise_ms = 600,
        .drop_ms = 500,
    },
};
pub const identity = .{ .classname = "weapon_daikatana", .label = "Daikatana", .episode = 0, .interval = 420 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn update(controller: anytype) void {
    const ps = controller.ps;
    if (!controller.pressed() and ps.dk3Burst == 0) {
        ps.dk3AttackHeld = 0;
        if (ps.weaponTime <= 0) {
            if (((ps.dk3WeaponSequence >> 3) & 15) != 0) {
                ps.dk3WeaponSequence &= 7;
                const factor: f32 = 1 - 0.1 * @as(f32, @floatFromInt(controller.boost()));
                ps.weaponTime += @intFromFloat(500 * factor);
            }
            ps.weaponstate = state.ready;
            ps.dk3NovaSpent = 0;
        }
        return;
    }
    ps.dk3AttackHeld = @intFromBool(controller.pressed());
    if (ps.weaponTime <= 0) fireSwing(controller);
}

fn fireSwing(controller: anytype) void {
    const ps = controller.ps;
    const level = sword.level(ps.dk3SwordExperience);
    const chain = (ps.dk3WeaponSequence >> 3) & 15;
    const previous = if (chain != 0) ps.dk3WeaponSequence & 7 else -1;
    const selected = if (chain >= 2 * level) -1 else sword.select(previous, @bitCast(controller.now()));
    if (selected < 0) {
        ps.dk3WeaponSequence &= 7;
        ps.weaponstate = state.ready;
        const factor: f32 = 1 - 0.1 * @as(f32, @floatFromInt(controller.boost()));
        ps.weaponTime += @intFromFloat(1000 * factor);
        return;
    }
    ps.dk3WeaponSequence = selected | ((chain + 1) << 3);
    ps.weaponstate = state.firing;
    controller.fireEvent();
    const duration = sword.swings[@intCast(selected)].followThrough * sword.frameTime(ps.dk3SwordExperience);
    ps.weaponTime += duration;
}
