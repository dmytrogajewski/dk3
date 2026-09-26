// SPDX-License-Identifier: GPL-2.0-or-later
//! Build bundled engine sources directly; generated files are limited to GLSL strings.
const std = @import("std");
const config = @import("ioq3_config.zig");
const stringify_shader = @import("stringify_shader.zig");

/// The upstream source tree is part of this repository, never a sibling checkout.
pub const source_root = "engine/ioquake3";
/// Declare engine products without introducing game-data or reference dependencies.
pub fn declare(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) bool {
    const all = b.step("engine", "Build the bundled client, server, renderers (gameplay modules are built by the Zig runtime)");
    const server_step = b.step("engine-server", "Build the bundled dedicated server");
    b.getInstallStep().dependOn(all);
    const settings = options(b);
    if (!config.inTargetMatrix(target.result.cpu.arch, target.result.os.tag, target.result.abi)) {
        const failure = &b.addFail("dk3 supports x86_64-linux-gnu; select -Dtarget=x86_64-linux-gnu").step;
        all.dependOn(failure);
        server_step.dependOn(failure);
        return false;
    }
    const conflicts = config.optionConflicts(b.allocator, settings) catch @panic("OOM");
    if (conflicts.len != 0) {
        all.dependOn(&b.addFail(std.mem.join(b.allocator, "\n", conflicts) catch @panic("OOM")).step);
    }
    for ([_]config.Product{ .client, .server, .renderer_opengl1, .renderer_opengl2 }) |product| {
        const artifact = addProduct(b, target, optimize, settings, product);
        const installed = switch (product) {
            .client, .server => &b.addInstallArtifact(artifact, .{}).step,
            else => &b.addInstallFileWithDir(artifact.getEmittedBin(), .bin, installPath(product)).step,
        };
        all.dependOn(installed);
        if (product == .server) server_step.dependOn(installed);
    }
    return true;
}

fn options(b: *std.Build) config.Config {
    return .{
        .build_standalone = true,
        .use_voip = b.option(bool, "USE_VOIP", "Enable voice support") orelse true,
        .use_http = b.option(bool, "USE_HTTP", "Enable HTTP downloads") orelse true,
        .use_codec_vorbis = b.option(bool, "USE_CODEC_VORBIS", "Enable Vorbis decoding") orelse true,
        .use_codec_opus = b.option(bool, "USE_CODEC_OPUS", "Enable Opus decoding") orelse true,
        .use_mumble = b.option(bool, "USE_MUMBLE", "Enable Mumble support") orelse true,
        .use_openal = b.option(bool, "USE_OPENAL", "Enable dynamically loaded OpenAL") orelse true,
        .use_freetype = b.option(bool, "USE_FREETYPE", "Enable FreeType font support") orelse false,
        .product_version = "dk3-development",
        .product_date = "",
    };
}

fn name(product: config.Product) []const u8 {
    return switch (product) {
        .client => "dk3",
        .server => "dk3ded",
        else => @tagName(product),
    };
}

fn installPath(product: config.Product) []const u8 {
    return switch (product) {
        .client => "dk3",
        .server => "dk3ded",
        .renderer_opengl1 => "renderer_opengl1.so",
        .renderer_opengl2 => "renderer_opengl2.so",
        .qagame => "baseq3/qagame.so",
        .cgame => "baseq3/cgame.so",
        .ui => "baseq3/ui.so",
    };
}

