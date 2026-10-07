// SPDX-License-Identifier: GPL-2.0-or-later
//! Replacement module entrypoint. Bootstrap probes are explicit, never gameplay fallback.
const std = @import("std");
const abi = @import("engine/abi.zig");
const engine = @import("engine/server.zig");
const c = abi.c;
const component = @import("domain/components.zig");
const map = @import("server/map.zig");
const Pool = @import("ecs/jobs.zig").Pool;
const Context = @import("server/world_context.zig").Context;
var initial_context: Context = .{};
var active: *Context = &initial_context;
var social: @import("server/social.zig").State = .{};
var rooms: @import("server/rooms.zig").State = .{};
var pool: ?*Pool = null;
var clock: @import("domain/time.zig").Clock = .{ .now_ms = 0 };
const persistence = @import("server/persistence.zig");
const campaign_module = @import("server/campaign.zig");
var campaign: campaign_module.State = .{};
var restoring_visit = false;
const checkpoint_rules = @import("domain/checkpoint.zig");
var checkpoint: checkpoint_rules.State = .{};
var autosave: checkpoint_rules.Autosave = .{};
var resident_worlds: @import("server/resident_worlds.zig").State = .{};
var demote_ms: i64 = 0;
var progression: @import("server/region_progression.zig").State = .{};
/// Scripted co-op verification bot; module-global so it survives region travel.
var coop: @import("server/coop_bot.zig").Driver = .{};

