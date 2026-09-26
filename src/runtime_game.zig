// SPDX-License-Identifier: GPL-2.0-or-later
pub const weapon_side = .server;
comptime {
    _ = @import("multiplayer/music.zig");
    _ = @import("multiplayer/objectives.zig");
    _ = @import("multiplayer/appearance.zig");
    _ = @import("multiplayer/room.zig");
    _ = @import("weapons/module.zig");
    _ = @import("weapons/server/entry.zig");
}
