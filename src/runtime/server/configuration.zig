// SPDX-License-Identifier: GPL-2.0-or-later
//! Incremental updates use the admission stream's bounded chunks and digest.
//! A snapshot cannot expose a foreign resource before its complete definition.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/server.zig");
const access = @import("region_access.zig");
const wire = @import("../domain/world_admission.zig");
pub const State = struct {
    enabled: bool = false,
    sent: u64 = 0,
    acknowledged: u64 = 0,
    dirty: [c.MAX_CONFIGSTRINGS]bool = @splat(false),
    pending: ?struct { index: u16, bytes: []u8, offset: usize = 0, digest: u64 } = null,
    pub fn deinit(self: *State) void {
        if (self.pending) |pending| std.heap.c_allocator.free(pending.bytes);
        self.* = .{};
    }
    /// The client has just received a complete gamestate (it carries every
    /// configstring stored so far): nothing is outstanding, and changes from
    /// now on travel by bounded patches.
    pub fn begin(self: *State) void {
        if (self.pending) |pending| std.heap.c_allocator.free(pending.bytes);
        self.* = .{ .enabled = true };
    }
    pub fn waiting(self: *const State, index: usize) bool {
        return self.dirty[index] or (self.pending != null and self.pending.?.index == index);
    }
    pub fn available(self: *const State, entity: c.entityState_t) bool {
        if (entity.modelindex > 0 and self.waiting(c.CS_MODELS + @as(usize, @intCast(entity.modelindex)))) return false;
        if (entity.loopSound > 0 and self.waiting(c.CS_SOUNDS + @as(usize, @intCast(entity.loopSound)))) return false;
        if (entity.eType == c.ET_EVENTS + c.EV_GENERAL_SOUND and self.waiting(c.CS_SOUNDS + @as(usize, @intCast(entity.eventParm)))) return false;
        return true;
    }
    pub fn queue(self: *State, index: usize, regional: bool) bool {
        if (!regional or !self.enabled) return false;
        self.dirty[index] = true;
        return true;
    }
    pub fn acknowledge(self: *State, serial: u64) !void {
        if (serial < self.acknowledged or serial > self.sent) return error.InvalidWorldAcknowledgement;
        self.acknowledged = serial;
    }
    fn step(self: *State, network: u32, budget: *usize) !void {
        while (budget.* > 0) {
            if (self.pending == null) {
                var index: ?u16 = null;
                // Resource definitions precede frequently changing lightstyles.
                for (0..self.dirty.len) |cursor| {
                    const i = (cursor + c.CS_MODELS) % self.dirty.len;
                    if (!self.dirty[i]) continue;
                    index = @intCast(i);
                    break;
                }
                const i = index orelse return;
                var value: [c.MAX_GAMESTATE_CHARS]u8 = undefined;
                _ = engine.gateway.call(c.G_GET_CONFIGSTRING, .{ @as(isize, i), &value, @as(isize, value.len) });
                const text = std.mem.sliceTo(&value, 0);
                const bytes = try std.heap.c_allocator.alloc(u8, text.len + 2);
                std.mem.writeInt(u16, bytes[0..2], i, .little);
                @memcpy(bytes[2..], text);
                self.pending = .{ .index = i, .bytes = bytes, .digest = std.hash.Wyhash.hash(0, bytes) };
                self.dirty[i] = false;
            }
            const pending = &self.pending.?;
            const end = @min(pending.bytes.len, pending.offset + wire.chunk_size);
            var encoded: [wire.chunk_size * 2]u8 = undefined;
            var command: [c.MAX_STRING_CHARS]u8 = undefined;
            engine.send(0, try std.fmt.bufPrintZ(&command, "dk3_world_patch {d} {d} {d} {d} {d} {s}", .{ network, self.sent + 1, pending.bytes.len, pending.digest, pending.offset, try wire.hex(&encoded, pending.bytes[pending.offset..end]) }));
            self.sent += 1;
            budget.* -= 1;
            pending.offset = end;
            if (end == pending.bytes.len) {
                std.heap.c_allocator.free(pending.bytes);
                self.pending = null;
            }
        }
    }
};
pub fn changed(index: i32) bool {
    const region = access.region orelse return false;
    if (region.manifest.count == 0) return false;
    const owner = access.byHandle(@import("../engine/worlds.zig").current()) orelse return false;
    return owner.configuration.queue(@intCast(index), true);
}
pub fn publish() !void {
    const region = access.region orelse return;
    // Arenas retain ordinary engine configstrings and match semantics.
    if (region.manifest.count == 0) return;
    var outstanding = region.initial.configuration.sent - region.initial.configuration.acknowledged;
    for (region.residents.entries) |maybe| if (maybe) |entry| if (entry.context) |context| {
        outstanding += context.configuration.sent - context.configuration.acknowledged;
    };
    if (outstanding > 4) return error.WorldUpdateWindow;
    var budget: usize = 4 - @as(usize, @intCast(outstanding));
    const initial_scope = try region.initial.select();
    defer initial_scope.deinit();
    try region.initial.configuration.step(region.initial.network_id, &budget);
    for (region.residents.entries) |maybe| if (maybe) |entry| {
        if (!entry.ready or entry.publication == null or !entry.publication.?.ready) continue;
        const context = entry.context orelse continue;
        const scope = try context.select();
        defer scope.deinit();
        try context.configuration.step(context.network_id, &budget);
    };
}

