//! dkguard command-line grammar: flags, value parsers and named parse errors. Does not allocate.
// FRD: specs/frds/FRD-002-dkguard-resource-guard-for-heavy-workloads.md
const std = @import("std");

/// Named reasons a command line is rejected.
pub const Error = error{
    UnknownFlag,
    MissingCommand,
    MissingValue,
    InvalidMemoryCap,
    InvalidTimeout,
    InvalidScreen,
    NoWaitRequiresGpu,
    ScreenRequiresHeadless,
};

/// The virtual display `--screen WxH` asks xvfb-run for. Without the flag a headless run keeps xvfb-run's own default
/// screen, which is 640x480 (`XVFBARGS="-screen 0 640x480x24"`), so every 4:3 run is unchanged.
pub const Screen = struct { width: u32, height: u32 };

/// The colour depth of the virtual screen: 24-bit true colour, xvfb-run's own default.
pub const screen_depth = 24;

/// Parses `<width>x<height>`; both numbers must be positive.
pub fn parseScreen(text: []const u8) error{InvalidScreen}!Screen {
    const cross = std.mem.indexOfScalar(u8, text, 'x') orelse return error.InvalidScreen;
    const width = std.fmt.parseUnsigned(u32, text[0..cross], 10) catch return error.InvalidScreen;
    const height = std.fmt.parseUnsigned(u32, text[cross + 1 ..], 10) catch return error.InvalidScreen;
    if (width == 0 or height == 0) return error.InvalidScreen;
    return .{ .width = width, .height = height };
}

const Unit = struct { suffix: []const u8, factor: u64 };

/// `--mem` suffixes; powers of 1024 like systemd's `MemoryMax=`.
const memory_units = [_]Unit{
    .{ .suffix = "K", .factor = 1 << 10 },
    .{ .suffix = "M", .factor = 1 << 20 },
    .{ .suffix = "G", .factor = 1 << 30 },
    .{ .suffix = "T", .factor = 1 << 40 },
};

/// Parses `<positive integer>[K|M|G|T]` into bytes.
pub fn parseMemoryCap(text: []const u8) error{InvalidMemoryCap}!u64 {
    return scaled(text, &memory_units, 1) catch error.InvalidMemoryCap;
}

/// `--timeout` suffixes in milliseconds. `ms` is listed after `s` so it wins as the last match.
const duration_units = [_]Unit{
    .{ .suffix = "s", .factor = std.time.ms_per_s },
    .{ .suffix = "m", .factor = std.time.ms_per_min },
    .{ .suffix = "h", .factor = std.time.ms_per_hour },
    .{ .suffix = "ms", .factor = 1 },
};

/// Parses `<positive integer>[ms|s|m|h]` into milliseconds; a bare number is seconds.
pub fn parseDuration(text: []const u8) error{InvalidTimeout}!u64 {
    return scaled(text, &duration_units, std.time.ms_per_s) catch error.InvalidTimeout;
}

/// Parses a positive integer followed by one of `units` (or `bare_factor` without a suffix).
fn scaled(text: []const u8, units: []const Unit, bare_factor: u64) error{ Overflow, InvalidCharacter, Zero }!u64 {
    var digits = text;
    var factor = bare_factor;
    for (units) |unit| if (std.mem.cutSuffix(u8, text, unit.suffix)) |rest| {
        digits = rest;
        factor = unit.factor;
    };
    const value = try std.fmt.parseUnsigned(u64, digits, 10);
    if (value == 0) return error.Zero;
    return std.math.mul(u64, value, factor);
}

/// Filled by `parse` with the argument that caused a rejection.
pub const Diagnostic = struct {
    arg: []const u8 = "",
};

/// What dkguard runs and which caps apply. `command` borrows from the parsed argv.
/// Lock file shared by every GPU job on the host unless `--lock-file` overrides it.
pub const default_lock_file = "/tmp/dkguard-gpu.lock";

/// What dkguard runs and which caps apply. `command` and `lock_file` borrow from the parsed argv.
pub const Config = struct {
    /// `--gpu`: hold the exclusive GPU lock while the command runs.
    gpu: bool = false,
    /// Cleared by `--no-wait`: fail fast instead of waiting for the GPU lock.
    wait_for_gpu: bool = true,
    /// `--lock-file`: the lock file serializing GPU jobs.
    lock_file: []const u8 = default_lock_file,
    /// `--mem`: memory cap in bytes.
    mem_cap_bytes: ?u64 = null,
    /// `--headless`: software GL, dummy audio, virtual X display.
    headless: bool = false,
    /// `--screen`: the size of that virtual display, for a run that must render wider than xvfb-run's 640x480 default.
    screen: ?Screen = null,
    /// `--timeout`: wall-clock limit for the whole process group, in milliseconds.
    timeout_ms: ?u64 = null,
    /// `--help` / `-h`: print usage instead of running anything.
    help: bool = false,
    command: []const []const u8 = &.{},
};

