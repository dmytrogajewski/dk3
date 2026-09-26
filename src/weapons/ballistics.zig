// SPDX-License-Identifier: GPL-2.0-or-later
//! Pure flight/contact contracts. Each concrete weapon owns its extra state.
const v = @import("vector.zig");
pub const State = union(enum) {
    ion,
    bolter: @import("descriptions/bolter.zig").BallisticState,
    sidewinder: @import("descriptions/sidewinder.zig").BallisticState,
    cordite: @import("descriptions/cordite.zig").BallisticState,
    venom: @import("descriptions/venom.zig").BallisticState,
    kineticore: @import("descriptions/kineticore.zig").BallisticState,
};
pub const Launch = struct { muzzle: v.Vec, pitch: f32 = 0, roll: f32 = 0 };
pub const Frame = struct { age_ms: i64, delta_ms: u32, distance: f32, wet: bool, was_wet: bool, velocity: v.Vec, speed: f32 = 0 };
pub const Motion = struct { velocity: v.Vec, gravity: f32 = 0, remove: bool = false };
pub const Contact = struct { damageable: bool, living: bool, brush: bool };
pub const Response = union(enum) { remove, direct, stick: u16, bounce: f32, explode };
pub const Hit = struct { damage: f32, age_ms: i64, lifetime_ms: i64, self_hit: bool = false, victim_class: []const u8 = "" };
pub const Damage = struct { amount: f32, effect: @import("affliction.zig").Effect = .none };
