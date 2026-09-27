// SPDX-License-Identifier: GPL-2.0-or-later
//! Carried objectives follow the supplied animated player hardpoint.
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const rules = @import("../domain/multiplayer.zig");
const std = @import("std");
const v = @import("../domain/vector.zig");
var skins: [8]c.qhandle_t = @splat(0);
pub fn reset() void {
    skins = @splat(0);
}
pub fn draw(game: *const c.gameState_t, objective: c.entityState_t, entities: []const c.entityState_t, local: i32, now: i32) !void {
    if (objective.dk3Team != 1 and objective.dk3Team != 2) return error.InvalidObjectiveTeam;
    var model = std.mem.zeroes(c.refEntity_t);
    model.hModel = try @import("models.zig").get(game, objective.modelindex);
    if (model.hModel == 0) return error.MissingObjectiveModel;
    model.reType = c.RT_MODEL;
    model.shaderRGBA = @splat(255);
    model.frame = objective.frame;
    model.oldframe = objective.frame;
    var angles = @import("../engine/trajectory.zig").evaluate(objective.apos, now);
    model.origin = @import("../engine/trajectory.zig").evaluate(objective.pos, now);
    if (objective.dk3Carrier > 0) {
        const slot = objective.dk3Carrier - 1;
        if (slot == local) return; // First person must not see its own back attachment.
        var owner: ?c.entityState_t = null;
        for (entities) |entity| if (entity.eType == c.ET_PLAYER and entity.number == slot) {
            owner = entity;
            break;
        };
        const carrier = owner orelse return; // Carrier may be outside this snapshot's PVS.
        var parent = std.mem.zeroes(c.refEntity_t);
        parent.hModel = try @import("models.zig").get(game, carrier.modelindex);
        if (parent.hModel == 0) return error.MissingObjectiveCarrierModel;
        parent.frame = carrier.frame;
        parent.oldframe = carrier.frame;
        parent.origin = @import("../engine/trajectory.zig").evaluate(carrier.pos, now);
        angles = @import("../engine/trajectory.zig").evaluate(carrier.apos, now);
        axes(&parent, angles);
        model.origin = try @import("actor_hardpoints.zig").point(&parent, "ctf_flag");
    }
    axes(&model, angles);
    model.oldorigin = model.origin;
    model.lightingOrigin = model.origin;
    model.renderfx = c.RF_MINLIGHT;
    if (objective.generic1 > 0) {
        if (objective.generic1 > skins.len) return error.InvalidObjectiveColor;
        const index: usize = @intCast(objective.generic1 - 1);
        if (skins[index] == 0) {
            var path: [64]u8 = undefined;
            skins[index] = @intCast(engine.gateway.call(c.CG_R_REGISTERSKIN, .{(try std.fmt.bufPrintZ(&path, "{s}", .{rules.color_skins[index]})).ptr}));
            if (skins[index] == 0) return error.ObjectiveSkinUnavailable;
        }
        model.customSkin = skins[index];
    }
    _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&model});
}
fn axes(model: *c.refEntity_t, angles: v.Vec3) void {
    const basis = v.basis(angles);
    model.axis = .{ basis.forward, v.scale(basis.right, -1), v.cross(basis.forward, v.scale(basis.right, -1)) };
}
