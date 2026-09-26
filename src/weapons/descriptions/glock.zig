// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 21;
pub const spec: profiles.Spec = .{
    .combat = .{ .hitscan = .{} },
    .companion_episode = 4,
    .start_episode = 4,
    .ammo_class = "ammo_bullets", // glock
    .world_model = "models/e4/a_glock.dkm",
    .animation = .{
        .view_model = "models/e4/w_glock.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 300,
        .drop_ms = 250,
    },
    .audio = .{
        .fire = "e4/we_glockshootb.wav",
        .ready = "e4/we_glockready.wav",
        .away = "e4/we_glockaway.wav",
        .reload = "e4/we_glockreload.wav",
    },
};
pub const identity = .{ .classname = "weapon_glock", .label = "Glock", .episode = 4, .interval = 500 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.consume_clip = true;
    return result;
}

pub fn update(controller: anytype) void {
    const ps = controller.ps;
    if (ps.weaponstate == state.dropping and ps.dk3WeaponSequence == state.glock_reload_sequence) {
        if (ps.weaponTime > 0) return;
        ps.dk3GlockClip = @min(ps.ammo[id], 10);
        ps.dk3WeaponSequence = 0;
        ps.weaponstate = state.ready;
    }
    if (!controller.pressed() and ps.dk3Burst == 0) {
        controller.release();
        return;
    }
    ps.dk3AttackHeld = @intFromBool(controller.pressed());
    if (ps.weaponTime > 0) return;
    const next = predictionShot(controller);
    if (ps.dk3GlockClip <= 0 and (next.cost == 0 or ps.ammo[id] >= next.cost)) {
        ps.weaponstate = state.dropping;
        ps.weaponTime = 1650;
        ps.dk3WeaponSequence = state.glock_reload_sequence;
        return;
    }
    controller.fire(@This(), next);
    if (ps.dk3GlockClip == 0 and ps.ammo[id] > 0) {
        ps.weaponstate = state.dropping;
        ps.weaponTime = 1650;
        ps.dk3WeaponSequence = state.glock_reload_sequence;
    }
}

pub fn isReloading(ps: anytype) bool {
    return ps.weaponstate == state.dropping and ps.dk3WeaponSequence == state.glock_reload_sequence;
}
