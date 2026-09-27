// SPDX-License-Identifier: GPL-2.0-or-later
//! Switches, authored patterns and ramps update the bundled renderer's lightstyle blocks.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("../domain/lightstyles.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
pub fn owns(name: []const u8) bool {
    for ([_][]const u8{ "light", "light_spot", "light_strobe", "light_flare", "light_e1", "light_e2", "light_e3", "light_e4" }) |value| if (std.mem.eql(u8, name, value)) return true;
    return false;
}
pub fn initialize(object: data.MapObject, id: u32, now: i64) !policy.Light {
    const kind: policy.Kind = if (std.mem.eql(u8, object.classname, "light")) .light else if (std.mem.eql(u8, object.classname, "light_spot")) .spot else if (std.mem.eql(u8, object.classname, "light_strobe")) .strobe else if (std.mem.eql(u8, object.classname, "light_flare")) .flare else .flame;
    const style = @trunc(try prop.number(object, "style", 0));
    if (style < 0 or style > 255) return error.InvalidLightStyle;
    var state: policy.Light = .{ .kind = kind, .style = @intFromFloat(style), .enabled = kind == .flame or object.flags & 1 == 0, .revision = id, .phase_ms = now };
    state.switchable = kind == .flare or kind == .spot or kind == .strobe or (kind == .light and state.style >= 32);
    if (kind == .light or kind == .spot or kind == .strobe) {
        state.pattern = prop.text(object, "lightstyle") orelse "";
        if (state.pattern.len >= 1024) return error.InvalidLightPattern;
        if (kind == .light and state.style >= 32) {
            state.pattern = "";
            state.level = if (state.enabled) 12 else 0;
        }
    }
    if (kind == .flame) state.model = switch (object.classname[7]) {
        '3' => "models/global/e3_firea.sp2",
        '4' => "models/global/e4_firea.sp2",
        else => "models/global/e2_firea.sp2",
    } else if (kind == .flare or (kind == .light and object.flags & 2 != 0)) state.model = prop.text(object, "model") orelse "models/global/e_flare2.sp2";
    if (prop.text(object, "scale")) |scale| {
        var words = std.mem.tokenizeAny(u8, scale, " \t");
        if (kind == .light) {
            const value = std.fmt.parseFloat(f32, words.next() orelse return error.InvalidLightScale) catch return error.InvalidLightScale;
            state.scale = @splat(value);
        } else {
            for (&state.scale) |*axis| {
                const word = words.next() orelse break;
                axis.* = std.fmt.parseFloat(f32, word) catch return error.InvalidLightScale;
            }
        }
        for (&state.scale) |*axis| {
            if (axis.* == 0) axis.* = 1;
            if (!std.math.isFinite(axis.*) or axis.* < 0 or axis.* > 10000) return error.InvalidLightScale;
        }
    }
    return state;
}
pub fn bind(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity) !void {
    const light = (try world.get(entity, data.WorldControl)).action.light;
    if (light.model.len == 0) return;
    if (light.kind == .flame) try world.put(entity, data.Body{ .mins = @splat(0), .maxs = @splat(0), .contents = c.CONTENTS_TRIGGER });
    try @import("weapon_entities.zig").bind(world, slots, projections, entity, light.model);
    try publish(world, entity, projections);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const light = (try world.get(entity, data.WorldControl)).action.light;
    const binding = world.get(entity, data.Binding) catch return;
    const pose = (try world.get(entity, data.Transform)).*;
    const out = &projections[binding.slot];
    out.state.number = binding.slot;
    out.state.eType = c.ET_GENERAL;
    out.state.generic1 = policy.render_tag;
    out.state.modelindex = binding.model;
    out.state.weapon = @intFromBool(light.kind == .flame);
    out.state.time = @intCast(light.phase_ms);
    out.state.angles2 = light.scale;
    out.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    out.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    out.shared.currentOrigin = pose.position;
    out.shared.ownerNum = c.ENTITYNUM_NONE;
    out.shared.contents = if (light.kind == .flame) c.CONTENTS_TRIGGER else 0;
    out.shared.mins = @splat(0);
    out.shared.maxs = @splat(0);
    // Reference ordinary lights keep their flare when switched off after first use.
    out.shared.svFlags = if (light.enabled or (light.kind == .light and (try world.get(entity, data.WorldControl)).uses != 0)) 0 else c.SVF_NOCLIENT;
    engine.link(out);
}
fn revision(world: *data.World) u64 {
    var latest: u64 = 0;
    var query = world.queryAccess(data.World.mask(.{data.WorldControl}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.WorldControl)) |control| if (control.action == .light) {
        latest = @max(latest, control.action.light.revision);
    };
    return latest + 1;
}
pub fn set(world: *data.World, entity: ecs.Entity, level: u8) !void {
    const next = revision(world);
    const light = &(try world.get(entity, data.WorldControl)).action.light;
    light.level = level;
    light.pattern = "";
    light.revision = next;
}
pub fn use(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const control = try world.get(entity, data.WorldControl);
    const light = &control.action.light;
    if (!light.switchable) return;
    light.enabled = !light.enabled;
    control.uses += 1;
    if (light.kind != .flare) try set(world, entity, if (light.enabled) 12 else 0);
    try publish(world, entity, projections);
}
pub fn styles(world: *data.World, now: i64) void {
    var levels = policy.defaults(now);
    var revisions: [256]u64 = @splat(0);
    {
        var query = world.queryAccess(data.World.mask(.{data.WorldControl}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.read(data.WorldControl)) |control| if (control.action == .light) {
            const light = control.action.light;
            if ((light.pattern.len == 0 and light.level == null) or light.revision < revisions[light.style]) continue;
            levels[light.style] = light.level orelse policy.sample(light.pattern, now - light.phase_ms);
            revisions[light.style] = light.revision;
        };
    }
    // Config publication can synchronously disconnect a client; release readers
    // before handing control back to the engine.
    const text = policy.encode(levels);
    engine.config(c.CS_DK3_LIGHTSTYLES, &text);
}
pub fn ramp(object: data.MapObject) !policy.Ramp {
    const message = prop.text(object, "message") orelse return error.MissingLightRamp;
    if (message.len != 2 or message[0] < 'a' or message[0] > 'z' or message[1] < 'a' or message[1] > 'z' or message[0] == message[1] or object.target.len == 0) return error.InvalidLightRamp;
    var duration = try prop.milliseconds(object, "speed", 1);
    if (duration == 0) duration = 1000;
    if (duration < 0) return error.InvalidLightRamp;
    return .{ .from = message[0] - 'a', .to = message[1] - 'a', .duration_ms = duration, .reverse = object.flags & 1 != 0 };
}
pub fn rampUse(world: *data.World, entity: ecs.Entity, now: i64) !void {
    const state = &(try world.get(entity, data.WorldControl)).action.light_ramp;
    if (state.target == 0) {
        const targets = try @import("names.zig").named(world, (try world.get(entity, data.MapObject)).target);
        if (targets.count == 0) return error.MissingRampTarget;
        const target = world.find(targets.ids[0]).?;
        const control = world.get(target, data.WorldControl) catch return error.InvalidRampTarget;
        if (control.action != .light or control.action.light.kind != .light) return error.InvalidRampTarget;
        state.target = targets.ids[0];
    }
    state.started_ms = now;
    state.next_ms = now + 100;
}
pub fn rampStep(world: *data.World, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.WorldControl)).action.light_ramp;
    if (state.next_ms == null or now < state.next_ms.?) return;
    const target = world.find(state.target) orelse return error.MissingRampTarget;
    try set(world, target, state.sample(now));
    if (now - state.started_ms < state.duration_ms) state.next_ms = now + 100 else {
        state.next_ms = null;
        if (state.reverse) std.mem.swap(u8, &state.from, &state.to);
    }
    (try world.get(entity, data.WorldControl)).action.light_ramp = state;
}
