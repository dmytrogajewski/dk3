// SPDX-License-Identifier: GPL-2.0-or-later
//! Menu selection is persistent state; moving the cursor only changes hover.
const std = @import("std");
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    pub fn contains(self: Rect, x: f32, y: f32) bool {
        return x >= self.x and y >= self.y and x < self.x + self.width and y < self.y + self.height;
    }
};
pub const Layout = struct {
    scale: f32,
    x: f32,
    y: f32,
    pub fn fit(width: f32, height: f32) Layout {
        const scale = @max(0.01, @min(width / 640, height / 480));
        return .{ .scale = scale, .x = (width - 640 * scale) * 0.5, .y = (height - 480 * scale) * 0.5 };
    }
};
pub const Selection = struct {
    selected: ?usize = null,
    hovered: ?usize = null,
    pub fn move(self: *Selection, count: usize, direction: i32) void {
        if (count == 0) {
            self.selected = null;
            return;
        }
        const current: i64 = @intCast(self.selected orelse if (direction > 0) count - 1 else 0);
        self.selected = @intCast(@mod(current + direction, @as(i64, @intCast(count))));
    }
    pub fn click(self: *Selection) bool {
        self.selected = self.hovered orelse return false;
        return true;
    }
};
test "moving from a chosen save to its load button preserves selection" {
    var row: Selection = .{ .hovered = 3 };
    try std.testing.expect(row.click());
    row.hovered = null;
    try std.testing.expectEqual(@as(?usize, 3), row.selected);
    try std.testing.expect(!row.click());
    row.move(5, 1);
    try std.testing.expectEqual(@as(?usize, 4), row.selected);
    row.move(5, 1);
    try std.testing.expectEqual(@as(?usize, 0), row.selected);
    const wide = Layout.fit(1920, 1080);
    try std.testing.expectEqual(@as(f32, 240), wide.x);
    try std.testing.expectEqual(@as(f32, 2.25), wide.scale);
}
