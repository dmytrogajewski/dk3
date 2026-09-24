// SPDX-License-Identifier: GPL-2.0-or-later
pub const weapon_side = .client;
comptime {
    _ = @import("module.zig");
    _ = @import("client/entry.zig");
}
