// SPDX-License-Identifier: GPL-2.0-or-later
//! Light lifetime follows ordinary held-fire events; prediction owns battery spending.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
const W = @import("weapon_catalog").flashlight;
const entities = @import("weapon_entities.zig");
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const light = (try world.get(entity, data.Flashlight)).*;
    try entities.effect(world, entity, projections, .{ .owner = light.owner, .weapon = W.id, .strength = light.strength, .end_ms = light.expires_ms });
}
pub fn refresh(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, now: i64) !void {
    const owner_id = try world.persistentId(owner);
    const light: data.Flashlight = .{ .owner = owner_id, .expires_ms = now + 200, .strength = W.power((try world.get(owner, data.Weapons)).ammo[W.id]) };
    for (slots.occupants) |occupant| if (occupant) |entity| {
        const existing = world.get(entity, data.Flashlight) catch continue;
        if (existing.owner == owner_id) {
            existing.* = light;
            return;
        }
    };
    if (light.strength <= 0) return;
    const entity = try world.create(null, .{ (try world.get(owner, data.Transform)).*, light });
    errdefer world.destroy(entity) catch unreachable;
    try entities.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        const light = (world.get(entity, data.Flashlight) catch continue).*;
        const owner = world.find(light.owner);
        if (owner == null or now >= light.expires_ms or light.strength <= 0 or (try world.get(owner.?, data.Health)).current <= 0 or (try world.get(owner.?, data.Weapons)).weapon != W.id) {
            try entities.remove(world, slots, projections, entity);
            continue;
        }
        var pose = (try world.get(owner.?, data.Transform)).*;
        pose.position[2] += (try world.get(owner.?, data.Player)).view_height;
        (try world.get(entity, data.Transform)).* = pose;
        try publish(world, entity, projections);
    }
}
