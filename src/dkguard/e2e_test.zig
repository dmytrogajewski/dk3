//! Black-box e2e tests for `dkguard`: run the built binary as a user would and observe exit
//! statuses, stderr reports, lock files and /proc. Every process a test starts is killed and
//! reaped by that test; every file it creates lives in a `testing.tmpDir`.
// FRD: specs/frds/FRD-002-dkguard-resource-guard-for-heavy-workloads.md
const std = @import("std");
const bins = @import("e2e_bins");

const gpa = std.testing.allocator;
const io = std.testing.io;

const status_usage = 64;
const status_not_found = 127;

/// Safety net only: a hung dkguard fails its test instead of hanging `zig build test`.
const run_timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromSeconds(60), .clock = .awake } };

/// Collected output of one dkguard run whose command leaves no process behind.
const Outcome = struct {
    result: std.process.RunResult,

    fn deinit(o: Outcome) void {
        gpa.free(o.result.stdout);
        gpa.free(o.result.stderr);
    }

    fn exitCode(o: Outcome) ?u8 {
        return switch (o.result.term) {
            .exited => |code| code,
            else => null,
        };
    }

    fn expectStderr(o: Outcome, needle: []const u8) !void {
        if (std.mem.indexOf(u8, o.result.stderr, needle) == null) {
            std.debug.print("stderr lacks '{s}':\n{s}\n", .{ needle, o.result.stderr });
            return error.TestExpectedStderr;
        }
    }
};

/// Runs `dkguard <tail>` to completion with stdin ignored and stdout/stderr captured.
fn runGuard(tail: []const []const u8, environ_map: ?*const std.process.Environ.Map) !Outcome {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, bins.dkguard_exe);
    try argv.appendSlice(gpa, tail);
    return .{ .result = try std.process.run(gpa, io, .{ .argv = argv.items, .environ_map = environ_map, .timeout = run_timeout }) };
}

/// Returns the value following `key` up to the next space or newline.
fn field(text: []const u8, key: []const u8) ![]const u8 {
    const start = (std.mem.indexOf(u8, text, key) orelse return error.TestMissingField) + key.len;
    const end = std.mem.indexOfAnyPos(u8, text, start, " \n") orelse text.len;
    return text[start..end];
}

const status_gpu_busy = 75;
const started_prefix = "dkguard: started pid=";
const finished_prefix = "dkguard: finished status=";
/// Bounds one stderr report line and every path the tests build.
const line_capacity = 4096;

/// dkguard's stderr (report lines interleaved with the command's own lines) read line by line,
/// remembering the pgid from `started` and whether `finished` was seen.
const Report = struct {
    in: *std.Io.Reader,
    pgid: ?std.posix.pid_t = null,
    finished: bool = false,

    /// Reads lines until one starts with `prefix` (the readiness signal) and returns it.
    fn waitForLine(r: *Report, prefix: []const u8) ![]const u8 {
        while (try r.in.takeDelimiter('\n')) |line| {
            if (std.mem.startsWith(u8, line, started_prefix)) r.pgid = try std.fmt.parseInt(std.posix.pid_t, try field(line, " pgid="), 10);
            if (std.mem.startsWith(u8, line, finished_prefix)) r.finished = true;
            if (std.mem.startsWith(u8, line, prefix)) return line;
        }
        std.debug.print("dkguard stderr ended before a line starting with '{s}'\n", .{prefix});
        return error.TestExpectedLine;
    }
};

/// A dkguard run observed line by line. Initialise in place (`start`), because the reader points
/// into `buf`. `stop` kills whatever is left of the job and reaps dkguard; it is safe after exit.
const Job = struct {
    child: std.process.Child,
    reader: std.Io.File.Reader,
    buf: [line_capacity]u8,
    report: Report,

    fn start(job: *Job, tail: []const []const u8) !void {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.append(gpa, bins.dkguard_exe);
        try argv.appendSlice(gpa, tail);
        job.child = try std.process.spawn(io, .{ .argv = argv.items, .stdin = .ignore, .stdout = .ignore, .stderr = .pipe });
        job.reader = job.child.stderr.?.readerStreaming(io, &job.buf);
        job.report = .{ .in = &job.reader.interface };
    }

    fn stop(job: *Job) void {
        const pid = job.child.id orelse return;
        if (job.report.pgid) |pgid| if (!job.report.finished) std.posix.kill(-pgid, .KILL) catch {};
        std.posix.kill(pid, .KILL) catch {};
        _ = job.child.wait(io) catch {};
    }
};

