// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const catalog = @import("actor_catalog");
const v = @import("vector.zig");
const animation = @import("animation.zig");
pub const Mode = enum { idle, flee, chase, attack, reload, dead };
pub const State = struct {
    definition: u8,
    melee: catalog.melee_cycle.State = .{},
    spider: catalog.spider.State = .{},
    cryotech: catalog.cryotech.State = .{},
    surgeon: catalog.surgeon.State = .{},
    cerberus: catalog.cerberus.State = .{},
    thief: catalog.thief.State = .{},
    prisoner: catalog.prisoners.State = .{},
    femgang: catalog.femgang.State = .{},
    evasion: catalog.evasion.State = .{},
    battleboar: catalog.battleboar.State = .{},
    rocketmp: catalog.rocketmp.State = .{},
    rocketgang: catalog.rocketgang.State = .{},
    archer: catalog.archers.State = .{},
    rotworm: catalog.rotworm.State = .{},
    vermin: catalog.vermin.State = .{},
    shark: catalog.shark.State = .{},
    rat: catalog.rats.State = .{},
    knight: catalog.knights.State = .{},
    inmater: catalog.inmater.State = .{},
    lasergat: catalog.lasergat.State = .{},
    lycanthir: catalog.lycanthir.State = .{},
    column: catalog.column.State = .{},
    reaction: ?animation.Sequence = null,
    reaction_started_ms: i64 = 0,
    reaction_until_ms: ?i64 = null,
    death_pose: ?animation.Sequence = null,
    guard: catalog.mishima.State = .{},
    skeeter: catalog.skeeter.State = .{},
    pod: catalog.protopod.State = .{},
    frog: catalog.froginator.State = .{},
    thunder: catalog.thunderskeet.State = .{},
    cambot: catalog.cambot.State = .{},
    crox: catalog.crox.State = .{},
    rockgat: catalog.rockgat.State = .{},
    uses: u32 = 0,
    use_ready_ms: i64 = 0,
    think_ms: i64 = 0,
    unique: []const u8 = "",
    ignore_player: bool = false,
    path: u32 = 0,
    scripted_pose: ?animation.Sequence = null,
    moving_pose: ?animation.Sequence = null,
    scripted_ms: i64 = 0,
    script_paused_ms: ?i64 = null,

    mode: Mode = .idle,
    changed_ms: i64 = 0,
    panic_until: i64 = 0,
    threat: u32 = 0,
    threat_position: v.Vec3 = @splat(0),
    threat_seen_ms: i64 = 0,
    witness_ms: i64 = -1,
    receipt: u32 = 0,
    death_dispatched: bool = false,
    ground_entity: u16 = 2047,
    route: @import("navigation.zig").State = .{},
    escape_until: i64 = 0,
    jump_ready_ms: i64 = 0,
    pub fn panic(self: *State, source: u32, point: v.Vec3, now: i64) void {
        if (self.mode == .dead) return;
        if (self.mode != .flee) self.changed_ms = now;
        self.mode = .flee;
        self.panic_until = now + catalog.entries[self.definition].panic_ms;
        self.threat = source;
        self.threat_position = point;
    }
};
pub const Definition = struct {
    loaded: bool = false,
    pain_c: ?animation.Sequence = null,
    dwarf: catalog.dwarf.Tuning = .{},
    thief_knife: catalog.weapon.Tuning = .{},
    prisoner_rock: catalog.weapon.Tuning = .{},
    alternate_idle: animation.Sequence = .{},
    boar_weapons: [2]catalog.weapon.Tuning = @splat(.{}),
    mp_rockets: [2]catalog.weapon.Tuning = @splat(.{}),
    gang_rockets: [2]catalog.weapon.Tuning = @splat(.{}),
    archer_ranged: catalog.weapon.Tuning = .{},
    rotworm_spit: catalog.weapon.Tuning = .{},
    vermin_rocket: catalog.weapon.Tuning = .{},
    vermin_has_leap: bool = false,
    rat_poison: catalog.weapon.Tuning = .{},
    knight_ranged: catalog.knights.Weapon = .{},
    laser: catalog.laser.Tuning = .{},
    frog: catalog.froginator.Tuning = .{},
    model: []const u8 = "",
    health: i32 = 0,
    mass: f32 = 100,
    speed: f32 = 0,
    walk_speed: f32 = 0,
    mins: v.Vec3 = @splat(0),
    maxs: v.Vec3 = @splat(0),
    idle: animation.Sequence = .{},
    run: animation.Sequence = .{},
    death: animation.Sequence = .{},
    attacks: [8]animation.Sequence = @splat(.{}),
    strikes: [8]u16 = @splat(1),
    second_strikes: [8]?u16 = @splat(null),
    attack_sounds: [8][]const u8 = @splat(""),
    attack_sound_ms: [8]i64 = @splat(0),
    second_attack_sounds: [8][]const u8 = @splat(""),
    second_sound_ms: [8]?i64 = @splat(null),
    swim: animation.Sequence = .{},
    walk: animation.Sequence = .{},
    death_b: animation.Sequence = .{},
    death_d: animation.Sequence = .{},
    awakening: animation.Sequence = .{},
    pain: [2]?animation.Sequence = @splat(null),
    hatch_sound: []const u8 = "",
    reload: animation.Sequence = .{},
    hatch: animation.Sequence = .{},
    sight_range: f32 = 0,
    attack_range: f32 = 0,
    fov: f32 = 180,
    yaw_speed: f32 = 20,
    pitch_speed: f32 = 20,
    upward_speed: f32 = 0,
    jump_strike_ms: i64 = 0,
    jump_distance: f32 = 0,
    damage: f32 = 0,
    random_damage: f32 = 0,
    range: f32 = 0,
    offset: v.Vec3 = @splat(0),
    spread: [2]f32 = @splat(0),
    scale: v.Vec3 = @splat(1),
    pub fn guardTiming(self: Definition) catalog.mishima.Timing {
        var result: catalog.mishima.Timing = undefined;
        for (self.attacks[0..3], self.strikes[0..3], 0..) |sequence, strike, i| {
            result.attack_ms[i] = @divTrunc(@as(i64, sequence.last - sequence.first + 1) * 1000, sequence.fps);
            result.strike_ms[i] = @divTrunc(@as(i64, strike) * 1000, sequence.fps);
        }
        result.reload_ms = @divTrunc(@as(i64, self.reload.last - self.reload.first + 1) * 1000, self.reload.fps);
        result.reload_sound_ms = @divTrunc(@as(i64, catalog.mishima.reload_sound_frame) * 1000, self.reload.fps);
        return result;
    }
};
pub const Table = struct {
    definitions: [catalog.entries.len]Definition = @splat(.{}),
    pub fn parse(bytes: []const u8) !Table {
        var result: Table = .{};
        var reader = try @import("tables.zig").Reader.init(bytes);
        while (try reader.next()) |row| {
            const id = catalog.find(row.field("classname") orelse return error.MissingActorClass) orelse continue;
            const entry = &result.definitions[id];
            if (entry.loaded) return error.DuplicateActorClass;
            entry.model = row.field("model_name") orelse return error.MissingActorModel;
            if (entry.model.len == 0 or entry.model.len >= 64) return error.InvalidActorModel;
            if (catalog.entries[id].kind == .rockgat) {
                // This class reads only its model from aidata; map epairs own the
                // turret tuning. Its hull, mass and default health are class values.
                entry.health = 500;
                entry.mass = 1;
                entry.mins = @splat(-16);
                entry.maxs = @splat(16);
                entry.loaded = true;
                continue;
            }
            const health = try row.number("health", 0);
            entry.speed = try row.number("run_speed", 0);
            entry.walk_speed = try row.number("walk_speed", 0);
            entry.jump_distance = try row.number("jump_attack_distance", 0);
            entry.upward_speed = try row.number("upward_velocity", 0);
            if (entry.upward_speed < 0 or entry.upward_speed > 2000) return error.InvalidActorJump;
            if (health <= 0 or health > 1000000 or entry.speed < 0 or entry.speed > 2000) return error.InvalidActorTuning;
            entry.health = @intFromFloat(health);
            entry.mass = try row.number("mass", 100);
            if (!std.math.isFinite(entry.mass) or entry.mass <= 0 or entry.mass > 100000) return error.InvalidActorMass;
            entry.attack_range = try row.number("attack_distance", 0);
            entry.sight_range = try row.number("active_distance", 1000);
            entry.fov = try row.number("fov", 180);
            if (row.field("angle_speed")) |angles| {
                var parts = std.mem.tokenizeAny(u8, angles, " \t");
                entry.pitch_speed = try std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidActorAngles);
                entry.yaw_speed = try std.fmt.parseFloat(f32, parts.next() orelse return error.InvalidActorAngles);
                if (!std.math.isFinite(entry.pitch_speed) or entry.pitch_speed < 0 or entry.pitch_speed > 360) return error.InvalidActorAngles;
                if (!std.math.isFinite(entry.yaw_speed) or entry.yaw_speed <= 0 or entry.yaw_speed > 360) return error.InvalidActorAngles;
            }
            entry.damage = try row.number("weapon1_base_damage", 0);
            entry.random_damage = try row.number("weapon1_random_damage", 0);
            entry.range = try row.number("weapon1_distance", 0);
            entry.spread = .{ try row.number("weapon1_spread_x", 0), try row.number("weapon1_spread_z", 0) };
            if (entry.sight_range < 0 or entry.sight_range > 65536 or entry.fov < 0 or entry.fov > 360 or entry.damage < 0 or entry.damage > 1000000 or entry.random_damage < 0 or entry.random_damage > 1000000 or entry.range < 0 or entry.range > 65536) return error.InvalidActorTuning;
            for (entry.spread) |spread| if (spread < 0 or spread > 8192) return error.InvalidActorSpread;
            if (row.field("render_scale")) |scale| {
                var axes = std.mem.tokenizeAny(u8, scale, " \t");
                for (&entry.scale) |*value| {
                    value.* = try std.fmt.parseFloat(f32, axes.next() orelse return error.InvalidActorScale);
                    if (!std.math.isFinite(value.*) or value.* <= 0 or value.* > 16) return error.InvalidActorScale;
                }
                if (axes.next() != null) return error.InvalidActorScale;
            }
            inline for (.{ "x", "y", "z" }, 0..) |axis, i| {
                entry.offset[i] = try row.number("weapon1_offset_" ++ axis, 0);
                if (@abs(entry.offset[i]) > 1024) return error.InvalidActorOffset;
                entry.mins[i] = try row.number("size_min_" ++ axis, 0);
                entry.maxs[i] = try row.number("size_max_" ++ axis, 0);
                if (entry.mins[i] >= entry.maxs[i] or @abs(entry.mins[i]) > 1024 or @abs(entry.maxs[i]) > 1024) return error.InvalidActorBounds;
            }
            if (catalog.entries[id].kind == .froginator) entry.frog = try catalog.froginator.Tuning.parse(row);
            if (catalog.entries[id].kind == .dwarf) entry.dwarf = try catalog.dwarf.Tuning.parse(row);
            if (catalog.entries[id].kind == .inmater) entry.laser = try catalog.laser.Tuning.parse(row, "weapon2_");
            if (catalog.entries[id].kind == .lasergat) entry.laser = try catalog.laser.Tuning.parse(row, "weapon1_");
            if (catalog.entries[id].kind == .cryotech) {
                entry.damage = try row.number("weapon2_base_damage", 0);
                entry.random_damage = try row.number("weapon2_random_damage", 0);
                entry.range = try row.number("weapon2_distance", 0);
                if (entry.damage < 0 or entry.random_damage < 0 or entry.range <= 0) return error.InvalidCryotechWeapon;
            }
            if (catalog.entries[id].kind == .thief) {
                entry.thief_knife = try catalog.weapon.Tuning.parse(row, "weapon2_");
                if (entry.thief_knife.speed <= 0) return error.InvalidThiefKnife;
            }
            if (catalog.entries[id].kind == .blackprisoner or catalog.entries[id].kind == .whiteprisoner) {
                entry.prisoner_rock = try catalog.weapon.Tuning.parse(row, "weapon2_");
                if (entry.prisoner_rock.speed <= 0) return error.InvalidPrisonerRock;
            }
            if (catalog.entries[id].kind == .battleboar) {
                entry.boar_weapons = .{ try catalog.weapon.Tuning.parse(row, "weapon1_"), try catalog.weapon.Tuning.parse(row, "weapon2_") };
                if (entry.boar_weapons[1].speed <= 0) return error.InvalidBoarRocket;
            }
            if (catalog.entries[id].kind == .rocketmp) {
                entry.mp_rockets = .{ try catalog.weapon.Tuning.parse(row, "weapon2_"), try catalog.weapon.Tuning.parse(row, "weapon3_") };
                for (entry.mp_rockets) |rocket| if (rocket.speed <= 0) return error.InvalidMpRocket;
            }
            if (catalog.entries[id].kind == .rocketdude) {
                entry.gang_rockets = .{ try catalog.weapon.Tuning.parse(row, "weapon1_"), try catalog.weapon.Tuning.parse(row, "weapon2_") };
                for (entry.gang_rockets) |rocket| if (rocket.speed <= 0) return error.InvalidGangRocket;
            }
            if (catalog.entries[id].kind == .centurion or catalog.entries[id].kind == .fletcher) {
                entry.archer_ranged = try catalog.weapon.Tuning.parse(row, "weapon1_");
                if (entry.archer_ranged.speed <= 0) return error.InvalidArcherProjectile;
                if (catalog.entries[id].kind == .centurion) {
                    const melee = try catalog.weapon.Tuning.parse(row, "weapon2_");
                    entry.damage = melee.damage;
                    entry.random_damage = melee.random_damage;
                    entry.range = melee.range;
                    entry.offset = melee.offset;
                    entry.spread = melee.spread;
                }
            }
            if (catalog.entries[id].kind == .rotworm) {
                entry.rotworm_spit = try catalog.weapon.Tuning.parse(row, "weapon2_");
                if (entry.rotworm_spit.speed <= 0) return error.InvalidRotwormSpit;
            }
            if (catalog.entries[id].kind == .shark and entry.walk_speed <= 0) return error.InvalidSharkSpeed;
            if (catalog.entries[id].kind == .venomvermin) {
                entry.vermin_rocket = try catalog.weapon.Tuning.parse(row, "weapon3_");
                const bite = try catalog.weapon.Tuning.parse(row, "weapon2_");
                entry.damage = bite.damage;
                entry.random_damage = bite.random_damage;
                entry.range = bite.range;
                entry.offset = bite.offset;
                entry.spread = bite.spread;
                if (entry.vermin_rocket.speed <= 0) return error.InvalidVerminRocket;
            }
            if (catalog.entries[id].kind == .plague_rat) entry.rat_poison = try catalog.weapon.Tuning.parse(row, "weapon2_");
            if (catalog.entries[id].kind == .knight1) entry.knight_ranged = try catalog.knights.Weapon.parse(row, "weapon2_");
            if (catalog.entries[id].kind == .knight2) {
                entry.knight_ranged = try catalog.knights.Weapon.parse(row, "weapon1_");
                const melee = try catalog.knights.Weapon.parse(row, "weapon2_");
                entry.damage = melee.damage;
                entry.random_damage = melee.random_damage;
                entry.range = melee.range;
                entry.offset = melee.offset;
                entry.spread = melee.spread;
            }
            entry.loaded = true;
        }
        return result;
    }
};
pub fn fleeVelocity(position: v.Vec3, threat: v.Vec3, speed: f32) v.Vec3 {
    var away = v.add(position, v.scale(threat, -1));
    away[2] = 0;
    if (v.length(away) < 0.01) away = .{ 1, 0, 0 };
    return v.scale(v.normalize(away), speed);
}
test "civilian panic has bounded duration, stable speed and no post-death transition" {
    var state: State = .{ .definition = 0 };
    state.panic(42, .{ 10, 20, 0 }, 1000);
    try std.testing.expectEqual(Mode.flee, state.mode);
    try std.testing.expect(state.panic_until > 1000);
    try std.testing.expectApproxEqAbs(@as(f32, 150), v.length(fleeVelocity(.{ 1, 2, 0 }, .{ 1, 3, 0 }, 150)), 0.001);
    state.mode = .dead;
    state.panic(43, @splat(0), 2000);
    try std.testing.expectEqual(@as(u32, 42), state.threat);
}
