// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 22;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_ripgun", // ripgun
    .world_model = "models/e4/a_ripgun.dkm",
    .animation = .{
        .view_model = "models/e4/w_ripgun.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .raise_ms = 350,
        .drop_ms = 250,
    },
    .audio = .{
        .fire = "e4/we_sluggershoota.wav",
        .ready = "e4/we_sluggerready.wav",
        .away = "e4/we_sluggeraway.wav",
    },
};
pub const identity = .{ .classname = "weapon_ripgun", .label = "Ripgun", .episode = 4, .interval = 100 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    const ps = controller.ps;
    if (controller.pressed()) ps.dk3NovaSpent = 300 else ps.dk3NovaSpent = @max(0, ps.dk3NovaSpent - controller.msec);
    if (!controller.pressed() and ps.dk3NovaSpent == 0) {
        ps.dk3Charge = 0;
        controller.release();
        return;
    }
    if (ps.dk3AttackHeld == 0 and ps.weaponTime > 0) return;
    ps.dk3AttackHeld = 1;
    const spinning = ps.dk3Charge < 350;
    ps.dk3Charge = @min(350, ps.dk3Charge + controller.msec);
    ps.weaponstate = state.firing;
    if (ps.dk3Charge < 350) return;
    if (spinning) ps.weaponTime = @max(0, ps.weaponTime);
    if (ps.weaponTime <= 0) controller.fire(@This(), predictionShot(controller));
}