/// Absolute path of `name` inside `tmp`, written into `out`.
fn tmpPath(tmp: *std.testing.TmpDir, name: []const u8, out: []u8) ![]const u8 {
    var dir_buf: [line_capacity]u8 = undefined;
    const dir = dir_buf[0..try tmp.dir.realPath(io, &dir_buf)];
    return std.fmt.bufPrint(out, "{s}/{s}", .{ dir, name });
}

const shared_log_name = "shared.log";
/// The lines dkguard and its command must both leave whole in one regular file: the start of dkguard's caps line, its started and
/// finished reports, and the command's stdout and stderr lines.
const shared_log_lines = [_][]const u8{ "dkguard: caps gpu=off ", started_prefix, "dkguard: finished status=0 (exited)\n", "command-stdout\n", "command-stderr\n" };

test "dkguard's report lines and the command's output all survive in one regular file both write to" {
    // specs/bugs/BUG-dkguard-report-overwrites-output-in-a-shared-file.md: `dkguard ... > log 2>&1`, the way run logs are kept
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [line_capacity]u8 = undefined;
    const log = try tmpPath(&tmp, shared_log_name, &path_buf);
    var script_buf: [2 * line_capacity]u8 = undefined;
    const script = try std.fmt.bufPrint(&script_buf, "exec '{s}' -- sh -c 'echo command-stdout; echo command-stderr >&2' > '{s}' 2>&1", .{ bins.dkguard_exe, log });
    const result = try std.process.run(gpa, io, .{ .argv = &.{ "sh", "-c", script }, .timeout = run_timeout });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    try expectExited(result.term, 0);
    const text = try tmp.dir.readFileAlloc(io, shared_log_name, gpa, .limited(line_capacity));
    defer gpa.free(text);
    for (shared_log_lines) |line| {
        if (std.mem.indexOf(u8, text, line) == null) {
            std.debug.print("{s} lacks '{s}':\n{s}\n", .{ shared_log_name, line, text });
            return error.TestExpectedLine;
        }
    }
}

test "a second --gpu --no-wait job exits 75 gpu busy while the first holds the lock" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [line_capacity]u8 = undefined;
    const lock = try tmpPath(&tmp, "gpu.lock", &path_buf);

    var first: Job = undefined;
    try first.start(&.{ "--gpu", "--no-wait", "--lock-file", lock, "--", "sleep", job_sleep_s });
    defer first.stop();
    _ = try first.report.waitForLine(started_prefix);

    const second = try runGuard(&.{ "--gpu", "--no-wait", "--lock-file", lock, "--", "sleep", "1" }, null);
    defer second.deinit();
    try std.testing.expectEqual(@as(?u8, status_gpu_busy), second.exitCode());
    try second.expectStderr("gpu busy");
    try second.expectStderr(lock);
}

test "--gpu waits while another holder has the lock and runs the command once it is released" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [line_capacity]u8 = undefined;
    const lock = try tmpPath(&tmp, "gpu.lock", &path_buf);
    var holder = try tmp.dir.createFile(io, "gpu.lock", .{ .lock = .exclusive, .truncate = false });
    var held = true;
    defer if (held) holder.close(io);

    var job: Job = undefined;
    try job.start(&.{ "--gpu", "--lock-file", lock, "--", "true" });
    defer job.stop();
    _ = try job.report.waitForLine("dkguard: waiting for gpu lock");
    holder.close(io);
    held = false;
    _ = try job.report.waitForLine(finished_prefix ++ "0 ");
}

const status_timeout = 124;
const status_sigterm = 128 + 15;
const grandchild_prefix = "grandchild=";
/// Length of the sleeps jobs run; it only bounds how long a regression can stall a test.
const job_sleep_s = "30";

fn expectExited(term: std.process.Child.Term, code: u8) !void {
    try std.testing.expectEqual(std.process.Child.Term{ .exited = code }, term);
}

/// Passes when `pid` no longer runs: /proc has no entry, or the entry is a zombie (Z) or dead (X)
/// process that only waits to be reaped by its new parent.
fn expectGone(pid: std.posix.pid_t) !void {
    var path_buf: [64]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/proc/{d}/stat", .{pid});
    var stat_buf: [512]u8 = undefined;
    const stat = std.Io.Dir.cwd().readFile(io, path, &stat_buf) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    const state = stat[(std.mem.lastIndexOfScalar(u8, stat, ')') orelse return error.TestBadProcStat) + 2];
    if (state == 'Z' or state == 'X') return;
    std.debug.print("process {d} is still running: {s}\n", .{ pid, stat });
    return error.TestOrphanLeft;
}

