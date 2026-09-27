// SPDX-License-Identifier: GPL-2.0-or-later
//! Single-player map admission; the active connection's configstrings stay intact.
const std = @import("std");
const engine = @import("../engine/server.zig");
const worlds = @import("../engine/worlds.zig");
const c = @import("../engine/abi.zig").c;
const wire = @import("../domain/world_admission.zig");
pub const State = struct {
    payload: []u8,
    digest: u64,
    checksum: u32,
    begun: bool = false,
    acknowledged_begin: bool = false,
    sent: usize = 0,
    acknowledged: usize = 0,
    ready: bool = false,
    pub fn capture(handle: worlds.Handle) !State {
        const previous = worlds.current();
        try worlds.select(handle);
        defer worlds.select(previous) catch @panic("lost active server world");
        var bytes: std.ArrayList(u8) = .empty;
        errdefer bytes.deinit(std.heap.c_allocator);
        var buffer: [c.MAX_GAMESTATE_CHARS]u8 = undefined;
        for (0..c.MAX_CONFIGSTRINGS) |index| {
            _ = engine.gateway.call(c.G_GET_CONFIGSTRING, .{ @as(isize, @intCast(index)), &buffer, @as(isize, buffer.len) });
            const value = std.mem.sliceTo(&buffer, 0);
            if (value.len > 0) try wire.append(std.heap.c_allocator, &bytes, @intCast(index), value);
        }
        var reader: wire.Reader = .{ .bytes = bytes.items };
        while (try reader.next()) |_| {}
        const checksum: u32 = @truncate(@as(usize, @bitCast(engine.gateway.call(c.G_DK3_WORLD_CHECKSUM_V1, .{}))));
        const payload = try bytes.toOwnedSlice(std.heap.c_allocator);
        return .{ .payload = payload, .digest = std.hash.Wyhash.hash(0, payload), .checksum = checksum };
    }
    pub fn deinit(self: *State, handle: worlds.Handle) void {
        if (self.begun) {
            var text: [80]u8 = undefined;
            engine.send(0, std.fmt.bufPrintZ(&text, "dk3_world_cancel {d}", .{@intFromEnum(handle)}) catch unreachable);
        }
        std.heap.c_allocator.free(self.payload);
    }
    pub fn step(self: *State, handle: worlds.Handle, name: []const u8) !void {
        var command: [c.MAX_STRING_CHARS]u8 = undefined;
        if (!self.begun) {
            engine.send(0, try std.fmt.bufPrintZ(&command, "dk3_world_begin {d} {d} {s} {d} {d} {d}", .{ wire.version, @intFromEnum(handle), name, self.checksum, self.payload.len, self.digest }));
            self.begun = true;
            return;
        }
        if (!self.acknowledged_begin or self.ready) return;
        while (self.sent < self.payload.len and self.sent - self.acknowledged < wire.window) {
            const end = @min(self.payload.len, self.sent + wire.chunk_size);
            var encoded: [wire.chunk_size * 2]u8 = undefined;
            engine.send(0, try std.fmt.bufPrintZ(&command, "dk3_world_data {d} {d} {s}", .{ @intFromEnum(handle), self.sent, try wire.hex(&encoded, self.payload[self.sent..end]) }));
            self.sent = end;
        }
    }
    pub fn acknowledge(self: *State, offset: usize, ready: bool) !void {
        if (!self.begun or offset > self.sent or offset < self.acknowledged or (ready and offset != self.payload.len)) return error.InvalidWorldAcknowledgement;
        self.acknowledged_begin = true;
        self.acknowledged = offset;
        self.ready = ready;
    }
};
