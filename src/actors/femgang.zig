// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakb" };
pub const State = struct { idle_chosen: bool = false, idle_b: bool = false };
pub const attack_distance: f32 = 200;
pub fn select(distance: f32, reach: f32) u3 {
    return @intFromBool(distance >= reach);
}
