//! Build logic: turns one renderer_opengl2 GLSL file into the C source CMake generates for it
//! (ioq3 cmake/utils/stringify_shader.cmake, run by cmake/renderer_gl2.cmake:46-63). build/ioq3.zig
//! calls it while the graph is configured and hands the bytes to a `WriteFile` step.
// FRD: specs/frds/FRD-008-ioquake3-client-renderers-and-game-modules-built-by-zig-build.md
const std = @import("std");

/// Writes `const char *fallbackShader_<name> =` and `glsl` as one C string literal:
/// `\` → `\\`, `"` → `\"`, each newline → `\n"` newline `"` (stringify_shader.cmake:7-11).
pub fn stringify(w: *std.Io.Writer, name: []const u8, glsl: []const u8) std.Io.Writer.Error!void {
    try w.print("const char *fallbackShader_{s} =\n\"", .{name});
    for (glsl) |byte| switch (byte) {
        '\\' => try w.writeAll("\\\\"),
        '"' => try w.writeAll("\\\""),
        '\n' => try w.writeAll("\\n\"\n\""),
        else => try w.writeByte(byte),
    };
    try w.writeAll("\";\n");
}

test "stringify escapes backslashes and quotes and splits lines like stringify_shader.cmake" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try stringify(&out.writer, "generic_fp", "a\\b\"c\nd\n");
    try std.testing.expectEqualStrings(
        "const char *fallbackShader_generic_fp =\n\"a\\\\b\\\"c\\n\"\n\"d\\n\"\n\"\";\n",
        out.written(),
    );
}
