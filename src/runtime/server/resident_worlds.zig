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
    publication: ?@import("world_publication.zig").State = null,
    client_failed: bool = false,
    namespace: u7 = 1,
    saved: ?*@import("../domain/snapshot.zig").Loaded = null,
};
pub const State = struct {
    entries: [127]?Entry = @splat(null),
    cursor: usize = 0,
    initial_namespace: u7 = 0,
    pub fn ensure(self: *State, name: []const u8) !bool {
        for (self.entries) |maybe| if (maybe) |entry| {
            if (!std.mem.eql(u8, name, std.mem.sliceTo(&entry.name, 0))) continue;
            if (entry.status == .failed or entry.client_failed) return error.RegionPreparationFailed;
            return entry.ready and entry.publication != null and entry.publication.?.ready;
        };
        self.request(name, true) catch |err| switch (err) {
            error.WorldReaderLimit => return false,
            else => return err,
        };
        return false;
    }
    pub fn hasGameplay(self: *const State) bool {
        for (self.entries) |maybe| if (maybe) |entry| if (entry.gameplay) return true;
        return false;
    }
    pub fn captureOthers(self: *State, allocator: std.mem.Allocator, initial: *Context, active: *Context) ![]const @import("../domain/snapshot.zig").Archive {
        var result: std.ArrayList(@import("../domain/snapshot.zig").Archive) = .empty;
        if (initial != active) try result.append(allocator, try initial.capture(allocator));
        for (self.entries) |maybe| if (maybe) |entry| if (entry.ready) if (entry.context) |context| {
            if (context != active) try result.append(allocator, try context.capture(allocator));
        };
        return result.items;
    }
    pub fn restorationReady(self: *State, saved: *@import("../domain/snapshot.zig").Loaded) !bool {
        self.initial_namespace = saved.header.namespace orelse 0;
        var ready = true;
        for (saved.residents) |*member| {
            var found = false;
            for (self.entries) |maybe| if (maybe) |entry| {
                if (!std.mem.eql(u8, member.map, std.mem.sliceTo(&entry.name, 0))) continue;
                found = true;
                if (entry.status == .failed or entry.client_failed) return error.RegionRestorePreparationFailed;
                if (!entry.ready or entry.publication == null or !entry.publication.?.ready) ready = false;
                break;
            };
            if (!found) {
                self.requestSaved(member.map, true, member) catch |err| switch (err) {
                    error.WorldReaderLimit => return false,
                    else => return err,
                };
                ready = false;
            }
        }
        return ready;
    }
    pub fn restoreMembers(self: *State, saved: *@import("../domain/snapshot.zig").Loaded, now: i64) !void {
        // Each hidden context already owns its admitted saved state. Retain the
        // saved activation state while rebasing the time spent preparing media.
        for (saved.residents) |*member| {
            const context = try self.destination(member.map);
            if (!member.ownership_transferred) return error.ResidentRestoreNotStaged;
            const exposed = context.activated;
            try context.awaken(now);
            context.activated = exposed;
        }
        for (saved.residents) |*member| {
            const context = try self.destination(member.map);
            for (&self.entries) |*maybe| if (maybe.*) |*entry| if (entry.context == context) {
                entry.saved = null;
            };
        }
    }
    pub fn destination(self: *State, name: []const u8) !*Context {
        for (&self.entries) |*maybe| if (maybe.*) |*entry| {
            if (!std.mem.eql(u8, name, std.mem.sliceTo(&entry.name, 0))) continue;
            if (!entry.ready or entry.client_failed or entry.publication == null or !entry.publication.?.ready) return error.WorldNotAdmitted;
            return entry.context orelse error.WorldNotPrepared;
        };
        return error.WorldNotRequested;
    }
    pub fn deinit(self: *State) void {
        for (&self.entries) |*maybe| if (maybe.*) |*entry| {
            if (entry.publication) |*publication| publication.deinit(entry.handle);
            if (entry.context) |context| context.destroy();
            _ = worlds.release(entry.handle);
        };
        self.* = .{};
    }
    pub fn request(self: *State, name: []const u8, gameplay: bool) !void {
        try self.requestSaved(name, gameplay, null);
    }
    fn requestSaved(self: *State, name: []const u8, gameplay: bool, saved: ?*@import("../domain/snapshot.zig").Loaded) !void {
        if (gameplay and engine.integer("g_gametype") != c.GT_SINGLE_PLAYER) return error.CampaignPreparationRequiresSinglePlayer;
        if (!@import("../domain/snapshot.zig").validName(name) or name.len >= 64) return error.InvalidWorldName;
        var active: usize = 0;
        for (self.entries) |maybe| if (maybe) |entry| {
            if (std.mem.eql(u8, std.mem.sliceTo(&entry.name, 0), name)) return error.WorldAlreadyRequested;
            if (entry.status == .reading) active += 1;
        };
        if (active >= 4) return error.WorldReaderLimit;
        for (&self.entries) |*slot| if (slot.* == null) {
            var occupied: [128]bool = @splat(false);
            occupied[self.initial_namespace] = true;
            for (self.entries) |maybe| if (maybe) |entry| {
                occupied[entry.namespace] = true;
            };
            const namespace = if (saved) |value| value.header.namespace orelse return error.MissingWorldNamespace else blk: {
                for (occupied, 0..) |used, i| if (!used) break :blk @as(u7, @intCast(i));
                return error.WorldNamespaceCapacity;
            };
            if (occupied[namespace]) return error.DuplicateWorldNamespace;
            var entry: Entry = .{ .handle = try worlds.request(name), .gameplay = gameplay, .namespace = namespace, .saved = saved };
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
            if (entry.ready and !entry.client_failed) {
                if (entry.publication == null) {
                    // Renderer admission retains its reader through decoding.
                    // A fifth simultaneous publication must wait for readiness,
                    // not mistake that bounded capacity for a corrupt map.
                    var admitting: usize = 0;
                    for (self.entries) |maybe| if (maybe) |other| if (other.publication) |publication| {
                        if (!publication.ready and !other.client_failed) admitting += 1;
                    };
                    if (admitting >= 4) continue;
                    entry.publication = try @import("world_publication.zig").State.capture(entry.handle);
                }
                try entry.publication.?.step(entry.handle, std.mem.sliceTo(&entry.name, 0));
                continue;
            }
            if (entry.status == .collision_ready and entry.gameplay and !entry.ready) {
                const before = engine.gateway.call(c.G_MILLISECONDS, .{});
                if (entry.context == null) {
                    try worlds.attach(entry.handle);
                    entry.context = Context.prepare(entry.handle, entry.namespace, now, table, entry.saved) catch |err| {
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
    pub fn clientCommand(self: *State, client: usize, command_name: []const u8) !bool {
        const failed = std.mem.eql(u8, command_name, "dk3_world_failed");
        if (!failed and !std.mem.eql(u8, command_name, "dk3_world_ack")) return false;
        if (client != 0 or engine.integer("g_gametype") != c.GT_SINGLE_PLAYER) return true;
        var argument: [96]u8 = undefined;
        const handle = std.fmt.parseInt(u32, engine.argv(1, &argument), 10) catch return true;
        for (&self.entries) |*maybe| if (maybe.*) |*entry| {
            if (@intFromEnum(entry.handle) != handle or entry.publication == null) continue;
            if (failed) {
                entry.client_failed = true;
                var message: [192]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&message, "dk3 resident: map={s} client_failed={s}\n", .{ std.mem.sliceTo(&entry.name, 0), engine.argv(2, &argument) }));
                return true;
            }
            const offset = std.fmt.parseInt(usize, engine.argv(2, &argument), 10) catch return true;
            const ready = std.mem.eql(u8, engine.argv(3, &argument), "ready");
            const was_ready = entry.publication.?.ready;
            entry.publication.?.acknowledge(offset, ready) catch return true;
            if (ready and !was_ready) {
                var message: [192]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&message, "dk3 resident: map={s} stage=client_ready handle={d} definitions={d}\n", .{ std.mem.sliceTo(&entry.name, 0), handle, offset }));
            }
            return true;
        };
        return true; // A cancelled generation may still have reliable replies in flight.
    }
    pub fn command(self: *State) !void {
        var verb_buffer: [32]u8 = undefined;
        const verb = engine.argv(1, &verb_buffer);
        if (std.mem.eql(u8, verb, "clear")) {
            for (self.entries) |maybe| if (maybe) |entry| if (entry.handle == worlds.current()) return error.CannotReleaseActiveWorld;
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
