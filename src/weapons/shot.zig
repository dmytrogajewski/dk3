// SPDX-License-Identifier: GPL-2.0-or-later
//! The common ammunition and timing transaction supplied by a weapon type.
const c = @import("abi.zig").c;

pub const Shot = struct {
    cost: c_int,
    sequence: c_int,
    duration_ms: c_int,
    consume_clip: bool = false,
};

pub fn standard(controller: anytype) Shot {
    const weapon: usize = @intCast(controller.ps.weapon);
    return .{
        .cost = c.dk_weapons[weapon].ammoCost,
        .sequence = @mod(controller.ps.dk3WeaponSequence + 1, 3),
        // winfoAnimate scales frame time, then adds its fixed 100 ms tail.
        .duration_ms = controller.scaled(@max(0, c.dk_weapons[weapon].interval - 100)) + 100,
    };
}
