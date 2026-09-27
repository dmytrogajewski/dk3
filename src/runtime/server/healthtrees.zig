// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored health tree interaction, fruit frames, sounds, floor contact and saves.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("item_catalog").healthtree;
const v = @import("../domain/vector.zig");
fn respawn() bool {
    return engine.integer("g_gametype") != c.GT_SINGLE_PLAYER and engine.integer("dm_item_respawn") != 0;
}
pub fn spawn(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    var entities: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (std.mem.eql(u8, object.classname, "misc_healthtree") or std.mem.eql(u8, object.classname, "misc_drugbox")) {
            entities[count] = entity;
            count += 1;
        };
    }
    for (entities[0..count]) |entity| {
        const drugbox = std.mem.eql(u8, (try world.get(entity, data.MapObject)).classname, "misc_drugbox");
        const maximum: u3 = @intFromFloat(std.math.clamp(try @import("properties.zig").number((try world.get(entity, data.MapObject)).*, "max_fruit", 5), 0, 5));
        try world.put(entity, data.HealthTree{ .drugbox = if (drugbox) .{} else null, .maximum = maximum, .fruit = maximum, .previous = 5, .changed_ms = now });
        try world.put(entity, data.Random{ .state = try world.persistentId(entity) });
        try world.put(entity, data.Health{ .current = 100, .maximum = 100 });
        try world.put(entity, data.Hurt{});
        try world.put(entity, data.Velocity{});
        var body: data.Body = .{ .mins = @splat(std.math.inf(f32)), .maxs = @splat(-std.math.inf(f32)), .contents = c.CONTENTS_SOLID, .collision_mask = c.MASK_SOLID, .mass = 1 };
        const angles = (try world.get(entity, data.Transform)).angles;
        for (0..8) |corner| {
            const point = @import("../domain/poses.zig").rotate(.{ if (corner & 1 == 0) -8 else 8, if (corner & 2 == 0) -8 else 8, if (corner & 4 == 0) -24 else 8 }, @splat(0), angles);
            for (point, 0..) |value, axis| {
                body.mins[axis] = @min(body.mins[axis], value);
                body.maxs[axis] = @max(body.maxs[axis], value);
            }
        }
        try world.put(entity, body);
        try @import("weapon_entities.zig").bind(world, slots, projections, entity, if (drugbox) @import("item_catalog").drugbox.model else policy.model);
        try publish(world, entity, projections, now);
    }
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) !void {
    const player = world.find(activator) orelse return;
    if ((world.get(player, data.Player) catch null) == null) return;
    const health = try world.get(player, data.Health);
    if ((try world.get(entity, data.HealthTree)).drugbox) |*box| {
        const dose = box.use(&health.current, health.maximum, now) orelse return;
        if (dose.sound.len > 0) try @import("events.zig").configuredSound(world, slots, projections, dose.sound, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now, .{ .volume = dose.volume });
        try publish(world, entity, projections, now);
        return;
    }
    if (!(try world.get(entity, data.HealthTree)).take(&health.current, health.maximum, now, respawn())) return;
    const sound = policy.sounds[@intFromBool((try world.get(entity, data.Random)).next() >= 0.5)];
    try @import("events.zig").sound(world, slots, projections, sound, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
    try publish(world, entity, projections, now);
    var text: [120]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 tree: id={d} fruit={d} player={d} health={d}\n", .{ try world.persistentId(entity), (try world.get(entity, data.HealthTree)).fruit, activator, (try world.get(player, data.Health)).current }));
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.modelindex = binding.model;
    const tree = (try world.get(entity, data.HealthTree)).*;
    projection.state.frame = tree.frame(now);
    if (tree.drugbox) |box| {
        projection.state.generic1 = @import("item_catalog").drugbox.render_tag;
        projection.state.time2 = @intFromFloat(box.alpha(now) * 255);
    }
    projection.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.mins = body.mins;
    projection.shared.maxs = body.maxs;
    projection.shared.contents = @bitCast(body.contents);
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64, elapsed: u32) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        const tree = world.get(entity, data.HealthTree) catch continue;
        if (tree.drugbox) |box| {
            if (box.alpha(now) <= 0.051) {
                try @import("weapon_entities.zig").remove(world, slots, projections, entity);
                continue;
            }
        }
        if (tree.drugbox == null and tree.regenerate(now, respawn())) try @import("events.zig").sound(world, slots, projections, policy.regen_sound, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
        const body = try world.get(entity, data.Body);
        const pose = try world.get(entity, data.Transform);
        const velocity = try world.get(entity, data.Velocity);
        const slot = (try world.get(entity, data.Binding)).slot;
        const collision = engine.collisionService();
        var remaining = elapsed;
        while (remaining > 0) {
            const milliseconds = @min(remaining, 50);
            remaining -= milliseconds;
            body.grounded = false;
            if (velocity.linear[2] <= 100) {
                const floor = try collision.trace(.{ .start = pose.position, .end = v.add(pose.position, .{ 0, 0, -0.5 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
                if (!floor.start_solid and !floor.all_solid and floor.fraction < 1 and floor.normal[2] >= 0.7) {
                    pose.position = floor.end;
                    velocity.linear[2] = 0;
                    body.grounded = true;
                }
            }
            const seconds = @as(f32, @floatFromInt(milliseconds)) * 0.001;
            velocity.linear[2] -= 800 * seconds;
            const hit = try collision.trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity.linear, seconds)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
            if (hit.start_solid or hit.all_solid) {
                velocity.linear = @splat(0);
                break;
            }
            pose.position = hit.end;
            if (hit.fraction < 1) {
                velocity.linear = policy.contact(velocity.linear, hit.normal);
                body.grounded = hit.normal[2] > 0.7 and velocity.linear[2] == 0;
            }
        }
        try publish(world, entity, projections, now);
    }
}
