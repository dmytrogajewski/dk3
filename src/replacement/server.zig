// SPDX-License-Identifier: GPL-2.0-or-later
//! Replacement module entrypoint. Bootstrap probes are explicit, never gameplay fallback.
const std = @import("std");
const abi = @import("engine/abi.zig");
const engine = @import("engine/server.zig");
const c = abi.c;
const component = @import("domain/components.zig");
const map = @import("server/map.zig");
const Pool = @import("ecs/jobs.zig").Pool;
var arena: ?std.heap.ArenaAllocator = null;
var world: ?component.World = null;
var pool: ?*Pool = null;
var projection: [c.MAX_GENTITIES]abi.EntityProjection = undefined;
var players: [c.MAX_CLIENTS]c.playerState_t = undefined;
var clock: @import("domain/time.zig").Clock = .{ .now_ms = 0 };
var slots: @import("engine/slots.zig").Slots = .{};

export fn dllEntry(callback: abi.Syscall) callconv(.c) void {
    engine.gateway.bind(callback);
}
fn shutdown() void {
    if (pool) |workers| workers.destroy();
    pool = null;
    if (world) |*value| value.deinit();
    world = null;
    if (arena) |*value| value.deinit();
    arena = null;
}
fn init(now: i64) !void {
    shutdown();
    engine.register("dk3_runtime_probe", "0", 0);
    if (engine.integer("dk3_runtime_probe") != 1) return error.ReplacementGameplayNotQualified;
    var defaults: [12]u8 = undefined;
    const worker_default = try std.fmt.bufPrintZ(&defaults, "{d}", .{Pool.defaultWorkers()});
    engine.register("dk3_jobs", worker_default, c.CVAR_ARCHIVE | c.CVAR_LATCH);
    const jobs = engine.integer("dk3_jobs");
    if (jobs < 0 or jobs > 8) return error.WorkerLimit;
    arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    errdefer shutdown();
    world = component.World.init(std.heap.c_allocator, 1024);
    pool = try Pool.create(std.heap.c_allocator, @intCast(jobs));
    @memset(std.mem.asBytes(&projection), 0);
    @memset(std.mem.asBytes(&players), 0);
    for (&projection, 0..) |*entity, i| {
        entity.state.number = @intCast(i);
        entity.shared.ownerNum = c.ENTITYNUM_NONE;
    }
    clock = .{ .now_ms = now };
    slots = .{};
    engine.locate(&projection, &players);
    engine.config(c.CS_GAME_VERSION, "dk3-zig-probe-1");
    engine.register("g_gametype", "2", c.CVAR_SERVERINFO);
    while (try map.read(arena.?.allocator(), engine)) |object| {
        _ = try world.?.create(null, .{ object.binding, object.transform });
    }
    var text: [160]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig: isolated bootstrap, {d} map entities, {d} workers; gameplay not qualified\n", .{ world.?.count(), jobs }));
}
fn probeMotion() !void {
    const movement = @import("server/motion.zig");
    const w = if (world) |*value| value else return error.NotInitialized;
    var created: [128]@import("ecs/world.zig").Entity = undefined;
    var count: usize = 0;
    defer for (created[0..count]) |entity| {
        if (slots.find(entity)) |slot| slots.release(slot, entity) catch unreachable;
        w.destroy(entity) catch unreachable;
    };
    for (&created, 0..) |*entity, i| {
        entity.* = try w.create(null, .{
            component.Transform{ .position = .{ @as(f32, @floatFromInt(i)), 0, 128 } },
            component.Velocity{ .linear = .{ 3, 2, 1 } },
            component.Gravity{},
            component.Motion{},
            component.Body{ .collision_mask = c.MASK_SOLID },
            component.Binding{ .slot = c.ENTITYNUM_NONE },
        });
        count += 1;
        (try w.get(entity.*, component.Binding)).slot = try slots.acquire(entity.*, null);
    }
    for (0..20) |_| try movement.step(w, pool.?, engine.collisionService(), 50);
    var hash = std.hash.Wyhash.init(0);
    for (created) |entity| hash.update(std.mem.asBytes(&(try w.get(entity, component.Transform)).position));
    var output: [128]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig motion probe: workers={d} entities=128 steps=20 hash={x}\n", .{ pool.?.thread_count, hash.final() }));
}
fn consoleCommand() isize {
    var buffer: [128]u8 = undefined;
    const command = engine.argv(0, &buffer);
    if (std.mem.eql(u8, command, "dk3_runtime_probe_motion")) {
        probeMotion() catch |err| {
            var failure: [128]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&failure, "dk3 zig probe failed: {s}\n", .{@errorName(err)}) catch unreachable);
        };
        return 1;
    }
    if (!std.mem.eql(u8, command, "dk3_runtime_status")) return 0;
    var text: [160]u8 = undefined;
    engine.print(std.fmt.bufPrintZ(&text, "dk3 zig: entities={d} frames={d} time={d} workers={d}\n", .{ if (world) |*value| value.count() else 0, clock.frame, clock.now_ms, if (pool) |value| value.thread_count else 0 }) catch unreachable);
    return 1;
}
export fn vmMain(command: c_int, arg0: isize, arg1: isize, arg2: isize, arg3: isize, arg4: isize, arg5: isize, arg6: isize, arg7: isize, arg8: isize, arg9: isize, arg10: isize, arg11: isize) callconv(.c) isize {
    _ = .{ arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11 };
    switch (command) {
        c.GAME_INIT => init(arg0) catch |err| {
            var buffer: [256]u8 = undefined;
            engine.fatal(std.fmt.bufPrintZ(&buffer, "Zig replacement: {s}. Use the legacy runtime for gameplay; explicit isolated bootstrap uses dk3_runtime_probe=1.", .{@errorName(err)}) catch unreachable);
        },
        c.GAME_SHUTDOWN => shutdown(),
        c.GAME_CLIENT_CONNECT => return @intCast(@intFromPtr(@as([*:0]const u8, "Zig replacement gameplay is not qualified; bootstrap does not admit players."))),
        c.GAME_RUN_FRAME => {
            _ = clock.advance(arg0) catch {
                engine.fatal("Zig replacement: invalid engine frame time");
            };
        },
        c.GAME_CONSOLE_COMMAND => return consoleCommand(),
        c.GAME_CLIENT_BEGIN, c.GAME_CLIENT_USERINFO_CHANGED, c.GAME_CLIENT_DISCONNECT, c.GAME_CLIENT_COMMAND, c.GAME_CLIENT_THINK, c.BOTAI_START_FRAME => {},
        else => return -1,
    }
    return 0;
}
