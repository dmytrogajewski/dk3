// SPDX-License-Identifier: GPL-2.0-or-later
//! Native dk3 modules use upstream services and independent game-owned code.
const std = @import("std");
const config = @import("ioq3_config.zig");

pub fn declare(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, rules_identity: []const u8) void {
    const step = b.step("game", "Build independent dk3 game, client and UI modules");
    if (std.mem.eql(u8, b.install_path, b.pathFromRoot("zig-out/online"))) {
        step.dependOn(&b.addFail("The preserved online installation is not a development prefix").step);
        b.getInstallStep().dependOn(step);
        return;
    }
    for ([_]config.Product{ .qagame, .cgame, .ui }) |product| {
        const artifact = @import("runtime.zig").addProduct(b, target, optimize, product, rules_identity);
        const install = b.addInstallFileWithDir(artifact.getEmittedBin(), .lib, b.fmt("dk3/{t}.so", .{product}));
        step.dependOn(&install.step);
    }
    b.getInstallStep().dependOn(step);
}
