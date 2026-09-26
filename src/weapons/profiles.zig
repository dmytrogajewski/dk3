// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed Gold animation, audio and muzzle bindings for every native weapon.
//! Common value types used inside concrete weapon definitions.

pub const Animation = struct {
    view_model: [:0]const u8 = "",
    ready: [:0]const u8 = "",
    away: [:0]const u8 = "",
    fire: [:0]const u8 = "",
    fire_variants: [4]?[:0]const u8 = @splat(null),
    reload: ?[:0]const u8 = null,
    idle: [3]?[:0]const u8 = .{ null, null, null },
    alternate: ?[:0]const u8 = null,
    rate: u8 = 20,
    raise_ms: u16 = 0,
    drop_ms: u16 = 0,
    hold_fire: bool = false,
    fire_loop: bool = false,
    fire_end: ?[:0]const u8 = null,
    fire_start_ms: i16 = 0,
    finish_ms: u16 = 0,
    scale_fire_rate: bool = true,
    charge: ?struct { max_frame: u16, frame_ms: u16, sound: [:0]const u8, sound_ms: u16 } = null,
    reselect: ?[:0]const u8 = null,
};
pub const AttackAnimation = struct { pose: [:0]const u8, rate: u16 };

pub const Audio = struct {
    /// Gold weaponTouch / ammo_touch defaults; individual classes override ammunition.
    pickup: [:0]const u8 = "global/i_pickup6.wav",
    ammo_pickup: [:0]const u8 = "global/i_c4ammo.wav",
    fire: ?[:0]const u8 = null,
    variants: [3]?[:0]const u8 = .{ null, null, null },
    ready: ?[:0]const u8 = null,
    away: ?[:0]const u8 = null,
    reload: ?[:0]const u8 = null,
    finish: ?[:0]const u8 = null,
    /// Gold SND_WEAPON_STD: looped on the holder while selected.
    hum: ?[:0]const u8 = null,
    /// Gold SND_AMBIENT_STD..: played with the matching idle animation.
    idle: [3]?[:0]const u8 = .{ null, null, null },
};

pub const Visual = struct {
    projectile_scale: f32 = 1,
    projectile_sprite: ?[:0]const u8 = null,
    resting_sprite: ?[:0]const u8 = null,
    sprite_additive: bool = true,
    projectile_model: [:0]const u8 = "",
    impact_sprite: [:0]const u8 = "models/global/we_expl.sp2",
    blast_sound: ?[:0]const u8 = null,
    color: [3]f32 = .{ 1, 0.45, 0.12 },
    spin: bool = false,
    /// Constant light around the projectile model.
    glow: bool = true,
    fade_stuck: bool = true,
};

pub const ProjectileSpawn = struct {
    mins: [3]f32 = @splat(-1),
    maxs: [3]f32 = @splat(1),
    recoil: f32 = 0,
    recoil_on_launch: bool = false,
    sound_on_launch: bool = true,
    inertial: bool = false,
    aim_range: f32 = 2000,
    self_splash: f32 = 0.5,
    gravity: bool = false,
    water_collision: bool = false,
    loop_sound: ?[:0]const u8 = null,
    direct_scale: f32 = 1,
    splash_scale: f32 = 0,
    splash_radius: f32 = 128,
    action_delay_ms: u32 = 0,
    lifetime_ms: u32 = 0,
    lifetime_scale: f32 = 1,
    collide_owner_after_bounce: bool = false,
    contact_when_resting: bool = false,
    remove_when_resting: bool = false,
    resting_lifetime_scale: f32 = 0,
};
pub const Muzzle = struct {
    model: [:0]const u8,
    sprite: bool = false,
    delay_ms: u16 = 0,
    animation: [:0]const u8 = "stand",
    shader: ?[:0]const u8 = null,
    scale: f32 = 1,
    alpha: u8 = 153,
    offset: f32 = 0,
    light_radius: f32 = 150,
    color: [3]f32 = .{ 0.8, 0.4, 0.2 },
};

pub const Combat = union(enum) {
    pending,
    projectile,
    melee,
    charge,
    hammer,
    shockwave,
    trident,
    ballista,
    novabeam,
    flashlight,
    discus,
    sunflare,
    stavros,
    hitscan: struct { single_player_scale: f32 = 1, standing_height: ?f32 = null, crouching_height: ?f32 = null, inertial: bool = false },
    pellets: struct { count: u8, spread: f32, single_player_scale: f32 = 1, range: f32 = 4000, aim_reach: bool = false, max_victims: u8 = 12, inertial: bool = false, recoil: f32 = 0 },
    ion: struct { radius: f32, water_radius: f32, bounce_retention: f32, max_bounces: u8, cleanup_ms: i64 },
};

pub const Spec = struct {
    reselect_command: ?[:0]const u8 = null,
    combat: Combat = .pending,
    impact: @import("impact.zig").Style = .none,
    ammo_class: ?[:0]const u8 = null,
    /// Rounds in one gold ammo pack; 0 falls back to the initial ammunition.
    ammo_pack: c_int = 0,
    auto_select: bool = true,
    droppable: bool = true,
    companion_pickup: bool = true,
    start_episode: u8 = 0,
    campaign_equipment: bool = false,
    companion_episode: u8 = 0,
    splash_hazard: bool = false,
    bot_charge_ms: c_int = 0,
    bot_range: ?f32 = null,
    protects_water: bool = false,
    inventory_view_model: bool = false,
    world_model: ?[:0]const u8 = null,
    /// Pickup and equipped representations have independent contracts.
    equipped: bool = true,
    equipped_frame: c_int = 4,
    animation: Animation = .{},
    muzzle: ?Muzzle = null,
    audio: Audio = .{},
    visual: Visual = .{},
    projectile: ProjectileSpawn = .{},
    burst_shots: u8 = 0,
    burst_recovery_ms: u16 = 0,
    projectile_muzzle: bool = false,
};
