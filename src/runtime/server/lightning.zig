// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored emitters and attractors; projectiles remain independent, saved entities.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("../domain/lightning.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Router = @import("targets.zig").Router;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
const entities = @import("weapon_entities.zig");
pub fn initialize(world: *data.World, entity: ecs.Entity, now: i64) !policy.Emitter {
    const object = (try world.get(entity, data.MapObject)).*;
    var state: policy.Emitter = .{ .flags = object.flags, .next_ms = now + if (object.flags & policy.constant != 0) @as(i64, 3750) else 100, .uncull_until_ms = now + 3000 };
    state.damage = try prop.number(object, "dmg", 0);
    state.scale = try prop.number(object, "scale", 10);
    if (state.scale == 0) state.scale = 10;
    state.modulation = try prop.number(object, "modulation", 1);
    state.chance = try prop.number(object, "chance", 0.1);
    if (state.chance == 0) state.chance = 0.1;
    state.ground_chance = try prop.number(object, "gndchance", 0.2);
    if (state.ground_chance == 0) state.ground_chance = 0.2;
    state.delay_ms = try prop.milliseconds(object, "delay", 2);
    if (state.delay_ms == 0) state.delay_ms = 2000;
    state.duration_ms = try prop.milliseconds(object, "duration", 0.3);
    if (state.duration_ms == 0) state.duration_ms = 300;
    if (state.damage < 0 or state.scale <= 0 or state.modulation < 0 or state.delay_ms < 0 or state.duration_ms < 0) return error.InvalidAuthoredLightning;
    if (prop.text(object, "_color")) |color| state.color = try @import("map.zig").vector(color);
    for (object.properties) |property| {
        const index: usize = if (std.ascii.eqlIgnoreCase(property.key, "sound") or std.ascii.eqlIgnoreCase(property.key, "sound1")) 0 else if (std.ascii.eqlIgnoreCase(property.key, "sound2")) 1 else if (std.ascii.eqlIgnoreCase(property.key, "sound3")) 2 else continue;
        state.sounds[index] = try @import("resources.zig").sound(property.value);
    }
    try world.put(entity, data.Random{ .state = try world.persistentId(entity) });
    return state;
}
pub fn attractor(object: data.MapObject, now: i64) !policy.Attractor {
    return .{ .link_ms = if (object.targetname.len > 0) now + 200 + @as(i64, @intFromFloat(@trunc(try prop.number(object, "triggerindex", 0)) * 100)) else null };
}
/// Link once, in authored trigger-index/entity order. Separate lists avoid the
/// reference's shared-node removal alias when several emitters name one attractor.
pub fn linkAttractors(world: *data.World, now: i64) !void {
    const Pending = struct { entity: ecs.Entity, id: u32, at: i64 };
    var pending: [ecs.max_entities]Pending = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.WorldControl}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.WorldControl)) |entity, control| if (control.action == .attractor) {
            if (control.action.attractor.link_ms) |at| if (at <= now) {
                pending[count] = .{ .entity = entity, .id = try world.persistentId(entity), .at = at };
                count += 1;
            };
        };
    }
    std.mem.sort(Pending, pending[0..count], {}, struct {
        fn less(_: void, a: Pending, b: Pending) bool {
            return if (a.at == b.at) a.id < b.id else a.at < b.at;
        }
    }.less);
    for (pending[0..count]) |entry| {
        const name = (try world.get(entry.entity, data.MapObject)).targetname;
        var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.WorldControl }), 0, data.World.mask(.{data.WorldControl}));
        while (query.next()) |view| for (view.read(data.MapObject), view.write(data.WorldControl)) |object, *control| {
            if (control.action != .lightning or !std.ascii.eqlIgnoreCase(object.target, name)) continue;
            const state = &control.action.lightning;
            if (state.count == state.attractors.len) {
                query.deinit();
                return error.LightningAttractorCapacity;
            }
            state.attractors[state.count] = entry.id;
            state.count += 1;
            if (state.current == 0 and state.count == 1) state.current = entry.id;
        };
        query.deinit();
        (try world.get(entry.entity, data.WorldControl)).action.attractor = .{ .link_ms = null, .linked = true };
    }
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const control = (try world.get(entity, data.WorldControl)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const origin = (try world.get(entity, data.Transform)).position;
    const out = &projections[binding.slot];
    out.state.number = binding.slot;
    out.state.eType = c.ET_GENERAL;
    out.state.pos = @import("../engine/trajectory.zig").stationary(origin);
    out.state.modelindex = 0;
    out.shared.currentOrigin = origin;
    out.shared.mins = @splat(-1);
    out.shared.maxs = @splat(1);
    out.shared.contents = 0;
    out.shared.ownerNum = c.ENTITYNUM_NONE;
    out.shared.svFlags = c.SVF_NOCLIENT;
    if (control.action == .lightning) {
        const state = control.action.lightning;
        out.state.generic1 = @import("../domain/audio.zig").parameter_tag;
        const parameters: @import("../domain/audio.zig").Parameters = .{};
        out.state.angles2 = .{ parameters.volume, parameters.minimum, parameters.maximum };
        out.state.weapon = 0;
        out.state.loopSound = if (state.flags & policy.on != 0) state.loop_sound else 0;
        if (out.state.loopSound != 0) out.shared.svFlags = 0;
    } else {
        const bolt = control.action.lightning_bolt;
        const emitter = world.find(bolt.emitter) orelse {
            engine.link(out);
            return;
        };
        const state = (try world.get(emitter, data.WorldControl)).action.lightning;
        out.state.generic1 = policy.render_tag;
        out.state.time2 = @bitCast(try world.persistentId(entity));
        out.state.origin2 = bolt.endpoint;
        if (world.find(bolt.target)) |target| out.state.origin2 = (try world.get(target, data.Transform)).position;
        out.state.otherEntityNum = if (world.find(bolt.target)) |target| if (world.get(target, data.Binding) catch null) |bound| bound.slot else c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
        out.state.angles2 = state.color;
        out.state.pos.trDelta = .{ state.scale, state.modulation, 0 };
        out.state.weapon = @bitCast(state.flags);
        out.shared.svFlags = c.SVF_BROADCAST;
    }
    engine.link(out);
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, entity: ecs.Entity, now: i64) !void {
    const state = &(try world.get(entity, data.WorldControl)).action.lightning;
    if (state.flags & policy.once != 0) {
        try strike(world, slots, projections, router, entity, now);
    } else if (state.flags & policy.on != 0) {
        state.flags &= ~@as(u32, policy.on);
        state.next_ms = null;
        state.initialized = true;
    } else {
        state.flags |= policy.on;
        try strike(world, slots, projections, router, entity, now);
    }
    if (world.alive(entity)) try publish(world, entity, projections);
}
fn recipient(world: *data.World, entity: ecs.Entity) bool {
    return (world.get(entity, data.Player) catch null) != null or (world.get(entity, data.Companion) catch null) != null;
}
fn spawnBolt(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, emitter: ecs.Entity, target: u32, endpoint: v.Vec3, now: i64) !void {
    const state = (try world.get(emitter, data.WorldControl)).action.lightning;
    const origin = (try world.get(emitter, data.Transform)).position;
    if (now > state.uncull_until_ms and state.flags & policy.constant == 0) {
        var audible = false;
        for (slots.occupants) |occupant| if (occupant) |client| if (recipient(world, client) and engine.inPhs((try world.get(client, data.Transform)).position, origin)) {
            audible = true;
            break;
        };
        if (!audible) return;
    }
    const bolt = try world.create(null, .{ data.Transform{ .position = origin }, data.MapObject{ .classname = "effect_lightning_bolt" }, data.WorldControl{ .action = .{ .lightning_bolt = .{ .emitter = try world.persistentId(emitter), .target = target, .endpoint = endpoint, .next_ms = now + 100, .until_ms = now + state.duration_ms, .damage = state.damage } } } });
    try entities.bind(world, slots, projections, bolt, "");
    try publish(world, bolt, projections);
    const choice: usize = @intFromFloat((try world.get(emitter, data.Random)).next() * 2.9);
    const sound = if (state.sounds[choice] != 0) state.sounds[choice] else state.sounds[0];
    if (sound != 0) {
        if (state.flags & policy.constant != 0) {
            (try world.get(emitter, data.WorldControl)).action.lightning.loop_sound = state.sounds[0];
        } else try @import("events.zig").configuredSound(world, slots, projections, @import("resources.zig").soundName(sound), origin, (try world.get(bolt, data.Binding)).slot, c.CHAN_AUTO, now, .{});
    }
}
fn strike(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.WorldControl)).action.lightning;
    var random = (try world.get(entity, data.Random)).*;
    const origin = (try world.get(entity, data.Transform)).position;
    const slot = (try world.get(entity, data.Binding)).slot;
    var target: u32 = 0;
    var point: ?v.Vec3 = null;
    var attracted: ?ecs.Entity = null;
    switch (state.branch(random.next())) {
        .client => {
            var closest: f32 = 2000;
            for (slots.occupants) |occupant| if (occupant) |client| {
                if (!recipient(world, client)) continue;
                const position = (try world.get(client, data.Transform)).position;
                const direction = v.subtract(position, origin);
                const distance = v.length(direction);
                if (distance >= closest) continue;
                const hit = try engine.collisionService().trace(.{ .start = v.add(origin, v.scale(v.normalize(direction), 128)), .end = position, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
                if (hit.entity == (try world.get(client, data.Binding)).slot or hit.fraction == 1) {
                    closest = distance;
                    target = try world.persistentId(client);
                    point = position;
                }
            };
        },
        .ground => for (0..6) |_| {
            const direction = v.basis(@import("../domain/complex_particles.zig").angles(.{ random.next() - 0.5, random.next() - 0.5, random.next() - 0.5 })).forward;
            const start = v.add(origin, v.scale(direction, 128));
            const hit = try engine.collisionService().trace(.{ .start = start, .end = v.add(start, v.scale(direction, 2000)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
            if (hit.entity == c.ENTITYNUM_WORLD and hit.fraction < 1) {
                point = hit.end;
                break;
            }
        },
        .attractor => {
            var count: u8 = 0;
            for (state.attractors[0..state.count]) |id| if (world.find(id)) |candidate| {
                const action = (world.get(candidate, data.WorldControl) catch continue).action;
                if (action != .attractor) continue;
                state.attractors[count] = id;
                count += 1;
            };
            @memset(state.attractors[count..], 0);
            state.count = count;
            if (state.choose(random.next())) |id| {
                attracted = world.find(id);
                point = (try world.get(attracted.?, data.Transform)).position;
            }
        },
    }
    state.schedule(now, random.next());
    (try world.get(entity, data.Random)).* = random;
    (try world.get(entity, data.WorldControl)).action.lightning = state;
    if (attracted) |attractor_entity| try router.fire(world, slots, projections, attractor_entity, 0, now);
    if (!world.alive(entity)) return;
    if (point) |endpoint| try spawnBolt(world, slots, projections, entity, target, endpoint, now);
}
fn hurt(world: *data.World, bolt: policy.Bolt, target: ecs.Entity, origin: v.Vec3, now: i64) !void {
    if (bolt.damage <= 0) return;
    const direction = v.subtract((try world.get(target, data.Transform)).position, origin);
    if (try @import("weapon_damage.zig").hurt(world, target, bolt.emitter, 0, bolt.damage, now, false)) try @import("weapon_damage.zig").shove(world, target, bolt.emitter, direction, bolt.damage, now);
}
fn traceDamage(world: *data.World, slots: *Slots, entity: ecs.Entity, bolt: policy.Bolt, origin: v.Vec3, now: i64) !void {
    const hit = try engine.collisionService().trace(.{ .start = origin, .end = bolt.endpoint, .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SHOT });
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |target| if (recipient(world, target) and try world.persistentId(target) != bolt.emitter) try hurt(world, bolt, target, origin, now);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, entity: ecs.Entity, now: i64) !void {
    const control = (try world.get(entity, data.WorldControl)).*;
    if (control.action == .lightning) {
        const state = &(try world.get(entity, data.WorldControl)).action.lightning;
        if (state.next_ms == null or now < state.next_ms.?) return;
        const startup = !state.initialized;
        state.initialized = true;
        state.next_ms = null;
        if (!startup or state.flags & policy.on != 0) try strike(world, slots, projections, router, entity, now);
        if (!world.alive(entity)) return;
        const updated = &(try world.get(entity, data.WorldControl)).action.lightning;
        if (startup and updated.next_ms != null) updated.next_ms = now + 3000;
        try publish(world, entity, projections);
        return;
    }
    var bolt = control.action.lightning_bolt;
    if (now < bolt.next_ms) return;
    const emitter = world.find(bolt.emitter) orelse {
        try entities.remove(world, slots, projections, entity);
        return;
    };
    const state = (try world.get(emitter, data.WorldControl)).action.lightning;
    const origin = (try world.get(entity, data.Transform)).position;
    if (world.find(bolt.target)) |target| {
        bolt.endpoint = (try world.get(target, data.Transform)).position;
    } else bolt.target = 0;
    if (bolt.expired(state, now)) {
        if (bolt.damage > 0 and state.flags & policy.trace_damage != 0) try traceDamage(world, slots, entity, bolt, origin, now);
        if (state.flags & policy.scorch != 0) {
            const hit = try engine.collisionService().trace(.{ .start = bolt.endpoint, .end = v.add(bolt.endpoint, v.scale(v.subtract(bolt.endpoint, origin), 1.1)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(emitter, data.Binding)).slot, .mask = c.MASK_SOLID });
            if (hit.entity == c.ENTITYNUM_WORLD and hit.fraction < 1) try scorchEvent(world, slots, projections, hit.end, hit.normal, now);
        }
        try entities.remove(world, slots, projections, entity);
        return;
    }
    if (world.find(bolt.target)) |target| {
        try hurt(world, bolt, target, origin, now);
    } else if (bolt.damage > 0 and bolt.check_trace and state.flags & policy.trace_damage != 0) {
        try traceDamage(world, slots, entity, bolt, origin, now);
        bolt.traced(state);
    }
    bolt.next_ms = now + if (state.flags & policy.constant != 0) @as(i64, 500) else 100;
    (try world.get(entity, data.WorldControl)).action.lightning_bolt = bolt;
    try publish(world, entity, projections);
}
fn scorchEvent(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, origin: v.Vec3, normal: v.Vec3, now: i64) !void {
    // Use the existing transient event lifetime, with a distinct authored-effect tag.
    try @import("events.zig").impact(world, slots, projections, .{ .weapon = 0, .kind = .world, .normal = normal, .sequence = policy.scorch_tag }, origin, now);
}

test "attractors link once in deadline and identity order to every matching emitter" {
    const t = std.testing;
    var world = data.World.init(t.allocator, 16);
    defer world.deinit();
    const source = try world.create(100, .{ data.MapObject{ .classname = "effect_lightning", .target = "arc" }, data.WorldControl{ .action = .{ .lightning = .{ .flags = policy.cycle, .next_ms = null, .uncull_until_ms = 3000 } } } });
    const other = try world.create(101, .{ data.MapObject{ .classname = "effect_lightning", .target = "ARC" }, data.WorldControl{ .action = .{ .lightning = .{ .flags = 0, .next_ms = null, .uncull_until_ms = 3000 } } } });
    _ = try world.create(8, .{ data.MapObject{ .classname = "target_attractor", .targetname = "arc" }, data.WorldControl{ .action = .{ .attractor = .{ .link_ms = 300 } } } });
    _ = try world.create(7, .{ data.MapObject{ .classname = "target_attractor", .targetname = "arc" }, data.WorldControl{ .action = .{ .attractor = .{ .link_ms = 200 } } } });
    _ = try world.create(6, .{ data.MapObject{ .classname = "target_attractor", .targetname = "arc" }, data.WorldControl{ .action = .{ .attractor = .{ .link_ms = 200 } } } });
    try linkAttractors(&world, 199);
    try t.expectEqual(@as(u8, 0), (try world.get(source, data.WorldControl)).action.lightning.count);
    try linkAttractors(&world, 300);
    try linkAttractors(&world, 500);
    for ([_]ecs.Entity{ source, other }) |entity| {
        const state = (try world.get(entity, data.WorldControl)).action.lightning;
        try t.expectEqual(@as(u8, 3), state.count);
        try t.expectEqualSlices(u32, &.{ 6, 7, 8 }, state.attractors[0..state.count]);
    }
}
