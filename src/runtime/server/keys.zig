// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("../domain/components.zig");
pub fn allows(world: *data.World, object: data.MapObject, activator: u32) bool {
    const name = @import("properties.zig").text(object, "keyname") orelse return true;
    if (name.len == 0) return true;
    const player = @import("region_access.zig").find(world, activator) orelse return false;
    const keys = player.get(data.Keys) catch return false;
    return keys.has(name);
}
