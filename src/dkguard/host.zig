//! Host probes for dkguard: executable lookup on PATH and memory-cap mechanism detection.
// FRD: specs/frds/FRD-002-dkguard-resource-guard-for-heavy-workloads.md
const std = @import("std");
const plan = @import("plan.zig");

/// Linux PATH_MAX; bounds every path dkguard builds.
pub const path_capacity = 4096;

/// Returns `<dir>/<name>` for the first absolute `dir` in the `:`-separated `path_list` where
/// `name` is executable, written into `out`. Empty and relative entries are ignored.
pub fn findExecutable(io: std.Io, path_list: []const u8, name: []const u8, out: []u8) ?[]const u8 {
    var dirs = std.mem.splitScalar(u8, path_list, ':');
    while (dirs.next()) |dir| {
        if (!std.mem.startsWith(u8, dir, "/")) continue;
        const candidate = std.fmt.bufPrint(out, "{s}/{s}", .{ dir, name }) catch continue;
        std.Io.Dir.accessAbsolute(io, candidate, .{ .execute = true }) catch continue;
        return candidate;
    }
    return null;
}

/// Picks how `--mem` is enforced. A systemd user scope is used when `systemd-run` is on
/// `path_list` and a probe scope with the same properties runs `true` successfully (it fails in
/// sessions without a user bus); otherwise `prlimit` when it is on `path_list`; otherwise null.
pub fn selectMemMechanism(arena: std.mem.Allocator, io: std.Io, path_list: []const u8, cap_bytes: u64) ?plan.MemMechanism {
    var buf: [path_capacity]u8 = undefined;
    if (findExecutable(io, path_list, "systemd-run", &buf) != null and systemdScopeWorks(arena, io, cap_bytes)) return .systemd_run;
    if (findExecutable(io, path_list, "prlimit", &buf) != null) return .prlimit;
    return null;
}

fn systemdScopeWorks(arena: std.mem.Allocator, io: std.Io, cap_bytes: u64) bool {
    const probe: plan.Wrappers = .{ .mem = .{ .mechanism = .systemd_run, .cap_bytes = cap_bytes } };
    const argv = plan.buildArgv(arena, probe, &.{"true"}) catch return false;
    const result = std.process.run(arena, io, .{ .argv = argv }) catch return false;
    return switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
}

test "findExecutable returns the first executable match and skips empty, relative and non-executable entries" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    (try tmp.dir.createFile(io, "tool", .{ .permissions = .executable_file })).close(io);
    (try tmp.dir.createFile(io, "plain", .{ .permissions = .default_file })).close(io);
    var dir_buf: [path_capacity]u8 = undefined;
    const dir = dir_buf[0..try tmp.dir.realPath(io, &dir_buf)];
    var list_buf: [path_capacity]u8 = undefined;
    const path_list = try std.fmt.bufPrint(&list_buf, "::relative:{s}", .{dir});

    var out: [path_capacity]u8 = undefined;
    const found = findExecutable(io, path_list, "tool", &out) orelse return error.TestExpectedMatch;
    try std.testing.expect(std.mem.startsWith(u8, found, dir) and std.mem.endsWith(u8, found, "/tool"));
    try std.testing.expectEqual(null, findExecutable(io, path_list, "plain", &out));
    try std.testing.expectEqual(null, findExecutable(io, path_list, "missing", &out));
}

test "selectMemMechanism reports no mechanism when neither systemd-run nor prlimit is on PATH" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [path_capacity]u8 = undefined;
    const empty_dir = dir_buf[0..try tmp.dir.realPath(io, &dir_buf)];
    try std.testing.expectEqual(null, selectMemMechanism(arena.allocator(), io, empty_dir, 64));
}

test "selectMemMechanism falls back to prlimit when systemd-run is not on PATH" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    (try tmp.dir.createFile(io, "prlimit", .{ .permissions = .executable_file })).close(io);
    var dir_buf: [path_capacity]u8 = undefined;
    const dir = dir_buf[0..try tmp.dir.realPath(io, &dir_buf)];
    try std.testing.expectEqual(plan.MemMechanism.prlimit, selectMemMechanism(arena.allocator(), io, dir, 64));
}
