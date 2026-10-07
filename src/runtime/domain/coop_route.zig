// SPDX-License-Identifier: GPL-2.0-or-later
//! Scripted co-op bot actions: typed requests decoded from route scripts and
//! their pure geometry/completion rules. Execution lives in server/coop_bot.zig;
//! every action is carried out through ordinary player commands.
const std = @import("std");
const v = @import("vector.zig");
const catalog = @import("actor_catalog");
pub const Vec3 = v.Vec3;
/// Script-supplied names are copied out of the Lua stack before it unwinds.
pub const Name = struct {
    bytes: [64]u8 = @splat(0),
    len: u8 = 0,
    pub fn from(text: []const u8) !Name {
        if (text.len > 64) return error.NameTooLong;
        var result: Name = .{ .len = @intCast(text.len) };
        @memcpy(result.bytes[0..text.len], text);
        return result;
    }
    pub fn slice(self: *const Name) []const u8 {
        return self.bytes[0..self.len];
    }
    pub fn empty(self: Name) bool {
        return self.len == 0;
    }
};
/// Selects world entities by authored identity, never by engine slot.
pub const Target = struct {
    name: Name = .{},
    class: Name = .{},
    id: u32 = 0,
    /// Authored BSP entity index within the current map (1 = worldspawn).
    index: u32 = 0,
    point: ?Vec3 = null,
    /// Among several matches, prefer the one nearest this point (default: the bot).
    near: ?Vec3 = null,
    pub fn entityless(self: Target) bool {
        return self.point != null and self.name.empty() and self.class.empty() and self.id == 0 and self.index == 0;
    }
};
pub const Op = enum { frame, move, touch, use, shoot, pickup, ride, kill, exit, cinematic, look, weapon, jump, leap, save, wait, finish };
pub const Action = struct {
    op: Op,
    target: ?Target = null,
    timeout_ms: i64 = 60_000,
    /// Arrival radius for move, search radius for kill.
    radius: f32 = 0,
    around: ?Vec3 = null,
    fight: bool = true,
    /// kill: engage from the current position instead of closing in.
    hold: bool = false,
    /// move: steer straight at the goal without navigation (drops into water,
    /// jumps across gaps, authored falls the area graph does not represent).
    direct: bool = false,
    /// move: hold crouch for the whole segment (low pipes, vents).
    crouch: bool = false,
    /// move: stop and fight what engages the player (held on a short tether,
    /// dodging) before going on, instead of firing on the run.
    cautious: bool = false,
    /// leap: a shotcycler jump (fired at the floor as the player jumps).
    blast: bool = false,
    /// leap: fraction of full running input, for a short hop onto a narrow
    /// ledge that a running jump would carry the player past.
    pace: f32 = 1,
    /// kill with hold: the horizontal box (min, max) dodges and strafes stay in.
    arena: ?[2][2]f32 = null,
    map: Name = .{},
    /// Save slot, or the summary text of `finish`.
    slot: Name = .{},
    duration_ms: i64 = 0,
    yaw: f32 = 0,
    pitch: f32 = 0,
    weapon: u5 = 0,
    /// kill: stop once this many matching hostiles have died (0 = all of them).
    count: u32 = 0,
    pub fn arrival(self: Action) f32 {
        return if (self.radius > 0) self.radius else 40;
    }
    pub fn searchRadius(self: Action) f32 {
        return if (self.radius > 0) self.radius else 1536;
    }
};
pub const Result = union(enum) { running, done: []const u8, failed: []const u8 };

/// Authored actors that oppose the player. Civilians, companions and ambient
/// wildlife are never kill targets, even when an encounter script angers them.
pub fn hostile(kind: catalog.Kind) bool {
    return switch (kind) {
        .civilian, .companion, .fish, .seagull => false,
        else => true,
    };
}
/// Closest origin of a hull overlapping `box`, measured from `position`. Touching
/// a thin trigger requires overlap, not placing the origin inside its centre.
pub fn contact(position: Vec3, box_mins: Vec3, box_maxs: Vec3, hull_mins: Vec3, hull_maxs: Vec3) Vec3 {
    var point = position;
    for (0..3) |axis| {
        const low = box_mins[axis] - hull_maxs[axis] + 1;
        const high = box_maxs[axis] - hull_mins[axis] - 1;
        point[axis] = if (low <= high) std.math.clamp(point[axis], low, high) else (low + high) / 2;
    }
    return point;
}
pub fn overlaps(position: Vec3, hull_mins: Vec3, hull_maxs: Vec3, box_mins: Vec3, box_maxs: Vec3) bool {
    for (0..3) |axis| {
        if (position[axis] + hull_maxs[axis] <= box_mins[axis] or position[axis] + hull_mins[axis] >= box_maxs[axis]) return false;
    }
    return true;
}
/// Horizontal arrival with a vertical allowance for step height and crouching.
pub fn arrived(position: Vec3, goal: Vec3, radius: f32) bool {
    const dx = position[0] - goal[0];
    const dy = position[1] - goal[1];
    return dx * dx + dy * dy <= radius * radius and @abs(position[2] - goal[2]) <= @max(radius, 56);
}
/// Watchdog for physical progress: the bot must reduce its distance to the goal
/// by a meaningful amount within the window, or the action is reported stuck.
pub const Progress = struct {
    best: f32 = std.math.inf(f32),
    since_ms: i64 = 0,
    pub fn update(self: *Progress, distance: f32, now: i64) void {
        if (distance < self.best - 24 or self.since_ms == 0) {
            self.best = distance;
            self.since_ms = now;
        }
    }
    pub fn stalled(self: Progress, now: i64, window_ms: i64) bool {
        return self.since_ms != 0 and now - self.since_ms >= window_ms;
    }
};

test "names, targets and arrival geometry" {
    const t = std.testing;
    const name = try Name.from("from_b");
    try t.expectEqualStrings("from_b", name.slice());
    try t.expectError(error.NameTooLong, Name.from("x" ** 65));
    try t.expect((Target{ .point = .{ 1, 2, 3 } }).entityless());
    try t.expect(!(Target{ .point = .{ 1, 2, 3 }, .class = try Name.from("weapon_ionblaster") }).entityless());
    // e1m1a's thin exit brush: the hull must overlap it, its centre is not required.
    const point = contact(.{ -200, -1400, 520 }, .{ -608, -1480, 488 }, .{ -592, -1288, 704 }, .{ -15, -15, -24 }, .{ 15, 15, 32 });
    try t.expect(overlaps(point, .{ -15, -15, -24 }, .{ 15, 15, 32 }, .{ -608, -1480, 488 }, .{ -592, -1288, 704 }));
    try t.expectApproxEqAbs(@as(f32, -592 + 15 - 1), point[0], 0.001);
    try t.expect(arrived(.{ 10, 0, 30 }, .{ 0, 0, 0 }, 40));
    try t.expect(!arrived(.{ 50, 0, 0 }, .{ 0, 0, 0 }, 40));
    try t.expect(hostile(.froginator) and !hostile(.companion) and !hostile(.civilian) and !hostile(.seagull));
}
test "progress watchdog resets only on real approach" {
    var progress: Progress = .{};
    progress.update(1000, 100);
    progress.update(990, 2000);
    try std.testing.expect(progress.stalled(5100, 5000));
    progress.update(900, 5200);
    try std.testing.expect(!progress.stalled(5300, 5000));
}
