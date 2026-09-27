// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("../domain/weather.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
pub fn initialize(world: *data.World, entity: ecs.Entity) !policy.State {
    const object = (try world.get(entity, data.MapObject)).*;
    const body = try world.get(entity, data.Body);
    const height = try @import("properties.zig").number(object, "height", 0);
    if (height < 0 or height > 1000000) return error.InvalidWeatherHeight;
    var state: policy.State = .{ .kind = if (std.mem.eql(u8, object.classname, "effect_rain")) .rain else .snow, .flags = object.flags, .mins = body.mins, .maxs = body.maxs };
    state.mins[2] = state.maxs[2] - height;
    body.contents = 0;
    body.collision_mask = 0;
    return state;
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const state = (try world.get(entity, data.WorldControl)).action.weather;
    const binding = (try world.get(entity, data.Binding)).*;
    const origin = (try world.get(entity, data.Transform)).position;
    const out = &projections[binding.slot];
    out.state.number = binding.slot;
    out.state.eType = abi.c.ET_GENERAL;
    out.state.generic1 = policy.render_tag;
    out.state.modelindex = binding.model;
    out.state.pos = @import("../engine/trajectory.zig").stationary(origin);
    out.state.origin2 = v.add(origin, state.mins);
    out.state.angles2 = v.add(origin, state.maxs);
    out.state.weapon = @intFromEnum(state.kind);
    out.state.frame = @bitCast(state.flags);
    out.state.time2 = @bitCast(try world.persistentId(entity));
    out.shared.contents = 0;
    out.shared.currentOrigin = origin;
    out.shared.svFlags = abi.c.SVF_BROADCAST;
    engine.link(out);
}

test "weather brushes become non-solid columns with authored height instead of visible movers" {
    const t = std.testing;
    var world = data.World.init(t.allocator, 4);
    defer world.deinit();
    const entity = try world.create(1, .{ data.MapObject{ .classname = "effect_rain", .model = "*2", .properties = &.{.{ .key = "height", .value = "1376" }} }, data.Body{ .mins = .{ -1089, -1281, 1231 }, .maxs = .{ -831, -1023, 1249 }, .contents = abi.c.CONTENTS_SOLID } });
    const state = try initialize(&world, entity);
    try t.expectEqual(@as(u32, 0), (try world.get(entity, data.Body)).contents);
    try t.expectEqual(@as(f32, -127), state.mins[2]);
    try t.expectEqual(@as(f32, 1249), state.maxs[2]);
    try t.expectEqual(@as(f32, -1089), state.mins[0]);
    try t.expectEqual(policy.Kind.rain, state.kind);
}