export fn dllEntry(callback: abi.Syscall) callconv(.c) void {
    engine.gateway.bind(callback);
}
fn shutdown(restart: bool) void {
    engine.config_observer = null;
    @import("server/region_access.zig").region = null;
    @import("server/companion_pilot.zig").reset();
    demote_ms = 0;
    // Engine bot client slots outlive a fast VM restart. Release their input
    // owners before unloading; the new match population admits fresh bots.
    if (restart) if (active.world) |*value| for (active.bots.brains, 0..) |brain, index| {
        if (brain != null) active.bots.remove(value, &active.slots, &active.projection, &active.clients, index, clock.now_ms) catch |err| runtimeFailure(err);
    };
    if (active.world) |*value| rooms.checkpoint(value, &active.clients) catch |err| runtimeFailure(err);
    coop.deinit();
    active = &initial_context;
    active.running = false;
    active.configuration.deinit();
    if (active.handle) |handle| @import("engine/worlds.zig").select(handle) catch {};
    _ = @import("server/resources.zig").select(&active.resources);
    resident_worlds.deinit();
    progression.deinit();
    campaign.deinit();
    restoring_visit = false;
    checkpoint = .{};
    autosave = .{};
    if (active.restore_pending) |*saved| saved.deinit(std.heap.c_allocator);
    active.restore_pending = null;
    active.systems.deinit(restart);
    if (pool) |workers| workers.destroy();
    pool = null;
    if (active.world) |*value| value.deinit();
    active.world = null;
    if (active.restored_arena) |strings| {
        strings.deinit();
        std.heap.c_allocator.destroy(strings);
    }
    active.restored_arena = null;
    if (active.arena) |*value| value.deinit();
    active.arena = null;
    active.handle = null;
}
fn init(now: i64, restart: bool) !void {
    shutdown(restart);
    engine.register("dk3_runtime_probe", "0", 0);
    if (engine.integer("dk3_runtime_probe") < 1 or engine.integer("dk3_runtime_probe") > 2) return error.ReplacementGameplayNotQualified;
    var defaults: [12]u8 = undefined;
    const worker_default = try std.fmt.bufPrintZ(&defaults, "{d}", .{Pool.defaultWorkers()});
    engine.register("dk3_jobs", worker_default, c.CVAR_ARCHIVE | c.CVAR_LATCH);
    const jobs = engine.integer("dk3_jobs");
    if (jobs < 0 or jobs > 8) return error.WorkerLimit;
    active.arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    errdefer shutdown(false);
    active.world = component.World.initNamespaced(std.heap.c_allocator, 1024, 0);
    active.handle = @import("engine/worlds.zig").current();
    active.network_id = 0;
    @import("server/region_access.zig").region = .{ .initial = &initial_context, .residents = &resident_worlds, .manifest = &progression.manifest };
    engine.config_observer = @import("server/configuration.zig").changed;
    active.activated = true;
    active.stepped_at = now;
    _ = engine.mapName(&active.map_name);
    pool = try Pool.create(std.heap.c_allocator, @intCast(jobs));
    @memset(std.mem.asBytes(&active.projection), 0);
    @memset(std.mem.asBytes(&active.players), 0);
    for (&active.projection, 0..) |*entity, i| {
        entity.state.number = @intCast(i);
        entity.shared.ownerNum = c.ENTITYNUM_NONE;
    }
    clock = .{ .now_ms = now };
    active.slots = .{};
    active.presentation = .{};
    active.clients = .{};
    active.bots = .{};
    social = .{};
    active.systems = .{};
    active.targets = .{};
    _ = @import("server/resources.zig").select(&active.resources);
    @import("server/resources.zig").reset();
    if (engine.integer("dk3_runtime_probe") == 2) {
        const bytes = try @import("engine/files.zig").read(.server, &engine.gateway, std.heap.c_allocator, "dk3/tables/weapons.cfg", 4 * 1024 * 1024);
        defer std.heap.c_allocator.free(bytes);
        active.clients.weapon_table = try @import("domain/weapons.zig").Table.parse(bytes);
        var map_name: [c.MAX_QPATH]u8 = @splat(0);
        _ = engine.mapName(&map_name);
        if (map_name[0] == 'e' and map_name[1] >= '1' and map_name[1] <= '4') active.clients.episode = map_name[1] - '0';
    }
    engine.locate(&active.projection, &active.players);
    engine.config(c.CS_GAME_VERSION, @import("engine/player_state.zig").version);
    engine.config(c.CS_DK3_SKY, "1");
    engine.register("g_gametype", "2", c.CVAR_SERVERINFO);
    engine.register("sv_violence", "0", c.CVAR_SERVERINFO | c.CVAR_ARCHIVE | c.CVAR_LATCH);
    engine.register("gib_enable", "1", c.CVAR_ARCHIVE);
    engine.register("p_sendparticles", "0", 0);
    engine.register("dm_item_respawn", "1", c.CVAR_SERVERINFO | c.CVAR_LATCH);
    engine.register("dm_weapons_stay", "0", c.CVAR_SERVERINFO | c.CVAR_LATCH);
    engine.register("dm_use_skill_system", "1", c.CVAR_ARCHIVE);
    engine.register("dm_levellimit", "0", c.CVAR_SERVERINFO | c.CVAR_LATCH);
    while (try map.read(active.arena.?.allocator(), engine)) |object| {
        if (std.mem.eql(u8, object.binding.classname, "worldspawn")) {
            var loadscreen: [64]u8 = undefined;
            const name = @import("server/properties.zig").text(object.binding, "loadscreen") orelse "";
            engine.config(c.CS_DK3_LOADSCREEN, try std.fmt.bufPrintZ(&loadscreen, "{s}", .{name}));
        }
        _ = try active.world.?.create(null, .{ object.binding, object.transform });
    }
    if (engine.integer("dk3_runtime_probe") == 2) {
        try active.systems.spawn(active.arena.?.allocator(), &active.world.?, &active.slots, &active.projection, now, active.clients.episode, &active.clients.weapon_table, restart, false);
        active.targets.scripts = &active.systems.scripts;
        active.targets.cinematics = &active.systems.cinematics;
        active.targets.actors = &active.systems.actors;
        if (engine.integer("dk3_resume") == 1) {
            _ = engine.gateway.call(c.G_CVAR_SET, .{ @as([*:0]const u8, "dk3_resume"), @as([*:0]const u8, "0") });
            var loaded = try persistence.prepare("dk3-resume-internal", false);
            errdefer loaded.deinit(std.heap.c_allocator);
            var name: [64]u8 = undefined;
            if (!std.mem.eql(u8, loaded.map, persistence.mapName(&name))) return error.SaveMapMismatch;
            const checksum: u32 = @truncate(@as(usize, @bitCast(engine.gateway.call(c.G_DK3_WORLD_CHECKSUM_V1, .{}))));
            if (loaded.header.asset_crc != 0 and loaded.header.asset_crc != checksum) return error.SaveAssetMismatch;
            try persistence.admit(&loaded, &active.systems);
            active.restore_pending = loaded;
        } else if (engine.integer("dk3_travel_pending") == 1) {
            _ = engine.gateway.call(c.G_CVAR_SET, .{ @as([*:0]const u8, "dk3_travel_pending"), @as([*:0]const u8, "0") });
            var transfer = try persistence.prepare("dk3-travel-internal", false);
            defer transfer.deinit(std.heap.c_allocator);
            var name: [64]u8 = undefined;
            var prepared = try campaign_module.prepare(&transfer, persistence.mapName(&name), now, &active.clients.weapon_table);
            errdefer {
                prepared.state.deinit();
                if (prepared.world) |*saved| saved.deinit(std.heap.c_allocator);
            }
            if (prepared.world) |*saved| try persistence.admit(saved, &active.systems);
            campaign = prepared.state;
            active.restore_pending = prepared.world;
            restoring_visit = true;
        }
    }
    try rooms.init();
    if (engine.integer("dk3_runtime_probe") == 2) try progression.init();
    // A save restores its map's own seamless region before play; the other
    // maps it carries stay dormant until travel or prefetch wants them.
    if (active.restore_pending) |*saved| if (progression.manifest.count != 0) try resident_worlds.retainRegion(saved, &progression.manifest);
    // Publish the saved resource registry while the engine is still loading the
    // map. The initial gamestate must contain these identities; replacing them
    // at ClientBegin can overflow reliable commands before any acknowledgement.
    // Bounded regional patches start only once the traveler has that gamestate
    // (beginClient): until then a change is simply part of it, and marking it
    // pending would hide every entity using it until a patch drained.
    if (active.restore_pending) |*saved| {
        try @import("server/resources.zig").restore(saved.header.resources);
        // Complete immutable mover bindings before the engine sends the first
        // gamestate. Registering them only during projection can leave an old
        // save's first press ahead of its sound configstring.
        try @import("server/movers.zig").restoreSounds(&saved.world);
    }
    var text: [160]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig: isolated bootstrap, {d} map entities, {d} workers; gameplay not qualified\n", .{ active.world.?.count(), jobs }));
    coop.configure();
}
/// Ownership transfers only after all admission/rebasing checks have succeeded.
fn restore(loaded: *@import("domain/snapshot.zig").Loaded, visit: bool) !void {
    // Companion planning is transient: a restored party plans afresh.
    @import("server/companion_pilot.zig").reset();
    // Earlier native schema-1 snapshots predate exit latches. Reconstruct their
    // default from authored metadata without replacing an already saved latch.
    try campaign_module.spawn(&loaded.world);
    try @import("server/monitors.zig").spawn(&loaded.world);
    try @import("server/attachments.zig").reconcile(&loaded.world);
    try persistence.admit(loaded, &active.systems);
    try loaded.rebase(clock.now_ms);
    var staged_campaign = if (!visit) try campaign_module.State.fromArchives(loaded.visited) else null;
    errdefer if (staged_campaign) |*state| state.deinit();
    try resident_worlds.restoreMembers(loaded, clock.now_ms);
    for (&active.projection) |*entity| if (entity.shared.linked != 0) engine.unlink(entity);
    active.world.?.deinit();
    if (active.restored_arena) |strings| {
        strings.deinit();
        std.heap.c_allocator.destroy(strings);
    }
    active.world = loaded.world;
    active.stepped_at = clock.now_ms;
    active.restored_arena = loaded.arena;
    const header = loaded.header;
    loaded.* = undefined;
    // Remaining work publishes admitted state; unexpected invariant failures are
    // runtime errors, never a partially successful load reported to the player.
    @import("server/resources.zig").restore(header.resources) catch |err| runtimeFailure(err);
    active.systems.actors.prepareParty() catch |err| runtimeFailure(err);
    active.targets = .{ .pending = header.pending, .scripts = &active.systems.scripts, .cinematics = &active.systems.cinematics, .actors = &active.systems.actors };
    persistence.project(&active.world.?, &active.slots, &active.projection, &active.clients, &active.players, &active.systems, header, clock.now_ms) catch |err| runtimeFailure(err);
    try active.auditRestore(clock.now_ms);
    if (staged_campaign) |state| {
        campaign.deinit();
        campaign = state;
    }
    resident_worlds.legacy_archives = campaign.visited;
    resident_worlds.traveler_id = header.player_id;
    if (!visit) {
        autosave.completed(clock.now_ms);
        if (saveRegion(checkpoint_rules.slot)) |_| {
            checkpoint.saved();
            engine.print("dk3 checkpoint: ready\n");
        } else |err| {
            saveFeedback(err);
            checkpoint = .{ .pending = false };
        }
    }
    const restored_loadout = (try active.world.?.get(active.world.?.find(header.player_id).?, component.Weapons)).*;
    var restoration: [128]u8 = undefined;
    if (restored_loadout.weaponstate == @import("weapon_catalog").transitions.state.firing and restored_loadout.last_fire_ms != null) {
        engine.send(0, try std.fmt.bufPrintZ(&restoration, "dk3_restored {d} {d} {d}", .{ restored_loadout.weapon, restored_loadout.event_sequence -% 1, restored_loadout.last_fire_ms.? }));
    } else engine.send(0, "dk3_restored");
    var restored_message: [96]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&restored_message, "dk3 zig: saved world restored health={d}\n", .{(try active.world.?.get(active.world.?.find(header.player_id).?, component.Health)).current}));
}
fn saveCommand(command: []const u8) !bool {
    const saving = std.mem.eql(u8, command, "save");
    if (!saving and !std.mem.eql(u8, command, "load")) return false;
    if (engine.integer("g_gametype") != c.GT_SINGLE_PLAYER) return error.SaveRequiresSinglePlayer;
    var argument: [64]u8 = undefined;
    var option: [32]u8 = undefined;
    const slot = engine.argv(1, &argument);
    if (!@import("domain/snapshot.zig").validName(slot) or std.mem.startsWith(u8, slot, "dk3-")) return error.InvalidSaveSlot;
    if (saving) {
        if (progression.held or active.restore_pending != null) return error.RegionAdmissionInProgress;
        try saveRegion(slot);
        rememberCheckpoint(slot, false) catch |err| saveFeedback(err);
        engine.print("dk3 zig: world saved\n");
    } else {
        const extra = engine.argv(2, &option);
        const previous = std.mem.eql(u8, extra, "previous");
        if (extra.len != 0 and !previous) return error.InvalidSaveOption;
        try loadSlot(slot, previous);
    }
    return true;
}
fn saveRegion(slot: []const u8) !void {
    var scratch = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer scratch.deinit();
    const members = try resident_worlds.captureOthers(scratch.allocator(), &initial_context, active);
    var cold: std.ArrayList(@import("domain/snapshot.zig").Archive) = .empty;
    archives: for (campaign.visited) |archive| {
        if (std.mem.eql(u8, archive.map, std.mem.sliceTo(&active.map_name, 0))) continue;
        for (members) |member| if (std.mem.eql(u8, archive.map, member.map)) continue :archives;
        try cold.append(scratch.allocator(), archive);
    }
    try persistence.save(&active.world.?, &active.clients, &active.targets, &active.systems, slot, clock.now_ms, cold.items, members);
}
fn loadSlot(slot: []const u8, previous: bool) !void {
    var loaded = try persistence.prepare(slot, previous);
    var owned = true;
    defer if (owned) loaded.deinit(std.heap.c_allocator);
    var name: [64]u8 = undefined;
    if (loaded.residents.len == 0 and !resident_worlds.hasGameplay() and std.mem.eql(u8, loaded.map, persistence.mapName(&name)) and @import("server/resources.zig").canRestoreInPlace(loaded.header.resources)) {
        try restore(&loaded, false);
        owned = false;
    } else {
        // A different map or resource registry needs a fresh gamestate.
        // Decode completely before restarting; the existing atomic save
        // service owns the internal transfer file.
        const bytes = try @import("engine/save_storage.zig").read(std.heap.c_allocator, slot, previous);
        defer std.heap.c_allocator.free(bytes);
        try @import("engine/save_storage.zig").write("dk3-resume-internal", bytes, false);
        _ = engine.gateway.call(c.G_CVAR_SET, .{ @as([*:0]const u8, "dk3_resume"), @as([*:0]const u8, "1") });
        _ = engine.gateway.call(c.G_CVAR_SET, .{ @as([*:0]const u8, "dk3_travel_pending"), @as([*:0]const u8, "0") });
        var text: [160]u8 = undefined;
        const next = try std.fmt.bufPrintZ(&text, "set g_spSkill {d}\nmap {s}\n", .{ loaded.skill, loaded.map });
        _ = engine.gateway.call(c.G_SEND_CONSOLE_COMMAND, .{ @as(isize, c.EXEC_APPEND), next.ptr });
    }
}
fn saveFeedback(err: anyerror) void {
    var buffer: [160]u8 = undefined;
    const message = std.fmt.bufPrintZ(&buffer, "Save/load refused: {s}\n", .{@errorName(err)}) catch unreachable;
    engine.print(message);
    _ = engine.gateway.call(c.G_CVAR_SET, .{ @as([*:0]const u8, "com_errorMessage"), message.ptr });
}
fn rememberCheckpoint(slot: []const u8, previous: bool) !void {
    if (!std.mem.eql(u8, slot, checkpoint_rules.slot)) {
        const bytes = try @import("engine/save_storage.zig").read(std.heap.c_allocator, slot, previous);
        defer std.heap.c_allocator.free(bytes);
        try @import("engine/save_storage.zig").write(checkpoint_rules.slot, bytes, false);
    }
    checkpoint.saved();
    coop.checkpointSaved();
    engine.print("dk3 checkpoint: ready\n");
}
fn recovery() !void {
    if (engine.integer("g_gametype") != c.GT_SINGLE_PLAYER or active.restore_pending != null or campaign.departing or active.targets.travel != null) return;
    const entity = active.clients.entities[0] orelse return;
    const player = (try active.world.?.get(entity, component.Player)).*;
    const alive = (try active.world.?.get(entity, component.Health)).current > 0;
    const playable = alive and player.mode == .normal and player.command_ms > 0 and !@import("server/cinematics.zig").active(&active.world.?) and !progression.held;
    const periodic_due = autosave.due(clock.now_ms);
    const health = (try active.world.?.get(entity, component.Health)).*;
    const arrival_due = checkpoint.pending and checkpoint_rules.Autosave.arrivalAdmits(health.current, health.maximum, checkpoint.available);
    if (playable and clock.now_ms >= autosave.retry_ms and (arrival_due or (!checkpoint.pending and periodic_due and try @import("server/companions.zig").healthyParty(&active.world.?, entity)))) {
        const slot = if (checkpoint.pending) checkpoint_rules.arrival_slot else checkpoint_rules.periodic_slot;
        // Advance the deadline only after the atomic write has completed. Failed
        // storage is retried with a bound rather than once per simulation frame.
        autosave.retry_ms = clock.now_ms + 5000;
        try saveRegion(slot);
        try rememberCheckpoint(slot, false);
        autosave.completed(clock.now_ms);
        var message: [128]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 autosave: saved slot={s} now={d}\n", .{ slot, clock.now_ms }));
    }
    var input: c.usercmd_t = undefined;
    engine.usercmd(0, &input);
    if (checkpoint.wantsRestart(alive, input.buttons & c.BUTTON_ATTACK != 0 or input.upmove > 0, clock.now_ms)) {
        if (!checkpoint.available) {
            engine.send(0, "cp \"No death checkpoint available. Load a saved game.\"");
            return;
        }
        engine.print("dk3 checkpoint: restoring after death\n");
        try loadSlot(checkpoint_rules.slot, false);
    }
}
fn probeMotion() !void {
    const movement = @import("server/motion.zig");
    const w = if (active.world) |*value| value else return error.NotInitialized;
    var created: [128]@import("ecs/world.zig").Entity = undefined;
    var count: usize = 0;
    defer for (created[0..count]) |entity| {
        if (active.slots.find(entity)) |slot| active.slots.release(slot, entity) catch unreachable;
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
        (try w.get(entity.*, component.Binding)).slot = try active.slots.acquire(entity.*, null);
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
    if (std.mem.eql(u8, command, "dk3_runtime_enter_world")) {
        enterWorld(engine.argv(1, &buffer)) catch |err| {
            var message: [160]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "dk3 world transfer: failed={s}\n", .{@errorName(err)}) catch unreachable);
        };
        return 1;
    }
    if (std.mem.eql(u8, command, "dk3_runtime_resident")) {
        resident_worlds.command() catch |err| {
            var message: [128]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "dk3 resident: failed {s}\n", .{@errorName(err)}) catch unreachable);
        };
        return 1;
    }
    if (@import("server/multiplayer.zig").enabled() and std.mem.eql(u8, command, "addbot")) {
        active.bots.add(&active.world.?, &active.slots, &active.projection, &active.players, &active.clients, clock.now_ms) catch |err| runtimeFailure(err);
        return 1;
    }
    if (std.mem.eql(u8, command, "dk3_runtime_observe")) {
        @import("server/observation.zig").report(&active.world.?, active.clients.entities[0], clock.now_ms) catch |err| runtimeFailure(err);
        return 1;
    }
    if (std.mem.eql(u8, command, "dk3_runtime_match")) {
        active.bots.report(&active.world.?, &active.slots, &active.clients, clock.now_ms) catch |err| runtimeFailure(err);
        @import("server/observation.zig").match(&active.world.?, clock.now_ms) catch |err| runtimeFailure(err);
        return 1;
    }
    if (std.mem.eql(u8, command, "dk3_runtime_pickup_routes")) {
        @import("server/navigation_probe.zig").pickupRoutes(&active.world.?, &active.slots, active.systems.navigation.service()) catch |err| runtimeFailure(err);
        return 1;
    }
    if (std.mem.eql(u8, command, "dk3_runtime_route")) {
        @import("server/navigation_probe.zig").route() catch |err| {
            var message: [128]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "dk3 route failed: {s}\n", .{@errorName(err)}) catch unreachable);
        };
        return 1;
    }
    if (std.mem.eql(u8, command, "dk3_runtime_navigation_coverage")) {
        // dk3_runtime_navigation_coverage [grid step] [jump height]
        var value: [32]u8 = undefined;
        const step = std.fmt.parseFloat(f32, engine.argv(1, &value)) catch 16;
        const jump = std.fmt.parseFloat(f32, engine.argv(2, &value)) catch 33;
        @import("server/navigation_coverage.zig").run(&active.world.?, &active.projection, .{ .step = step, .jump = jump }) catch |err| {
            var message: [128]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "dk3 navcover: failed {s}\n", .{@errorName(err)}) catch unreachable);
        };
        return 1;
    }
    if (std.mem.eql(u8, command, "dk3_runtime_route_controls")) {
        for (active.clients.entities) |maybe| if (maybe) |entity| {
            const pose = (active.world.?.get(entity, component.Transform) catch continue).*;
            const toward = @import("domain/vector.zig").add(pose.position, @import("domain/vector.zig").scale(@import("domain/vector.zig").basis(pose.angles).forward, 80));
            @import("server/bot_routes.zig").diagnose(&active.world.?, &active.slots, &active.projection, entity, toward, active.systems.navigation.service(), clock.now_ms) catch |err| runtimeFailure(err);
        };
        engine.print("dk3 route controls complete\n");
        return 1;
    }
    if (saveCommand(command) catch |err| {
        saveFeedback(err);
        return 1;
    }) return 1;
    if (engine.integer("dk3_runtime_probe") == 2) {
        if (std.mem.eql(u8, command, "dk3_runtime_chase")) {
            if (active.clients.entities[0]) |player| @import("server/navigation_probe.zig").chase(&active.world.?, player, clock.now_ms) catch |err| {
                var message: [128]u8 = undefined;
                engine.print(std.fmt.bufPrintZ(&message, "dk3 zig navigation fixture failed: {s}\n", .{@errorName(err)}) catch unreachable);
            };
            return 1;
        }
        if (std.mem.eql(u8, command, "dk3_runtime_world")) {
            @import("server/world_probe.zig").diagnostics(&active.world.?, &active.slots, &active.projection) catch |err| runtimeFailure(err);
            return 1;
        }
        if (std.mem.eql(u8, command, "dk3_runtime_actors")) {
            @import("server/actors.zig").diagnostics(&active.systems.actors, &active.world.?, &active.slots, clock.now_ms) catch |err| runtimeFailure(err);
            return 1;
        }
        if (std.mem.eql(u8, command, "dk3_runtime_performers")) {
            @import("server/cinematics.zig").diagnostics(&active.world.?, clock.now_ms) catch |err| runtimeFailure(err);
            return 1;
        }
        if (@import("server/actor_probe.zig").command(command, active, clock.now_ms) catch |err| blk: {
            var message: [128]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "dk3 actor probe failed: {s}\n", .{@errorName(err)}) catch unreachable);
            break :blk true;
        }) return 1;
        if (@import("server/combat_probe.zig").command(command, &active.world.?, &active.slots, &active.projection, active.clients.entities[0], &active.clients.weapon_table, clock.now_ms) catch |err| blk: {
            var message: [128]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "dk3 zig combat probe failed: {s}\n", .{@errorName(err)}) catch unreachable);
            break :blk true;
        }) return 1;
    }
    if (std.mem.eql(u8, command, "dk3_runtime_probe_motion")) {
        probeMotion() catch |err| {
            var failure: [128]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&failure, "dk3 zig probe failed: {s}\n", .{@errorName(err)}) catch unreachable);
        };
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_items")) {
        for (active.slots.occupants) |occupant| {
            const entity = occupant orelse continue;
            const pickup = active.world.?.get(entity, component.Pickup) catch continue;
            const object = (active.world.?.get(entity, component.MapObject) catch unreachable).*;
            const transform = (active.world.?.get(entity, component.Transform) catch unreachable).*;
            const motion = (active.world.?.get(entity, component.ItemMotion) catch unreachable).*;
            var message: [256]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "zig item id={d} class={s} visible={d} ground={?d} pos={d:.2},{d:.2},{d:.2}\n", .{ active.world.?.persistentId(entity) catch unreachable, object.classname, @intFromBool(pickup.visible), motion.ground, transform.position[0], transform.position[1], transform.position[2] }) catch unreachable);
        }
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_config_pending")) {
        // Entities withheld from snapshots until a configstring they use has
        // finished bounded publication (invisible to the client meanwhile).
        var entities: usize = 0;
        for (active.slots.occupants, 0..) |maybe, slot| if (maybe != null) {
            if (active.projection[slot].shared.svFlags & c.SVF_DK3_CONFIG_PENDING != 0) entities += 1;
        };
        var indices: usize = 0;
        for (active.configuration.dirty) |dirty| indices += @intFromBool(dirty);
        var message: [160]u8 = undefined;
        engine.print(std.fmt.bufPrintZ(&message, "dk3 config pending: entities={d} indices={d} sent={d} acknowledged={d}\n", .{ entities, indices + @intFromBool(active.configuration.pending != null), active.configuration.sent, active.configuration.acknowledged }) catch unreachable);
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_damage")) {
        // Diagnostic: `dk3_runtime_damage <amount> [mikiko|superfly]` hurts the
        // player, or the named companion of the player's party.
        const player = active.clients.entities[0] orelse return 1;
        var argument: [64]u8 = undefined;
        const amount = std.fmt.parseInt(i32, engine.argv(1, &argument), 10) catch return 1;
        if (amount <= 0 or amount > 10000) return 1;
        var who: [32]u8 = undefined;
        const name = engine.argv(2, &who);
        var target_world = &active.world.?;
        var entity = player;
        if (name.len != 0) {
            const identity = std.meta.stringToEnum(@import("actor_catalog").companions.Identity, name) orelse return 1;
            const owner = active.world.?.persistentId(player) catch unreachable;
            const member = @import("server/companions.zig").member(&active.world.?, identity, owner) orelse return 1;
            target_world = member.world;
            entity = member.entity;
        }
        const result = @import("server/damage.zig").apply(target_world, entity, amount, clock.now_ms, .{}) catch |err| runtimeFailure(err);
        var message: [128]u8 = undefined;
        engine.print(std.fmt.bufPrintZ(&message, "zig damage blood={d} armor={d} killed={d}\n", .{ result.blood, result.armor, @intFromBool(result.killed) }) catch unreachable);
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_character")) {
        const entity = active.clients.entities[0] orelse return 1;
        const state = (active.world.?.get(entity, component.Character) catch unreachable).*;
        var values: [256]u8 = undefined;
        engine.print(std.fmt.bufPrintZ(&values, "zig character attributes base={d},{d},{d},{d},{d} effective={d},{d},{d},{d},{d}\n", .{ state.attributes[0], state.attributes[1], state.attributes[2], state.attributes[3], state.attributes[4], state.attribute(.power, clock.now_ms), state.attribute(.attack, clock.now_ms), state.attribute(.speed, clock.now_ms), state.attribute(.acro, clock.now_ms), state.attribute(.vita, clock.now_ms) }) catch unreachable);
        var message: [256]u8 = undefined;
        engine.print(std.fmt.bufPrintZ(&message, "zig character time={d} speed={d} boost_until={d} invincible={d} environment={d} gems={d} level={d} points={d}\n", .{ clock.now_ms, state.attribute(.speed, clock.now_ms), state.boost_until[2], state.invincible_until, state.environment_until, state.save_gems, state.level, state.points }) catch unreachable);
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_inventory")) {
        const entity = active.clients.entities[0] orelse return 1;
        const loadout = (active.world.?.get(entity, component.Weapons) catch unreachable).*;
        const keys = (active.world.?.get(entity, component.Keys) catch unreachable).*;
        const health = (active.world.?.get(entity, component.Health) catch unreachable).*;
        var message: [256]u8 = undefined;
        engine.print(std.fmt.bufPrintZ(&message, "zig inventory keys={x} quest={x} owned={x} weapon={d} health={d} armor={d}\n", .{ keys.mask, keys.quest, @as(u32, @bitCast(loadout.dk3Inventory)), loadout.weapon, health.current, health.armor }) catch unreachable);
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_movers")) {
        for (active.slots.occupants) |occupant| {
            const entity = occupant orelse continue;
            const mover = active.world.?.get(entity, component.Mover) catch continue;
            const object = (active.world.?.get(entity, component.MapObject) catch unreachable).*;
            const transform = (active.world.?.get(entity, component.Transform) catch unreachable).*;
            var message: [352]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "zig mover id={d} group={d} class={s} name={s} state={s} pos={d:.1},{d:.1},{d:.1} end={d:.1},{d:.1},{d:.1} loop_offer={d} carrier={d}\n", .{ active.world.?.persistentId(entity) catch unreachable, mover.group, object.classname, object.targetname, @tagName(mover.state), transform.position[0], transform.position[1], transform.position[2], mover.opened[0], mover.opened[1], mover.opened[2], if (mover.moving() and mover.loop_sounds) (if (mover.state == .opening) mover.opening_sound else mover.closing_sound) else 0, mover.loop_carrier }) catch unreachable);
        }
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_special")) {
        for (active.slots.occupants) |occupant| {
            const entity = occupant orelse continue;
            const secret = active.world.?.get(entity, component.Secret) catch null;
            const rotation = active.world.?.get(entity, component.Rotation) catch null;
            if (secret == null and rotation == null) continue;
            const transform = (active.world.?.get(entity, component.Transform) catch unreachable).*;
            var message: [256]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "zig special id={d} phase={s} pos={d:.1},{d:.1},{d:.1} angles={d:.1},{d:.1},{d:.1}\n", .{ active.world.?.persistentId(entity) catch unreachable, if (secret) |value| @tagName(value.phase) else if (rotation.?.active) "rotating" else "stopped", transform.position[0], transform.position[1], transform.position[2], transform.angles[0], transform.angles[1], transform.angles[2] }) catch unreachable);
        }
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_trains")) {
        for (active.slots.occupants) |occupant| {
            const entity = occupant orelse continue;
            const train = active.world.?.get(entity, component.Train) catch continue;
            const object = (active.world.?.get(entity, component.MapObject) catch unreachable).*;
            const transform = (active.world.?.get(entity, component.Transform) catch unreachable).*;
            var message: [352]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&message, "zig train id={d} name={s} phase={s} corner={d} wait={d} due={?d} start={d} duration={d} endz={d:.1} pos={d:.1},{d:.1},{d:.1}\n", .{ active.world.?.persistentId(entity) catch unreachable, object.targetname, @tagName(train.phase), train.destination, train.departure_wait_ms, train.action.at_ms, train.position.start_ms, train.position.duration_ms, train.position.end[2], transform.position[0], transform.position[1], transform.position[2] }) catch unreachable);
        }
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_place")) {
        const player_entity = active.clients.entities[0] orelse return 1;
        var point: component.Vec3 = undefined;
        for (&point, 0..) |*axis, i| {
            var argument: [64]u8 = undefined;
            axis.* = std.fmt.parseFloat(f32, engine.argv(@intCast(i + 1), &argument)) catch return 1;
            if (!std.math.isFinite(axis.*) or @abs(axis.*) > 1000000) return 1;
        }
        (active.world.?.get(player_entity, component.Transform) catch unreachable).position = point;
        (active.world.?.get(player_entity, component.Velocity) catch unreachable).linear = @splat(0);
        (active.world.?.get(player_entity, component.Player) catch unreachable).ground_entity = c.ENTITYNUM_NONE;
        active.clients.publish(&active.world.?, &active.projection, &active.players, 0, clock.now_ms) catch |err| runtimeFailure(err);
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_board")) {
        var argument: [32]u8 = undefined;
        const id = std.fmt.parseInt(u32, engine.argv(1, &argument), 10) catch return 1;
        const player_entity = active.clients.entities[0] orelse return 1;
        const entity = active.world.?.find(id) orelse return 1;
        const binding = active.world.?.get(entity, component.Binding) catch return 1;
        const brush = &active.projection[binding.slot];
        const transform = active.world.?.get(player_entity, component.Transform) catch unreachable;
        const candidate: component.Vec3 = .{ (brush.shared.absmin[0] + brush.shared.absmax[0]) * 0.5, (brush.shared.absmin[1] + brush.shared.absmax[1]) * 0.5, brush.shared.absmax[2] + 24.125 };
        const body = (active.world.?.get(player_entity, component.Body) catch unreachable).*;
        const clear = engine.collisionService().trace(.{ .start = candidate, .end = candidate, .mins = body.mins, .maxs = body.maxs, .slot = 0, .mask = c.MASK_PLAYERSOLID }) catch |err| runtimeFailure(err);
        if (clear.start_solid) {
            engine.print("zig probe: brush centre is obstructed; choose a known walkable position with dk3_runtime_place.\n");
            return 1;
        }
        transform.position = candidate;
        (active.world.?.get(player_entity, component.Velocity) catch unreachable).linear = @splat(0);
        active.clients.publish(&active.world.?, &active.projection, &active.players, 0, clock.now_ms) catch |err| runtimeFailure(err);
        return 1;
    }
    if (engine.integer("dk3_runtime_probe") == 2 and std.mem.eql(u8, command, "dk3_runtime_activate")) {
        var argument: [32]u8 = undefined;
        const id = std.fmt.parseInt(u32, engine.argv(1, &argument), 10) catch return 1;
        var owner: u32 = 0;
        if (std.mem.eql(u8, engine.argv(2, &argument), "player")) if (active.clients.entities[0]) |player| {
            owner = active.world.?.persistentId(player) catch unreachable;
        };
        if (active.world.?.find(id)) |entity| active.targets.activate(&active.world.?, &active.slots, &active.projection, entity, owner, clock.now_ms) catch |err| runtimeFailure(err);
        return 1;
    }
    if (!std.mem.eql(u8, command, "dk3_runtime_status")) return 0;
    var text: [160]u8 = undefined;
    engine.print(std.fmt.bufPrintZ(&text, "dk3 zig: entities={d} frames={d} time={d} workers={d}\n", .{ if (active.world) |*value| value.count() else 0, clock.frame, clock.now_ms, if (pool) |value| value.thread_count else 0 }) catch unreachable);
    return 1;
}
fn enterWorld(name: []const u8) !void {
    // Host-console instrumentation uses the same explicit native diagnostic
    // mode as placement/equipment probes. Normal save reloads clear sv_cheats.
    if (engine.integer("g_gametype") != c.GT_SINGLE_PLAYER or engine.integer("dk3_runtime_probe") != 2) return error.DiagnosticRequiresNativeSinglePlayer;
    const destination = if (std.mem.eql(u8, name, "initial") or std.mem.eql(u8, name, std.mem.sliceTo(&initial_context.map_name, 0))) &initial_context else try resident_worlds.destination(name);
    try activateWorld(destination);
}
fn activateWorld(destination: *Context) !void {
    try @import("server/world_transfer.zig").player(active, destination, clock.now_ms);
    active = destination;
    try @import("engine/worlds.zig").select(active.handle.?);
    _ = @import("server/resources.zig").select(&active.resources);
    var map_buffer: [c.MAX_QPATH]u8 = undefined;
    var message: [256]u8 = undefined;
    const entity = active.clients.entities[0].?;
    const pose = (try active.world.?.get(entity, component.Transform)).*;
    engine.print(try std.fmt.bufPrintZ(&message, "dk3 world transfer: map={s} world={d} player={d} position={d:.3},{d:.3},{d:.3} command={d}\n", .{ engine.mapName(&map_buffer), active.network_id, try active.world.?.persistentId(entity), pose.position[0], pose.position[1], pose.position[2], (try active.world.?.get(entity, component.Player)).command_ms }));
}
fn depart(request: @import("domain/travel.zig").Request) !void {
    const journey = (try campaign_module.departure(&active.world.?, &active.clients, &active.systems, &active.projection, request, clock.now_ms)) orelse {
        progression.pending = null; // The cinematic/ending owns subsequent dispatch.
        return;
    };
    const edge = try progression.edge(active, request.exit);
    if (!std.mem.eql(u8, progression.manifest.names[edge.destination], journey.destination)) return error.RegionAuthoringMismatch;
    if (!(try progression.ready(&resident_worlds, &initial_context, journey.destination, false))) {
        if (edge.kind == .identity) return error.ConnectedRegionNotReady;
        progression.pending = request;
        progression.hold(true);
        return;
    }
    const destination = if (std.mem.eql(u8, journey.destination, std.mem.sliceTo(&initial_context.map_name, 0))) &initial_context else try resident_worlds.destination(journey.destination);
    if (progression.held) try active.awaken(clock.now_ms);
    const player = active.clients.entities[0].?;
    // Authored cuts retain the established inventory/episode/landing contract.
    // Qualified corridors preserve the actual command, pose and action instead.
    var arrival: ?campaign_module.Arrival = null;
    if (edge.kind != .identity) {
        var traveler = try @import("server/companions.zig").capture(&active.world.?, player, active.clients.episode, clock.now_ms);
        traveler.selectParty(journey);
        try @import("server/weapon_actions.zig").cancel(&active.world.?, &active.slots, &active.projection, player);
        try traveler.arrive(destination.clients.episode, clock.now_ms, &destination.clients.weapon_table);
        arrival = .{ .journey = journey, .traveler = traveler };
    }
    const source = active;
    try activateWorld(destination);
    if (arrival) |value| {
        try active.clients.arrive(&active.world.?, &active.slots, &active.projection, &active.players, value, &active.systems.actors, clock.now_ms);
        try @import("server/world_transfer.zig").party(source, active, value.traveler);
    } else try campaign_module.disarmArrival(&active.world.?, &active.projection, active.clients.entities[0].?);
    try @import("server/region_presentation.zig").State.tag(active);
    progression.pending = null;
    progression.hold(false);
    checkpoint.pending = true;
    var message: [192]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&message, "dk3 region: authored departure map={s} exit={d} kind={s} connection=retained\n", .{ journey.destination, request.exit, @tagName(edge.kind) }));
}
fn refuseDeparture(request: @import("domain/travel.zig").Request, err: anyerror) !void {
    // Readiness fails before traveler/weapon/party ownership changes. Resume
    // the existing world if a cut was held while that failure arrived.
    if (progression.held) try active.awaken(clock.now_ms);
    progression.pending = null;
    progression.hold(false);
    var message: [160]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&message, "dk3 travel: exit {d} refused: {s}\n", .{ request.exit, @errorName(err) }));
    if (err == error.RegionPreparationFailed) engine.send(0, "cp \"The next area could not be loaded.\"");
}
/// Ordinary client entry. Slot 0 is the single-player traveler: companions,
/// pending restoration, legacy arrival and initial region admission follow it.
fn beginClient(arg0: usize) void {
    if (arg0 == 0) active.configuration.begin();
    active.clients.begin(&active.world.?, &active.slots, &active.projection, &active.players, arg0, clock.now_ms, if (arg0 == 0 and campaign.arrival != null) campaign.arrival.?.journey else null) catch |err| runtimeFailure(err);
    if (arg0 == 0 and active.restore_pending == null) @import("server/companions.zig").start(&active.systems.actors, &active.world.?, &active.slots, &active.projection, active.clients.entities[0].?, if (campaign.arrival) |arrival| arrival.journey.spawn else "", if (campaign.arrival) |arrival| if (arrival.journey.kind == .submap) arrival.journey.companions else null else null, clock.now_ms) catch |err| runtimeFailure(err);
    if (arg0 == 0) if (active.restore_pending) |value| {
        if (value.residents.len != 0) {
            var wait_command: [64]u8 = undefined;
            engine.send(0, std.fmt.bufPrintZ(&wait_command, "dk3_region_wait 1 {d}", .{value.residents.len}) catch unreachable);
        } else {
            var saved = value;
            active.restore_pending = null;
            restore(&saved, restoring_visit) catch |err| {
                saved.deinit(std.heap.c_allocator);
                runtimeFailure(err);
            };
        }
    };
    if (arg0 == 0) if (campaign.arrival) |arrival| {
        active.clients.arrive(&active.world.?, &active.slots, &active.projection, &active.players, arrival, &active.systems.actors, clock.now_ms) catch |err| runtimeFailure(err);
        campaign.arrival = null;
        restoring_visit = false;
    };
    if (arg0 == 0 and progression.initial_pending) progression.holdFor(std.mem.sliceTo(&active.map_name, 0));
}
export fn vmMain(command: c_int, arg0: isize, arg1: isize, arg2: isize, arg3: isize, arg4: isize, arg5: isize, arg6: isize, arg7: isize, arg8: isize, arg9: isize, arg10: isize, arg11: isize) callconv(.c) isize {
    _ = .{ arg1, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11 };
    switch (command) {
        c.GAME_INIT => init(arg0, arg2 != 0) catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
            var buffer: [256]u8 = undefined;
            engine.fatal(std.fmt.bufPrintZ(&buffer, "Native Zig runtime: {s}. Isolated development uses dk3_runtime_probe=2; bootstrap diagnostics use 1.", .{@errorName(err)}) catch unreachable);
        },
        c.GAME_SHUTDOWN => shutdown(arg0 != 0),
        c.GAME_CLIENT_CONNECT => {
            if (engine.integer("dk3_runtime_probe") != 2) return @intCast(@intFromPtr(@as([*:0]const u8, "Native bootstrap does not admit players; movement development requires dk3_runtime_probe=2.")));
            if (arg0 < 0 or arg0 >= c.MAX_CLIENTS) return @intCast(@intFromPtr(@as([*:0]const u8, "Invalid client slot.")));
            var userinfo: [c.MAX_INFO_STRING]u8 = @splat(0);
            _ = engine.gateway.call(c.G_GET_USERINFO, .{ arg0, &userinfo, @as(isize, userinfo.len) });
            const identity = @import("engine/info.zig").get(std.mem.sliceTo(&userinfo, 0), "dk3_runtime_build") orelse "";
            if (!std.mem.eql(u8, identity, @import("engine/player_state.zig").version)) return @intCast(@intFromPtr(@as([*:0]const u8, "Zig runtime build mismatch. Install matching server, client and UI modules.")));
            if (rooms.connect(&active.clients, @intCast(arg0), arg2 != 0) catch |err| runtimeFailure(err)) |reason| return @intCast(@intFromPtr(reason.ptr));
            return 0;
        },
        c.GAME_CLIENT_BEGIN => beginClient(@intCast(arg0)),
        c.GAME_CLIENT_USERINFO_CHANGED => active.clients.userinfo(&active.world.?, @intCast(arg0)) catch |err| runtimeFailure(err),
        c.GAME_CLIENT_THINK => if (active.restore_pending == null and !progression.held and !progression.initial_pending) {
            active.clients.think(&active.world.?, &active.slots, &active.projection, &active.players, @intCast(arg0), clock.now_ms) catch |err| runtimeFailure(err);
        },
        c.GAME_CLIENT_DISCONNECT => {
            rooms.disconnect(&active.world.?, &active.clients, @intCast(arg0)) catch |err| runtimeFailure(err);
            active.clients.disconnect(&active.world.?, &active.slots, &active.projection, @intCast(arg0), clock.now_ms) catch |err| runtimeFailure(err);
            active.bots.brains[@intCast(arg0)] = null;
            social.chat_ready[@intCast(arg0)] = 0;
            social.score_ready[@intCast(arg0)] = 0;
            active.clients.returning[@intCast(arg0)] = null;
            engine.config(c.CS_PLAYERS + @as(i32, @intCast(arg0)), "");
        },
        c.GAME_RUN_FRAME => {
            const elapsed = clock.advance(arg0) catch {
                engine.fatal("Native runtime: invalid engine frame time");
            };
            if (engine.integer("dk3_runtime_probe") == 2) {
                if (campaign.departing) return 0;
                // The co-op bot is a client: it is admitted through the ordinary
                // begin path and answers publication even while the world is held.
                if (coop.admit(active.clients.entities[0] != null, clock.now_ms)) |index| beginClient(index);
                coop.pump();
                defer coop.finishFrame(&active.projection);
                if (active.clients.entities[0] == null and engine.integer("g_gametype") == c.GT_SINGLE_PLAYER) return 0;
                resident_worlds.step(clock.now_ms, &active.clients.weapon_table) catch |err| runtimeFailure(err);
                if (active.restore_pending) |*pending| {
                    if (active.clients.entities[0] == null or !(resident_worlds.restorationReady(pending) catch |err| runtimeFailure(err))) return 0;
                    var saved = pending.*;
                    active.restore_pending = null;
                    restore(&saved, restoring_visit) catch |err| runtimeFailure(err);
                    engine.send(0, "dk3_region_wait 0");
                    engine.print("dk3 region: restoration committed\n");
                }
                if (progression.initial_pending) {
                    resident_worlds.legacy_archives = campaign.visited;
                    resident_worlds.traveler_id = active.world.?.persistentId(active.clients.entities[0] orelse return 0) catch |err| runtimeFailure(err);
                    resident_worlds.initial_namespace = @intCast(active.world.?.id_first >> 24);
                    if (!(progression.ready(&resident_worlds, &initial_context, std.mem.sliceTo(&active.map_name, 0), false) catch |err| runtimeFailure(err))) return 0;
                    active.awaken(clock.now_ms) catch |err| runtimeFailure(err);
                    progression.initial_pending = false;
                    progression.hold(false);
                    engine.print("dk3 region: initial admission committed\n");
                }
                _ = progression.ready(&resident_worlds, &initial_context, std.mem.sliceTo(&active.map_name, 0), true) catch |err| runtimeFailure(err);
                progression.publishPortals() catch |err| runtimeFailure(err);
                // Maps left behind (beyond the current region and the next
                // exits) give their memory back and keep their state dormant.
                if (progression.pending == null and !progression.held and clock.now_ms >= demote_ms) {
                    demote_ms = clock.now_ms + 2000;
                    _ = resident_worlds.demote(&progression.manifest, std.mem.sliceTo(&active.map_name, 0), active) catch |err| runtimeFailure(err);
                }
                if (progression.pending) |request| {
                    depart(request) catch |err| switch (err) {
                        error.RegionPreparationFailed => refuseDeparture(request, err) catch |failure| runtimeFailure(failure),
                        else => runtimeFailure(err),
                    };
                    return 0;
                }
                rooms.tick(&active.world.?, &active.clients, clock.now_ms) catch |err| runtimeFailure(err);
                active.running = true;
                active.systems.multiplayer.warmup = rooms.warmup_ms != 0;
                campaign_module.endings(&active.world.?, &active.targets, clock.now_ms) catch |err| runtimeFailure(err);
                active.systems.cinematics.step(&active.world.?, &active.slots, &active.projection, &active.targets, active.clients.entities[0], clock.now_ms) catch |err| runtimeFailure(err);
                active.bots.step(&active.world.?, &active.slots, &active.projection, &active.players, &active.clients, &active.targets, active.systems.navigation.service(), &active.systems.gates, clock.now_ms) catch |err| runtimeFailure(err);
                var coop_map: [64]u8 = undefined;
                coop.step(&active.world.?, &active.slots, &active.projection, &active.clients, active.systems.navigation.service(), &active.systems.gates, persistence.mapName(&coop_map), clock.now_ms) catch |err| coop.crash(err, clock.now_ms);
                active.systems.step(&active.world.?, &active.slots, &active.projection, &active.targets, clock.now_ms, elapsed, &active.clients.weapon_table) catch |err| runtimeFailure(err);
                @import("server/player_damage.zig").step(&active.world.?, &active.slots, &active.projection, active.clients.episode, &active.clients.weapon_table, clock.now_ms) catch |err| runtimeFailure(err);
                for (active.clients.entities, 0..) |entity, index| if (entity != null) {
                    active.clients.publish(&active.world.?, &active.projection, &active.players, index, clock.now_ms) catch |err| runtimeFailure(err);
                    active.systems.cinematics.camera(&active.world.?, &active.players[index], clock.now_ms) catch |err| runtimeFailure(err);
                    @import("server/monitors.zig").camera(&active.world.?, entity.?, &active.players[index]) catch |err| runtimeFailure(err);
                    @import("server/companions.zig").camera(&active.world.?, entity.?, &active.players[index]) catch |err| runtimeFailure(err);
                    campaign_module.camera(&active.world.?, entity.?, &active.players[index]) catch |err| runtimeFailure(err);
                };
                active.stepped_at = clock.now_ms;
                @import("server/region_simulation.zig").step(active, clock.now_ms, elapsed) catch |err| runtimeFailure(err);
                @import("server/configuration.zig").publish() catch |err| runtimeFailure(err);
                active.presentation.publish(active, clock.now_ms) catch |err| runtimeFailure(err);
                recovery() catch |err| saveFeedback(err);
                if (active.targets.travel) |request| {
                    active.targets.travel = null;
                    if (@import("server/cinematics.zig").active(&active.world.?)) @import("server/cinematics.zig").finish(&active.world.?, &active.slots, &active.projection, &active.targets, active.clients.entities[0].?, clock.now_ms) catch |err| runtimeFailure(err);
                    depart(request) catch |err| {
                        refuseDeparture(request, err) catch |failure| runtimeFailure(failure);
                    };
                }
            }
        },
        c.GAME_CONSOLE_COMMAND => return consoleCommand(),
        c.GAME_CLIENT_COMMAND => {
            if (arg0 < 0 or arg0 >= c.MAX_CLIENTS) return 0;
            var command_buffer: [64]u8 = undefined;
            const client_command = engine.argv(0, &command_buffer);
            if (@import("server/configuration.zig").clientCommand(@intCast(arg0), client_command)) return 0;
            if (resident_worlds.clientCommand(@intCast(arg0), client_command) catch |err| runtimeFailure(err)) return 0;
            if (arg0 == 0 and (saveCommand(client_command) catch |err| {
                saveFeedback(err);
                return 0;
            })) return 0;
            if (@import("server/multiplayer.zig").enabled()) {
                const index: usize = @intCast(arg0);
                if (social.command(&active.world.?, &active.clients, &active.players, @intCast(arg0), client_command, clock.now_ms) catch |err| runtimeFailure(err)) return 0;
                if (rooms.command(&active.world.?, &active.clients, @intCast(arg0), client_command, clock.now_ms) catch |err| runtimeFailure(err)) return 0;
                if (active.clients.entities[index]) |entity| {
                    if (std.mem.eql(u8, client_command, "team")) {
                        var argument: [32]u8 = undefined;
                        const name = engine.argv(1, &argument);
                        const team: ?@import("domain/multiplayer.zig").Team = if (std.ascii.eqlIgnoreCase(name, "red")) .red else if (std.ascii.eqlIgnoreCase(name, "blue")) .blue else if (std.ascii.eqlIgnoreCase(name, "spectator") or std.ascii.eqlIgnoreCase(name, "s")) .spectator else if (std.ascii.eqlIgnoreCase(name, "free")) .free else null;
                        if (team) |selected| {
                            if ((selected == .red or selected == .blue) != @import("server/multiplayer.zig").teams() and selected != .spectator) return 0;
                            rooms.unready(&active.world.?, &active.clients, @intCast(arg0));
                            (active.world.?.get(entity, component.Session) catch unreachable).team = selected;
                            active.clients.begin(&active.world.?, &active.slots, &active.projection, &active.players, index, clock.now_ms, null) catch |err| runtimeFailure(err);
                        }
                        return 0;
                    }
                    if (std.mem.eql(u8, client_command, "kill")) {
                        _ = @import("server/damage.zig").apply(&active.world.?, entity, 100000, clock.now_ms, .{ .source = active.world.?.persistentId(entity) catch unreachable, .bypass_armor = true, .bypass_protection = true }) catch |err| runtimeFailure(err);
                        return 0;
                    }
                }
            }
            if (std.mem.eql(u8, client_command, "sidekick")) {
                var who_buffer: [32]u8 = undefined;
                var order_buffer: [32]u8 = undefined;
                const who = engine.argv(1, &who_buffer);
                const order = engine.argv(2, &order_buffer);
                if (active.clients.entities[@intCast(arg0)]) |player| {
                    const pose = (active.world.?.get(player, component.Transform) catch unreachable).*;
                    const v = @import("domain/vector.zig");
                    const origin = v.add(pose.position, .{ 0, 0, 22 });
                    const trace = @import("server/region_collision.zig").trace(.{ .start = origin, .end = v.add(origin, v.scale(v.basis(pose.angles).forward, 2000)), .mins = @splat(0), .maxs = @splat(0), .slot = @intCast(arg0), .mask = c.MASK_SHOT | c.CONTENTS_TRIGGER }) catch |err| runtimeFailure(err);
                    const target = if (@import("server/region_access.zig").victim(&active.world.?, &active.slots, trace)) |hit| hit.id() catch unreachable else 0;
                    const changed = @import("server/companions.zig").order(&active.systems.actors, &active.world.?, clock.now_ms, player, who, order, target, trace.end) catch |err| runtimeFailure(err);
                    engine.send(@intCast(arg0), if (changed) "cp \"Companion order received\"" else "cp \"Companion order unavailable\"");
                }
                return 0;
            }
            if (std.mem.eql(u8, client_command, "attribute")) {
                var argument: [64]u8 = undefined;
                const attribute = @import("domain/character.zig").attributeNamed(engine.argv(1, &argument)) orelse return 0;
                if (active.clients.entities[@intCast(arg0)]) |entity| {
                    const state = active.world.?.get(entity, component.Character) catch return 0;
                    _ = state.spend(attribute);
                }
            } else if (std.mem.eql(u8, client_command, "detonate")) {
                if (active.clients.entities[@intCast(arg0)]) |entity| {
                    const loadout = active.world.?.get(entity, component.Weapons) catch return 0;
                    const health = active.world.?.get(entity, component.Health) catch return 0;
                    if (loadout.weapon == @import("weapon_catalog").c4.id and health.current > 0) {
                        _ = @import("server/c4.zig").detonate(&active.world.?, active.world.?.persistentId(entity) catch return 0, clock.now_ms, false) catch |err| runtimeFailure(err);
                    }
                }
            } else if (std.mem.eql(u8, client_command, "cin_skip")) {
                if (arg0 == 0 and engine.integer("g_gametype") == c.GT_SINGLE_PLAYER and @import("server/cinematics.zig").active(&active.world.?)) {
                    if (active.clients.entities[0]) |entity| @import("server/cinematics.zig").completePlayback(&active.world.?, &active.slots, &active.projection, &active.targets, entity, clock.now_ms) catch |err| runtimeFailure(err);
                }
            } else if (std.mem.eql(u8, client_command, "use")) {
                if (active.clients.entities[@intCast(arg0)]) |entity| @import("server/interactions.zig").use(&active.world.?, &active.slots, &active.projection, &active.targets, entity, clock.now_ms) catch |err| runtimeFailure(err);
            }
        },
        c.BOTAI_START_FRAME => {},
        else => return -1,
    }
    return 0;
}

// Inline: the caller's error return trace is the one worth printing.
inline fn runtimeFailure(err: anyerror) noreturn {
    if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
    var message: [160]u8 = undefined;
    engine.fatal(std.fmt.bufPrintZ(&message, "Zig runtime: {s}", .{@errorName(err)}) catch unreachable);
}
