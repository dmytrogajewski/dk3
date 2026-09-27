// SPDX-License-Identifier: GPL-2.0-or-later
//! Final hostile Mikiko; companion behavior is a separate controller.
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc" };
pub const State = struct {
    voice_pose: u2 = 0,
    awakened: bool = false,
    aura: bool = false,
    aura_started_ms: i64 = 0,
    light_red: f32 = 1,
};
pub fn sound(pose: u2, frame: u16) ?[]const u8 {
    return switch (pose) {
        0 => if (frame >= 40 and frame <= 41) "global/we_swordwhoosha.wav" else null,
        1 => if (frame >= 52 and frame <= 53) "mikiko/jump5.wav" else if (frame >= 58 and frame <= 59) "global/we_swordwhooshf.wav" else null,
        2 => if (frame >= 70 and frame <= 71) "mikiko/jump8.wav" else if (frame >= 73 and frame <= 74) "global/we_swordwhooshc.wav" else if (frame >= 83 and frame <= 84) "global/we_swordwhooshd.wav" else null,
        else => null,
    };
}
