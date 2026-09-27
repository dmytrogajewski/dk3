// SPDX-License-Identifier: GPL-2.0-or-later
//! Owner of asynchronous collision preparations. Deliberately reports the
//! precise completed stage, never "region ready" before the other owners exist.
const std = @import("std");
const worlds = @import("../engine/worlds.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const Context = @import("world_context.zig").Context;
const Entry = struct {
    name: [64]u8 = @splat(0),
    handle: worlds.Handle,
    status: worlds.Status = .reading,
    gameplay: bool = false,
    context: ?*Context = null,
    ready: bool = false,
};
pub const State = struct {
    entries: [127]?Entry = @splat(null),
    cursor: usize = 0,
    pub fn deinit(self: *State) void {
        for (self.entries) |maybe| if (maybe) |entry| {
            if (entry.context) |context| context.destroy();
            _ = worlds.release(entry.handle);
        };
        self.* = .{};
    }
    pub fn request(self: *State, name: []const u8, gameplay: bool) !void {
        if (!@import("../domain/snapshot.zig").validName(name) or name.len >= 64) return error.InvalidWorldName;
        var active: usize = 0;
        for (self.entries) |maybe| if (maybe) |entry| {
            if (std.mem.eql(u8, std.mem.sliceTo(&entry.name, 0), name)) return error.WorldAlreadyRequested;
            if (entry.status == .reading) active += 1;
        };
        if (active >= 4) return error.WorldReaderLimit;
        for (&self.entries) |*slot| if (slot.* == null) {
            var entry: Entry = .{ .handle = try worlds.request(name), .gameplay = gameplay };
            @memcpy(entry.name[0..name.len], name);
            slot.* = entry;
            return;
        };
        return error.ResidentWorldLimit;
    }
    pub fn step(self: *State, now: i64, table: *const @import("../domain/weapons.zig").Table) !void {
        // At most one completed BSP is admitted per server frame. This is a
        // measured collision preparation stage, not a frame-budget guarantee.
        for (0..self.entries.len) |_| {
            const index = self.cursor;
            self.cursor = (index + 1) % self.entries.len;
            const entry = if (self.entries[index]) |*value| value else continue;
            if (entry.status == .collision_ready and entry.gameplay and !entry.ready) {
                const before = engine.gateway.call(c.G_MILLISECONDS, .{});
                if (entry.context == null) {
                    try worlds.attach(entry.handle);
                    entry.context = Context.prepare(entry.handle, now, table) catch |err| {
                        entry.status = .failed;
                        _ = worlds.release(entry.handle);
                        var failure: [192]u8 = undefined;
                        engine.print(try std.fmt.bufPrintZ(&failure, "dk3 resident: map={s} gameplay_failed={s}\n", .{ std.mem.sliceTo(&entry.name, 0), @errorName(err) }));
                        return;
                    };
                }
                const previous = worlds.current();
                try worlds.select(entry.handle);
                defer worlds.select(previous) catch @panic("lost active server world");
                try entry.context.?.systems.navigation.frame(now);
                if (engine.gateway.call(c.BOTLIB_AAS_INITIALIZED, .{}) == 0) return;
                entry.ready = true;
                const elapsed = engine.gateway.call(c.G_MILLISECONDS, .{}) - before;
                var message: [256]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&message, "dk3 resident: map={s} stage=gameplay_prepared entities={d} navigation=1 admission_ms={d}\n", .{ std.mem.sliceTo(&entry.name, 0), entry.context.?.world.?.count(), elapsed }));
                return;
            }
            if (entry.status != .reading) continue;
            const before = engine.gateway.call(c.G_MILLISECONDS, .{});
            entry.status = worlds.poll(entry.handle);
            if (entry.status == .reading) continue;
            const elapsed = engine.gateway.call(c.G_MILLISECONDS, .{}) - before;
            var buffer: [256]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 resident: map={s} handle={d} stage={s} bytes={d} admission_ms={d}\n", .{ std.mem.sliceTo(&entry.name, 0), @intFromEnum(entry.handle), @tagName(entry.status), worlds.bytes(entry.handle), elapsed }));
            return;
        }
    }
    pub fn command(self: *State) !void {
        var verb_buffer: [32]u8 = undefined;
        const verb = engine.argv(1, &verb_buffer);
        if (std.mem.eql(u8, verb, "clear")) {
            self.deinit();
            engine.print("dk3 resident: cleared\n");
            return;
        }
        var name_buffer: [64]u8 = undefined;
        const name = engine.argv(2, &name_buffer);
        if (std.mem.eql(u8, verb, "inspect")) {
            var point_buffer: [128]u8 = undefined;
            const point = try @import("map.zig").vector(engine.argv(3, &point_buffer));
            for (self.entries) |maybe| if (maybe) |entry| {
                if (!std.mem.eql(u8, std.mem.sliceTo(&entry.name, 0), name)) continue;
                if (!entry.ready) return error.GameplayNotPrepared;
                const context = entry.context.?;
                const previous = worlds.current();
                try worlds.select(entry.handle);
                defer worlds.select(previous) catch @panic("lost active server world");
                var actual_name: [64]u8 = undefined;
                if (!std.mem.eql(u8, engine.mapName(&actual_name), name)) return error.WorldSelectionMismatch;
                const area = engine.gateway.call(c.BOTLIB_AAS_POINT_AREA_NUM, .{&point});
                var linked: usize = 0;
                for (context.projection) |entity| if (entity.shared.linked != 0) {
                    linked += 1;
                };
                const data = @import("../domain/components.zig");
                var hash = std.hash.Wyhash.init(0);
                var actors: usize = 0;
                var contacts: usize = 0;
                var query = context.world.?.queryAccess(data.World.mask(.{ data.Actor, data.Transform, data.Health, data.Binding }), 0, 0);
                defer query.deinit();
                while (query.next()) |view| for (view.read(data.Transform), view.read(data.Health), view.read(data.Binding)) |pose, health, binding| {
                    actors += 1;
                    hash.update(std.mem.asBytes(&pose.position));
                    hash.update(std.mem.asBytes(&health.current));
                    const entity = context.projection[binding.slot];
                    const v = @import("../domain/vector.zig");
                    const center = v.add(entity.shared.currentOrigin, v.scale(v.add(entity.shared.mins, entity.shared.maxs), 0.5));
                    const contact = try engine.collisionService().trace(.{ .start = center, .end = center, .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = c.CONTENTS_BODY });
                    if (contact.entity == binding.slot and contact.start_solid) contacts += 1;
                };
                var message: [256]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&message, "dk3 resident inspect: map={s} entities={d} actors={d} linked={d} area={d} state={x} contacts={d}\n", .{ name, context.world.?.count(), actors, linked, area, hash.final(), contacts }));
                return;
            };
            return error.WorldNotRequested;
        }
        if (std.mem.eql(u8, verb, "prepare") or std.mem.eql(u8, verb, "prepare-game")) {
            try self.request(name, std.mem.eql(u8, verb, "prepare-game"));
            engine.print("dk3 resident: requested\n");
            return;
        }
        if (std.mem.eql(u8, verb, "trace")) {
            var from_buffer: [128]u8 = undefined;
            var to_buffer: [128]u8 = undefined;
            const from = try @import("map.zig").vector(engine.argv(3, &from_buffer));
            const to = try @import("map.zig").vector(engine.argv(4, &to_buffer));
            for (self.entries) |maybe| if (maybe) |entry| {
                if (!std.mem.eql(u8, std.mem.sliceTo(&entry.name, 0), name)) continue;
                const result = try worlds.trace(entry.handle, from, to, @splat(0), @splat(0), 0, c.MASK_SOLID);
                var buffer: [256]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 resident trace: map={s} fraction={d:.5} startsolid={d} end={d:.2},{d:.2},{d:.2}\n", .{ name, result.fraction, result.startsolid, result.endpos[0], result.endpos[1], result.endpos[2] }));
                return;
            };
            return error.WorldNotRequested;
        }
        return error.InvalidResidentCommand;
    }
};
