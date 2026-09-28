// SPDX-License-Identifier: GPL-2.0-or-later
//! Explicit migration of persistent references from independent visited saves.
//! Slots, counters, random seeds, masks and resource indices are never identities.
const std = @import("std");
const data = @import("components.zig");
pub const Mapping = struct {
    namespace: u7,
    old_player: u32,
    player: u32,
    pub fn id(self: Mapping, value: u32) !u32 {
        if (value == 0) return 0;
        if (value > 0xffffff) return error.InvalidLegacyIdentity;
        if (value == self.old_player) return self.player;
        return (@as(u32, self.namespace) << 24) | value;
    }
    fn one(self: Mapping, value: *u32) !void {
        value.* = try self.id(value.*);
    }
    fn optional(self: Mapping, value: *?u32) !void {
        if (value.*) |*id_value| try self.one(id_value);
    }
    fn fields(self: Mapping, value: anytype, comptime names: anytype) !void {
        inline for (names) |name| try self.one(&@field(value, name));
    }
    fn many(self: Mapping, values: []u32) !void {
        for (values) |*value| try self.one(value);
    }
};
pub fn remap(comptime kind: data.ComponentId, value: *data.types[@intFromEnum(kind)], map: Mapping) !void {
    switch (kind) {
        .body => try map.optional(&value.motion_owner),
        .attachment => try map.one(&value.parent_id),
        .mover, .secret => try map.fields(value, .{ "group", "owner" }),
        .train => try map.fields(value, .{ "destination", "owner" }),
        .target_sequence => try map.one(&value.activator),
        .exit => try map.one(&value.ending_player),
        .hurt => try map.one(&value.source),
        .ailments => {
            try map.one(&value.freeze_source);
            if (value.poison) |*poison| try map.one(&poison.source);
            if (value.warp) |*warp| try map.one(&warp.source);
        },
        .actor => {
            try map.fields(value, .{ "path", "threat" });
            try map.one(&value.audio.threat);
            try map.one(&value.fish.owner);
            try map.one(&value.shark.suspended_target);
            try map.one(&value.cambot.alarmed);
            try map.one(&value.medusa.target);
            try map.fields(&value.wyndrax, .{ "source", "charge" });
            try map.one(&value.ghost.owner);
        },
        .projectile => {
            try map.one(&value.owner);
            switch (value.flight) {
                .trident => |*flight| try map.fields(flight, .{ "leader", "left", "right" }),
                .ballista => |*flight| {
                    try map.optional(&flight.victim);
                    try map.optional(&flight.last_victim);
                },
                .discus => |*flight| try map.optional(&flight.target),
                .wyndrax => |*flight| {
                    try map.optional(&flight.enemy);
                    try map.many(&flight.targets);
                },
                .metamaser => |*flight| {
                    for (&flight.targets) |*track| try map.one(&track.target);
                    for (&flight.acquired) |*track| try map.one(&track.target);
                },
                .ion, .bolter, .sidewinder, .cordite, .venom, .kineticore, .shockwave, .sunflare, .stavros => {},
            }
        },
        .melee, .weapon_launch, .charge, .hammer, .shockwave, .nova, .flashlight, .thunder_spray, .dwarf_axe, .frog_spit, .cryo_spray, .actor_laser => try map.one(&value.owner),
        .zeus => {
            try map.one(&value.owner);
            try map.many(&value.targets);
        },
        .zeus_bolt => try map.fields(value, .{ "owner", "chain", "source", "target" }),
        .nightmare => {
            try map.one(&value.owner);
            try map.many(&value.targets);
            try map.optional(&value.victim);
        },
        .meta_ring, .meta_laser => try map.fields(value, .{ "owner", "cube" }),
        .cinematic => try map.fields(value, .{ "trigger", "exit", "viewer" }),
        .script => {
            try map.one(&value.activator);
            for (&value.stack) |*frame| try map.one(&frame.activator);
        },
        .companion => try map.fields(value, .{ "owner", "target", "collecting", "avoided_item" }),
        .monitor => {
            try map.optional(&value.viewer);
            try map.fields(value, .{ "camera", "target" });
        },
        .objective => try map.optional(&value.carrier),
        .actor_attack => {
            try map.one(&value.owner);
            switch (value.attack) {
                inline .knight_zap, .npc_wisp, .wyndrax_zap, .nharre_reaper => |*attack| try map.one(&attack.target),
                .wyndrax_bolt => |*attack| try map.fields(attack, .{ "parent", "target" }),
                .fireball, .knight_punch, .rocket, .rotworm_spit, .shaft, .prisoner_rock, .sludge_glob, .gunner_burst, .meteor, .summon_effect, .psyclaw_sphere => {},
            }
        },
        .firefly => try map.one(&value.source),
        .wisp_swarm => {
            try map.many(&value.children);
            try map.one(&value.consumer);
        },
        .world_control => switch (value.action) {
            .chest => |*control| try map.one(&control.opener),
            .lightning => |*control| {
                try map.many(&control.attractors);
                try map.one(&control.current);
            },
            .lightning_bolt => |*control| try map.fields(control, .{ "emitter", "target" }),
            inline .light_ramp, .spotlight, .laser => |*control| try map.one(&control.target),
            .debris => |*control| try map.fields(control, .{ "owner", "activator" }),
            .healer => |*control| try map.one(&control.recipient),
            inline .timer, .toggle => |*control| try map.one(&control.activator),
            .blood_cloud, .target_effect, .weather, .attractor, .particles, .light, .earthquake, .gib_emitter, .room, .speaker, .push, .teleport, .secret, .music, .console, .remove_item => {},
        },
        .transform, .velocity, .health, .random, .binding, .map_object, .lifetime, .gravity, .motion, .inventory, .player, .weapons, .trigger, .rotation, .keys, .pickup, .item_motion, .character, .sound_event, .hazard, .destructible, .wall, .impact_event, .performer, .health_tree, .session, .scenery => {},
    }
}

