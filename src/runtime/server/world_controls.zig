// SPDX-License-Identifier: GPL-2.0-or-later
//! World controls execute authored contracts through normal routing and collision.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/world_controls.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const prop = @import("properties.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Router = @import("targets.zig").Router;
pub fn owns(name: []const u8) bool {
    for ([_][]const u8{ "misc_hosportal", "misc_fountain", "target_speaker", "sound_ambient", "func_timer", "trigger_push", "trigger_teleport", "trigger_secret", "trigger_toggle", "trigger_changemusic", "trigger_console", "trigger_remove_inventory_item" }) |item| if (std.mem.eql(u8, name, item)) return true;
    return false;
}
pub fn spawn(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    var ids: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (owns(object.classname)) {
            ids[count] = entity;
            count += 1;
        };
    }
    for (ids[0..count]) |entity| {
        const object = (try world.get(entity, data.MapObject)).*;
        var action: rules.Action = undefined;
        if (@import("healers.zig").owns(object.classname)) {
            action = .{ .healer = try @import("healers.zig").initialize(object) };
        } else if (@import("speakers.zig").owns(object.classname)) {
            action = .{ .speaker = try @import("speakers.zig").initialize(object, try world.persistentId(entity), now) };
        } else if (std.mem.eql(u8, object.classname, "func_timer")) {
            const wait = try prop.milliseconds(object, "wait", 1);
            if (wait < 100) return error.InvalidTimerWait;
            var timer: rules.Timer = .{ .wait_ms = wait, .variance_ms = @min(@max(0, try prop.milliseconds(object, "random", 0)), wait - 100), .delay_ms = try prop.milliseconds(object, "delay", 0), .random = try world.persistentId(entity), .once = object.flags & 2 != 0 };
            if (timer.delay_ms < 0) return error.InvalidTimerDelay;
            if (object.flags & 1 != 0) {
                timer.activator = try world.persistentId(entity);
                timer.next_ms = now + 1000 + try prop.milliseconds(object, "pausetime", 0) + timer.delay_ms + timer.interval();
            }
            action = .{ .timer = timer };
        } else if (std.mem.eql(u8, object.classname, "trigger_push")) {
            const angles = (try world.get(entity, data.Transform)).angles;
            const direction: v.Vec3 = if (angles[1] == -1) .{ 0, 0, 1 } else if (angles[1] == -2) .{ 0, 0, -1 } else v.basis(angles).forward;
            const supplied = try prop.number(object, "speed", 1000);
            action = .{ .push = .{ .velocity = v.scale(direction, (if (supplied == 0) @as(f32, 1000) else supplied) * 10), .once = object.flags & 1 != 0, .toggleable = object.flags & 2 != 0, .enabled = object.flags & 4 == 0 } };
        } else if (std.mem.eql(u8, object.classname, "trigger_teleport")) {
            action = .{ .teleport = .{ .named_subject = prop.text(object, "teleport") orelse "" } };
        } else if (std.mem.eql(u8, object.classname, "trigger_secret")) {
            action = .secret;
        } else if (std.mem.eql(u8, object.classname, "trigger_toggle")) {
            const binding = (try world.get(entity, data.Binding)).*;
            const projection = projections[binding.slot].shared;
            action = .{ .toggle = .{ .center = v.scale(v.add(projection.absmin, projection.absmax), 0.5), .radius = v.length(v.subtract(projection.absmax, projection.absmin)) * 0.57 } };
        } else if (std.mem.eql(u8, object.classname, "trigger_changemusic")) {
            action = .{ .music = .{ .path = prop.text(object, "path") orelse return error.MissingMusicPath, .volume = std.math.clamp(try prop.number(object, "volume", 1), 0, 1) } };
        } else if (std.mem.eql(u8, object.classname, "trigger_console")) {
            const command = prop.text(object, "message") orelse prop.text(object, "command") orelse return error.MissingAuthoredCommand;
            action = .{ .console = if (std.mem.eql(u8, command, "disconnect")) .disconnect else if (std.mem.eql(u8, command, "s_daikatana")) .sword else if (std.mem.eql(u8, command, "weapon_select_1")) .first_weapon else return error.UnsupportedAuthoredCommand };
        } else {
            action = .{ .remove_item = prop.text(object, "item") orelse return error.MissingRemovedItem };
        }
        try world.put(entity, data.WorldControl{ .action = action });
        if (action == .healer) try @import("healers.zig").bind(world, slots, projections, entity);
        if (action == .speaker) {
            try @import("weapon_entities.zig").bind(world, slots, projections, entity, "");
            try @import("speakers.zig").publish(world, entity, projections);
        }
    }
}
fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, sample: []const u8, now: i64) !void {
    if (sample.len == 0) return;
    try @import("events.zig").sound(world, slots, projections, sample, (try world.get(entity, data.Transform)).position, if (slots.find(entity)) |slot| slot else c.ENTITYNUM_WORLD, c.CHAN_AUTO, now);
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, entity: ecs.Entity, activator: u32, now: i64) !void {
    const control = try world.get(entity, data.WorldControl);
    if (now < control.ready_ms) return;
    const object = (try world.get(entity, data.MapObject)).*;
    switch (control.action) {
        .healer => try @import("healers.zig").use(world, slots, projections, entity, activator, now),
        .speaker => try @import("speakers.zig").use(world, slots, projections, entity, now),
        .timer => |*timer| {
            if (timer.once and control.uses > 0) return;
            timer.activator = activator;
            timer.next_ms = if (timer.next_ms != null) null else now + timer.delay_ms;
            if (timer.next_ms != null and timer.next_ms.? <= now) try fireTimer(world, slots, projections, router, entity, now);
        },
        .push => |*push| if (push.toggleable) { push.enabled = !push.enabled; },
        .teleport => |teleport| {
            if (teleport.named_subject.len == 0) return;
            if (std.mem.eql(u8, teleport.named_subject, "player")) {
                if (slots.occupants[0]) |player| try @import("teleports.zig").move(world, slots, projections, router, entity, player, true, now);
            } else {
                const found = try @import("names.zig").named(world, teleport.named_subject);
                for (found.ids[0..found.count]) |id| if (world.find(id)) |actor| try @import("teleports.zig").move(world, slots, projections, router, entity, actor, true, now);
            }
        },
        .secret => {
            if (control.uses > 0) return;
            const player = world.find(activator) orelse return;
            const character = world.get(player, data.Character) catch return;
            control.uses = 1;
            character.secrets += 1;
            const episode = (router.actors orelse return error.MissingActorDefinitions).episode;
            var path: [40]u8 = undefined;
            try sound(world, slots, projections, player, try std.fmt.bufPrint(&path, "e{d}/e{d}_secret.wav", .{ episode, episode }), now);
            try message(world, player, prop.text(object, "message") orelse "Secret found.");
            try router.fire(world, slots, projections, entity, activator, now);
        },
        .toggle => {}, // Touch/exit transitions are owned by this volume.
        .music => |*music| {
            control.ready_ms = now + 1000;
            music.changed_ms = now;
            try @import("music.zig").publish(music.path, music.volume);
        },
        .console => |command| {
            if (object.flags & 1 != 0 and control.uses > 0) return;
            const player = world.find(activator) orelse return;
            const binding = world.get(player, data.Binding) catch return;
            if (binding.slot >= c.MAX_CLIENTS) return;
            control.uses += 1;
            control.ready_ms = now + 1000;
            if (command == .disconnect) {
                engine.send(@intCast(binding.slot), "disconnect");
            } else {
                const id = if (command == .sword) @import("weapon_catalog").daikatana.id else @import("weapon_catalog").starting((router.actors orelse return error.MissingActorDefinitions).episode);
                if ((try world.get(player, data.Weapons)).dk3Inventory & (@as(i32, 1) << id) == 0) return;
                var text: [32]u8 = undefined;
                engine.send(@intCast(binding.slot), try std.fmt.bufPrintZ(&text, "dk3_weapon {d}", .{id}));
            }
        },
        .remove_item => |name| {
            const player = world.find(activator) orelse return;
            if ((world.get(player, data.Player) catch null) == null) return;
            try @import("inventory_actions.zig").remove(world, player, name);
        },
    }
}
fn message(world: *data.World, player: ecs.Entity, value: []const u8) !void {
    const slot = (try world.get(player, data.Binding)).slot;
    if (slot >= c.MAX_CLIENTS) return;
    var text: [1024]u8 = undefined;
    var escaped: [900]u8 = undefined;
    var size: usize = 0;
    for (value) |ch| {
        if (size == escaped.len) break;
        if (ch == '"' or ch == '\n' or ch == '\r') continue;
        escaped[size] = ch;
        size += 1;
    }
    engine.send(@intCast(slot), try std.fmt.bufPrintZ(&text, "cp \"{s}\"", .{escaped[0..size]}));
}

