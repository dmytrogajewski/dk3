// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("item_catalog").chest;
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
pub fn initialize(world: *data.World, entity: ecs.Entity, now: i64) !policy.State {
    const kind = policy.kind((try world.get(entity, data.MapObject)).classname) orelse return error.UnknownChest;
    try world.put(entity, data.Body{ .mins = .{ -10, -10, 0 }, .maxs = .{ 10, 10, 32 }, .contents = abi.c.CONTENTS_SOLID, .collision_mask = abi.c.MASK_SOLID });
    try world.put(entity, data.ItemMotion{ .base = (try world.get(entity, data.Transform)).position, .started_ms = now, .bounce = 0 });
    try world.put(entity, data.Random{ .state = (try world.persistentId(entity)) *% 0x9e3779b9 });
    return .{ .kind = kind, .stepped_ms = now };
}
pub fn bind(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    try @import("weapon_entities.zig").bind(world, slots, projections, entity, policy.model((try world.get(entity, data.WorldControl)).action.chest.kind));
    try publish(world, entity, projections, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const state = (try world.get(entity, data.WorldControl)).action.chest;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const out = &projections[binding.slot];
    out.state.number = binding.slot;
    out.state.eType = abi.c.ET_GENERAL;
    out.state.modelindex = if (state.phase == .exploding) try @import("resources.zig").model("models/global/we_expball.dkm") else binding.model;
    out.state.generic1 = policy.render_tag;
    out.state.frame = if (state.phase == .exploding) 0 else state.frame(now);
    out.state.time = @intCast(if (state.phase == .exploding) state.next_ms.? - 300 else state.started_ms orelse 0);
    out.state.time2 = @bitCast(try world.persistentId(entity));
    out.state.weapon = if (state.phase == .exploding) 2 else @intFromBool(state.phase == .revealing);
    out.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    out.state.apos = @import("../engine/trajectory.zig").stationary(if (state.phase == .exploding) .{ 0, 0, 1 } else pose.angles);
    out.shared.currentOrigin = pose.position;
    out.shared.mins = body.mins;
    out.shared.maxs = body.maxs;
    out.shared.contents = @bitCast(body.contents);
    out.shared.ownerNum = abi.c.ENTITYNUM_NONE;
    engine.link(out);
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) !void {
    const chest = &(try world.get(entity, data.WorldControl)).action.chest;
    if (chest.phase != .closed) return;
    const opener = world.find(activator) orelse return;
    if ((world.get(opener, data.Transform) catch null) == null) return;
    const roll: u8 = @intFromFloat((try world.get(entity, data.Random)).next() * 100);
    if (!chest.use(activator, now, roll)) return;
    try publish(world, entity, projections, now);
    try @import("events.zig").configuredSound(world, slots, projections, "doors/e3/woodendoor4open.wav", (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, abi.c.CHAN_VOICE, now, .{ .volume = 0.85 });
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.WorldControl)).action.chest;
    if (!try @import("items.zig").settle(world, entity, now, @intCast(@max(0, now - state.stepped_ms)))) {
        try @import("weapon_entities.zig").remove(world, slots, projections, entity);
        return;
    }
    state.stepped_ms = now;
    const roll: u8 = if (state.next_ms != null and state.next_ms.? <= now and state.phase == .opening and !state.explosive) @intFromFloat((try world.get(entity, data.Random)).next() * 100) else 0;
    const action = state.advance(now, roll);
    (try world.get(entity, data.WorldControl)).action.chest = state;
    const pose = (try world.get(entity, data.Transform)).*;
    if (action == .remove) {
        try @import("weapon_entities.zig").remove(world, slots, projections, entity);
        return;
    }
    if (action == .explode) {
        (try world.get(entity, data.Body)).contents = 0;
        var direction: data.Vec3 = .{ 0, 0, 30 };
        if (world.find(state.opener)) |opener| {
            direction = v.add(v.scale(v.normalize(v.subtract((try world.get(opener, data.Transform)).position, pose.position)), 16), .{ 0, 0, 30 });
            _ = try @import("damage.zig").apply(world, opener, 25, now, .{ .source = try world.persistentId(entity) });
        }
        try @import("scenery.zig").explosionVariant(world, slots, projections, v.add(pose.position, direction), 1, (try world.get(entity, data.Random)).next() < 0.5, now);
        try @import("scenery.zig").explosion(world, slots, projections, v.add(pose.position, direction), 0.55, now);
        try @import("events.zig").configuredSound(world, slots, projections, "global/e_explode1.wav", pose.position, abi.c.ENTITYNUM_NONE, abi.c.CHAN_AUTO, now, .{ .minimum = 32, .maximum = 2048 });
    }
    if (action == .reward) {
        const point = v.add(v.add(pose.position, .{ 0, 0, 40 }), v.scale(v.basis(pose.angles).forward, 8));
        _ = try @import("items.zig").spawnDynamic(world, slots, projections, state.rewardClass(), .{ .position = point }, now, 3);
    }
    try publish(world, entity, projections, now);
}
