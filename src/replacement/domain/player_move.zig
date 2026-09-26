// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 1999-2005 Id Software, Inc.
// Shared Zig movement adapted from bundled GPL bg_pmove.c and project dk_ladder.inc.
// See LICENSE. No private reference implementation is imported.
const std = @import("std");
const v = @import("vector.zig");
const collision = @import("collision.zig");
const slide = @import("slide.zig");
pub const Mode = enum { normal, spectator, noclip, dead, frozen };
pub const Timer = enum { none, land, knockback, water_jump };
pub const Player = struct {
    command_ms: i64 = 0,
    delta_angles: [3]i32 = @splat(0),
    mode: Mode = .normal,
    ducked: bool = false,
    jump_held: bool = false,
    respawned: bool = false,
    view_height: f32 = 22,
    ground_entity: u16 = 2047,
    water_level: u2 = 0,
    water_type: u32 = 0,
    timer: Timer = .none,
    timer_ms: u32 = 0,
};
pub const Command = struct {
    time_ms: i64,
    angles: v.Vec3,
    forward: i8 = 0,
    right: i8 = 0,
    up: i8 = 0,
    weapon: u8 = 0,
    talking: bool = false,
    attack: bool = false,
    use: bool = false,
};
pub const Parameters = struct {
    speed: f32 = 320,
    gravity: f32 = 800,
    jump_speed: f32 = 270,
    slot: u16,
    mask: u32,
    water_mask: u32,
    solid_mask: u32,
    fixed_ms: ?u8 = null,
    snap_velocity: bool = true,
};
pub const Event = union(enum) { jump, step: f32, land: f32, water_enter, water_leave, water_under, water_surface };
pub const Result = struct {
    events: [256]Event = undefined,
    event_count: usize = 0,
    touches: [32]u16 = undefined,
    touch_count: usize = 0,
    mins: v.Vec3 = .{ -15, -15, -24 },
    maxs: v.Vec3 = .{ 15, 15, 32 },
    fn event(self: *Result, value: Event) !void {
        if (self.event_count == self.events.len) return error.MovementEventCapacity;
        self.events[self.event_count] = value;
        self.event_count += 1;
    }
};
const Frame = struct {
    player: *Player,
    motion: *slide.State,
    cmd: Command,
    parameters: Parameters,
    service: collision.Collision,
    result: *Result,
    delta: f32,
    ground: ?collision.Trace = null,
    walking: bool = false,
    forward: v.Vec3,
    right: v.Vec3,
    fn trace(self: *Frame, start: v.Vec3, end: v.Vec3) !collision.Trace {
        return self.service.trace(.{ .start = start, .end = end, .mins = self.result.mins, .maxs = self.result.maxs, .slot = self.parameters.slot, .mask = self.parameters.mask });
    }
    fn water(self: *Frame) !void {
        const p = self.player;
        p.water_level = 0;
        p.water_type = 0;
        var point = self.motion.position;
        point[2] -= 23;
        const contents = try self.service.contents(point, self.parameters.slot);
        if (contents & self.parameters.water_mask == 0) return;
        p.water_type = contents;
        p.water_level = 1;
        point[2] = self.motion.position[2] - 24 + @trunc((p.view_height + 24) / 2);
        if (try self.service.contents(point, self.parameters.slot) & self.parameters.water_mask == 0) return;
        p.water_level = 2;
        point[2] = self.motion.position[2] + p.view_height;
        if (try self.service.contents(point, self.parameters.slot) & self.parameters.water_mask != 0) p.water_level = 3;
    }
    fn bounds(self: *Frame) !void {
        const p = self.player;
        if (p.mode == .dead) {
            self.result.maxs[2] = -8;
            p.view_height = -16;
            return;
        }
        if (self.cmd.up < 0) p.ducked = true else if (p.ducked) {
            self.result.maxs[2] = 32;
            if (!(try self.trace(self.motion.position, self.motion.position)).all_solid) p.ducked = false;
        }
        self.result.maxs[2] = if (p.ducked) 4 else 32;
        p.view_height = if (p.ducked) -2 else 22;
    }
    fn groundTrace(self: *Frame) !void {
        var end = self.motion.position;
        end[2] -= 0.25;
        var hit = try self.trace(self.motion.position, end);
        self.walking = false;
        self.ground = null;
        self.player.ground_entity = 2047;
        if (hit.all_solid) {
            var clear = false;
            outer: for (0..3) |x| for (0..3) |y| for (0..3) |z| {
                const point = v.add(self.motion.position, .{ @as(f32, @floatFromInt(x)) - 1, @as(f32, @floatFromInt(y)) - 1, @as(f32, @floatFromInt(z)) - 1 });
                if (!(try self.trace(point, point)).all_solid) {
                    clear = true;
                    break :outer;
                }
            };
            if (!clear) return;
            hit = try self.trace(self.motion.position, end);
        }
        if (hit.fraction == 1 or (self.motion.velocity[2] > 0 and v.dot(self.motion.velocity, hit.normal) > 10)) return;
        self.ground = hit;
        if (hit.normal[2] < 0.7) return;
        self.walking = true;
        self.player.ground_entity = hit.entity;
        if (self.player.timer == .water_jump) {
            self.player.timer = .none;
            self.player.timer_ms = 0;
        }
    }
    fn friction(self: *Frame, flying: bool) void {
        var velocity = self.motion.velocity;
        if (self.walking) velocity[2] = 0;
        const speed = v.length(velocity);
        if (speed < 1) {
            self.motion.velocity[0] = 0;
            self.motion.velocity[1] = 0;
            return;
        }
        var drop: f32 = 0;
        if (self.player.water_level <= 1 and self.walking and !self.ground.?.slick and self.player.timer != .knockback)
            drop += @max(speed, 100) * 6 * self.delta;
        drop += speed * @as(f32, @floatFromInt(self.player.water_level)) * self.delta;
        if (flying) drop += speed * 5 * self.delta;
        self.motion.velocity = v.scale(self.motion.velocity, @max(0, speed - drop) / speed);
    }
    fn commandScale(self: *Frame) f32 {
        const axes: v.Vec3 = .{ @floatFromInt(self.cmd.forward), @floatFromInt(self.cmd.right), @floatFromInt(self.cmd.up) };
        const maximum = @max(@abs(axes[0]), @abs(axes[1]), @abs(axes[2]));
        return if (maximum == 0) 0 else self.parameters.speed * maximum / (127 * v.length(axes));
    }
    fn accelerate(self: *Frame, direction: v.Vec3, speed: f32, acceleration: f32) void {
        const add = speed - v.dot(self.motion.velocity, direction);
        if (add > 0) self.motion.velocity = v.add(self.motion.velocity, v.scale(direction, @min(add, acceleration * self.delta * speed)));
    }
    fn slideMove(self: *Frame, gravity: bool, step: bool) !void {
        var context: slide.Context = .{ .service = self.service, .mins = self.result.mins, .maxs = self.result.maxs, .slot = self.parameters.slot, .mask = self.parameters.mask, .delta = self.delta, .gravity = if (gravity) self.parameters.gravity else 0, .ground = if (self.ground) |hit| hit.normal else null, .preserve_velocity = self.player.timer_ms > 0 };
        if (step) try context.step(self.motion) else _ = try context.move(self.motion);
        self.result.touch_count = context.touch_count;
        @memcpy(self.result.touches[0..context.touch_count], context.touches[0..context.touch_count]);
        if (context.step_height > 2) try self.result.event(.{ .step = context.step_height });
    }
    fn ladder(self: *Frame) !bool {
        if (self.player.mode != .normal or self.player.water_level > 1) return false;
        const horizontal = v.normalize(.{ self.forward[0], self.forward[1], 0 });
        if (v.length(horizontal) == 0) return false;
        for (0..4) |axis| {
            var direction: v.Vec3 = @splat(0);
            direction[axis / 2] = if (axis & 1 == 0) 1 else -1;
            const hit = try self.trace(self.motion.position, v.add(self.motion.position, v.scale(direction, 3)));
            if (hit.fraction == 1 or !hit.ladder or @abs(hit.normal[2]) >= 0.5) continue;
            const facing = v.dot(horizontal, hit.normal);
            if (self.cmd.forward != 0 and (if (self.cmd.forward < 0) facing < -0.1 else facing > 0.1)) return false;
            if (self.cmd.up == 0 and facing > -0.5) return false;
            const climb: f32 = if (self.cmd.up != 0) @floatFromInt(self.cmd.up) else @as(f32, @floatFromInt(self.cmd.forward)) * (if (self.forward[2] < -0.35) @as(f32, -1) else 1);
            const speed = @min(self.parameters.speed, 140);
            var wish = v.scale(self.right, @as(f32, @floatFromInt(self.cmd.right)) * speed / 127);
            wish[2] = climb * speed / 127;
            wish = v.clip(wish, hit.normal);
            self.motion.velocity = v.add(self.motion.velocity, v.scale(v.add(wish, v.scale(self.motion.velocity, -1)), @min(1, 12 * self.delta)));
            self.player.ground_entity = 2047;
            try self.slideMove(false, true);
            return true;
        }
        return false;
    }
    fn swim(self: *Frame) !void {
        if (self.player.water_level == 2 and self.player.timer_ms == 0) {
            const flat = v.normalize(.{ self.forward[0], self.forward[1], 0 });
            var spot = v.add(self.motion.position, v.scale(flat, 30));
            spot[2] += 4;
            if (try self.service.contents(spot, self.parameters.slot) & self.parameters.solid_mask != 0) {
                spot[2] += 16;
                if (try self.service.contents(spot, self.parameters.slot) == 0) {
                    self.motion.velocity = v.scale(self.forward, 200);
                    self.motion.velocity[2] = 350;
                    self.player.timer = .water_jump;
                    self.player.timer_ms = 2000;
                    try self.waterJump();
                    return;
                }
            }
        }
        self.friction(false);
        const scale = self.commandScale();
        var wish = v.add(v.scale(self.forward, scale * @as(f32, @floatFromInt(self.cmd.forward))), v.scale(self.right, scale * @as(f32, @floatFromInt(self.cmd.right))));
        wish[2] += scale * @as(f32, @floatFromInt(self.cmd.up));
        if (scale == 0) wish = .{ 0, 0, -60 };
        self.accelerate(v.normalize(wish), @min(v.length(wish), self.parameters.speed * 0.5), 4);
        if (self.ground) |hit| if (v.dot(self.motion.velocity, hit.normal) < 0) {
            self.motion.velocity = v.scale(v.normalize(v.clip(self.motion.velocity, hit.normal)), v.length(self.motion.velocity));
        };
        try self.slideMove(false, false);
    }
    fn waterJump(self: *Frame) !void {
        try self.slideMove(true, true);
        self.motion.velocity[2] -= self.parameters.gravity * self.delta;
        if (self.motion.velocity[2] < 0) {
            self.player.timer = .none;
            self.player.timer_ms = 0;
        }
    }
    fn fly(self: *Frame, noclip: bool) !void {
        if (noclip) {
            const speed = v.length(self.motion.velocity);
            self.motion.velocity = if (speed < 1) @splat(0) else v.scale(self.motion.velocity, @max(0, speed - @max(speed, 100) * 9 * self.delta) / speed);
        } else self.friction(true);
        const scale = self.commandScale();
        var wish = v.add(v.scale(self.forward, scale * @as(f32, @floatFromInt(self.cmd.forward))), v.scale(self.right, scale * @as(f32, @floatFromInt(self.cmd.right))));
        wish[2] += scale * @as(f32, @floatFromInt(self.cmd.up));
        self.accelerate(v.normalize(wish), v.length(wish), if (noclip) 10 else 8);
        if (noclip) self.motion.position = v.add(self.motion.position, v.scale(self.motion.velocity, self.delta)) else try self.slideMove(false, true);
    }
    fn walkAir(self: *Frame) !void {
        if (self.walking and self.cmd.up >= 10 and !self.player.respawned) {
            if (self.player.jump_held) self.cmd.up = 0 else {
                self.player.jump_held = true;
                self.player.ground_entity = 2047;
                self.walking = false;
                self.ground = null;
                self.motion.velocity[2] = self.parameters.jump_speed;
                try self.result.event(.jump);
            }
        }
        self.friction(false);
        var forward = v.normalize(.{ self.forward[0], self.forward[1], 0 });
        var right = v.normalize(.{ self.right[0], self.right[1], 0 });
        if (self.walking) {
            forward = v.normalize(v.clip(forward, self.ground.?.normal));
            right = v.normalize(v.clip(right, self.ground.?.normal));
        }
        const wish = v.add(v.scale(forward, @floatFromInt(self.cmd.forward)), v.scale(right, @floatFromInt(self.cmd.right)));
        var speed = v.length(wish) * self.commandScale();
        if (self.walking and self.player.ducked) speed = @min(speed, self.parameters.speed * 0.25);
        if (self.walking and self.player.water_level > 0) speed = @min(speed, self.parameters.speed * (1 - 0.5 * @as(f32, @floatFromInt(self.player.water_level)) / 3));
        const slick = self.walking and (self.ground.?.slick or self.player.timer == .knockback);
        self.accelerate(v.normalize(wish), speed, if (self.walking and !slick) 10 else 1);
        if (slick) self.motion.velocity[2] -= self.parameters.gravity * self.delta;
        if (self.ground) |hit| {
            const before = v.length(self.motion.velocity);
            self.motion.velocity = v.clip(self.motion.velocity, hit.normal);
            if (self.walking) self.motion.velocity = v.scale(v.normalize(self.motion.velocity), before);
        }
        if (self.walking and self.motion.velocity[0] == 0 and self.motion.velocity[1] == 0) return;
        try self.slideMove(!self.walking, true);
    }
};