/// Reads the `grandchild=<pid>` line a test command prints to stderr, and dkguard's `started` line
/// too: the command shares the pipe and may print before dkguard reports the pgid.
fn waitForGrandchild(report: *Report) !std.posix.pid_t {
    const line = try report.waitForLine(grandchild_prefix);
    const grandchild = try std.fmt.parseInt(std.posix.pid_t, line[grandchild_prefix.len..], 10);
    if (report.pgid == null) _ = try report.waitForLine(started_prefix);
    return grandchild;
}

test "waitForGrandchild learns the job's pgid even when the command's line precedes dkguard's started line" {
    var in: std.Io.Reader = .fixed(grandchild_prefix ++ "42\n" ++ started_prefix ++ "7 pgid=7\n");
    var report: Report = .{ .in = &in };
    try std.testing.expectEqual(@as(std.posix.pid_t, 42), try waitForGrandchild(&report));
    try std.testing.expectEqual(@as(?std.posix.pid_t, 7), report.pgid);
}

test "--timeout kills the whole process group, exits 124 and leaves no orphan in /proc" {
    var job: Job = undefined;
    try job.start(&.{ "--timeout", "2s", "--", "sh", "-c", "sleep " ++ job_sleep_s ++ " & echo " ++ grandchild_prefix ++ "$! >&2; wait" });
    defer job.stop();
    const grandchild = try waitForGrandchild(&job.report);
    errdefer std.posix.kill(grandchild, .KILL) catch {};
    const leader = job.report.pgid.?;

    _ = try job.report.waitForLine(finished_prefix ++ "124 ");
    try expectExited(try job.child.wait(io), status_timeout);
    try expectGone(grandchild);
    try expectGone(leader);
}

test "processes the command leaves in its group are killed when the command exits" {
    var job: Job = undefined;
    try job.start(&.{ "--", "sh", "-c", "sleep " ++ job_sleep_s ++ " & echo " ++ grandchild_prefix ++ "$! >&2" });
    defer job.stop();
    const grandchild = try waitForGrandchild(&job.report);
    errdefer std.posix.kill(grandchild, .KILL) catch {};

    _ = try job.report.waitForLine(finished_prefix ++ "0 ");
    try expectExited(try job.child.wait(io), 0);
    try expectGone(grandchild);
}

const hog_ready = "hog-running";

/// Highest CPU this test process may run on, formatted for `taskset -c`.
fn lastAllowedCpu(out: []u8) ![]const u8 {
    const set = try std.posix.sched_getaffinity(0);
    const word_bits = @bitSizeOf(usize);
    var cpu = set.len * word_bits;
    while (cpu > 0) {
        cpu -= 1;
        if (set[cpu / word_bits] & (@as(usize, 1) << @intCast(cpu % word_bits)) != 0) return std.fmt.bufPrint(out, "{d}", .{cpu});
    }
    return error.TestNoAllowedCpu;
}

/// Starts a busy loop pinned to `cpu`, outside any dkguard group, and returns once it runs there.
/// `--pdeathsig KILL` ends it with the test process even if the test aborts before `killAndWait`.
fn startHog(cpu: []const u8) !std.process.Child {
    var hog = try std.process.spawn(io, .{
        .argv = &.{ "setpriv", "--pdeathsig", "KILL", "taskset", "-c", cpu, "sh", "-c", "echo " ++ hog_ready ++ "; while :; do :; done" },
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .ignore,
    });
    errdefer killAndWait(&hog);
    var buf: [64]u8 = undefined;
    var reader = hog.stdout.?.readerStreaming(io, &buf);
    const line = try reader.interface.takeDelimiter('\n') orelse return error.TestHogNotRunning;
    try std.testing.expectEqualStrings(hog_ready, line);
    return hog;
}

fn killAndWait(child: *std.process.Child) void {
    std.posix.kill(child.id orelse return, .KILL) catch {};
    _ = child.wait(io) catch {};
}

