// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared presentation values; concrete weapon types select and execute cues.

const c = @import("abi.zig").c;
const profiles = @import("profiles.zig");

pub const AudioContext = struct { entity: c_int, local_entity: c_int, sequence: c_int, fired: c_int, now: c_int };

pub fn pointer(value: ?[:0]const u8) [*c]const u8 {
    return if (value) |name| name.ptr else null;
}

pub fn basicView(spec: profiles.Spec) ViewCue {
    return .{ .pose = pointer(if (spec.animation.fire.len == 0) null else spec.animation.fire), .rate = spec.animation.rate, .poseStartOffsetMs = 0, .finishDelayMs = 0 };
}

pub fn basicAudio(spec: profiles.Spec) AudioCue {
    return .{ .fire = pointer(spec.audio.fire), .extra = null };
}

pub const ViewCue = struct {
    pose: [*c]const u8,
    rate: c_int,
    poseStartOffsetMs: c_int,
    finishDelayMs: c_int,
};
pub const AudioCue = struct { fire: [*c]const u8, extra: [*c]const u8 };
