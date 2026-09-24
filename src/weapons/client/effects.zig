// SPDX-License-Identifier: GPL-2.0-or-later
const r = @import("render.zig");
const c = r.c;
const v = r.v;
pub fn Effects(comptime W: type) type {
    return struct {
        const Blast = struct { start: c_int = 0, end: c_int = 0, scale: f32 = 1, alpha: f32 = 1, origin: v.Vec = v.zero };
        var blasts: [64]Blast = @splat(.{});
        var next: usize = 0;
        pub fn reset() void {
            blasts = @splat(.{});
            next = 0;
        }
        pub fn event(cent: *c.centity_t, is_blast: bool) void {
            if (is_blast) {
                var effect: Blast = .{ .start = r.now(), .end = r.now() + 600, .origin = cent.lerpOrigin };
                if (@hasDecl(W, "blastEffect")) W.blastEffect(cent, &effect);
                blasts[next] = effect;
                next = (next + 1) % blasts.len;
                r.worldSound(W.blastSound(cent.currentState.number), cent.lerpOrigin);
            } else {
                const effect: *c.localEntity_t = c.CG_AllocLocalEntity();
                const entity = &effect.refEntity;
                effect.startTime = r.now();
                effect.endTime = r.now() + 100;
                effect.lifeRate = 0.01;
                effect.leType = c.LE_FADE_RGB;
                const color = W.spec.visual.color;
                effect.color = .{ color[0], color[1], color[2], 1 };
                entity.shaderRGBA = .{ r.byte(color[0]), r.byte(color[1]), r.byte(color[2]), 255 };
                entity.reType = c.RT_RAIL_CORE;
                entity.radius = 2;
                entity.customShader = c.trap_R_RegisterShader("dk3/fx/beam");
                entity.origin = cent.currentState.pos.trBase;
                entity.oldorigin = cent.currentState.origin2;
            }
        }
        pub fn frame() void {
            for (blasts) |effect| {
                if (r.now() < effect.start or r.now() >= effect.end) continue;
                const alpha = v.f(effect.end - r.now()) / v.f(@max(1, effect.end - effect.start));
                const period = if (@hasDecl(W, "blast_frame_ms")) W.blast_frame_ms else 70;
                _ = r.sprite(W.spec.visual.impact_sprite, @divTrunc(r.now() - effect.start, period), effect.origin, v.zero, effect.scale, alpha * effect.alpha, W.spec.visual.color, c.DK_SPRITE_ADDITIVE | c.DK_SPRITE_CLAMP);
                r.light(effect.origin, 180 * alpha, W.spec.visual.color);
            }
        }
    };
}
