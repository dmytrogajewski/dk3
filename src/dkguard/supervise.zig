//! Process supervision for dkguard: the command runs as the leader of its own process group, so
//! dkguard can signal the whole job without signalling itself or its parent.
// FRD: specs/frds/FRD-002-dkguard-resource-guard-for-heavy-workloads.md
const std = @import("std");
const plan = @import("plan.zig");
const linux = std.os.linux;
const posix = std.posix;

/// Time the job gets between SIGTERM and SIGKILL once `--timeout` elapses.
pub const kill_grace_ms = 5_000;

/// Signals delivered to dkguard that are passed on to the job's process group.
const forwarded_signals = [_]posix.SIG{ .INT, .TERM, .HUP };

/// Write end of the signal self-pipe. A signal handler can only reach state through a global.
var signal_pipe_write: posix.fd_t = -1;

fn onSignal(sig: posix.SIG) callconv(.c) void {
    const byte: u8 = @truncate(@intFromEnum(sig));
    _ = linux.write(signal_pipe_write, @ptrCast(&byte), 1);
}

/// Routes SIGINT, SIGTERM and SIGHUP into a pipe that `watch` polls and returns its read end.
/// Call it after the GPU lock is held (so Ctrl-C still aborts a wait) and before `start`.
pub fn forwardSignals() error{SignalPipe}!posix.fd_t {
    var fds: [2]i32 = undefined;
    if (linux.errno(linux.pipe2(&fds, .{ .CLOEXEC = true, .NONBLOCK = true })) != .SUCCESS) return error.SignalPipe;
    signal_pipe_write = fds[1];
    const action: posix.Sigaction = .{ .handler = .{ .handler = onSignal }, .mask = posix.sigemptyset(), .flags = 0 };
    for (forwarded_signals) |sig| posix.sigaction(sig, &action, null);
    return fds[0];
}

/// Makes dkguard the child subreaper of the job, so every process the command orphans becomes a
/// child of dkguard that `watch` can wait for. Call it before `start`.
pub fn adoptOrphans() posix.PrctlError!void {
    _ = try posix.prctl(.SET_CHILD_SUBREAPER, .{1});
}

/// Spawns `argv` as the leader of a new process group (pgid = its pid), stdio inherited.
pub fn start(io: std.Io, argv: []const []const u8, environ_map: ?*const std.process.Environ.Map) std.process.SpawnError!std.process.Child {
    return std.process.spawn(io, .{ .argv = argv, .environ_map = environ_map, .pgid = 0 });
}

/// How the job ended.
pub const Outcome = struct {
    term: std.process.Child.Term,
    /// `--timeout` elapsed and the group was terminated by dkguard.
    timed_out: bool,
};

/// Reasons supervision itself can fail.
pub const WatchError = std.process.Child.WaitError || posix.PollError || posix.UnexpectedError || error{PidfdUnavailable};

/// Waits for the job led by `child`: forwards signals arriving on `signal_fd` to its group,
/// enforces `timeout_ms`, kills whatever remains of the group before reaping the leader, and
/// returns only once every process left in the group has died.
pub fn watch(io: std.Io, child: *std.process.Child, signal_fd: posix.fd_t, timeout_ms: ?u64) WatchError!Outcome {
    const pgid = child.id.?;
    const pidfd_rc = linux.pidfd_open(pgid, 0);
    if (linux.errno(pidfd_rc) != .SUCCESS) return error.PidfdUnavailable;
    const pidfd: posix.fd_t = @intCast(pidfd_rc);
    defer _ = linux.close(pidfd);

    const watcher: Watcher = .{ .io = io, .pidfd = pidfd, .signal_fd = signal_fd, .pgid = pgid };
    const deadline = if (timeout_ms) |ms| deadlineIn(io, ms) else null;
    const timed_out = !try watcher.leaderExitsBy(deadline);
    if (timed_out) {
        signalGroup(pgid, .TERM);
        _ = try watcher.leaderExitsBy(deadlineIn(io, kill_grace_ms));
    }
    // The unreaped leader keeps the pgid reserved, so this cannot hit an unrelated group.
    signalGroup(pgid, .KILL);
    const term = try child.wait(io);
    try reapGroup(pgid);
    return .{ .term = term, .timed_out = timed_out };
}

