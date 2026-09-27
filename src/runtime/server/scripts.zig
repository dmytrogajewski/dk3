// SPDX-License-Identifier: GPL-2.0-or-later
//! Supplied actor action execution. Programs are immutable; cursors live in saves.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/actions.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
pub fn unique(world: *data.World, name: []const u8) ?ecs.Entity {
    if (name.len == 0) return null;
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| {
        const id = if (world.get(entity, data.Actor) catch null) |actor| actor.unique else prop.text(object, "uniqueid") orelse "";
        if (std.ascii.eqlIgnoreCase(id, name)) return entity;
    };
    return null;
}
pub fn named(world: *data.World, name: []const u8) ?ecs.Entity {
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (std.ascii.eqlIgnoreCase(object.targetname, name)) return entity;
    return null;
}
pub const State = struct {
    program: rules.Program = .{},
    pub fn init(self: *State, allocator: std.mem.Allocator, world: *data.World) !void {
        var map: [64]u8 = undefined;
        var program_path: [100]u8 = undefined;
        const filename = try std.fmt.bufPrintZ(&program_path, "dk3/actions/{s}.cfg", .{@import("persistence.zig").mapName(&map)});
        var handle: abi.c.fileHandle_t = 0;
        const size = engine.gateway.call(abi.c.G_FS_FOPEN_FILE, .{ filename.ptr, &handle, @as(isize, abi.c.FS_READ) });
        if (handle != 0) _ = engine.gateway.call(abi.c.G_FS_FCLOSE_FILE, .{@as(isize, handle)});
        if (size < 0) {
            var objects = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
            defer objects.deinit();
            while (objects.next()) |view| for (view.read(data.MapObject)) |object| if (prop.nonempty(object, "aiscript")) return error.MissingAuthoredActionProgram;
            return; // Maps without authored AI actions have no converted program.
        }
        const bytes = try @import("../engine/files.zig").read(.server, &engine.gateway, allocator, filename, 4 * 1024 * 1024);
        self.program = try rules.Program.parse(allocator, bytes);
        var root: ?ecs.Entity = null;
        var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
        {
            defer query.deinit();
            while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (std.mem.eql(u8, object.classname, "worldspawn")) {
                root = entity;
            };
        }
        if (root) |entity| if (self.program.find("$level_start")) |script| if (script.actions.len > 0) try self.start(world, entity, "$level_start", 0, true);
    }
    pub fn admit(self: *const State, world: *data.World) !void {
        var query = world.queryAccess(data.World.mask(.{data.Script}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.read(data.Script)) |execution| {
            const script = self.program.find(execution.name) orelse return error.UnavailableSavedScript;
            if (execution.index > script.actions.len or execution.depth > execution.stack.len) return error.InvalidSavedScriptCursor;
            for (execution.stack[0..execution.depth]) |frame| {
                const parent = self.program.find(frame.name) orelse return error.UnavailableSavedScript;
                if (frame.index > parent.actions.len or frame.remaining < -1 or frame.remaining > 10000) return error.InvalidSavedScriptCursor;
            }
        };
    }
    pub fn use(self: *const State, world: *data.World, entity: ecs.Entity, activator: u32, now: i64) !bool {
        const actor = world.get(entity, data.Actor) catch return false;
        const program = self.program.onUse(actor.unique) orelse return false;
        if (now < actor.use_ready_ms) return true;
        actor.uses += 1;
        actor.use_ready_ms = now + program.loops;
        var selected: ?rules.Action = null;
        for (program.actions) |action| {
            if (std.ascii.eqlIgnoreCase(action.name, "idle") and selected == null) selected = action;
            if ((std.fmt.parseInt(u32, action.name, 10) catch 0) == actor.uses) {
                selected = action;
                break;
            }
        }
        if (selected) |action| {
            if (action.args.len == 0) return error.EmptyUsedAction;
            const random = (try world.get(entity, data.Random)).next();
            const index = if (std.ascii.eqlIgnoreCase(action.name, "idle")) @min(action.args.len - 1, @as(usize, @intFromFloat(random * @as(f32, @floatFromInt(action.args.len))))) else 0;
            try self.launch(world, entity, action.args[index], activator, true, true);
        }
        return true;
    }
    pub fn start(self: *const State, world: *data.World, caller: ecs.Entity, name: []const u8, activator: u32, use_owner: bool) !void {
        return self.launch(world, caller, name, activator, use_owner, false);
    }
    fn launch(self: *const State, world: *data.World, caller: ecs.Entity, name: []const u8, activator: u32, use_owner: bool, when_used: bool) !void {
        const script = self.program.find(name) orelse {
            var text: [128]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&text, "dk3 script: unavailable authored request {s}\n", .{name}));
            return; // Reference absent script lookup is a no-op, not a fabricated action.
        };
        const entity = if (use_owner and script.owner.len > 0) unique(world, script.owner) orelse return else caller;
        if (world.get(entity, data.Health) catch null) |health| if (health.current <= 0) return;
        var next: data.Script = .{ .name = script.name, .remaining = script.loops, .active = true, .activator = activator, .revision = 1, .when_used = when_used };
        if (world.get(entity, data.Script) catch null) |prior| {
            next.revision = prior.revision +% 1;
            // Ordinary script goals replace ordinary script goals. A player-use
            // goal interrupts the current goal and resumes it when finished.
            if (prior.active and (when_used or prior.when_used)) {
                if (prior.depth == prior.stack.len) return error.ScriptCallDepth;
                next.stack = prior.stack;
                next.depth = prior.depth + 1;
                next.stack[prior.depth] = .{ .name = prior.name, .index = prior.index, .remaining = prior.remaining, .when_used = prior.when_used, .activator = prior.activator };
            }
        }
        if ((world.get(entity, data.Random) catch null) == null) try world.put(entity, data.Random{ .state = try world.persistentId(entity) });
        try world.put(entity, next);
        if (world.get(entity, data.Actor) catch null) |actor| actor.scripted_pose = null;
    }
    pub fn step(self: *const State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, actors: *@import("actors.zig").Actors, router: *@import("targets.zig").Router, now: i64) anyerror!void {
        var entities: [ecs.max_entities]ecs.Entity = undefined;
        var count: usize = 0;
        var query = world.queryAccess(data.World.mask(.{data.Script}), 0, 0);
        {
            defer query.deinit();
            while (query.next()) |view| for (view.entities()) |entity| {
                entities[count] = entity;
                count += 1;
            };
        }
        for (entities[0..count]) |entity| {
            if (!world.alive(entity)) continue;
            if (world.get(entity, data.Health) catch null) |health| if (health.current <= 0) continue;
            if (world.get(entity, data.Actor) catch null) |actor| {
                if (actor.surgeon.active or (@import("actor_catalog").entries[actor.definition].kind == .civilian and actor.mode == .flee)) {
                    if (actor.script_paused_ms == null) actor.script_paused_ms = now;
                    continue;
                }
                if (actor.script_paused_ms) |paused| {
                    const interval = now - paused;
                    const execution = try world.get(entity, data.Script);
                    if (execution.started) execution.due_ms += interval;
                    execution.next_ms += interval;
                    if (actor.scripted_pose != null) actor.scripted_ms += interval;
                    actor.script_paused_ms = null;
                }
            }
            for (0..1024) |_| {
                var execution = (try world.get(entity, data.Script)).*;
                if (!execution.active or now < execution.next_ms) break;
                const script = self.program.find(execution.name) orelse return error.MissingRunningScript;
                if (execution.index >= script.actions.len) {
                    if (execution.remaining > 1 or execution.remaining == -1) {
                        if (execution.remaining > 1) execution.remaining -= 1;
                        execution.index = 0;
                    } else if (execution.depth > 0) {
                        execution.depth -= 1;
                        const frame = execution.stack[execution.depth];
                        execution.name = frame.name;
                        execution.index = frame.index;
                        execution.remaining = frame.remaining;
                        execution.when_used = frame.when_used;
                        execution.activator = frame.activator;
                        execution.started = false;
                        execution.moving = false;
                    } else execution.active = false;
                    (try world.get(entity, data.Script)).* = execution;
                    if (world.get(entity, data.Actor) catch null) |actor| actor.scripted_pose = null;
                    break;
                }
                const action = script.actions[execution.index];
                const args = action.args;
                if (std.mem.eql(u8, action.name, "spawn")) {
                    if (args.len < 7 or args.len > 9 or (!std.ascii.eqlIgnoreCase(args[6], "false") and !std.ascii.eqlIgnoreCase(args[6], "true"))) return error.InvalidScriptSpawnOptions;
                    if (unique(world, args[1]) != null) return error.DuplicateScriptActor;
                    const child = try actors.spawnDynamic(world, slots, projections, args[0], .{ try rules.number(args[2]), try rules.number(args[3]), try rules.number(args[4]) }, .{ 0, try rules.number(args[5]), 0 }, now);
                    (try world.get(child, data.Actor)).unique = args[1];
                    (try world.get(child, data.Actor)).ignore_player = std.ascii.eqlIgnoreCase(args[6], "false");
                    if (args.len > 7) (try world.get(child, data.MapObject)).targetname = args[7];
                    if (args.len > 8) {
                        const object = try world.get(child, data.MapObject);
                        const properties = try actors.allocator.alloc(data.Property, object.properties.len + 1);
                        @memcpy(properties[0..object.properties.len], object.properties);
                        properties[object.properties.len] = .{ .key = "deathtarget", .value = args[8] };
                        object.properties = properties;
                    }
                    var text: [140]u8 = undefined;
                    engine.print(try std.fmt.bufPrintZ(&text, "dk3 script: spawned {s} id={d} class={s}\n", .{ args[1], try world.persistentId(child), args[0] }));
                } else if (std.mem.eql(u8, action.name, "set_state")) {
                    if (args.len < 2 or args.len > 3) return error.InvalidSetState;
                    if (unique(world, args[0])) |target| if (world.get(target, data.Actor) catch null) |actor| {
                        if (std.ascii.eqlIgnoreCase(args[1], "ignore_player")) {
                            actor.ignore_player = true;
                            actor.threat = 0;
                            actor.mode = .idle;
                        } else if (std.ascii.eqlIgnoreCase(args[1], "aggressive")) {
                            actor.ignore_player = false;
                        } else if (std.ascii.eqlIgnoreCase(args[1], "pathfollow")) {
                            if (args.len != 3) return error.MissingScriptPath;
                            const point = named(world, args[2]) orelse return error.MissingScriptPath;
                            actor.path = try world.persistentId(point);
                            actor.route = .{};
                        } else return error.UnsupportedActorScriptState;
                    };
                } else if ((std.mem.eql(u8, action.name, "send_message") or std.mem.eql(u8, action.name, "send_urgent_message"))) {
                    if (args.len != 2) return error.InvalidScriptMessage;
                    if (unique(world, args[0])) |target| try self.start(world, target, args[1], execution.activator, true);
                } else if (std.mem.eql(u8, action.name, "call") or std.mem.eql(u8, action.name, "random_script")) {
                    if (args.len == 0 or (std.mem.eql(u8, action.name, "call") and args.len != 1)) return error.InvalidScriptCall;
                    const random = (try world.get(entity, data.Random)).next();
                    const index = if (std.mem.eql(u8, action.name, "call")) 0 else @min(args.len - 1, @as(usize, @intFromFloat(random * @as(f32, @floatFromInt(args.len)))));
                    execution.index += 1;
                    execution.started = false;
                    (try world.get(entity, data.Script)).* = execution;
                    try self.start(world, entity, args[index], execution.activator, std.mem.eql(u8, action.name, "random_script"));
                    continue;
                } else if (std.mem.eql(u8, action.name, "wait")) {
                    if (args.len != 1) return error.InvalidScriptWait;
                    if (!execution.started) {
                        const seconds = try rules.number(args[0]);
                        if (seconds < 0 or seconds > 3600) return error.InvalidScriptWait;
                        execution.started = true;
                        execution.due_ms = now + @as(i64, @intFromFloat(seconds * 1000));
                    }
                    if (now < execution.due_ms) {
                        (try world.get(entity, data.Script)).* = execution;
                        break;
                    }
                } else if (std.mem.eql(u8, action.name, "move_to")) {
                    if (args.len != 3) return error.InvalidScriptDestination;
                    execution.destination = .{ try rules.number(args[0]), try rules.number(args[1]), try rules.number(args[2]) };
                    execution.moving = true;
                    const pose = (try world.get(entity, data.Transform)).*;
                    if (@import("../domain/navigation.zig").horizontalDistance(pose.position, execution.destination) > 20 or @abs(pose.position[2] - execution.destination[2]) > 32) {
                        (try world.get(entity, data.Script)).* = execution;
                        break;
                    }
                    execution.moving = false;
                } else if (std.mem.eql(u8, action.name, "attack")) {
                    if (args.len != 1) return error.InvalidScriptAttack;
                    const victim = unique(world, args[0]) orelse return error.MissingScriptVictim;
                    const actor = try world.get(entity, data.Actor);
                    actor.threat = try world.persistentId(victim);
                    actor.threat_position = (try world.get(victim, data.Transform)).position;
                    actor.ignore_player = false;
                } else if (std.mem.eql(u8, action.name, "sound") or std.mem.eql(u8, action.name, "stream_sound")) {
                    if (args.len < 1 or args.len > 2) return error.InvalidScriptSound;
                    const speaker = if (args.len == 2) unique(world, args[1]) orelse return error.MissingScriptSpeaker else entity;
                    if (std.mem.eql(u8, action.name, "stream_sound")) {
                        for (args[0]) |ch| if (ch < 32 or ch == '"' or ch == '\\') return error.InvalidScriptSound;
                        var command: [320]u8 = undefined;
                        const text = try std.fmt.bufPrintZ(&command, "dk3_cine_sound 0 2 \"{s}\"", .{args[0]});
                        _ = engine.gateway.call(abi.c.G_SEND_SERVER_COMMAND, .{ @as(isize, -1), text.ptr });
                    } else {
                        const pose = (try world.get(speaker, data.Transform)).*;
                        const slot: u16 = if (world.get(speaker, data.Binding) catch null) |binding| binding.slot else abi.c.ENTITYNUM_NONE;
                        try @import("events.zig").sound(world, slots, projections, args[0], pose.position, slot, abi.c.CHAN_VOICE, now);
                    }
                } else if (std.mem.eql(u8, action.name, "remove")) {
                    if (args.len != 1) return error.InvalidScriptRemoval;
                    if (unique(world, args[0])) |target| {
                        if (slots.find(target)) |slot| {
                            engine.unlink(&projections[slot]);
                            try slots.release(slot, target);
                        }
                        try world.destroy(target);
                    }
                } else if (std.mem.eql(u8, action.name, "print")) {
                    if (args.len != 1) return error.InvalidScriptPrint;
                    var text: [384]u8 = undefined;
                    engine.print(try std.fmt.bufPrintZ(&text, "dk3 script: {s}\n", .{args[0]}));
                } else if (std.mem.eql(u8, action.name, "use")) {
                    if (args.len != 1) return error.InvalidScriptUse;
                    if (unique(world, args[0]) orelse named(world, args[0])) |target| try router.activate(world, slots, projections, target, execution.activator, now);
                } else if (std.mem.eql(u8, action.name, "face_angle")) {
                    if (args.len != 3) return error.InvalidScriptAngle;
                    const actor = try world.get(entity, data.Actor);
                    const pose = try world.get(entity, data.Transform);
                    const speed = actors.table.definitions[actor.definition].yaw_speed;
                    const delta = @mod(try rules.number(args[1]) - pose.angles[1] + 180, 360) - 180;
                    if (!execution.started) {
                        execution.started = true;
                        execution.due_ms = now + 5000;
                    }
                    if (@abs(delta) > speed * 0.1 and now < execution.due_ms) {
                        pose.angles[1] = @mod(pose.angles[1] + std.math.clamp(delta, -speed, speed), 360);
                        execution.next_ms = now + 100;
                        (try world.get(entity, data.Script)).* = execution;
                        break;
                    }
                } else if (std.mem.eql(u8, action.name, "animate") or std.mem.eql(u8, action.name, "set_moving_animation")) {
                    if (args.len < 1 or args.len > 2) return error.InvalidScriptAnimation;
                    const actor = try world.get(entity, data.Actor);
                    const sequence = try actors.findSequence(actor.definition, args[0]);
                    if (sequence) |pose| {
                        if (std.mem.eql(u8, action.name, "set_moving_animation")) actor.moving_pose = pose else {
                            if (!execution.started) {
                                execution.started = true;
                                execution.due_ms = now + if (args.len == 2) @as(i64, @intFromFloat(try rules.number(args[1]) * 1000)) else pose.duration();
                                actor.scripted_pose = pose;
                                actor.scripted_ms = now;
                            }
                            if (now < execution.due_ms) {
                                (try world.get(entity, data.Script)).* = execution;
                                break;
                            }
                            actor.scripted_pose = null;
                        }
                    }
                } else {
                    var text: [192]u8 = undefined;
                    engine.print(try std.fmt.bufPrintZ(&text, "dk3 script: unsupported {s} action={s} index={d}\n", .{ script.name, action.name, execution.index }));
                    return error.UnsupportedAuthoredAction;
                }
                if (!world.alive(entity)) break;
                // A script can replace its own action program through a message/use.
                if ((try world.get(entity, data.Script)).revision != execution.revision) break;
                execution.index += 1;
                execution.started = false;
                (try world.get(entity, data.Script)).* = execution;
            } else return error.ScriptActionBudget;
        }
    }
};

