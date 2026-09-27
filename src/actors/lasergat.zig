// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{"shoota"};
pub const State = struct { servo_ms: i64 = 0, turning: bool = false };
pub const turn_degrees: f32 = 10;
pub const servo_sound = "e1/m_lazergatservo.wav";
