// SPDX-License-Identifier: GPL-2.0-or-later
//! Owner of asynchronous collision preparations. Deliberately reports the
//! precise completed stage, never "region ready" before the other owners exist.
const std = @import("std");
const worlds = @import("../engine/worlds.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const Entry = struct {
    name: [64]u8 = @splat(0),
    handle: worlds.Handle,
    status: worlds.Status = .reading,
};
pub const State = struct {
    entries: [127]?Entry = @splat(null),
    cursor: usize = 0,
    pub fn deinit(self: *State) void {
        for (self.entries) |maybe| if (maybe) |entry| {
            _ = worlds.release(entry.handle);
        };
        self.* = .{};
    }
    pub fn request(self: *State, name: []const u8) !void {
        if (!@import("../domain/snapshot.zig").validName(name) or name.len >= 64) return error.InvalidWorldName;
        var active: usize = 0;
        for (self.entries) |maybe| if (maybe) |entry| {
            if (std.mem.eql(u8, std.mem.sliceTo(&entry.name, 0), name)) return error.WorldAlreadyRequested;
            if (entry.status == .reading) active += 1;
        };
        if (active >= 4) return error.WorldReaderLimit;
        for (&self.entries) |*slot| if (slot.* == null) {
            var entry: Entry = .{ .handle = try worlds.request(name) };
            @memcpy(entry.name[0..name.len], name);
            slot.* = entry;
            return;
        };
        return error.ResidentWorldLimit;
    }
    pub fn step(self: *State) !void {
        // At most one completed BSP is admitted per server frame. This is a
        // measured collision preparation stage, not a frame-budget guarantee.
        for (0..self.entries.len) |_| {
            const index = self.cursor;
            self.cursor = (index + 1) % self.entries.len;
            const entry = if (self.entries[index]) |*value| value else continue;
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
        if (std.mem.eql(u8, verb, "prepare")) {
            try self.request(name);
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
