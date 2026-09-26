// SPDX-License-Identifier: GPL-2.0-or-later
//! Prediction state IDs are part of the existing snapshot ABI.
pub const ready: i32 = 0;
pub const raising: i32 = 1;
pub const dropping: i32 = 2;
pub const firing: i32 = 3;
pub const glock_reload_sequence: i32 = 256;
