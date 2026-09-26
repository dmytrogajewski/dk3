// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("../domain/components.zig");
pub fn allows(world: *data.World, object: data.MapObject, activator: u32) bool {
    const name = @import("properties.zig").text(object, "keyname") orelse return true;
    if (name.len == 0) return true;
    const player = world.find(activator) orelse return false;
    const keys = world.get(player, data.Keys) catch return false;
    return keys.has(name);
}
