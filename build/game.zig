// SPDX-License-Identifier: GPL-2.0-or-later
//! Native dk3 modules use upstream services and independent game-owned code.
const std = @import("std");
const ioq3 = @import("ioq3.zig");
const config = @import("ioq3_config.zig");

pub fn declare(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, engine: ioq3.Engine) void {
    const step = b.step("game", "Build independent dk3 game, client and UI modules");
    for ([_]config.Product{ .qagame, .cgame, .ui }) |product| {
        const artifact = ioq3.addProduct(b, target, optimize, engine.settings, product, true);
        const install = b.addInstallFileWithDir(artifact.getEmittedBin(), .lib, b.fmt("dk3/{t}.so", .{product}));
        step.dependOn(&install.step);
    }
    b.getInstallStep().dependOn(step);
}
