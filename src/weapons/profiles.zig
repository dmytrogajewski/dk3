// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed Gold animation, audio and muzzle bindings for every native weapon.
//! Common value types used inside concrete weapon definitions.

pub const Animation = struct {
    view_model: [:0]const u8 = "",
    ready: [:0]const u8 = "",
    away: [:0]const u8 = "",
    fire: [:0]const u8 = "",
    idle: [3]?[:0]const u8 = .{ null, null, null },
    alternate: ?[:0]const u8 = null,
    rate: u8 = 20,
    raise_ms: u16 = 0,
    drop_ms: u16 = 0,
};

pub const Audio = struct {
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
    projectile_model: [:0]const u8 = "",
    impact_sprite: [:0]const u8 = "models/global/we_expl.sp2",
    blast_sound: ?[:0]const u8 = null,
    color: [3]f32 = .{ 1, 0.45, 0.12 },
    spin: bool = false,
    /// Constant light around the projectile model.
    glow: bool = true,
};

pub const ProjectileSpawn = struct {
    gravity: bool = false,
    water_collision: bool = false,
    loop_sound: ?[:0]const u8 = null,
    direct_scale: f32 = 1,
    splash_scale: f32 = 0,
    splash_radius: f32 = 128,
    action_delay_ms: u32 = 0,
    lifetime_ms: u32 = 0,
};

pub const Spec = struct {
    ammo_class: ?[:0]const u8 = null,
    /// Rounds in one gold ammo pack; 0 falls back to the initial ammunition.
    ammo_pack: c_int = 0,
    auto_select: bool = true,
    droppable: bool = true,
    companion_pickup: bool = true,
    start_episode: u8 = 0,
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
    audio: Audio = .{},
    visual: Visual = .{},
    projectile: ProjectileSpawn = .{},
    burst_shots: u8 = 0,
    burst_recovery_ms: u16 = 0,
    projectile_muzzle: bool = false,
};
