// SPDX-License-Identifier: GPL-2.0-or-later
//! Explicit owner-thread barriers: activation, deadlines, collision, arrival, targets.
const data = @import("../domain/components.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Router = @import("targets.zig").Router;
const binary = @import("movers.zig");
const trains = @import("trains.zig");
const special = @import("special_movers.zig");
pub const State = struct {
    multiplayer: @import("multiplayer.zig").State = .{},
    inline_models: u16 = 1,
    cinematics: @import("cinematics.zig").State = .{},
    scripts: @import("scripts.zig").State = .{},
    actors: @import("actors.zig").Actors = .{},
    navigation: @import("../engine/navigation.zig").Navigation = .{},
    pub fn deinit(self: *State) void {
        self.navigation.deinit();
    }
    pub fn spawn(self: *State, allocator: @import("std").mem.Allocator, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64, episode: u8, table: *const @import("../domain/weapons.zig").Table) !void {
        {
            var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
            defer query.deinit();
            while (query.next()) |view| for (view.read(data.MapObject)) |object| if (object.model.len > 1 and object.model[0] == '*') {
                self.inline_models = @max(self.inline_models, 1 + try @import("std").fmt.parseInt(u16, object.model[1..], 10));
            };
        }
        try @import("spawn_filter.zig").apply(world);
        try @import("brushes.zig").spawn(world, slots, projections);
        try binary.spawn(world, slots, projections);
        try @import("monitors.zig").spawn(world);
        try @import("targets.zig").spawn(world);
        try @import("world_controls.zig").spawn(world, projections, now);
        try @import("music.zig").restore(world, allocator);
        try @import("companion_triggers.zig").spawn(world, projections);
        try @import("campaign.zig").spawn(world);
        try @import("world_actions.zig").spawn(allocator, world, projections);
        try trains.spawn(world, slots, projections, now);
        try special.spawn(world, slots, projections, now);
        try @import("items.zig").spawn(world, slots, projections, now, episode);
        try @import("healthtrees.zig").spawn(world, slots, projections, now);
        self.actors.weapons = table.*;
        try self.actors.spawn(allocator, world, slots, projections, now, episode);
        try @import("fireflies.zig").spawn(world, slots, projections, now);
        try @import("wisps.zig").spawn(world, slots, projections, now);
        try @import("scenery.zig").spawn(allocator, world, slots, projections, now);
        try @import("attachments.zig").spawn(world);
        try self.multiplayer.spawn(world, slots, projections, episode, now);
        try self.cinematics.spawn(allocator, world);
        try self.scripts.init(allocator, world);
        try self.navigation.init(allocator, now);
    }
    pub fn step(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, targets: *Router, now: i64, elapsed: u32, table: *const @import("../domain/weapons.zig").Table) !void {
        try @import("events.zig").expire(world, slots, projections, now);
        try @import("interactions.zig").touch(world, slots, projections, targets, now);
        try binary.prepare(world, slots, projections, now);
        try trains.prepare(world, slots, projections, now);
        try special.prepare(world, slots, projections, now);
        try binary.step(world, slots, projections, now, elapsed);
        try trains.step(world, slots, projections, now, elapsed);
        try special.step(world, slots, projections, now, elapsed);
        try @import("pusher.zig").staticRoots(world, slots, projections, now, elapsed);
        const arrivals = try binary.finish(world, slots, projections, now);
        const train_arrivals = try trains.finish(world, slots, projections, now);
        const secret_arrivals = try special.finish(world, slots, projections, now);
        for (arrivals.entities[0..arrivals.count]) |entity| {
            if (!world.alive(entity)) continue;
            try targets.fire(world, slots, projections, entity, (try world.get(entity, data.Mover)).owner, now);
        }
        for (secret_arrivals.entities[0..secret_arrivals.count]) |entity| {
            if (!world.alive(entity)) continue;
            try targets.fire(world, slots, projections, entity, (try world.get(entity, data.Secret)).owner, now);
        }
        for (train_arrivals.entities[0..train_arrivals.count]) |entity| {
            if (!world.alive(entity)) continue;
            const train = (try world.get(entity, data.Train)).*;
            if (world.find(train.destination)) |point| {
                const object = (try world.get(point, data.MapObject)).*;
                const name = @import("properties.zig").text(object, "pathtarget") orelse "";
                try targets.fireNamed(world, slots, projections, name, entity, train.owner, now);
            }
        }
        try @import("projectiles.zig").step(world, slots, projections, now);
        try @import("c4.zig").step(world, slots, projections, now);
        try @import("hammer.zig").step(world, slots, projections, now);
        try @import("shockwave.zig").step(world, slots, projections, now);
        try @import("trident.zig").step(world, slots, projections, now);
        try @import("ballista.zig").step(world, slots, projections, now);
        try @import("novabeam.zig").step(world, slots, projections, now);
        try @import("flashlight.zig").step(world, slots, projections, now);
        try @import("discus.zig").step(world, slots, projections, table, now);
        try @import("sunflare.zig").step(world, slots, projections, now);
        try @import("stavros.zig").step(world, slots, projections, now);
        try @import("zeus.zig").step(world, slots, projections, now);
        try @import("wyndrax.zig").step(world, slots, projections, now);
        try @import("nightmare.zig").step(world, slots, projections, now);
        try @import("metamaser.zig").step(world, slots, projections, now);
        try @import("weapon_launches.zig").step(world, slots, projections, table, now);
        try @import("melee.zig").step(world, slots, projections, table, now);
        try @import("thunder_spray.zig").step(world, slots, projections, now);
        try @import("dwarf_axes.zig").step(world, slots, projections, now);
        try @import("frog_spit.zig").step(world, slots, projections, now);
        try @import("cryo_spray.zig").step(world, slots, projections, now);
        try @import("actor_lasers.zig").step(world, slots, projections, now);
        try @import("environment.zig").step(world, slots, projections, self.actors.episode, now);
        try @import("ailments.zig").step(world, now);
        try @import("monitors.zig").step(world, slots, now);
        try self.navigation.frame(now);
        self.navigation.sync(projections);
        if (!@import("cinematics.zig").active(world)) try self.actors.step(world, slots, projections, targets, self.navigation.service(), now, elapsed);
        if (!@import("cinematics.zig").active(world)) try @import("companions.zig").combat(&self.actors, world, slots, projections, table, now, elapsed);
        try @import("actor_attacks.zig").step(world, slots, projections, now);
        try @import("wisps.zig").step(world, slots, projections, now);
        try @import("fireflies.zig").step(world, slots, projections, now, elapsed);
        try @import("scenery.zig").step(world, slots, projections, targets, now, elapsed);
        try @import("healthtrees.zig").step(world, slots, projections, now, elapsed);
        try @import("items.zig").step(world, slots, projections, targets, table, now, elapsed);
        try targets.step(world, slots, projections, now);
        try @import("world_controls.zig").step(world, slots, projections, targets, now);
        if (!@import("cinematics.zig").active(world)) try self.scripts.step(world, slots, projections, &self.actors, targets, now);
        try @import("world_actions.zig").step(world, slots, projections, targets, now);
        try self.multiplayer.step(world, slots, projections, targets, now);
    }
};
