// SPDX-License-Identifier: GPL-2.0-or-later
//! Destination prediction geometry and class-owned media, without changing the
//! active snapshot, input prediction, music or loading screen.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const wire = @import("../domain/world_admission.zig");
pub const State = struct {
    server_id: u32,
    checksum: u32,
    collision: u32,
    collision_ready: bool = false,
    receiver: wire.Receiver,
    game: c.gameState_t = undefined,
    definitions: bool = false,
    inline_models: [c.MAX_MODELS]c.qhandle_t = @splat(0),
    inline_count: usize = 0,
    inline_cursor: usize = 1,
    model_cursor: usize = 1,
    sound_cursor: usize = 1,
    models: usize = 0,
    sounds: usize = 0,
    sky: @import("sky.zig").State = .{},
    ready: bool = false,
    failed: bool = false,
    pub fn create(server_id: u32, name: []const u8, checksum: u32, length: usize, digest: u64) !*State {
        const self = try std.heap.c_allocator.create(State);
        errdefer std.heap.c_allocator.destroy(self);
        var receiver = try wire.Receiver.init(std.heap.c_allocator, length, digest);
        errdefer receiver.deinit(std.heap.c_allocator);
        var path: [80]u8 = undefined;
        const handle = engine.gateway.call(c.CG_DK3_COLLISION_REQUEST_V1, .{(try std.fmt.bufPrintZ(&path, "maps/{s}.bsp", .{name})).ptr});
        if (handle <= 0) return error.PredictionWorldUnavailable;
        self.* = .{ .server_id = server_id, .checksum = checksum, .collision = @intCast(handle), .receiver = receiver };
        return self;
    }
    pub fn destroy(self: *State) void {
        _ = engine.gateway.call(c.CG_DK3_COLLISION_RELEASE_V1, .{@as(isize, self.collision)});
        self.receiver.deinit(std.heap.c_allocator);
        std.heap.c_allocator.destroy(self);
    }
    pub fn acknowledge(self: *const State) !void {
        var command: [128]u8 = undefined;
        _ = engine.gateway.call(c.CG_SENDCLIENTCOMMAND, .{(try std.fmt.bufPrintZ(&command, "dk3_world_ack {d} {d} {s}", .{ self.server_id, self.receiver.received, if (self.ready) @as([]const u8, "ready") else "receiving" })).ptr});
    }
    pub fn fail(self: *State, err: anyerror) void {
        self.failed = true;
        failure(self.server_id, err);
    }
    pub fn failure(server_id: u32, err: anyerror) void {
        var command: [192]u8 = undefined;
        _ = engine.gateway.call(c.CG_SENDCLIENTCOMMAND, .{(std.fmt.bufPrintZ(&command, "dk3_world_failed {d} {s}", .{ server_id, @errorName(err) }) catch unreachable).ptr});
        engine.print(std.fmt.bufPrintZ(&command, "dk3 world admission: handle={d} failed={s}\n", .{ server_id, @errorName(err) }) catch unreachable);
    }
    pub fn accept(self: *State, offset: usize, encoded: []const u8) !void {
        if (self.failed) return;
        var bytes: [wire.chunk_size]u8 = undefined;
        if (encoded.len == 0 or encoded.len > bytes.len * 2 or encoded.len % 2 != 0) return error.InvalidWorldChunk;
        const decoded = try std.fmt.hexToBytes(&bytes, encoded);
        try self.receiver.accept(offset, decoded);
        if (self.receiver.received == self.receiver.bytes.len) {
            var reader = try self.receiver.finish();
            @memset(std.mem.asBytes(&self.game), 0);
            self.game.dataCount = 1;
            while (try reader.next()) |row| {
                const begin: usize = @intCast(self.game.dataCount);
                self.game.stringOffsets[row.index] = @intCast(begin);
                @memcpy(self.game.stringData[begin..][0..row.value.len], row.value);
                self.game.dataCount += @intCast(row.value.len + 1);
            }
            if (!std.mem.eql(u8, try engine.config(&self.game, c.CS_GAME_VERSION), @import("../engine/player_state.zig").version)) return error.RuntimeMismatch;
            self.definitions = true;
        }
        try self.acknowledge();
    }
    /// Completed admission units, never an elapsed-time estimate. Rendering is
    /// the first unit; model/sound counts become known from validated config.
    pub fn progress(self: *const State) f32 {
        if (self.ready) return 1;
        if (!self.definitions or !self.collision_ready) return 0;
        var total: usize = self.inline_count + 1; // Render world and final sky.
        for (1..c.MAX_MODELS) |index| if (self.game.stringOffsets[c.CS_MODELS + index] != 0) {
            total += 1;
        };
        for (1..c.MAX_SOUNDS) |index| if (self.game.stringOffsets[c.CS_SOUNDS + index] != 0) {
            total += 1;
        };
        return @as(f32, @floatFromInt(self.inline_cursor + self.models + self.sounds)) / @as(f32, @floatFromInt(total));
    }
    /// One resource per step; renderer admission has already completed. A map is
    /// acknowledged only after actual collision, inline, model and sound work.
    pub fn step(self: *State, render_world: u32, name: []const u8) !void {
        if (self.ready or self.failed) return;
        if (!self.collision_ready) {
            const status = engine.gateway.call(c.CG_DK3_COLLISION_POLL_V1, .{@as(isize, self.collision)});
            if (status < 0) return error.PredictionWorldUnavailable;
            if (status == 0) return;
            const checksum: u32 = @truncate(@as(usize, @bitCast(engine.gateway.call(c.CG_DK3_COLLISION_CHECKSUM_V1, .{@as(isize, self.collision)}))));
            if (checksum != self.checksum) return error.WorldAssetMismatch;
            const count = engine.gateway.call(c.CG_DK3_COLLISION_MODELS_V1, .{@as(isize, self.collision)});
            if (count < 1 or count > self.inline_models.len) return error.InlineModelLimit;
            self.inline_count = @intCast(count);
            self.collision_ready = true;
            return;
        }
        if (!self.definitions) return;
        const previous = engine.gateway.call(c.CG_DK3_WORLD_CURRENT_V1, .{});
        if (engine.gateway.call(c.CG_DK3_WORLD_SELECT_V1, .{@as(isize, render_world)}) == 0) return error.RenderWorldNotReady;
        defer if (engine.gateway.call(c.CG_DK3_WORLD_SELECT_V1, .{previous}) == 0) @panic("lost active renderer world");
        if (self.inline_cursor < self.inline_count) {
            var path: [20]u8 = undefined;
            const handle = engine.gateway.call(c.CG_R_REGISTERMODEL, .{(try std.fmt.bufPrintZ(&path, "*{d}", .{self.inline_cursor})).ptr});
            if (handle <= 0) return error.MissingInlineModel;
            self.inline_models[self.inline_cursor] = @intCast(handle);
            self.inline_cursor += 1;
            return;
        }
        while (self.model_cursor < c.MAX_MODELS) {
            const model = try engine.config(&self.game, c.CS_MODELS + self.model_cursor);
            self.model_cursor += 1;
            if (model.len == 0) continue;
            if (std.mem.endsWith(u8, model, ".sp2")) {
                _ = try @import("sprites.zig").register(model);
            } else if (try @import("models.zig").register(model) == 0) return error.MissingWorldModel;
            self.models += 1;
            return;
        }
        while (self.sound_cursor < c.MAX_SOUNDS) {
            const sound = try engine.config(&self.game, c.CS_SOUNDS + self.sound_cursor);
            self.sound_cursor += 1;
            if (sound.len == 0) continue;
            if (try engine.registerSound(sound) == 0) return error.MissingWorldSound;
            self.sounds += 1;
            return;
        }
        try self.sky.init(name, &self.game);
        self.ready = true;
        try self.acknowledge();
        var text: [256]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 world admission: map={s} handle={d} ready=1 inline={d} models={d} sounds={d} checksum={d}\n", .{ name, self.server_id, self.inline_count - 1, self.models, self.sounds, self.checksum }));
    }
};

test "loading progress counts admitted resources and reserves completion for finalization" {
    const t = std.testing;
    const state = try t.allocator.create(State);
    defer t.allocator.destroy(state);
    state.* = .{ .server_id = 1, .checksum = 0, .collision = 1, .receiver = .{ .bytes = &.{}, .digest = 0 } };
    try t.expectEqual(@as(f32, 0), state.progress());
    state.game = std.mem.zeroes(c.gameState_t);
    state.game.dataCount = 1;
    try @import("config_patch.zig").apply(&state.game, c.CS_MODELS + 3, "models/actor.md3");
    try @import("config_patch.zig").apply(&state.game, c.CS_SOUNDS + 7, "sounds/actor.wav");
    state.definitions = true;
    state.collision_ready = true;
    state.inline_count = 3;
    try t.expectApproxEqAbs(@as(f32, 1.0 / 6.0), state.progress(), 0.0001);
    state.inline_cursor = 3;
    state.models = 1;
    state.sounds = 1;
    try t.expectApproxEqAbs(@as(f32, 5.0 / 6.0), state.progress(), 0.0001);
    state.ready = true;
    try t.expectEqual(@as(f32, 1), state.progress());
}
