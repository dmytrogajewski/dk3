// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    switch ((try world.get(entity, data.ActorAttack)).attack) {
        .vermin_rocket => try @import("vermin_rockets.zig").publish(world, entity, projections, now),
        .knight_flame, .knight_zap, .knight_punch => try @import("knight_attacks.zig").publish(world, entity, projections, now),
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |maybe| {
        const entity = maybe orelse continue;
        if (!world.alive(entity)) continue;
        const state = (world.get(entity, data.ActorAttack) catch continue).*;
        switch (state.attack) {
            .vermin_rocket => try @import("vermin_rockets.zig").step(world, slots, projections, entity, now),
            .knight_flame, .knight_zap, .knight_punch => try @import("knight_attacks.zig").step(world, slots, projections, entity, now),
        }
    }
}
