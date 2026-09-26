// SPDX-License-Identifier: GPL-2.0-or-later
//! Deferred target identity and timing are saveable domain state.
pub const Action = struct { source: u32, activator: u32, due_ms: i64 };
pub const Queue = [256]?Action;