test "legacy reference mapping preserves counters resources and random state" {
    const t = std.testing;
    const map: Mapping = .{ .namespace = 3, .old_player = 7, .player = 0x1000008 };
    var actor: data.Actor = .{ .definition = 0, .uses = 7, .receipt = 7, .threat = 7, .path = 12, .ground_entity = 12, .audio = .{ .threat = 7 }, .cambot = .{ .alarmed = 12 }, .wyndrax = .{ .source = 13, .charge = 14 } };
    try remap(.actor, &actor, map);
    try t.expectEqual(@as(u32, 0x1000008), actor.threat);
    try t.expectEqual(@as(u32, 0x1000008), actor.audio.threat);
    try t.expectEqual(@as(u32, 0x300000c), actor.path);
    try t.expectEqual(@as(u32, 0x300000c), actor.cambot.alarmed);
    try t.expectEqual(@as(u32, 0x300000e), actor.wyndrax.charge);
    try t.expectEqual(@as(u32, 7), actor.uses);
    try t.expectEqual(@as(u32, 7), actor.receipt);
    try t.expectEqual(@as(u16, 12), actor.ground_entity);
    var control: data.WorldControl = .{ .uses = 7, .action = .{ .timer = .{ .activator = 7, .random = 7, .next_ms = 1200 } } };
    try remap(.world_control, &control, map);
    try t.expectEqual(@as(u32, 0x1000008), control.action.timer.activator);
    try t.expectEqual(@as(u32, 7), control.action.timer.random);
    try t.expectEqual(@as(u32, 7), control.uses);
    try t.expectEqual(@as(?i64, 1200), control.action.timer.next_ms);
    var projectile: data.Projectile = .{ .owner = 7, .weapon = 27, .damage = 10, .born_ms = 100, .stepped_ms = 100, .flight = .{ .wyndrax = .{ .enemy = 12, .targets = .{ 7, 12, 0, 0 } } } };
    try remap(.projectile, &projectile, map);
    try t.expectEqual(@as(u32, 0x1000008), projectile.owner);
    try t.expectEqual(@as(?u32, 0x300000c), projectile.flight.wyndrax.enemy);
    try t.expectEqual([4]u32{ 0x1000008, 0x300000c, 0, 0 }, projectile.flight.wyndrax.targets);
    var binding: data.Binding = .{ .slot = 7, .model = 12 };
    try remap(.binding, &binding, map);
    try t.expectEqual(data.Binding{ .slot = 7, .model = 12 }, binding);
    try t.expectError(error.InvalidLegacyIdentity, map.id(0x2000007));
}
