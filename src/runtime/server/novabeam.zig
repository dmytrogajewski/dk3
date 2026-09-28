// SPDX-License-Identifier: GPL-2.0-or-later
//! Timed Novabeam discharge. Current aim is sampled; consumed burst never restarts.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const weapons = @import("../domain/weapons.zig");
const W = @import("weapon_catalog").novabeam;
const v = @import("../domain/vector.zig");
const entities = @import("weapon_entities.zig");
const c = abi.c;
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const beam = (try world.get(entity, data.Nova)).*;
    try entities.effect(world, entity, projections, .{ .owner = beam.owner, .weapon = W.id, .endpoint = beam.endpoint, .phase = @intCast(@intFromEnum(beam.phase)), .strength = beam.alpha, .born_ms = beam.born_ms, .end_ms = beam.end_ms orelse 0 });
}
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, shot: weapons.Fired, table: *const weapons.Table, now: i64) !void {
    const owner_id = try world.persistentId(owner);
    const occupants = slots.occupants;
    for (occupants) |occupant| if (occupant) |entity| {
        const old = world.get(entity, data.Nova) catch continue;
        if (old.owner == owner_id) try entities.remove(world, slots, projections, entity);
    };
    const boost: u8 = @intCast((try world.get(owner, data.Character)).attribute(.attack, now));
    const entity = try world.create(null, .{ data.Transform{ .position = shot.position, .angles = shot.angles }, W.Discharge.init(owner_id, table.entries[W.id], boost, now) });
    errdefer world.destroy(entity) catch unreachable;
    try entities.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        var beam = (world.get(entity, data.Nova) catch continue).*;
        const owner = world.find(beam.owner);
        if (owner == null or now >= beam.expires_ms or (try world.get(owner.?, data.Health)).current <= 0 or (try world.get(owner.?, data.Weapons)).weapon != W.id) {
            try entities.remove(world, slots, projections, entity);
            continue;
        }
        const pose = (try world.get(owner.?, data.Transform)).*;
        const slot = (try world.get(owner.?, data.Binding)).slot;
        const player = (try world.get(owner.?, data.Player)).*;
        const eye = @import("../domain/combat.zig").eye(pose.position, player.view_height);
        const muzzle = @import("../domain/combat.zig").muzzle(eye, pose.angles, W.muzzle);
        const muzzle_hit = try @import("region_collision.zig").trace(.{ .start = eye, .end = muzzle, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
        const start = muzzle_hit.end;
        const hit = try @import("region_collision.zig").from(muzzle_hit.world, .{ .start = start, .end = v.add(start, v.scale(v.basis(pose.angles).forward, W.visual.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT }, beam.owner);
        beam.endpoint = hit.end;
        const previous = beam.phase;
        const tick = beam.advance(now, (try world.get(owner.?, data.Weapons)).ammo[W.id]);
        (try world.get(owner.?, data.Weapons)).ammo[W.id] -= tick.consumed;
        if (tick.damage > 0) if (@import("region_access.zig").victim(world, slots, hit)) |target| {
            _ = try @import("weapon_damage.zig").hurt(target.world, target.entity, beam.owner, W.id, tick.damage, now, false);
        };
        if (tick.finish) try @import("events.zig").sound(world, slots, projections, W.spec.audio.finish.?, start, slot, c.CHAN_WEAPON, now);
        if (engine.integer("developer") > 0 and previous != beam.phase) {
            var text: [180]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig novabeam: id={d} phase={s} remaining={d:.3} ammo={d}\n", .{ try world.persistentId(entity), @tagName(beam.phase), beam.remaining_damage, (try world.get(owner.?, data.Weapons)).ammo[W.id] }));
        }
        (try world.get(entity, data.Nova)).* = beam;
        (try world.get(entity, data.Transform)).* = .{ .position = start, .angles = pose.angles };
        try publish(world, entity, projections);
    }
}
