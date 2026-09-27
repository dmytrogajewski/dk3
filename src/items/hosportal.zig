// SPDX-License-Identifier: GPL-2.0-or-later
//! The station and fountain share transfer rules, with class-owned media and hulls.
const std = @import("std");
pub const render_tag = 10031;
pub const Kind = enum { large, medium, small, fountain };
pub const Definition = struct { model: []const u8, top: f32, particle_sound: []const u8, recharged_sound: []const u8 = "global/h_recharged.wav", empty_sound: []const u8 = "global/h_healthup.wav" };
pub fn definition(kind: Kind) Definition {
    return switch (kind) {
        .large => .{ .model = "models/e1/hosportal1.dkm", .top = 36, .particle_sound = "global/h_hfx.wav" },
        .medium => .{ .model = "models/e1/hosportal2.dkm", .top = 24, .particle_sound = "global/h_hfx.wav" },
        .small => .{ .model = "models/e1/hosportal3.dkm", .top = 24, .particle_sound = "global/h_hfx.wav" },
        .fountain => .{ .model = "models/e2/a2_hlthfnt.dkm", .top = 8, .particle_sound = "global/e_pondwaterb.wav", .recharged_sound = "", .empty_sound = "" },
    };
}
pub const Phase = enum { ready, giving, recharging };
pub const Cue = enum { none, effects, recharged, empty };
pub const State = struct {
    kind: Kind = .large,
    capacity: u32 = 100,
    // The authored maximum is parsed after the initial 100-unit fill.
    charge: u32 = 100,
    phase: Phase = .ready,
    recipient: u32 = 0,
    next_ms: ?i64 = null,
    effect_ms: ?i64 = null,
    pub fn use(self: *State, recipient: u32, health: i32, maximum: i32, eligible: bool, now: i64) Cue {
        if (self.phase != .ready) return .recharged;
        if (!eligible or health <= 0) return .none;
        if (health >= maximum) return .recharged;
        self.recipient = recipient;
        self.phase = .giving;
        self.next_ms = now + 100;
        self.effect_ms = now;
        return .effects;
    }
    fn reset(self: *State, now: i64) void {
        self.phase = .recharging;
        self.recipient = 0;
        self.next_ms = now + 100;
    }
    pub fn tick(self: *State, health: ?*i32, maximum: i32, eligible: bool, now: i64) Cue {
        const at = self.next_ms orelse return .none;
        if (now < at) return .none;
        switch (self.phase) {
            .ready => return .none,
            .recharging => {
                if (self.charge < self.capacity) {
                    self.charge += 1;
                    self.next_ms = now + 100;
                    return .none;
                }
                self.phase = .ready;
                self.next_ms = null;
                return .recharged;
            },
            .giving => {
                const current = health orelse { self.reset(now); return .none; };
                if (!eligible or current.* <= 0) { self.reset(now); return .none; }
                if (current.* >= maximum) { self.reset(now); return .recharged; }
                if (self.charge == 0) { self.reset(now); return .empty; }
                current.* += 1;
                self.charge -= 1;
                self.next_ms = now + 200;
                if (self.effect_ms == null or now - self.effect_ms.? >= 2000) {
                    self.effect_ms = now;
                    return .effects;
                }
                return .none;
            },
        }
    }
    pub fn frame(self: State) i32 { return @intFromBool(self.phase != .recharging); }
};
test "healing requires continuing proximity and facing, then locks until replenished" {
    const t = std.testing;
    var state: State = .{ .capacity = 2, .charge = 2 };
    var health: i32 = 95;
    try t.expectEqual(Cue.none, state.use(7, health, 100, false, 1000));
    try t.expectEqual(Cue.effects, state.use(7, health, 100, true, 1000));
    _ = state.tick(&health, 100, true, 1099);
    try t.expectEqual(@as(i32, 95), health);
    _ = state.tick(&health, 100, true, 1100);
    try t.expectEqual(@as(i32, 96), health);
    try t.expectEqual(@as(u32, 1), state.charge);
    _ = state.tick(&health, 100, false, 1300);
    try t.expectEqual(Phase.recharging, state.phase);
    try t.expectEqual(Cue.recharged, state.use(9, 50, 100, true, 1300));
    _ = state.tick(null, 0, false, 1400);
    try t.expectEqual(Cue.recharged, state.tick(null, 0, false, 1500));
    try t.expectEqual(Phase.ready, state.phase);
    try t.expectEqual(@as(u32, 2), state.charge);
}
test "initial station fill is independent of authored recharge capacity" {
    const t = std.testing;
    var state: State = .{ .capacity = 50 };
    var health: i32 = 99;
    _ = state.use(7, health, 100, true, 1000);
    _ = state.tick(&health, 100, true, 1100);
    try t.expectEqual(@as(i32, 100), health);
    try t.expectEqual(Cue.recharged, state.tick(&health, 100, true, 1300));
    try t.expectEqual(Cue.recharged, state.tick(null, 0, false, 1400));
    try t.expectEqual(@as(u32, 99), state.charge);
}
