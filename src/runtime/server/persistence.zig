// SPDX-License-Identifier: GPL-2.0-or-later
//! Save preparation owns staging and validation; projection commit follows only
//! after the complete snapshot has been admitted. No opaque engine state is saved.
const std = @import("std");
const data = @import("../domain/components.zig");
const format = @import("../domain/snapshot.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const storage = @import("../engine/save_storage.zig");
const Slots = @import("../engine/slots.zig").Slots;
const c = abi.c;
pub fn mapName(buffer: []u8) []const u8 {
    @memset(buffer, 0);
    _ = engine.gateway.call(c.G_CVAR_VARIABLE_STRING_BUFFER, .{ @as([*:0]const u8, "mapname"), buffer.ptr, @as(isize, @intCast(buffer.len)) });
    return std.mem.sliceTo(buffer, 0);
}
pub fn capture(allocator: std.mem.Allocator, bytes: []u8, world: *data.World, clients: *const @import("clients.zig").Clients, targets: *const @import("targets.zig").Router, now: i64, visited: []const format.Archive, journey: ?@import("../domain/travel.zig").Journey) ![]const u8 {
    const player = clients.entities[0] orelse return error.NoPlayerToSave;
    var map: [64]u8 = undefined;
    const header: format.Header = .{ .at_ms = now, .player_id = try world.persistentId(player), .episode = clients.episode, .next_id = world.next_id, .resources = try @import("resources.zig").capture(allocator), .pending = targets.pending, .journey = journey };
    return format.captureCampaign(allocator, bytes, world, mapName(&map), @intCast(std.math.clamp(engine.integer("g_spSkill"), 1, 5)), header, visited);
}
pub fn save(world: *data.World, clients: *const @import("clients.zig").Clients, targets: *const @import("targets.zig").Router, systems: *@import("world_systems.zig").State, slot: []const u8, now: i64, visited: []const format.Archive) !void {
    if (engine.integer("g_gametype") != c.GT_SINGLE_PLAYER) return error.SaveRequiresSinglePlayer;
    const player = clients.entities[0] orelse return error.NoPlayerToSave;
    if ((try world.get(player, data.Health)).current <= 0) return error.CannotSaveDeadPlayer;
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const bytes = try allocator.alloc(u8, format.maximum);
    var map: [64]u8 = undefined;
    const saved = try capture(allocator, bytes, world, clients, targets, now, visited, null);
    // This also catches semantic schema omissions before replacing a prior save.
    var admitted = try format.decode(allocator, saved);
    defer admitted.deinit(allocator);
    try admit(&admitted, systems);
    try storage.write(slot, saved, false);
    var info: [512]u8 = undefined;
    const health = (try world.get(player, data.Health)).current;
    const character = (try world.get(player, data.Character)).*;
    const metadata = try std.fmt.bufPrint(&info, "dk3_save_info 1\nmap \"{s}\"\nhealth {d}\nlevel {d}\nnative_schema {d}\n", .{ mapName(&map), health, character.level, format.schema });
    storage.write(slot, metadata, true) catch engine.print("dk3 save: saved world; preview metadata could not be written\n");
}
pub fn prepare(slot: []const u8, previous: bool) !format.Loaded {
    const allocator = std.heap.c_allocator;
    const bytes = try storage.read(allocator, slot, previous);
    defer allocator.free(bytes);
    return format.decode(allocator, bytes);
}
/// Admission may load immutable class metadata, but cannot mutate engine entities.
/// Projection rebuilding below is infallible
/// for the admitted entity families and current map's loaded definitions.
pub fn admit(loaded: *format.Loaded, systems: *@import("world_systems.zig").State) !void {
    try systems.cinematics.admit(&loaded.world);
    try systems.scripts.admit(&loaded.world);
    var query = loaded.world.queryAccess(0, 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities()) |entity| {
        if (loaded.world.get(entity, data.Actor) catch null) |actor| try systems.actors.ensure(actor.definition);
        if (loaded.world.get(entity, data.Binding) catch null) |binding| {
            if ((loaded.world.get(entity, data.Hammer) catch null) != null or (loaded.world.get(entity, data.Shockwave) catch null) != null or (loaded.world.get(entity, data.Nova) catch null) != null or (loaded.world.get(entity, data.Flashlight) catch null) != null or (loaded.world.get(entity, data.Zeus) catch null) != null or (loaded.world.get(entity, data.ZeusBolt) catch null) != null or (loaded.world.get(entity, data.Nightmare) catch null) != null or (loaded.world.get(entity, data.MetaRing) catch null) != null or (loaded.world.get(entity, data.MetaLaser) catch null) != null) continue;
            if (loaded.world.get(entity, data.WorldControl) catch null) |control| if (control.action == .lightning or control.action == .lightning_bolt or control.action == .particles or control.action == .light or control.action == .spotlight or control.action == .earthquake or control.action == .speaker or control.action == .laser or control.action == .healer) {
                if (control.action == .spotlight and control.action.spotlight.model.len > 0) {
                    if (binding.model == 0 or binding.model > loaded.header.resources.models.len or !std.mem.eql(u8, loaded.header.resources.models[binding.model - 1], control.action.spotlight.model)) return error.InvalidSavedSpotlight;
                    continue;
                }
                if (control.action == .light) {
                    if (binding.model == 0 or binding.model > loaded.header.resources.models.len or !std.mem.eql(u8, loaded.header.resources.models[binding.model - 1], control.action.light.model)) return error.InvalidSavedLight;
                    continue;
                }
                if (control.action == .healer) {
                    if (binding.model == 0 or binding.model > loaded.header.resources.models.len or !std.mem.eql(u8, loaded.header.resources.models[binding.model - 1], @import("item_catalog").hosportal.definition(control.action.healer.kind).model)) return error.InvalidSavedHealer;
                    continue;
                }
                if (binding.model != 0) return error.InvalidSavedSpeaker;
                continue;
            };
            const object = loaded.world.get(entity, data.MapObject) catch null;
            const brush = object != null and object.?.model.len > 1 and object.?.model[0] == '*';
            if (brush) {
                const model = try std.fmt.parseInt(u16, object.?.model[1..], 10);
                if (model == 0 or model >= systems.inline_models or binding.model != model) return error.InvalidSavedBrush;
            } else if (object != null and object.?.model.len == 0 and std.mem.eql(u8, object.?.classname, "func_train") and (loaded.world.get(entity, data.Train) catch null) != null) {
                // Authored invisible trains carry attachments without a BSP model.
                if (binding.model != 0 or (try loaded.world.get(entity, data.Body)).contents != 0) return error.InvalidSavedTrain;
            } else if ((loaded.world.get(entity, data.Player) catch null) == null) {
                const model_optional = (loaded.world.get(entity, data.CryoSpray) catch null) != null or
                    (if (loaded.world.get(entity, data.ActorAttack) catch null) |attack| (attack.attack == .wyndrax_zap or attack.attack == .wyndrax_bolt or attack.attack == .knight_zap or attack.attack == .knight_punch or attack.attack == .gunner_burst) else false);
                if ((!model_optional and binding.model == 0) or binding.model > loaded.header.resources.models.len) {
                    var text: [192]u8 = undefined;
                    engine.print(try std.fmt.bufPrintZ(&text, "dk3 save: invalid model on entity {d} ({s}), model={d}, registered={d}\n", .{ try loaded.world.persistentId(entity), if (object) |value| value.classname else "dynamic", binding.model, loaded.header.resources.models.len }));
                    return error.InvalidSavedModel;
                }
                if ((loaded.world.get(entity, data.ActorAttack) catch null) == null and (loaded.world.get(entity, data.ActorLaser) catch null) == null and (loaded.world.get(entity, data.CryoSpray) catch null) == null and (loaded.world.get(entity, data.Firefly) catch null) == null and (loaded.world.get(entity, data.Scenery) catch null) == null and (loaded.world.get(entity, data.Actor) catch null) == null and (loaded.world.get(entity, data.Pickup) catch null) == null and (loaded.world.get(entity, data.Projectile) catch null) == null and (loaded.world.get(entity, data.Charge) catch null) == null and (loaded.world.get(entity, data.Performer) catch null) == null and (loaded.world.get(entity, data.DwarfAxe) catch null) == null and (loaded.world.get(entity, data.FrogSpit) catch null) == null and (loaded.world.get(entity, data.HealthTree) catch null) == null and (loaded.world.get(entity, data.ThunderSpray) catch null) == null) return error.UnsupportedSavedEntity;
            }
        }
    };
}
pub fn project(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, clients: *@import("clients.zig").Clients, states: []c.playerState_t, systems: *const @import("world_systems.zig").State, header: format.Header, now: i64) !void {
    slots.* = .{};
    clients.entities = @splat(null);
    clients.episode = header.episode;
    for (projections, 0..) |*projection, i| {
        projection.* = std.mem.zeroes(abi.EntityProjection);
        projection.state.number = @intCast(i);
        projection.shared.ownerNum = c.ENTITYNUM_NONE;
    }
    const player = world.find(header.player_id).?;
    clients.entities[0] = player;
    @memset(std.mem.sliceAsBytes(states), 0);
    states[0].gravity = 800;
    states[0].clientNum = 0;
    const player_state = try world.get(player, data.Player);
    player_state.command_ms = now;
    var input: c.usercmd_t = undefined;
    engine.usercmd(0, &input);
    for ((try world.get(player, data.Transform)).angles, 0..) |angle, i| player_state.delta_angles[i] = @as(i32, @intFromFloat(@mod(angle, 360) * (65536.0 / 360.0))) -% input.angles[i];
    var query = world.queryAccess(data.World.mask(.{data.Binding}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Binding)) |entity, binding| {
        // Saved transport slots are reserved explicitly; entity references remain
        // independent persistent IDs and stale ECS handles are never reused.
        slots.occupants[binding.slot] = entity;
        if (binding.slot == 0) {
            try clients.publish(world, projections, states, 0, now);
            continue;
        }
        if (world.get(entity, data.WorldControl) catch null) |control| if (control.action == .weather) {
            try @import("weather.zig").publish(world, entity, projections);
            continue;
        };
        if (world.get(entity, data.WorldControl) catch null) |control| if (control.action == .lightning or control.action == .lightning_bolt) {
            try @import("lightning.zig").publish(world, entity, projections);
            continue;
        };
        if (world.get(entity, data.WorldControl) catch null) |control| if (control.action == .particles) {
            try @import("complex_particles.zig").publish(world, entity, projections);
            continue;
        };
        if (world.get(entity, data.WorldControl) catch null) |control| if (control.action == .light) {
            try @import("lights.zig").publish(world, entity, projections);
            continue;
        };
        if (world.get(entity, data.WorldControl) catch null) |control| if (control.action == .spotlight) {
            try @import("spotlights.zig").publish(world, entity, projections);
            continue;
        };
        if (world.get(entity, data.WorldControl) catch null) |control| if (control.action == .earthquake) {
            try @import("earthquakes.zig").publish(world, entity, projections);
            continue;
        };
        if (world.get(entity, data.WorldControl) catch null) |control| if (control.action == .debris) {
            try @import("debris.zig").publish(world, entity, slots, projections);
            continue;
        };
        if (world.get(entity, data.WorldControl) catch null) |control| if (control.action == .healer or control.action == .laser or control.action == .speaker) {
            if (control.action == .laser) {
                try @import("lasers.zig").publish(world, entity, projections);
                continue;
            }
            if (control.action == .healer) {
                try @import("healers.zig").publish(world, entity, projections);
                continue;
            }
            try @import("speakers.zig").publish(world, entity, projections);
            continue;
        };
        if ((world.get(entity, data.Firefly) catch null) != null) {
            try @import("fireflies.zig").publish(world, entity, projections);
            continue;
        }
        if ((world.get(entity, data.Scenery) catch null) != null) {
            try @import("scenery.zig").publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.ThunderSpray) catch null) != null) {
            try @import("thunder_spray.zig").publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.HealthTree) catch null) != null) {
            try @import("healthtrees.zig").publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.DwarfAxe) catch null) != null) {
            try @import("dwarf_axes.zig").publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.ActorAttack) catch null) != null) {
            try @import("actor_attacks.zig").publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.ActorLaser) catch null) != null) {
            try @import("actor_lasers.zig").publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.CryoSpray) catch null) != null) {
            try @import("cryo_spray.zig").publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.FrogSpit) catch null) != null) {
            try @import("frog_spit.zig").publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.Performer) catch null) != null) {
            try @import("cinematics.zig").publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.Actor) catch null) != null) {
            try systems.actors.publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.Pickup) catch null) != null) {
            try @import("items.zig").publish(world, entity, projections);
            continue;
        }
        if ((world.get(entity, data.Projectile) catch null) != null) {
            try @import("projectiles.zig").publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.Charge) catch null) != null) {
            try @import("c4.zig").publish(world, entity, projections, now);
            continue;
        }
        if ((world.get(entity, data.Hammer) catch null) != null) {
            try @import("hammer.zig").publish(world, entity, projections);
            continue;
        }
        if ((world.get(entity, data.Shockwave) catch null) != null) {
            try @import("shockwave.zig").publish(world, entity, projections);
            continue;
        }
        if ((world.get(entity, data.Nova) catch null) != null) {
            try @import("novabeam.zig").publish(world, entity, projections);
            continue;
        }
        if ((world.get(entity, data.Flashlight) catch null) != null) {
            try @import("flashlight.zig").publish(world, entity, projections);
            continue;
        }
        if ((world.get(entity, data.Zeus) catch null) != null or (world.get(entity, data.ZeusBolt) catch null) != null) {
            try @import("zeus.zig").publish(world, entity, projections);
            continue;
        }
        if ((world.get(entity, data.MetaRing) catch null) != null or (world.get(entity, data.MetaLaser) catch null) != null) {
            try @import("metamaser_death.zig").publish(world, entity, projections);
            continue;
        }
        if ((world.get(entity, data.Nightmare) catch null) != null) {
            try @import("nightmare.zig").publish(world, entity, projections);
            continue;
        }
        const object = (try world.get(entity, data.MapObject)).*;
        const body = (try world.get(entity, data.Body)).*;
        const transform = (try world.get(entity, data.Transform)).*;
        const projection = &projections[binding.slot];
        if (object.model.len == 0 and (world.get(entity, data.Train) catch null) != null) {
            projection.state.eType = c.ET_MOVER;
            projection.shared.svFlags = c.SVF_NOCLIENT;
            projection.shared.mins = body.mins;
            projection.shared.maxs = body.maxs;
            try @import("trains.zig").publish(world, entity, projections);
            continue;
        }
        var model: [64]u8 = undefined;
        _ = engine.gateway.call(c.G_SET_BRUSH_MODEL, .{ projection, (try std.fmt.bufPrintZ(&model, "{s}", .{object.model})).ptr });
        projection.state.eType = c.ET_MOVER;
        projection.state.pos = @import("../engine/trajectory.zig").stationary(transform.position);
        projection.state.apos = @import("../engine/trajectory.zig").stationary(transform.angles);
        projection.shared.currentOrigin = transform.position;
        projection.shared.currentAngles = @import("brushes.zig").collisionAngles(object.classname, transform.angles);
        projection.shared.contents = @bitCast(body.contents);
        var hidden = std.mem.startsWith(u8, object.classname, "trigger_") or std.mem.eql(u8, object.classname, "func_clip") or std.mem.eql(u8, object.classname, "func_monsterclip");
        if (world.get(entity, data.Destructible) catch null) |destructible| hidden = hidden or destructible.hidden or destructible.broken;
        if (world.get(entity, data.Wall) catch null) |wall| hidden = hidden or !wall.visible;
        if (hidden) projection.shared.svFlags |= c.SVF_NOCLIENT;
        engine.link(projection);
    };
    @import("lights.zig").styles(world, now);
    try @import("music.zig").restore(world, @import("std").heap.c_allocator);
}
