// SPDX-License-Identifier: GPL-2.0-or-later
//! Grouped destructible walls retain their scheduled fragment bursts in saves.
pub const Burst = struct { position: [3]f32 = @splat(0), due_ms: ?i64 = null };
pub const State = struct {
    models: [3][]const u8 = .{ "models/global/e_rock1.dkm", "models/global/e_rock2.dkm", "models/global/e_rock3.dkm" },
    bounds_min: [3]f32 = @splat(0),
    bounds_max: [3]f32 = @splat(0),
    bursts: [11]Burst = @splat(.{}),
};
