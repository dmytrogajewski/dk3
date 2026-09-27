// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    switch ((try world.get(entity, data.ActorAttack)).attack) {
        .fireball => try @import("actor_fireballs.zig").publish(world, entity, projections, now),
        .psyclaw_sphere => try @import("psyclaw_spheres.zig").publish(world, entity, projections, now),
        .gunner_burst => try @import("gunner_bursts.zig").publish(world, entity, projections, now),
        .sludge_glob => try @import("sludge_globs.zig").publish(world, entity, projections, now),
        .prisoner_rock => try @import("prisoner_rocks.zig").publish(world, entity, projections, now),
        .shaft => try @import("shafts.zig").publish(world, entity, projections, now),
        .rotworm_spit => try @import("venom_spit.zig").publish(world, entity, projections, now),
        .rocket => try @import("actor_rockets.zig").publish(world, entity, projections, now),
        .meteor => try @import("meteors.zig").publish(world, entity, projections, now),
        .npc_wisp, .wyndrax_zap, .wyndrax_bolt => try @import("wyndrax_attacks.zig").publish(world, entity, projections, now),
        .knight_zap, .knight_punch => try @import("knight_attacks.zig").publish(world, entity, projections, now),
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |maybe| {
        const entity = maybe orelse continue;
        if (!world.alive(entity)) continue;
        const state = (world.get(entity, data.ActorAttack) catch continue).*;
        switch (state.attack) {
            .fireball => try @import("actor_fireballs.zig").step(world, slots, projections, entity, now),
            .psyclaw_sphere => try @import("psyclaw_spheres.zig").step(world, slots, projections, entity, now),
            .gunner_burst => try @import("gunner_bursts.zig").step(world, slots, projections, entity, now),
            .sludge_glob => try @import("sludge_globs.zig").step(world, slots, projections, entity, now),
            .prisoner_rock => try @import("prisoner_rocks.zig").step(world, slots, projections, entity, now),
            .shaft => try @import("shafts.zig").step(world, slots, projections, entity, now),
            .rotworm_spit => try @import("venom_spit.zig").step(world, slots, projections, entity, now),
            .rocket => try @import("actor_rockets.zig").step(world, slots, projections, entity, now),
            .meteor => try @import("meteors.zig").step(world, slots, projections, entity, now),
            .npc_wisp, .wyndrax_zap, .wyndrax_bolt => try @import("wyndrax_attacks.zig").step(world, slots, projections, entity, now),
            .knight_zap, .knight_punch => try @import("knight_attacks.zig").step(world, slots, projections, entity, now),
        }
    }
}
