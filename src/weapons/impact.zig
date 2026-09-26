// SPDX-License-Identifier: GPL-2.0-or-later
//! Reusable impact presentation components selected by concrete weapon types.
const c = @import("abi.zig").c;

pub const Context = struct { kind: c_int, entity: c_int, frame: c_int };

pub fn none(context: Context) Cue {
    return .{ .mark = null, .sound = null, .radius = 4, .orientation = @floatFromInt(@mod(context.entity *% 137, 360)) };
}

pub fn bullet(context: Context) Cue {
    var cue = none(context);
    cue.mark = "models/global/we_bhole.sp2/0@mark";
    cue.sound = if (context.kind == 1) "global/bullethitflesh.wav" else "global/e_ricocheta.wav";
    return cue;
}

pub fn scorch(context: Context) Cue {
    var cue = none(context);
    cue.mark = "models/global/we_scorch.sp2/0@mark";
    cue.radius = 16;
    return cue;
}

pub const Cue = struct {
    mark: [*c]const u8,
    sound: [*c]const u8,
    radius: f32,
    orientation: f32,
    /// Gold clientSparks: count doubles as the launch strength.
    sparks: u8 = 0,
    spark_color: [3]f32 = .{ 1, 1, 1 },
    light_radius: f32 = 0,
    light_color: [3]f32 = .{ 1, 1, 1 },
    light_ms: c_int = 0,
};
