//! Pure planning for dkguard: the wrapped argv, the child environment, the caps report and the
//! mapping from the command's termination to dkguard's exit status. No I/O happens here.
// FRD: specs/frds/FRD-002-dkguard-resource-guard-for-heavy-workloads.md
const std = @import("std");
const args = @import("args.zig");

/// Exit statuses for dkguard's own outcomes: sysexits.h codes, GNU timeout's 124, the shell's
/// 126/127 and 128+signal. Anything else is the command's own exit code.
pub const status = struct {
    pub const ok: u8 = 0;
    pub const usage: u8 = 64;
    pub const unavailable: u8 = 69;
    pub const internal: u8 = 70;
    pub const gpu_busy: u8 = 75;
    pub const timeout: u8 = 124;
    pub const not_executable: u8 = 126;
    pub const not_found: u8 = 127;
    pub const signal_base: u8 = 128;
};

/// Headless engine runs: no audio device, software OpenGL, and only the X display xvfb-run
/// provides. SDL3 (behind sdl2-compat) prefers Wayland when `WAYLAND_DISPLAY` is inherited, which
/// would put the window on the real compositor, so the variable is dropped and both the SDL2
/// (`SDL_VIDEODRIVER`) and SDL3 (`SDL_VIDEO_DRIVER`) driver variables select X11.
pub fn applyHeadlessEnv(env: *std.process.Environ.Map) std.mem.Allocator.Error!void {
    try env.put("SDL_AUDIODRIVER", "dummy");
    try env.put("LIBGL_ALWAYS_SOFTWARE", "1");
    _ = env.swapRemove("WAYLAND_DISPLAY");
    try env.put("SDL_VIDEODRIVER", "x11");
    try env.put("SDL_VIDEO_DRIVER", "x11");
}

/// Maps how the command ended to dkguard's exit status.
pub fn exitStatus(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        .signal => |sig| status.signal_base +| (std.math.cast(u8, @intFromEnum(sig)) orelse return status.internal),
        .stopped, .unknown => status.internal,
    };
}

const off = "off";

/// Writes the one-line `caps` report printed before the command starts.
pub fn writeCaps(w: *std.Io.Writer, config: args.Config, wrappers: Wrappers) std.Io.Writer.Error!void {
    try w.print("dkguard: caps gpu={s} mem=", .{if (config.gpu) config.lock_file else off});
    if (wrappers.mem) |mem| switch (mem.mechanism) {
        .systemd_run => try w.print("systemd-run:MemoryMax={d},MemorySwapMax=0", .{mem.cap_bytes}),
        .prlimit => try w.print("prlimit:--as={d}", .{mem.cap_bytes}),
    } else try w.writeAll(off);
    try w.print(" headless={s}", .{wrappers.xvfb_run orelse off});
    if (wrappers.screen) |screen| try w.print(":{d}x{d}", .{ screen.width, screen.height });
    try w.writeAll(" timeout=");
    if (config.timeout_ms) |ms| try w.print("{d}ms\n", .{ms}) else try w.writeAll(off ++ "\n");
}

/// How a memory cap is enforced on this host.
pub const MemMechanism = enum {
    /// Transient systemd user scope: the kernel OOM-kills the job at `MemoryMax`.
    systemd_run,
    /// `prlimit --as`: address-space limit; allocations beyond it fail.
    prlimit,
};

/// A memory cap and the mechanism selected for it.
pub const MemCap = struct { mechanism: MemMechanism, cap_bytes: u64 };

/// Wrappers placed in front of the command, outermost first: memory cap, then virtual display.
pub const Wrappers = struct {
    mem: ?MemCap = null,
    /// Resolved path of `xvfb-run` when `--headless` applies.
    xvfb_run: ?[]const u8 = null,
    /// `--screen`: the size of the virtual display, passed to the X server behind xvfb-run. Null keeps xvfb-run's own
    /// 640x480 default, so every run that does not ask stays exactly as it was.
    screen: ?args.Screen = null,
};

/// Builds the argv dkguard spawns. Formatted arguments are not freed individually, so pass an arena.
pub fn buildArgv(arena: std.mem.Allocator, wrappers: Wrappers, command: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    if (wrappers.mem) |mem| switch (mem.mechanism) {
        // MemorySwapMax=0: with swap (zram) present, MemoryMax alone only forces swapping.
        // --expand-environment=no: systemd-run would otherwise expand `$VAR` in the command.
        .systemd_run => try argv.appendSlice(arena, &.{
            "systemd-run",                                                    "--user", "--scope",         "--quiet", "--expand-environment=no", "-p",
            try std.fmt.allocPrint(arena, "MemoryMax={d}", .{mem.cap_bytes}), "-p",     "MemorySwapMax=0", "--",
        }),
        .prlimit => try argv.appendSlice(arena, &.{ "prlimit", try std.fmt.allocPrint(arena, "--as={d}", .{mem.cap_bytes}), "--" }),
    };
    if (wrappers.xvfb_run) |path| {
        try argv.appendSlice(arena, &.{ path, "-a" });
        // xvfb-run passes `-s ARGS` on to the X server, so one argument carries the whole `-screen` specification.
        if (wrappers.screen) |screen| try argv.appendSlice(arena, &.{ "-s", try std.fmt.allocPrint(arena, "-screen 0 {d}x{d}x{d}", .{ screen.width, screen.height, args.screen_depth }) });
    }
    try argv.appendSlice(arena, command);
    return argv.toOwnedSlice(arena);
}

