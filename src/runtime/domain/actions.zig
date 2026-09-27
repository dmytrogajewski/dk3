// SPDX-License-Identifier: GPL-2.0-or-later
//! Supplied action programs and their persistent execution cursor.
const std = @import("std");
const Reader = @import("tables.zig").Reader;
pub const Action = struct { name: []const u8, args: []const []const u8 };
pub const Script = struct { name: []const u8, owner: []const u8, loops: i32, actions: []const Action };
pub const Execution = struct {
    name: []const u8 = "",
    index: u16 = 0,
    remaining: i32 = 1,
    active: bool = false,
    started: bool = false,
    due_ms: i64 = 0,
    next_ms: i64 = 0,
    activator: u32 = 0,
    revision: u32 = 0,
};
pub const Program = struct {
    scripts: []const Script = &.{},
    pub fn find(self: Program, name: []const u8) ?Script {
        for (self.scripts) |script| if (std.ascii.eqlIgnoreCase(script.name, name)) return script;
        return null;
    }
    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !Program {
        if (bytes.len > 4 * 1024 * 1024) return error.ActionProgramSize;
        var reader: Reader = .{ .bytes = bytes };
        if (!std.mem.eql(u8, try token(&reader), "dk3_actions") or !std.mem.eql(u8, try token(&reader), "1")) return error.InvalidActionProgram;
        var scripts: std.ArrayList(Script) = .empty;
        while (try reader.token()) |tag| {
            if (!std.mem.eql(u8, tag, "script") or scripts.items.len == 1024) return error.InvalidScriptHeader;
            const name = try token(&reader);
            const owner = try token(&reader);
            const loops = try std.fmt.parseInt(i32, try token(&reader), 10);
            const count = try std.fmt.parseInt(u16, try token(&reader), 10);
            if (name.len == 0 or name.len > 64 or owner.len > 64 or count > 1024 or loops < -1 or loops > 10000) return error.InvalidScriptBounds;
            for (scripts.items) |script| if (std.ascii.eqlIgnoreCase(script.name, name)) return error.DuplicateScript;
            const actions = try allocator.alloc(Action, count);
            for (actions) |*action| {
                const kind = try token(&reader);
                const argc = try std.fmt.parseInt(u8, try token(&reader), 10);
                if (argc > 16 or kind.len > 64) return error.InvalidScriptAction;
                const args = try allocator.alloc([]const u8, argc);
                for (args) |*arg| {
                    arg.* = try token(&reader);
                    if (arg.len > 256) return error.InvalidScriptArgument;
                }
                action.* = .{ .name = kind, .args = args };
            }
            try scripts.append(allocator, .{ .name = name, .owner = owner, .loops = loops, .actions = actions });
        }
        return .{ .scripts = try scripts.toOwnedSlice(allocator) };
    }
};
fn token(reader: *Reader) ![]const u8 {
    return try reader.token() orelse error.TruncatedActionProgram;
}
pub fn number(text: []const u8) !f32 {
    const value = try std.fmt.parseFloat(f32, text);
    if (!std.math.isFinite(value) or @abs(value) > 1000000) return error.InvalidScriptNumber;
    return value;
}
test "action programs retain authored ownership and reject truncated setup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try Program.parse(arena.allocator(), "dk3_actions 1 script spawn_wave controller 1 1 spawn 7 monster_slaughterskeet first 1 2 3 90 false");
    const script = program.find("SPAWN_WAVE").?;
    try std.testing.expectEqualStrings("controller", script.owner);
    try std.testing.expectEqualStrings("false", script.actions[0].args[6]);
    try std.testing.expectError(error.TruncatedActionProgram, Program.parse(arena.allocator(), "dk3_actions 1 script bad owner 1 1 spawn 2 monster"));
}
