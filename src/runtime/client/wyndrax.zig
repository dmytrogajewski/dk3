// SPDX-License-Identifier: GPL-2.0-or-later
//! Wisp glow and retained target links are presentation of authoritative snapshots.
const std = @import("std");
const W = @import("weapon_catalog").wyndrax;
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const sprites = @import("sprites.zig");
pub fn draw(entity: c.entityState_t, snapshot: []const c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    const origin = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    const alpha: u8 = @intFromFloat(std.math.clamp(entity.origin2[2], 0, 1) * 255);
    const flare = try sprites.register(W.flare);
    sprites.drawPlane(flare, 0, origin, 0.75, true, v.scale(ref.viewaxis[1], -1), ref.viewaxis[2], .{ 64, 115, 217, @intCast(@as(u16, alpha) * 3 / 5) });
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &origin, engine.floatArg(120 * entity.origin2[2]), engine.floatArg(0.25), engine.floatArg(0.45), engine.floatArg(0.85) });
    const targets = [_]i32{ entity.otherEntityNum, entity.otherEntityNum2, @intFromFloat(entity.origin2[0]), @intFromFloat(entity.origin2[1]) };
    for (targets) |slot| {
        if (slot == c.ENTITYNUM_NONE) continue;
        for (snapshot) |target| if (target.number == slot) {
            const end = @import("../engine/trajectory.zig").evaluate(target.pos, now);
            @import("beams.zig").draw("dk3/fx/ion-lightning", origin, end, 6, .{ 64, 115, 217, @intCast(@as(u16, alpha) * 3 / 5) }, ref);
            break;
        };
    }
}
