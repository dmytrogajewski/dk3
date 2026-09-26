// SPDX-License-Identifier: GPL-2.0-or-later
//! Personal actions cannot follow a disconnected player or a new campaign arrival.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
fn owner(world: *data.World, entity: ecs.Entity) ?u32 {
    inline for (.{ data.Melee, data.WeaponLaunch, data.Nova, data.Flashlight, data.Zeus, data.ZeusBolt }) |T| if (world.get(entity, T) catch null) |action| return action.owner;
    if (world.get(entity, data.Hammer) catch null) |hammer| if (hammer.quake_until_ms == null) return hammer.owner;
    return null;
}
pub fn cancel(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, player: ecs.Entity) !void {
    const identity = try world.persistentId(player);
    var pending: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(0, 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            const ritual = world.get(entity, data.Nightmare) catch null;
            if (owner(world, entity) == identity or (ritual != null and (ritual.?.owner == identity or ritual.?.victim == identity))) {
                pending[count] = entity;
                count += 1;
            }
        };
    }
    for (pending[0..count]) |entity| {
        if ((world.get(entity, data.Nightmare) catch null) != null) {
            try @import("nightmare.zig").remove(world, slots, projections, entity);
            continue;
        }
        if ((world.get(entity, data.Binding) catch null) != null) try @import("weapon_entities.zig").remove(world, slots, projections, entity) else try world.destroy(entity);
    }
}
