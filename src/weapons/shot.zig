// SPDX-License-Identifier: GPL-2.0-or-later
//! The common ammunition and timing transaction supplied by a weapon type.

pub const Shot = struct {
    cost: c_int,
    sequence: c_int,
    duration_ms: c_int,
    consume_clip: bool = false,
};

pub fn standard(controller: anytype) Shot {
    const weapon = controller.ps.weapon;
    return .{
        .cost = controller.ammoCost(weapon),
        .sequence = @mod(controller.ps.dk3WeaponSequence + 1, 3),
        // winfoAnimate scales frame time, then adds its fixed 100 ms tail.
        .duration_ms = controller.scaled(@max(0, controller.interval(weapon) - 100)) + 100,
    };
}
