// SPDX-License-Identifier: GPL-2.0-or-later
//! Snapshot effect dispatch, separate from first-person animation and simulation.
const std = @import("std");
const catalog = @import("weapon_catalog");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t, client: i32) !void {
    if (entity.weapon == catalog.novabeam.id) {
        if (entity.frame != 1) return;
        const visual = catalog.novabeam.visual;
        var start = entity.pos.trBase;
        if (entity.otherEntityNum == client) {
            const offset = catalog.novabeam.muzzle;
            start = v.add(ref.vieworg, v.add(v.scale(ref.viewaxis[0], offset[1]), v.add(v.scale(ref.viewaxis[1], -offset[0]), .{ 0, 0, offset[2] - 22 })));
        }
        const alpha: u8 = @intFromFloat(std.math.clamp(entity.angles2[0], 0, 1) * 255);
        @import("beams.zig").draw("dk3/fx/novabeam", start, entity.origin2, 4, .{ 255, 255, 255, alpha }, ref);
        const sprites = @import("sprites.zig");
        sprites.draw(try sprites.register(visual.muzzle), 0, start, 0.25, true, ref);
        sprites.draw(try sprites.register(visual.flare), 0, entity.origin2, 0.3, true, ref);
        for ([_]v.Vec3{ start, entity.origin2 }, [_]f32{ 200, 150 }) |position, radius| _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &position, engine.floatArg(radius), engine.floatArg(0.8), engine.floatArg(0.4), engine.floatArg(0.2) });
    } else if (entity.weapon == catalog.flashlight.id) {
        const W = catalog.flashlight;
        const origin = if (entity.otherEntityNum == client) ref.vieworg else entity.pos.trBase;
        const angles = entity.apos.trBase;
        const strength = std.math.clamp(entity.angles2[0], 0, 1);
        for (W.rays) |offset| {
            const direction = v.basis(v.add(angles, .{ offset[0], offset[1], 0 })).forward;
            const hit = try engine.collisionService().trace(.{ .start = origin, .end = v.add(origin, v.scale(direction, 2000)), .mins = @splat(0), .maxs = @splat(0), .slot = @intCast(entity.otherEntityNum), .mask = c.MASK_SHOT });
            if (hit.sky or hit.fraction == 1) continue;
            const distance = v.length(v.subtract(hit.end, origin));
            const position = v.add(hit.end, v.scale(hit.normal, 2));
            const brightness = W.brightness(distance, strength);
            _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &position, engine.floatArg(W.radius(distance, strength)), engine.floatArg(brightness), engine.floatArg(brightness), engine.floatArg(brightness) });
        }
    } else try @import("area_effects.zig").draw(entity, now);
}
