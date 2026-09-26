// SPDX-License-Identifier: GPL-2.0-or-later
//! BSP submodels receive explicit ECS bindings and transport projections.
const std = @import("std");
const data = @import("../domain/components.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const Slots = @import("../engine/slots.zig").Slots;
pub fn spawn(world: *data.World, slots: *Slots, projections: []abi.EntityProjection) !void {
    // Collect handles before adding components: no structural edits in a query epoch.
    var entities: [@import("../ecs/world.zig").max_entities]@import("../ecs/world.zig").Entity = undefined;
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| {
            if (object.model.len > 1 and object.model[0] == '*' and !std.mem.eql(u8, object.classname, "func_areaportal")) {
                entities[count] = entity;
                count += 1;
            }
        };
    }
    for (entities[0..count]) |entity| {
        const object = (try world.get(entity, data.MapObject)).*;
        var transform = (try world.get(entity, data.Transform)).*;
        for ([_][]const u8{ "func_door", "func_button", "func_train", "func_plat" }) |name| if (std.mem.eql(u8, object.classname, name)) {
            transform.angles = @splat(0);
            (try world.get(entity, data.Transform)).angles = transform.angles;
            break;
        };
        const model = try std.fmt.parseInt(u16, object.model[1..], 10);
        const index = try slots.acquire(entity, null);
        errdefer slots.release(index, entity) catch unreachable;
        var name: [16]u8 = undefined;
        const path = try std.fmt.bufPrintZ(&name, "*{d}", .{model});
        const projection = &projections[index];
        _ = engine.gateway.call(c.G_SET_BRUSH_MODEL, .{ projection, path.ptr });
        const trigger = std.mem.startsWith(u8, object.classname, "trigger_");
        const hidden = trigger or std.mem.eql(u8, object.classname, "func_clip") or std.mem.eql(u8, object.classname, "func_monsterclip");
        const contents: u32 = if (trigger) c.CONTENTS_TRIGGER else if (std.mem.eql(u8, object.classname, "func_illusionary")) 0 else c.CONTENTS_SOLID;
        try world.put(entity, data.Binding{ .slot = index, .model = model });
        try world.put(entity, data.Body{ .mins = projection.shared.mins, .maxs = projection.shared.maxs, .contents = contents, .collision_mask = c.MASK_SOLID });
        projection.state.eType = c.ET_MOVER;
        projection.state.pos.trType = c.TR_STATIONARY;
        projection.state.pos.trBase = transform.position;
        projection.state.apos.trType = c.TR_STATIONARY;
        projection.state.apos.trBase = transform.angles;
        projection.shared.currentOrigin = transform.position;
        projection.shared.currentAngles = transform.angles;
        projection.shared.contents = @bitCast(contents);
        if (hidden) projection.shared.svFlags |= c.SVF_NOCLIENT;
        engine.link(projection);
    }
}
