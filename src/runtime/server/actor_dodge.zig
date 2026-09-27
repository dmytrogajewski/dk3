// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored ground-node escape selection shared by Harpy and Chaingang.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
pub fn destination(actors: *@import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, pose: data.Transform, body: data.Body) !?v.Vec3 {
    const random = try world.get(entity, data.Random);
    const slot = (try world.get(entity, data.Binding)).slot;
    var degrees = random.next() * 360;
    const turn: f32 = if (random.next() > 0.5) 10 else -10;
    var distance: f32 = 250;
    while (distance > 50) : (distance *= 0.5) {
        for (0..36) |_| {
            const direction = v.basis(.{ pose.angles[0], pose.angles[1] + degrees, pose.angles[2] }).forward;
            const point = v.add(pose.position, .{ direction[0] * distance, direction[1] * distance, 0 });
            _ = random.next(); // The shared reference vector helper samples altitude even on XY-only searches.
            const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = point, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
            if (!hit.start_solid and hit.fraction == 1) {
                return actors.water_routes.nearest(point);
            }
            degrees += turn;
        }
    }
    return null;
}
