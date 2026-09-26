// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const rules = @import("weapon_catalog").character;
pub const Attribute = enum(u3) { power, attack, speed, acro, vita };
pub const State = struct {
    attributes: [5]i32 = @splat(0),
    boost_until: [5]i64 = @splat(0),
    invincible_until: i64 = 0,
    invisible_until: i64 = 0,
    environment_until: i64 = 0,
    rings: u32 = 0,
    save_gems: i32 = 0,
    level: i32 = 1,
    experience: i32 = 0,
    points: i32 = 0,
    pub fn attribute(self: State, which: Attribute, now: i64) i32 {
        const index = @intFromEnum(which);
        return rules.attribute(self.attributes[index], self.boost_until[index], now);
    }
    pub fn boost(self: *State, which: Attribute, now: i64) bool {
        const index = @intFromEnum(which);
        if (self.attributes[index] >= 5) return false;
        self.boost_until[index] = now + 30000;
        return true;
    }
    pub fn award(self: *State, amount: i32) !u8 {
        if (amount <= 0) return 0;
        self.experience = std.math.add(i32, self.experience, amount) catch return error.ExperienceOverflow;
        var gained: u8 = 0;
        while (self.level < 25 and self.experience >= rules.experienceThreshold(self.level)) {
            self.level += 1;
            self.points += 1;
            gained += 1;
        }
        return gained;
    }
    pub fn spend(self: *State, which: Attribute) bool {
        const index = @intFromEnum(which);
        if (self.points <= 0 or self.attributes[index] >= 5) return false;
        self.attributes[index] += 1;
        self.points -= 1;
        return true;
    }
};
pub const Ailments = struct {
    mask: u32 = 0,
    freeze_level: f32 = 0,
    pub fn cure(self: *Ailments) void {
        self.mask &= ~@as(u32, 7);
        self.freeze_level = 0;
    }
};
pub fn attributeNamed(name: []const u8) ?Attribute {
    inline for (std.meta.fields(Attribute)) |field| if (std.ascii.eqlIgnoreCase(name, field.name)) return @enumFromInt(field.value);
    return null;
}
test "level awards accrue points; spending and boosts respect the attribute cap" {
    var state: State = .{};
    try std.testing.expectEqual(@as(u8, 3), try state.award(2000));
    try std.testing.expectEqual(@as(i32, 4), state.level);
    try std.testing.expect(state.spend(.speed));
    try std.testing.expectEqual(@as(i32, 2), state.points);
    try std.testing.expect(state.boost(.speed, 100));
    try std.testing.expectEqual(@as(i32, 2), state.attribute(.speed, 30099));
    try std.testing.expectEqual(@as(i32, 1), state.attribute(.speed, 30100));
    state.attributes[2] = 5;
    try std.testing.expect(!state.boost(.speed, 40000));
    try std.testing.expect(!state.spend(.speed));
    var ailments: Ailments = .{ .mask = 7 | 128, .freeze_level = 0.8 };
    ailments.cure();
    try std.testing.expectEqual(@as(u32, 128), ailments.mask);
}
