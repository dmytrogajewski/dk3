// SPDX-License-Identifier: GPL-2.0-or-later
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const policy = @import("actor_catalog").medusa;
pub fn eyes(model: *const c.refEntity_t, ref: *const c.refdef_t) !void {
    const sprites = @import("sprites.zig");
    const sprite = try sprites.register("models/global/e_flgreen.sp2");
    for ([_][*:0]const u8{ "eye1", "eye2" }) |name| sprites.draw(sprite, 0, try @import("actor_hardpoints.zig").point(model, name), 0.75, false, ref);
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &model.origin, engine.floatArg(100), engine.floatArg(-1), engine.floatArg(0.95), engine.floatArg(-1) });
}
pub fn flash(entities: []const c.entityState_t, player: i32, now: i32, display: c.glconfig_t) void {
    var alpha: f32 = 0;
    for (entities) |entity| if (entity.eType == c.ET_GENERAL and entity.time2 == policy.gaze_tag and entity.otherEntityNum == player) {
        if (entity.torsoAnim > now) alpha = 0.35;
    };
    @import("status_visuals.zig").psychic(.{ 0.65, 0.65, 0.65, alpha }, display);
}
