// SPDX-License-Identifier: GPL-2.0-or-later
//! Saved ritual phases and explicit victim ownership; no callback or legacy entity mirrors.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const W = @import("weapon_catalog").nightmare;
const weapons = @import("../domain/weapons.zig");
const v = @import("../domain/vector.zig");
const c = abi.c;
const entities = @import("weapon_entities.zig");
fn alive(world: *data.World, identity: u32) bool {
    const target = world.find(identity) orelse return false;
    return (world.get(target, data.Health) catch return false).current > 0;
}
pub fn frozen(world: *data.World, target: ecs.Entity) bool {
    if (@import("nharre_reaper.zig").frozen(world, target)) return true;
    const body = world.get(target, data.Body) catch return false;
    const controller = world.find(body.motion_owner orelse return false) orelse return false;
    const ritual = world.get(controller, data.Nightmare) catch return false;
    return ritual.victim == (world.persistentId(target) catch return false);
}
pub fn release(world: *data.World, controller: ecs.Entity, ritual: *data.Nightmare) !void {
    if (ritual.victim) |identity| if (world.find(identity)) |target| {
        const body = try world.get(target, data.Body);
        if (body.motion_owner == try world.persistentId(controller)) {
            body.motion_owner = null;
            (try world.get(target, data.Velocity)).linear = @splat(0);
            if (world.get(target, data.Player) catch null) |player| {
                if (player.mode == .frozen) player.mode = if (alive(world, identity)) .normal else .dead;
                player.view_height = ritual.previous_view_height;
            }
        }
    };
    ritual.victim = null;
}
pub fn remove(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity) !void {
    var ritual = (try world.get(entity, data.Nightmare)).*;
    try release(world, entity, &ritual);
    if (world.find(ritual.owner)) |owner| if (world.get(owner, data.Weapons) catch null) |loadout| if (loadout.weapon == W.id) {
        loadout.weaponTime = 0;
    };
    try entities.remove(world, slots, projections, entity);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const ritual = (try world.get(entity, data.Nightmare)).*;
    try entities.effect(world, entity, projections, .{ .weapon = W.id, .owner = ritual.owner, .phase = @intFromEnum(ritual.phase), .born_ms = ritual.phase_ms, .end_ms = ritual.next_ms });
    const state = &projections[(try world.get(entity, data.Binding)).slot].state;
    state.otherEntityNum2 = if (ritual.victim) |identity| (if (world.find(identity)) |target| (try world.get(target, data.Binding)).slot else c.ENTITYNUM_NONE) else c.ENTITYNUM_NONE;
    state.angles2[1] = @floatFromInt(ritual.born_ms);
}
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, shot: weapons.Fired, table: *const weapons.Table, now: i64) !void {
    const tuning = table.entries[W.id];
    const factor = @import("weapon_catalog").transitions.attackFactor((try world.get(owner, data.Character)).attribute(.attack, now));
    const ritual: data.Nightmare = .{ .owner = try world.persistentId(owner), .damage = tuning.damage, .range = tuning.range, .born_ms = now, .phase_ms = now, .next_ms = now + W.searchDelay(factor) };
    const entity = try world.create(null, .{ data.Transform{ .position = shot.position }, ritual });
    errdefer world.destroy(entity) catch unreachable;
    try entities.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections);
}
fn search(world: *data.World, slots: *Slots, entity: ecs.Entity, ritual: *data.Nightmare, now: i64) !void {
    const owner = world.find(ritual.owner).?;
    const origin = (try world.get(entity, data.Transform)).position;
    const view: v.Vec3 = .{ 0, 0, (try world.get(owner, data.Player)).view_height };
    const eye = v.add((try world.get(owner, data.Transform)).position, view);
    var seen = false;
    for (slots.occupants) |occupant| {
        const target = occupant orelse continue;
        const identity = try world.persistentId(target);
        if (identity == ritual.owner or !alive(world, identity)) continue;
        if ((world.get(target, data.Actor) catch null) == null and (engine.integer("g_gametype") == c.GT_SINGLE_PLAYER or (world.get(target, data.Player) catch null) == null)) continue;
        const position = (try world.get(target, data.Transform)).position;
        if (v.length(v.subtract(position, origin)) > ritual.range) continue;
        // com_Visible offsets both endpoints by the observer's view offset and masks opaque liquids.
        const sight = try engine.collisionService().trace(.{ .start = eye, .end = v.add(position, view), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(owner, data.Binding)).slot, .mask = c.MASK_OPAQUE });
        if (sight.start_solid or sight.all_solid or (sight.fraction < 1 and sight.entity != (try world.get(target, data.Binding)).slot)) continue;
        seen = true;
        if (world.get(target, data.MapObject) catch null) |object| if (std.mem.eql(u8, object.classname, "monster_garroth")) continue;
        _ = ritual.mark(identity);
    }
    if (!seen) _ = ritual.mark(ritual.owner);
    ritual.advance(.waiting, now, if (engine.integer("g_gametype") == c.GT_SINGLE_PLAYER) 500 else 1500);
}

fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, name: [:0]const u8, now: i64) !void {
    try @import("events.zig").sound(world, slots, projections, name, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
fn nextVictim(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, ritual: *data.Nightmare, now: i64) !bool {
    while (ritual.cursor < ritual.count) {
        const identity = ritual.targets[ritual.cursor];
        ritual.cursor += 1;
        if (!alive(world, identity)) continue;
        const target = world.find(identity).?;
        // An existing transport/freeze keeps ownership; overlapping rituals cannot steal it.
        if ((try world.get(target, data.Body)).motion_owner != null) continue;
        if (world.get(target, data.Player) catch null) |player| if (player.mode != .normal) continue;
        const forward = try @import("clear_direction.zig").choose(world, target, c.MASK_SHOT);
        const pose = (try world.get(target, data.Transform)).*;
        (try world.get(entity, data.Transform)).* = .{ .position = v.add(pose.position, v.scale(forward, 100)), .angles = .{ 0, std.math.atan2(-forward[1], -forward[0]) * (180.0 / std.math.pi), 0 } };
        ritual.victim = identity;
        (try world.get(target, data.Body)).motion_owner = try world.persistentId(entity);
        (try world.get(target, data.Velocity)).linear = @splat(0);
        if (world.get(target, data.Player) catch null) |player| {
            ritual.previous_view_height = player.view_height;
            player.view_height = 32;
            player.mode = .frozen;
            (try world.get(target, data.Transform)).angles = .{ -25, std.math.atan2(forward[1], forward[0]) * (180.0 / std.math.pi), 0 };
        }
        ritual.advance(.appearing, now, 500);
        try sound(world, slots, projections, entity, W.sounds.appear, now);
        try sound(world, slots, projections, entity, W.sounds.wind, now);
        return true;
    }
    return false;
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var ritual = (world.get(entity, data.Nightmare) catch continue).*;
        if (!alive(world, ritual.owner)) {
            try remove(world, slots, projections, entity);
            continue;
        }
        if (ritual.victim) |identity| if (!alive(world, identity)) {
            try release(world, entity, &ritual);
            ritual.advance(.after, now, 0);
        };
        if (now >= ritual.next_ms) switch (ritual.phase) {
            .casting => try search(world, slots, entity, &ritual, now),
            .waiting, .after => if (!try nextVictim(world, slots, projections, entity, &ritual, now)) {
                try remove(world, slots, projections, entity);
                continue;
            },
            .appearing => ritual.advance(.reaping, now, W.strike_ms),
            .reaping => {
                const identity = ritual.victim.?;
                const target = world.find(identity).?;
                const position = (try world.get(target, data.Transform)).position;
                const origin = (try world.get(entity, data.Transform)).position;
                try release(world, entity, &ritual);
                try sound(world, slots, projections, entity, W.sounds.strike, now);
                if ((world.get(target, data.Player) catch null) != null) {
                    (try world.get(target, data.Velocity)).linear = v.scale(v.normalize(v.subtract(position, origin)), 1500);
                    (try world.get(target, data.Player)).ground_entity = c.ENTITYNUM_NONE;
                    (try world.get(target, data.Body)).grounded = false;
                }
                const amount = ritual.damage;
                if (try @import("weapon_damage.zig").hurt(world, target, ritual.owner, W.id, amount, now, false)) try @import("weapon_damage.zig").shove(world, target, ritual.owner, v.subtract(position, v.add(origin, .{ 0, 0, -24 })), amount, now);
                ritual.advance(.after, now, 300);
            },
        };
        (try world.get(entity, data.Nightmare)).* = ritual;
        try publish(world, entity, projections);
    }
}
