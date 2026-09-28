// SPDX-License-Identifier: GPL-2.0-or-later
//! Persistent lightning graph. Bolts expand before damaging, sharing a bounded target set.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const access = @import("region_access.zig");
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
fn valid(entity: Ref, owner: u32) !bool {
    if (try entity.id() == owner or (entity.get(data.Health) catch return false).current <= 0) return false;
    if ((entity.get(data.Actor) catch null) != null) return true;
    return engine.integer("g_gametype") != c.GT_SINGLE_PLAYER and (entity.get(data.Player) catch null) != null;
}
fn point(entity: Ref) !v.Vec3 {
    return @import("area_damage.zig").center(entity.world, entity.entity);
}
fn visible(source: Ref, target: Ref) !bool {
    const hit = try @import("region_collision.zig").owned(source.world, .{ .start = try point(source), .end = try point(target), .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = c.MASK_SOLID }, try source.id());
    return @import("region_collision.zig").reaches(source.world, hit, target);
}
fn addBolt(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, chain: *data.Zeus, chain_id: u32, source: Ref, target: Ref, now: i64) !void {
    if (source.world != world) {
        const context = access.contextFor(source.world) orelse return error.LightningWorldUnavailable;
        const scope = try context.select();
        defer scope.deinit();
        try context.expose(now);
        return addBolt(source.world, &context.slots, &context.projection, chain, chain_id, source, target, now);
    }
    const target_id = try target.id();
    if (!chain.reserve(target_id)) return;
    const position = try point(source);
    const entity = try world.create(null, .{ data.Transform{ .position = position }, data.ZeusBolt{ .owner = chain.owner, .chain = chain_id, .source = try source.id(), .target = target_id, .born_ms = now, .next_ms = now + 100, .endpoint = try point(target) } });
    errdefer world.destroy(entity) catch unreachable;
    try entities.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections);
    try @import("events.zig").sound(world, slots, projections, W.sounds[(try world.persistentId(entity)) % W.sounds.len], position, (try world.get(entity, data.Binding)).slot, c.CHAN_WEAPON, now);
}
fn strike(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, chain: *data.Zeus, owner: Ref, now: i64) !void {
    const pose = (try owner.get(data.Transform)).*;
    const forward = v.basis(.{ 0, pose.angles[1], 0 }).forward;
    var selected: ?Ref = null;
    var candidates = access.Damageables.init(world, slots);
    while (candidates.next()) |candidate| {
        if (!try valid(candidate, chain.owner)) continue;
        var delta = v.subtract(try point(candidate), pose.position);
        if (v.length(delta) > chain.range) continue;
        delta[2] = 0;
        if (v.dot(v.normalize(delta), forward) < @sqrt(@as(f32, 0.5)) or !try visible(owner, candidate)) continue;
        selected = candidate;
        break;
    }
    const deathmatch = engine.integer("g_gametype") != c.GT_SINGLE_PLAYER;
    if ((selected != null or deathmatch) and (try owner.get(data.Weapons)).ammo[W.id] >= chain.ammo_cost) {
        (try owner.get(data.Weapons)).ammo[W.id] -= chain.ammo_cost;
        if (selected) |target| {
            chain.phase = .active;
            (try owner.get(data.Weapons)).weaponTime = 5000;
            try addBolt(world, slots, projections, chain, try world.persistentId(entity), owner, target, now);
            if (engine.integer("developer") > 0) engine.print("dk3 zig zeus: strike\n");
            const slot = (try owner.get(data.Binding)).slot;
            if ((try engine.collisionService().contents(pose.position, slot)) & c.MASK_WATER != 0) try @import("area_damage.zig").apply(world, slots, .{ .owner = chain.owner, .weapon = W.id, .origin = pose.position, .damage = chain.damage * 2, .radius = 64, .occlusion = false, .inertial = true }, now);
        } else {
            _ = try @import("weapon_damage.zig").hurt(owner.world, owner.entity, chain.owner, W.id, chain.damage * 0.5, now, false);
            try @import("weapon_damage.zig").shove(owner.world, owner.entity, chain.owner, v.scale(forward, -1), chain.damage * 0.5, now);
            try @import("events.zig").sound(world, slots, projections, W.sounds[0], pose.position, (try owner.get(data.Binding)).slot, c.CHAN_WEAPON, now);
        }
    }
    if (chain.phase == .pending) {
        chain.phase = .finished;
        chain.closed_ms = now;
        chain.expires_ms = now + 500;
        (try owner.get(data.Weapons)).weaponTime = 400;
    }
}
fn removeBolt(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, bolt: data.ZeusBolt) !void {
    if (bolt.phase != .fading) if (access.find(world, bolt.chain)) |parent| if (parent.get(data.Zeus) catch null) |chain| {
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
        const parent = access.find(world, bolt.chain);
        const owner = access.find(world, bolt.owner);
        const source = access.find(world, bolt.source);
        const target = access.find(world, bolt.target);
        if (parent == null or owner == null or source == null or target == null or (try owner.?.get(data.Health)).current <= 0) {
            try removeBolt(world, slots, projections, entity, bolt);
            continue;
        }
        const origin = try point(source.?);
        bolt.endpoint = try point(target.?);
        if (now >= bolt.next_ms) {
            var chain = (try parent.?.get(data.Zeus)).*;
            switch (bolt.phase) {
                .spreading => {
                    bolt.phase = .zapping;
                    bolt.next_ms = now + 100;
                    var nearest: [2]?Ref = @splat(null);
                    var distances: [2]f32 = @splat(std.math.inf(f32));
                    var candidates = access.Damageables.init(world, slots);
                    while (candidates.next()) |candidate| {
                        if (!try valid(candidate, bolt.owner) or chain.contains(try candidate.id())) continue;
                        // Gold measures this hop's search radius from its source,
                        // while visibility is measured from its destination.
                        const distance = v.length(v.subtract(try point(candidate), origin));
                        if (distance >= chain.range * 0.25 or !try visible(target.?, candidate)) continue;
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
                    var random = (try parent.?.get(data.Random)).*;
                    const branches: usize = if (random.next() < 0.5) 1 else 2;
                    (try parent.?.get(data.Random)).* = random;
                    for (nearest[0..branches]) |candidate| if (candidate) |who| try addBolt(world, slots, projections, &chain, bolt.chain, target.?, who, now);
                },
                .zapping => {
                    const amount = chain.zap();
                    if (try @import("weapon_damage.zig").hurt(target.?.world, target.?.entity, bolt.owner, W.id, amount, now, false)) try @import("weapon_damage.zig").shove(target.?.world, target.?.entity, bolt.owner, v.subtract(bolt.endpoint, origin), amount, now);
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
            (try parent.?.get(data.Zeus)).* = chain;
        }
        (try world.get(entity, data.Transform)).position = origin;
        (try world.get(entity, data.ZeusBolt)).* = bolt;
        try publish(world, entity, projections);
        try @import("region_motion.zig").Cursor.init(source.?.world, 0).finish(world, entity, now);
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var chain = (world.get(entity, data.Zeus) catch continue).*;
        const owner = access.find(world, chain.owner);
        if (owner == null or (try owner.?.get(data.Health)).current <= 0 or now >= chain.expires_ms or (chain.phase == .pending and (try owner.?.get(data.Weapons)).weapon != W.id)) {
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
        (try world.get(entity, data.Transform)).position = (try owner.?.get(data.Transform)).position;
        (try world.get(entity, data.Zeus)).* = chain;
        try publish(world, entity, projections);
    }
    try bolts(world, slots, projections, now);
}
