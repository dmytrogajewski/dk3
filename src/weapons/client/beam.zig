// SPDX-License-Identifier: GPL-2.0-or-later
const r = @import("render.zig");
const c = r.c;
const v = r.v;
pub const Style = struct { color: v.Vec, core: v.Vec, flare: [:0]const u8, flare_scale: f32, muzzle: bool = false };
pub fn draw(cent: *c.centity_t, style: Style) void {
    const alpha = @max(0, @min(1, cent.currentState.dk3Alpha));
    var start = cent.lerpOrigin;
    if (style.muzzle and cent.currentState.otherEntityNum == c.cg.clientNum and c.cg.renderingThirdPerson == 0) {
        const view = @import("view.zig");
        const offset = if (view.muzzle_weapon == cent.currentState.weapon) view.muzzle_offset else v.Vec{ 14, -6, -6 };
        start = v.madd(v.madd(v.madd(c.cg.refdef.vieworg, offset[0], c.cg.refdef.viewaxis[0]), offset[1], c.cg.refdef.viewaxis[1]), offset[2], c.cg.refdef.viewaxis[2]);
    }
    const shader = c.trap_R_RegisterShader("dk3/fx/beam");
    r.strip(start, cent.currentState.origin2, 8, style.color, 0.35 * alpha, shader);
    r.strip(start, cent.currentState.origin2, 3, style.core, alpha, shader);
    if (style.muzzle) {
        _ = r.sprite("models/e4/we_mfnbeam.sp2", @divTrunc(r.now(), 50), start, v.zero, 0.25, alpha, style.color, c.DK_SPRITE_ADDITIVE);
        r.light(start, 200 * alpha, .{ 0.8, 0.4, 0.2 });
    }
    _ = r.sprite(style.flare, @divTrunc(r.now(), 50), cent.currentState.origin2, v.zero, style.flare_scale, alpha, style.color, c.DK_SPRITE_ADDITIVE);
    r.light(cent.currentState.origin2, 150 * alpha, style.color);
}
