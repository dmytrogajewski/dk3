// SPDX-License-Identifier: GPL-2.0-or-later
//! Weapon-owned requests. Runtime status scheduling owns their application.
pub const Effect = union(enum) {
    none,
    poison: struct { damage: f32, duration_ms: u32, interval_ms: u32 = 1000 },
    freeze: f32,
};
