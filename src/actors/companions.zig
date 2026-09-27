// SPDX-License-Identifier: GPL-2.0-or-later
//! Party identity and explicit orders; shared weapon classes own combat rules.
pub const Identity = enum { mikiko, superfly };
pub const Order = enum { follow, stay, attack, collect, move };
pub const Authored = enum { none, stop, teleport };
pub const State = struct {
    identity: Identity,
    carrying: bool = false,
    enabled: bool = true,
    order: Order = .follow,
    owner: u32 = 0,
    target: u32 = 0,
    destination: [3]f32 = @splat(0),
    authored: Authored = .none,
    animation_until: ?i64 = null,
    after_teleport: Order = .follow,
    stopped: bool = false,
    next_ms: i64 = 0,
    last_ms: i64 = 0,
    death_reported: bool = false,
};
