// SPDX-License-Identifier: GPL-2.0-or-later
//! One loading bar across both halves of a campaign load: the client's own
//! map and resource registration, then admission of the neighbouring maps the
//! server holds the player for. The bar never runs backwards or refills; a
//! region wait that follows registration continues from where it stopped.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;

/// Share of the bar given to the client's own registration when neighbouring
/// maps follow (each admitted neighbour costs about as much again).
pub const registration_share: f32 = 0.35;

pub const Bar = struct {
    phase: enum { idle, registering, awaiting_region, region } = .idle,
    /// Where the region half starts.
    split: f32 = 1,
    high: f32 = 0,
    started_ms: i32 = 0,
    /// Client registration begins. Single-player maps are followed by a
    /// region wait; others fill the whole bar themselves.
    pub fn begin(self: *Bar, single_player: bool, now: i32) f32 {
        self.* = .{ .phase = .registering, .split = if (single_player) registration_share else 1, .started_ms = now };
        return self.raise(0);
    }
    pub fn registration(self: *Bar, done: usize, total: usize) f32 {
        const fraction = @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(@max(1, total)));
        return self.raise(self.split * fraction);
    }
    pub fn registered(self: *Bar) f32 {
        self.phase = if (self.split < 1) .awaiting_region else .idle;
        return self.raise(self.split);
    }
    /// The server holds the player for neighbouring maps. Straight after
    /// registration the bar continues; on its own (an in-place load) it is
    /// the whole load.
    pub fn regionStart(self: *Bar, now: i32) f32 {
        switch (self.phase) {
            .awaiting_region, .region => {},
            .idle, .registering => self.* = .{ .split = 0, .started_ms = now },
        }
        self.phase = .region;
        return self.raise(self.split);
    }
    pub fn region(self: *Bar, fraction: f32) f32 {
        return self.raise(self.split + (1 - self.split) * std.math.clamp(fraction, 0, 1));
    }
    pub fn regionEnd(self: *Bar) f32 {
        self.phase = .idle;
        return self.raise(1);
    }
    fn raise(self: *Bar, value: f32) f32 {
        self.high = @max(self.high, value);
        return self.high;
    }
};
pub var bar: Bar = .{};

pub fn publish(value: f32) void {
    var text: [32]u8 = undefined;
    const progress = std.fmt.bufPrintZ(&text, "{d:.4}", .{value}) catch unreachable;
    _ = engine.gateway.call(c.CG_CVAR_SET, .{ @as([*:0]const u8, "dk3_loading_progress"), progress.ptr });
}
/// Developer timing of the load's phases (`developer 1`).
pub fn mark(label: []const u8, now: i32) void {
    if (engine.integer("developer") < 1) return;
    var text: [128]u8 = undefined;
    engine.print(std.fmt.bufPrintZ(&text, "dk3 loading: phase={s} ms={d}\n", .{ label, now - bar.started_ms }) catch return);
}

test "a campaign load fills the bar once across registration and region admission" {
    var state: Bar = .{};
    try std.testing.expectEqual(@as(f32, 0), state.begin(true, 0));
    try std.testing.expectApproxEqAbs(registration_share / 2, state.registration(5, 10), 0.0001);
    try std.testing.expectApproxEqAbs(registration_share, state.registered(), 0.0001);
    try std.testing.expectApproxEqAbs(registration_share, state.regionStart(10), 0.0001);
    const half = state.region(0.5);
    try std.testing.expect(half > registration_share and half < 1);
    // A neighbour joining the count must not pull the bar back.
    try std.testing.expectEqual(half, state.region(0.25));
    try std.testing.expectEqual(@as(f32, 1), state.regionEnd());
}
test "an in-place load's region wait is the whole bar, and arenas fill it alone" {
    var state: Bar = .{};
    _ = state.begin(true, 0);
    _ = state.registered();
    _ = state.regionStart(5);
    _ = state.regionEnd();
    try std.testing.expectEqual(@as(f32, 0), state.regionStart(9000));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), state.region(0.5), 0.0001);
    _ = state.begin(false, 0);
    try std.testing.expectEqual(@as(f32, 1), state.registered());
}
