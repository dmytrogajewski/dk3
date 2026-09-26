// SPDX-License-Identifier: GPL-2.0-or-later
//! Runtime data only: no engine imports or callbacks.
const std = @import("std");
pub const Inventory = @import("inventory_rules").Inventory;
pub const Weapons = @import("weapons.zig").State;
pub const Trigger = struct { uses: u32 = 0, limit: u32 = 0, ready_ms: i64 = 0, wait_ms: i32 = 200, counter: bool = false };
pub const Rotation = @import("special_movers.zig").Rotation;
pub const Secret = @import("special_movers.zig").Secret;
pub const Train = @import("trains.zig").Train;
pub const Mover = @import("movers.zig").Binary;
pub const Player = @import("player_move.zig").Player;
pub const Vec3 = [3]f32;
pub const Transform = @import("poses.zig").Pose;
pub const Velocity = struct { linear: Vec3 = @splat(0) };
pub const Body = struct { mins: Vec3 = .{ -16, -16, -24 }, maxs: Vec3 = .{ 16, 16, 32 }, contents: u32 = 0, collision_mask: u32 = 0, grounded: bool = false };
pub const Health = @import("items.zig").Health;
pub const Keys = @import("items.zig").Keys;
pub const Pickup = @import("items.zig").Pickup;
pub const ItemMotion = @import("item_motion.zig").State;
pub const Random = struct {
    state: u32,
    pub fn next(self: *Random) f32 {
        self.state = self.state *% 1664525 +% 1013904223;
        return @as(f32, @floatFromInt(self.state >> 8)) / 16777216;
    }
};
pub const Binding = struct { slot: u16, model: u16 = 0 };
pub const Property = struct { key: []const u8, value: []const u8 };
pub const MapObject = struct { properties: []const Property = &.{}, classname: []const u8, targetname: []const u8 = "", target: []const u8 = "", model: []const u8 = "", flags: u32 = 0 };
pub const Gravity = struct { acceleration: f32 = 800 };
pub const Motion = struct { destination: Vec3 = @splat(0), velocity: Vec3 = @splat(0) };
pub const Lifetime = struct { expires_ms: i64 };
pub const Attachment = struct { parent_id: u32, offset: Vec3 };
pub const ComponentId = enum(u6) { transform = 0, velocity = 1, body = 2, health = 3, random = 4, binding = 5, map_object = 6, lifetime = 7, attachment = 8, gravity = 9, motion = 10, inventory = 11, player = 12, weapons = 13, mover = 14, trigger = 15, train = 16, rotation = 17, secret = 18, keys = 19, pickup = 20, item_motion = 21 };
pub const Component = union(ComponentId) {
    transform: Transform,
    velocity: Velocity,
    body: Body,
    health: Health,
    random: Random,
    binding: Binding,
    map_object: MapObject,
    lifetime: Lifetime,
    attachment: Attachment,
    gravity: Gravity,
    motion: Motion,
    inventory: Inventory,
    player: Player,
    weapons: Weapons,
    mover: Mover,
    trigger: Trigger,
    train: Train,
    rotation: Rotation,
    secret: Secret,
    keys: Keys,
    pickup: Pickup,
    item_motion: ItemMotion,
};
pub const types = blk: {
    const fields = std.meta.fields(Component);
    var result: [fields.len]type = undefined;
    for (fields, 0..) |field, i| {
        if (@intFromEnum(@field(ComponentId, field.name)) != i) @compileError("component registry order must preserve explicit IDs");
        result[i] = field.type;
    }
    break :blk result;
};
pub const World = @import("../ecs/world.zig").World(types);
pub const Commands = @import("../ecs/commands.zig").Commands(World, Component);
