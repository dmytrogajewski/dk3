// SPDX-License-Identifier: GPL-2.0-or-later
//! The co-op bot's network-client duties. Reliable server commands are drained
//! every frame, and regional world publication is acknowledged with the same
//! commands the client module sends after validating each payload digest and the
//! runtime identity. Rendering, sound and prediction are not emulated.
const std = @import("std");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const wire = @import("../domain/world_admission.zig");
const version = @import("../engine/player_state.zig").version;
const Admission = struct { handle: u32, receiver: wire.Receiver, ready: bool = false };
const Patch = struct { owner: u32, receiver: wire.Receiver };
pub const Link = struct {
    admissions: [16]?Admission = @splat(null),
    patches: [16]?Patch = @splat(null),
    /// First publication defect, reported once as the run's failure.
    failure: ?anyerror = null,
    worlds_ready: u32 = 0,
    patches_applied: u32 = 0,

    pub fn deinit(self: *Link) void {
        for (&self.admissions) |*maybe| if (maybe.*) |*entry| entry.receiver.deinit(std.heap.c_allocator);
        for (&self.patches) |*maybe| if (maybe.*) |*entry| entry.receiver.deinit(std.heap.c_allocator);
        self.* = .{};
    }
    /// Drain every queued reliable command for `index`, answering publication.
    pub fn pump(self: *Link, index: u16) void {
        var message: [c.MAX_STRING_CHARS * 2]u8 = undefined;
        while (engine.gateway.call(c.BOTLIB_GET_CONSOLE_MESSAGE, .{ @as(isize, index), &message, @as(isize, message.len) }) != 0) {
            const text = std.mem.sliceTo(&message, 0);
            self.handle(index, text) catch |err| {
                if (self.failure == null) {
                    self.failure = err;
                    var line: [320]u8 = undefined;
                    engine.print(std.fmt.bufPrintZ(&line, "dk3 coop link: rejected {s}: {s}\n", .{ @errorName(err), text[0..@min(text.len, 240)] }) catch "dk3 coop link: rejected\n");
                }
            };
        }
    }
    fn handle(self: *Link, index: u16, text: []const u8) !void {
        var words = std.mem.tokenizeScalar(u8, text, ' ');
        const name = words.next() orelse return;
        if (std.mem.eql(u8, name, "dk3_world_begin")) {
            if (try number(u32, &words) != wire.version) return error.WorldAdmissionVersion;
            const handle_id = try number(u32, &words);
            _ = words.next() orelse return error.InvalidWorldName;
            _ = try number(u32, &words);
            const length = try number(usize, &words);
            const digest = try number(u64, &words);
            for (&self.admissions) |*maybe| if (maybe.*) |*entry| if (entry.handle == handle_id) {
                return acknowledge(index, entry.*);
            };
            for (&self.admissions) |*maybe| if (maybe.* == null) {
                maybe.* = .{ .handle = handle_id, .receiver = try wire.Receiver.init(std.heap.c_allocator, length, digest) };
                return acknowledge(index, maybe.*.?);
            };
            return error.WorldAdmissionCapacity;
        }
        if (std.mem.eql(u8, name, "dk3_world_cancel") or std.mem.eql(u8, name, "dk3_world_data")) {
            const handle_id = try number(u32, &words);
            for (&self.admissions) |*maybe| if (maybe.*) |*entry| if (entry.handle == handle_id) {
                if (std.mem.eql(u8, name, "dk3_world_cancel")) {
                    entry.receiver.deinit(std.heap.c_allocator);
                    maybe.* = null;
                    return;
                }
                const offset = try number(usize, &words);
                var decoded: [wire.chunk_size]u8 = undefined;
                const encoded = words.next() orelse return error.InvalidWorldChunk;
                if (encoded.len % 2 != 0 or encoded.len > decoded.len * 2) return error.InvalidWorldChunk;
                try entry.receiver.accept(offset, try std.fmt.hexToBytes(&decoded, encoded));
                if (entry.receiver.received == entry.receiver.bytes.len) {
                    var reader = try entry.receiver.finish();
                    var identified = false;
                    while (try reader.next()) |row| if (row.index == c.CS_GAME_VERSION) {
                        if (!std.mem.eql(u8, row.value, version)) return error.RuntimeMismatch;
                        identified = true;
                    };
                    if (!identified) return error.RuntimeMismatch;
                    entry.ready = true;
                    self.worlds_ready += 1;
                }
                return acknowledge(index, entry.*);
            };
            return;
        }
        if (std.mem.eql(u8, name, "dk3_world_patch")) {
            const owner = try number(u32, &words);
            const serial = try number(u64, &words);
            const length = try number(usize, &words);
            const digest = try number(u64, &words);
            const offset = try number(usize, &words);
            var selected: ?*Patch = null;
            for (&self.patches) |*maybe| if (maybe.*) |*entry| if (entry.owner == owner) {
                selected = entry;
            };
            if (selected == null) {
                if (offset != 0) return error.InvalidWorldChunk;
                for (&self.patches) |*maybe| if (maybe.* == null) {
                    maybe.* = .{ .owner = owner, .receiver = try wire.Receiver.init(std.heap.c_allocator, length, digest) };
                    selected = &maybe.*.?;
                    break;
                };
            }
            const patch = selected orelse return error.WorldPatchCapacity;
            if (patch.receiver.digest != digest or patch.receiver.bytes.len != length) return error.WorldConfigDigest;
            var decoded: [wire.chunk_size]u8 = undefined;
            const encoded = words.next() orelse return error.InvalidWorldChunk;
            if (encoded.len % 2 != 0 or encoded.len > decoded.len * 2) return error.InvalidWorldChunk;
            try patch.receiver.accept(offset, try std.fmt.hexToBytes(&decoded, encoded));
            if (patch.receiver.received == patch.receiver.bytes.len) {
                const bytes = try patch.receiver.validatedBytes();
                if (bytes.len < 2) return error.InvalidWorldConfig;
                patch.receiver.deinit(std.heap.c_allocator);
                for (&self.patches) |*maybe| if (maybe.*) |*entry| if (entry == patch) {
                    maybe.* = null;
                };
                self.patches_applied += 1;
            }
            var command: [96]u8 = undefined;
            client(index, try std.fmt.bufPrintZ(&command, "dk3_world_patch_ack {d} {d}", .{ owner, serial }));
        }
    }
};
fn number(comptime T: type, words: *std.mem.TokenIterator(u8, .scalar)) !T {
    return std.fmt.parseInt(T, words.next() orelse return error.MissingArgument, 10);
}
fn acknowledge(index: u16, entry: Admission) void {
    var command: [128]u8 = undefined;
    client(index, std.fmt.bufPrintZ(&command, "dk3_world_ack {d} {d} {s}", .{ entry.handle, entry.receiver.received, if (entry.ready) @as([]const u8, "ready") else "receiving" }) catch unreachable);
}
/// Ordinary client command, executed by the engine as if received from the network.
pub fn client(index: u16, command: [:0]const u8) void {
    _ = engine.gateway.call(c.BOTLIB_EA_COMMAND, .{ @as(isize, index), command.ptr });
}