test "dkguard reports finished only after every process left in the command's group has died" {
    var cpu_buf: [16]u8 = undefined;
    const cpu = try lastAllowedCpu(&cpu_buf);
    var job: Job = undefined;
    // The background process moves itself to SCHED_IDLE on `cpu` before it reports. Once the hog
    // occupies that CPU, a SIGKILL takes effect only when the scheduler next runs the process.
    try job.start(&.{ "--", "sh", "-c", "chrt --idle 0 taskset -c \"$0\" sh -c 'echo " ++ grandchild_prefix ++ "$$ >&2; exec sleep " ++ job_sleep_s ++ "' & wait", cpu });
    defer job.stop();
    const grandchild = try waitForGrandchild(&job.report);
    errdefer std.posix.kill(grandchild, .KILL) catch {};
    var hog = try startHog(cpu);
    defer killAndWait(&hog);

    try std.posix.kill(job.report.pgid.?, .TERM);
    _ = try job.report.waitForLine(finished_prefix ++ "143 ");
    try expectExited(try job.child.wait(io), status_sigterm);
    try expectGone(grandchild);
}

test "SIGTERM to dkguard is forwarded to the command's process group" {
    var job: Job = undefined;
    try job.start(&.{ "--", "sleep", job_sleep_s });
    defer job.stop();
    _ = try job.report.waitForLine(started_prefix);
    const leader = job.report.pgid.?;

    try std.posix.kill(job.child.id.?, .TERM);
    _ = try job.report.waitForLine(finished_prefix ++ "143 (killed by SIGTERM)");
    try expectExited(try job.child.wait(io), status_sigterm);
    try expectGone(leader);
}

const status_sigkill = 128 + 9;
/// R7: the cap and the probes stay far below 1 GB.
const mem_cap = "64M";
const mem_cap_bytes = "67108864";
const probe_over_cap_mib = "256";
const probe_under_cap_mib = "8";
const probe_success = "alloc-probe: touched";

fn expectNoProbeSuccess(out: Outcome) !void {
    if (std.mem.indexOf(u8, out.result.stdout, probe_success) != null) {
        std.debug.print("probe completed despite the cap:\n{s}\n{s}\n", .{ out.result.stdout, out.result.stderr });
        return error.TestCapNotEnforced;
    }
}

test "--mem 64M kills an allocating probe in a systemd scope while the test process survives" {
    const out = try runGuard(&.{ "--mem", mem_cap, "--", bins.alloc_probe_exe, probe_over_cap_mib }, null);
    defer out.deinit();
    if (std.mem.indexOf(u8, out.result.stderr, "mem=prlimit:") != null) {
        std.debug.print("skipped: no systemd user scope in this session, dkguard selected prlimit\n", .{});
        return error.SkipZigTest;
    }
    try out.expectStderr("mem=systemd-run:MemoryMax=" ++ mem_cap_bytes ++ ",MemorySwapMax=0 ");
    try expectNoProbeSuccess(out);
    try std.testing.expectEqual(@as(?u8, status_sigkill), out.exitCode());
    try out.expectStderr("killed by SIGKILL");
}

test "--mem leaves a probe that fits the cap alone" {
    const out = try runGuard(&.{ "--mem", mem_cap, "--", bins.alloc_probe_exe, probe_under_cap_mib }, null);
    defer out.deinit();
    try std.testing.expectEqual(@as(?u8, 0), out.exitCode());
    try std.testing.expect(std.mem.indexOf(u8, out.result.stdout, probe_success ++ " " ++ probe_under_cap_mib ++ " MiB") != null);
}

test "--mem falls back to prlimit when the session has no user bus, and the probe cannot finish" {
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    _ = env.swapRemove("XDG_RUNTIME_DIR");
    try env.put("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent/dkguard-e2e-no-user-bus");

    const out = try runGuard(&.{ "--mem", mem_cap, "--", bins.alloc_probe_exe, probe_over_cap_mib }, &env);
    defer out.deinit();
    try out.expectStderr("mem=prlimit:--as=" ++ mem_cap_bytes ++ " ");
    try expectNoProbeSuccess(out);
    try std.testing.expect(out.exitCode() != @as(?u8, 0));
}

const status_unavailable = 69;
const xvfb_package = "xorg-x11-server-Xvfb";

/// Stands in for xvfb-run: reports how it was called and the headless environment, then runs the
/// command. It keeps the wrapping test independent of whether the real package is installed.
const xvfb_shim =
    \\#!/bin/sh
    \\echo "shim-xvfb-run args=$* SDL_AUDIODRIVER=$SDL_AUDIODRIVER LIBGL_ALWAYS_SOFTWARE=$LIBGL_ALWAYS_SOFTWARE WAYLAND_DISPLAY=$WAYLAND_DISPLAY SDL_VIDEODRIVER=$SDL_VIDEODRIVER SDL_VIDEO_DRIVER=$SDL_VIDEO_DRIVER"
    \\shift
    \\exec "$@"
    \\
