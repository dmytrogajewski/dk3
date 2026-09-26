// SPDX-License-Identifier: GPL-2.0-or-later
//! Conservative source-level rules identity, independent of optimization and ELF layout.
const std = @import("std");
pub fn declare(b: *std.Build) []const u8 {
    var paths: std.ArrayList([]const u8) = .empty;
    for ([_][]const u8{ "src/runtime", "src/weapons", "src/items", "src/actors", "src/multiplayer", "engine/ioquake3/code/game" }) |root| {
        var directory = std.Io.Dir.cwd().openDir(b.graph.io, b.pathFromRoot(root), .{ .iterate = true }) catch @panic("missing gameplay source");
        defer directory.close(b.graph.io);
        var walker = directory.walk(b.allocator) catch @panic("OOM");
        defer walker.deinit();
        while (walker.next(b.graph.io) catch @panic("cannot walk gameplay source")) |entry| {
            if (entry.kind != .file or (std.mem.startsWith(u8, entry.path, "client/") and !std.mem.eql(u8, root, "src/runtime"))) continue;
            if (!std.mem.endsWith(u8, entry.path, ".c") and !std.mem.endsWith(u8, entry.path, ".h") and !std.mem.endsWith(u8, entry.path, ".zig") and !std.mem.endsWith(u8, entry.path, ".def")) continue;
            paths.append(b.allocator, b.pathJoin(&.{ root, entry.path })) catch @panic("OOM");
        }
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn less(_: void, a: []const u8, c: []const u8) bool {
            return std.mem.lessThan(u8, a, c);
        }
    }.less);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("runtime=zig\x00");
    for (paths.items) |path| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(b.graph.io, b.pathFromRoot(path), b.allocator, .limited(16 << 20)) catch @panic("cannot hash gameplay source");
        hash.update(path);
        hash.update(&.{0});
        hash.update(bytes);
        hash.update(&.{0});
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const identity = b.dupe(&std.fmt.bytesToHex(digest, .lower));
    const generated = b.addWriteFiles();
    const manifest = generated.add("rules.json", b.fmt("{{\"protocol\":1346,\"schema\":\"dk3-snapshot-1346-1\",\"rules\":\"{s}\"}}\n", .{identity}));
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(manifest, .prefix, "share/dk3/rules.json").step);
    return identity;
}