pub fn addProduct(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, settings: config.Config, product: config.Product) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    @import("header_inputs.zig").track(b, module, &.{source_root});
    const generated = b.addWriteFiles();
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    const root = b.build_root.join(b.allocator, &.{source_root}) catch @panic("OOM");
    for (config.productSources(b.allocator, product, settings) catch @panic("OOM")) |path| {
        // Protocol messages are owned by the Zig network module. Keep the
        // licensed upstream C codec as a differential test reference only.
        if ((product == .client or product == .server) and std.mem.eql(u8, path, "code/qcommon/msg.c")) continue;
        if ((seen.getOrPut(b.allocator, path) catch @panic("OOM")).found_existing) {
            module.addCSourceFile(.{ .file = failSource(b, b.fmt("duplicate {t} source: {s}", .{ product, path })), .flags = &.{} });
            continue;
        }
        const absolute = b.pathJoin(&.{ root, path });
        std.Io.Dir.cwd().access(b.graph.io, absolute, .{}) catch |err| {
            module.addCSourceFile(.{ .file = failSource(b, b.fmt("missing {t} source {s}: {t}", .{ product, path, err })), .flags = &.{} });
            continue;
        };
        const file = if (config.isShader(path)) blk: {
            const bytes = std.Io.Dir.cwd().readFileAlloc(b.graph.io, absolute, b.allocator, .limited(1 << 20)) catch |err|
                break :blk failSource(b, b.fmt("cannot read GLSL {s}: {t}", .{ path, err }));
            var out: std.Io.Writer.Allocating = .init(b.allocator);
            const stem = std.fs.path.stem(path);
            stringify_shader.stringify(&out.writer, stem, bytes) catch @panic("OOM");
            break :blk generated.add(b.fmt("{s}.c", .{stem}), out.written());
        } else b.path(b.pathJoin(&.{ source_root, path }));
        module.addCSourceFile(.{ .file = file, .flags = config.sourceFlags(product, path) });
    }
    if (product == .client) {
        module.addIncludePath(b.path("engine/ioquake3/code/qcommon"));
        module.addCSourceFile(.{ .file = b.path("engine/ioquake3/code/qcommon/dk_save_format.c"), .flags = config.sourceFlags(product, "engine/ioquake3/code/qcommon/dk_save_format.c") });
    }
    for (config.productIncludeDirs(b.allocator, product, settings) catch @panic("OOM")) |directory|
        module.addIncludePath(b.path(b.pathJoin(&.{ source_root, directory })));
    for (config.productMacros(b.allocator, product, settings) catch @panic("OOM")) |macro|
        module.addCMacro(macro.name, macro.value);
    for (config.productSystemLibraries(b.allocator, product, settings) catch @panic("OOM")) |library| {
        const pkg_config = b.graph.environ_map.get("PKG_CONFIG") orelse "pkg-config";
        var paths: [2][]const u8 = undefined;
        var available = true;
        for ([_][]const u8{ "includedir", "libdir" }, &paths) |variable, *path| {
            var exit_code: u8 = undefined;
            const output = b.runAllowFail(&.{ pkg_config, b.fmt("--variable={s}", .{variable}), library.package }, &exit_code, .ignore) catch |err| {
                module.addCSourceFile(.{ .file = failSource(b, b.fmt("pkg-config package {s}: {t}; install its development package", .{ library.package, err })), .flags = &.{} });
                available = false;
                break;
            };
            path.* = config.pkgConfigDirectory(output) orelse {
                module.addCSourceFile(.{ .file = failSource(b, b.fmt("pkg-config package {s} has no {s}; install its development package", .{ library.package, variable })), .flags = &.{} });
                available = false;
                break;
            };
        }
        if (!available) continue;
        module.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ paths[0], library.include_subdir }) });
        module.addLibraryPath(.{ .cwd_relative = paths[1] });
        module.linkSystemLibrary(library.link_name, .{ .use_pkg_config = .no });
    }
    for ([_][]const u8{ "dl", "m" }) |library| module.linkSystemLibrary(library, .{});
    const artifact = switch (product) {
        .client, .server => b.addExecutable(.{ .name = name(product), .root_module = module }),
        else => b.addLibrary(.{ .name = name(product), .linkage = .dynamic, .root_module = module }),
    };
    if (product == .client or product == .server) {
        const network_module = b.createModule(.{ .root_source_file = b.path("src/network_engine.zig"), .target = target, .optimize = optimize, .link_libc = true });
        network_module.addIncludePath(b.path("engine/ioquake3/code/qcommon"));
        network_module.addIncludePath(b.path("engine/ioquake3/code/thirdparty/curl-8.15.0/include"));
        @import("header_inputs.zig").track(b, network_module, &.{source_root});
        const network = b.addLibrary(.{ .name = "dk3-network", .linkage = .static, .root_module = network_module });
        artifact.root_module.linkLibrary(network);
    }
    artifact.lto = .full;
    if (product == .client) artifact.linker_allow_shlib_undefined = true;
    return artifact;
}

fn failSource(b: *std.Build, message: []const u8) std.Build.LazyPath {
    const generated = b.addWriteFiles();
    generated.step.dependOn(&b.addFail(message).step);
    return generated.add("unavailable.c", "#error unavailable build input\n");
}