;

test "--headless fails with 69 naming xorg-x11-server-Xvfb when xvfb-run is not on PATH" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var dir_buf: [line_capacity]u8 = undefined;
    const empty_dir = dir_buf[0..try tmp.dir.realPath(io, &dir_buf)];
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    try env.put("PATH", empty_dir);

    const out = try runGuard(&.{ "--headless", "--", "true" }, &env);
    defer out.deinit();
    try std.testing.expectEqual(@as(?u8, status_unavailable), out.exitCode());
    try out.expectStderr("xvfb-run");
    try out.expectStderr(xvfb_package);
    try std.testing.expect(std.mem.indexOf(u8, out.result.stderr, started_prefix) == null);
}

test "--headless runs the command under xvfb-run -a with dummy audio, software GL and no Wayland display" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "xvfb-run", .data = xvfb_shim, .flags = .{ .permissions = .executable_file } });
    var dir_buf: [line_capacity]u8 = undefined;
    const shim_dir = dir_buf[0..try tmp.dir.realPath(io, &dir_buf)];
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    var path_buf: [line_capacity]u8 = undefined;
    try env.put("PATH", try std.fmt.bufPrint(&path_buf, "{s}:{s}", .{ shim_dir, env.get("PATH") orelse "/usr/bin:/bin" }));
    try env.put("WAYLAND_DISPLAY", "wayland-e2e");

    const out = try runGuard(&.{ "--headless", "--", "sh", "-c", "echo inner-ran" }, &env);
    defer out.deinit();
    try std.testing.expectEqual(@as(?u8, 0), out.exitCode());
    try std.testing.expect(std.mem.indexOf(u8, out.result.stdout, "shim-xvfb-run args=-a sh -c echo inner-ran " ++
        "SDL_AUDIODRIVER=dummy LIBGL_ALWAYS_SOFTWARE=1 WAYLAND_DISPLAY= SDL_VIDEODRIVER=x11 SDL_VIDEO_DRIVER=x11\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.result.stdout, "inner-ran\n") != null);
    try out.expectStderr("headless=");
    try out.expectStderr("/xvfb-run timeout=off");
}

test "--headless gives the command a virtual X display when xorg-x11-server-Xvfb is installed" {
    // The build graph detects xvfb-run and prints the skip reason (build/tests.zig).
    if (!bins.xvfb_run_installed) return error.SkipZigTest;
    const out = try runGuard(&.{ "--headless", "--timeout", "60s", "--", "sh", "-c", "test -n \"$DISPLAY\" && echo display=$DISPLAY" }, null);
    defer out.deinit();
    try std.testing.expectEqual(@as(?u8, 0), out.exitCode());
    try std.testing.expect(std.mem.indexOf(u8, out.result.stdout, "display=:") != null);
}

test "dkguard propagates the command's exit code" {
    const out = try runGuard(&.{ "--", "sh", "-c", "exit 7" }, null);
    defer out.deinit();
    try std.testing.expectEqual(@as(?u8, 7), out.exitCode());
}

test "dkguard rejects an unknown flag with status 64 naming the flag" {
    const out = try runGuard(&.{ "--frobnicate", "--", "true" }, null);
    defer out.deinit();
    try std.testing.expectEqual(@as(?u8, status_usage), out.exitCode());
    try out.expectStderr("UnknownFlag: '--frobnicate'");
}

test "dkguard exits 127 naming a command that is not on PATH" {
    const out = try runGuard(&.{ "--", "dkguard-e2e-no-such-command" }, null);
    defer out.deinit();
    try std.testing.expectEqual(@as(?u8, status_not_found), out.exitCode());
    try out.expectStderr("dkguard-e2e-no-such-command");
}

test "dkguard reports caps and runs the command as the leader of a new process group" {
    const out = try runGuard(&.{ "--", "sh", "-c", "cut -d' ' -f5 /proc/$$/stat" }, null);
    defer out.deinit();
    try std.testing.expectEqual(@as(?u8, 0), out.exitCode());
    try out.expectStderr("dkguard: caps gpu=off mem=off headless=off timeout=off\n");
    const pid = try field(out.result.stderr, "dkguard: started pid=");
    try std.testing.expectEqualStrings(pid, try field(out.result.stderr, " pgid="));
    try std.testing.expectEqualStrings(pid, std.mem.trim(u8, out.result.stdout, "\n"));
    try out.expectStderr("dkguard: finished status=0 ");
}
