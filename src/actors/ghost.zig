// SPDX-License-Identifier: GPL-2.0-or-later
//! Kage's summoned actor wakes, seeks, strikes once and fades.
pub const attacks = [_][]const u8{"ataka"};
pub const State = struct {
    phase: enum { dormant, waking, chase, attack, fading } = .dormant,
    owner: u32 = 0,
    alpha: f32 = 0,
    started_ms: i64 = 0,
    sound_ready_ms: i64 = 0,
    pub fn fade(self: *State, now: i64) void {
        if (self.phase == .fading) return;
        self.phase = .fading;
        self.started_ms = now;
    }
};
