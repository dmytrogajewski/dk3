// SPDX-License-Identifier: GPL-2.0-or-later
//! Party identity and explicit orders; shared weapon classes own combat rules.
pub const render_tag = 10029;
pub const Identity = enum { mikiko, superfly };
pub const Order = enum { follow, stay, attack, collect, move };
pub const Authored = enum { none, stop, teleport };
