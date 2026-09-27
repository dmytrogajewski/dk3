// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const sprites = @import("sprites.zig");
const Random = @import("../domain/components.zig").Random;
const Spark = struct { point: v.Vec3, clockwise: bool, speed: f32 = 250, scale: u8, alive: bool = true };
const Burst = struct { entity: i32 = -1, serial: i32 = -1, next_ms: i32 = 0, sparks: [128]Spark = undefined, marked: bool = false };
var bursts: [32]Burst = @splat(.{});
var cursor: usize = 0;
pub fn reset() void {
    bursts = @splat(.{});
    cursor = 0;
}
fn burst(entity: c.entityState_t) *Burst {
    for (&bursts) |*value| if (value.entity == entity.number and value.serial == entity.time) return value;
    const result = &bursts[cursor];
    cursor = (cursor + 1) % bursts.len;
    result.* = .{ .entity = entity.number, .serial = entity.time, .next_ms = entity.time2 };
    var random: Random = .{ .state = @as(u32, @bitCast(entity.time)) ^ @as(u32, @intCast(entity.number)) *% 2654435761 };
    for (&result.sparks) |*spark| spark.* = .{ .point = v.add(entity.pos.trBase, .{ -100 + @floor(random.next() * 200), -100 + @floor(random.next() * 200), -128 + @floor(random.next() * 328) }), .clockwise = random.next() >= 0.5, .scale = @intFromFloat(random.next() * 180) };
    return result;
}
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    const point = entity.pos.trBase;
    var model = std.mem.zeroes(c.refEntity_t);
    model.reType = c.RT_MODEL;
    model.hModel = try @import("models.zig").register(@import("actor_catalog").nharre.reaper_model);
    model.origin = point;
    model.oldorigin = point;
    const axes = v.basis(entity.apos.trBase);
    const scale: f32 = if (entity.weapon == 0) 0.001 else 1;
    model.axis = .{ v.scale(axes.forward, scale), v.scale(axes.right, -scale), v.scale(v.cross(axes.right, axes.forward), scale) };
    model.nonNormalizedAxes = c.qtrue;
    model.frame = entity.frame;
    model.oldframe = model.frame;
    model.shaderRGBA = @splat(255);
    _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&model});
    if (entity.weapon == 0) {
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &point, engine.floatArg(300), engine.floatArg(0.8), engine.floatArg(0.4), engine.floatArg(0.2) });
        return;
    }
    const age = @max(0, now - entity.time2);
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &point, engine.floatArg(@max(0, 250 - @as(f32, @floatFromInt(age)) / 12)), engine.floatArg(1), engine.floatArg(-1), engine.floatArg(-1) });
    const flame = try sprites.register("models/global/we_nharref.sp2");
    sprites.drawPlane(flame, @as(usize, @intCast(@divTrunc(age, 16))) % sprites.count(flame), point, 5, true, v.scale(ref.viewaxis[1], -1), ref.viewaxis[2], .{ 255, 255, 255, 204 });
    const state = burst(entity);
    if (!state.marked) {
        state.marked = true;
        var random: Random = .{ .state = @as(u32, @bitCast(entity.time)) ^ @as(u32, @intCast(entity.number)) };
        if (v.length(entity.pos.trDelta) > 0.5) _ = try @import("impacts.zig").decal(entity.apos.trDelta, entity.pos.trDelta, 64 * (1 + random.next() * 0.4), "models/e2/we_hammercrack.sp2/0@mark", random.next() * 2 * std.math.pi, entity.time2);
    }
    if (age < 1900) column(entity.origin2, entity.angles2);
    if (age >= 2000) return;
    // Keep the reviewed frame-driven spiral bounded and deterministic at 60 Hz.
    const center = v.add(point, .{ 0, 0, -92 });
    while (state.next_ms <= now) : (state.next_ms += 16) for (&state.sparks) |*spark| {
        if (!spark.alive) continue;
        const delta = v.subtract(center, spark.point);
        if (v.length(delta) < 3) {
            spark.alive = false;
            continue;
        }
        const direction = v.normalize(delta);
        const side: v.Vec3 = if (spark.clockwise) .{ direction[1], -direction[0], 0 } else .{ -direction[1], direction[0], 0 };
        spark.point = v.add(spark.point, v.scale(v.add(v.scale(side, spark.speed), v.scale(direction, spark.speed * 0.25)), 0.016));
        spark.speed *= 1.005;
        spark.scale = if (spark.scale > 174) 0 else spark.scale + 5;
    };
    const shader = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/jet-spark")});
    const alpha: u8 = @intFromFloat(@max(0, @sin(@as(f32, @floatFromInt(age)) * std.math.pi / 2000)) * 255);
    for (state.sparks) |spark| if (spark.alive) {
        var rendered = std.mem.zeroes(c.refEntity_t);
        rendered.reType = c.RT_SPRITE;
        rendered.customShader = @intCast(shader);
        rendered.origin = spark.point;
        rendered.radius = 1 + @sin(@as(f32, @floatFromInt(spark.scale)) * std.math.pi / 180);
        rendered.shaderRGBA = .{ 204, 51, 26, alpha };
        _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&rendered});
    };
}
fn column(start: v.Vec3, end: v.Vec3) void {
    const shader = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/beam")});
    var length = v.length(v.subtract(end, start));
    var radius: f32 = 10;
    for (0..2) |_| {
        const far = radius + length * 0.2;
        for (0..16) |i| {
            var vertices: [4]c.polyVert_t = undefined;
            for ([_]usize{ i, (i + 1) % 16, (i + 1) % 16, i }, 0..) |sector, j| {
                const angle = @as(f32, @floatFromInt(sector)) * 2 * std.math.pi / 16;
                const r = if (j < 2) radius else far;
                vertices[j] = .{ .xyz = v.add(if (j < 2) start else end, .{ @sin(angle) * r, -@cos(angle) * r, r }), .st = .{ 0, 0 }, .modulate = if (j < 2) .{ 230, 51, 26, 64 } else .{ 0, 0, 0, 13 } };
            }
            _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ shader, @as(isize, 4), &vertices });
        }
        radius *= 2.0 / 3.0;
        length *= 2.0 / 3.0;
    }
}
