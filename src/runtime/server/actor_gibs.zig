// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("../domain/gibs.zig");
pub fn total(world: *data.World) usize {
    var result: usize = 0;
    var query = world.queryAccess(data.World.mask(.{data.Scenery}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.Scenery)) |state| if (state.gib != null) {
        result += 1;
    };
    return result;
}
pub fn spawn(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    if (engine.integer("gib_enable") == 0) return;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const hurt = (try world.get(entity, data.Hurt)).*;
    const inherited = (try world.get(entity, data.Velocity)).linear;
    var random = (try world.get(entity, data.Random)).*;
    const origin = if (world.find(hurt.source)) |source| (try world.get(source, data.Transform)).position else pose.position;
    const away = v.normalize(v.subtract(pose.position, origin));
    const angles: v.Vec3 = .{ -std.math.atan2(away[2], @sqrt(away[0] * away[0] + away[1] * away[1])) * 180 / std.math.pi, std.math.atan2(away[1], away[0]) * 180 / std.math.pi, 0 };
    const requested = policy.count(body.mass, @import("multiplayer.zig").enabled());
    const available = 100 - @min(100, total(world));
    const extent = v.subtract(body.maxs, body.mins);
    const length = @max(extent[0], extent[2]);
    for (0..@min(requested, available)) |index| {
        var offset: v.Vec3 = .{ random.next() * extent[0], random.next() * extent[1], random.next() * extent[2] };
        offset[if (extent[2] > extent[0]) @as(usize, 2) else 0] = @as(f32, @floatFromInt(index + 3)) * length / @as(f32, @floatFromInt(requested));
        const horizontal = @max(0.038, random.next() * 0.06) * std.math.clamp(body.mass, 128, 300) / 10;
        const vertical = @max(0.038, random.next() * 0.05) * std.math.clamp(body.mass, 128, 300) / 10;
        const direction = v.basis(v.add(angles, .{ (random.next() * 2 - 1) * 45, (random.next() * 2 - 1) * 45, 0 })).forward;
        const speed = std.math.clamp(@min(1, @as(f32, @floatFromInt(hurt.amount)) / 100) * random.next() * 3000, 225, 300);
        const kick: v.Vec3 = .{ direction[0] * speed * 1.65, direction[1] * speed * 1.65, direction[2] * speed * 2.15 };
        const fragment = try world.create(null, .{
            data.Transform{ .position = v.add(v.add(pose.position, body.mins), offset) },                                                                                                                                         data.Velocity{ .linear = v.add(kick, inherited) },
            data.Body{ .mins = v.scale(policy.bounds(index), -1), .maxs = policy.bounds(index), .mass = 2, .collision_mask = c.MASK_SOLID },                                                                                      data.Random{ .state = random.state ^ @as(u32, @intCast(index)) },
            data.Scenery{ .model = policy.model(index), .movement = .bounce, .started_ms = now, .scale = .{ horizontal, horizontal, vertical }, .spin = v.scale(kick, 2.5), .fragment = true, .gib = .{ .next_ms = now + 100 } },
        });
        try @import("weapon_entities.zig").bind(world, slots, projections, fragment, policy.model(index));
        try @import("scenery.zig").publish(world, fragment, projections, now);
    }
    var sound: [64]u8 = undefined;
    try @import("events.zig").sound(world, slots, projections, try std.fmt.bufPrint(&sound, "global/m_gibslop{c}.wav", .{@as(u8, 'a') + @as(u8, @intFromFloat(random.next() * 4))}), pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
    (try world.get(entity, data.Random)).* = random;
}
pub fn update(world: *data.World, entity: ecs.Entity, state: *data.Scenery, body: data.Body, now: i64) !bool {
    const gib = &state.gib.?;
    if (now < gib.next_ms) return false;
    gib.next_ms = now + 100;
    if (gib.fade_ms) |at| {
        if (now >= at) {
            if (state.alpha <= 0.1) return true;
            const pressure: f32 = @floatFromInt(total(world));
            state.alpha = @max(0.09, state.alpha - 0.15 * (if (pressure > 70) pressure * 0.03 else 1));
        }
    } else if (body.grounded and now > state.started_ms + 1500) {
        gib.fade_ms = now + 5000 + @as(i64, @intFromFloat((try world.get(entity, data.Random)).next() * 10000));
    }
    return false;
}
pub fn contact(world: *data.World, entity: ecs.Entity, state: *data.Scenery, velocity: v.Vec3, normal: v.Vec3) !v.Vec3 {
    const random = try world.get(entity, data.Random);
    const speed = v.length(velocity);
    for (&state.spin) |*spin| spin.* = (random.next() * 2 - 1) * speed;
    const reflected = v.scale(v.subtract(velocity, v.scale(normal, 2 * v.dot(velocity, normal))), 0.85);
    return if (normal[2] > 0.7 and @abs(reflected[2]) < 60) @splat(0) else reflected;
}
