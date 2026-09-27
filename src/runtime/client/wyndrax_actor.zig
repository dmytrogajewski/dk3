// SPDX-License-Identifier: GPL-2.0-or-later
//! Authoritative NPC Wisp/bolt projections; no damage is inferred by the client.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const sprites = @import("sprites.zig");
const Random = @import("../domain/components.zig").Random;
var trails: [2048]struct { serial: i32 = -1, next: i64 = 0 } = @splat(.{});
pub fn reset() void {
    trails = @splat(.{});
}
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !bool {
    const point = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    switch (entity.weapon) {
        0 => {
            const sprite = try sprites.register(@import("actor_catalog").wisp.model);
            sprites.drawPlane(sprite, 0, point, entity.origin2[1], false, v.scale(ref.viewaxis[1], -1), ref.viewaxis[2], .{ 255, 255, 255, 255 });
            _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &point, engine.floatArg(175), engine.floatArg(0.35), engine.floatArg(0.35), engine.floatArg(0.75) });
            if (entity.number >= 0 and entity.number < trails.len) {
                const trail = &trails[@intCast(entity.number)];
                const tick = @divTrunc(@as(i64, now) * 60, 1000);
                if (trail.serial != entity.time or trail.next > tick + 1) trail.* = .{ .serial = entity.time, .next = tick };
                trail.next = @max(trail.next, tick - 5);
                while (trail.next <= tick) : (trail.next += 1) {
                    const at: i32 = @intCast(@divTrunc(trail.next * 1000, 60));
                    var random: Random = .{ .state = @as(u32, @bitCast(at)) ^ (@as(u32, @intCast(entity.number)) *% 2654435761) };
                    @import("fx_particles.zig").cloud(point, v.normalize(.{ 1, 1, -1 }), .{ 0.25, 0.15, 0.75 }, .{ 0.85, 0.45, 0.25 }, 0.75, 1, 7, 100, @splat(0), 2, .spark, at, &random);
                }
            }
            _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &point, engine.floatArg(100), engine.floatArg(0.5), engine.floatArg(0.75), engine.floatArg(1) });
            return false;
        },
        1 => return true,
        2 => {
            if (now < entity.time2) {
                const delta = v.subtract(entity.origin2, point);
                const forward = v.normalize(delta);
                var side = v.cross(forward, .{ 0, 0, 1 });
                if (v.length(side) < 0.01) side = .{ 1, 0, 0 };
                side = v.normalize(side);
                const up = v.cross(side, forward);
                var random: Random = .{ .state = @as(u32, @bitCast(entity.time)) ^ (@as(u32, @intCast(entity.number)) *% 2654435761) ^ @as(u32, @bitCast(@divTrunc(now, 50))) };
                const count: usize = @intFromFloat(std.math.clamp(@ceil(v.length(delta) / 32), 1, 256));
                var previous = point;
                var color: [4]u8 = .{ 0, 0, 0, 153 };
                for (entity.angles2, color[0..3]) |axis, *channel| channel.* = @intFromFloat(std.math.clamp(axis, 0, 1) * 255);
                for (1..count + 1) |i| {
                    var next = v.add(point, v.scale(delta, @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count))));
                    if (i < count) next = v.add(next, v.add(v.scale(side, (random.next() * 2 - 1) * 9), v.scale(up, (random.next() * 2 - 1) * 9)));
                    @import("beams.zig").draw("dk3/fx/ion-lightning", previous, next, @as(f32, @floatFromInt(entity.frame)) * 0.5, color, ref);
                    previous = next;
                }
            }
            if (now < entity.legsAnim) sprites.draw(try sprites.register("models/global/e_flblue.sp2"), 0, entity.angles, @as(f32, @floatFromInt(entity.torsoAnim)) * 0.01, true, ref);
            return true;
        },
        else => return error.InvalidWyndraxProjection,
    }
}
