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
    if (@import("lights.zig").owns(name)) return true;
    for ([_][]const u8{ "target_effect", "effect_rain", "effect_snow", "effect_drip", "effect_lightning", "target_attractor", "sfx_complex_particle", "func_dynalight", "target_lightramp", "target_spotlight", "target_earthquake", "func_gib", "func_debris", "func_debris_visible", "trigger_change_sfx", "target_laser", "misc_hosportal", "misc_fountain", "target_speaker", "sound_ambient", "func_timer", "trigger_push", "trigger_teleport", "trigger_secret", "trigger_toggle", "trigger_changemusic", "trigger_console", "trigger_remove_inventory_item" }) |item| if (std.mem.eql(u8, name, item)) return true;
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
        if (std.mem.eql(u8, object.classname, "light") and object.targetname.len == 0 and object.flags & 2 == 0) continue;
        if (std.mem.eql(u8, object.classname, "target_lightramp") and @import("multiplayer.zig").enabled()) {
            try world.destroy(entity);
            continue;
        }
        // This authored name remains in e1dm2, but its reference export was removed.
        if (std.mem.eql(u8, object.classname, "effect_drip")) {
            if ((world.get(entity, data.Binding) catch null) != null) try @import("weapon_entities.zig").remove(world, slots, projections, entity) else try world.destroy(entity);
            continue;
        }
        var action: rules.Action = undefined;
        if (std.mem.eql(u8, object.classname, "target_effect")) {
            action = .{ .target_effect = try @import("target_effects.zig").initialize(world, entity, now) };
            if (engine.integer("sv_violence") != 0 and action.target_effect.kind >= 3 and action.target_effect.kind <= 7) {
                try world.destroy(entity);
                continue;
            }
        } else if (std.mem.eql(u8, object.classname, "effect_rain") or std.mem.eql(u8, object.classname, "effect_snow")) {
            action = .{ .weather = try @import("weather.zig").initialize(world, entity) };
        } else if (std.mem.eql(u8, object.classname, "effect_lightning")) {
            action = .{ .lightning = try @import("lightning.zig").initialize(world, entity, now) };
        } else if (std.mem.eql(u8, object.classname, "target_attractor")) {
            action = .{ .attractor = try @import("lightning.zig").attractor(object, now) };
        } else if (std.mem.eql(u8, object.classname, "sfx_complex_particle")) {
            action = .{ .particles = try @import("complex_particles.zig").initialize(world, entity, now) };
        } else if (@import("lights.zig").owns(object.classname)) {
            action = .{ .light = try @import("lights.zig").initialize(object, try world.persistentId(entity), now) };
        } else if (std.mem.eql(u8, object.classname, "target_lightramp")) {
            action = .{ .light_ramp = try @import("lights.zig").ramp(object) };
        } else if (std.mem.eql(u8, object.classname, "target_spotlight") or std.mem.eql(u8, object.classname, "func_dynalight")) {
            action = .{ .spotlight = try @import("spotlights.zig").initialize(object, try world.get(entity, data.Transform), now) };
        } else if (std.mem.eql(u8, object.classname, "target_earthquake")) {
            action = .{ .earthquake = try @import("earthquakes.zig").initialize(world, entity) };
        } else if (std.mem.eql(u8, object.classname, "func_gib")) {
            action = .{ .gib_emitter = try @import("gib_emitters.zig").initialize(world, entity, now) };
        } else if (@import("debris.zig").owns(object.classname)) {
            action = .{ .debris = try @import("debris.zig").initialize(world, entity, projections, now) };
        } else if (std.mem.eql(u8, object.classname, "trigger_change_sfx")) {
            var preset: i32 = 0;
            for (object.properties) |property| if (std.ascii.eqlIgnoreCase(property.key, "reverb") or std.ascii.eqlIgnoreCase(property.key, "fxstyle")) {
                preset = @intFromFloat(try prop.number(object, property.key, 0));
            };
            if (preset < 0 or preset > 25) return error.InvalidRoomPreset;
            action = .{ .room = @intCast(preset) };
        } else if (std.mem.eql(u8, object.classname, "target_laser")) {
            action = .{ .laser = try @import("lasers.zig").initialize(object, (try world.get(entity, data.Transform)).*, now) };
        } else if (@import("healers.zig").owns(object.classname)) {
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
        if (action == .target_effect) {
            try @import("weapon_entities.zig").bind(world, slots, projections, entity, "");
            try @import("target_effects.zig").publish(world, entity, projections);
        }
        if (action == .weather) try @import("weather.zig").publish(world, entity, projections);
        if (action == .lightning) {
            try @import("weapon_entities.zig").bind(world, slots, projections, entity, "");
            try @import("lightning.zig").publish(world, entity, projections);
        }
        if (action == .particles) {
            try @import("weapon_entities.zig").bind(world, slots, projections, entity, "");
            try @import("complex_particles.zig").publish(world, entity, projections);
        }
        if (action == .light) try @import("lights.zig").bind(world, slots, projections, entity);
        if (action == .spotlight) {
            try @import("weapon_entities.zig").bind(world, slots, projections, entity, action.spotlight.model);
            try @import("spotlights.zig").publish(world, entity, projections);
        }
        if (action == .earthquake) {
            try @import("weapon_entities.zig").bind(world, slots, projections, entity, "");
            try @import("earthquakes.zig").publish(world, entity, projections);
        }
        if (action == .debris) try @import("debris.zig").publish(world, entity, slots, projections);
        if (action == .laser) {
            try @import("weapon_entities.zig").bind(world, slots, projections, entity, "");
            try @import("lasers.zig").publish(world, entity, projections);
        }
        if (action == .healer) try @import("healers.zig").bind(world, slots, projections, entity);
        if (action == .speaker) {
            try @import("weapon_entities.zig").bind(world, slots, projections, entity, "");
            try @import("speakers.zig").publish(world, entity, projections);
        }
    }
    @import("lights.zig").styles(world, now);
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
        .target_effect => try @import("target_effects.zig").use(world, slots, projections, entity, now),
        .lightning => try @import("lightning.zig").use(world, slots, projections, router, entity, now),
        .blood_cloud, .lightning_bolt, .attractor, .weather => {},
        .particles => try @import("complex_particles.zig").use(world, entity, projections, now),
        .light => try @import("lights.zig").use(world, entity, projections),
        .light_ramp => try @import("lights.zig").rampUse(world, entity, now),
        .spotlight => try @import("spotlights.zig").use(world, slots, projections, entity, now),
        .earthquake => try @import("earthquakes.zig").use(world, entity, projections, now),
        .gib_emitter => |*state| state.use(now),
        .debris => try @import("debris.zig").use(world, slots, projections, entity, activator, now),
        .room => {}, // Touch-only room control.
        .laser => try @import("lasers.zig").use(world, slots, projections, entity, now),
        .healer => try @import("healers.zig").use(world, slots, projections, entity, activator, now),
        .speaker => try @import("speakers.zig").use(world, slots, projections, entity, now),
        .timer => |*timer| {
            if (timer.once and control.uses > 0) return;
            timer.activator = activator;
            timer.next_ms = if (timer.next_ms != null) null else now + timer.delay_ms;
            if (timer.next_ms != null and timer.next_ms.? <= now) try fireTimer(world, slots, projections, router, entity, now);
        },
        .push => |*push| if (push.toggleable) {
            push.enabled = !push.enabled;
        },
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
        .light => |state| state.kind == .flame and (world.get(other, data.Health) catch null) != null,
        .blood_cloud, .light_ramp, .particles, .lightning, .lightning_bolt, .attractor, .weather, .target_effect => false,
        .debris => |state| state.active and (player or companion or (world.get(other, data.Actor) catch null) != null),
        .timer, .speaker, .healer, .laser, .gib_emitter, .earthquake, .spotlight => false,
        .teleport => |state| state.named_subject.len == 0 and object.targetname.len == 0 and (player or (companion and object.flags & 1 == 0)),
        .toggle => if (object.flags & 8 != 0) companion else player or (companion and object.flags & 4 != 0),
        .music => (player and object.flags & 1 == 0) or (world.get(other, data.Performer) catch null) != null,
        .push, .secret, .console, .remove_item, .room => player,
    };
}
pub fn touch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, entity: ecs.Entity, other: ecs.Entity, now: i64) !void {
    const control = try world.get(entity, data.WorldControl);
    if (now < control.ready_ms or !@import("keys.zig").allows(world, (try world.get(entity, data.MapObject)).*, try world.persistentId(other))) return;
    switch (control.action) {
        .light => {
            _ = try @import("damage.zig").apply(world, other, 2, now, .{ .source = try world.persistentId(entity) });
        },
        .debris => try @import("debris.zig").contact(world, slots, projections, entity, other, now),
        .room => |preset| (try world.get(other, data.Character)).sound_environment = preset + 1,
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
    try @import("lightning.zig").linkAttractors(world, now);
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
            .blood_cloud => try @import("blood_clouds.zig").step(world, slots, projections, entity, now),
            .target_effect => try @import("target_effects.zig").step(world, slots, projections, entity, now),
            .lightning, .lightning_bolt => try @import("lightning.zig").step(world, slots, projections, router, entity, now),
            .particles => try @import("complex_particles.zig").step(world, slots, projections, entity, now),
            .light_ramp => try @import("lights.zig").rampStep(world, entity, now),
            .spotlight => try @import("spotlights.zig").step(world, slots, projections, entity, now),
            .earthquake => try @import("earthquakes.zig").step(world, slots, projections, entity, now),
            .gib_emitter => try @import("gib_emitters.zig").step(world, slots, projections, entity, now),
            .debris => try @import("debris.zig").step(world, slots, projections, entity, now),
            .laser => try @import("lasers.zig").step(world, slots, projections, entity, now),
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
    @import("lights.zig").styles(world, now);
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
