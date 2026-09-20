//! `dkguard`: runs one command under the resource-safety rules of specs/dkq3-port/SPEC.md R7.
// FRD: specs/frds/FRD-002-dkguard-resource-guard-for-heavy-workloads.md
const std = @import("std");
const args = @import("args.zig");
const plan = @import("plan.zig");
const supervise = @import("supervise.zig");
const gpu_lock = @import("gpu_lock.zig");
const host = @import("host.zig");

const usage =
    \\usage: dkguard [--gpu [--no-wait]] [--lock-file PATH] [--mem CAP] [--headless]
    \\               [--timeout DURATION] [--] COMMAND [ARG...]
    \\
    \\  --gpu              hold the exclusive GPU lock while COMMAND runs (waits by default)
    \\  --no-wait          with --gpu: exit 75 "gpu busy" instead of waiting
    \\  --lock-file PATH   GPU lock file (default:
++ " " ++ args.default_lock_file ++ ")\n" ++
    \\  --mem CAP          memory cap, e.g. 512M, 8G (K/M/G/T are powers of 1024)
    \\  --headless         SDL_AUDIODRIVER=dummy, LIBGL_ALWAYS_SOFTWARE=1, run under xvfb-run;
    \\                     no WAYLAND_DISPLAY, SDL_VIDEODRIVER=x11, SDL_VIDEO_DRIVER=x11
    \\  --screen WxH       with --headless: the virtual display's size (default: xvfb-run's 640x480)
    \\  --timeout DURATION kill the whole process group after DURATION (500ms, 30s, 5m, 1h; bare = s)
    \\  -h, --help         print this help
    \\
;

/// Message buffer; reports are single short lines plus the usage text.
const stderr_capacity = 1024;

pub fn main(init: std.process.Init) !u8 {
    var stderr_buf: [stderr_capacity]u8 = undefined;
    // Streaming, not positional: stderr may be a regular file the command writes to as well (`> log 2>&1`), and only writes at the
    // shared file offset keep both writers' lines (specs/bugs/BUG-dkguard-report-overwrites-output-in-a-shared-file.md).
    var stderr: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buf);
    const report = &stderr.interface;
    defer report.flush() catch {};

    const arena = init.arena.allocator();
    const raw = try init.minimal.args.toSlice(arena);
    const argv = try arena.alloc([]const u8, raw.len - 1);
    for (argv, raw[1..]) |*dst, src| dst.* = src;

    var diag: args.Diagnostic = .{};
    const config = args.parse(argv, &diag) catch |err| {
        try report.print("dkguard: {s}: '{s}'\n{s}", .{ @errorName(err), diag.arg, usage });
        return plan.status.usage;
    };
    if (config.help) {
        try report.writeAll(usage);
        return plan.status.ok;
    }

    var wrappers: plan.Wrappers = .{};
    if (try prepare(arena, init.io, config, init.environ_map, report, &wrappers)) |code| return code;

    if (config.gpu) if (try holdGpu(init.io, config, report)) |code| return code;

    try plan.writeCaps(report, config, wrappers);
    try report.flush();
    const signal_fd = try supervise.forwardSignals();
    try supervise.adoptOrphans();
    var child = supervise.start(init.io, try plan.buildArgv(arena, wrappers, config.command), init.environ_map) catch |err| {
        try report.print("dkguard: cannot start '{s}': {s}\n", .{ config.command[0], @errorName(err) });
        return finish(report, supervise.spawnFailureStatus(err), "not started");
    };
    try report.print("dkguard: started pid={d} pgid={d}\n", .{ child.id.?, child.id.? });
    try report.flush();

    const outcome = try supervise.watch(init.io, &child, signal_fd, config.timeout_ms);
    if (outcome.timed_out) return finish(report, plan.status.timeout, "timeout");
    return finish(report, plan.exitStatus(outcome.term), switch (outcome.term) {
        .exited => "exited",
        .signal => |sig| try std.fmt.allocPrint(arena, "killed by SIG{s}", .{@tagName(sig)}),
        .stopped, .unknown => "unexpected wait status",
    });
}

/// Resolves the headless display and the memory-cap mechanism into `wrappers` before anything
/// starts. Returns an exit status when a required host tool is missing.
fn prepare(
    arena: std.mem.Allocator,
    io: std.Io,
    config: args.Config,
    env: *std.process.Environ.Map,
    report: *std.Io.Writer,
    wrappers: *plan.Wrappers,
) !?u8 {
    const path_list = env.get("PATH") orelse "";
    if (config.headless) {
        var buf: [host.path_capacity]u8 = undefined;
        const xvfb_run = host.findExecutable(io, path_list, "xvfb-run", &buf) orelse {
            try report.writeAll("dkguard: --headless needs xvfb-run, which is not on PATH; install the xorg-x11-server-Xvfb package\n");
            return try finish(report, plan.status.unavailable, "xvfb-run missing");
        };
        wrappers.xvfb_run = try arena.dupe(u8, xvfb_run);
        wrappers.screen = config.screen;
        try plan.applyHeadlessEnv(env);
    }
    if (config.mem_cap_bytes) |cap| {
        const mechanism = host.selectMemMechanism(arena, io, path_list, cap) orelse {
            try report.writeAll("dkguard: --mem needs systemd-run with a user scope or prlimit on PATH; neither is usable\n");
            return try finish(report, plan.status.unavailable, "memory cap unavailable");
        };
        wrappers.mem = .{ .mechanism = mechanism, .cap_bytes = cap };
    }
    return null;
}

/// Takes the GPU lock before anything starts. Returns an exit status when the command must not
/// run. The descriptor is deliberately never closed: dkguard and the command hold it until exit.
fn holdGpu(io: std.Io, config: args.Config, report: *std.Io.Writer) !?u8 {
    const lock = gpu_lock.open(io, config.lock_file) catch |err| {
        try report.print("dkguard: cannot open gpu lock file {s}: {s}\n", .{ config.lock_file, @errorName(err) });
        return try finish(report, plan.status.unavailable, "gpu lock unavailable");
    };
    if (try lock.tryLock(io, .exclusive)) return null;
    if (!config.wait_for_gpu) {
        try report.print("dkguard: gpu busy: {s} is locked by another job\n", .{config.lock_file});
        return try finish(report, plan.status.gpu_busy, "gpu busy");
    }
    try report.print("dkguard: waiting for gpu lock {s}\n", .{config.lock_file});
    try report.flush();
    try lock.lock(io, .exclusive);
    return null;
}

/// Prints the final report line and returns `code` as dkguard's exit status.
fn finish(report: *std.Io.Writer, code: u8, reason: []const u8) std.Io.Writer.Error!u8 {
    try report.print("dkguard: finished status={d} ({s})\n", .{ code, reason });
    return code;
}
