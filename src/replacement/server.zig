// SPDX-License-Identifier: GPL-2.0-or-later
//! Replacement module entrypoint. Bootstrap probes are explicit, never gameplay fallback.
const std = @import("std");
const abi = @import("engine/abi.zig");
const engine = @import("engine/server.zig");
const c = abi.c;
const component = @import("domain/components.zig");
const map = @import("server/map.zig");
const Pool = @import("ecs/jobs.zig").Pool;
var targets: @import("server/targets.zig").Router = .{};
var clients: @import("server/clients.zig").Clients = .{};
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
    if (engine.integer("dk3_runtime_probe") < 1 or engine.integer("dk3_runtime_probe") > 2) return error.ReplacementGameplayNotQualified;
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
    clients = .{};
    targets = .{};
    if (engine.integer("dk3_runtime_probe") == 2) {
        const bytes = try @import("engine/files.zig").read(.server, &engine.gateway, std.heap.c_allocator, "dk3/tables/weapons.cfg", 4 * 1024 * 1024);
        defer std.heap.c_allocator.free(bytes);
        clients.weapon_table = try @import("domain/weapons.zig").Table.parse(bytes);
        var map_name: [c.MAX_QPATH]u8 = @splat(0);
        _ = engine.gateway.call(c.G_CVAR_VARIABLE_STRING_BUFFER, .{ @as([*:0]const u8, "mapname"), &map_name, @as(isize, map_name.len) });
        if (map_name[0] == 'e' and map_name[1] >= '1' and map_name[1] <= '4') clients.episode = map_name[1] - '0';
    }
    engine.locate(&projection, &players);
    engine.config(c.CS_GAME_VERSION, @import("engine/player_state.zig").version);
    engine.register("g_gametype", "2", c.CVAR_SERVERINFO);
    while (try map.read(arena.?.allocator(), engine)) |object| {
        _ = try world.?.create(null, .{ object.binding, object.transform });
    }
    if (engine.integer("dk3_runtime_probe") == 2) {
        try @import("server/brushes.zig").spawn(&world.?, &slots, &projection);
        try @import("server/movers.zig").spawn(&world.?, &slots, &projection);
        try @import("server/targets.zig").spawn(&world.?);
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
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_movers")) {
        for (slots.occupants) |occupant| {
            const entity = occupant orelse continue;
            const mover = world.?.get(entity, component.Mover) catch continue;
            const object = (world.?.get(entity, component.MapObject) catch unreachable).*;
            const transform = (world.?.get(entity, component.Transform) catch unreachable).*;
            var message: [320]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "zig mover id={d} group={d} class={s} name={s} state={s} pos={d:.1},{d:.1},{d:.1} end={d:.1},{d:.1},{d:.1}\n", .{ world.?.persistentId(entity) catch unreachable, mover.group, object.classname, object.targetname, @tagName(mover.state), transform.position[0], transform.position[1], transform.position[2], mover.opened[0], mover.opened[1], mover.opened[2] }) catch unreachable);
        }
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_activate")) {
        var argument: [32]u8 = undefined;
        const id = std.fmt.parseInt(u32, engine.argv(1, &argument), 10) catch return 1;
        if (world.?.find(id)) |entity| targets.activate(&world.?, &slots, &projection, entity, 0, clock.now_ms) catch |err| runtimeFailure(err);
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
        c.GAME_CLIENT_CONNECT => {
            if (engine.integer("dk3_runtime_probe") != 2) return @intCast(@intFromPtr(@as([*:0]const u8, "Zig replacement bootstrap does not admit players; movement development requires dk3_runtime_probe=2.")));
            if (arg0 < 0 or arg0 >= c.MAX_CLIENTS) return @intCast(@intFromPtr(@as([*:0]const u8, "Invalid client slot.")));
            var userinfo: [c.MAX_INFO_STRING]u8 = @splat(0);
            _ = engine.gateway.call(c.G_GET_USERINFO, .{ arg0, &userinfo, @as(isize, userinfo.len) });
            const identity = @import("engine/info.zig").get(std.mem.sliceTo(&userinfo, 0), "dk3_runtime_build") orelse "";
            if (!std.mem.eql(u8, identity, @import("engine/player_state.zig").version)) return @intCast(@intFromPtr(@as([*:0]const u8, "Zig runtime build mismatch. Install matching server, client and UI modules.")));
            return 0;
        },
        c.GAME_CLIENT_BEGIN => clients.begin(&world.?, &slots, &projection, &players, @intCast(arg0), clock.now_ms) catch |err| runtimeFailure(err),
        c.GAME_CLIENT_THINK => clients.think(&world.?, &projection, &players, @intCast(arg0), clock.now_ms) catch |err| runtimeFailure(err),
        c.GAME_CLIENT_DISCONNECT => clients.disconnect(&world.?, &slots, &projection, @intCast(arg0)) catch |err| runtimeFailure(err),
        c.GAME_RUN_FRAME => {
            const elapsed = clock.advance(arg0) catch {
                engine.fatal("Zig replacement: invalid engine frame time");
            };
            if (engine.integer("dk3_runtime_probe") == 2) {
                @import("server/interactions.zig").touch(&world.?, &slots, &projection, &targets, clock.now_ms) catch |err| runtimeFailure(err);
                const arrivals = @import("server/movers.zig").step(&world.?, &slots, &projection, clock.now_ms, elapsed) catch |err| runtimeFailure(err);
                for (arrivals.entities[0..arrivals.count]) |entity| {
                    if (!world.?.alive(entity)) continue;
                    const owner = (world.?.get(entity, component.Mover) catch |err| runtimeFailure(err)).owner;
                    targets.fire(&world.?, &slots, &projection, entity, owner, clock.now_ms) catch |err| runtimeFailure(err);
                }
                targets.step(&world.?, &slots, &projection, clock.now_ms) catch |err| runtimeFailure(err);
                for (clients.entities, 0..) |entity, index| if (entity != null) {
                    clients.publish(&world.?, &projection, &players, index) catch |err| runtimeFailure(err);
                };
            }
        },
        c.GAME_CONSOLE_COMMAND => return consoleCommand(),
        c.GAME_CLIENT_COMMAND => {
            if (arg0 < 0 or arg0 >= c.MAX_CLIENTS) return 0;
            var command_buffer: [64]u8 = undefined;
            const client_command = engine.argv(0, &command_buffer);
            if (std.mem.eql(u8, client_command, "use")) {
                if (clients.entities[@intCast(arg0)]) |entity| @import("server/interactions.zig").use(&world.?, &slots, &projection, &targets, entity, clock.now_ms) catch |err| runtimeFailure(err);
            }
        },
        c.GAME_CLIENT_USERINFO_CHANGED, c.BOTAI_START_FRAME => {},
        else => return -1,
    }
    return 0;
}

fn runtimeFailure(err: anyerror) noreturn {
    var message: [160]u8 = undefined;
    engine.fatal(std.fmt.bufPrintZ(&message, "Zig runtime: {s}", .{@errorName(err)}) catch unreachable);
}
