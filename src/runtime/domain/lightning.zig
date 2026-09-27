// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored lightning scheduling, attractor order and bolt lifetime.
const std = @import("std");
const v = @import("vector.zig");
pub const render_tag = 10038;
pub const scorch_tag = 10039;
pub const on = 1;
pub const cycle = 2;
pub const ground = 4;
pub const random_delay = 8;
pub const no_clients = 32;
pub const trace_damage = 64;
pub const once = 128;
pub const no_sparks = 256;
pub const constant = 512;
pub const scorch = 1024;
pub const Emitter = struct {
    flags: u32,
    initialized: bool = false,
    next_ms: ?i64,
    uncull_until_ms: i64,
    delay_ms: i64 = 2000,
    duration_ms: i64 = 300,
    damage: f32 = 0,
    scale: f32 = 10,
    modulation: f32 = 1,
    chance: f32 = 0.1,
    ground_chance: f32 = 0.2,
    color: v.Vec3 = .{ 0.45, 0.45, 0.75 },
    sounds: [3]u16 = @splat(0),
    loop_sound: u16 = 0,
    attractors: [32]u32 = @splat(0),
    count: u8 = 0,
    current: u32 = 0,
    pub fn branch(self: Emitter, chance_roll: f32) enum { client, ground, attractor } {
        if (self.flags & no_clients == 0 and chance_roll < self.chance) return .client;
        if (self.flags & ground != 0 and chance_roll < self.ground_chance) return .ground;
        return .attractor;
    }
    pub fn schedule(self: *Emitter, now: i64, random: f32) void {
        if (self.flags & (once | constant) != 0) return;
        self.initialized = true;
        self.next_ms = now + if (self.flags & random_delay != 0) @as(i64, @intFromFloat(random * @as(f32, @floatFromInt(self.delay_ms)))) else self.delay_ms;
    }
    pub fn choose(self: *Emitter, random: f32) ?u32 {
        if (self.count == 0) return null;
        var index: usize = 0;
        if (self.flags & cycle != 0) {
            for (self.attractors[0..self.count], 0..) |id, i| if (id == self.current) { index = i; break; };
            self.current = if (index + 1 < self.count) self.attractors[index + 1] else 0;
        } else {
            index = @min(self.count - 1, @as(usize, @intFromFloat(random * @as(f32, @floatFromInt(self.count)))));
            self.current = self.attractors[index];
        }
        return self.attractors[index];
    }
};
pub const Attractor = struct { link_ms: ?i64, linked: bool = false };
pub const Bolt = struct {
    emitter: u32,
    target: u32 = 0,
    endpoint: v.Vec3,
    next_ms: i64,
    until_ms: i64,
    damage: f32,
    check_trace: bool = true,
    pub fn expired(self: Bolt, emitter: Emitter, now: i64) bool {
        return if (emitter.flags & constant != 0) emitter.flags & on == 0 else now >= self.until_ms;
    }
    pub fn traced(self: *Bolt, emitter: Emitter) void {
        if (emitter.flags & constant == 0) self.check_trace = false;
    }
};

test "lightning chooses one branch; zero random interval does not invent a dwell" {
    const t = std.testing;
    var state: Emitter = .{ .flags = ground | random_delay, .next_ms = null, .uncull_until_ms = 3000 };
    try t.expectEqual(.client, state.branch(0.05));
    try t.expectEqual(.ground, state.branch(0.15));
    try t.expectEqual(.attractor, state.branch(0.3));
    state.flags |= no_clients;
    try t.expectEqual(.ground, state.branch(0.05));
    state.schedule(1000, 0);
    try t.expectEqual(@as(?i64, 1000), state.next_ms);
    state.flags |= once;
    state.next_ms = null;
    state.schedule(1000, 0.5);
    try t.expectEqual(@as(?i64, null), state.next_ms);
}
test "attractor cycling wraps and missing current returns to the first survivor" {
    const t = std.testing;
    var state: Emitter = .{ .flags = cycle, .next_ms = null, .uncull_until_ms = 3000 };
    state.attractors[0..3].* = .{ 7, 9, 13 }; state.count = 3;
    for ([_]u32{ 7, 9, 13, 7 }) |id| try t.expectEqual(@as(?u32, id), state.choose(0.9));
    state.current = 99;
    try t.expectEqual(@as(?u32, 7), state.choose(0));
}
test "finite bolts trace once while active and constant bolts last until switched off" {
    const t = std.testing;
    var state: Emitter = .{ .flags = on | trace_damage, .next_ms = null, .uncull_until_ms = 3000 };
    var bolt: Bolt = .{ .emitter = 1, .endpoint = @splat(0), .next_ms = 100, .until_ms = 300, .damage = 10 };
    try t.expect(!bolt.expired(state, 299));
    bolt.traced(state); try t.expect(!bolt.check_trace);
    try t.expect(bolt.expired(state, 300));
    state.flags |= constant; bolt.check_trace = true; bolt.traced(state);
    try t.expect(bolt.check_trace and !bolt.expired(state, 5000));
    state.flags &= ~@as(u32, on);
    try t.expect(bolt.expired(state, 5000));
}
