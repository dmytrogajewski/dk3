// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
pub fn candidate(distance_from_start: f32, active_range: f32, horizontal: f32, vertical: f32, yaw_delta: f32, walk_speed: f32) bool {
    return !(horizontal < walk_speed * 0.2 and @abs(vertical) < 32) and distance_from_start < active_range and @abs(@mod(yaw_delta + 180, 360) - 180) <= 90;
}
