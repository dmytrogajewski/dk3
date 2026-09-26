// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const config = @import("ioq3_config.zig");
pub fn declareTests(b: *std.Build, optimize: std.builtin.OptimizeMode) *std.Build.Step {
    const step = b.step("test-runtime", "Check native runtime domain, ECS and adapter contracts");
    const root = runtimeModule(b, b.graph.host, optimize, "src/runtime/root.zig");
    root.addIncludePath(b.path("src/runtime/tests/reference"));
    root.addIncludePath(b.path("src/runtime/tests"));
    for ([_][]const u8{ "engine/ioquake3/code/game/bg_pmove.c", "engine/ioquake3/code/game/bg_slidemove.c", "engine/ioquake3/code/qcommon/q_math.c", "src/runtime/tests/movement_reference.c" }) |source| root.addCSourceFile(.{ .file = b.path(source), .flags = &.{ "-std=gnu99", "-ffp-contract=off" } });
    root.linkSystemLibrary("m", .{});
    step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = root })).step);
    const audit = b.addExecutable(.{ .name = "dk3-runtime-audit", .root_module = b.createModule(.{ .root_source_file = b.path("src/runtime/audit.zig"), .target = b.graph.host, .optimize = optimize }) });
    const audit_step = b.step("runtime-audit", "Build read-only save compatibility inspector");
    audit_step.dependOn(&b.addInstallArtifact(audit, .{}).step);
    return step;
}
pub fn addProduct(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, product: config.Product, rules_identity: []const u8) *std.Build.Step.Compile {
    const root = switch (product) {
        .qagame => "src/runtime/server.zig",
        .cgame => "src/runtime/client.zig",
        .ui => "src/runtime/ui.zig",
        else => unreachable,
    };
    const module = runtimeModule(b, target, optimize, root);
    const compatibility = b.addOptions();
    compatibility.addOption([]const u8, "identity", rules_identity);
    module.addOptions("runtime_build", compatibility);
    @import("header_inputs.zig").track(b, module, &.{"engine/ioquake3/code"});
    return b.addLibrary(.{ .name = @tagName(product), .linkage = .dynamic, .root_module = module });
}

fn runtimeModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, source: []const u8) *std.Build.Module {
    const module = b.createModule(.{ .root_source_file = b.path(source), .target = target, .optimize = optimize, .link_libc = true });
    for ([_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "inventory_rules", .path = "src/weapons/inventory_rules.zig" },
        .{ .name = "weapon_catalog", .path = "src/weapons/catalog.zig" },
        .{ .name = "item_catalog", .path = "src/items/catalog.zig" },
        .{ .name = "actor_catalog", .path = "src/actors/catalog.zig" },
    }) |dependency| module.addImport(dependency.name, b.createModule(.{ .root_source_file = b.path(dependency.path), .target = target, .optimize = optimize }));
    module.addCMacro("DK3_GAME", "1");
    for ([_][]const u8{ "qcommon", "game", "cgame", "ui", "renderercommon" }) |directory|
        module.addIncludePath(b.path(b.fmt("engine/ioquake3/code/{s}", .{directory})));
    return module;
}
