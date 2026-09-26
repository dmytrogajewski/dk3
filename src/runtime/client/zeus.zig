// SPDX-License-Identifier: GPL-2.0-or-later
//! Finite replicated bolts use deterministic cosmetic segments and class media.
const std = @import("std");
const W = @import("weapon_catalog").zeus;
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t, client: i32) !void {
    if (entity.frame >= 99) return;
    var start = entity.pos.trBase;
    if (entity.angles2[0] == 1) {
        if (entity.otherEntityNum == client) start = v.add(ref.vieworg, v.add(v.scale(ref.viewaxis[0], 8), v.add(v.scale(ref.viewaxis[1], -2.5), .{ 0, 0, -0.5 }))) else start[2] += 21.5;
    }
    const delta = v.subtract(entity.origin2, start);
    const alpha: u8 = if (entity.frame == 2) @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(entity.time2 - now)) / 500, 0, 1) * 153) else 153;
    const direction = v.normalize(delta);
    var right = v.cross(direction, .{ 0, 0, 1 });
    if (v.length(right) < 0.01) right = ref.viewaxis[1] else right = v.normalize(right);
    const up = v.cross(direction, right);
    var random: @import("../domain/components.zig").Random = .{ .state = @as(u32, @bitCast(entity.generic1)) ^ @as(u32, @intCast(@divTrunc(@max(0, now - entity.time), 50))) };
    var previous = start;
    for (1..9) |index| {
        var end = v.add(start, v.scale(delta, @as(f32, @floatFromInt(index)) / 8));
        if (index != 8) end = v.add(end, v.add(v.scale(right, (2 * random.next() - 1) * 8), v.scale(up, (2 * random.next() - 1) * 8)));
        @import("beams.zig").draw("dk3/fx/ion-lightning", previous, end, 4, .{ 64, 115, 217, alpha }, ref);
        previous = end;
    }
    const sprites = @import("sprites.zig");
    const media = try sprites.register(W.visual.flare);
    sprites.drawPlane(media, 0, entity.origin2, 4, true, v.scale(ref.viewaxis[1], -1), ref.viewaxis[2], .{ 255, 255, 255, @intCast(@divTrunc(@as(u16, alpha), 3)) });
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &entity.origin2, engine.floatArg(180), engine.floatArg(0), engine.floatArg(0), engine.floatArg(1) });
}
