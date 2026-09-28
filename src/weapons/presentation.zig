// SPDX-License-Identifier: GPL-2.0-or-later
//! Presentation transitions consume shared controller state and class-owned cues.
const std = @import("std");
const profiles = @import("profiles.zig");
const controller = @import("weapon_state.zig");
pub const Phase = enum { ready, away, fire, settle, reload, idle };
pub const Cue = struct { pose: [:0]const u8, sound: ?[:0]const u8 = null, phase: Phase, rate: u16 = 20, loop: bool = false };
pub const Input = struct { weapon: u5, state: i32, sequence: i32, reloading: bool, attack_factor: f32 = 1, now_ms: i64, fire_pose: ?[:0]const u8 = null, fire_rate: ?u16 = null, finish_ms: ?i64 = null };
pub const State = struct {
    incarnation: ?u16 = null,
    weapon: u5 = 0,
    state: i32 = controller.ready,
    phase: Phase = .ready,
    ended_ms: i64 = 0,
    fire_serial: ?u32 = null,
    fire_weapon: u5 = 0,
    fire_ms: i64 = -1000,
    pending_fire: bool = false,
    pub fn synchronize(self: *State, incarnation: u16) void {
        if (self.incarnation != incarnation) self.* = .{ .incarnation = incarnation };
    }
    pub fn noteFire(self: *State, weapon: u5, serial: u32, now: i64) void {
        if (self.fire_serial) |prior| {
            // Player event sequences have a 16-bit wire representation. Both
            // predicted full counters and decoded echoes use this same order.
            const difference = @as(u16, @truncate(serial)) -% @as(u16, @truncate(prior));
            if (difference == 0 or difference >= 0x8000) return;
        }
        self.fire_serial = serial;
        self.fire_weapon = weapon;
        self.fire_ms = now;
        self.pending_fire = true;
    }
    pub fn update(self: *State, spec: profiles.Spec, input: Input) ?Cue {
        const changed_weapon = self.weapon != input.weapon;
        const changed_state = self.state != input.state;
        self.weapon = input.weapon;
        self.state = input.state;
        var cue: ?Cue = null;
        if (input.reloading and (changed_weapon or self.phase != .reload)) {
            if (spec.animation.reload) |name| cue = .{ .pose = name, .sound = spec.audio.reload, .phase = .reload };
        } else if ((self.pending_fire and self.fire_weapon == input.weapon) or (spec.animation.fire_loop and input.state == controller.firing and (changed_weapon or self.phase != .fire))) {
            var pose = spec.animation.fire;
            if (input.sequence >= 0 and input.sequence < spec.animation.fire_variants.len) if (spec.animation.fire_variants[@intCast(input.sequence)]) |name| {
                pose = name;
            };
            if (input.fire_pose) |name| pose = name;
            if (changed_weapon or self.phase != .fire or (!spec.animation.fire_loop and (!spec.animation.hold_fire or input.now_ms >= self.ended_ms))) {
                cue = .{ .pose = pose, .phase = .fire, .rate = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(input.fire_rate orelse spec.animation.rate)) * (if (spec.animation.scale_fire_rate) input.attack_factor else 1), 1, 240)), .loop = spec.animation.fire_loop };
            }
        } else if (changed_weapon or (changed_state and input.state == controller.raising)) {
            cue = .{ .pose = spec.animation.ready, .sound = spec.audio.ready, .phase = .ready };
        } else if (changed_state and input.state == controller.dropping) {
            cue = .{ .pose = spec.animation.away, .sound = spec.audio.away, .phase = .away };
        } else if ((input.state == controller.ready or input.finish_ms != null) and self.phase == .fire and spec.animation.fire_end != null) {
            cue = .{ .pose = spec.animation.fire_end.?, .phase = .settle };
        } else if (input.state == controller.ready and input.now_ms >= self.ended_ms and self.phase != .idle) {
            if (spec.animation.idle[0]) |name| cue = .{ .pose = name, .phase = .idle, .loop = true };
        }
        self.pending_fire = false;
        if (cue) |value| self.phase = value.phase;
        return cue;
    }
};
test "predicted shots deduplicate server echoes and finite attacks give way to idle" {
    var state: State = .{};
    const spec: profiles.Spec = .{ .player_grip = .pistol, .animation = .{ .ready = "ready", .away = "away", .fire = "fire", .idle = .{ "idle", null, null }, .reload = "reload" } };
    var input: Input = .{ .weapon = 21, .state = controller.ready, .sequence = 0, .reloading = false, .now_ms = 0 };
    try std.testing.expectEqual(Phase.ready, state.update(spec, input).?.phase);
    state.noteFire(21, 1, 50);
    input.state = controller.firing;
    input.now_ms = 60;
    try std.testing.expectEqual(Phase.fire, state.update(spec, input).?.phase);
    state.ended_ms = 500;
    state.noteFire(21, 1, 100);
    try std.testing.expect(state.update(spec, input) == null);
    try std.testing.expectEqual(@as(i64, 50), state.fire_ms);
    input.state = controller.ready;
    input.now_ms = 499;
    try std.testing.expect(state.update(spec, input) == null);
    input.now_ms = 500;
    try std.testing.expectEqual(Phase.idle, state.update(spec, input).?.phase);
    input.reloading = true;
    input.state = controller.dropping;
    try std.testing.expectEqual(Phase.reload, state.update(spec, input).?.phase);
    try std.testing.expect(state.update(spec, input) == null);
}

test "burst shots retain their pose and rotary fire spins down after release" {
    var view: State = .{};
    var input: Input = .{ .weapon = 4, .state = controller.firing, .sequence = 0, .reloading = false, .now_ms = 100 };
    const spec: profiles.Spec = .{ .player_grip = .rifle, .animation = .{ .fire = "shoot", .hold_fire = true } };
    view.noteFire(4, 1, 100);
    try std.testing.expectEqual(Phase.fire, view.update(spec, input).?.phase);
    view.ended_ms = 1900;
    view.noteFire(4, 2, 370);
    input.now_ms = 370;
    try std.testing.expect(view.update(spec, input) == null);
    const rotary: profiles.Spec = .{ .player_grip = .rifle, .animation = .{ .fire = "shoota", .fire_loop = true, .fire_end = "spdn" } };
    input.weapon = 22;
    try std.testing.expect(view.update(rotary, input).?.loop);
    input.state = controller.ready;
    try std.testing.expectEqual(Phase.settle, view.update(rotary, input).?.phase);
}

test "respawn accepts the first shot and wire wrap deduplicates predicted echoes" {
    var state: State = .{};
    state.synchronize(1);
    state.noteFire(1, 500, 1000);
    state.synchronize(2);
    state.noteFire(1, 0, 2000);
    try std.testing.expectEqual(@as(i64, 2000), state.fire_ms);
    state.synchronize(2);
    state.noteFire(1, 0, 2010);
    try std.testing.expectEqual(@as(i64, 2000), state.fire_ms);
    state.synchronize(3);
    state.noteFire(1, 65535, 3000);
    state.noteFire(1, 65536, 3010);
    state.pending_fire = false;
    state.noteFire(1, 0, 3020);
    try std.testing.expect(!state.pending_fire);
    state.noteFire(1, 1, 3030);
    try std.testing.expectEqual(@as(i64, 3030), state.fire_ms);
}
