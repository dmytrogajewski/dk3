// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const config = @import("ioq3_config.zig");
pub fn declareTests(b: *std.Build, optimize: std.builtin.OptimizeMode) *std.Build.Step {
    const step = b.step("test-runtime", "Check the native Zig replacement independently of legacy gameplay");
    const root = b.createModule(.{ .root_source_file = b.path("src/replacement/root.zig"), .target = b.graph.host, .optimize = optimize, .link_libc = true });
    root.addImport("inventory_rules", b.createModule(.{ .root_source_file = b.path("src/weapons/inventory_rules.zig"), .target = b.graph.host, .optimize = optimize }));
    step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = root })).step);
    const audit = b.addExecutable(.{ .name = "dk3-runtime-audit", .root_module = b.createModule(.{ .root_source_file = b.path("src/replacement/audit.zig"), .target = b.graph.host, .optimize = optimize }) });
    const audit_step = b.step("runtime-audit", "Build read-only replacement save compatibility inspector");
    audit_step.dependOn(&b.addInstallArtifact(audit, .{}).step);
    return step;
}
pub fn addProduct(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, product: config.Product) *std.Build.Step.Compile {
    const root = switch (product) {
        .qagame => "src/replacement/server.zig",
        .cgame => "src/replacement/client.zig",
        .ui => "src/replacement/ui.zig",
        else => unreachable,
    };
    const module = b.createModule(.{ .root_source_file = b.path(root), .target = target, .optimize = optimize, .link_libc = true });
    module.addImport("inventory_rules", b.createModule(.{ .root_source_file = b.path("src/weapons/inventory_rules.zig"), .target = target, .optimize = optimize }));
    module.addCMacro("DK3_GAME", "1");
    module.addIncludePath(b.path("engine/ioquake3/code/qcommon"));
    module.addIncludePath(b.path("engine/ioquake3/code/game"));
    module.addIncludePath(b.path("engine/ioquake3/code/cgame"));
    module.addIncludePath(b.path("engine/ioquake3/code/ui"));
    @import("header_inputs.zig").track(b, module, &.{"engine/ioquake3/code"});
    return b.addLibrary(.{ .name = @tagName(product), .linkage = .dynamic, .root_module = module });
}
