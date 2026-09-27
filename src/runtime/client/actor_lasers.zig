// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    const origin = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    if (entity.frame == 0) {
        const sprites = @import("sprites.zig");
        const media = try sprites.register(@import("actor_catalog").laser.sprite);
        sprites.drawPlane(media, 0, origin, 0.3, false, v.scale(ref.viewaxis[1], -1), ref.viewaxis[2], .{ 255, 255, 255, 179 });
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &origin, engine.floatArg(165), engine.floatArg(0.75), engine.floatArg(0.35), engine.floatArg(0.35) });
        return;
    }
    const age = @as(f32, @floatFromInt(now - entity.time)) * 0.001;
    if (age < 0 or age >= 0.8) return;
    const shader = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/actor-laser-spark")});
    var random: @import("../domain/components.zig").Random = .{ .state = @bitCast(entity.time2) };
    for (0..100) |_| {
        var point = v.add(origin, v.scale(entity.origin2, @floor(random.next() * 8)));
        for (&point) |*value| value.* += @floor(random.next() * 4) - 2;
        const velocity: v.Vec3 = .{ (random.next() * 2 - 1) * 20, (random.next() * 2 - 1) * 20, 0 };
        const alpha = @max(0, 1 + age * (-2 + random.next() * 0.75));
        var particle = std.mem.zeroes(c.refEntity_t);
        particle.reType = c.RT_SPRITE;
        particle.customShader = @intCast(shader);
        particle.origin = v.add(v.add(point, v.scale(velocity, age)), .{ 0, 0, -50 * age * age });
        particle.radius = 1.5;
        particle.shaderRGBA = .{ 128, 128, 255, @intFromFloat(alpha * 255) };
        _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&particle});
    }
}
