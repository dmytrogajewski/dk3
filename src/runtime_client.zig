// SPDX-License-Identifier: GPL-2.0-or-later
pub const weapon_side = .client;
comptime {
    _ = @import("multiplayer/appearance.zig");
    _ = @import("weapons/module.zig");
    _ = @import("weapons/client/entry.zig");
}