pub fn path(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *@import("targets.zig").Router, actor_entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, speed: f32, now: i64) !?v.Vec3 {
    const corner = world.find(actor.path) orelse {
        actor.path = 0;
        return null;
    };
    const point = (try world.get(corner, data.Transform)).position;
    const distance = @import("../domain/navigation.zig").horizontalDistance(pose.position, point);
    const tolerance = @max(20, speed * (if (speed > 175) @as(f32, 0.1) else 0.2));
    if (distance >= tolerance or @abs(pose.position[2] - point[2]) >= 32) return point;
    const object = (try world.get(corner, data.MapObject)).*;
    var choices: [4][]const u8 = undefined;
    var count: usize = 0;
    for ([_][]const u8{ prop.text(object, "target1") orelse object.target, prop.text(object, "target2") orelse "", prop.text(object, "target3") orelse "", prop.text(object, "target4") orelse "" }) |name| {
        if (name.len == 0) break;
        choices[count] = name;
        count += 1;
    }
    actor.path = 0;
    if (count > 0) {
        const random = try world.get(actor_entity, data.Random);
        const index = @min(count - 1, @as(usize, @intFromFloat(random.next() * @as(f32, @floatFromInt(count)))));
        if (named(world, choices[index])) |next| actor.path = try world.persistentId(next);
    }
    if (prop.text(object, "aiscript")) |name| if (router.scripts) |scripts| try scripts.start(world, actor_entity, name, try world.persistentId(actor_entity), true);
    if (prop.text(object, "pathtarget")) |name| {
        const trigger = world.get(corner, data.Trigger) catch null;
        if (trigger == null or trigger.?.uses == 0) {
            try world.put(corner, data.Trigger{ .uses = 1, .limit = 1 });
            try router.fireNamed(world, slots, projections, name, actor_entity, try world.persistentId(actor_entity), now);
        }
    }
    var text: [128]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 path: actor={d} corner={s} next={d}\n", .{ try world.persistentId(actor_entity), object.targetname, actor.path }));
    return null;
}
