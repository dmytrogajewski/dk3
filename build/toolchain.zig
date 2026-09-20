//! Toolchain gate: the installed Zig must belong to the release series pinned by
//! `minimum_zig_version` in build.zig.zon.
// FRD: specs/frds/FRD-001-zig-build-graph-skeleton-and-green-quality-gate.md
const std = @import("std");

/// Failure reported when the installed compiler is outside the pinned release series.
pub const Error = error{ ZigVersionMismatch, InvalidPin };

/// Accepts `installed` only when it shares the pinned major.minor series and is not older
/// than the pin (so pre-releases of the pinned version are rejected).
pub fn check(pinned: std.SemanticVersion, installed: std.SemanticVersion) Error!void {
    if (installed.major != pinned.major or installed.minor != pinned.minor) return error.ZigVersionMismatch;
    if (installed.order(pinned) == .lt) return error.ZigVersionMismatch;
}

/// Buffer size that always fits the message produced by `describeMismatch`.
pub const mismatch_message_capacity = 256;

/// Formats the configure-time error naming both versions and the remediation.
pub fn describeMismatch(buf: []u8, pinned: std.SemanticVersion, installed: std.SemanticVersion) error{NoSpaceLeft}![]const u8 {
    return std.fmt.bufPrint(buf, "zig version mismatch: pinned {f} (build.zig.zon minimum_zig_version), " ++
        "installed {f}; install Zig {d}.{d}.x or change the pin", .{ pinned, installed, pinned.major, pinned.minor });
}

/// Checks `installed` against the pin text; on mismatch prints both versions to stderr.
pub fn verify(pin_text: []const u8, installed: std.SemanticVersion) Error!void {
    const pinned = std.SemanticVersion.parse(pin_text) catch return error.InvalidPin;
    check(pinned, installed) catch |err| {
        var buf: [mismatch_message_capacity]u8 = undefined;
        std.debug.print("error: {s}\n", .{describeMismatch(&buf, pinned, installed) catch "zig version mismatch"});
        return err;
    };
}

/// Configure-time gate: stops the build runner with exit status 1 when `verify` fails.
pub fn enforce(pin_text: []const u8, installed: std.SemanticVersion) void {
    verify(pin_text, installed) catch |err| {
        std.debug.print("error: toolchain gate failed ({s}) for pin '{s}'\n", .{ @errorName(err), pin_text });
        std.process.exit(1);
    };
}

test "check rejects an older minor release" {
    const pinned = try std.SemanticVersion.parse("0.16.0");
    const installed = try std.SemanticVersion.parse("0.15.2");
    try std.testing.expectError(error.ZigVersionMismatch, check(pinned, installed));
}

test "check rejects a pre-release below the pin" {
    const pinned = try std.SemanticVersion.parse("0.16.0");
    const installed = try std.SemanticVersion.parse("0.16.0-dev.1");
    try std.testing.expectError(error.ZigVersionMismatch, check(pinned, installed));
}

test "check accepts a newer patch release of the pinned series" {
    const pinned = try std.SemanticVersion.parse("0.16.0");
    try check(pinned, try std.SemanticVersion.parse("0.16.1"));
}

test "check rejects a newer minor release" {
    const pinned = try std.SemanticVersion.parse("0.16.0");
    const installed = try std.SemanticVersion.parse("0.17.0");
    try std.testing.expectError(error.ZigVersionMismatch, check(pinned, installed));
}

test "mismatch message names both the pinned and the installed version" {
    var buf: [mismatch_message_capacity]u8 = undefined;
    const pinned = try std.SemanticVersion.parse("0.16.0");
    const installed = try std.SemanticVersion.parse("0.15.2");
    const message = try describeMismatch(&buf, pinned, installed);
    try std.testing.expect(std.mem.indexOf(u8, message, "pinned 0.16.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "installed 0.15.2") != null);
}

test "installed zig satisfies the pin declared in build.zig.zon" {
    const build_info = @import("build_info");
    try verify(build_info.pinned_zig_version, @import("builtin").zig_version);
}
