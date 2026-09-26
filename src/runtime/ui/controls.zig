// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const engine = @import("../engine/ui.zig");
const c = engine.c;
pub const Entry = struct { label: []const u8, command: [:0]const u8 };
pub const entries = [_]Entry{
    .{ .label = "Forward", .command = "+forward" },              .{ .label = "Back", .command = "+back" },
    .{ .label = "Left", .command = "+moveleft" },                .{ .label = "Right", .command = "+moveright" },
    .{ .label = "Jump / climb", .command = "+moveup" },          .{ .label = "Crouch", .command = "+movedown" },
    .{ .label = "Attack", .command = "+attack" },                .{ .label = "Walk", .command = "+speed" },
    .{ .label = "Next weapon", .command = "weapnext" },          .{ .label = "Previous weapon", .command = "weapprev" },
    .{ .label = "Use", .command = "use" },                       .{ .label = "Inventory", .command = "inventory" },
    .{ .label = "Next inventory item", .command = "invnext" },   .{ .label = "Previous inventory item", .command = "invprev" },
    .{ .label = "Next attribute", .command = "attribute_next" }, .{ .label = "Increase attribute", .command = "attribute_increase" },
    .{ .label = "Quicksave", .command = "save quick" },          .{ .label = "Quickload", .command = "load quick" },
};
pub const Capture = struct {
    action: ?usize = null,
    conflict: ?i32 = null,
    pub fn key(self: *Capture, key_code: i32) bool {
        const action = self.action orelse return false;
        if (key_code == c.K_ESCAPE) {
            self.* = .{};
            return true;
        }
        if (key_code <= 0 or key_code >= c.MAX_KEYS or key_code == '`' or key_code == '~') return true;
        if (self.conflict) |conflict| {
            if (key_code == c.K_ENTER) {
                assign(action, conflict);
                self.* = .{};
            }
            return true;
        }
        var prior: [256]u8 = undefined;
        const command = engine.binding(key_code, &prior);
        if (command.len > 0 and !std.ascii.eqlIgnoreCase(command, entries[action].command)) {
            self.conflict = key_code;
        } else {
            assign(action, key_code);
            self.* = .{};
        }
        return true;
    }
};
fn assign(action: usize, key_code: i32) void {
    var buffer: [256]u8 = undefined;
    for (1..c.MAX_KEYS) |key_value| {
        const code: i32 = @intCast(key_value);
        if (std.ascii.eqlIgnoreCase(engine.binding(code, &buffer), entries[action].command)) engine.bind(code, "");
    }
    engine.bind(key_code, entries[action].command);
}
pub fn bound(action: usize) ?i32 {
    var buffer: [256]u8 = undefined;
    for (1..c.MAX_KEYS) |key_value| if (std.ascii.eqlIgnoreCase(engine.binding(@intCast(key_value), &buffer), entries[action].command)) return @intCast(key_value);
    return null;
}
