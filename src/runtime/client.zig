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
var weapon_view: @import("client/weapon_view.zig").View = .{};
var hud: @import("client/hud.zig").Hud = .{};
export fn dllEntry(callback: abi.Syscall) callconv(.c) void {
    engine.gateway.bind(callback);
}
fn shutdown() void {
    @import("client/scoreboard.zig").reset();
    @import("client/messages.zig").reset();
    @import("client/cinematics.zig").reset();
    @import("client/dragon.zig").reset();
    @import("client/chaingang.zig").reset();
    @import("client/buboid.zig").reset();
    @import("client/sword_aura.zig").reset();
    @import("client/venom_spit.zig").reset();
    @import("client/wisps.zig").reset();
    @import("client/wyndrax_actor.zig").reset();
    @import("client/actor_meteors.zig").reset();
    @import("client/summon_effects.zig").reset();
    @import("client/nharre_reaper.zig").reset();
    @import("client/fx_particles.zig").reset();
    @import("client/gibs.zig").reset();
    @import("client/quake_kick.zig").reset();
    @import("client/complex_particles.zig").reset();
    @import("client/lightning.zig").reset();
    @import("client/weather.zig").reset();
    @import("client/target_effects.zig").reset();
    weapon_view.deinit();
    if (world) |*value| value.deinit();
    world = null;
    predicted = null;
}
fn init(server_message: i32, sequence: i32, client: i32) !void {
    shutdown();
    @import("client/models.zig").reset();
    @import("client/objectives.zig").reset();
    @import("client/held_weapons.zig").reset();
    @import("client/events.zig").reset();
    selected_weapon = 0;
    @import("client/music.zig").reset();
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
    weapon_view.init();
    try hud.init();
    world = data.World.init(std.heap.c_allocator, 128);
    predicted = try world.?.create(null, .{ data.Transform{}, data.Velocity{}, data.Player{}, data.Health{}, data.Weapons{}, data.Character{}, data.Ailments{} });
    have_snapshot = false;
    client_number = client;
    command_sequence = sequence;
    snapshot_number = server_message - 1;
    _ = engine.gateway.call(c.CG_ADDCOMMAND, .{@as([*:0]const u8, "viewpos")});
    _ = engine.gateway.call(c.CG_ADDCOMMAND, .{@as([*:0]const u8, "use")});
    for ([_][*:0]const u8{ "weapon", "weapnext", "weapprev", "attribute", "inventory", "invnext", "invprev", "attribute_next", "attribute_increase", "save", "load", "+scores", "-scores", "say", "say_team", "ready", "team", "callvote", "vote" }) |command_name| _ = engine.gateway.call(c.CG_ADDCOMMAND, .{command_name});
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
        if (!have_snapshot) engine.print("dk3 zig client: first snapshot applied\n");
        have_snapshot = true;
        const sequence_number: u32 = @bitCast(snapshot.ps.eventSequence);
        for (0..c.MAX_PS_EVENTS) |i| {
            const serial = sequence_number -% @as(u32, @intCast(c.MAX_PS_EVENTS - i));
            const index = serial & (c.MAX_PS_EVENTS - 1);
            if (snapshot.ps.events[index] != c.EV_FIRE_WEAPON) continue;
            const id = snapshot.ps.eventParms[index];
            if (id > 0 and id <= 28) weapon_view.fire(@intCast(id), serial, snapshot.ps.commandTime);
        }
        while (command_sequence < snapshot.serverCommandSequence) {
            command_sequence += 1;
            if (engine.gateway.call(c.CG_GETSERVERCOMMAND, .{@as(isize, command_sequence)}) != 0) {
                try @import("client/cinematics.zig").command();
                try @import("client/events.zig").command();
                @import("client/messages.zig").command(now);
                @import("client/scoreboard.zig").command();
                @import("client/quake_kick.zig").command();
                if (@import("client/commands.zig").restored()) |restored| {
                    @import("client/messages.zig").reset();
                    @import("client/models.zig").reset();
                    @import("client/objectives.zig").reset();
                    @import("client/held_weapons.zig").reset();
                    @import("client/events.zig").reset();
                    @import("client/quake_kick.zig").reset();
    @import("client/complex_particles.zig").reset();
    @import("client/lightning.zig").reset();
    @import("client/weather.zig").reset();
    @import("client/target_effects.zig").reset();
                    weapon_view.init();
                    if (restored.fire) |fire| weapon_view.fire(fire.weapon, fire.serial, fire.started_ms);
                    selected_weapon = snapshot.ps.weapon;
                    engine.print("dk3 zig client: restoration applied\n");
                }
                if (@import("client/commands.zig").selectedWeapon(snapshot.ps.dk3Inventory)) |id| selected_weapon = id;
            }
        }
        _ = engine.gateway.call(c.CG_GETGAMESTATE, .{&game});
    }
    if (!have_snapshot or snapshot_number < 0 or snapshot.ps.clientNum != client_number) return;
    if (snapshot.numEntities < 0 or snapshot.numEntities > snapshot.entities.len) return error.InvalidSnapshot;
    try @import("client/music.zig").update(&game);
    try @import("client/events.zig").environment(snapshot.ps.dk3SoundEnvironment);
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
        bridge.holdView(player, transform.angles, input);
        const command = bridge.command(input, &player.delta_angles);
        var motion: @import("domain/slide.zig").State = .{ .position = transform.position, .velocity = velocity.linear };
        if (ailments.mask & 128 != 0) motion.velocity = @splat(0);
        var events: weapons.Events = .{};
        var weapon_context: weapons.Context = .{ .ps = loadout, .healthy = snapshot.ps.stats[c.STAT_HEALTH] > 0, .single_player = engine.integer("g_gametype") == c.GT_SINGLE_PLAYER, .table = &weapon_table, .events = &events, .service = engine.collisionService(), .slot = @intCast(client_number), .shot_mask = c.MASK_SHOT, .attack_boost = character.attribute(.attack, command.time_ms) };
        _ = try move.runWithHook(player, &motion, command, bridge.characterParameters(@intCast(client_number), character.*, ailments.*, command.time_ms), engine.collisionService(), weapon_context.hook());
        for (events.values[0..events.count], 0..) |event, i| switch (event) {
            .fired => |shot| weapon_view.fire(shot.weapon, loadout.event_sequence -% @as(u32, @intCast(events.count - i)), shot.command_ms),
            .no_ammo => {},
        };
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
    const psychic = @import("actor_catalog").psyclaw.visual(snapshot.ps.dk3PsyEnd, now);
    ref.fov_x = 90 + psychic.fov;
    ref.fov_y = std.math.atan(@tan(ref.fov_x * std.math.pi / 360) * @as(f32, @floatFromInt(ref.height)) / @as(f32, @floatFromInt(ref.width))) * 360 / std.math.pi;
    ref.vieworg = transform.position;
    ref.vieworg[2] += player.view_height;
    if (snapshot.ps.dk3CameraActive != 0) {
        ref.vieworg = snapshot.ps.dk3CameraOrigin;
        ref.fov_x = snapshot.ps.dk3CameraFov;
        ref.fov_y = std.math.atan(@tan(ref.fov_x * std.math.pi / 360) * @as(f32, @floatFromInt(ref.height)) / @as(f32, @floatFromInt(ref.width))) * 360 / std.math.pi;
    }
    const basis = v.basis(if (snapshot.ps.dk3CameraActive != 0) snapshot.ps.dk3CameraAngles else v.add(v.add(v.add(view_angles, @import("client/quake_kick.zig").offset(now)), .{ 0, 0, psychic.roll }), @import("client/area_effects.zig").shake(snapshot.entities[0..@intCast(snapshot.numEntities)], ref.vieworg, now)));
    ref.viewaxis[0] = basis.forward;
    ref.viewaxis[1] = v.scale(basis.right, -1);
    ref.viewaxis[2] = v.cross(ref.viewaxis[0], ref.viewaxis[1]);
    ref.areamask = snapshot.areamask;
    const lightstyles = try engine.config(&game, c.CS_DK3_LIGHTSTYLES);
    ref.dk3Lightstyles = if (lightstyles.len > 0) try @import("domain/lightstyles.zig").decode(lightstyles) else @splat(1);
    _ = engine.gateway.call(c.CG_R_CLEARSCENE, .{});
    _ = engine.gateway.call(c.CG_S_CLEARLOOPINGSOUNDS, .{@as(isize, c.qfalse)});
    var weapon_end_ms: ?i64 = null;
    for (snapshot.entities[0..@intCast(snapshot.numEntities)]) |entity| {
        if (entity.eType == c.ET_DK3_EFFECT) {
            if (entity.weapon == @import("weapon_catalog").metamaser.id) {
                try @import("client/metamaser.zig").draw(entity, snapshot.entities[0..@intCast(snapshot.numEntities)], now, &ref);
                continue;
            }
            try @import("client/weapon_effects.zig").draw(entity, now, &ref, client_number);
            if (entity.weapon == @import("weapon_catalog").novabeam.id and entity.otherEntityNum == client_number and entity.weapon == loadout.weapon and entity.frame == 3) weapon_end_ms = entity.time2;
            if (entity.weapon == @import("weapon_catalog").zeus.id and entity.otherEntityNum == client_number and entity.weapon == loadout.weapon and entity.frame == 100) weapon_end_ms = entity.time2;
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").thunderskeet.spray_tag) {
            const sprite = try @import("client/sprites.zig").register(@import("actor_catalog").thunderskeet.spray_model);
            @import("client/sprites.zig").drawPlane(sprite, 0, @import("engine/trajectory.zig").evaluate(entity.pos, now), entity.angles2[0], true, v.scale(ref.viewaxis[1], -1), ref.viewaxis[2], .{ 255, 255, 255, 115 });
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").shafts.render_tag and (entity.weapon == @intFromEnum(@import("actor_catalog").shafts.Kind.fletcher) or entity.weapon == @intFromEnum(@import("actor_catalog").shafts.Kind.harpy))) {
            const origin = @import("engine/trajectory.zig").evaluate(entity.pos, now);
            const glow = try @import("client/sprites.zig").register("models/global/we_flarered.sp2");
            @import("client/sprites.zig").draw(glow, 0, origin, 1, true, &ref);
            _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &origin, engine.floatArg(175), engine.floatArg(0.65), engine.floatArg(0.35), engine.floatArg(0.35) });
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").fireballs.render_tag and entity.weapon == @intFromEnum(@import("actor_catalog").fireballs.Kind.knight)) {
            const origin = @import("engine/trajectory.zig").evaluate(entity.pos, now);
            _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &origin, engine.floatArg(150), engine.floatArg(0.95), engine.floatArg(0.35), engine.floatArg(0.15) });
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").psyclaw.render_tag and entity.weapon == 0) {
            const sprite = try @import("client/sprites.zig").register("models/global/e_sflgreen.sp2");
            @import("client/sprites.zig").draw(sprite, 0, @import("engine/trajectory.zig").evaluate(entity.pos, now), 1, true, &ref);
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").gunners.render_tag) {
            try @import("client/gunner_bursts.zig").draw(&game, entity, snapshot.entities[0..@intCast(snapshot.numEntities)], now);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").sludge.render_tag) {
            const origin = @import("engine/trajectory.zig").evaluate(entity.pos, now);
            const glow = try @import("client/sprites.zig").register(@import("actor_catalog").sludge.glow);
            @import("client/sprites.zig").draw(glow, 0, origin, 2, true, &ref);
            _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &origin, engine.floatArg(300), engine.floatArg(0.5), engine.floatArg(1), engine.floatArg(0.5) });
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").missiles.render_tag) {
            const origin = @import("engine/trajectory.zig").evaluate(entity.pos, now);
            const kind = std.enums.fromInt(@import("actor_catalog").missiles.Kind, entity.weapon) orelse return error.InvalidActorMissile;
            const boar = kind == .battleboar;
            const glow = try @import("client/sprites.zig").register(@import("actor_catalog").missiles.glow(kind));
            @import("client/sprites.zig").draw(glow, 0, origin, if (boar) 0.75 else if (kind == .mp_left or kind == .mp_right) 1 else 1.45, true, &ref);
            _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &origin, engine.floatArg(if (boar) 115 else 145), engine.floatArg(0.75), engine.floatArg(if (boar) 0.15 else 0.45), engine.floatArg(0.15) });
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").knights.render_tag) {
            if (try @import("client/knights.zig").draw(entity, now, &ref)) continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").laser.render_tag) {
            try @import("client/actor_lasers.zig").draw(entity, now, &ref);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").deathsphere.bolt_tag) {
            try @import("client/deathbolts.zig").draw(&game, entity, now, &ref);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").cryotech.render_tag) {
            @import("client/cryo_spray.zig").draw(entity, now, &ref);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").meteors.render_tag) {
            if (try @import("client/actor_meteors.zig").draw(entity, now, &ref)) continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").wyndrax.render_tag) {
            if (try @import("client/wyndrax_actor.zig").draw(entity, now, &ref)) continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").wisp.render_tag) {
            try @import("client/wisps.zig").draw(entity, now, &ref);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").firefly.render_tag) {
            if (entity.frame < 0 or entity.frame >= @import("actor_catalog").firefly.models.len) return error.InvalidFireflyShape;
            const sprite = try @import("client/sprites.zig").register(@import("actor_catalog").firefly.models[@intCast(entity.frame)]);
            var color: [4]u8 = undefined;
            for (entity.origin2, color[0..3]) |axis, *channel| channel.* = @intFromFloat(std.math.clamp(axis, 0, 1) * 255);
            color[3] = @intCast(std.math.clamp(entity.time2, 0, 255));
            @import("client/sprites.zig").drawPlane(sprite, 0, @import("engine/trajectory.zig").evaluate(entity.pos, now), entity.angles2[0], false, v.scale(ref.viewaxis[1], -1), ref.viewaxis[2], color);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("domain/scenery.zig").explosion_tag) {
            const sprite = try @import("client/sprites.zig").register(try engine.config(&game, c.CS_MODELS + @as(usize, @intCast(entity.modelindex))));
            const point = @import("engine/trajectory.zig").evaluate(entity.pos, now);
            @import("client/sprites.zig").draw(sprite, @intCast(entity.frame), point, entity.angles2[0], false, &ref);
            _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &point, engine.floatArg(200), engine.floatArg(1), engine.floatArg(0.5), engine.floatArg(0) });
            continue;
        }
        if (entity.eType == c.ET_MISSILE and try @import("client/projectiles.zig").sprite(entity, now, &ref)) continue;
        if (entity.eType == c.ET_MISSILE and entity.weapon == @import("weapon_catalog").stavros.id) try @import("client/stavros.zig").draw(entity, now, &ref);
        if (entity.eType == c.ET_MISSILE and entity.weapon == @import("weapon_catalog").wyndrax.id) try @import("client/wyndrax.zig").draw(entity, snapshot.entities[0..@intCast(snapshot.numEntities)], now, &ref);
        if (entity.eType == c.ET_MISSILE and entity.weapon == @import("weapon_catalog").metamaser.id) try @import("client/metamaser.zig").draw(entity, snapshot.entities[0..@intCast(snapshot.numEntities)], now, &ref);
        if (entity.eType == c.ET_DK3_ITEM and entity.dk3Team != 0) {
            try @import("client/objectives.zig").draw(&game, entity, snapshot.entities[0..@intCast(snapshot.numEntities)], client_number, now);
            continue;
        }
        if (entity.eType == c.ET_PLAYER and entity.number == client_number) {
            try @import("client/events.zig").loop(&game, entity, @import("engine/trajectory.zig").evaluate(entity.pos, now));
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").nharre.reaper_tag) {
            try @import("client/nharre_reaper.zig").draw(entity, now, &ref);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").summon_effect.render_tag) {
            try @import("client/summon_effects.zig").draw(entity, now, &ref);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("domain/audio.zig").parameter_tag) {
            try @import("client/events.zig").loop(&game, entity, @import("engine/trajectory.zig").evaluate(entity.pos, now));
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("item_catalog").hosportal.render_tag) @import("client/healers.zig").draw(entity, now);
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("domain/laser.zig").render_tag) {
            try @import("client/events.zig").loop(&game, entity, @import("engine/trajectory.zig").evaluate(entity.pos, now));
            @import("client/lasers.zig").draw(entity, now, &ref);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("domain/target_effect.zig").render_tag) {
            @import("client/target_effects.zig").emit(entity, now);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("domain/weather.zig").render_tag) {
            @import("client/weather.zig").emit(entity, now, &ref);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("domain/lightning.zig").render_tag) {
            @import("client/lightning.zig").draw(entity, snapshot.entities[0..@intCast(snapshot.numEntities)], now, &ref);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("domain/complex_particles.zig").render_tag) {
            @import("client/complex_particles.zig").emit(entity, now);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("domain/lightstyles.zig").render_tag) {
            try @import("client/lights.zig").draw(&game, entity, now, &ref);
            continue;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("domain/spotlight.zig").render_tag) {
            try @import("client/spotlights.zig").draw(&game, entity, now, &ref);
            continue;
        }
        var handle: c.qhandle_t = 0;
        if ((entity.solid == c.SOLID_BMODEL or (entity.eType == c.ET_MOVER and entity.generic1 == @import("domain/debris.zig").render_tag)) and entity.modelindex > 0 and entity.modelindex < inline_models.len) {
            handle = inline_models[@intCast(entity.modelindex)];
        } else if (entity.eType == c.ET_PLAYER or entity.eType == c.ET_DK3_ITEM or entity.eType == c.ET_MISSILE or entity.eType == c.ET_GENERAL) handle = try @import("client/models.zig").get(&game, entity.modelindex);
        if (handle == 0) continue;
        var rendered = std.mem.zeroes(c.refEntity_t);
        rendered.hModel = handle;
        if (entity.eType == c.ET_PLAYER) rendered.customSkin = try @import("client/models.zig").playerSkin(&game, entity.clientNum);
        rendered.frame = entity.frame;
        rendered.oldframe = entity.frame;
        rendered.reType = c.RT_MODEL;
        rendered.origin = @import("engine/trajectory.zig").evaluate(entity.pos, now);
        rendered.oldorigin = rendered.origin;
        const orientation = v.basis(@import("engine/trajectory.zig").evaluate(entity.apos, now));
        rendered.axis[0] = orientation.forward;
        rendered.axis[1] = v.scale(orientation.right, -1);
        rendered.axis[2] = v.cross(rendered.axis[0], rendered.axis[1]);
        if (entity.eType == c.ET_GENERAL and entity.angles2[0] > 0 and entity.angles2[1] > 0 and entity.angles2[2] > 0) {
            for (&rendered.axis, entity.angles2) |*axis, scale| axis.* = v.scale(axis.*, scale);
            rendered.nonNormalizedAxes = c.qtrue;
        }
        rendered.shaderRGBA = @splat(255);
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("item_catalog").drugbox.render_tag) rendered.shaderRGBA[3] = @intCast(std.math.clamp(entity.time2, 0, 255));
        if (entity.generic1 == @import("actor_catalog").medusa.stone_tag) {
            rendered.shaderRGBA[3] = 179;
            rendered.skinNum = 3;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("domain/scenery.zig").render_tag) {
            if (entity.weapon & 1 != 0) @import("client/gibs.zig").emit(entity, rendered.origin, now);
            rendered.shaderRGBA[3] = @intCast(std.math.clamp(entity.time2, 0, 255));
            if (entity.clientNum > 0) rendered.customShader = try @import("client/models.zig").firstMaterial(&game, entity.clientNum, if (rendered.shaderRGBA[3] < 255) .alpha else .ordinary);
        }
        if (entity.eType == c.ET_GENERAL and entity.time2 == @import("actor_catalog").kage.fade_tag) rendered.shaderRGBA[3] = @min(rendered.shaderRGBA[3], @as(u8, @intFromFloat(std.math.clamp(entity.origin2[0], 0, 1) * 255)));
        if (entity.eType == c.ET_GENERAL and entity.time2 == @import("actor_catalog").sword_aura_tag and entity.legsAnim == 1) rendered.shaderRGBA[3] = @min(rendered.shaderRGBA[3], @as(u8, @intCast(@divTrunc(std.math.clamp(entity.torsoAnim, 0, 1000) * 255, 1000))));
        if (entity.eType == c.ET_GENERAL and entity.time2 == @import("actor_catalog").buboid.melt_tag) {
            rendered.shaderRGBA[3] = @intFromFloat(std.math.clamp(entity.origin2[0], 0, 1) * 255);
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").dwarf.axe_tag) rendered.shaderRGBA[3] = @intCast(std.math.clamp(@divTrunc((@as(i64, entity.time2) - now) * 255, 1000), 0, 255));
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").shafts.render_tag and entity.time2 > 0) rendered.shaderRGBA[3] = @intCast(std.math.clamp(@divTrunc((@as(i64, entity.time2) - now) * 255, 1000), 0, 255));
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").psyclaw.render_tag) {
            for (entity.origin2, rendered.shaderRGBA[0..3]) |axis, *channel| channel.* = @intFromFloat(std.math.clamp(axis, 0, 1) * 255);
            rendered.shaderRGBA[3] = 115;
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").fireballs.render_tag and entity.weapon == @intFromEnum(@import("actor_catalog").fireballs.Kind.dragon)) {
            rendered.shaderRGBA = .{ 217, 64, 13, 77 };
            @import("client/dragon.zig").fireball(entity, now);
        }
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").wyndrax.render_tag) rendered.shaderRGBA[3] = @intFromFloat(std.math.clamp(entity.origin2[0], 0, 1) * 255);
        if (entity.eType == c.ET_MISSILE) try @import("client/projectiles.zig").decorate(&rendered, entity, now);
        // Converted MD3 surfaces carry ordinary/alpha/bright/alpha-bright
        // variants. Selecting alpha preserves each surface's own authored skin.
        if ((entity.eType == c.ET_GENERAL or entity.eType == c.ET_MISSILE) and rendered.shaderRGBA[3] < 255 and std.mem.endsWith(u8, try engine.config(&game, c.CS_MODELS + @as(usize, @intCast(entity.modelindex))), ".dkm")) rendered.skinNum = if (entity.generic1 == @import("actor_catalog").medusa.stone_tag) 3 else 1;
        try @import("client/events.zig").loop(&game, entity, rendered.origin);
        _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&rendered});
        if (entity.eType == c.ET_PLAYER or (entity.eType == c.ET_GENERAL and entity.time2 == @import("actor_catalog").companions.render_tag)) try @import("client/held_weapons.zig").draw(&rendered, entity.weapon);
        if (entity.eType == c.ET_GENERAL and (entity.time2 == @import("actor_catalog").cambot.idle_tag or entity.time2 == @import("actor_catalog").cambot.alert_tag)) try @import("client/cambot.zig").draw(&rendered, entity.time2 == @import("actor_catalog").cambot.alert_tag, &ref);
        if (entity.eType == c.ET_GENERAL and entity.time2 == @import("actor_catalog").battleboar.flash_tag) try @import("client/battleboar.zig").draw(&rendered);
        if (entity.eType == c.ET_GENERAL and entity.time2 == @import("actor_catalog").rockgat.flash_tag) try @import("client/rockgat.zig").draw(&rendered);
        if (entity.eType == c.ET_GENERAL and entity.time2 == @import("actor_catalog").buboid.melt_tag) @import("client/buboid.zig").emit(&rendered, entity, now);
        if (entity.eType == c.ET_GENERAL and entity.time2 == @import("actor_catalog").sword_aura_tag) try @import("client/sword_aura.zig").draw(&rendered, entity, now, &ref);
        if (entity.eType == c.ET_GENERAL and entity.time2 == @import("actor_catalog").chaingang.jet_tag) @import("client/chaingang.zig").emit(&rendered, entity, now);
        if (entity.eType == c.ET_GENERAL and entity.time2 == @import("actor_catalog").dragon.breath_tag) try @import("client/dragon.zig").breath(&rendered, entity, now);
        if (entity.eType == c.ET_GENERAL and entity.time2 == @import("actor_catalog").medusa.gaze_tag and entity.origin2[0] != 0) try @import("client/medusa.zig").eyes(&rendered, &ref);
        if (entity.eType == c.ET_GENERAL and entity.generic1 == @import("actor_catalog").rotworm.spit_tag) @import("client/venom_spit.zig").draw(entity, now);
        if (entity.eType == c.ET_GENERAL and entity.generic1 > 0 and entity.generic1 <= 1000) try @import("client/status_visuals.zig").frost(rendered, @as(f32, @floatFromInt(entity.generic1)) / 1000);
    }
    if (snapshot.ps.dk3CameraActive != 0) @import("client/cinematics.zig").audio(ref.vieworg);
    @import("client/impacts.zig").draw(now, &ref);
    @import("client/fx_particles.zig").draw(now, &ref);
    if (player.mode == .normal and snapshot.ps.stats[c.STAT_HEALTH] > 0) try weapon_view.draw(loadout.*, character.*, &ref, client_number, now, weapon_end_ms);
    _ = engine.gateway.call(c.CG_R_RENDERSCENE, .{&ref});
    if (snapshot.ps.dk3CameraActive != 0) {
        @import("client/cinematics.zig").overlay(snapshot.ps.dk3CameraBlend, display);
    } else {
        @import("client/status_visuals.zig").screen(ailments.*, display);
        @import("client/status_visuals.zig").psychic(psychic.blend, display);
        @import("client/medusa.zig").flash(snapshot.entities[0..@intCast(snapshot.numEntities)], client_number, now, display);
        try hud.render(display, .{ .current = snapshot.ps.stats[c.STAT_HEALTH], .armor = snapshot.ps.stats[c.STAT_ARMOR] }, character.*, .{ .mask = @bitCast(snapshot.ps.dk3Keys), .quest = @bitCast(snapshot.ps.dk3Quest) }, loadout.*, &weapon_table, selected_weapon, now);
    }
    _ = engine.gateway.call(c.CG_S_RESPATIALIZE, .{ @as(isize, client_number), &ref.vieworg, &ref.viewaxis, @as(isize, @intFromBool(player.water_level == 3)) });
    @import("client/messages.zig").render(hud.font, display, now);
    try @import("client/scoreboard.zig").render(hud.font, display, &game, &snapshot.ps, now);
}
fn console() isize {
    var buffer: [128]u8 = @splat(0);
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 0), &buffer, @as(isize, buffer.len) });
    const name = std.mem.sliceTo(&buffer, 0);
    if (world == null or !have_snapshot) return 0;
    if (@import("client/scoreboard.zig").input(name)) return 1;
    if (hud.command(name)) return 1;
    if (std.mem.eql(u8, name, "weapon")) {
        _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 1), &buffer, @as(isize, buffer.len) });
        const id = std.fmt.parseInt(u5, std.mem.sliceTo(&buffer, 0), 10) catch return 1;
        if (@import("weapon_catalog").find(id)) |entry| if (@as(u32, @bitCast(snapshot.ps.dk3Inventory)) & (@as(u32, 1) << id) != 0) {
            if (selected_weapon == id and snapshot.ps.weapon == id) if (entry.spec.reselect_command) |command| {
                _ = engine.gateway.call(c.CG_SENDCLIENTCOMMAND, .{command.ptr});
                weapon_view.reselect();
            };
            selected_weapon = id;
        };
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