/// Blocks until no child of dkguard is left in the group. A SIGKILL takes effect only when the
/// scheduler next runs the process, so sending it does not end the job. dkguard is the job's
/// subreaper (`adoptOrphans`) and a dying parent hands its children over before it can be reaped,
/// so every process that outlived the leader is waited for here.
fn reapGroup(pgid: posix.pid_t) posix.UnexpectedError!void {
    var info: linux.siginfo_t = undefined;
    while (true) switch (linux.errno(linux.waitid(.PGID, pgid, &info, linux.W.EXITED, null))) {
        .SUCCESS, .INTR => {},
        .CHILD => return,
        else => |err| return posix.unexpectedErrno(err),
    };
}

const Watcher = struct {
    io: std.Io,
    pidfd: posix.fd_t,
    signal_fd: posix.fd_t,
    pgid: posix.pid_t,

    /// Polls until the leader exits (true) or `deadline` passes (false), forwarding signals.
    fn leaderExitsBy(w: Watcher, deadline: ?std.Io.Timestamp) posix.PollError!bool {
        var fds = [_]posix.pollfd{
            .{ .fd = w.pidfd, .events = posix.POLL.IN, .revents = 0 },
            .{ .fd = w.signal_fd, .events = posix.POLL.IN, .revents = 0 },
        };
        while (true) {
            const ready = try posix.poll(&fds, if (deadline) |d| remainingMs(w.io, d) else -1);
            if (fds[0].revents != 0) return true;
            if (fds[1].revents != 0) {
                w.forwardPending();
            } else if (ready == 0) return false;
        }
    }

    fn forwardPending(w: Watcher) void {
        var buf: [16]u8 = undefined;
        const n = linux.read(w.signal_fd, &buf, buf.len);
        if (linux.errno(n) != .SUCCESS) return;
        for (buf[0..n]) |byte| signalGroup(w.pgid, @enumFromInt(byte));
    }
};

fn deadlineIn(io: std.Io, ms: u64) std.Io.Timestamp {
    return std.Io.Clock.awake.now(io).addDuration(.fromMilliseconds(@intCast(ms)));
}

fn remainingMs(io: std.Io, deadline: std.Io.Timestamp) i32 {
    const left = std.Io.Clock.awake.now(io).durationTo(deadline).toMilliseconds();
    return @intCast(std.math.clamp(left, 0, std.math.maxInt(i32)));
}

/// Signals every process in the group; an already empty group is not an error.
fn signalGroup(pgid: posix.pid_t, sig: posix.SIG) void {
    posix.kill(-pgid, sig) catch {};
}

/// Exit status reported when the command cannot be started, following the shell's 126/127.
pub fn spawnFailureStatus(err: std.process.SpawnError) u8 {
    return switch (err) {
        error.FileNotFound, error.NotDir => plan.status.not_found,
        error.AccessDenied, error.PermissionDenied, error.InvalidExe, error.IsDir => plan.status.not_executable,
        else => plan.status.internal,
    };
}

test "spawnFailureStatus follows the shell: 127 not found, 126 not executable, 70 otherwise" {
    try std.testing.expectEqual(plan.status.not_found, spawnFailureStatus(error.FileNotFound));
    try std.testing.expectEqual(plan.status.not_executable, spawnFailureStatus(error.AccessDenied));
    try std.testing.expectEqual(plan.status.not_executable, spawnFailureStatus(error.InvalidExe));
    try std.testing.expectEqual(plan.status.internal, spawnFailureStatus(error.SystemResources));
}
