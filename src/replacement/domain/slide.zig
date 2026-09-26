// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 1999-2005 Id Software, Inc.
// Zig adaptation of the GPL-2.0-or-later movement algorithm in
// engine/ioquake3/code/game/bg_slidemove.c. See LICENSE for the GPL terms.
const v = @import("vector.zig");
const collision = @import("collision.zig");
pub const State = struct { position: v.Vec3, velocity: v.Vec3 };
pub const Context = struct {
    service: collision.Collision,
    mins: v.Vec3,
    maxs: v.Vec3,
    slot: u16,
    mask: u32,
    delta: f32,
    gravity: f32 = 0,
    ground: ?v.Vec3 = null,
    preserve_velocity: bool = false,
    touches: [32]u16 = undefined,
    touch_count: usize = 0,
    impact_speed: f32 = 0,
    step_height: f32 = 0,
    pub fn trace(self: *const Context, from: v.Vec3, to: v.Vec3) !collision.Trace {
        return self.service.trace(.{ .start = from, .end = to, .mins = self.mins, .maxs = self.maxs, .slot = self.slot, .mask = self.mask });
    }
    fn touch(self: *Context, entity: u16) void {
        if (entity >= 2046) return;
        for (self.touches[0..self.touch_count]) |prior| if (prior == entity) return;
        if (self.touch_count < self.touches.len) {
            self.touches[self.touch_count] = entity;
            self.touch_count += 1;
        }
    }
    pub fn move(self: *Context, state: *State) !bool {
        var original = state.velocity;
        var end_velocity = state.velocity;
        if (self.gravity != 0) {
            end_velocity[2] -= self.gravity * self.delta;
            state.velocity[2] = (state.velocity[2] + end_velocity[2]) * 0.5;
            original[2] = end_velocity[2];
            if (self.ground) |normal| state.velocity = v.clip(state.velocity, normal);
        }
        var planes: [5]v.Vec3 = undefined;
        var plane_count: usize = 0;
        if (self.ground) |normal| {
            planes[0] = normal;
            plane_count = 1;
        }
        planes[plane_count] = v.normalize(state.velocity);
        plane_count += 1;
        var time_left = self.delta;
        var bumped = false;
        for (0..4) |_| {
            const hit = try self.trace(state.position, v.add(state.position, v.scale(state.velocity, time_left)));
            if (hit.all_solid) {
                state.velocity[2] = 0;
                return true;
            }
            if (hit.fraction > 0) state.position = hit.end;
            if (hit.fraction == 1) break;
            bumped = true;
            self.touch(hit.entity);
            time_left -= time_left * hit.fraction;
            if (plane_count == planes.len) {
                state.velocity = @splat(0);
                return true;
            }
            var duplicate = false;
            for (planes[0..plane_count]) |normal| {
                if (v.dot(hit.normal, normal) > 0.99) {
                    state.velocity = v.add(state.velocity, hit.normal);
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) continue;
            planes[plane_count] = hit.normal;
            plane_count += 1;
            for (planes[0..plane_count], 0..) |normal, i| {
                const into = v.dot(state.velocity, normal);
                if (into >= 0.1) continue;
                self.impact_speed = @max(self.impact_speed, -into);
                var clipped = v.clip(state.velocity, normal);
                var clipped_end = v.clip(end_velocity, normal);
                for (planes[0..plane_count], 0..) |second, j| {
                    if (i == j or v.dot(clipped, second) >= 0.1) continue;
                    clipped = v.clip(clipped, second);
                    clipped_end = v.clip(clipped_end, second);
                    if (v.dot(clipped, normal) >= 0) continue;
                    const crease = v.normalize(v.cross(normal, second));
                    clipped = v.scale(crease, v.dot(crease, state.velocity));
                    clipped_end = v.scale(crease, v.dot(crease, end_velocity));
                    for (planes[0..plane_count], 0..) |third, k| {
                        if (k == i or k == j or v.dot(clipped, third) >= 0.1) continue;
                        state.velocity = @splat(0);
                        return true;
                    }
                }
                state.velocity = clipped;
                end_velocity = clipped_end;
                break;
            }
        }
        if (self.gravity != 0) state.velocity = end_velocity;
        if (self.preserve_velocity) state.velocity = original;
        return bumped;
    }
    pub fn step(self: *Context, state: *State) !void {
        const start = state.*;
        if (!try self.move(state)) return;
        var down = start.position;
        down[2] -= 18;
        var hit = try self.trace(start.position, down);
        if (state.velocity[2] > 0 and (hit.fraction == 1 or hit.normal[2] < 0.7)) return;
        var up = start.position;
        up[2] += 18;
        hit = try self.trace(start.position, up);
        if (hit.all_solid) return;
        const height = hit.end[2] - start.position[2];
        state.position = hit.end;
        state.velocity = start.velocity;
        _ = try self.move(state);
        down = state.position;
        down[2] -= height;
        hit = try self.trace(state.position, down);
        if (!hit.all_solid) state.position = hit.end;
        if (hit.fraction < 1) state.velocity = v.clip(state.velocity, hit.normal);
        self.step_height = @max(0, state.position[2] - start.position[2]);
    }
};
