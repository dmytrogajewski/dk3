// SPDX-License-Identifier: GPL-2.0-or-later
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const sprites = @import("sprites.zig");
pub fn draw(game: *const c.gameState_t, entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    if (entity.modelindex <= 0 or entity.modelindex >= c.MAX_MODELS) return;
    const model = try engine.config(game, @intCast(c.CS_MODELS + entity.modelindex));
    const media = try sprites.register(model);
    const origin = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    if (entity.weapon == 0) {
        sprites.drawPlane(media, 0, origin, 1, false, v.scale(ref.viewaxis[1], -entity.angles2[0]), v.scale(ref.viewaxis[2], entity.angles2[1]), @splat(255));
        return;
    }
    const frame: usize = @intCast(@mod(@divFloor(@as(i64, now) - entity.time, 100), @as(i64, sprites.count(media))));
    for (0..2) |plane| {
        const angles = v.add(@import("../engine/trajectory.zig").evaluate(entity.apos, now), .{ 0, if (plane == 0) 0 else 90, 0 });
        const basis = v.basis(angles);
        sprites.drawPlane(media, frame, origin, 1, false, v.scale(basis.right, entity.angles2[0]), v.scale(v.cross(basis.right, basis.forward), entity.angles2[1]), @splat(255));
    }
}
