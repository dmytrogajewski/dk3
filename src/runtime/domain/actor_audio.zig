// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored frame and sight cues; no engine calls or hardcoded actor samples.
const std = @import("std");
const animation = @import("animation.zig");
pub const Cue = struct {
    name: []const u8,
    sequence: ?animation.Sequence,
    sounds: [2][]const u8 = .{ "", "" },
    frames: [2]?u16 = @splat(null),
    alternative: ?f32 = null,
    weight: f32 = 1,
    pub fn indices(self: Cue, alternate: bool) [2]?u16 {
        if (self.alternative != null) return if (alternate) .{ null, self.frames[0] } else .{ self.frames[0], null };
        return self.frames;
    }
};
pub const Idle = struct { sequence: animation.Sequence, weight: f32 = 1 };
pub fn idleChoices(allocator: std.mem.Allocator, metadata: []const u8, cues: []const Cue) ![]const Idle {
    var choices: std.ArrayList(Idle) = .empty;
    errdefer choices.deinit(allocator);
    var name = [_]u8{ 'a', 'm', 'b', 'a' };
    while (name[3] <= 'z') : (name[3] += 1) {
        const sequence = try animation.find(metadata, &name) orelse break;
        var weight: f32 = 1;
        for (cues) |cue| if (std.mem.eql(u8, cue.name, &name)) {
            weight = cue.weight;
            break;
        };
        try choices.append(allocator, .{ .sequence = sequence, .weight = weight });
    }
    return choices.toOwnedSlice(allocator);
}
pub const State = struct {
    attack_started_ms: ?i64 = null,
    attack_index: u3 = 0,
    attack_sounds: u2 = 0,
    attack_alternate: bool = false,
    cue: ?u16 = null,
    started_ms: ?i64 = null,
    pending: u2 = 0,
    frame: u16 = 0,
    sampled_ms: ?i64 = null,
    sounded: u2 = 0,
    alternate: bool = false,
    threat: u32 = 0,
    ambient_ready_ms: ?i64 = null,
};
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8, metadata: []const u8, classname: []const u8) ![]const Cue {
    var result: std.ArrayList(Cue) = .empty;
    errdefer result.deinit(allocator);
    var reader = try @import("tables.zig").Reader.init(bytes);
    while (try reader.next()) |row| {
        if (!std.mem.eql(u8, row.field("classname") orelse "", classname)) continue;
        const name = row.field("animation") orelse return error.MissingActorCueName;
        const sequence = try animation.find(metadata, name);
        if (sequence == null and !std.mem.startsWith(u8, name, "sight")) continue;
        // These fields were previously discarded by conversion. Inferring them
        // from sound names would change explicit zero-probability alternatives.
        if (row.field("sound2_alternative") == null or row.field("frame2_enabled") == null) return error.RegenerateActorEventAssets;
        var cue: Cue = .{ .name = name, .sequence = sequence, .sounds = .{ row.field("sound1") orelse "", row.field("sound2") orelse "" }, .weight = std.math.clamp(try row.number("weight", 100) * 0.01, 0, 1) };
        if (try row.number("sound2_alternative", 0) != 0) cue.alternative = std.math.clamp(try row.number("sound2_chance", 0) * 0.01, 0, 1);
        if (sequence) |clip| inline for (.{ "frame1", "frame2" }, 0..) |key, i| {
            const frame = try row.number(key, 1);
            // CSV frames outside a model clip never occur in the reference.
            if (try row.number(key ++ "_enabled", 0) != 0 and frame >= 0 and frame <= @as(f32, @floatFromInt(clip.last - clip.first))) cue.frames[i] = @intFromFloat(frame);
        };
        if (result.items.len >= 256) return error.ActorCueCapacity;
        try result.append(allocator, cue);
    }
    return result.toOwnedSlice(allocator);
}
pub fn sample(state: *State, cue: Cue, index: u16, frame: u16, now: i64, started: i64, looping: bool, roll: f32) u2 {
    const sequence = cue.sequence orelse return 0;
    const changed = state.cue != index or state.started_ms != started;
    const wrapped = !changed and looping and (frame < state.frame or (state.sampled_ms != null and now - state.sampled_ms.? >= sequence.duration()));
    if (changed or wrapped) {
        state.cue = index;
        state.started_ms = started;
        state.pending = 0;
        state.sounded = 0;
        if (changed) state.alternate = if (cue.alternative) |chance| roll < chance else false;
    }
    const relative = frame - sequence.first;
    var events: u2 = 0;
    for (cue.indices(state.alternate), 0..) |event, i| if (event) |at| {
        const bit = @as(u2, 1) << @intCast(i);
        if (state.sounded & bit == 0 and relative >= at) {
            state.sounded |= bit;
            events |= bit;
        }
    };
    state.frame = frame;
    state.sampled_ms = now;
    return events;
}
test "a second sound alternative replaces the first frame and never plays its old sequential frame" {
    const cue: Cue = .{ .name = "runa", .sequence = .{ .first = 20, .last = 39 }, .sounds = .{ "left", "right" }, .frames = .{ 2, 8 }, .alternative = 0.25 };
    var state: State = .{};
    try std.testing.expectEqual(@as(u2, 2), sample(&state, cue, 0, 22, 100, 0, true, 0.24));
    try std.testing.expectEqual(@as(u2, 0), sample(&state, cue, 0, 28, 700, 0, true, 0));
    var saved = state;
    try std.testing.expectEqual(@as(u2, 0), sample(&saved, cue, 0, 29, 800, 0, true, 0));
    try std.testing.expectEqual(@as(u2, 0), sample(&saved, cue, 0, 20, 2000, 2000, true, 0.25));
    try std.testing.expectEqual(@as(u2, 1), sample(&saved, cue, 0, 22, 2200, 2000, true, 0));
}
test "sequential cues both survive crossed frames and finite death poses do not repeat" {
    const cue: Cue = .{ .name = "diea", .sequence = .{ .first = 20, .last = 39 }, .frames = .{ 2, 8 } };
    var state: State = .{};
    try std.testing.expectEqual(@as(u2, 3), sample(&state, cue, 0, 29, 900, 0, false, 0));
    try std.testing.expectEqual(@as(u2, 0), sample(&state, cue, 0, 39, 5000, 0, false, 0));
}

