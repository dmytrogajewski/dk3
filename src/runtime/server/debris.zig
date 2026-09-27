// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored brush fragments retain collision, motion, impact damage and final rest.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("../domain/debris.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
pub fn owns(name: []const u8) bool {
    return std.mem.eql(u8, name, "func_debris") or std.mem.eql(u8, name, "func_debris_visible");
}
pub fn initialize(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !policy.State {
    const object = (try world.get(entity, data.MapObject)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const visible = std.mem.eql(u8, object.classname, "func_debris_visible");
    var state: policy.State = .{ .visible = visible, .flags = object.flags | 4, .next_ms = now + @as(i64, if (visible) 200 else 100) };
    if (prop.text(object, "flag")) |flag| {
        inline for (.{ .{ "GO_TO_ACTIVATOR", 1 }, .{ "NO_ROTATE", 2 }, .{ "MOMENTUM_DAMAGE", 4 }, .{ "NO_ROTATION_ADJUST", 8 }, .{ "DROP_ONLY", 16 }, .{ "QUARTER_SIZE", 32 } }) |entry| if (std.ascii.eqlIgnoreCase(flag, entry[0])) {
            state.flags |= entry[1];
        };
    }
    state.parameters.volume = try prop.number(object, "volume", if (visible) 1 else 0.6);
    if (state.parameters.volume == 0) state.parameters.volume = if (visible) 1 else 0.6;
    state.parameters.volume = try @import("../domain/audio.zig").wireVolume(state.parameters.volume);
    state.parameters.minimum = try prop.number(object, "min", 256);
    state.parameters.maximum = try prop.number(object, "max", 648);
    if (state.parameters.minimum == 0) state.parameters.minimum = 256;
    if (state.parameters.maximum == 0) state.parameters.maximum = 648;
    if (!state.parameters.valid()) return error.InvalidDebrisSound;
    const out = projections[binding.slot].shared;
    const contents = try engine.collisionService().contents(v.scale(v.add(out.absmin, out.absmax), 0.5), binding.slot);
    state.water = contents & (c.CONTENTS_WATER | c.CONTENTS_SLIME | c.CONTENTS_LAVA) != 0;
    try world.put(entity, data.Velocity{});
    try world.put(entity, data.Random{ .state = try world.persistentId(entity) });
    (try world.get(entity, data.Body)).contents = if (visible) c.CONTENTS_SOLID else 0;
    return state;
}
fn resolve(world: *data.World, entity: ecs.Entity) !void {
    const object = (try world.get(entity, data.MapObject)).*;
    var state = (try world.get(entity, data.WorldControl)).action.debris;
    if (object.target.len > 0) {
        var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject), view.read(data.Transform)) |other, candidate, pose| {
            if (candidate.targetname.len > 0) {
                if (std.ascii.eqlIgnoreCase(object.target, candidate.targetname)) state.destination = pose.position;
            } else if (candidate.target.len > 0 and object.targetname.len > 0 and std.ascii.eqlIgnoreCase(candidate.target, object.targetname)) state.owner = try world.persistentId(other);
        };
    }
    state.initialized = true;
    (try world.get(entity, data.WorldControl)).action.debris = state;
}
pub fn publish(world: *data.World, entity: ecs.Entity, slots: *Slots, projections: []abi.EntityProjection) !void {
    const state = (try world.get(entity, data.WorldControl)).action.debris;
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const out = &projections[binding.slot];
    out.state.number = binding.slot;
    out.state.eType = c.ET_MOVER;
    out.state.modelindex = binding.model;
    out.state.generic1 = policy.render_tag;
    out.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    out.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    out.shared.currentOrigin = pose.position;
    out.shared.currentAngles = if (state.active or state.stopped) @splat(0) else pose.angles;
    out.shared.mins = body.mins;
    out.shared.maxs = body.maxs;
    out.shared.contents = @bitCast(body.contents);
    out.shared.bmodel = @intFromBool(!state.active and !state.stopped and state.visible);
    out.shared.ownerNum = if (world.find(state.owner)) |owner| slots.find(owner) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
    out.shared.svFlags = if (state.visible) 0 else c.SVF_NOCLIENT;
    engine.link(out);
}
fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, key: []const u8, now: i64) !void {
    const object = (try world.get(entity, data.MapObject)).*;
    const name = prop.text(object, key) orelse return;
    if (name.len == 0) return;
    try @import("events.zig").configuredSound(world, slots, projections, name, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now, (try world.get(entity, data.WorldControl)).action.debris.parameters);
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) !void {
    if (!(try world.get(entity, data.WorldControl)).action.debris.initialized) try resolve(world, entity);
    var state = (try world.get(entity, data.WorldControl)).action.debris;
    if (state.stopped) return;
    const object = (try world.get(entity, data.MapObject)).*;
    const slot = (try world.get(entity, data.Binding)).slot;
    const bounds = projections[slot].shared;
    const center = v.scale(v.add(bounds.absmin, bounds.absmax), 0.5);
    const body = try world.get(entity, data.Body);
    body.mins = v.scale(v.subtract(bounds.absmin, center), 0.05);
    body.maxs = v.scale(v.subtract(bounds.absmax, center), 0.05);
    body.contents = c.CONTENTS_SOLID;
    body.grounded = false;
    (try world.get(entity, data.Transform)).position = center;
    if (state.flags & 1 != 0) {
        const actor = world.find(activator) orelse return error.MissingDebrisActivator;
        state.destination = (try world.get(actor, data.Transform)).position;
    }
    const random = try world.get(entity, data.Random);
    const velocity = try world.get(entity, data.Velocity);
    if (object.target.len == 0 and state.flags & 1 == 0) {
        if (state.flags & 16 != 0) velocity.linear = .{ 0, 0, -(100 + random.next() * 200) } else {
            const direction: v.Vec3 = .{ random.next() * 2 - 1, random.next() * 2 - 1, random.next() * 2 - 1 };
            velocity.linear = v.scale(direction, 350 + random.next() * 1000);
        }
    } else {
        var upward: f32 = if (state.water) 150 + random.next() * 150 else if (state.flags & 16 == 0) 400 + random.next() * 300 else -(100 + random.next() * 100);
        if (std.ascii.eqlIgnoreCase(object.targetname, "fanboom")) upward = 50;
        const delta = v.subtract(state.destination, center);
        velocity.linear = v.scale(v.normalize(delta), try policy.forwardSpeed(center[2], state.destination[2], v.length(delta), upward));
        velocity.linear[2] = upward;
    }
    if (state.flags & 2 == 0) state.spin = .{ random.next() * 200, random.next() * 200, random.next() * 200 };
    state.active = true;
    state.visible = true;
    state.activator = activator;
    state.started_ms = now;
    state.stepped_ms = now;
    state.next_ms = now + 100;
    state.expand_ms = now + 650;
    (try world.get(entity, data.WorldControl)).action.debris = state;
    try publish(world, entity, slots, projections);
    try sound(world, slots, projections, entity, "fly_sound", now);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.WorldControl)).action.debris;
    if (!state.initialized and now >= state.next_ms) {
        try resolve(world, entity);
        state = (try world.get(entity, data.WorldControl)).action.debris;
    }
    if (!state.active) return;
    const body = try world.get(entity, data.Body);
    const pose = try world.get(entity, data.Transform);
    const velocity = try world.get(entity, data.Velocity);
    const slot = (try world.get(entity, data.Binding)).slot;
    if (now >= state.next_ms) {
        if (state.expand_ms) |at| if (now > at) {
            body.mins = v.scale(body.mins, 2.25);
            body.maxs = v.scale(body.maxs, 2.25);
            state.expand_ms = null;
        };
        if (now > state.started_ms + 7500 or (now > state.started_ms + 3500 and v.length(velocity.linear) == 0)) {
            state.active = false;
            state.stopped = true;
            (try world.get(entity, data.WorldControl)).action.debris = state;
            try publish(world, entity, slots, projections);
            return;
        }
        state.next_ms = now + 100;
    }
    var remaining = @max(0, now - state.stepped_ms);
    while (remaining > 0) {
        const elapsed = @min(remaining, 50);
        remaining -= elapsed;
        const seconds = @as(f32, @floatFromInt(elapsed)) * 0.001;
        pose.angles = v.add(pose.angles, v.scale(state.spin, seconds));
        velocity.linear[2] -= 800 * seconds;
        const previous = pose.position;
        const hit = try engine.collisionService().trace(.{ .start = previous, .end = v.add(previous, v.scale(velocity.linear, seconds)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_SOLID });
        if (hit.start_solid or hit.all_solid) {
            velocity.linear = @splat(0);
            state.spin = @splat(0);
            break;
        }
        pose.position = hit.end;
        if (hit.fraction < 1) {
            if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
                _ = try @import("damage.zig").apply(world, victim, @intFromFloat(v.length(velocity.linear) / 3), now, .{ .source = if (state.activator != 0) state.activator else try world.persistentId(entity) });
            };
            try sound(world, slots, projections, entity, "hit_sound", now);
            if (velocity.linear[2] < 0 and v.length(v.subtract(previous, pose.position)) == 0) {
                velocity.linear = @splat(0);
                state.spin = @splat(0);
                body.grounded = true;
                break;
            }
            velocity.linear = policy.contact(velocity.linear, hit.normal);
        }
    }
    state.stepped_ms = now;
    (try world.get(entity, data.WorldControl)).action.debris = state;
    try publish(world, entity, slots, projections);
}

/// A moving player/actor also generates contact with an active debris hull.
pub fn contact(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, victim: ecs.Entity, now: i64) !void {
    const state = (try world.get(entity, data.WorldControl)).action.debris;
    if (!state.active) return;
    _ = try @import("damage.zig").apply(world, victim, @intFromFloat(v.length((try world.get(entity, data.Velocity)).linear) / 3), now, .{ .source = if (state.activator != 0) state.activator else try world.persistentId(entity) });
    try sound(world, slots, projections, entity, "hit_sound", now);
}
