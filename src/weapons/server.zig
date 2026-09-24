// SPDX-License-Identifier: GPL-2.0-or-later
pub const weapon_side = .server;
comptime {
    _ = @import("module.zig");
    _ = @import("server/entry.zig");
}