const separator = "--";

const Switch = enum { @"--gpu", @"--no-wait", @"--headless", @"--help", @"-h" };
const ValueFlag = enum { @"--mem", @"--timeout", @"--lock-file", @"--screen" };

/// Parses dkguard arguments (without argv[0]).
pub fn parse(argv: []const []const u8, diag: *Diagnostic) Error!Config {
    var config: Config = .{};
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        diag.arg = arg;
        if (std.mem.eql(u8, arg, separator)) {
            config.command = argv[i + 1 ..];
            break;
        }
        if (!std.mem.startsWith(u8, arg, "-")) {
            config.command = argv[i..];
            break;
        }
        if (std.meta.stringToEnum(Switch, arg)) |flag| {
            applySwitch(&config, flag);
            continue;
        }
        const flag = std.meta.stringToEnum(ValueFlag, arg) orelse return error.UnknownFlag;
        i += 1;
        if (i == argv.len) return error.MissingValue;
        diag.arg = argv[i];
        try applyValue(&config, flag, argv[i]);
    }
    return validate(config);
}

fn applySwitch(config: *Config, flag: Switch) void {
    switch (flag) {
        .@"--gpu" => config.gpu = true,
        .@"--no-wait" => config.wait_for_gpu = false,
        .@"--headless" => config.headless = true,
        .@"--help", .@"-h" => config.help = true,
    }
}

fn applyValue(config: *Config, flag: ValueFlag, value: []const u8) Error!void {
    switch (flag) {
        .@"--mem" => config.mem_cap_bytes = try parseMemoryCap(value),
        .@"--timeout" => config.timeout_ms = try parseDuration(value),
        .@"--lock-file" => config.lock_file = value,
        .@"--screen" => config.screen = try parseScreen(value),
    }
}

/// Cross-flag rules checked after every argument was read.
fn validate(config: Config) Error!Config {
    if (config.help) return config;
    if (config.command.len == 0) return error.MissingCommand;
    if (!config.gpu and !config.wait_for_gpu) return error.NoWaitRequiresGpu;
    if (config.screen != null and !config.headless) return error.ScreenRequiresHeadless;
    return config;
}

test "parse rejects an unknown flag with UnknownFlag" {
    var diag: Diagnostic = .{};
    try std.testing.expectError(error.UnknownFlag, parse(&.{ "--frobnicate", "--", "true" }, &diag));
    try std.testing.expectEqualStrings("--frobnicate", diag.arg);
}

test "parse rejects an empty command line and a bare separator with MissingCommand" {
    var diag: Diagnostic = .{};
    try std.testing.expectError(error.MissingCommand, parse(&.{}, &diag));
    try std.testing.expectError(error.MissingCommand, parse(&.{"--"}, &diag));
}

test "parse passes everything after the separator through verbatim" {
    var diag: Diagnostic = .{};
    const config = try parse(&.{ "--", "sleep", "--gpu" }, &diag);
    try std.testing.expectEqual(@as(usize, 2), config.command.len);
    try std.testing.expectEqualStrings("--gpu", config.command[1]);
}

test "parse starts the command at the first positional and leaves its flags unparsed" {
    var diag: Diagnostic = .{};
    const config = try parse(&.{ "sleep", "--gpu" }, &diag);
    try std.testing.expectEqual(@as(usize, 2), config.command.len);
    try std.testing.expect(!config.gpu);
}

test "parse reads the boolean caps" {
    var diag: Diagnostic = .{};
    const config = try parse(&.{ "--gpu", "--no-wait", "--headless", "--", "true" }, &diag);
    try std.testing.expect(config.gpu and !config.wait_for_gpu and config.headless);
}

test "parseMemoryCap converts binary suffixes to bytes" {
    try std.testing.expectEqual(@as(u64, 67_108_864), try parseMemoryCap("64M"));
    try std.testing.expectEqual(@as(u64, 4096), try parseMemoryCap("4K"));
    try std.testing.expectEqual(@as(u64, 2 << 30), try parseMemoryCap("2G"));
    try std.testing.expectEqual(@as(u64, 1 << 40), try parseMemoryCap("1T"));
    try std.testing.expectEqual(@as(u64, 1000), try parseMemoryCap("1000"));
}

