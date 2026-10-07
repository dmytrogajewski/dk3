// SPDX-License-Identifier: GPL-2.0-or-later
//! Ten-level multiplayer bot skill: shared perception, reaction, turning and aim policy.
//! Pure tables so the hosting menu, room services and the server brain agree on one ladder.
const std = @import("std");
const v = @import("vector.zig");
pub const minimum: i32 = 1;
pub const maximum: i32 = 10;
pub const fallback: i32 = 5;
pub const tiers = [_][]const u8{ "Novice", "Beginner", "Casual", "Average", "Capable", "Skilled", "Expert", "Master", "Elite", "Merciless" };
pub const Profile = struct {
    /// Total view cone in degrees. Targets outside it are unseen until the bot turns.
    field_of_view: f32,
    /// Close range that does not require facing, mirroring actor proximity senses.
    peripheral_range: f32,
    /// Farthest target the bot can notice at all, inside or outside cover.
    sight_range: f32,
    /// How long a target stays remembered after it leaves the view cone.
    memory_ms: i64,
    /// Delay between a target entering the cone and the first shot at it.
    reaction_ms: i64,
    /// Maximum view rotation in degrees per second, for aiming and for scanning.
    turn_rate: f32,
    /// Angular aim error at acquisition in degrees; it decays over settle_ms.
    aim_error: f32,
    /// Time tracking a target before the aim error disappears.
    settle_ms: i64,
    /// Interval between fresh error directions.
    wobble_ms: i64,
    /// Minimum interval between two shots, independent of the weapon's own cycle.
    burst_ms: i64,
    /// How long one search heading is held while the bot looks around.
    scan_period_ms: i64,
    /// Bearing error when turning toward the last gunshot heard.
    alert_error: f32,
    /// How long gunfire keeps the bot facing its shooter instead of scanning.
    alert_ms: i64,
    /// Steps out of incoming shots and forecast splash (and strafes while
    /// holding a fight). Off at the bottom of the ladder.
    evasion: bool = true,
    /// Share of a projectile's flight time the aim leads a moving target by.
    lead: f32 = 1,
    /// Fire only once the view is this close to the aim point (cosine of the
    /// tolerated angle): looser low on the ladder, so a bot still settling
    /// its aim shoots anyway, and misses.
    discipline: f32 = 0.995,
};
/// skill 1 is the least dangerous and skill 10 keeps the previous perfect-play behaviour.
const profiles = [_]Profile{
    .{ .field_of_view = 80, .peripheral_range = 128, .sight_range = 512, .memory_ms = 400, .reaction_ms = 700, .turn_rate = 140, .aim_error = 9, .settle_ms = 1400, .wobble_ms = 420, .burst_ms = 500, .scan_period_ms = 1100, .alert_error = 60, .alert_ms = 4000, .evasion = false, .lead = 0, .discipline = 0.96 },
    .{ .field_of_view = 90, .peripheral_range = 144, .sight_range = 640, .memory_ms = 500, .reaction_ms = 560, .turn_rate = 180, .aim_error = 7.5, .settle_ms = 1250, .wobble_ms = 380, .burst_ms = 400, .scan_period_ms = 1000, .alert_error = 52, .alert_ms = 3600, .evasion = false, .lead = 0, .discipline = 0.965 },
    .{ .field_of_view = 100, .peripheral_range = 160, .sight_range = 768, .memory_ms = 600, .reaction_ms = 450, .turn_rate = 220, .aim_error = 6, .settle_ms = 1100, .wobble_ms = 340, .burst_ms = 320, .scan_period_ms = 950, .alert_error = 44, .alert_ms = 3200, .evasion = false, .lead = 0.25, .discipline = 0.97 },
    .{ .field_of_view = 110, .peripheral_range = 176, .sight_range = 900, .memory_ms = 700, .reaction_ms = 360, .turn_rate = 280, .aim_error = 4.5, .settle_ms = 950, .wobble_ms = 300, .burst_ms = 260, .scan_period_ms = 900, .alert_error = 36, .alert_ms = 2800, .evasion = false, .lead = 0.4, .discipline = 0.975 },
    .{ .field_of_view = 120, .peripheral_range = 192, .sight_range = 1024, .memory_ms = 800, .reaction_ms = 290, .turn_rate = 340, .aim_error = 3.5, .settle_ms = 800, .wobble_ms = 260, .burst_ms = 200, .scan_period_ms = 850, .alert_error = 30, .alert_ms = 2500, .evasion = true, .lead = 0.55, .discipline = 0.98 },
    .{ .field_of_view = 130, .peripheral_range = 208, .sight_range = 1152, .memory_ms = 1000, .reaction_ms = 230, .turn_rate = 420, .aim_error = 2.5, .settle_ms = 650, .wobble_ms = 220, .burst_ms = 160, .scan_period_ms = 800, .alert_error = 24, .alert_ms = 2200, .evasion = true, .lead = 0.65, .discipline = 0.985 },
    .{ .field_of_view = 140, .peripheral_range = 224, .sight_range = 1280, .memory_ms = 1200, .reaction_ms = 180, .turn_rate = 520, .aim_error = 1.8, .settle_ms = 520, .wobble_ms = 180, .burst_ms = 120, .scan_period_ms = 750, .alert_error = 18, .alert_ms = 2000, .evasion = true, .lead = 0.75, .discipline = 0.988 },
    .{ .field_of_view = 150, .peripheral_range = 240, .sight_range = 1400, .memory_ms = 1600, .reaction_ms = 140, .turn_rate = 640, .aim_error = 1.2, .settle_ms = 400, .wobble_ms = 150, .burst_ms = 90, .scan_period_ms = 700, .alert_error = 12, .alert_ms = 1800, .evasion = true, .lead = 0.85, .discipline = 0.99 },
    .{ .field_of_view = 160, .peripheral_range = 256, .sight_range = 1536, .memory_ms = 2000, .reaction_ms = 110, .turn_rate = 800, .aim_error = 0.7, .settle_ms = 300, .wobble_ms = 120, .burst_ms = 60, .scan_period_ms = 650, .alert_error = 8, .alert_ms = 1600, .evasion = true, .lead = 0.95, .discipline = 0.993 },
    .{ .field_of_view = 170, .peripheral_range = 288, .sight_range = 1792, .memory_ms = 2600, .reaction_ms = 60, .turn_rate = 2400, .aim_error = 0.2, .settle_ms = 200, .wobble_ms = 100, .burst_ms = 30, .scan_period_ms = 600, .alert_error = 4, .alert_ms = 1400, .evasion = true, .lead = 1, .discipline = 0.995 },
};
pub fn normalize(skill: i32) i32 {
    return std.math.clamp(skill, minimum, maximum);
}
pub fn tier(skill: i32) []const u8 {
    return tiers[@intCast(normalize(skill) - minimum)];
}
/// Authored single-player actors keep their accepted five-level scale.
pub fn singlePlayer(skill: i32) i32 {
    return std.math.clamp(@divTrunc(normalize(skill) + 1, 2), minimum, 5);
}
pub fn profile(skill: i32) Profile {
    return profiles[@intCast(normalize(skill) - minimum)];
}
/// Yaw in degrees for a world direction, matching the engine's view-angle convention.
pub fn yaw(direction: v.Vec3) f32 {
    return std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi;
}
/// Pitch in degrees for a world direction; negative looks up, as the server expects.
pub fn pitch(direction: v.Vec3) f32 {
    return -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi;
}
pub fn wrap(angle: f32) f32 {
    return @mod(angle, 360);
}
/// Rotate yaw toward the wanted heading by at most `limit` degrees, taking the short way round.
pub fn turn(current: f32, wanted: f32, limit: f32) f32 {
    const delta = @mod(wanted - current + 180, 360) - 180;
    if (delta > limit) return wrap(current + limit);
    if (delta < -limit) return wrap(current - limit);
    return wrap(wanted);
}
/// Pitch is not cyclic and stays inside the range the server accepts.
pub fn pitchTurn(current: f32, wanted: f32, limit: f32) f32 {
    const delta = std.math.clamp(wanted - current, -limit, limit);
    return std.math.clamp(current + delta, -89, 89);
}
/// The bot's own view cone: what is in front of it, within range, plus close proximity.
pub fn sees(policy: Profile, forward: v.Vec3, eye: v.Vec3, target: v.Vec3) bool {
    const offset = v.subtract(target, eye);
    const distance = v.length(offset);
    if (distance > policy.sight_range) return false;
    if (distance <= policy.peripheral_range) return true;
    const cosine = v.dot(v.scale(offset, 1 / distance), forward);
    return cosine >= @cos(policy.field_of_view * std.math.pi / 360);
}
/// Deterministic bounded noise so aim error and heard-gunfire bearing stay reproducible.
pub fn noise(seed: *u32) f32 {
    seed.* ^= @as(u32, @truncate(seed.* << 13));
    seed.* ^= seed.* >> 17;
    seed.* ^= seed.* << 5;
    if (seed.* == 0) seed.* = 0x9e3779b9;
    return @as(f32, @floatFromInt(seed.* & 0x7fffff)) / 4194304 - 1;
}
test "skill ladder is monotone and covers one to ten" {
    const t = std.testing;
    try t.expectEqual(@as(i32, 1), normalize(-4));
    try t.expectEqual(@as(i32, 10), normalize(44));
    try t.expectEqualStrings("Novice", tier(0));
    try t.expectEqualStrings("Merciless", tier(11));
    var previous: ?Profile = null;
    for (minimum..maximum + 1) |skill| {
        const current = profile(@intCast(skill));
        try t.expectEqualStrings(tiers[skill - 1], tier(@intCast(skill)));
        if (previous) |older| {
            try t.expect(current.field_of_view > older.field_of_view);
            try t.expect(current.sight_range > older.sight_range);
            try t.expect(current.reaction_ms < older.reaction_ms);
            try t.expect(current.turn_rate > older.turn_rate);
            try t.expect(current.aim_error < older.aim_error);
            try t.expect(current.burst_ms < older.burst_ms);
            try t.expect(current.memory_ms > older.memory_ms);
        }
        previous = current;
    }
    try t.expectEqual(@as(i32, 1), singlePlayer(1));
    try t.expectEqual(@as(i32, 3), singlePlayer(5));
    try t.expectEqual(@as(i32, 5), singlePlayer(10));
}
test "a bot only sees inside its cone and nearby targets do not require facing" {
    const t = std.testing;
    const policy = profile(5);
    const eye: v.Vec3 = @splat(0);
    const forward: v.Vec3 = .{ 1, 0, 0 };
    try t.expect(sees(policy, forward, eye, .{ 500, 0, 0 }));
    try t.expect(!sees(policy, forward, eye, .{ -500, 0, 0 }));
    try t.expect(!sees(policy, forward, eye, .{ 0, 900, 0 }));
    try t.expect(!sees(policy, forward, eye, .{ 5000, 0, 0 }));
    try t.expect(sees(policy, forward, eye, .{ -100, -60, 0 })); // Close enough to notice by proximity.
    try t.expect(!sees(policy, .{ 0, 1, 0 }, eye, .{ 500, 0, 0 })); // Turning away hides the same target.
}
test "turning is rate limited and takes the short way around" {
    const t = std.testing;
    try t.expectApproxEqAbs(@as(f32, 20), turn(0, 90, 20), 0.001);
    try t.expectApproxEqAbs(@as(f32, 90), turn(0, 90, 180), 0.001);
    try t.expectApproxEqAbs(@as(f32, 340), turn(0, -30, 20), 0.001);
    try t.expectApproxEqAbs(@as(f32, 10), turn(350, 160, 20), 0.001);
    try t.expectApproxEqAbs(@as(f32, 340), turn(0, -90, 20), 0.001); // Yaw is reported wrapped into 0..360.
    try t.expectApproxEqAbs(@as(f32, 45), yaw(.{ 1, 1, 0 }), 0.001);
    try t.expectApproxEqAbs(@as(f32, -45), pitch(.{ 1, 0, 1 }), 0.001);
    try t.expectApproxEqAbs(@as(f32, -20), pitchTurn(0, -90, 20), 0.001);
    try t.expectApproxEqAbs(@as(f32, -89), pitchTurn(-85, -180, 20), 0.001);
}
test "an enemy at the bot's back is only acquired after it turns around" {
    const t = std.testing;
    const target: v.Vec3 = .{ -400, 0, 0 }; // Behind, inside every level's sight range.
    var ticks: [maximum]usize = @splat(0);
    for (minimum..maximum + 1) |level| {
        const policy = profile(@intCast(level));
        var heading: f32 = 0;
        while (ticks[@intCast(level - minimum)] < 400) : (ticks[@intCast(level - minimum)] += 1) {
            const radians = heading * std.math.pi / 180;
            if (sees(policy, .{ @cos(radians), @sin(radians), 0 }, @splat(0), target)) break;
            heading = turn(heading, yaw(target), policy.turn_rate * 0.05); // One 50 ms brain step.
        }
        try t.expect(ticks[@intCast(level - minimum)] < 400); // No level is permanently blind.
    }
    for (ticks) |count| try t.expect(count > 0); // Nothing is visible through the back of the head.
    for (ticks[1..], ticks[0 .. ticks.len - 1]) |later, earlier| try t.expect(later <= earlier);
    try t.expect(ticks[maximum - 1] < ticks[0]); // Merciless notices the ambush far sooner.
}
test "aim noise is bounded and repeats for one seed" {
    const t = std.testing;
    var seed: u32 = 12345;
    var first: [8]f32 = undefined;
    for (&first) |*value| value.* = noise(&seed);
    for (first) |value| try t.expect(value >= -1 and value <= 1);
    seed = 12345;
    for (first) |value| try t.expectApproxEqAbs(value, noise(&seed), 0.0001);
    seed = 0;
    try t.expect(noise(&seed) >= -1 and noise(&seed) <= 1);
}
test "the ladder's handling knobs keep level 10 exact and grow monotonically" {
    try std.testing.expect(!profile(4).evasion and profile(5).evasion);
    try std.testing.expectEqual(@as(f32, 1), profile(10).lead);
    try std.testing.expectEqual(@as(f32, 0.995), profile(10).discipline);
    var level: i32 = minimum + 1;
    while (level <= maximum) : (level += 1) {
        try std.testing.expect(profile(level).lead >= profile(level - 1).lead);
        try std.testing.expect(profile(level).discipline > profile(level - 1).discipline);
    }
}