test "buildArgv without caps is the command itself" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const argv = try buildArgv(arena.allocator(), .{}, &.{ "sleep", "1" });
    try expectArgv(&.{ "sleep", "1" }, argv);
}

test "buildArgv nests the systemd scope outside xvfb-run outside the command" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const wrappers: Wrappers = .{ .mem = .{ .mechanism = .systemd_run, .cap_bytes = 67_108_864 }, .xvfb_run = "/usr/bin/xvfb-run" };
    const argv = try buildArgv(arena.allocator(), wrappers, &.{"engine"});
    try expectArgv(&.{
        "systemd-run",     "--user", "--scope",           "--quiet", "--expand-environment=no", "-p", "MemoryMax=67108864", "-p",
        "MemorySwapMax=0", "--",     "/usr/bin/xvfb-run", "-a",      "engine",
    }, argv);
}

test "buildArgv gives xvfb-run the screen size --screen asked for" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const wrappers: Wrappers = .{ .xvfb_run = "/usr/bin/xvfb-run", .screen = .{ .width = 1280, .height = 720 } };
    const argv = try buildArgv(arena.allocator(), wrappers, &.{"engine"});
    try expectArgv(&.{ "/usr/bin/xvfb-run", "-a", "-s", "-screen 0 1280x720x24", "engine" }, argv);
}

test "buildArgv falls back to prlimit address-space cap" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const wrappers: Wrappers = .{ .mem = .{ .mechanism = .prlimit, .cap_bytes = 4096 } };
    const argv = try buildArgv(arena.allocator(), wrappers, &.{"probe"});
    try expectArgv(&.{ "prlimit", "--as=4096", "--", "probe" }, argv);
}

test "applyHeadlessEnv selects dummy audio and software GL and keeps the rest" {
    var env: std.process.Environ.Map = .init(std.testing.allocator);
    defer env.deinit();
    try env.put("PATH", "/usr/bin");
    try applyHeadlessEnv(&env);
    try std.testing.expectEqualStrings("dummy", env.get("SDL_AUDIODRIVER").?);
    try std.testing.expectEqualStrings("1", env.get("LIBGL_ALWAYS_SOFTWARE").?);
    try std.testing.expectEqualStrings("/usr/bin", env.get("PATH").?);
}

test "applyHeadlessEnv drops the Wayland display and selects the X11 video driver" {
    var env: std.process.Environ.Map = .init(std.testing.allocator);
    defer env.deinit();
    try env.put("WAYLAND_DISPLAY", "wayland-1");
    try applyHeadlessEnv(&env);
    try std.testing.expect(env.get("WAYLAND_DISPLAY") == null);
    try std.testing.expectEqualStrings("x11", env.get("SDL_VIDEODRIVER").?);
    try std.testing.expectEqualStrings("x11", env.get("SDL_VIDEO_DRIVER").?);
}

test "exitStatus propagates exit codes, maps signals to 128+n and anything else to internal" {
    try std.testing.expectEqual(@as(u8, 7), exitStatus(.{ .exited = 7 }));
    try std.testing.expectEqual(@as(u8, 137), exitStatus(.{ .signal = .KILL }));
    try std.testing.expectEqual(@as(u8, 143), exitStatus(.{ .signal = .TERM }));
    try std.testing.expectEqual(status.internal, exitStatus(.{ .stopped = .STOP }));
    try std.testing.expectEqual(status.internal, exitStatus(.{ .unknown = 0xffff }));
}

test "dkguard's own statuses are distinct" {
    const own = [_]u8{ status.usage, status.unavailable, status.internal, status.gpu_busy, status.timeout, status.not_executable, status.not_found };
    for (own, 0..) |a, i| for (own[i + 1 ..]) |b| try std.testing.expect(a != b);
}

test "writeCaps reports every cap as off when none applies" {
    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try writeCaps(&writer, .{ .command = &.{"true"} }, .{});
    try std.testing.expectEqualStrings("dkguard: caps gpu=off mem=off headless=off timeout=off\n", writer.buffered());
}

test "writeCaps names the lock file, memory mechanism, display wrapper and timeout" {
    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    const config: args.Config = .{ .gpu = true, .lock_file = "/l.lock", .timeout_ms = 2000, .command = &.{"true"} };
    const wrappers: Wrappers = .{ .mem = .{ .mechanism = .systemd_run, .cap_bytes = 64 }, .xvfb_run = "/x/xvfb-run" };
    try writeCaps(&writer, config, wrappers);
    try std.testing.expectEqualStrings("dkguard: caps gpu=/l.lock mem=systemd-run:MemoryMax=64,MemorySwapMax=0 " ++
        "headless=/x/xvfb-run timeout=2000ms\n", writer.buffered());
    writer = .fixed(&buf);
    try writeCaps(&writer, config, .{ .mem = .{ .mechanism = .prlimit, .cap_bytes = 64 } });
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), " mem=prlimit:--as=64 headless=off ") != null);
}

fn expectArgv(expected: []const []const u8, actual: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| try std.testing.expectEqualStrings(e, a);
}
