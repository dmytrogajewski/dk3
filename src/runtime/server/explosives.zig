// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored explosive brushes emit material chunks through the scenery lifecycle.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const prop = @import("properties.zig");
const policy = @import("../domain/explosives.zig");
pub fn burst(world: *data.World, slots: *@import("../engine/slots.zig").Slots, projections: []abi.EntityProjection, entity: ecs.Entity, center: v.Vec3, extent: v.Vec3, now: i64) !void {
    const object = (try world.get(entity, data.MapObject)).*;
    const material = policy.material(object.flags);
    var random: data.Random = .{ .state = (try world.persistentId(entity)) *% 1664525 +% @as(u32, @truncate(@as(u64, @bitCast(now)))) };
    const count = if (object.flags & 64 != 0) 0 else policy.count(try prop.number(object, "count", 10), try prop.number(object, "rndcount", 0), random.next());
    const speed = try prop.number(object, "speed", 1);
    const scale = 1.5 * try prop.number(object, "scale", 1);
    const gravity = 800 * try prop.number(object, "gravity", 1);
    var toward: ?v.Vec3 = null;
    if (prop.text(object, "vectortarget")) |name| {
        var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.read(data.MapObject), view.read(data.Transform)) |candidate, pose| {
            if (std.ascii.eqlIgnoreCase(candidate.targetname, name)) toward = v.subtract(pose.position, center);
        };
    }
    for (0..count) |_| {
        const sample = @max(0.1, random.next());
        const size = scale * sample;
        const direction: v.Vec3 = if (toward) |delta| v.basis(.{ -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi + (random.next() * 2 - 1) * 15, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi + (random.next() * 2 - 1) * 50, 0 }).forward else .{ random.next() * 2 - 1, random.next() * 2 - 1, 1 };
        const model = policy.model(material, random.next() <= 0.5);
        const chunk = try world.create(null, .{
            data.Transform{ .position = v.add(center, v.scale(extent, sample * (if (toward != null) @as(f32, 0.1) else 0.3))), .angles = .{ 0, 0, 180 * random.next() } },
            data.Velocity{ .linear = v.scale(direction, 350 * speed) },
            data.Body{ .mins = @splat(0), .maxs = @splat(0), .mass = 25 * size, .collision_mask = c.MASK_SOLID },
            data.Gravity{ .acceleration = gravity },
            data.Scenery{ .model = model, .movement = .bounce, .started_ms = now, .scale = @splat(size), .spin = .{ (25 * size + 5) * 100, 0, (25 * size + 5) * 100 }, .alpha = if (material == .glass) 0.55 else 1, .fragment = true, .explosive_fragment = true, .expires_ms = now + 6000 },
        });
        try @import("weapon_entities.zig").bind(world, slots, projections, chunk, model);
        try @import("scenery.zig").publish(world, chunk, projections, now);
    }
    if (object.flags & 256 == 0) {
        try @import("scenery.zig").explosionVariant(world, slots, projections, center, 1, false, now);
        if (count > 0) try @import("events.zig").sound(world, slots, projections, "global/e_explodeb.wav", center, c.ENTITYNUM_WORLD, c.CHAN_AUTO, now);
    }
    if (object.flags & 128 == 0 and count > 0) {
        var name: [80]u8 = undefined;
        const sound = if (material == .stone) try std.fmt.bufPrint(&name, "global/e_rocktumble{d}.wav", .{1 + @as(u32, @intFromFloat(random.next() * 4))}) else try std.fmt.bufPrint(&name, "global/e_{s}breaks{c}.wav", .{ @tagName(material), @as(u8, 'a') + @as(u8, @intFromFloat(random.next() * 5)) });
        try @import("events.zig").sound(world, slots, projections, sound, center, c.ENTITYNUM_WORLD, c.CHAN_AUTO, now);
    }
    var message: [128]u8 = undefined;
    @import("../engine/server.zig").print(try std.fmt.bufPrintZ(&message, "dk3 explosive: target={s} material={s} chunks={d}\n", .{ object.targetname, @tagName(material), count }));
}
