// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").summon_effect;
pub fn spawn(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, point: v.Vec3, state: policy.State, now: i64) !void {
    const entity = try world.create(null, .{ data.Transform{ .position = point, .angles = (try world.get(owner, data.Transform)).angles }, data.Velocity{}, data.Body{}, data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .summon_effect = state } } });
    errdefer world.destroy(entity) catch unreachable;
    try @import("weapon_entities.zig").bind(world, slots, projections, entity, if (state.kind == .blue) "models/global/e_flblue.sp2" else "models/global/e_flred.sp2");
    try publish(world, entity, projections, now);
}
pub fn flare(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, point: v.Vec3, scale: v.Vec3, spin: v.Vec3, life_ms: i64, blue: bool, oriented: bool, now: i64) !void {
    try spawn(world, slots, projections, owner, point, .{ .kind = if (blue) .blue else .red, .scale = scale, .spin = spin, .oriented = oriented, .alpha_multiplier = if (life_ms > 1000) 0.95 else @as(f32, @floatFromInt(life_ms)) * 0.001, .expires_ms = now + life_ms, .next_ms = now + 100 }, now);
}
pub fn smoke(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, point: v.Vec3, now: i64) !void {
    // Retain the one-shot projection through its particle lifetime for delivery/restoration.
    try spawn(world, slots, projections, owner, point, .{ .kind = .smoke, .expires_ms = now + 800, .next_ms = now + 100 }, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    _ = now;
    const attack = (try world.get(entity, data.ActorAttack)).*;
    const state = attack.attack.summon_effect;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const out = &projections[binding.slot];
    out.state.number = binding.slot;
    out.state.eType = abi.c.ET_GENERAL;
    out.state.modelindex = binding.model;
    out.state.generic1 = policy.render_tag;
    out.state.weapon = @intFromEnum(state.kind);
    out.state.time = @intCast(attack.born_ms);
    out.state.time2 = @intFromBool(state.oriented);
    out.state.angles2 = state.scale;
    out.state.origin2[0] = state.alpha;
    out.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    out.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    out.shared.currentOrigin = pose.position;
    out.shared.contents = 0;
    engine.link(out);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const attack = try world.get(entity, data.ActorAttack);
    const state = &attack.attack.summon_effect;
    if (now > state.expires_ms) return @import("weapon_entities.zig").remove(world, slots, projections, entity);
    while (state.next_ms <= now) : (state.next_ms += 100) {
        if (state.kind != .smoke) {
            state.alpha *= state.alpha_multiplier;
            state.scale = v.scale(state.scale, 0.85);
            const pose = try world.get(entity, data.Transform);
            pose.angles = v.add(pose.angles, state.spin);
        }
    }
    attack.stepped_ms = now;
    try publish(world, entity, projections, now);
}
