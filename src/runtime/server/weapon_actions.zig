// SPDX-License-Identifier: GPL-2.0-or-later
//! Actions tied to their owner's body follow a seamless ownership transfer and
//! end on disconnection. Free projectiles retain their own spatial owner.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
pub fn owner(world: *data.World, entity: ecs.Entity) ?u32 {
    inline for (.{ data.Melee, data.WeaponLaunch, data.Nova, data.Flashlight, data.Zeus, data.ZeusBolt }) |T| if (world.get(entity, T) catch null) |action| return action.owner;
    if (world.get(entity, data.Hammer) catch null) |hammer| if (hammer.quake_until_ms == null) return hammer.owner;
    if (world.get(entity, data.ActorAttack) catch null) |attack| switch (attack.attack) {
        .gunner_burst => return attack.owner,
        .wyndrax_bolt => |bolt| if (bolt.kind == .wisp or bolt.kind == .scenery) return bolt.parent,
        else => {},
    };
    return null;
}
/// Chained lightning originates at each hop's actor, independently of the
/// player owning the chain. Carry only the hop actually attached to a mover.
pub fn attachment(world: *data.World, entity: ecs.Entity) ?u32 {
    if (world.get(entity, data.ZeusBolt) catch null) |bolt| return bolt.source;
    return owner(world, entity);
}
pub fn cancel(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, player: ecs.Entity) !void {
    const identity = try world.persistentId(player);
    try cancelLocal(world, slots, projections, identity);
    // Personal graphs can have hops or a captured victim in another ready map.
    // Persistent ownership, not spatial proximity, decides disconnection cleanup.
    const access = @import("region_access.zig");
    const region = access.region orelse return;
    if (&region.initial.world.? != world) {
        const scope = try region.initial.select();
        defer scope.deinit();
        try cancelLocal(&region.initial.world.?, &region.initial.slots, &region.initial.projection, identity);
    }
    for (region.residents.entries) |maybe| if (maybe) |entry| if (entry.ready) if (entry.context) |context| {
        if (&context.world.? == world) continue;
        const scope = try context.select();
        defer scope.deinit();
        try cancelLocal(&context.world.?, &context.slots, &context.projection, identity);
    };
}
fn cancelLocal(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, identity: u32) !void {
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

test "a lightning hop follows its source while cancellation retains player ownership" {
    const t = @import("std").testing;
    var world = data.World.init(t.allocator, 2);
    defer world.deinit();
    const bolt = try world.create(null, .{data.ZeusBolt{ .owner = 12, .chain = 24, .source = 16777217, .target = 36, .born_ms = 0, .next_ms = 100 }});
    try t.expectEqual(@as(?u32, 12), owner(&world, bolt));
    try t.expectEqual(@as(?u32, 16777217), attachment(&world, bolt));
}
