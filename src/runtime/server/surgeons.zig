// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const v = @import("../domain/vector.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
pub fn think(world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: @import("../domain/actors.zig").Definition, now: i64) !void {
    const hurt = (try world.get(entity, data.Hurt)).*;
    if (hurt.revision != actor.receipt) {
        actor.receipt = hurt.revision;
        if (world.find(hurt.source)) |source| if ((world.get(source, data.Player) catch null) != null or (world.get(source, data.Actor) catch null) != null) {
            actor.threat = hurt.source;
            actor.surgeon.hurt(pose.position, now, (try world.get(entity, data.Random)).next());
        };
    }
    if (actor.surgeon.active) {
        var distance: f32 = std.math.inf(f32);
        var visible = false;
        if (world.find(actor.threat)) |target| {
            const point = (try world.get(target, data.Transform)).position;
            distance = v.length(v.subtract(point, pose.position));
            const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_OPAQUE });
            visible = hit.fraction == 1 or hit.entity == (try world.get(target, data.Binding)).slot;
        }
        const action = actor.surgeon.advance(distance, visible, definition.sight_range, now);
        actor.mode = .idle;
        if (action != .cower) {
            actor.threat = 0;
            actor.changed_ms = now;
        }
    }
    if (actor.surgeon.returning) {
        actor.threat_position = actor.surgeon.home;
        actor.mode = .chase;
        if (@import("../domain/navigation.zig").horizontalDistance(pose.position, actor.surgeon.home) < 16) {
            actor.surgeon.returning = false;
            actor.mode = .idle;
        }
    }
}
