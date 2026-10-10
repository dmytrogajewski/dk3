// SPDX-License-Identifier: GPL-2.0-or-later
//! Module-wide engine imports, allocation and diagnostics.
const std = @import("std");
const c = @import("c.zig").c;

/// Engine imports; valid from GetRefAPI until unload.
pub export var ri: c.refimport_t = undefined;
/// Renderer-owned allocations live until Shutdown releases them.
pub const gpa = std.heap.c_allocator;

pub fn print(level: c_int, comptime format: []const u8, args: anytype) void {
    var buffer: [4096]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, format, args) catch blk: {
        buffer[buffer.len - 1] = 0;
        break :blk buffer[0 .. buffer.len - 1 :0];
    };
    ri.Printf.?(level, "%s", text.ptr);
}

pub fn info(comptime format: []const u8, args: anytype) void {
    print(c.PRINT_ALL, format, args);
}

pub fn warn(comptime format: []const u8, args: anytype) void {
    print(c.PRINT_WARNING, "WARNING: " ++ format, args);
}

pub fn developer(comptime format: []const u8, args: anytype) void {
    print(c.PRINT_DEVELOPER, format, args);
}

pub fn fail(level: c_int, comptime format: []const u8, args: anytype) noreturn {
    var buffer: [2048]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, format, args) catch "renderer_vulkan: error text overflow";
    ri.Error.?(level, "%s", text.ptr);
    unreachable;
}

pub fn milliseconds() i32 {
    return ri.Milliseconds.?();
}

pub fn cvar(name: [*:0]const u8, value: [*:0]const u8, flags: c_int) *c.cvar_t {
    return ri.Cvar_Get.?(name, value, flags);
}

/// A NUL-terminated name as a slice.
pub fn span(text: [*c]const u8) []const u8 {
    if (text == null) return "";
    return std.mem.span(@as([*:0]const u8, @ptrCast(text)));
}

/// `name` copied into a fixed MAX_QPATH buffer.
pub fn qpath(buffer: *[c.MAX_QPATH]u8, name: []const u8) [:0]const u8 {
    const length = @min(name.len, buffer.len - 1);
    @memcpy(buffer[0..length], name[0..length]);
    buffer[length] = 0;
    return buffer[0..length :0];
}

/// Engine file bytes; release with `freeFile`.
pub fn readFile(name: [*:0]const u8) ?[]u8 {
    var bytes: ?*anyopaque = null;
    const length = ri.FS_ReadFile.?(name, &bytes);
    if (length < 0 or bytes == null) return null;
    return @as([*]u8, @ptrCast(bytes.?))[0..@intCast(length)];
}

pub fn freeFile(bytes: []u8) void {
    ri.FS_FreeFile.?(bytes.ptr);
}

pub fn fileExists(name: [*:0]const u8) bool {
    return ri.FS_ReadFile.?(name, null) >= 0;
}
