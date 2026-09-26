// SPDX-License-Identifier: GPL-2.0-or-later
//! Native snapshot ingestion, shared movement prediction and world rendering.
const std = @import("std");
const abi = @import("engine/abi.zig");
const engine = @import("engine/client.zig");
const bridge = @import("engine/player_state.zig");
const data = @import("domain/components.zig");
const move = @import("domain/player_move.zig");
const v = @import("domain/vector.zig");
const c = abi.c;
const weapons = @import("domain/weapons.zig");
var selected_weapon: i32 = 0;
var inventory_mask: i32 = 0;
var weapon_table: weapons.Table = .{};
var inline_models: [c.MAX_MODELS]c.qhandle_t = @splat(0);
var game: c.gameState_t = undefined;
var display: c.glconfig_t = undefined;
var snapshot: c.snapshot_t = undefined;
var world: ?data.World = null;
var predicted: ?@import("ecs/world.zig").Entity = null;
var have_snapshot = false;
var snapshot_number: i32 = -1;
var command_sequence: i32 = 0;
var client_number: i32 = 0;
var view_angles: v.Vec3 = @splat(0);
export fn dllEntry(callback: abi.Syscall) callconv(.c) void {
    engine.gateway.bind(callback);
}
fn shutdown() void {
    if (world) |*value| value.deinit();
    world = null;
    predicted = null;
}
fn init(server_message: i32, sequence: i32, client: i32) !void {
    shutdown();
    @import("client/models.zig").reset();
    @import("client/events.zig").reset();
    selected_weapon = 0;
    inventory_mask = 0;
    if (engine.integer("dk3_runtime_probe") != 2) return error.ReplacementGameplayNotQualified;
    _ = engine.gateway.call(c.CG_GETGAMESTATE, .{&game});
    if (!std.mem.eql(u8, try engine.config(&game, c.CS_GAME_VERSION), bridge.version)) return error.RuntimeMismatch;
    const info = try engine.config(&game, c.CS_SERVERINFO);
    const name = engine.info(info, "mapname") orelse return error.MissingMap;
    for (name) |ch| if (!std.ascii.isAlphanumeric(ch) and ch != '_') return error.InvalidMap;
    var path: [128]u8 = undefined;
    const map = try std.fmt.bufPrintZ(&path, "maps/{s}.bsp", .{name});
    _ = engine.gateway.call(c.CG_GETGLCONFIG, .{&display});
    _ = engine.gateway.call(c.CG_CM_LOADMAP, .{map.ptr});
    _ = engine.gateway.call(c.CG_R_LOADWORLDMAP, .{map.ptr});
    @memset(&inline_models, 0);
    const model_count = engine.gateway.call(c.CG_CM_NUMINLINEMODELS, .{});
    if (model_count < 1 or model_count > inline_models.len) return error.InlineModelLimit;
    for (1..@intCast(model_count)) |i| {
        var model_name: [20]u8 = undefined;
        const model = try std.fmt.bufPrintZ(&model_name, "*{d}", .{i});
        inline_models[i] = @intCast(engine.gateway.call(c.CG_R_REGISTERMODEL, .{model.ptr}));
    }
    const table_bytes = try @import("engine/files.zig").read(.client, &engine.gateway, std.heap.c_allocator, "dk3/tables/weapons.cfg", 4 * 1024 * 1024);
    defer std.heap.c_allocator.free(table_bytes);
    weapon_table = try weapons.Table.parse(table_bytes);
    world = data.World.init(std.heap.c_allocator, 128);
    predicted = try world.?.create(null, .{ data.Transform{}, data.Velocity{}, data.Player{}, data.Health{}, data.Weapons{}, data.Character{}, data.Ailments{} });
    have_snapshot = false;
    client_number = client;
    command_sequence = sequence;
    snapshot_number = server_message - 1;
    _ = engine.gateway.call(c.CG_ADDCOMMAND, .{@as([*:0]const u8, "viewpos")});
    _ = engine.gateway.call(c.CG_ADDCOMMAND, .{@as([*:0]const u8, "use")});
    for ([_][*:0]const u8{ "weapon", "weapnext", "weapprev", "attribute" }) |command_name| _ = engine.gateway.call(c.CG_ADDCOMMAND, .{command_name});
    engine.print("dk3 zig: shared movement prediction initialized\n");
}
fn draw(now: i32) !void {
    if (world == null) return;
    var latest: i32 = 0;
    var server_time: i32 = 0;
    _ = engine.gateway.call(c.CG_GETCURRENTSNAPSHOTNUMBER, .{ &latest, &server_time });
    if (latest > snapshot_number) {
        if (engine.gateway.call(c.CG_GETSNAPSHOT, .{ @as(isize, latest), &snapshot }) == 0) return;
        snapshot_number = latest;
        have_snapshot = true;
        while (command_sequence < snapshot.serverCommandSequence) {
            command_sequence += 1;
            if (engine.gateway.call(c.CG_GETSERVERCOMMAND, .{@as(isize, command_sequence)}) != 0) {
                if (@import("client/commands.zig").selectedWeapon(snapshot.ps.dk3Inventory)) |id| selected_weapon = id;
            }
        }
        _ = engine.gateway.call(c.CG_GETGAMESTATE, .{&game});
    }
    if (!have_snapshot or snapshot_number < 0 or snapshot.ps.clientNum != client_number) return;
    if (snapshot.numEntities < 0 or snapshot.numEntities > snapshot.entities.len) return error.InvalidSnapshot;
    engine.setSnapshot(snapshot.entities[0..@intCast(snapshot.numEntities)], now);
    try @import("client/events.zig").consume(&game, snapshot.entities[0..@intCast(snapshot.numEntities)]);
    if (selected_weapon == 0 or snapshot.ps.dk3Inventory != inventory_mask) {
        selected_weapon = snapshot.ps.weapon;
        inventory_mask = snapshot.ps.dk3Inventory;
    }
    const w = &world.?;
    const player_entity = predicted.?;
    const transform = try w.get(player_entity, data.Transform);
    const velocity = try w.get(player_entity, data.Velocity);
    const player = try w.get(player_entity, data.Player);
    transform.* = .{ .position = snapshot.ps.origin, .angles = snapshot.ps.viewangles };
    velocity.linear = snapshot.ps.velocity;
    player.* = bridge.read(&snapshot.ps);
    const loadout = try w.get(player_entity, data.Weapons);
    loadout.* = bridge.readWeapons(&snapshot.ps);
    const character = try w.get(player_entity, data.Character);
    const ailments = try w.get(player_entity, data.Ailments);
    character.* = bridge.readCharacter(&snapshot.ps);
    ailments.* = .{ .mask = @as(u32, @bitCast(snapshot.ps.dk3Status)) & (7 | 128), .freeze_level = snapshot.ps.dk3FreezeLevel };
    const current: i32 = @intCast(engine.gateway.call(c.CG_GETCURRENTCMDNUMBER, .{}));
    var number = @max(0, current - c.CMD_BACKUP + 1);
    while (number <= current) : (number += 1) {
        var input: c.usercmd_t = undefined;
        if (engine.gateway.call(c.CG_GETUSERCMD, .{ @as(isize, number), &input }) == 0 or input.serverTime <= player.command_ms or input.serverTime > now) continue;
        const command = bridge.command(input, &player.delta_angles);
        var motion: @import("domain/slide.zig").State = .{ .position = transform.position, .velocity = velocity.linear };
        if (ailments.mask & 128 != 0) motion.velocity = @splat(0);
        var events: weapons.Events = .{};
        var weapon_context: weapons.Context = .{ .ps = loadout, .healthy = snapshot.ps.stats[c.STAT_HEALTH] > 0, .single_player = engine.integer("g_gametype") == c.GT_SINGLE_PLAYER, .table = &weapon_table, .events = &events, .service = engine.collisionService(), .slot = @intCast(client_number), .shot_mask = c.MASK_SHOT, .attack_boost = character.attribute(.attack, command.time_ms) };
        _ = try move.runWithHook(player, &motion, command, bridge.characterParameters(@intCast(client_number), character.*, ailments.*, command.time_ms), engine.collisionService(), weapon_context.hook());
        transform.position = motion.position;
        transform.angles = command.angles;
        velocity.linear = motion.velocity;
    }
    view_angles = transform.angles;
    _ = engine.gateway.call(c.CG_SETUSERCMDVALUE, .{ @as(isize, selected_weapon), engine.floatArg(1) });
    var ref = std.mem.zeroes(c.refdef_t);
    ref.width = display.vidWidth;
    ref.height = display.vidHeight;
    ref.time = now;
    ref.fov_x = 90;
    ref.fov_y = std.math.atan(@as(f32, @floatFromInt(ref.height)) / @as(f32, @floatFromInt(ref.width))) * 360 / std.math.pi;
    ref.vieworg = transform.position;
    ref.vieworg[2] += player.view_height;
    const basis = v.basis(view_angles);
    ref.viewaxis[0] = basis.forward;
    ref.viewaxis[1] = v.scale(basis.right, -1);
    ref.viewaxis[2] = v.cross(ref.viewaxis[0], ref.viewaxis[1]);
    ref.areamask = snapshot.areamask;
    ref.dk3Lightstyles = @splat(1);
    _ = engine.gateway.call(c.CG_R_CLEARSCENE, .{});
    for (snapshot.entities[0..@intCast(snapshot.numEntities)]) |entity| {
        var handle: c.qhandle_t = 0;
        if (entity.solid == c.SOLID_BMODEL and entity.modelindex > 0 and entity.modelindex < inline_models.len) {
            handle = inline_models[@intCast(entity.modelindex)];
        } else if (entity.eType == c.ET_DK3_ITEM) handle = try @import("client/models.zig").get(&game, entity.modelindex);
        if (handle == 0) continue;
        var rendered = std.mem.zeroes(c.refEntity_t);
        rendered.hModel = handle;
        rendered.reType = c.RT_MODEL;
        rendered.origin = @import("engine/trajectory.zig").evaluate(entity.pos, now);
        rendered.oldorigin = rendered.origin;
        const orientation = v.basis(@import("engine/trajectory.zig").evaluate(entity.apos, now));
        rendered.axis[0] = orientation.forward;
        rendered.axis[1] = v.scale(orientation.right, -1);
        rendered.axis[2] = v.cross(rendered.axis[0], rendered.axis[1]);
        rendered.shaderRGBA = @splat(255);
        _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&rendered});
    }
    _ = engine.gateway.call(c.CG_R_RENDERSCENE, .{&ref});
    _ = engine.gateway.call(c.CG_S_RESPATIALIZE, .{ @as(isize, client_number), &ref.vieworg, &ref.viewaxis, @as(isize, @intFromBool(player.water_level == 3)) });
}
fn console() isize {
    var buffer: [128]u8 = @splat(0);
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 0), &buffer, @as(isize, buffer.len) });
    const name = std.mem.sliceTo(&buffer, 0);
    if (world == null or !have_snapshot) return 0;
    if (std.mem.eql(u8, name, "weapon")) {
        _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 1), &buffer, @as(isize, buffer.len) });
        const id = std.fmt.parseInt(u5, std.mem.sliceTo(&buffer, 0), 10) catch return 1;
        if (@import("weapon_catalog").find(id) != null and @as(u32, @bitCast(snapshot.ps.dk3Inventory)) & (@as(u32, 1) << id) != 0) selected_weapon = id;
        return 1;
    }
    if (std.mem.eql(u8, name, "weapnext") or std.mem.eql(u8, name, "weapprev")) {
        const direction: i32 = if (std.mem.eql(u8, name, "weapnext")) 1 else -1;
        var id = selected_weapon;
        for (0..28) |_| {
            id = @mod(id - 1 + direction, 28) + 1;
            const entry = @import("weapon_catalog").find(@intCast(id)).?;
            if (entry.spec.auto_select and @as(u32, @bitCast(snapshot.ps.dk3Inventory)) & (@as(u32, 1) << @as(u5, @intCast(id))) != 0) {
                selected_weapon = id;
                break;
            }
        }
        return 1;
    }
    if (!std.mem.eql(u8, name, "viewpos")) return 0;
    const transform = world.?.get(predicted.?, data.Transform) catch return 0;
    var message: [200]u8 = undefined;
    engine.print(std.fmt.bufPrintZ(&message, "zig viewpos: {d:.3} {d:.3} {d:.3}, angles {d:.2} {d:.2} {d:.2}\n", .{ transform.position[0], transform.position[1], transform.position[2], view_angles[0], view_angles[1], view_angles[2] }) catch unreachable);
    return 1;
}
fn failure(err: anyerror) noreturn {
    var message: [160]u8 = undefined;
    engine.fatal(std.fmt.bufPrintZ(&message, "Zig client: {s}", .{@errorName(err)}) catch unreachable);
}
export fn vmMain(command: c_int, arg0: isize, arg1: isize, arg2: isize, arg3: isize, arg4: isize, arg5: isize, arg6: isize, arg7: isize, arg8: isize, arg9: isize, arg10: isize, arg11: isize) callconv(.c) isize {
    _ = .{ arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11 };
    switch (command) {
        c.CG_INIT => init(@intCast(arg0), @intCast(arg1), @intCast(arg2)) catch |err| failure(err),
        c.CG_SHUTDOWN => shutdown(),
        c.CG_DRAW_ACTIVE_FRAME => draw(@intCast(arg0)) catch |err| failure(err),
        c.CG_CONSOLE_COMMAND => return console(),
        c.CG_CROSSHAIR_PLAYER, c.CG_LAST_ATTACKER => return -1,
        else => {},
    }
    return 0;
}
