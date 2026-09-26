// SPDX-License-Identifier: GPL-2.0-or-later
//! Persistent flame presentation reconstructed from replicated birth/count/identity.
const std = @import("std");
const W = @import("weapon_catalog").sunflare;
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const sprites = @import("sprites.zig");
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    _ = ref;
    if (entity.frame < 2) return;
    const count: u8 = @intFromFloat(std.math.clamp(entity.angles2[0], 5, 9));
    const radius = (W.BallisticState{ .flames = count }).visualRadius();
    const age = @max(0, now - entity.time);
    const appearance = W.appearance(age);
    if (appearance.alpha < 0.05) return;
    const alpha: u8 = @intFromFloat(255 * appearance.alpha);
    const flame = try sprites.register(W.visual.fire);
    const glow = try sprites.register(W.visual.glow);
    var random: @import("../domain/components.zig").Random = .{ .state = @bitCast(entity.generic1) };
    for (0..count + 1) |i| {
        const angle = random.next() * 2 * std.math.pi;
        const distance = if (i == count) 0 else radius * @sqrt(random.next());
        const origin = v.add(entity.pos.trBase, .{ @cos(angle) * distance, @sin(angle) * distance, 0 });
        const ground = try engine.collisionService().trace(.{ .start = v.add(origin, .{ 0, 0, 50 }), .end = v.add(origin, .{ 0, 0, -100 }), .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = c.MASK_SOLID });
        const position = if (entity.origin2[0] == 0 and i != count and ground.fraction < 1 and !ground.start_solid) v.add(ground.end, .{ 0, 0, 0.2 }) else origin;
        const frame = (@as(usize, @intCast(@divTrunc(age, 50))) + i * 3) % sprites.count(flame);
        const scale = appearance.scale * (if (i == count) @as(f32, 2.5) else 1);
        for ([_]f32{ angle, angle + std.math.pi / 2.0 }) |yaw| sprites.drawPlane(flame, frame, position, scale, true, .{ @cos(yaw), @sin(yaw), 0 }, .{ 0, 0, 1 }, .{ 255, 255, 255, alpha });
        if (entity.origin2[0] == 0 and i != count) sprites.drawPlane(glow, 0, position, 1.5 * appearance.scale, true, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 255, 255, 255, @intFromFloat(255 * @min(1, appearance.alpha + 0.2)) });
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &position, engine.floatArg(150), engine.floatArg(0.8), engine.floatArg(0.4), engine.floatArg(0.2) });
    }
}
