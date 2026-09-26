// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
pub fn declare(b: *std.Build, _: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    // These operator tools link the host SQLite SDK, like the asset tools. A
    // cross-compiled game must not accidentally link a host library into them.
    const host = b.graph.host.result;
    const target = b.resolveTargetQuery(.{ .cpu_arch = host.cpu.arch, .os_tag = host.os.tag, .abi = host.abi, .glibc_version = if (host.os.tag == .linux and host.abi == .gnu) host.os.version_range.linux.glibc else null });
    const step = b.step("online", "Build the Zig room coordinator and worker tools");
    const coordinator = b.addExecutable(.{ .name = "dk3-coordinator", .root_module = b.createModule(.{ .root_source_file = b.path("src/online/coordinator_main.zig"), .target = target, .optimize = optimize, .link_libc = true }) });
    const sqlite_lib = std.mem.trim(u8, b.run(&.{ "pkg-config", "--variable=libdir", "sqlite3" }), " \r\n");
    const sqlite_include = std.mem.trim(u8, b.run(&.{ "pkg-config", "--variable=includedir", "sqlite3" }), " \r\n");
    coordinator.root_module.addLibraryPath(.{ .cwd_relative = sqlite_lib });
    coordinator.root_module.addSystemIncludePath(.{ .cwd_relative = sqlite_include });
    coordinator.root_module.linkSystemLibrary("sqlite3", .{ .use_pkg_config = .no });
    const install = b.addInstallArtifact(coordinator, .{});
    step.dependOn(&install.step);
    const worker = b.addExecutable(.{ .name = "dk3-worker", .root_module = b.createModule(.{ .root_source_file = b.path("src/online/worker_main.zig"), .target = target, .optimize = optimize, .link_libc = true }) });
    worker.root_module.addIncludePath(b.path("engine/ioquake3/code/thirdparty/curl-8.15.0/include"));
    step.dependOn(&b.addInstallArtifact(worker, .{}).step);
    const client = b.addExecutable(.{ .name = "dk3-online", .root_module = b.createModule(.{ .root_source_file = b.path("src/online/client_main.zig"), .target = target, .optimize = optimize, .link_libc = true }) });
    client.root_module.addIncludePath(b.path("engine/ioquake3/code/thirdparty/curl-8.15.0/include"));
    step.dependOn(&b.addInstallArtifact(client, .{}).step);
    const operator = b.addExecutable(.{ .name = "dk3-operator", .root_module = b.createModule(.{ .root_source_file = b.path("src/online/operator_main.zig"), .target = target, .optimize = optimize, .link_libc = true }) });
    operator.root_module.addIncludePath(b.path("engine/ioquake3/code/thirdparty/curl-8.15.0/include"));
    step.dependOn(&b.addInstallArtifact(operator, .{}).step);
    const tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/online/coordinator.zig"), .target = target, .link_libc = true }) });
    tests.root_module.addLibraryPath(.{ .cwd_relative = sqlite_lib });
    tests.root_module.addSystemIncludePath(.{ .cwd_relative = sqlite_include });
    tests.root_module.linkSystemLibrary("sqlite3", .{ .use_pkg_config = .no });
    const check = b.step("test-online", "Check room authority lifecycle and packet security");
    check.dependOn(&b.addRunArtifact(tests).step);
    const packet_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/network/security.zig"), .target = target }) });
    check.dependOn(&b.addRunArtifact(packet_tests).step);
    const codec_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/network/message.zig"), .target = target, .link_libc = true }) });
    codec_tests.root_module.addIncludePath(b.path("engine/ioquake3/code/qcommon"));
    codec_tests.root_module.addCMacro("STANDALONE", "1");
    codec_tests.root_module.addCSourceFiles(.{ .files = &.{ "src/network/message_reference.c", "engine/ioquake3/code/qcommon/huffman.c" }, .flags = &.{"-fno-sanitize=undefined"} });
    const codec_check = b.step("test-codec", "Compare Zig protocol codec with reviewed C reference");
    codec_check.dependOn(&b.addRunArtifact(codec_tests).step);
    b.getInstallStep().dependOn(step);
}
