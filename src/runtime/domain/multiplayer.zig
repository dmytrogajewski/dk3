// SPDX-License-Identifier: GPL-2.0-or-later
//! Native match participants and objective transitions. No engine-owned gameplay state.
const std = @import("std");
pub const Team = enum(u8) { free, red, blue, spectator };
pub const Session = struct {
    team: Team = .free,
    score: i32 = 0,
    deaths: u32 = 0,
    captures: u32 = 0,
    respawn_ms: i64 = 0,
    joined_ms: i64 = 0,
    bot: bool = false,
    appearance: u8 = 0,
    ready: bool = false,
    pose: @import("player_pose.zig").State = .{},
};
pub fn allied(a: Session, b: Session) bool {
    return (a.team == .red or a.team == .blue) and a.team == b.team;
}
// The objective owns its authored presentation; network team identity is separate
// from the map-selected color. Model frames are supplied character fit variants.
pub const flag_model = "models/global/a_ctf_flagl.dkm";
pub const pack_model = "models/global/dt_bpack.dkm";
pub const stand_frame = 3;
pub const carry_frames = [3]i32{ 4, 6, 5 };
pub const color_skins = [8][]const u8{
    "models/objectives/ctf/1.skin", "models/objectives/ctf/2.skin",
    "models/objectives/ctf/3.skin", "models/objectives/ctf/4.skin",
    "models/objectives/ctf/5.skin", "models/objectives/ctf/6.skin",
    "models/objectives/ctf/7.skin", "models/objectives/ctf/8.skin",
};
pub fn color(team: Team, supplied: i32) u8 {
    return if (supplied >= 1 and supplied <= 8) @intCast(supplied) else if (team == .blue) 2 else 1;
}
pub fn appearance(selected: u8, team_color: u8) u8 {
    const rows = [8]u8{ 7, 2, 3, 0, 1, 4, 5, 6 };
    std.debug.assert(team_color >= 1 and team_color <= 8);
    return rows[team_color - 1] * 3 + selected % 3;
}
pub fn acceptsCapture(flags: u32, team: Team, bomb: bool) bool {
    if (team != .red and team != .blue) return false;
    const selected = flags & 3;
    // Shared pads are authored for deathtag. CTF's spawn routine rejects them.
    return selected == @intFromEnum(team) or (bomb and (selected == 0 or selected == 3));
}
pub const Defense = struct {
    base: bool = false,
    flag: bool = false,
    enemy_carrier: bool = false,
    escort: bool = false,
    pub fn score(self: Defense) i32 {
        return @as(i32, @intFromBool(self.base)) + @as(i32, @intFromBool(self.flag)) +
            @as(i32, @intFromBool(self.enemy_carrier)) * 2 + @as(i32, @intFromBool(self.escort));
    }
};

test "CTF scoring stacks defense conditions and capture pad rules differ from deathtag" {
    const t = std.testing;
    try t.expectEqual(@as(i32, 5), (Defense{ .base = true, .flag = true, .enemy_carrier = true, .escort = true }).score());
    try t.expectEqual(@as(i32, 2), (Defense{ .enemy_carrier = true }).score());
    try t.expect(!acceptsCapture(3, .red, false));
    try t.expect(acceptsCapture(3, .red, true));
    try t.expect(acceptsCapture(0, .blue, true));
    try t.expect(!acceptsCapture(1, .blue, true));
    try t.expect(!acceptsCapture(0, .spectator, true));
    try t.expectEqual(@as(u8, 23), appearance(2, color(.red, 0)));
    try t.expectEqual(@as(u8, 8), appearance(23, color(.blue, 0)));
    try t.expectEqual(@as(u8, 4), appearance(1, color(.red, 5)));
}

pub const Objective = struct {
    team: Team,
    color: u8 = 0,
    phase: enum { home, carried, dropped, planted, resetting } = .home,
    carrier: ?u32 = null,
    home: [3]f32,
    angles: [3]f32,
    deadline: ?i64 = null,
    pickup_ms: i64 = 0,
    beep_ms: i64 = 0,
    velocity: [3]f32 = @splat(0),
    airborne: bool = false,
    stepped_ms: i64 = 0,
    pub fn reset(self: *Objective) void {
        self.phase = .home;
        self.carrier = null;
        self.deadline = null;
        self.pickup_ms = 0;
        self.beep_ms = 0;
        self.velocity = @splat(0);
        self.airborne = false;
    }
    pub fn take(self: *Objective, player: u32, team: Team, bomb: bool, now: i64) enum { none, taken, returned, detonate } {
        if (team != .red and team != .blue) return .none;
        if ((self.phase != .home and self.phase != .dropped) or now < self.pickup_ms) return .none;
        if (bomb and team != self.team) return if (self.phase == .dropped) .detonate else .none;
        if (!bomb and team == self.team) {
            if (self.phase != .dropped) return .none;
            self.reset();
            return .returned;
        }
        if (bomb and self.phase == .home) {
            self.deadline = now + 90000;
            self.beep_ms = now + 80000;
        }
        if (!bomb) self.deadline = null;
        self.phase = .carried;
        self.carrier = player;
        self.airborne = false;
        self.velocity = @splat(0);
        return .taken;
    }
    pub fn drop(self: *Objective, bomb: bool, now: i64) void {
        if (self.phase != .carried) return;
        self.phase = .dropped;
        self.carrier = null;
        self.pickup_ms = now;
        self.airborne = true;
        self.stepped_ms = now;
        if (!bomb) self.deadline = now + 60000;
    }
    pub fn capture(self: *Objective, bomb: bool, now: i64) void {
        if (!bomb) return self.reset();
        self.phase = .planted;
        self.carrier = null;
        self.deadline = @min(self.deadline orelse now, now + 5000);
        self.beep_ms = @min(self.beep_ms, self.deadline.? - 10000);
        self.velocity = @splat(0);
        self.airborne = true;
        self.stepped_ms = now;
    }
    pub fn tick(self: *Objective, now: i64) bool {
        const due = self.deadline orelse return false;
        if (self.phase == .home or self.phase == .resetting or now >= due or now < self.beep_ms) return false;
        self.beep_ms = now + 1000;
        return true;
    }
};

test "deathtag fuse survives a drop and transfer and a capture shortens it" {
    const t = std.testing;
    var flag: Objective = .{ .team = .red, .home = @splat(0), .angles = @splat(0) };
    try t.expectEqual(.none, flag.take(3, .blue, true, 1000));
    try t.expectEqual(.taken, flag.take(1, .red, true, 1000));
    flag.drop(true, 2000);
    try t.expectEqual(.taken, flag.take(2, .red, true, 2000));
    try t.expectEqual(@as(?i64, 91000), flag.deadline);
    try t.expect(!flag.tick(80999));
    try t.expect(flag.tick(81000));
    try t.expect(!flag.tick(81999));
    flag.capture(true, 82000);
    try t.expectEqual(@as(?i64, 87000), flag.deadline);
    try t.expect(flag.tick(82000));
    try t.expectEqual(.none, flag.take(3, .blue, true, 83000));
    flag.reset();
    try t.expectEqual(@as(?i64, null), flag.deadline);
    try t.expectEqual(@as(?u32, null), flag.carrier);
}
