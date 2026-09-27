// SPDX-License-Identifier: GPL-2.0-or-later
//! Froginator decisions and authored attack events, independent of engine transport.
const std = @import("std");
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc" };
pub const spit_model = "models/e1/me_sludge.dkm";
pub const jump_sounds = [_][]const u8{ "e1/m_frogjumpa.wav", "e1/m_frogamba.wav" };
pub const landing_sound = "e1/m_frogambb.wav";
/// A short floor probe can settle the small rebound at the end of a jump.
/// Fast upward launch/rebound motion must remain airborne.
pub fn acceptsFloor(upward: f32, normal_z: f32) bool {
    return upward <= 100 and normal_z >= 0.7;
}

test "frog landing admits the captured low rebound without cancelling launch or wall bounce" {
    try std.testing.expect(acceptsFloor(13.333, 1));
    try std.testing.expect(acceptsFloor(-40, 1));
    try std.testing.expect(acceptsFloor(100, 0.7));
    try std.testing.expect(!acceptsFloor(100.01, 1));
    try std.testing.expect(!acceptsFloor(300, 1));
    try std.testing.expect(!acceptsFloor(13.333, 0.69));
    try std.testing.expect(!acceptsFloor(-40, 0));
}
pub const Spit = struct { owner: u32, damage: f32, born_ms: i64, stepped_ms: i64 };
pub const Tuning = struct {
    damage: f32 = 0,
    random_damage: f32 = 0,
    speed: f32 = 0,
    range: f32 = 0,
    upward: f32 = 0,
    offset: [3]f32 = @splat(0),
    pub fn parse(row: anytype) !Tuning {
        var value: Tuning = .{
            .damage = try row.number("weapon2_base_damage", 0),
            .random_damage = try row.number("weapon2_random_damage", 0),
            .speed = try row.number("weapon2_speed", 0),
            .range = try row.number("weapon2_distance", 0),
            .upward = try row.number("upward_velocity", 0),
        };
        inline for (.{ "x", "y", "z" }, 0..) |axis, i| value.offset[i] = try row.number("weapon2_offset_" ++ axis, 0);
        if (value.damage <= 0 or value.damage > 1000000 or value.random_damage < 0 or value.random_damage > 1000000 or value.speed <= 0 or value.speed > 65536 or value.range <= 0 or value.range > 65536 or value.upward <= 0 or value.upward > 2000) return error.InvalidFroginatorTuning;
        return value;
    }
};
pub const State = struct {
    phase: enum { decide, chase, spit, bite, jump } = .decide,
    started_ms: i64 = 0,
    fired: u2 = 0,
    sounded: bool = false,
    pub fn pose(self: State) usize {
        return switch (self.phase) {
            .spit => 0,
            .bite => 1,
            .jump => 2,
            else => 0,
        };
    }
    pub fn enter(self: *State, phase: @FieldType(State, "phase"), now: i64) void {
        self.* = .{ .phase = phase, .started_ms = now };
    }
    pub fn choose(self: *State, now: i64, distance: f32, range: f32, dry: bool, ranged: bool, random: f32) void {
        if (self.phase == .decide) {
            if (distance < 400 and ranged and random < 0.4 and (dry or distance <= 80)) {
                self.enter(if (distance > 80) .spit else .bite, now);
            } else self.enter(.chase, now);
        } else if (self.phase == .chase) {
            if (distance > 200 and distance < 425 and random > 0.65) self.enter(.jump, now) else if (distance <= range) self.enter(.bite, now);
        }
    }
    pub fn strikes(self: *State, now: i64, first: i64, second: ?i64) u2 {
        var count: u2 = 0;
        if (self.fired & 1 == 0 and now >= self.started_ms + first) {
            self.fired |= 1;
            count += 1;
        }
        if (second) |at| if (self.fired & 2 == 0 and now >= self.started_ms + at) {
            self.fired |= 2;
            count += 1;
        };
        return count;
    }
};
test "frog preserves difficulty and water restrictions and both supplied bite strikes" {
    const t = std.testing;
    var frog: State = .{};
    frog.choose(100, 300, 60, true, false, 0);
    try t.expectEqual(.chase, frog.phase);
    frog.enter(.decide, 100);
    frog.choose(100, 300, 60, false, true, 0);
    try t.expectEqual(.chase, frog.phase);
    frog.enter(.decide, 100);
    frog.choose(100, 300, 60, true, true, 0);
    try t.expectEqual(.spit, frog.phase);
    frog.enter(.bite, 1000);
    try t.expectEqual(@as(u2, 0), frog.strikes(1599, 600, 1400));
    try t.expectEqual(@as(u2, 1), frog.strikes(1600, 600, 1400));
    try t.expectEqual(@as(u2, 1), frog.strikes(2400, 600, 1400));
    try t.expectEqual(@as(u2, 0), frog.strikes(2500, 600, 1400));
}
