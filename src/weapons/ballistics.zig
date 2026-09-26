// SPDX-License-Identifier: GPL-2.0-or-later
//! Pure flight/contact contracts. Each concrete weapon owns its extra state.
const v = @import("vector.zig");
pub const State = union(enum) {
    ion,
    bolter: @import("descriptions/bolter.zig").BallisticState,
    sidewinder: @import("descriptions/sidewinder.zig").BallisticState,
    cordite: @import("descriptions/cordite.zig").BallisticState,
};
pub const Launch = struct { muzzle: v.Vec, pitch: f32 = 0, roll: f32 = 0 };
pub const Frame = struct { age_ms: i64, delta_ms: u32, distance: f32, wet: bool, was_wet: bool, velocity: v.Vec };
pub const Motion = struct { velocity: v.Vec, gravity: f32 = 0 };
pub const Contact = struct { damageable: bool, living: bool, brush: bool };
pub const Response = union(enum) { remove, direct, stick: u16, bounce: f32, explode };
