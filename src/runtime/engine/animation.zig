// SPDX-License-Identifier: GPL-2.0-or-later
//! Existing wire animation fields carry authored timing to the renderer.
const std = @import("std");
const c = @import("abi.zig").c;
const animation = @import("../domain/animation.zig");
pub fn publish(state: *c.entityState_t, playback: animation.Playback, now: i64) void {
    state.frame = playback.frame(now);
    state.dk3AnimationStart = @intCast(playback.started);
    state.dk3AnimationFirst = if (playback.reverse) playback.sequence.last else playback.sequence.first;
    state.dk3AnimationLast = if (playback.reverse) playback.sequence.first else playback.sequence.last;
    state.dk3AnimationRate = playback.sequence.fps;
    state.dk3AnimationLoop = @intFromBool(playback.looping);
}
pub fn sample(state: c.entityState_t, now: i64) !@TypeOf((animation.Sequence{}).sample(0, false)) {
    if (state.dk3AnimationRate == 0) return .{ .frame = @intCast(state.frame), .oldframe = @intCast(state.frame), .backlerp = 0 };
    const first = @min(state.dk3AnimationFirst, state.dk3AnimationLast);
    const last = @max(state.dk3AnimationFirst, state.dk3AnimationLast);
    if (first < 0 or last > 65535 or state.dk3AnimationRate < 1 or state.dk3AnimationRate > 127) return error.InvalidSnapshotAnimation;
    const playback: animation.Playback = .{ .sequence = .{ .first = @intCast(first), .last = @intCast(last), .fps = @intCast(state.dk3AnimationRate) }, .started = state.dk3AnimationStart, .looping = state.dk3AnimationLoop != 0, .reverse = state.dk3AnimationFirst > state.dk3AnimationLast };
    return playback.sample(now);
}
test "wire animation advances between snapshots and retains reverse loops and final holds" {
    const t = std.testing;
    var state = std.mem.zeroes(c.entityState_t);
    var playback: animation.Playback = .{ .sequence = .{ .first = 10, .last = 13, .fps = 10 }, .started = 1000 };
    publish(&state, playback, 1100);
    const a = try sample(state, 1125);
    const b = try sample(state, 1175);
    try t.expectEqual(@as(u16, 11), a.oldframe);
    try t.expectEqual(@as(u16, 12), a.frame);
    try t.expectApproxEqAbs(@as(f32, 0.75), a.backlerp, 0.001);
    try t.expectApproxEqAbs(@as(f32, 0.25), b.backlerp, 0.001);
    playback.reverse = true;
    publish(&state, playback, 1100);
    try t.expectEqual(@as(u16, 12), (try sample(state, 1125)).oldframe);
    try t.expectEqual(@as(u16, 11), (try sample(state, 1125)).frame);
    try t.expectEqual(@as(u16, 13), (try sample(state, 1400)).oldframe);
    playback.looping = false;
    publish(&state, playback, 1100);
    try t.expectEqual(@as(u16, 10), (try sample(state, 9999)).oldframe);
    try t.expectEqual(@as(u16, 10), (try sample(state, 9999)).frame);
}
