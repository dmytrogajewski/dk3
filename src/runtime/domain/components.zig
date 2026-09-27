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
pub const Body = struct { mins: Vec3 = .{ -16, -16, -24 }, maxs: Vec3 = .{ 16, 16, 32 }, contents: u32 = 0, collision_mask: u32 = 0, grounded: bool = false, mass: f32 = 100, motion_owner: ?u32 = null };
pub const Health = @import("items.zig").Health;
pub const Actor = @import("actors.zig").State;
pub const Hurt = @import("damage.zig").Receipt;
pub const Hazard = @import("world_actions.zig").Hazard;
pub const Destructible = @import("world_actions.zig").Destructible;
pub const Wall = @import("world_actions.zig").Wall;
pub const WorldControl = @import("world_controls.zig").State;
pub const TargetSequence = @import("world_actions.zig").Sequence;
pub const Exit = @import("travel.zig").Exit;
pub const Projectile = @import("combat.zig").Projectile;
pub const Melee = @import("melee.zig").State;
pub const WeaponLaunch = struct { owner: u32, weapon: u5, sequence: i32, charge: i32, execute_ms: i64 };
pub const Charge = @import("weapon_catalog").c4.Charge;
pub const Hammer = @import("weapon_catalog").hammer.Action;
pub const Shockwave = @import("weapon_catalog").shockwave.Wave;
pub const Nova = @import("weapon_catalog").novabeam.Discharge;
pub const Flashlight = @import("weapon_catalog").flashlight.Light;
pub const Zeus = @import("weapon_catalog").zeus.Chain;
pub const ZeusBolt = @import("weapon_catalog").zeus.Bolt;
pub const Nightmare = @import("weapon_catalog").nightmare.Ritual;
pub const MetaRing = @import("weapon_catalog").metamaser.Ring;
pub const Cinematic = @import("cinematics.zig").Playback;
pub const Companion = @import("companions.zig").State;
pub const Session = @import("multiplayer.zig").Session;
pub const Objective = @import("multiplayer.zig").Objective;
pub const Monitor = struct { duration_ms: i32 = 3000, viewer: ?u32 = null, until_ms: ?i64 = null, camera: u32 = 0, target: u32 = 0, origin: Vec3 = @splat(0), angles: Vec3 = @splat(0) };
pub const Performer = @import("cinematics.zig").Performer;
pub const ThunderSpray = @import("actor_catalog").thunderskeet.Spray;
pub const HealthTree = @import("item_catalog").healthtree.State;
pub const Script = @import("actions.zig").Execution;
pub const WispSwarm = @import("actor_catalog").wisp.Swarm;
pub const Firefly = @import("actor_catalog").firefly.State;
pub const Scenery = @import("scenery.zig").State;
pub const DwarfAxe = @import("actor_catalog").dwarf.Axe;
pub const ActorAttack = @import("actor_attack.zig").State;
pub const ActorLaser = @import("actor_catalog").laser.State;
pub const CryoSpray = @import("actor_catalog").cryotech.Spray;
pub const FrogSpit = @import("actor_catalog").froginator.Spit;
pub const MetaLaser = @import("weapon_catalog").metamaser.Laser;
pub const SoundEvent = struct { sound: u16, subject: u16, channel: u8 };
pub const ImpactEvent = struct { weapon: u5, kind: @import("weapon_catalog").impact_rules.Kind, normal: Vec3, charged: bool = false, detonation: bool = false, sequence: i32 = 0, trail: bool = false, no_blood: bool = false };
pub const Character = @import("character.zig").State;
pub const Ailments = @import("character.zig").Ailments;
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
pub const ComponentId = enum(u6) { transform = 0, velocity = 1, body = 2, health = 3, random = 4, binding = 5, map_object = 6, lifetime = 7, attachment = 8, gravity = 9, motion = 10, inventory = 11, player = 12, weapons = 13, mover = 14, trigger = 15, train = 16, rotation = 17, secret = 18, keys = 19, pickup = 20, item_motion = 21, character = 22, ailments = 23, sound_event = 24, projectile = 25, actor = 26, hurt = 27, hazard = 28, destructible = 29, wall = 30, target_sequence = 31, exit = 32, impact_event = 33, melee = 34, weapon_launch = 35, charge = 36, hammer = 37, shockwave = 38, nova = 39, flashlight = 40, zeus = 41, zeus_bolt = 42, nightmare = 43, meta_ring = 44, meta_laser = 45, cinematic = 46, performer = 47, frog_spit = 48, script = 49, health_tree = 50, thunder_spray = 51, monitor = 52, session = 53, objective = 54, companion = 55, dwarf_axe = 56, scenery = 57, firefly = 58, cryo_spray = 59, actor_laser = 60, actor_attack = 61, wisp_swarm = 62, world_control = 63 };
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
    character: Character,
    ailments: Ailments,
    sound_event: SoundEvent,
    projectile: Projectile,
    actor: Actor,
    hurt: Hurt,
    hazard: Hazard,
    destructible: Destructible,
    wall: Wall,
    target_sequence: TargetSequence,
    exit: Exit,
    impact_event: ImpactEvent,
    melee: Melee,
    weapon_launch: WeaponLaunch,
    charge: Charge,
    hammer: Hammer,
    shockwave: Shockwave,
    nova: Nova,
    flashlight: Flashlight,
    zeus: Zeus,
    zeus_bolt: ZeusBolt,
    nightmare: Nightmare,
    meta_ring: MetaRing,
    meta_laser: MetaLaser,
    cinematic: Cinematic,
    performer: Performer,
    frog_spit: FrogSpit,
    script: Script,
    health_tree: HealthTree,
    thunder_spray: ThunderSpray,
    monitor: Monitor,
    session: Session,
    objective: Objective,
    companion: Companion,
    dwarf_axe: DwarfAxe,
    scenery: Scenery,
    firefly: Firefly,
    cryo_spray: CryoSpray,
    actor_laser: ActorLaser,
    actor_attack: ActorAttack,
    wisp_swarm: WispSwarm,
    world_control: WorldControl,
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
