// SPDX-License-Identifier: GPL-2.0-or-later
//! The meteor's replicated scale and launch position also drive its flare/portal.
const std = @import("std");
const W = @import("weapon_catalog").stavros;
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const sprites = @import("sprites.zig");
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    const fragment = entity.generic1 & 8 != 0;
    const origin = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    const glow = try sprites.register(W.visual.glow);
    sprites.draw(glow, 0, origin, if (fragment) entity.angles2[0] * 0.78 else 2.75, true, ref);
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &origin, engine.floatArg(if (fragment) @as(f32, 200) else 300), engine.floatArg(if (fragment) @as(f32, 0.85) else 0.55), engine.floatArg(0.35), engine.floatArg(0.15) });
    const age = now - entity.time;
    if (fragment or age < 0 or age >= 900) return;
    const tick: f32 = @floatFromInt(@divTrunc(age, 100));
    const scale = if (tick <= 2) 0.1 + tick * 0.35 else @max(0.1, 0.8 - (tick - 2) * 0.07);
    const angle = tick * 15 * (std.math.pi / 180.0);
    const right = v.add(v.scale(ref.viewaxis[1], -@cos(angle)), v.scale(ref.viewaxis[2], @sin(angle)));
    const up = v.add(v.scale(ref.viewaxis[1], @sin(angle)), v.scale(ref.viewaxis[2], @cos(angle)));
    const portal = try sprites.register(W.visual.portal);
    sprites.drawPlane(portal, @min(10, sprites.count(portal) - 1), entity.origin2, scale, true, right, up, .{ 255, 255, 255, 191 });
}
