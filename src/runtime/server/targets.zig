// SPDX-License-Identifier: GPL-2.0-or-later
//! Bounded target routing; authored behavior remains in concrete systems.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const named = @import("names.zig").named;
const prop = @import("properties.zig");
const movers = @import("movers.zig");
const c = abi.c;
const Trigger = data.Trigger;
pub const Router = struct {
    pending: @import("../domain/target_actions.zig").Queue = @splat(null),
    depth: usize = 0,
    scripts: ?*const @import("scripts.zig").State = null,
    cinematics: ?*@import("cinematics.zig").State = null,
    actors: ?*@import("actors.zig").Actors = null,
    travel: ?@import("../domain/travel.zig").Request = null,
    pub fn activate(self: *Router, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) anyerror!void {
        return self.activateFrom(world, slots, projections, entity, null, activator, now);
    }
    pub fn activateFrom(self: *Router, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, source: ?ecs.Entity, activator: u32, now: i64) anyerror!void {
        if (self.depth >= 64) return error.TargetCycle;
        self.depth += 1;
        defer self.depth -= 1;
        const object = (try world.get(entity, data.MapObject)).*;
        if (!@import("keys.zig").allows(world, object, activator)) return;
        if ((world.get(entity, data.WorldControl) catch null) != null) return @import("world_controls.zig").use(world, slots, projections, self, entity, activator, now);
        if (@import("companion_triggers.zig").owns(object.classname)) return @import("companion_triggers.zig").use(self.actors orelse return error.MissingActorDefinitions, world, slots, projections, entity, activator, now);
        if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .rockgat) {
            if ((try world.get(entity, data.Health)).current > 0) {
                actor.rockgat.use();
                actor.think_ms = now + 100;
            }
            return;
        };
        if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .labmonkey) {
            if ((try world.get(entity, data.Health)).current > 0) {
                actor.ignore_player = false;
                const actors = self.actors orelse return error.MissingActorDefinitions;
                try @import("actor_perception.zig").acquire(world, slots, entity, actor, (try world.get(entity, data.Transform)).*, actors.table.definitions[actor.definition], now);
            }
            return;
        };
        if (self.scripts) |scripts| if (try scripts.use(world, entity, activator, now)) return;
        if ((world.get(entity, data.Monitor) catch null) != null) return @import("monitors.zig").use(world, slots, projections, entity, activator, now);
        if (std.mem.eql(u8, object.classname, "target_monster_spawn")) return @import("actor_spawns.zig").use(self.actors orelse return error.MissingActorDefinitions, world, slots, projections, entity, source, now);
        if ((world.get(entity, data.HealthTree) catch null) != null) return @import("healthtrees.zig").use(world, slots, projections, entity, activator, now);
        if (std.mem.eql(u8, object.classname, "trigger_script")) {
            const trigger = try world.get(entity, data.Trigger);
            if (now < trigger.ready_ms or (trigger.limit > 0 and trigger.uses >= trigger.limit)) return;
            if (prop.nonempty(object, "cinescript")) {
                const cine = self.cinematics orelse return error.MissingCinematicPrograms;
                if (!try cine.trigger(world, entity, prop.text(object, "cinescript").?, activator)) return;
                const used = try world.get(entity, data.Trigger);
                used.uses += 1;
                used.ready_ms = now + used.wait_ms;
                return;
            }
            const name = prop.text(object, "aiscript") orelse return error.MissingAuthoredScript;
            try (self.scripts orelse return error.MissingScriptPrograms).start(world, entity, name, activator, true);
            const used = try world.get(entity, data.Trigger);
            used.uses += 1;
            used.ready_ms = now + used.wait_ms;
            return;
        }
        if (world.get(entity, data.Exit) catch null) |exit| {
            if (now < exit.ready_ms or self.travel != null) return;
            const player = world.find(activator) orelse return;
            const state = world.get(player, data.Player) catch return;
            if ((state.mode != .normal and !(state.mode == .frozen and @import("cinematics.zig").active(world))) or (try world.get(player, data.Health)).current <= 0) return;
            exit.ready_ms = now + 1000;
            self.travel = .{ .exit = try world.persistentId(entity), .player = activator };
            return;
        }
        if (std.mem.eql(u8, object.classname, "trigger_changetarget")) {
            const next = prop.text(object, "newtarget") orelse return error.MissingNewTarget;
            const matches = try named(world, object.target);
            for (matches.ids[0..matches.count]) |id| if (world.find(id)) |target| {
                (try world.get(target, data.MapObject)).target = next;
            };
            return;
        }
        if (try @import("world_actions.zig").activate(world, slots, projections, self, entity, activator, now)) return;
        if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .protopod) {
            actor.pod.use(now);
            return;
        };
        if (world.get(entity, data.Mover)) |_| return movers.use(world, slots, projections, entity, activator, now) else |_| {}
        if ((world.get(entity, data.Secret) catch null) != null or (world.get(entity, data.Rotation) catch null) != null) {
            if (try @import("special_movers.zig").use(world, slots, projections, entity, activator, now)) try self.fire(world, slots, projections, entity, activator, now);
            return;
        }
        if (world.get(entity, data.Train)) |_| return @import("trains.zig").use(world, projections, entity, source, activator, now) else |_| {}
        if (std.mem.eql(u8, object.classname, "trigger_elevator")) {
            const matches = try named(world, object.target);
            if (matches.count > 0) if (world.find(matches.ids[0])) |train| {
                if (world.get(train, data.Train)) |_| try @import("trains.zig").use(world, projections, train, source, activator, now) else |_| {}
            };
            return;
        }
        if (world.get(entity, data.Trigger)) |trigger| {
            if (now < trigger.ready_ms or (trigger.limit > 0 and trigger.uses >= trigger.limit)) return;
            trigger.uses += 1;
            if (trigger.counter and trigger.uses < trigger.limit) return;
            trigger.ready_ms = now + trigger.wait_ms;
            try self.fire(world, slots, projections, entity, activator, now);
        } else |_| {}
    }
    pub fn fire(self: *Router, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) anyerror!void {
        const object = (try world.get(entity, data.MapObject)).*;
        const delay = try prop.milliseconds(object, "delay", 0);
        if (delay < 0 or delay > 3600000) return error.InvalidTargetDelay;
        if (delay > 0) {
            for (&self.pending) |*item| if (item.* == null) {
                item.* = .{ .source = try world.persistentId(entity), .activator = activator, .due_ms = now + delay };
                return;
            };
            return error.TargetQueueCapacity;
        }
        try self.dispatch(world, slots, projections, entity, activator, now);
    }
    pub fn fireImmediate(self: *Router, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) anyerror!void {
        try self.dispatch(world, slots, projections, entity, activator, now);
    }
    fn dispatch(self: *Router, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) anyerror!void {
        const object = (try world.get(entity, data.MapObject)).*;
        const own_id = try world.persistentId(entity);
        const killed = prop.text(object, "killtarget") orelse "";
        if (killed.len > 0) {
            const victims = try named(world, killed);
            for (victims.ids[0..victims.count]) |id| {
                if (id == own_id) continue;
                const victim = world.find(id) orelse continue;
                try @import("monitors.zig").stop(world, victim);
                if (slots.find(victim)) |slot| {
                    engine.unlink(&projections[slot]);
                    try slots.release(slot, victim);
                }
                try world.destroy(victim);
            }
        }
        for ([_][]const u8{ object.target, prop.text(object, "target2") orelse "", prop.text(object, "target3") orelse "", prop.text(object, "target4") orelse "" }) |name| {
            if (name.len == 0) continue;
            const matches = try named(world, name);
            for (matches.ids[0..matches.count]) |id| {
                if (!world.alive(entity)) return;
                if (id == own_id) continue;
                if (world.find(id)) |target| try self.activateFrom(world, slots, projections, target, entity, activator, now);
            }
        }
    }
    pub fn fireNamed(self: *Router, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, name: []const u8, source: ecs.Entity, activator: u32, now: i64) anyerror!void {
        if (name.len == 0) return;
        const matches = try named(world, name);
        for (matches.ids[0..matches.count]) |id| {
            if (!world.alive(source)) return;
            if (world.find(id)) |entity| try self.activateFrom(world, slots, projections, entity, source, activator, now);
        }
    }
    pub fn step(self: *Router, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
        // Newly scheduled work waits until the next frame, preserving a bounded barrier.
        const current = self.pending;
        for (current, 0..) |entry, index| if (entry) |action| {
            if (action.due_ms > now) continue;
            self.pending[index] = null;
            if (world.find(action.source)) |entity| try self.dispatch(world, slots, projections, entity, action.activator, now);
        };
    }
};
pub fn spawn(world: *data.World) !void {
    var entities: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| {
            for ([_][]const u8{ "trigger_once", "trigger_multiple", "trigger_relay", "trigger_counter", "trigger_script" }) |name| if (std.mem.eql(u8, object.classname, name)) {
                entities[count] = entity;
                count += 1;
                break;
            };
        };
    }
    for (entities[0..count]) |entity| {
        const object = (try world.get(entity, data.MapObject)).*;
        if (std.mem.eql(u8, object.classname, "trigger_script")) {
            try world.put(entity, Trigger{ .limit = if (object.flags & 1 != 0) 0 else 1, .wait_ms = try prop.milliseconds(object, "wait", 2) });
            continue;
        }
        const counter = std.mem.eql(u8, object.classname, "trigger_counter");
        const limit = try prop.number(object, "count", if (counter) 2 else 0);
        const wait = try prop.milliseconds(object, "wait", 0);
        try world.put(entity, Trigger{ .limit = if (std.mem.eql(u8, object.classname, "trigger_once")) 1 else if (counter) @intFromFloat(@max(1, limit)) else @intFromFloat(@max(0, limit)), .counter = counter, .wait_ms = if (wait > 0) wait else 200 });
    }
}