test "parseMemoryCap rejects zero, unknown suffixes, bare suffixes and overflow" {
    for ([_][]const u8{ "0", "0M", "64X", "M", "", "-1M", "99999999999T" }) |text| {
        try std.testing.expectError(error.InvalidMemoryCap, parseMemoryCap(text));
    }
}

test "parseDuration converts ms, s, m and h suffixes to milliseconds, bare numbers are seconds" {
    try std.testing.expectEqual(@as(u64, 500), try parseDuration("500ms"));
    try std.testing.expectEqual(@as(u64, 2_000), try parseDuration("2s"));
    try std.testing.expectEqual(@as(u64, 180_000), try parseDuration("3m"));
    try std.testing.expectEqual(@as(u64, 3_600_000), try parseDuration("1h"));
    try std.testing.expectEqual(@as(u64, 7_000), try parseDuration("7"));
}

test "parseDuration rejects zero, negative, unknown suffixes and bare suffixes" {
    for ([_][]const u8{ "0", "0s", "-1", "5x", "ms", "", "1.5s" }) |text| {
        try std.testing.expectError(error.InvalidTimeout, parseDuration(text));
    }
}

test "parse reads value flags and defaults the lock file to the shared path" {
    var diag: Diagnostic = .{};
    const config = try parse(&.{ "--mem", "64M", "--timeout", "2s", "--", "true" }, &diag);
    try std.testing.expectEqual(@as(?u64, 67_108_864), config.mem_cap_bytes);
    try std.testing.expectEqual(@as(?u64, 2_000), config.timeout_ms);
    try std.testing.expectEqualStrings(default_lock_file, config.lock_file);
    const custom = try parse(&.{ "--lock-file", "/tmp/x.lock", "true" }, &diag);
    try std.testing.expectEqualStrings("/tmp/x.lock", custom.lock_file);
}

test "parseScreen reads a WxH size and rejects anything else" {
    try std.testing.expectEqual(Screen{ .width = 1280, .height = 720 }, try parseScreen("1280x720"));
    try std.testing.expectEqual(Screen{ .width = 1920, .height = 1080 }, try parseScreen("1920x1080"));
    for ([_][]const u8{ "", "1280", "1280x", "x720", "0x720", "1280x0", "1280X720", "1280x720x24", "-1x720" }) |text| {
        try std.testing.expectError(error.InvalidScreen, parseScreen(text));
    }
}

test "parse takes --screen only with --headless" {
    var diag: Diagnostic = .{};
    const config = try parse(&.{ "--headless", "--screen", "1280x720", "--", "true" }, &diag);
    try std.testing.expectEqual(Screen{ .width = 1280, .height = 720 }, config.screen.?);
    try std.testing.expectError(error.ScreenRequiresHeadless, parse(&.{ "--screen", "1280x720", "--", "true" }, &diag));
    try std.testing.expectEqual(@as(?Screen, null), (try parse(&.{ "--headless", "--", "true" }, &diag)).screen);
}

test "parse rejects a value flag without a value with MissingValue naming the flag" {
    var diag: Diagnostic = .{};
    for ([_][]const u8{ "--mem", "--timeout", "--lock-file", "--screen" }) |flag| {
        try std.testing.expectError(error.MissingValue, parse(&.{flag}, &diag));
        try std.testing.expectEqualStrings(flag, diag.arg);
    }
}

test "parse names the rejected value for invalid caps" {
    var diag: Diagnostic = .{};
    try std.testing.expectError(error.InvalidMemoryCap, parse(&.{ "--mem", "64X", "true" }, &diag));
    try std.testing.expectEqualStrings("64X", diag.arg);
    try std.testing.expectError(error.InvalidTimeout, parse(&.{ "--timeout", "0", "true" }, &diag));
}

test "parse rejects --no-wait without --gpu with NoWaitRequiresGpu" {
    var diag: Diagnostic = .{};
    try std.testing.expectError(error.NoWaitRequiresGpu, parse(&.{ "--no-wait", "--", "true" }, &diag));
}

test "parse recognizes --help and -h without a command" {
    var diag: Diagnostic = .{};
    try std.testing.expect((try parse(&.{"--help"}, &diag)).help);
    try std.testing.expect((try parse(&.{"-h"}, &diag)).help);
}