pub fn clientCommand(client: usize, name: []const u8) bool {
    if (!std.mem.eql(u8, name, "dk3_world_patch_ack")) return false;
    if (client != 0 or engine.integer("g_gametype") != c.GT_SINGLE_PLAYER) return true;
    const region = access.region orelse return true;
    var buffer: [64]u8 = undefined;
    const id = std.fmt.parseInt(u32, engine.argv(1, &buffer), 10) catch return true;
    const serial = std.fmt.parseInt(u64, engine.argv(2, &buffer), 10) catch return true;
    const owner = if (id == 0) region.initial else access.byHandle(@enumFromInt(id)) orelse return true;
    owner.configuration.acknowledge(serial) catch return true;
    return true;
}
test "resource update acknowledgements cannot expand the reliable window" {
    var state: State = .{ .sent = 4 };
    try std.testing.expectError(error.InvalidWorldAcknowledgement, state.acknowledge(5));
    try state.acknowledge(2);
    try std.testing.expectEqual(@as(u64, 2), state.sent - state.acknowledged);
    try std.testing.expectError(error.InvalidWorldAcknowledgement, state.acknowledge(1));
    try state.acknowledge(4);
    try std.testing.expectEqual(@as(u64, 0), state.sent - state.acknowledged);
}
test "regional configuration coalesces changes and leaves arenas on engine publication" {
    var state: State = .{};
    try std.testing.expect(!state.queue(c.CS_DK3_LIGHTSTYLES, true));
    state.enabled = true;
    try std.testing.expect(!state.queue(c.CS_DK3_LIGHTSTYLES, false));
    try std.testing.expect(!state.waiting(c.CS_DK3_LIGHTSTYLES));
    for (0..500) |_| try std.testing.expect(state.queue(c.CS_DK3_LIGHTSTYLES, true));
    var count: usize = 0;
    for (state.dirty) |dirty| count += @intFromBool(dirty);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u64, 0), state.sent);
}
test "snapshots wait for both models and sound events to finish bounded publication" {
    var state: State = .{ .enabled = true };
    var entity = std.mem.zeroes(c.entityState_t);
    entity.modelindex = 7;
    try std.testing.expect(state.available(entity));
    _ = state.queue(c.CS_MODELS + 7, true);
    try std.testing.expect(!state.available(entity));
    state.dirty[c.CS_MODELS + 7] = false;
    try std.testing.expect(state.available(entity));
    entity.eType = c.ET_EVENTS + c.EV_GENERAL_SOUND;
    entity.eventParm = 9;
    _ = state.queue(c.CS_SOUNDS + 9, true);
    try std.testing.expect(!state.available(entity));
    state.dirty[c.CS_SOUNDS + 9] = false;
    entity.eType = c.ET_GENERAL;
    entity.loopSound = 9;
    state.pending = .{ .index = c.CS_SOUNDS + 9, .bytes = &.{}, .digest = 0 };
    try std.testing.expect(!state.available(entity));
    state.pending = null;
    try std.testing.expect(state.available(entity));
}
test "changes before the gamestate never hide entities, and a new gamestate recovers the window" {
    var state: State = .{};
    var entity = std.mem.zeroes(c.entityState_t);
    entity.modelindex = 12;
    // A restore during map load is carried by the gamestate itself.
    try std.testing.expect(!state.queue(c.CS_MODELS + 12, true));
    try std.testing.expect(state.available(entity));
    state.begin();
    try std.testing.expect(state.queue(c.CS_MODELS + 12, true));
    try std.testing.expect(!state.available(entity));
    // Acknowledgements lost with an old gamestate cannot stall the next one.
    state.sent = 4;
    state.begin();
    try std.testing.expect(state.available(entity));
    try std.testing.expectEqual(@as(u64, 0), state.sent - state.acknowledged);
    try std.testing.expectError(error.InvalidWorldAcknowledgement, state.acknowledge(3));
}
