// SPDX-License-Identifier: GPL-2.0-or-later
//! Bounded cosmetic pools overwrite their oldest entry. Gameplay events are authoritative.
const std = @import("std");
const catalog = @import("weapon_catalog");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const marks = @import("../engine/marks.zig");
const Random = @import("../domain/components.zig").Random;
const Mark = struct { polygon: marks.Polygon = .{}, shader: c.qhandle_t = 0, at: i64 = 0, origin: v.Vec3 = @splat(0), normal: v.Vec3 = @splat(0) };
const Particle = struct { shader: c.qhandle_t = 0, origin: v.Vec3 = @splat(0), velocity: v.Vec3 = @splat(0), color: [3]f32 = @splat(1), at: i64 = 0, radius: f32 = 2 };
const Light = struct { origin: v.Vec3 = @splat(0), color: [3]f32 = @splat(1), radius: f32 = 0, at: i64 = 0, duration: u16 = 1 };
var seen: [c.MAX_GENTITIES]u32 = @splat(0);
var decals: [128]Mark = @splat(.{});
var particles: [256]Particle = @splat(.{});
var lights: [32]Light = @splat(.{});
var next_mark: usize = 0;
var next_particle: usize = 0;
var next_light: usize = 0;
pub fn reset() void {
    @memset(&seen, 0);
    @memset(&decals, .{});
    @memset(&particles, .{});
    @memset(&lights, .{});
    next_mark = 0;
    next_particle = 0;
    next_light = 0;
}
pub fn consume(entity: c.entityState_t) !void {
    if (entity.number < 0 or entity.number >= seen.len or entity.weapon <= 0 or entity.weapon > 28 or entity.eventParm < 0 or entity.eventParm > @intFromEnum(catalog.impact_rules.Kind.wood)) return error.InvalidImpactEvent;
    for (entity.pos.trBase ++ entity.origin2) |coordinate| if (!std.math.isFinite(coordinate)) return error.InvalidImpactPosition;
    const slot: usize = @intCast(entity.number);
    const serial: u32 = @bitCast(entity.time2);
    if (serial == 0 or seen[slot] == serial) return;
    seen[slot] = serial;
    const kind: catalog.impact_rules.Kind = @enumFromInt(entity.eventParm);
    const cue = catalog.impact(@intCast(entity.weapon), .{ .kind = kind, .serial = serial, .charged = entity.frame != 0 });
    if (cue.sound) |name| {
        var buffer: [c.MAX_QPATH + 8]u8 = undefined;
        const path = try std.fmt.bufPrintZ(&buffer, "sounds/{s}", .{name});
        const sound = engine.gateway.call(c.CG_S_REGISTERSOUND, .{ path.ptr, @as(isize, 0) });
        if (sound != 0) _ = engine.gateway.call(c.CG_S_STARTSOUND, .{ &entity.pos.trBase, @as(isize, entity.number), @as(isize, c.CHAN_AUTO), sound });
    }
    const normal = v.normalize(entity.origin2);
    var mark_count: usize = 0;
    if (cue.mark) |name| if (v.length(normal) > 0.5) {
        const shader: c.qhandle_t = @intCast(engine.gateway.call(c.CG_R_REGISTERSHADER, .{name.ptr}));
        // Repeated stationary shots must not stack the texture's faint alpha fringe
        // until its rectangular footprint becomes opaque.
        for (&decals) |*mark| if (mark.shader == shader and v.dot(mark.normal, normal) > 0.95 and v.length(v.subtract(mark.origin, entity.pos.trBase)) < cue.radius * 0.5) {
            mark.shader = 0;
        };
        const angle = @as(f32, @floatFromInt((serial *% 137) % 360)) * (std.math.pi / 180.0);
        const projected = try marks.project(entity.pos.trBase, normal, cue.radius, angle);
        for (projected.polygons[0..projected.count]) |polygon| {
            decals[next_mark] = .{ .polygon = polygon, .shader = shader, .at = entity.time, .origin = entity.pos.trBase, .normal = normal };
            next_mark = (next_mark + 1) % decals.len;
        }
        mark_count = projected.count;
    };
    if (cue.particles > 0) {
        const shader: c.qhandle_t = @intCast(engine.gateway.call(c.CG_R_REGISTERSHADER, .{cue.particle_shader.ptr}));
        var random: Random = .{ .state = serial ^ 0x496d7061 };
        for (0..cue.particles) |_| {
            const direction = v.normalize(v.add(normal, .{ random.next() * 2 - 1, random.next() * 2 - 1, random.next() * 2 - 1 }));
            particles[next_particle] = .{ .shader = shader, .origin = v.add(entity.pos.trBase, v.scale(normal, 1)), .velocity = v.scale(direction, 35 + random.next() * 65), .color = cue.color, .at = entity.time, .radius = if (kind == .flesh) 3 else 2 };
            next_particle = (next_particle + 1) % particles.len;
        }
    }
    if (cue.light_radius > 0) {
        lights[next_light] = .{ .origin = v.add(entity.pos.trBase, v.scale(normal, 4)), .color = cue.color, .radius = cue.light_radius, .at = entity.time, .duration = cue.light_ms };
        next_light = (next_light + 1) % lights.len;
    }
    if (engine.integer("developer") > 0) {
        var message: [256]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig impact: weapon={d} kind={s} sound={s} marks={d} particles={d}\n", .{ entity.weapon, @tagName(kind), cue.sound orelse "none", mark_count, cue.particles }));
    }
}
pub fn draw(now: i64) void {
    for (&decals) |*mark| {
        const age = now - mark.at;
        if (mark.shader == 0 or age < 0 or age >= 10000) continue;
        const alpha: u8 = @intCast(@min(255, @divTrunc((10000 - age) * 255, 1000)));
        for (mark.polygon.vertices[0..mark.polygon.count]) |*vertex| vertex.modulate[3] = alpha;
        _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ @as(isize, mark.shader), @as(isize, mark.polygon.count), &mark.polygon.vertices });
    }
    for (particles) |particle| {
        const age = now - particle.at;
        if (particle.shader == 0 or age < 0 or age >= 450) continue;
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
        const fade = 1 - @as(f32, @floatFromInt(age)) / @as(f32, @floatFromInt(light.duration));
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &light.origin, engine.floatArg(light.radius * fade), engine.floatArg(light.color[0]), engine.floatArg(light.color[1]), engine.floatArg(light.color[2]) });
    }
}
