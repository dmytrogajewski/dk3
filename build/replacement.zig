// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const config = @import("ioq3_config.zig");
pub fn declareTests(b: *std.Build, optimize: std.builtin.OptimizeMode) *std.Build.Step {
    const step = b.step("test-runtime", "Check the native Zig replacement independently of legacy gameplay");
    const root = b.createModule(.{ .root_source_file = b.path("src/replacement/root.zig"), .target = b.graph.host, .optimize = optimize, .link_libc = true });
    root.addImport("inventory_rules", b.createModule(.{ .root_source_file = b.path("src/weapons/inventory_rules.zig"), .target = b.graph.host, .optimize = optimize }));
    root.addImport("weapon_catalog", catalog(b, b.graph.host, optimize));
    root.addImport("item_catalog", itemCatalog(b, b.graph.host, optimize));
    root.addCMacro("DK3_GAME", "1");
    for ([_][]const u8{ "engine/ioquake3/code/qcommon", "engine/ioquake3/code/game", "engine/ioquake3/code/cgame", "engine/ioquake3/code/ui", "engine/ioquake3/code/renderercommon", "src/shared", "src/game", "src/replacement/tests" }) |directory| root.addIncludePath(b.path(directory));
    for ([_][]const u8{ "engine/ioquake3/code/game/bg_pmove.c", "engine/ioquake3/code/game/bg_slidemove.c", "engine/ioquake3/code/qcommon/q_math.c", "src/replacement/tests/movement_reference.c" }) |source| root.addCSourceFile(.{ .file = b.path(source), .flags = &.{ "-std=gnu99", "-ffp-contract=off" } });
    root.linkSystemLibrary("m", .{});
    step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = root })).step);
    const audit = b.addExecutable(.{ .name = "dk3-runtime-audit", .root_module = b.createModule(.{ .root_source_file = b.path("src/replacement/audit.zig"), .target = b.graph.host, .optimize = optimize }) });
    const audit_step = b.step("runtime-audit", "Build read-only replacement save compatibility inspector");
    audit_step.dependOn(&b.addInstallArtifact(audit, .{}).step);
    return step;
}
pub fn addProduct(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, product: config.Product, rules_identity: []const u8) *std.Build.Step.Compile {
    const root = switch (product) {
        .qagame => "src/replacement/server.zig",
        .cgame => "src/replacement/client.zig",
        .ui => "src/replacement/ui.zig",
        else => unreachable,
    };
    const module = b.createModule(.{ .root_source_file = b.path(root), .target = target, .optimize = optimize, .link_libc = true });
    const compatibility = b.addOptions();
    compatibility.addOption([]const u8, "identity", rules_identity);
    module.addOptions("runtime_build", compatibility);
    module.addImport("inventory_rules", b.createModule(.{ .root_source_file = b.path("src/weapons/inventory_rules.zig"), .target = target, .optimize = optimize }));
    module.addImport("weapon_catalog", catalog(b, target, optimize));
    module.addImport("item_catalog", itemCatalog(b, target, optimize));
    module.addCMacro("DK3_GAME", "1");
    module.addIncludePath(b.path("engine/ioquake3/code/qcommon"));
    module.addIncludePath(b.path("engine/ioquake3/code/game"));
    module.addIncludePath(b.path("engine/ioquake3/code/cgame"));
    module.addIncludePath(b.path("engine/ioquake3/code/ui"));
    module.addIncludePath(b.path("engine/ioquake3/code/renderercommon"));
    @import("header_inputs.zig").track(b, module, &.{"engine/ioquake3/code"});
    return b.addLibrary(.{ .name = @tagName(product), .linkage = .dynamic, .root_module = module });
}

fn catalog(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const module = b.createModule(.{ .root_source_file = b.path("src/weapons/catalog.zig"), .target = target, .optimize = optimize });
    return module;
}

fn itemCatalog(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return b.createModule(.{ .root_source_file = b.path("src/items/catalog.zig"), .target = target, .optimize = optimize });
}
