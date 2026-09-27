// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
pub fn draw(game: *const c.gameState_t, entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    if (entity.frame != 0) return @import("actor_lasers.zig").sparks(entity, now, .{ 230, 153, 26 }, 30);
    const origin = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    const basis = v.basis(@import("../engine/trajectory.zig").evaluate(entity.apos, now));
    var model = std.mem.zeroes(c.refEntity_t);
    model.reType = c.RT_MODEL;
    model.hModel = try @import("models.zig").get(game, entity.modelindex);
    model.origin = origin;
    model.oldorigin = origin;
    model.axis = .{ v.scale(basis.forward, 3), v.scale(basis.right, -1.5), v.scale(v.cross(basis.right, basis.forward), 1.5) };
    model.nonNormalizedAxes = c.qtrue;
    model.renderfx = c.RF_MINLIGHT | c.RF_NOSHADOW;
    model.shaderRGBA = .{ 255, 255, 255, 179 };
    _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&model});
    const sprites = @import("sprites.zig");
    sprites.draw(try sprites.register(@import("actor_catalog").deathsphere.bolt_flare), 0, origin, 0.85, true, ref);
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &origin, engine.floatArg(150), engine.floatArg(0.8), engine.floatArg(0.7), engine.floatArg(0.2) });
}
