// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored camera shots, performer queues and brush uses for the native campaign.
const std = @import("std");
const data = @import("../domain/components.zig");
const rules = @import("../domain/cinematics.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Router = @import("targets.zig").Router;
const Definition = struct {
    classname: []const u8,
    model: []const u8,
    metadata: ?[]const u8 = null,
    scale: v.Vec3 = @splat(1),
    walk: f32 = 25,
    run: f32 = 125,
    yaw: f32 = 20,
    fn sequence(self: Definition, name: []const u8) !?@import("../domain/animation.zig").Sequence {
        return try @import("../domain/animation.zig").find(self.metadata orelse return null, name);
    }
    fn locomotion(self: Definition, running: bool, fallback: @import("../domain/animation.zig").Sequence) !@import("../domain/animation.zig").Sequence {
        const names: []const []const u8 = if (running) &.{ "runa", "run", "runb" } else &.{ "walka", "walk", "walkb" };
        for (names) |name| if (try self.sequence(name)) |value| return value;
        return fallback;
    }
};
pub const State = struct {
    allocator: std.mem.Allocator = undefined,
    programs: [64]struct { name: []const u8, value: rules.Program } = undefined,
    program_count: usize = 0,
    program: ?rules.Program = null,
    name: []const u8 = "",
    definitions: [128]Definition = undefined,
    count: usize = 0,
    pub fn spawn(self: *State, allocator: std.mem.Allocator, world: *data.World) !void {
        engine.register("dk3_cinematics", "1", 0);
        if (engine.integer("g_gametype") != c.GT_SINGLE_PLAYER) return;
        self.allocator = allocator;
        var controller: ?ecs.Entity = null;
        var intro: []const u8 = "";
        var names: [64][]const u8 = undefined;
        var count: usize = 0;
        {
            var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
            defer query.deinit();
            while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| {
                const prop = @import("properties.zig");
                if (std.mem.eql(u8, object.classname, "worldspawn")) {
                    controller = entity;
                    intro = prop.text(object, "cinematic_intro") orelse "";
                }
                const name = prop.text(object, "cinescript") orelse prop.text(object, "cinematic") orelse prop.text(object, "cinematic_intro") orelse "";
                if (name.len == 0) continue;
                var duplicate = false;
                for (names[0..count]) |previous| if (std.mem.eql(u8, previous, name)) {
                    duplicate = true;
                    break;
                };
                if (duplicate) continue;
                if (count == names.len) return error.CinematicProgramCapacity;
                names[count] = name;
                count += 1;
            };
        }
        for (names[0..count]) |name| try self.load(allocator, name);
        if (intro.len > 0 and self.available(intro)) {
            try self.select(intro);
            try world.put(controller orelse return error.MissingCinematicController, data.Cinematic{ .name = intro });
        }
    }
    pub fn available(self: *const State, name: []const u8) bool {
        for (self.programs[0..self.program_count]) |program| if (std.mem.eql(u8, program.name, name)) return true;
        return false;
    }
    fn select(self: *State, name: []const u8) !void {
        for (self.programs[0..self.program_count]) |program| if (std.mem.eql(u8, program.name, name)) {
            self.name = program.name;
            self.program = program.value;
            return;
        };
        return error.UnavailableCinematicProgram;
    }
    pub fn trigger(self: *State, world: *data.World, entity: ecs.Entity, name: []const u8, activator: u32) !bool {
        if (!self.available(name)) return false;
        if (active(world)) return false;
        const player = world.find(activator) orelse return false;
        if ((world.get(player, data.Player) catch return false).mode != .normal) return false;
        if ((try world.get(player, data.Body)).motion_owner != null) return false;
        try self.select(name);
        const controller = findController(world) orelse entity;
        try world.put(controller, data.Cinematic{ .name = self.name, .trigger = try world.persistentId(entity), .viewer = activator });
        return true;
    }
    fn load(self: *State, allocator: std.mem.Allocator, name: []const u8) !void {
        if (!@import("../domain/snapshot.zig").validName(name)) return error.InvalidCinematicName;
        var path: [96]u8 = undefined;
        const program_path = try std.fmt.bufPrintZ(&path, "dk3/cinematics/{s}.cfg", .{name});
        const bytes = try @import("../engine/files.zig").readOptional(.server, &engine.gateway, allocator, program_path, 4 * 1024 * 1024) orelse {
            var warning: [160]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&warning, "dk3 cinematic: unavailable program={s}\n", .{name}));
            return;
        };
        const program = try rules.parse(allocator, bytes);
        if (program.shots.len == 0) return error.EmptyCinematic;
        const tuning = try @import("../engine/files.zig").read(.server, &engine.gateway, allocator, "dk3/tables/aidata.cfg", 4 * 1024 * 1024);
        var map_buffer: [64]u8 = undefined;
        const map_name = @import("persistence.zig").mapName(&map_buffer);
        for (program.shots) |shot| for (shot.tracks) |track| {
            if (!program.needsDefinition(track)) continue;
            if (self.definition(track.classname) != null) continue;
            if (self.count == self.definitions.len) return error.CinematicClassCapacity;
            var actor_definition: Definition = .{ .classname = track.classname, .model = "" };
            // Cine classes select the supplied map-family performance model.
            const prefix: ?[]const u8 = if (std.mem.startsWith(u8, track.classname, "cine_")) blk: {
                const aliases = .{ .{ "superfly", "super" }, .{ "toshiro", "tosh" }, .{ "gharroth", "ghar" }, .{ "pgharroth", "pghar" }, .{ "charon", "char" }, .{ "fatworker", "fat" }, .{ "thinworker", "thin" } };
                inline for (aliases) |alias| if (std.mem.eql(u8, track.classname[5..], alias[0])) break :blk alias[1];
                break :blk track.classname[5..];
            } else null;
            var reader = try @import("../domain/tables.zig").Reader.init(tuning);
            while (try reader.next()) |row| {
                if (!std.mem.eql(u8, row.field("classname") orelse "", track.classname)) continue;
                actor_definition.model = row.field("model_name") orelse return error.MissingCinematicModel;
                actor_definition.walk = try row.number("walk_speed", 25);
                actor_definition.run = try row.number("run_speed", 125);
                if (row.field("render_scale")) |scale| if (scale.len > 0) {
                    actor_definition.scale = try @import("map.zig").vector(scale);
                };
                if (row.field("angle_speed")) |speed| if (speed.len > 0) {
                    actor_definition.yaw = (try @import("map.zig").vector(speed))[1];
                };
            }
            if (prefix) |stem| actor_definition.model = try std.fmt.allocPrint(allocator, "models/cinematic/c_{s}_{s}.dkm", .{ stem, map_name[0..@min(4, map_name.len)] });
            if (actor_definition.model.len == 0) {
                for (program.tasks[track.first..][0..track.count]) |task| if (task.kind == .spawn) return error.UnknownCinematicClass;
                // Commands may address an absent actor. The reference leaves
                // that command without a recipient; it does not create one.
                continue;
            }
            const metadata_path = try std.fmt.bufPrintZ(&path, "{s}.anim", .{actor_definition.model});
            actor_definition.metadata = try @import("../engine/files.zig").readOptional(.server, &engine.gateway, allocator, metadata_path, 1 << 20);
            if (actor_definition.metadata == null) {
                if (!program.controlOnly(track.classname)) return error.MissingCinematicModel;
                // Keep the timed authored use/removal, without rendering a
                // replacement actor for absent control-carrier media.
                var warning: [180]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&warning, "dk3 cinematic: control carrier has no media class={s} model={s}\n", .{ track.classname, actor_definition.model }));
                actor_definition.model = "";
            }
            self.definitions[self.count] = actor_definition;
            self.count += 1;
        };
        if (self.program_count == self.programs.len) return error.CinematicProgramCapacity;
        self.programs[self.program_count] = .{ .name = name, .value = program };
        self.program_count += 1;
    }
    fn definition(self: *const State, classname: []const u8) ?Definition {
        for (self.definitions[0..self.count]) |definition_value| if (std.mem.eql(u8, definition_value.classname, classname)) return definition_value;
        return null;
    }
    pub fn admit(self: *State, world: *data.World) !void {
        if (findController(world)) |controller| try self.select((try world.get(controller, data.Cinematic)).name);
        var query = world.queryAccess(0, 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            if (world.get(entity, data.Cinematic) catch null) |playback| {
                const program = self.program orelse return error.UnavailableSavedCinematic;
                if (!std.mem.eql(u8, self.name, playback.name)) return error.SavedCinematicMismatch;
                if (playback.shot >= program.shots.len and !playback.finished) return error.InvalidSavedCinematicShot;
                if (!playback.finished) {
                    const shot = program.shots[playback.shot];
                    if (playback.sounds > shot.sounds.len) return error.InvalidSavedCinematicSound;
                    for (shot.tracks, playback.queued[0..shot.tracks.len]) |track, cursor| if (cursor > track.count) return error.InvalidSavedCinematicTask;
                }
            }
            if (world.get(entity, data.Performer) catch null) |performer| {
                const program = self.program orelse return error.UnavailableSavedCinematic;
                _ = self.definition(performer.classname) orelse return error.UnavailableSavedCinematicActor;
                for (performer.queue[0..performer.count]) |task| if (task >= program.tasks.len) return error.InvalidSavedCinematicTask;
            }
        };
    }
    pub fn step(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, player: ?ecs.Entity, now: i64) !void {
        const program = self.program orelse return;
        const viewer = player orelse return;
        const controller = findController(world) orelse return;
        var playback = (try world.get(controller, data.Cinematic)).*;
        if (playback.finished) return;
        if (engine.integer("dk3_cinematics") == 0) {
            try completePlayback(world, slots, projections, router, viewer, now);
            return;
        }
        if (!playback.active) {
            playback.active = true;
            playback.started_ms = now;
            try @import("weapon_actions.zig").cancel(world, slots, projections, viewer);
            (try world.get(viewer, data.Body)).motion_owner = try world.persistentId(controller);
            playback.viewer = try world.persistentId(viewer);
            (try world.get(viewer, data.Player)).mode = .frozen;
            (try world.get(viewer, data.Velocity)).linear = @splat(0);
            engine.print("dk3 cinematic: started\n");
        }
        var shot = program.shots[playback.shot];
        var elapsed = now - playback.started_ms;
        // Finish each shot's due tasks before advancing, including exact-end removals.
        try self.queue(world, slots, projections, program, shot, &playback, elapsed, now);
        try self.perform(world, slots, projections, router, viewer, now);
        if (elapsed >= shot.duration() and (!shot.end_on_actor or done(world, shot.end_name))) {
            playback.inherited = shot.camera(elapsed, playback.inherited);
            playback.shot += 1;
            if (playback.shot >= program.shots.len) {
                (try world.get(controller, data.Cinematic)).* = playback;
                try completePlayback(world, slots, projections, router, viewer, now);
                return;
            }
            engine.send(0, "dk3_cine_cut");
            playback.started_ms = now;
            playback.sounds = 0;
            playback.queued = @splat(0);
            shot = program.shots[playback.shot];
            elapsed = 0;
            var text: [96]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&text, "dk3 cinematic: shot={d}/{d} name={s}\n", .{ playback.shot + 1, program.shots.len, playback.name }));
            try self.queue(world, slots, projections, program, shot, &playback, elapsed, now);
        }
        (try world.get(controller, data.Cinematic)).* = playback;
    }
    fn queue(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, program: rules.Program, shot: rules.Shot, playback: *rules.Playback, elapsed: i64, now: i64) !void {
        for (shot.tracks, 0..) |track, index| {
            while (playback.queued[index] < track.count) {
                const task_id = track.first + playback.queued[index];
                const task = program.tasks[task_id];
                if (task.when * 1000 > @as(f32, @floatFromInt(elapsed))) break;
                const unique = if (task.unique.len > 0) task.unique else track.unique;
                var actor = resolveActor(world, task.kind, unique, track.classname);
                if (actor == null) if (@import("scripts.zig").unique(world, unique)) |existing| {
                    if ((world.get(existing, data.Actor) catch null) != null) {
                        try self.adopt(world, existing, track.classname, unique, now);
                        actor = existing;
                    }
                };
                switch (task.kind) {
                    .spawn => {
                        if (actor) |existing| {
                            (try world.get(existing, data.Transform)).* = .{ .position = task.destination, .angles = task.angles };
                            playback.queued[index] += 1;
                            continue;
                        }
                        const definition_value = self.definition(track.classname) orelse return error.UnknownCinematicClass;
                        const idle: @import("../domain/animation.zig").Sequence = try definition_value.sequence("amba") orelse .{};
                        const movement = try definition_value.sequence("walka") orelse idle;
                        const entity = try world.create(null, .{ data.Transform{ .position = task.destination, .angles = task.angles }, data.Performer{ .unique = unique, .classname = track.classname, .model = definition_value.model, .scale = definition_value.scale, .walk_speed = definition_value.walk, .run_speed = definition_value.run, .yaw_speed = definition_value.yaw, .animation = idle, .idle = idle, .movement = movement, .animation_ms = now, .next_ms = now }, data.Body{ .mins = .{ -12, -12, -24 }, .maxs = .{ 12, 12, 30 }, .contents = 0, .collision_mask = c.MASK_SOLID } });
                        const slot = try slots.acquire(entity, null);
                        try world.put(entity, data.Binding{ .slot = slot, .model = try @import("resources.zig").model(definition_value.model) });
                        try publish(world, entity, projections, now);
                    },
                    .remove => if (actor) |entity| {
                        try remove(world, slots, projections, entity);
                    },
                    .clear => if (actor) |entity| {
                        const performer = try world.get(entity, data.Performer);
                        performer.count = 0;
                        performer.started = false;
                        performer.animation = performer.idle;
                        performer.animation_ms = now;
                        performer.velocity = @splat(0);
                    },
                    else => if (actor) |entity| {
                        const performer = try world.get(entity, data.Performer);
                        if (task.kind == .animation and try self.definition(performer.classname).?.sequence(task.animation) == null) {
                            // Gold QueueAnimation ignores absent sequence names. The supplied
                            // intro requests Usagi's absent amba after nodd in shot 34.
                            var warning: [180]u8 = undefined;
                            engine.print(try std.fmt.bufPrintZ(&warning, "dk3 cinematic: absent animation ignored class={s} sequence={s}\n", .{ performer.classname, task.animation }));
                            playback.queued[index] += 1;
                            continue;
                        }
                        if (task.kind == .teleport and performer.count != 0) break;
                        if (performer.count == performer.queue.len) return error.CinematicQueueCapacity;
                        performer.queue[performer.count] = task_id;
                        performer.count += 1;
                    } else if (task.kind != .none) {
                        var warning: [256]u8 = undefined;
                        engine.print(try std.fmt.bufPrintZ(&warning, "dk3 cinematic: absent recipient class={s} unique={s} task={s}\n", .{ track.classname, unique, @tagName(task.kind) }));
                    },
                }
                playback.queued[index] += 1;
            }
        }
        while (playback.sounds < shot.sounds.len) {
            const sound = shot.sounds[playback.sounds];
            if (sound.when * 1000 > @as(f32, @floatFromInt(elapsed))) break;
            var text: [160]u8 = undefined;
            if (std.mem.indexOfScalar(u8, sound.path, '"') != null or sound.path.len >= c.MAX_QPATH) return error.InvalidCinematicSound;
            engine.send(0, try std.fmt.bufPrintZ(&text, "dk3_cine_sound {d} {d} {s}", .{ @intFromBool(sound.loop), sound.channel, sound.path }));
            playback.sounds += 1;
        }
    }
    fn adopt(self: *State, world: *data.World, entity: ecs.Entity, classname: []const u8, unique: []const u8, now: i64) !void {
        const definition_value = self.definition(classname) orelse return error.UnknownCinematicClass;
        const binding = (try world.get(entity, data.Binding)).*;
        const body = (try world.get(entity, data.Body)).*;
        const idle = try definition_value.sequence("amba") orelse try definition_value.sequence("aamba") orelse @import("../domain/animation.zig").Sequence{};
        const walking = try definition_value.sequence("walka") orelse idle;
        try world.put(entity, data.Performer{ .unique = unique, .classname = classname, .model = definition_value.model, .scale = definition_value.scale, .walk_speed = definition_value.walk, .run_speed = definition_value.run, .yaw_speed = definition_value.yaw, .animation = idle, .idle = idle, .movement = walking, .animation_ms = now, .next_ms = now, .borrowed = true, .original_model = binding.model, .original_contents = body.contents });
        (try world.get(entity, data.Binding)).model = try @import("resources.zig").model(definition_value.model);
        (try world.get(entity, data.Body)).contents = 0;
        (try world.get(entity, data.Velocity)).linear = @splat(0);
    }
    fn perform(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, viewer: ecs.Entity, now: i64) !void {
        const occupants = slots.occupants;
        for (occupants) |occupant| {
            const entity = occupant orelse continue;
            var performer = (world.get(entity, data.Performer) catch continue).*;
            var pose = (try world.get(entity, data.Transform)).*;
            if (now < performer.next_ms) continue;
            const dt = @min(@as(f32, 0.1), @as(f32, @floatFromInt(@max(1, now - performer.next_ms + 100))) * 0.001);
            performer.next_ms = now + 100;
            var budget: usize = 0;
            while (performer.count > 0 and budget < 128) : (budget += 1) {
                const task = self.program.?.tasks[performer.queue[0]];
                const definition_value = self.definition(performer.classname).?;
                if (!performer.started) {
                    performer.started = true;
                    performer.due_ms = now;
                    switch (task.kind) {
                        .animation, .idle => {
                            const sequence = try definition_value.sequence(task.animation) orelse return error.MissingCinematicAnimation;
                            if (task.kind == .idle) performer.idle = sequence else {
                                performer.animation = sequence;
                                performer.animation_ms = now;
                                performer.due_ms = now + sequence.duration();
                            }
                        },
                        .move, .move_turn => {
                            const movement = try definition_value.locomotion(performer.running, performer.movement);
                            performer.animation = if (task.animation.len > 0) try definition_value.sequence(task.animation) orelse movement else movement;
                            performer.animation_ms = now;
                        },
                        .wait => performer.due_ms = now + @as(i64, @intFromFloat(@max(0, task.attribute) * 1000)),
                        .head => {
                            performer.head_ms = now;
                            performer.due_ms = now + @as(i64, @intCast(task.head.len + 1)) * 200;
                        },
                        else => {},
                    }
                }
                var complete = true;
                switch (task.kind) {
                    .animation, .wait => complete = now >= performer.due_ms,
                    .move, .move_turn => {
                        const offset = v.add(task.destination, v.scale(pose.position, -1));
                        const distance = v.length(.{ offset[0], offset[1], 0 });
                        if (distance > 1) {
                            complete = false;
                            const speed = if (performer.running) performer.run_speed else performer.walk_speed;
                            const delta = v.scale(.{ offset[0], offset[1], 0 }, @min(distance, speed * dt) / distance);
                            pose.angles[1] = std.math.atan2(offset[1], offset[0]) * 180 / std.math.pi;
                            var collision = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, delta), .mins = .{ -12, -12, -24 }, .maxs = .{ 12, 12, 30 }, .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID });
                            if (collision.fraction < 1) {
                                // Reuse the game's step-height contract for authored walking.
                                const elevated = v.add(pose.position, .{ 0, 0, 18 });
                                const clearance = try engine.collisionService().trace(.{ .start = pose.position, .end = elevated, .mins = .{ -12, -12, -24 }, .maxs = .{ 12, 12, 30 }, .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID });
                                if (clearance.fraction == 1) collision = try engine.collisionService().trace(.{ .start = elevated, .end = v.add(elevated, delta), .mins = .{ -12, -12, -24 }, .maxs = .{ 12, 12, 30 }, .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID });
                            }
                            pose.position = collision.end;
                        } else if (task.kind == .move_turn) pose.angles[1] = task.angles[1];
                    },
                    .turn => {
                        const delta = @mod(task.angles[1] - pose.angles[1] + 180, 360) - 180;
                        const amount = performer.yaw_speed * dt * 10;
                        pose.angles[1] += @max(-amount, @min(amount, delta));
                        complete = @abs(delta) <= amount;
                    },
                    .teleport => {
                        pose.position = task.destination;
                        pose.angles = task.angles;
                        performer.velocity = @splat(0);
                        performer.ground_entity = c.ENTITYNUM_NONE;
                        projections[(try world.get(entity, data.Binding)).slot].state.eFlags ^= c.EF_TELEPORT_BIT;
                    },
                    .use => {
                        var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
                        var target: ?ecs.Entity = null;
                        {
                            defer query.deinit();
                            while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |candidate, object| {
                                if (std.mem.eql(u8, @import("properties.zig").text(object, "uniqueid") orelse "", task.use) or std.mem.eql(u8, object.targetname, task.use)) {
                                    target = candidate;
                                    break;
                                }
                            };
                        }
                        // e23_timestream's last shot uses "changelevel", a name no
                        // entity carries: the trigger_changelevel that started the
                        // cinematic travels when it ends. A use with no target does nothing.
                        if (target) |found| {
                            try router.activate(world, slots, projections, found, try world.persistentId(viewer), now);
                        } else if (engine.integer("developer") >= 1) {
                            var text: [160]u8 = undefined;
                            engine.print(std.fmt.bufPrintZ(&text, "dk3 cinematic: use target \"{s}\" not found\n", .{task.use[0..@min(task.use.len, 64)]}) catch "");
                        }
                    },
                    .idle, .none => {},
                    .run => performer.running = true,
                    .walk => performer.running = false,
                    .walk_speed => performer.walk_speed = task.attribute,
                    .run_speed => performer.run_speed = task.attribute,
                    .yaw_speed => performer.yaw_speed = task.attribute,
                    .backup => performer.backup = .{ performer.run_speed, performer.walk_speed, performer.yaw_speed },
                    .restore => if (performer.backup) |values| {
                        performer.run_speed = values[0];
                        performer.walk_speed = values[1];
                        performer.yaw_speed = values[2];
                    },
                    .sound => if (task.sound.len > 0) {
                        try @import("events.zig").sound(world, slots, projections, task.sound, pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_VOICE, now);
                    },
                    .head => {
                        pose.angles = task.headAngles(now - performer.head_ms);
                        complete = now >= performer.due_ms;
                    },
                    .spawn, .remove, .clear => unreachable,
                }
                if (!complete) break;
                std.mem.copyForwards(u16, performer.queue[0 .. performer.count - 1], performer.queue[1..performer.count]);
                performer.count -= 1;
                performer.started = false;
                if (performer.count == 0) {
                    performer.animation = performer.idle;
                    performer.animation_ms = now;
                }
            }
            // Cinematic performers are independent, non-damageable actors, but still meet floors.
            performer.velocity[2] -= 800 * dt;
            const floor = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(performer.velocity, dt)), .mins = .{ -12, -12, -24 }, .maxs = .{ 12, 12, 30 }, .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID });
            pose.position = floor.end;
            if (floor.fraction < 1) performer.velocity = @splat(0);
            performer.ground_entity = if (floor.fraction < 1 and floor.normal[2] > 0.7) floor.entity else c.ENTITYNUM_NONE;
            (try world.get(entity, data.Performer)).* = performer;
            (try world.get(entity, data.Transform)).* = pose;
            try publish(world, entity, projections, now);
        }
    }
    pub fn camera(self: *const State, world: *data.World, ps: *c.playerState_t, now: i64) !void {
        ps.dk3CameraActive = 0;
        const controller = findController(world) orelse return;
        const playback = (try world.get(controller, data.Cinematic)).*;
        if (!playback.active or playback.finished) return;
        const shot = self.program.?.shots[playback.shot];
        var view = shot.camera(now - playback.started_ms, playback.inherited);
        if (shot.target) if (findPerformer(world, shot.target_name)) |target| {
            const offset = v.add((try world.get(target, data.Transform)).position, v.scale(view.position, -1));
            view.angles = .{ -std.math.atan2(offset[2], @sqrt(offset[0] * offset[0] + offset[1] * offset[1])) * 180 / std.math.pi, std.math.atan2(offset[1], offset[0]) * 180 / std.math.pi, 0 };
        };
        ps.dk3CameraActive = 1;
        ps.dk3CameraOrigin = view.position;
        ps.dk3CameraAngles = view.angles;
        ps.dk3CameraFov = std.math.clamp(view.fov, 1, 179);
        for (&ps.dk3CameraBlend, view.blend) |*value, color| value.* = std.math.clamp(color / 255, 0, 1);
    }
};
pub fn findController(world: *data.World) ?ecs.Entity {
    var query = world.queryAccess(data.World.mask(.{data.Cinematic}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities()) |entity| return entity;
    return null;
}
pub fn active(world: *data.World) bool {
    if (@import("monitors.zig").active(world)) return true;
    const entity = findController(world) orelse return false;
    return (world.get(entity, data.Cinematic) catch unreachable).active;
}
fn findPerformer(world: *data.World, unique: []const u8) ?ecs.Entity {
    if (unique.len == 0) return null;
    var query = world.queryAccess(data.World.mask(.{data.Performer}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Performer)) |entity, performer| if (std.mem.eql(u8, unique, performer.unique)) return entity;
    return null;
}
fn resolveActor(world: *data.World, kind: rules.TaskKind, unique: []const u8, classname: []const u8) ?ecs.Entity {
    if (findPerformer(world, unique)) |entity| return entity;
    return if (kind == .spawn or kind == .remove) null else findClass(world, classname);
}
// Reference queue lookup tries the unique ID, then the first matching class.
// Authored intro uses both oka1 and osa1 for the same Osaka performer.
fn findClass(world: *data.World, classname: []const u8) ?ecs.Entity {
    var query = world.queryAccess(data.World.mask(.{data.Performer}), 0, 0);
    defer query.deinit();
    var selected: ?ecs.Entity = null;
    var lowest: u32 = std.math.maxInt(u32);
    while (query.next()) |view| for (view.entities(), view.read(data.Performer)) |entity, performer| {
        if (!std.mem.eql(u8, classname, performer.classname)) continue;
        const id = world.persistentId(entity) catch unreachable;
        if (id < lowest) {
            lowest = id;
            selected = entity;
        }
    };
    return selected;
}
fn done(world: *data.World, unique: []const u8) bool {
    const entity = findPerformer(world, unique) orelse return true;
    return (world.get(entity, data.Performer) catch unreachable).count == 0;
}
fn remove(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity) !void {
    const slot = (try world.get(entity, data.Binding)).slot;
    engine.unlink(&projections[slot]);
    try slots.release(slot, entity);
    try world.destroy(entity);
}
/// Natural completion and an explicit skip share cleanup and authored continuation.
pub fn completePlayback(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, player: ecs.Entity, now: i64) !void {
    const controller = findController(world) orelse return;
    const playback = (try world.get(controller, data.Cinematic)).*;
    if (playback.finished) return;
    try finish(world, slots, projections, router, player, now);
    const id = try world.persistentId(player);
    if (playback.exit != 0) router.travel = .{ .exit = playback.exit, .player = id } else if (world.find(playback.trigger)) |trigger| try router.fire(world, slots, projections, trigger, id, now);
}
pub fn finish(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, player: ecs.Entity, now: i64) !void {
    var name: []const u8 = "";
    if (findController(world)) |entity| {
        const playback = try world.get(entity, data.Cinematic);
        if (playback.finished) return;
        name = playback.name;
        playback.active = false;
        playback.finished = true;
        if ((try world.get(player, data.Body)).motion_owner == try world.persistentId(entity)) (try world.get(player, data.Body)).motion_owner = null;
    }
    if (name.len == 0) return;
    for (slots.occupants) |occupant| if (occupant) |entity| {
        if (world.get(entity, data.Performer) catch null) |performer| {
            if (performer.borrowed) {
                (try world.get(entity, data.Binding)).model = performer.original_model;
                (try world.get(entity, data.Body)).contents = performer.original_contents;
                try world.remove(entity, data.Performer);
                projections[(try world.get(entity, data.Binding)).slot].state.modelindex = (try world.get(entity, data.Binding)).model;
                projections[(try world.get(entity, data.Binding)).slot].shared.contents = @bitCast((try world.get(entity, data.Body)).contents);
                engine.link(&projections[(try world.get(entity, data.Binding)).slot]);
            } else try remove(world, slots, projections, entity);
        }
    };
    const state = try world.get(player, data.Player);
    if (state.mode == .frozen) state.mode = if ((try world.get(player, data.Health)).current > 0) .normal else .dead;
    engine.send(0, "dk3_cine_stop");
    // Completion targets run after performers are removed and the viewer is released.
    // Capture identities before routing: a use can remove another completion target.
    var completion: [ecs.max_entities]u32 = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| {
            const prop = @import("properties.zig");
            if (std.mem.eql(u8, prop.text(object, "cinetrigger") orelse "", name) or std.mem.eql(u8, prop.text(object, "cinekill") orelse "", name)) {
                completion[count] = try world.persistentId(entity);
                count += 1;
            }
        };
    }
    for (completion[0..count]) |id| if (world.find(id)) |entity| {
        const object = (try world.get(entity, data.MapObject)).*;
        if (std.mem.eql(u8, @import("properties.zig").text(object, "cinetrigger") orelse "", name)) try router.activate(world, slots, projections, entity, try world.persistentId(player), now);
        if (std.mem.eql(u8, @import("properties.zig").text(object, "cinekill") orelse "", name) and world.alive(entity)) {
            if (slots.find(entity)) |slot| {
                engine.unlink(&projections[slot]);
                try slots.release(slot, entity);
            }
            try world.destroy(entity);
        }
    };
    engine.print("dk3 cinematic: completed\n");
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const performer = (try world.get(entity, data.Performer)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    const body = (try world.get(entity, data.Body)).*;
    const teleport_flag = projection.state.eFlags & c.EF_TELEPORT_BIT;
    projection.* = std.mem.zeroes(abi.EntityProjection);
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.eFlags = teleport_flag;
    projection.state.modelindex = binding.model;
    projection.state.groundEntityNum = performer.ground_entity;
    @import("../engine/animation.zig").publish(&projection.state, .{ .sequence = performer.animation, .started = performer.animation_ms, .looping = performer.count == 0 or (performer.started and now >= performer.due_ms) }, now);
    projection.state.angles2 = performer.scale;
    projection.state.pos = @import("../engine/trajectory.zig").interpolated(pose.position);
    projection.state.apos = @import("../engine/trajectory.zig").interpolated(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = body.mins;
    projection.shared.maxs = body.maxs;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    projection.shared.svFlags = c.SVF_BROADCAST;
    engine.link(projection);
}

pub fn diagnostics(world: *data.World, now: i64) !void {
    var query = world.queryAccess(data.World.mask(.{ data.Performer, data.Transform }), 0, 0);
    defer query.deinit();
    var count: usize = 0;
    while (query.next()) |view| for (view.entities(), view.read(data.Performer), view.read(data.Transform)) |entity, performer, pose| {
        var text: [320]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 performer: id={d} unique={s} class={s} ground={d} queued={d} pos={d:.3},{d:.3},{d:.3} angles={d:.3},{d:.3},{d:.3}\n", .{ try world.persistentId(entity), performer.unique, performer.classname, performer.ground_entity, performer.count, pose.position[0], pose.position[1], pose.position[2], pose.angles[0], pose.angles[1], pose.angles[2] }));
        count += 1;
    };
    var text: [96]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 performers: now={d} count={d}\n", .{ now, count }));
}

test "intro Osaka queue alias resolves by class without duplicating spawn or removal" {
    var world = data.World.init(std.testing.allocator, 8);
    defer world.deinit();
    const original = try world.create(20, .{data.Performer{ .unique = "oka1", .classname = "cine_osaka", .model = "models/cinematic/c_osaka_intr.dkm" }});
    try std.testing.expectEqual(original, resolveActor(&world, .animation, "osa1", "cine_osaka").?);
    try std.testing.expect(resolveActor(&world, .spawn, "osa1", "cine_osaka") == null);
    try std.testing.expect(resolveActor(&world, .remove, "osa1", "cine_osaka") == null);
    const exact = try world.create(21, .{data.Performer{ .unique = "osa1", .classname = "cine_osaka", .model = "models/cinematic/c_osaka_intr.dkm" }});
    try std.testing.expectEqual(exact, resolveActor(&world, .animation, "osa1", "cine_osaka").?);
    try std.testing.expectEqual(exact, resolveActor(&world, .animation, "osa1", "misspelled_class").?);
    try std.testing.expectEqual(exact, resolveActor(&world, .remove, "osa1", "misspelled_class").?);
}

test "an absent class-only recipient cannot bind another unnamed performer" {
    var world = data.World.init(std.testing.allocator, 4);
    defer world.deinit();
    const existing = try world.create(20, .{data.Performer{ .unique = "", .classname = "cine_hero", .model = "models/hero.dkm" }});
    try std.testing.expect(resolveActor(&world, .teleport, "", "absent_actor") == null);
    try std.testing.expectEqual(existing, resolveActor(&world, .teleport, "", "cine_hero").?);
    try std.testing.expect(resolveActor(&world, .spawn, "", "cine_hero") == null);
}