pub fn touches(world: *data.World, entity: ecs.Entity, other: ecs.Entity) !bool {
    const control = (try world.get(entity, data.WorldControl)).*;
    const object = (try world.get(entity, data.MapObject)).*;
    const player = (world.get(other, data.Player) catch null) != null;
    const companion = (world.get(other, data.Companion) catch null) != null;
    return switch (control.action) {
        .timer, .speaker, .healer => false,
        .teleport => |state| state.named_subject.len == 0 and object.targetname.len == 0 and (player or (companion and object.flags & 1 == 0)),
        .toggle => if (object.flags & 8 != 0) companion else player or (companion and object.flags & 4 != 0),
        .music => (player and object.flags & 1 == 0) or (world.get(other, data.Performer) catch null) != null,
        .push, .secret, .console, .remove_item => player,
    };
}
pub fn touch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, entity: ecs.Entity, other: ecs.Entity, now: i64) !void {
    const control = try world.get(entity, data.WorldControl);
    if (now < control.ready_ms or !@import("keys.zig").allows(world, (try world.get(entity, data.MapObject)).*, try world.persistentId(other))) return;
    switch (control.action) {
        .push => |push| {
            if (!push.enabled or (push.once and control.uses > 0)) return;
            (try world.get(other, data.Velocity)).linear = push.velocity;
            if (push.velocity[2] > 0) {
                const player = try world.get(other, data.Player);
                player.ground_entity = c.ENTITYNUM_NONE;
                (try world.get(other, data.Body)).grounded = false;
            }
            control.uses += 1;
            // Authoring defines an optional push sound, not a forced wind sound.
            const object = (try world.get(entity, data.MapObject)).*;
            try sound(world, slots, projections, other, prop.text(object, "sound") orelse "", now);
        },
        .teleport => try @import("teleports.zig").move(world, slots, projections, router, entity, other, false, now),
        .toggle => |*toggle| {
            if (toggle.activator != 0) return;
            toggle.activator = try world.persistentId(other);
            control.ready_ms = now + 200;
            try router.fire(world, slots, projections, entity, toggle.activator, now);
        },
        else => try use(world, slots, projections, router, entity, try world.persistentId(other), now),
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, now: i64) !void {
    var ids: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.WorldControl}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            ids[count] = entity;
            count += 1;
        };
    }
    for (ids[0..count]) |entity| {
        if (!world.alive(entity)) continue;
        const control = try world.get(entity, data.WorldControl);
        switch (control.action) {
            .healer => try @import("healers.zig").step(world, slots, projections, entity, now),
            .speaker => try @import("speakers.zig").step(world, slots, projections, entity, now),
            .timer => |*timer| if (timer.next_ms) |at| {
                if (now < at) continue;
                try fireTimer(world, slots, projections, router, entity, now);
            },
            .toggle => |*toggle| {
                if (toggle.activator == 0 or now < control.ready_ms) continue;
                control.ready_ms = now + 200;
                const activator = toggle.activator;
                const actor = world.find(activator);
                if (actor) |other| if (v.length(v.subtract((try world.get(other, data.Transform)).position, toggle.center)) <= toggle.radius) continue;
                toggle.activator = 0;
                if ((try world.get(entity, data.MapObject)).flags & 1 != 0 and actor != null) try router.fire(world, slots, projections, entity, activator, now);
            },
            else => {},
        }
    }
}

fn fireTimer(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, entity: ecs.Entity, now: i64) !void {
    const control = try world.get(entity, data.WorldControl);
    const timer = &control.action.timer;
    const activator = timer.activator;
    timer.next_ms = if (timer.once) null else now + timer.interval();
    control.uses += 1;
    // Initial delay belongs to activation, not every target firing.
    try router.fireImmediate(world, slots, projections, entity, activator, now);
}