test "cue parsing retains sight rows, exact clips, disabled events and contiguous idle weights" {
    const metadata = "dk3_animation 1 50 amba 0 9 10 ambb 10 19 10 ambd 20 29 10 diea 30 49 10";
    const rows =
        \\dk3_table 1
        \\{ classname fixture animation amba sound1 a frame1 1 frame1_enabled 1 frame2_enabled 0 sound2_alternative 0 weight 25 }
        \\{ classname fixture animation ambb sound1 b frame1 1 frame1_enabled 0 frame2_enabled 0 sound2_alternative 1 sound2_chance 0 }
        \\{ classname fixture animation sighta sound1 notice frame2_enabled 0 sound2_alternative 0 }
        \\{ classname fixture animation ignored frame2_enabled 0 sound2_alternative 0 }
        \\{ classname fixture animation diea frame1 25 frame1_enabled 1 frame2_enabled 0 sound2_alternative 0 }
    ;
    const cues = try parse(std.testing.allocator, rows, metadata, "fixture");
    defer std.testing.allocator.free(cues);
    try std.testing.expectEqual(@as(usize, 4), cues.len);
    try std.testing.expectEqual(@as(?u16, 1), cues[0].frames[0]);
    try std.testing.expectEqual(null, cues[1].frames[0]);
    try std.testing.expectEqual(@as(?f32, 0), cues[1].alternative);
    try std.testing.expectEqual(null, cues[2].sequence);
    try std.testing.expectEqualStrings("notice", cues[2].sounds[0]);
    try std.testing.expectEqual(null, cues[3].frames[0]);
    const choices = try idleChoices(std.testing.allocator, metadata, cues);
    defer std.testing.allocator.free(choices);
    try std.testing.expectEqual(@as(usize, 2), choices.len);
    try std.testing.expectEqual(@as(f32, 0.25), choices[0].weight);
    try std.testing.expectError(error.RegenerateActorEventAssets, parse(std.testing.allocator, "dk3_table 1 { classname fixture animation amba }", metadata, "fixture"));
}
