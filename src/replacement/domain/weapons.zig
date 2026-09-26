// SPDX-License-Identifier: GPL-2.0-or-later
//! ECS-owned loadout and controller state. Concrete policies are shared with legacy.
const std = @import("std");
const catalog = @import("weapon_catalog");
const rules = catalog.transitions;
const collision = @import("collision.zig");
const movement = @import("player_move.zig");
const slide = @import("slide.zig");
const v = @import("vector.zig");
pub const State = struct {
    dk3Inventory: i32 = 0,
    ammo: [32]i32 = @splat(0),
    weapon: i32 = 0,
    weaponTime: i32 = 0,
    weaponstate: i32 = 0,
    dk3Burst: i32 = 0,
    dk3Charge: i32 = 0,
    dk3NovaSpent: i32 = 0,
    dk3WeaponSequence: i32 = 0,
    dk3AttackHeld: i32 = 0,
    dk3GlockClip: i32 = 10,
    dk3SwordExperience: i32 = 0,
    gas_until_ms: i64 = 0,
    event_sequence: u32 = 0,
    pub fn acquire(self: *State, table: *const Table, id: u5, rounds: i32) bool {
        const entry = catalog.find(id) orelse return false;
        var owned: u32 = @bitCast(self.dk3Inventory);
        if (!@import("inventory_rules").acquire(&owned, &self.ammo, &self.weapon, id, rounds, .{ .maximum = table.entries[id].ammoMax, .auto_select = entry.spec.auto_select })) return false;
        if (id == 23) @import("inventory_rules").grantPair(&owned, &self.ammo, 27, table.entries[27].ammoMax, table.entries[27].initialAmmo);
        self.dk3Inventory = @bitCast(owned);
        return true;
    }
};
pub const Table = struct {
    entries: [29]catalog.values.Values = @splat(.{}),
    pub fn parse(bytes: []const u8) !Table {
        var table: Table = .{};
        var loaded: [29]bool = @splat(false);
        var reader = try @import("tables.zig").Reader.init(bytes);
        while (try reader.next()) |row| {
            const classname = row.field("classname") orelse return error.MissingWeaponClass;
            const id: u5 = blk: {
                for (catalog.entries) |entry| if (std.mem.eql(u8, entry.classname, classname)) break :blk entry.id;
                return error.UnknownWeaponClass;
            };
            if (loaded[id]) return error.DuplicateWeaponClass;
            table.entries[id] = try catalog.values.parse(id, &row);
            loaded[id] = true;
        }
        for (loaded[1..28]) |present| if (!present) return error.MissingWeaponClass;
        return table;
    }
};
pub const Fired = struct { weapon: u5, sequence: i32, command_ms: i64, position: v.Vec3, angles: v.Vec3, charge: i32 };
pub const Event = union(enum) { fired: Fired, no_ammo };
pub const Events = struct {
    values: [128]Event = undefined,
    count: usize = 0,
    pub fn append(self: *Events, event: Event) !void {
        if (self.count == self.values.len) return error.WeaponEventCapacity;
        self.values[self.count] = event;
        self.count += 1;
    }
};
pub const Context = struct {
    ps: *State,
    table: *const Table,
    events: *Events,
    service: collision.Collision,
    slot: u16,
    shot_mask: u32,
    healthy: bool = true,
    single_player: bool = true,
    attack_boost: i32 = 0,
    camera_active: bool = false,
    msec: i32 = 0,
    command: movement.Command = undefined,
    player: *movement.Player = undefined,
    motion: *slide.State = undefined,
    failure: ?anyerror = null,
    pub fn hook(self: *Context) movement.AfterStep {
        return .{ .context = self, .run_fn = step };
    }
    fn step(raw: *anyopaque, player: *movement.Player, motion: *slide.State, command: movement.Command, milliseconds: u32) !void {
        const self: *Context = @ptrCast(@alignCast(raw));
        self.player = player;
        self.motion = motion;
        self.command = command;
        self.msec = @intCast(milliseconds);
        if (!self.canFire()) self.inventoryTick();
        rules.tick(self);
        if (self.failure) |err| return err;
    }
    pub fn canFire(self: *const Context) bool {
        return self.healthy and self.player.mode == .normal and !self.player.respawned;
    }
    pub fn selection(self: *const Context) i32 {
        return self.command.weapon;
    }
    pub fn now(self: *const Context) i32 {
        return @intCast(self.command.time_ms);
    }
    pub fn ammoCost(self: *const Context, id: i32) i32 {
        return self.table.entries[@intCast(id)].ammoCost;
    }
    pub fn lifetime(self: *const Context, id: i32) f32 {
        return self.table.entries[@intCast(id)].lifetime;
    }
    pub fn interval(_: *const Context, id: i32) i32 {
        return (catalog.find(@intCast(id)) orelse unreachable).interval;
    }
    pub fn boost(self: *const Context) i32 {
        return self.attack_boost;
    }
    pub fn scaled(self: *const Context, duration: i32) i32 {
        return @intFromFloat(@as(f32, @floatFromInt(duration)) / rules.attackFactor(self.boost()));
    }
    pub fn pressed(self: *const Context) bool {
        return self.command.attack and !self.command.talking;
    }
    pub fn release(self: *Context) void {
        rules.release(self);
    }
    pub fn fire(self: *Context, comptime W: type, shot: catalog.Shot) void {
        rules.fire(self, W, shot);
    }
    pub fn automatic(self: *Context, comptime W: type) void {
        rules.automatic(self, W);
    }
    pub fn noAmmo(self: *Context) void {
        self.ps.event_sequence +%= 1;
        self.events.append(.no_ammo) catch |err| {
            self.failure = err;
        };
    }
    pub fn fireEvent(self: *Context) void {
        self.ps.event_sequence +%= 1;
        self.events.append(.{ .fired = .{ .weapon = @intCast(self.ps.weapon), .sequence = self.ps.dk3WeaponSequence, .command_ms = self.command.time_ms, .position = self.motion.position, .angles = self.command.angles, .charge = self.ps.dk3Charge } }) catch |err| {
            self.failure = err;
        };
    }
    pub fn inventoryTick(self: *Context) void {
        if (!self.single_player or self.ps.dk3Inventory & (@as(i32, 1) << 7) == 0) return;
        if (catalog.gas.advance(self.ps.gas_until_ms, self.command.time_ms, self.msec, self.healthy, self.ps.weapon != 7 or self.camera_active or self.player.mode == .frozen)) |deadline| {
            self.ps.gas_until_ms = deadline;
        } else {
            self.ps.gas_until_ms = 0;
            rules.expireGas(self.ps);
        }
    }
    fn contact(self: *Context, range: f32, eye_offset: f32, body: bool) ?collision.Trace {
        var eye = self.motion.position;
        eye[2] += eye_offset;
        return self.service.trace(.{ .start = eye, .end = v.add(eye, v.scale(v.basis(self.command.angles).forward, range)), .mins = if (body) .{ -15, -15, -24 } else @splat(0), .maxs = if (body) .{ 15, 15, if (self.player.ducked) @as(f32, 4) else 32 } else @splat(0), .slot = self.slot, .mask = self.shot_mask }) catch |err| {
            self.failure = err;
            return null;
        };
    }
    pub fn discusMelee(self: *Context) bool {
        const hit = self.contact(100, self.player.view_height, false) orelse return false;
        return hit.fraction < 1;
    }
    pub fn venomBite(self: *Context) bool {
        if (self.player.water_level > 1 or self.ps.ammo[11] < self.ammoCost(11)) return true;
        const hit = self.contact(150, 4, true) orelse return false;
        return hit.fraction < 1 and hit.entity < 2046;
    }
};
