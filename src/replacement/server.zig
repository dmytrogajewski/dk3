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
    @import("server/resources.zig").reset();
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
        try @import("server/world_systems.zig").spawn(&world.?, &slots, &projection, now, clients.episode);
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
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_items")) {
        for (slots.occupants) |occupant| {
            const entity = occupant orelse continue;
            const pickup = world.?.get(entity, component.Pickup) catch continue;
            const object = (world.?.get(entity, component.MapObject) catch unreachable).*;
            const transform = (world.?.get(entity, component.Transform) catch unreachable).*;
            const motion = (world.?.get(entity, component.ItemMotion) catch unreachable).*;
            var message: [256]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "zig item id={d} class={s} visible={d} ground={?d} pos={d:.2},{d:.2},{d:.2}\n", .{ world.?.persistentId(entity) catch unreachable, object.classname, @intFromBool(pickup.visible), motion.ground, transform.position[0], transform.position[1], transform.position[2] }) catch unreachable);
        }
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_damage")) {
        const entity = clients.entities[0] orelse return 1;
        var argument: [64]u8 = undefined;
        const amount = std.fmt.parseInt(i32, engine.argv(1, &argument), 10) catch return 1;
        if (amount <= 0 or amount > 10000) return 1;
        const result = @import("server/damage.zig").apply(&world.?, entity, amount, clock.now_ms, .{}) catch |err| runtimeFailure(err);
        var message: [128]u8 = undefined;
        engine.print(std.fmt.bufPrintZ(&message, "zig damage blood={d} armor={d} killed={d}\n", .{ result.blood, result.armor, @intFromBool(result.killed) }) catch unreachable);
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_character")) {
        const entity = clients.entities[0] orelse return 1;
        const state = (world.?.get(entity, component.Character) catch unreachable).*;
        var message: [256]u8 = undefined;
        engine.print(std.fmt.bufPrintZ(&message, "zig character time={d} speed={d} boost_until={d} invincible={d} environment={d} gems={d} level={d} points={d}\n", .{ clock.now_ms, state.attribute(.speed, clock.now_ms), state.boost_until[2], state.invincible_until, state.environment_until, state.save_gems, state.level, state.points }) catch unreachable);
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_inventory")) {
        const entity = clients.entities[0] orelse return 1;
        const loadout = (world.?.get(entity, component.Weapons) catch unreachable).*;
        const keys = (world.?.get(entity, component.Keys) catch unreachable).*;
        const health = (world.?.get(entity, component.Health) catch unreachable).*;
        var message: [256]u8 = undefined;
        engine.print(std.fmt.bufPrintZ(&message, "zig inventory keys={x} quest={x} owned={x} weapon={d} health={d} armor={d}\n", .{ keys.mask, keys.quest, @as(u32, @bitCast(loadout.dk3Inventory)), loadout.weapon, health.current, health.armor }) catch unreachable);
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
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_special")) {
        for (slots.occupants) |occupant| {
            const entity = occupant orelse continue;
            const secret = world.?.get(entity, component.Secret) catch null;
            const rotation = world.?.get(entity, component.Rotation) catch null;
            if (secret == null and rotation == null) continue;
            const transform = (world.?.get(entity, component.Transform) catch unreachable).*;
            var message: [256]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "zig special id={d} phase={s} pos={d:.1},{d:.1},{d:.1} angles={d:.1},{d:.1},{d:.1}\n", .{ world.?.persistentId(entity) catch unreachable, if (secret) |value| @tagName(value.phase) else if (rotation.?.active) "rotating" else "stopped", transform.position[0], transform.position[1], transform.position[2], transform.angles[0], transform.angles[1], transform.angles[2] }) catch unreachable);
        }
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_trains")) {
        for (slots.occupants) |occupant| {
            const entity = occupant orelse continue;
            const train = world.?.get(entity, component.Train) catch continue;
            const object = (world.?.get(entity, component.MapObject) catch unreachable).*;
            const transform = (world.?.get(entity, component.Transform) catch unreachable).*;
            var message: [320]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "zig train id={d} name={s} phase={s} corner={d} wait={d} due={?d} start={d} duration={d} endz={d:.1} pos={d:.1},{d:.1},{d:.1}\n", .{ world.?.persistentId(entity) catch unreachable, object.targetname, @tagName(train.phase), train.destination, train.departure_wait_ms, train.action.at_ms, train.position.start_ms, train.position.duration_ms, train.position.end[2], transform.position[0], transform.position[1], transform.position[2] }) catch unreachable);
        }
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_place")) {
        const player_entity = clients.entities[0] orelse return 1;
        var point: component.Vec3 = undefined;
        for (&point, 0..) |*axis, i| {
            var argument: [64]u8 = undefined;
            axis.* = std.fmt.parseFloat(f32, engine.argv(@intCast(i + 1), &argument)) catch return 1;
            if (!std.math.isFinite(axis.*) or @abs(axis.*) > 1000000) return 1;
        }
        (world.?.get(player_entity, component.Transform) catch unreachable).position = point;
        (world.?.get(player_entity, component.Velocity) catch unreachable).linear = @splat(0);
        (world.?.get(player_entity, component.Player) catch unreachable).ground_entity = c.ENTITYNUM_NONE;
        clients.publish(&world.?, &projection, &players, 0) catch |err| runtimeFailure(err);
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_board")) {
        var argument: [32]u8 = undefined;
        const id = std.fmt.parseInt(u32, engine.argv(1, &argument), 10) catch return 1;
        const player_entity = clients.entities[0] orelse return 1;
        const entity = world.?.find(id) orelse return 1;
        const binding = world.?.get(entity, component.Binding) catch return 1;
        const brush = &projection[binding.slot];
        const transform = world.?.get(player_entity, component.Transform) catch unreachable;
        const candidate: component.Vec3 = .{ (brush.shared.absmin[0] + brush.shared.absmax[0]) * 0.5, (brush.shared.absmin[1] + brush.shared.absmax[1]) * 0.5, brush.shared.absmax[2] + 24.125 };
        const body = (world.?.get(player_entity, component.Body) catch unreachable).*;
        const clear = engine.collisionService().trace(.{ .start = candidate, .end = candidate, .mins = body.mins, .maxs = body.maxs, .slot = 0, .mask = c.MASK_PLAYERSOLID }) catch |err| runtimeFailure(err);
        if (clear.start_solid) {
            engine.print("zig probe: brush centre is obstructed; choose a known walkable position with dk3_runtime_place.\n");
            return 1;
        }
        transform.position = candidate;
        (world.?.get(player_entity, component.Velocity) catch unreachable).linear = @splat(0);
        clients.publish(&world.?, &projection, &players, 0) catch |err| runtimeFailure(err);
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_activate")) {
        var argument: [32]u8 = undefined;
        const id = std.fmt.parseInt(u32, engine.argv(1, &argument), 10) catch return 1;
        var owner: u32 = 0;
        if (std.mem.eql(u8, engine.argv(2, &argument), "player")) if (clients.entities[0]) |player| {
            owner = world.?.persistentId(player) catch unreachable;
        };
        if (world.?.find(id)) |entity| targets.activate(&world.?, &slots, &projection, entity, owner, clock.now_ms) catch |err| runtimeFailure(err);
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
            engine.fatal(std.fmt.bufPrintZ(&buffer, "Native Zig runtime: {s}. Isolated development uses dk3_runtime_probe=2; bootstrap diagnostics use 1.", .{@errorName(err)}) catch unreachable);
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
                @import("server/world_systems.zig").step(&world.?, &slots, &projection, &targets, clock.now_ms, elapsed, &clients.weapon_table) catch |err| runtimeFailure(err);
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
            if (std.mem.eql(u8, client_command, "attribute")) {
                var argument: [64]u8 = undefined;
                const attribute = @import("domain/character.zig").attributeNamed(engine.argv(1, &argument)) orelse return 0;
                if (clients.entities[@intCast(arg0)]) |entity| {
                    const state = world.?.get(entity, component.Character) catch return 0;
                    _ = state.spend(attribute);
                }
            } else if (std.mem.eql(u8, client_command, "use")) {
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