pub const AfterStep = struct {
    context: *anyopaque,
    run_fn: *const fn (*anyopaque, *Player, *slide.State, Command, u32) anyerror!void,
};
pub fn run(player: *Player, motion: *slide.State, command: Command, parameters: Parameters, service: collision.Collision) !Result {
    return runWithHook(player, motion, command, parameters, service, null);
}
pub fn runWithHook(player: *Player, motion: *slide.State, command: Command, parameters: Parameters, service: collision.Collision, hook: ?AfterStep) !Result {
    if (parameters.fixed_ms) |ms| if (ms < 1 or ms > 200) return error.InvalidMovementStep;
    if (!std.math.isFinite(parameters.speed) or parameters.speed < 0 or !std.math.isFinite(parameters.gravity) or !std.math.isFinite(parameters.jump_speed)) return error.InvalidMovementParameters;
    for (command.angles) |angle| if (!std.math.isFinite(angle)) return error.InvalidMovementParameters;
    var result: Result = .{};
    result.maxs[2] = if (player.mode == .dead) -8 else if (player.ducked) 4 else 32;
    if (command.time_ms < player.command_ms) return result;
    const elapsed = std.math.sub(i64, command.time_ms, player.command_ms) catch return error.InvalidMovementTime;
    if (elapsed > 1000) player.command_ms = command.time_ms - 1000;
    var cmd = command;
    if (cmd.talking or player.mode == .dead) {
        cmd.forward = 0;
        cmd.right = 0;
        cmd.up = 0;
    }
    if (!cmd.attack and !cmd.use) player.respawned = false;
    const basis = v.basis(command.angles);
    while (player.command_ms < command.time_ms) {
        const milliseconds: u32 = @intCast(@min(command.time_ms - player.command_ms, parameters.fixed_ms orelse 66));
        player.command_ms += milliseconds;
        if (cmd.up < 10) player.jump_held = false;
        if (player.mode == .frozen) {
            if (hook) |after| {
                var step_command = cmd;
                step_command.time_ms = player.command_ms;
                try after.run_fn(after.context, player, motion, step_command, milliseconds);
            }
            continue;
        }
        var frame: Frame = .{ .player = player, .motion = motion, .cmd = cmd, .parameters = parameters, .service = service, .result = &result, .delta = @as(f32, @floatFromInt(milliseconds)) * 0.001, .forward = basis.forward, .right = basis.right };
        if (player.mode == .noclip or player.mode == .spectator) {
            if (player.mode == .spectator) try frame.bounds() else player.view_height = 22;
            try frame.fly(player.mode == .noclip);
            player.timer_ms -|= milliseconds;
            if (player.timer_ms == 0) player.timer = .none;
            continue;
        }
        try frame.water();
        const prior_water = player.water_level;
        try frame.bounds();
        const prior_ground = player.ground_entity;
        const prior_velocity = motion.velocity;
        try frame.groundTrace();
        if (player.mode == .dead and frame.walking) motion.velocity = v.scale(v.normalize(motion.velocity), @max(0, v.length(motion.velocity) - 20));
        player.timer_ms -|= milliseconds;
        if (player.timer_ms == 0) player.timer = .none;
        if (player.timer == .water_jump) try frame.waterJump() else if (!try frame.ladder()) {
            if (player.water_level > 1) try frame.swim() else try frame.walkAir();
        }
        try frame.groundTrace();
        try frame.water();
        if (prior_ground == 2047 and player.ground_entity != 2047) {
            try result.event(.{ .land = @max(0, -prior_velocity[2]) });
            if (prior_velocity[2] < -200) {
                player.timer = .land;
                player.timer_ms = 250;
            }
        }
        if (prior_water == 0 and player.water_level > 0) try result.event(.water_enter);
        if (prior_water > 0 and player.water_level == 0) try result.event(.water_leave);
        if (prior_water != 3 and player.water_level == 3) try result.event(.water_under);
        if (prior_water == 3 and player.water_level != 3) try result.event(.water_surface);
        if (hook) |after| {
            var step_command = cmd;
            step_command.time_ms = player.command_ms;
            try after.run_fn(after.context, player, motion, step_command, milliseconds);
        }
        if (parameters.snap_velocity) for (&motion.velocity) |*axis| {
            axis.* = v.snap(axis.*);
        };
        if (player.jump_held) cmd.up = 20;
    }
    return result;
}
