// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 28;
pub const spec: profiles.Spec = .{
    .combat = .flashlight,
    .companion_pickup = false,
    .auto_select = false,
    .droppable = false, // flashlight
    .animation = .{ .view_model = "models/e2/w_sflare.dkm", .ready = "ready", .away = "away", .fire = "shoota", .idle = .{ "amba", null, null } },
};
pub const identity = .{ .classname = "weapon_flashlight", .label = "Flashlight", .episode = 0, .interval = 300 };

const shot_rules = @import("../shot.zig");
pub const Light = struct { owner: u32, expires_ms: i64, strength: f32 };
pub const rays = [_][2]f32{ .{ 0, 0 }, .{ -4, 0 }, .{ 4, 0 }, .{ 0, -4 }, .{ 0, 4 } };
pub fn power(ammunition: i32) f32 {
    const remaining = @as(f32, @floatFromInt(@divTrunc(@max(0, ammunition), 10))) / 50;
    return if (remaining <= 0) 0 else if (remaining >= 1) 1 else 0.5 + remaining * 0.5;
}
pub fn radius(distance: f32, strength: f32) f32 {
    return @max(75, (75 + distance * 0.15) * strength);
}
pub fn brightness(distance: f32, strength: f32) f32 {
    return strength * (if (distance > 0) @min(1, 200000 / (distance * distance)) else @as(f32, 1));
}
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.duration_ms = 100;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
test "flashlight battery has the reference display threshold and softened dimming" {
    const std = @import("std");
    try std.testing.expectEqual(@as(f32, 0), power(9));
    try std.testing.expectApproxEqAbs(@as(f32, 0.51), power(10), 0.001);
    try std.testing.expectEqual(@as(f32, 1), power(500));
    try std.testing.expectEqual(@as(f32, 0.2), brightness(1000, 1));
}
