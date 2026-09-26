// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 28;
pub const spec: profiles.Spec = .{
    .companion_pickup = false,
    .auto_select = false,
    .droppable = false, // flashlight
};
pub const identity = .{ .classname = "weapon_flashlight", .label = "Flashlight", .episode = 0, .interval = 300 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    const ps = controller.ps;
    if (!controller.pressed()) {
        controller.release();
        return;
    }
    if (ps.dk3AttackHeld != 0) return;
    ps.dk3AttackHeld = 1;
    if (ps.weaponTime <= 0) controller.fire(@This(), predictionShot(controller));
}
