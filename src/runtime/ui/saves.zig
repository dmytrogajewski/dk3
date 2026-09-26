// SPDX-License-Identifier: GPL-2.0-or-later
//! Save rows keep their own selection when focus moves to the Load/Save button.
const std = @import("std");
const engine = @import("../engine/ui.zig");
const c = engine.c;
const snapshot = @import("../domain/snapshot.zig");
pub const Browser = struct {
    names: [128][48]u8 = @splat(@splat(0)),
    count: usize = 0,
    choice: @import("../domain/menu.zig").Selection = .{},
    first: usize = 0,
    pub fn name(self: *const Browser, index: usize) []const u8 {
        return std.mem.sliceTo(&self.names[index], 0);
    }
    pub fn selected(self: *const Browser) ?[]const u8 {
        return self.name(self.choice.selected orelse return null);
    }
    pub fn refresh(self: *Browser, writing: bool) !void {
        self.* = .{};
        if (writing) {
            @memcpy(self.names[0][0..5], "quick");
            for (1..9) |i| _ = try std.fmt.bufPrintZ(&self.names[i], "save{d}", .{i});
            self.count = 9;
        } else {
            var buffer: [16384]u8 = @splat(0);
            const count = engine.gateway.call(c.UI_FS_GETFILELIST, .{ @as([*:0]const u8, "saves"), @as([*:0]const u8, ".sav"), &buffer, @as(isize, buffer.len) });
            var at: usize = 0;
            for (0..@intCast(@max(0, count))) |_| {
                if (at >= buffer.len) break;
                const end = at + (std.mem.indexOfScalar(u8, buffer[at..], 0) orelse break);
                const file = buffer[at..end];
                at = end + 1;
                if (!std.mem.endsWith(u8, file, ".sav")) continue;
                const slot = file[0 .. file.len - 4];
                if (!snapshot.validName(slot) or std.mem.startsWith(u8, slot, "dk3-") or self.count == self.names.len) continue;
                @memcpy(self.names[self.count][0..slot.len], slot);
                self.count += 1;
            }
            std.mem.sort([48]u8, self.names[0..self.count], {}, less);
        }
        if (self.count > 0) self.choice.selected = 0;
    }
    pub fn page(self: *Browser, direction: i32) void {
        const pages = @max(1, (self.count + 7) / 8);
        self.first = @as(usize, @intCast(@mod(@as(i64, @intCast(self.first / 8)) + direction, @as(i64, @intCast(pages))))) * 8;
    }
    pub fn validate(self: *const Browser) !void {
        const slot = self.selected() orelse return error.SelectSaveFirst;
        var path: [80]u8 = undefined;
        const bytes = try @import("../engine/files.zig").read(.ui, &engine.gateway, std.heap.c_allocator, try std.fmt.bufPrintZ(&path, "saves/{s}.sav", .{slot}), snapshot.maximum);
        defer std.heap.c_allocator.free(bytes);
        var loaded = try snapshot.decode(std.heap.c_allocator, bytes);
        defer loaded.deinit(std.heap.c_allocator);
    }
};
fn less(_: void, a: [48]u8, b: [48]u8) bool {
    return std.mem.order(u8, std.mem.sliceTo(&a, 0), std.mem.sliceTo(&b, 0)) == .lt;
}
