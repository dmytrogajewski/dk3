// SPDX-License-Identifier: GPL-2.0-or-later
//! Map-scoped resource identities projected through public configstrings.
const std = @import("std");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
comptime {
    const snapshot = @import("../domain/snapshot.zig");
    if (snapshot.model_limit != c.MAX_MODELS or snapshot.sound_limit != c.MAX_SOUNDS) @compileError("native save resource limits must match transport limits");
}
fn Registry(comptime limit: usize, comptime base: i32) type {
    return struct {
        names: [limit][c.MAX_QPATH]u8 = @splat(@splat(0)),
        count: usize = 1,
        fn contains(self: *const @This(), saved: []const []const u8) bool {
            if (saved.len >= self.count) return false;
            for (saved, 1..) |name, index| if (!std.mem.eql(u8, name, std.mem.sliceTo(&self.names[index], 0))) return false;
            return true;
        }
        fn add(self: *@This(), path: []const u8) !u16 {
            if (path.len == 0) return 0;
            if (path.len >= c.MAX_QPATH or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidResourcePath;
            for (1..self.count) |index| if (std.mem.eql(u8, std.mem.sliceTo(&self.names[index], 0), path)) return @intCast(index);
            if (self.count == limit) return error.ResourceCapacity;
            const index = self.count;
            self.count += 1;
            @memcpy(self.names[index][0..path.len], path);
            self.names[index][path.len] = 0;
            engine.config(base + @as(i32, @intCast(index)), self.names[index][0..path.len :0]);
            return @intCast(index);
        }
    };
}
pub const State = struct {
    models: Registry(c.MAX_MODELS, c.CS_MODELS) = .{},
    sounds: Registry(c.MAX_SOUNDS, c.CS_SOUNDS) = .{},
};
var initial: State = .{};
var selected: *State = &initial;
pub fn select(state: *State) *State {
    const previous = selected;
    selected = state;
    return previous;
}
pub fn reset() void {
    selected.models = .{};
    selected.sounds = .{};
}
pub fn capture(allocator: std.mem.Allocator) !@import("../domain/snapshot.zig").Resources {
    const model_names = try allocator.alloc([]const u8, selected.models.count - 1);
    errdefer allocator.free(model_names);
    const sound_names = try allocator.alloc([]const u8, selected.sounds.count - 1);
    for (model_names, 1..) |*name, i| name.* = std.mem.sliceTo(&selected.models.names[i], 0);
    for (sound_names, 1..) |*name, i| name.* = std.mem.sliceTo(&selected.sounds.names[i], 0);
    return .{ .models = model_names, .sounds = sound_names };
}
pub fn restore(saved: @import("../domain/snapshot.zig").Resources) !void {
    reset();
    for (saved.models) |name| _ = try model(name);
    // Preserve old wire indices even when two archived spellings resolve to the
    // same normalized asset. New registrations use the canonical spelling.
    for (saved.sounds) |name| _ = try selected.sounds.add(name);
}
/// Rewinding the current resource prefix is safe without another gamestate.
/// New or reordered identities must be admitted through map initialization.
pub fn canRestoreInPlace(saved: @import("../domain/snapshot.zig").Resources) bool {
    return selected.models.contains(saved.models) and selected.sounds.contains(saved.sounds);
}
pub fn model(path: []const u8) !u16 {
    return selected.models.add(path);
}
pub fn modelName(index: u16) []const u8 {
    std.debug.assert(index > 0 and index < selected.models.count);
    return std.mem.sliceTo(&selected.models.names[index], 0);
}
pub fn soundName(index: u16) []const u8 {
    std.debug.assert(index > 0 and index < selected.sounds.count);
    return std.mem.sliceTo(&selected.sounds.names[index], 0);
}
pub fn sound(path: []const u8) !u16 {
    var normalized: [c.MAX_QPATH]u8 = undefined;
    if (path.len >= c.MAX_QPATH) return error.InvalidResourcePath;
    return selected.sounds.add(try @import("../domain/audio.zig").soundPath(path, &normalized));
}
pub fn floorBounds(path: []const u8) !?@import("../domain/md3.zig").Bounds {
    if (!std.mem.endsWith(u8, path, ".dkm")) return null;
    var buffer: [c.MAX_QPATH + 5]u8 = undefined;
    const converted = try std.fmt.bufPrintZ(&buffer, "{s}.md3", .{path});
    const bytes = @import("../engine/files.zig").read(.server, &engine.gateway, std.heap.c_allocator, converted, 32 * 1024 * 1024) catch |err| switch (err) {
        error.InvalidFileSize => return null,
        else => return err,
    };
    defer std.heap.c_allocator.free(bytes);
    return @import("../domain/md3.zig").bounds(bytes);
}

test "in-place restoration requires every saved resource identity already published" {
    const t = std.testing;
    var registry: Registry(4, 0) = .{};
    @memcpy(registry.names[1][0..5], "first");
    @memcpy(registry.names[2][0..6], "second");
    registry.count = 3;
    try t.expect(registry.contains(&.{}));
    try t.expect(registry.contains(&.{"first"}));
    try t.expect(registry.contains(&.{ "first", "second" }));
    try t.expect(!registry.contains(&.{ "second", "first" }));
    try t.expect(!registry.contains(&.{ "first", "second", "new" }));
}
