//! GPU exclusivity for dkguard (spec R7 "one heavy workload at a time"): an exclusive `flock` on a
//! lock file shared by every GPU job. The kernel releases it when the last descriptor closes, so a
//! crashed job never leaves a stale lock, and the file itself is never deleted (that would reopen
//! the race between two jobs).
// FRD: specs/frds/FRD-002-dkguard-resource-guard-for-heavy-workloads.md
const std = @import("std");
const linux = std.os.linux;

/// Reasons the lock file cannot be prepared.
pub const OpenError = std.Io.File.OpenError || error{InheritFailed};

/// Opens `path`, creating it when absent and never truncating it, with close-on-exec cleared: the
/// command inherits the descriptor, so the lock stays held while any job process that inherited
/// it lives, even if dkguard itself is killed with SIGKILL.
pub fn open(io: std.Io, path: []const u8) OpenError!std.Io.File {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = false });
    errdefer file.close(io);
    const flags = linux.fcntl(file.handle, linux.F.GETFD, 0);
    if (linux.errno(flags) != .SUCCESS) return error.InheritFailed;
    const inheritable = flags & ~@as(usize, linux.FD_CLOEXEC);
    if (linux.errno(linux.fcntl(file.handle, linux.F.SETFD, inheritable)) != .SUCCESS) return error.InheritFailed;
    return file;
}

test "a second descriptor cannot take the lock while the first holds it" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [4096]u8 = undefined;
    const len = try tmp.dir.realPath(io, &buf);
    const path = try std.fmt.bufPrint(buf[len..], "/gpu.lock", .{});
    const full = buf[0 .. len + path.len];

    const first = try open(io, full);
    defer first.close(io);
    try std.testing.expect(try first.tryLock(io, .exclusive));
    const second = try open(io, full);
    defer second.close(io);
    try std.testing.expect(!try second.tryLock(io, .exclusive));
}

test "open clears close-on-exec so the command inherits the lock" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [4096]u8 = undefined;
    const len = try tmp.dir.realPath(io, &buf);
    const path = try std.fmt.bufPrint(buf[len..], "/gpu.lock", .{});

    const file = try open(io, buf[0 .. len + path.len]);
    defer file.close(io);
    try std.testing.expectEqual(@as(usize, 0), linux.fcntl(file.handle, linux.F.GETFD, 0) & linux.FD_CLOEXEC);
}
