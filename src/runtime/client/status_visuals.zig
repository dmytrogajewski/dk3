// SPDX-License-Identifier: GPL-2.0-or-later
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
pub fn frost(model: c.refEntity_t, strength: f32) !void {
    var overlay = model;
    overlay.customShader = @intCast(engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/freeze")}));
    overlay.shaderRGBA = .{ @intFromFloat(30 * strength), @intFromFloat(60 * strength), @intFromFloat(110 * strength), 255 };
    _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&overlay});
}
pub fn screen(state: @import("../domain/components.zig").Ailments, display: c.glconfig_t) void {
    if (state.mask & 5 == 0) return;
    const color: [4]f32 = if (state.freeze_level > 0) .{ 0.2, 0.3, 1, state.freeze_level * 0.15 } else .{ 0.1, 0.65, 0.1, 0.08 };
    const white = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "white")});
    _ = engine.gateway.call(c.CG_R_SETCOLOR, .{&color});
    _ = engine.gateway.call(c.CG_R_DRAWSTRETCHPIC, .{ engine.floatArg(0), engine.floatArg(0), engine.floatArg(@floatFromInt(display.vidWidth)), engine.floatArg(@floatFromInt(display.vidHeight)), engine.floatArg(0), engine.floatArg(0), engine.floatArg(1), engine.floatArg(1), white });
    _ = engine.gateway.call(c.CG_R_SETCOLOR, .{@as(?*const [4]f32, null)});
}

pub fn psychic(color: [4]f32, display: c.glconfig_t) void {
    if (color[3] <= 0) return;
    const white = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "white")});
    _ = engine.gateway.call(c.CG_R_SETCOLOR, .{&color});
    _ = engine.gateway.call(c.CG_R_DRAWSTRETCHPIC, .{ engine.floatArg(0), engine.floatArg(0), engine.floatArg(@floatFromInt(display.vidWidth)), engine.floatArg(@floatFromInt(display.vidHeight)), engine.floatArg(0), engine.floatArg(0), engine.floatArg(1), engine.floatArg(1), white });
    _ = engine.gateway.call(c.CG_R_SETCOLOR, .{@as(?*const [4]f32, null)});
}
