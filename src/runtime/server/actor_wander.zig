// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const rules = @import("../domain/actors.zig");
const v = @import("../domain/vector.zig");
const Routes = @import("air_routes.zig").Routes;
pub fn next(routes: *const Routes, pose: data.Transform, start: v.Vec3, definition: rules.Definition, random: *data.Random, water: ?struct { body: data.Body, slot: u16 }) !?v.Vec3 {
    var nearest: usize = 0;
    var distance = std.math.inf(f32);
    if (routes.nodes.len == 0) return null;
    for (routes.nodes, 0..) |node, i| {
        const separation = v.length(v.subtract(node.position, pose.position));
        if (separation < distance) {
            nearest = i;
            distance = separation;
        }
    }
    const links = routes.nodes[nearest].links;
    if (links.len == 0) return null;
    var eligible: [6]usize = undefined;
    var usable: [6]usize = undefined;
    var usable_count: usize = 0;
    var count: usize = 0;
    for (links, 0..) |link, i| {
        const point = routes.nodes[routes.indices[@intCast(link[1])].?].position;
        if (water) |context| if (!try Routes.waterPath(pose.position, point, context.body, context.slot)) continue;
        usable[usable_count] = i;
        usable_count += 1;
        const offset = v.subtract(point, pose.position);
        if (!@import("actor_catalog").wander.candidate(v.length(v.subtract(point, start)), definition.sight_range, @sqrt(offset[0] * offset[0] + offset[1] * offset[1]), offset[2], std.math.atan2(offset[1], offset[0]) * 180 / std.math.pi - pose.angles[1], definition.walk_speed)) continue;
        eligible[count] = i;
        count += 1;
    }
    if (usable_count == 0) return null;
    const fraction = random.next();
    const index = if (count == 0) usable[@intFromFloat(fraction * @as(f32, @floatFromInt(usable_count)))] else eligible[@intFromFloat(fraction * @as(f32, @floatFromInt(count)))];
    return routes.nodes[routes.indices[@intCast(links[index][1])].?].position;
}
