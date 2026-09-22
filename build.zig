// SPDX-License-Identifier: GPL-2.0-or-later
//! Bundled engine, upstream module foundations and reviewed tools. No Gold or game data input.
const std = @import("std");
const toolchain = @import("build/toolchain.zig");
const manifest = @import("build.zig.zon");
const engine = @import("build/ioq3.zig");
const qvm = @import("build/qvm.zig");
const assets = @import("build/assets.zig");
const game = @import("build/game.zig");
const play = @import("build/play.zig");
const bspc = @import("build/bspc.zig");

pub fn build(b: *std.Build) void {
    toolchain.enforce(manifest.minimum_zig_version, @import("builtin").zig_version);
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu } });
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode") orelse .ReleaseSafe;
    const guard = b.addExecutable(.{ .name = "dkguard", .root_module = b.createModule(.{
        .root_source_file = b.path("src/dkguard/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.installArtifact(guard);
    if (engine.declare(b, target, optimize)) |products| game.declare(b, target, optimize, products);
    qvm.declare(b, optimize);
    const checks = b.step("test", "Run the existing published component checks");
    checks.dependOn(&b.addFmt(.{ .paths = &.{ "build.zig", "build.zig.zon", "build", "src" }, .check = true }).step);
    const info = b.addOptions();
    info.addOption([]const u8, "pinned_zig_version", manifest.minimum_zig_version);
    for ([_][]const u8{ "build/toolchain.zig", "build/stringify_shader.zig", "src/dkguard/args.zig", "src/dkguard/plan.zig", "src/dkguard/host.zig", "src/dkguard/gpu_lock.zig", "src/dkguard/supervise.zig" }) |path| {
        const module = b.createModule(.{ .root_source_file = b.path(path), .target = b.graph.host });
        module.addImport("build_info", info.createModule());
        checks.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = module })).step);
    }
    const host_guard = b.addExecutable(.{ .name = "dkguard", .root_module = b.createModule(.{
        .root_source_file = b.path("src/dkguard/main.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    }) });
    const probe = b.addExecutable(.{ .name = "allocation-probe", .root_module = b.createModule(.{
        .root_source_file = b.path("src/dkguard/alloc_probe.zig"),
        .target = b.graph.host,
    }) });
    const bins = b.addOptions();
    bins.addOptionPath("dkguard_exe", host_guard.getEmittedBin());
    bins.addOptionPath("alloc_probe_exe", probe.getEmittedBin());
    const has_xvfb = if (b.findProgram(&.{"xvfb-run"}, &.{})) |_| true else |_| false;
    bins.addOption(bool, "xvfb_run_installed", has_xvfb);
    const e2e = b.createModule(.{ .root_source_file = b.path("src/dkguard/e2e_test.zig"), .target = b.graph.host });
    e2e.addImport("e2e_bins", bins.createModule());
    const process_checks = b.addRunArtifact(b.addTest(.{ .root_module = e2e }));
    process_checks.has_side_effects = true;
    if (!has_xvfb) process_checks.step.dependOn(&b.addSystemCommand(&.{ "echo", "dkguard: skipping display check because xvfb-run is missing" }).step);
    checks.dependOn(&process_checks.step);
    const python = b.option([]const u8, "python", "Python 3.10+ interpreter") orelse "python3";
    const navigation = bspc.declare(b, optimize);
    const packages = assets.declare(b, host_guard, python, navigation);
    play.declare(b, packages, host_guard);
    const bootstrap =
        \\import os, sys, unittest
        \\os.environ['DKGUARD'] = os.path.abspath(sys.argv.pop(1))
        \\unittest.main(module=None, argv=['unittest', 'discover', '-s', 'dkq3/tools/tests', '-t', 'dkq3/tools'])
    ;
    const archive_checks = b.addSystemCommand(&.{ python, "-B", "-c", bootstrap });
    archive_checks.addArtifactArg(host_guard);
    archive_checks.setCwd(b.path("."));
    archive_checks.setEnvironmentVariable("PYTHONDONTWRITEBYTECODE", "1");
    checks.dependOn(&archive_checks.step);
}
