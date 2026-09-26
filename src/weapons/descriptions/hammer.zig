// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 12;
pub const spec: profiles.Spec = .{
    .bot_charge_ms = 900,
    .bot_range = 110,
    .start_episode = 2, // hammer
    .visual = .{},
    .world_model = "models/e2/a_hammer.dkm",
    .animation = .{
        .view_model = "models/e2/w_hammer.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ null, null, null },
        .raise_ms = 300,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e2/we_hammerd.wav",
        .ready = "e2/we_hammerready.wav",
        .away = "e2/we_hammeraway.wav",
    },
};
pub const identity = .{ .classname = "weapon_hammer", .label = "Hammer of Hephaestus", .episode = 2, .interval = 700 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    const ps = controller.ps;
    if (controller.pressed()) {
        if (ps.dk3AttackHeld == 0) ps.dk3Charge = 0;
        ps.dk3Charge = @min(ps.dk3Charge + controller.msec, 1800);
        ps.dk3AttackHeld = 1;
        return;
    }
    if (ps.dk3AttackHeld == 0) {
        controller.release();
        return;
    }
    if (ps.weaponTime <= 0) {
        ps.dk3AttackHeld = 0;
        controller.fire(@This(), predictionShot(controller));
    }
}
