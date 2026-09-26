// SPDX-License-Identifier: GPL-2.0-or-later
//! Persistent lightning graph. Bolts expand before damaging, sharing a bounded target set.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const W = @import("weapon_catalog").zeus;
const weapons = @import("../domain/weapons.zig");
const v = @import("../domain/vector.zig");
const c = abi.c;
const entities = @import("weapon_entities.zig");
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    if (world.get(entity, data.ZeusBolt) catch null) |bolt| {
        const value = bolt.*;
        try entities.effect(world, entity, projections, .{ .weapon = W.id, .owner = value.owner, .phase = @intFromEnum(value.phase), .endpoint = value.endpoint, .strength = if (value.source == value.owner) 1 else 0, .born_ms = value.born_ms, .end_ms = value.next_ms });
    } else {
        const chain = (try world.get(entity, data.Zeus)).*;
        try entities.effect(world, entity, projections, .{ .weapon = W.id, .owner = chain.owner, .phase = if (chain.closed_ms != null) 100 else 99, .end_ms = chain.closed_ms orelse 0 });
    }
}
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, shot: weapons.Fired, table: *const weapons.Table, now: i64) !void {
    const tuning = table.entries[W.id];
    const owner_id = try world.persistentId(owner);
    const boost = (try world.get(owner, data.Character)).attribute(.attack, now);
    const ready = now + W.releaseDelay(@import("weapon_catalog").transitions.attackFactor(boost));
    const entity = try world.create(null, .{ data.Transform{ .position = shot.position }, data.Zeus{ .owner = owner_id, .damage = tuning.damage, .range = tuning.range, .ammo_cost = tuning.ammoCost, .ready_ms = ready, .expires_ms = ready + 5500 }, data.Random{ .state = owner_id ^ @as(u32, @truncate(@as(u64, @bitCast(now)))) ^ 0x674afe2b } });
    errdefer world.destroy(entity) catch unreachable;
    try entities.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections);
}
fn valid(world: *data.World, entity: ecs.Entity, owner: u32) !bool {
    if (try world.persistentId(entity) == owner) return false;
    const health = world.get(entity, data.Health) catch return false;
    if (health.current <= 0) return false;
    if ((world.get(entity, data.Actor) catch null) != null) return true;
    return engine.integer("g_gametype") != c.GT_SINGLE_PLAYER and (world.get(entity, data.Player) catch null) != null;
}
fn point(world: *data.World, entity: ecs.Entity) !v.Vec3 {
    return @import("area_damage.zig").center(world, entity);
}
fn visible(world: *data.World, source: ecs.Entity, target: ecs.Entity) !bool {
    return @import("area_damage.zig").visible(try point(world, source), try point(world, target), (try world.get(source, data.Binding)).slot, (try world.get(target, data.Binding)).slot);
}
fn addBolt(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, chain: *data.Zeus, chain_id: u32, source: ecs.Entity, target: ecs.Entity, now: i64) !void {
    const target_id = try world.persistentId(target);
    if (!chain.reserve(target_id)) return;
    const position = try point(world, source);
    const entity = try world.create(null, .{ data.Transform{ .position = position }, data.ZeusBolt{ .owner = chain.owner, .chain = chain_id, .source = try world.persistentId(source), .target = target_id, .born_ms = now, .next_ms = now + 100, .endpoint = try point(world, target) } });
    errdefer world.destroy(entity) catch unreachable;
    try entities.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections);
    try @import("events.zig").sound(world, slots, projections, W.sounds[(try world.persistentId(entity)) % W.sounds.len], position, (try world.get(entity, data.Binding)).slot, c.CHAN_WEAPON, now);
}
fn strike(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, chain: *data.Zeus, owner: ecs.Entity, now: i64) !void {
    const pose = (try world.get(owner, data.Transform)).*;
    const forward = v.basis(.{ 0, pose.angles[1], 0 }).forward;
    var selected: ?ecs.Entity = null;
    for (slots.occupants) |occupant| {
        const candidate = occupant orelse continue;
        if (!try valid(world, candidate, chain.owner)) continue;
        var delta = v.subtract(try point(world, candidate), pose.position);
        if (v.length(delta) > chain.range) continue;
        delta[2] = 0;
        if (v.dot(v.normalize(delta), forward) < @sqrt(@as(f32, 0.5)) or !try visible(world, owner, candidate)) continue;
        selected = candidate;
        break;
    }
    const deathmatch = engine.integer("g_gametype") != c.GT_SINGLE_PLAYER;
    if ((selected != null or deathmatch) and (try world.get(owner, data.Weapons)).ammo[W.id] >= chain.ammo_cost) {
        (try world.get(owner, data.Weapons)).ammo[W.id] -= chain.ammo_cost;
        if (selected) |target| {
            chain.phase = .active;
            (try world.get(owner, data.Weapons)).weaponTime = 5000;
            try addBolt(world, slots, projections, chain, try world.persistentId(entity), owner, target, now);
            if (engine.integer("developer") > 0) engine.print("dk3 zig zeus: strike\n");
            const slot = (try world.get(owner, data.Binding)).slot;
            if ((try engine.collisionService().contents(pose.position, slot)) & c.MASK_WATER != 0) try @import("area_damage.zig").apply(world, slots, .{ .owner = chain.owner, .weapon = W.id, .origin = pose.position, .damage = chain.damage * 2, .radius = 64, .occlusion = false, .inertial = true }, now);
        } else {
            _ = try @import("weapon_damage.zig").hurt(world, owner, chain.owner, W.id, chain.damage * 0.5, now, false);
            try @import("weapon_damage.zig").shove(world, owner, chain.owner, v.scale(forward, -1), chain.damage * 0.5, now);
            try @import("events.zig").sound(world, slots, projections, W.sounds[0], pose.position, (try world.get(owner, data.Binding)).slot, c.CHAN_WEAPON, now);
        }
    }
    if (chain.phase == .pending) {
        chain.phase = .finished;
        chain.closed_ms = now;
        chain.expires_ms = now + 500;
        (try world.get(owner, data.Weapons)).weaponTime = 400;
    }
}
fn removeBolt(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, bolt: data.ZeusBolt) !void {
    if (bolt.phase != .fading) if (world.find(bolt.chain)) |parent| if (world.get(parent, data.Zeus) catch null) |chain| {
        chain.active -|= 1;
    };
    try entities.remove(world, slots, projections, entity);
}
fn bolts(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var bolt = (world.get(entity, data.ZeusBolt) catch continue).*;
        const parent = world.find(bolt.chain);
        const owner = world.find(bolt.owner);
        const source = world.find(bolt.source);
        const target = world.find(bolt.target);
        if (parent == null or owner == null or source == null or target == null or (try world.get(owner.?, data.Health)).current <= 0) {
            try removeBolt(world, slots, projections, entity, bolt);
            continue;
        }
        const origin = try point(world, source.?);
        bolt.endpoint = try point(world, target.?);
        if (now >= bolt.next_ms) {
            var chain = (try world.get(parent.?, data.Zeus)).*;
            switch (bolt.phase) {
                .spreading => {
                    bolt.phase = .zapping;
                    bolt.next_ms = now + 100;
                    var nearest: [2]?ecs.Entity = @splat(null);
                    var distances: [2]f32 = @splat(std.math.inf(f32));
                    for (slots.occupants) |candidate_slot| {
                        const candidate = candidate_slot orelse continue;
                        if (!try valid(world, candidate, bolt.owner) or chain.contains(try world.persistentId(candidate))) continue;
                        // Gold measures this hop's search radius from its source,
                        // while visibility is measured from its destination.
                        const distance = v.length(v.subtract(try point(world, candidate), origin));
                        if (distance >= chain.range * 0.25 or !try visible(world, target.?, candidate)) continue;
                        if (distance < distances[0]) {
                            distances[1] = distances[0];
                            nearest[1] = nearest[0];
                            distances[0] = distance;
                            nearest[0] = candidate;
                        } else if (distance < distances[1]) {
                            distances[1] = distance;
                            nearest[1] = candidate;
                        }
                    }
                    var random = (try world.get(parent.?, data.Random)).*;
                    const branches: usize = if (random.next() < 0.5) 1 else 2;
                    (try world.get(parent.?, data.Random)).* = random;
                    for (nearest[0..branches]) |candidate| if (candidate) |who| try addBolt(world, slots, projections, &chain, bolt.chain, target.?, who, now);
                },
                .zapping => {
                    const amount = chain.zap();
                    if (try @import("weapon_damage.zig").hurt(world, target.?, bolt.owner, W.id, amount, now, false)) try @import("weapon_damage.zig").shove(world, target.?, bolt.owner, v.subtract(bolt.endpoint, origin), amount, now);
                    bolt.phase = .fading;
                    bolt.next_ms = now + 500;
                    if (engine.integer("developer") > 0) {
                        var output: [144]u8 = undefined;
                        engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig zeus: target={d} damage={d:.2} targets={d} active={d}\n", .{ bolt.target, amount, chain.count, chain.active }));
                    }
                },
                .fading => {
                    try removeBolt(world, slots, projections, entity, bolt);
                    continue;
                },
            }
            (try world.get(parent.?, data.Zeus)).* = chain;
        }
        (try world.get(entity, data.Transform)).position = origin;
        (try world.get(entity, data.ZeusBolt)).* = bolt;
        try publish(world, entity, projections);
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var chain = (world.get(entity, data.Zeus) catch continue).*;
        const owner = world.find(chain.owner);
        if (owner == null or (try world.get(owner.?, data.Health)).current <= 0 or now >= chain.expires_ms or (chain.phase == .pending and (try world.get(owner.?, data.Weapons)).weapon != W.id)) {
            try entities.remove(world, slots, projections, entity);
            continue;
        }
        if (chain.phase == .pending and now >= chain.ready_ms) try strike(world, slots, projections, entity, &chain, owner.?, now);
        if (chain.phase == .active and chain.active == 0) {
            chain.phase = .finished;
            chain.closed_ms = now;
            if (engine.integer("developer") > 0) {
                var output: [128]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig zeus: closed targets={d} zaps={d}\n", .{ chain.count, chain.zaps }));
            }
        }
        (try world.get(entity, data.Transform)).position = (try world.get(owner.?, data.Transform)).position;
        (try world.get(entity, data.Zeus)).* = chain;
        try publish(world, entity, projections);
    }
    try bolts(world, slots, projections, now);
}
