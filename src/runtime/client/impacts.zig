// SPDX-License-Identifier: GPL-2.0-or-later
//! Bounded cosmetic pools overwrite their oldest entry. Gameplay events are authoritative.
const std = @import("std");
const catalog = @import("weapon_catalog");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const marks = @import("../engine/marks.zig");
const Random = @import("../domain/components.zig").Random;
const sprites = @import("sprites.zig");
const Sprite = struct { presentation: engine.Presentation = .{}, media: ?u8 = null, origin: v.Vec3 = @splat(0), scale: f32 = 1, rate: u8 = 20, at: i64 = 0, normal: ?v.Vec3 = null, additive: bool = true, alpha: u8 = 255, fade: bool = false };
const Mark = struct { presentation: engine.Presentation = .{}, polygon: marks.Polygon = .{}, shader: c.qhandle_t = 0, at: i64 = 0, origin: v.Vec3 = @splat(0), normal: v.Vec3 = @splat(0) };
const Particle = struct { presentation: engine.Presentation = .{}, shader: c.qhandle_t = 0, origin: v.Vec3 = @splat(0), velocity: v.Vec3 = @splat(0), color: [3]f32 = @splat(1), at: i64 = 0, radius: f32 = 2 };
const Light = struct { presentation: engine.Presentation = .{}, origin: v.Vec3 = @splat(0), color: [3]f32 = @splat(1), radius: f32 = 0, at: i64 = 0, duration: u16 = 1 };
var seen: [c.MAX_GENTITIES]u128 = @splat(0);
var decals: [128]Mark = @splat(.{});
var particles: [256]Particle = @splat(.{});
var lights: [32]Light = @splat(.{});
var next_mark: usize = 0;
var next_particle: usize = 0;
var next_light: usize = 0;
var animations: [64]Sprite = @splat(.{});
var next_animation: usize = 0;
pub fn reset() void {
    sprites.reset();
    @memset(&animations, .{});
    next_animation = 0;
    @memset(&seen, 0);
    @memset(&decals, .{});
    @memset(&particles, .{});
    @memset(&lights, .{});
    next_mark = 0;
    next_particle = 0;
    next_light = 0;
}
pub fn consume(entity: c.entityState_t) !void {
    const authored_scorch = entity.weapon == 0 and entity.generic1 == @import("../domain/lightning.zig").scorch_tag;
    if (entity.number < 0 or entity.number >= seen.len or (!authored_scorch and (entity.weapon <= 0 or entity.weapon > 28)) or entity.eventParm < 0 or entity.eventParm > @intFromEnum(catalog.impact_rules.Kind.wood)) return error.InvalidImpactEvent;
    for (entity.pos.trBase ++ entity.origin2) |coordinate| if (!std.math.isFinite(coordinate)) return error.InvalidImpactPosition;
    const slot: usize = @intCast(entity.number);
    const serial: u32 = @bitCast(entity.time2);
    const key = @as(u128, @as(u32, @bitCast(entity.dk3World))) << 64 | @as(u128, @as(u32, @bitCast(entity.dk3Identity))) << 32 | serial;
    if (serial == 0 or seen[slot] == key) return;
    seen[slot] = key;
    if (authored_scorch) {
        var random: Random = .{ .state = serial };
        const dimensions = sprites.extent(try sprites.register("models/global/we_scorch.sp2"), 0);
        const scale = @abs((random.next() * 2 - 1) * 0.8 + 0.3);
        _ = try decal(entity.pos.trBase, v.normalize(entity.origin2), @max(dimensions[0], dimensions[1]) * scale * 0.5, "models/global/we_scorch.sp2/0@mark", random.next() * 2 * std.math.pi, entity.time);
        return;
    }
    const kind: catalog.impact_rules.Kind = @enumFromInt(entity.eventParm);
    var cue = catalog.impact(@intCast(entity.weapon), .{ .kind = kind, .serial = serial, .charged = entity.frame & 1 != 0, .detonation = entity.frame & 2 != 0, .sequence = entity.generic1, .trail = entity.frame & 4 != 0 });
    if (entity.frame & 8 != 0 and std.mem.indexOf(u8, cue.particle_shader, "blood") != null) cue.particles = 0;
    if (cue.sound) |name| {
        const sound = try engine.registerSound(name);
        if (sound != 0) _ = engine.gateway.call(c.CG_S_STARTSOUND, .{ &entity.pos.trBase, @as(isize, entity.number), @as(isize, c.CHAN_AUTO), @as(isize, sound) });
    }
    const normal = v.normalize(entity.origin2);
    if (cue.sprite) |name| {
        animations[next_animation] = .{ .presentation = engine.Presentation.current(), .media = try sprites.register(name), .origin = v.add(entity.pos.trBase, v.scale(normal, 2)), .scale = cue.sprite_scale, .rate = cue.sprite_rate, .at = entity.time, .normal = if (cue.oriented) normal else null, .additive = cue.additive, .alpha = cue.alpha, .fade = cue.fade };
        next_animation = (next_animation + 1) % animations.len;
    }
    var mark_count: usize = 0;
    if (cue.mark) |name| if (v.length(normal) > 0.5) {
        const angle = (cue.angle_degrees orelse @as(f32, @floatFromInt((serial *% 137) % 360))) * (std.math.pi / 180.0);
        mark_count = try decal(entity.pos.trBase, normal, cue.radius, name, angle, entity.time);
    };
    if (cue.particles > 0) {
        const shader: c.qhandle_t = @intCast(engine.gateway.call(c.CG_R_REGISTERSHADER, .{cue.particle_shader.ptr}));
        var random: Random = .{ .state = serial ^ 0x496d7061 };
        for (0..cue.particles) |_| {
            const direction = v.normalize(v.add(normal, .{ random.next() * 2 - 1, random.next() * 2 - 1, random.next() * 2 - 1 }));
            particles[next_particle] = .{ .presentation = engine.Presentation.current(), .shader = shader, .origin = v.add(entity.pos.trBase, v.scale(normal, 1)), .velocity = v.scale(direction, 35 + random.next() * 65), .color = cue.color, .at = entity.time, .radius = if (kind == .flesh) 3 else 2 };
            next_particle = (next_particle + 1) % particles.len;
        }
    }
    if (cue.light_radius > 0) {
        lights[next_light] = .{ .presentation = engine.Presentation.current(), .origin = v.add(entity.pos.trBase, v.scale(normal, 4)), .color = cue.color, .radius = cue.light_radius, .at = entity.time, .duration = cue.light_ms };
        next_light = (next_light + 1) % lights.len;
    }
    if (engine.integer("developer") > 0) {
        var message: [256]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig impact: weapon={d} kind={s} sound={s} marks={d} particles={d}\n", .{ entity.weapon, @tagName(kind), cue.sound orelse "none", mark_count, cue.particles }));
    }
}
pub fn draw(now: i64, ref: *const c.refdef_t) void {
    for (animations) |animation| if (animation.media) |index| {
        const age = now - animation.at;
        if (age < 0) continue;
        const frame: usize = @intCast(@divTrunc(age * animation.rate, 1000));
        const duration = @divTrunc(@as(i64, sprites.count(index)) * 1000, animation.rate);
        if (age >= duration) continue;
        const scope = animation.presentation.select();
        defer scope.deinit();
        const alpha: u8 = if (animation.fade) @intCast(@divTrunc((duration - age) * animation.alpha, duration)) else animation.alpha;
        var right = v.scale(ref.viewaxis[1], -1);
        var up = ref.viewaxis[2];
        if (animation.normal) |normal| {
            const perpendicular = v.cross(normal, .{ 0, 0, 1 });
            right = if (v.length(perpendicular) > 0.01) v.normalize(perpendicular) else .{ 1, 0, 0 };
            up = v.cross(right, normal);
        }
        sprites.drawPlane(index, frame, animation.origin, animation.scale, animation.additive, right, up, .{ 255, 255, 255, alpha });
    };
    for (&decals) |*mark| {
        const age = now - mark.at;
        if (mark.shader == 0 or age < 0 or age >= 10000) continue;
        const scope = mark.presentation.select();
        defer scope.deinit();
        const alpha: u8 = @intCast(@min(255, @divTrunc((10000 - age) * 255, 1000)));
        for (mark.polygon.vertices[0..mark.polygon.count]) |*vertex| vertex.modulate[3] = alpha;
        _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ @as(isize, mark.shader), @as(isize, mark.polygon.count), &mark.polygon.vertices });
    }
    for (particles) |particle| {
        const age = now - particle.at;
        if (particle.shader == 0 or age < 0 or age >= 450) continue;
        const scope = particle.presentation.select();
        defer scope.deinit();
        const seconds = @as(f32, @floatFromInt(age)) * 0.001;
        var rendered = std.mem.zeroes(c.refEntity_t);
        rendered.reType = c.RT_SPRITE;
        rendered.customShader = particle.shader;
        rendered.origin = v.add(v.add(particle.origin, v.scale(particle.velocity, seconds)), .{ 0, 0, -120 * seconds * seconds });
        rendered.radius = particle.radius;
        for (particle.color, 0..) |color, i| rendered.shaderRGBA[i] = @intFromFloat(color * 255);
        rendered.shaderRGBA[3] = @intCast(@divTrunc((450 - age) * 255, 450));
        _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&rendered});
    }
    for (lights) |light| {
        const age = now - light.at;
        if (light.radius <= 0 or age < 0 or age >= light.duration) continue;
        const scope = light.presentation.select();
        defer scope.deinit();
        const fade = 1 - @as(f32, @floatFromInt(age)) / @as(f32, @floatFromInt(light.duration));
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &light.origin, engine.floatArg(light.radius * fade), engine.floatArg(light.color[0]), engine.floatArg(light.color[1]), engine.floatArg(light.color[2]) });
    }
}

/// Actor effects use the same bounded decal lifetime and overlap policy as weapons.
pub fn decal(origin: v.Vec3, normal: v.Vec3, radius: f32, name: [:0]const u8, angle: f32, now: i64) !usize {
    const shader: c.qhandle_t = @intCast(engine.gateway.call(c.CG_R_REGISTERSHADER, .{name.ptr}));
    for (&decals) |*mark| if (mark.presentation.network == engine.entity_world and mark.shader == shader and v.dot(mark.normal, normal) > 0.95 and v.length(v.subtract(mark.origin, origin)) < radius * 0.5) {
        mark.shader = 0;
    };
    const projected = try marks.project(origin, normal, radius, angle);
    for (projected.polygons[0..projected.count]) |polygon| {
        decals[next_mark] = .{ .presentation = engine.Presentation.current(), .polygon = polygon, .shader = shader, .at = now, .origin = origin, .normal = normal };
        next_mark = (next_mark + 1) % decals.len;
    }
    return projected.count;
}
