// SPDX-License-Identifier: GPL-2.0-or-later
//! Native dk3 modules use upstream services and independent game-owned code.
const std = @import("std");
const ioq3 = @import("ioq3.zig");
const config = @import("ioq3_config.zig");

pub const Runtime = enum { legacy, zig };

pub fn declare(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, engine: ioq3.Engine, runtime: Runtime, rules_identity: []const u8) void {
    const step = b.step("game", "Build independent dk3 game, client and UI modules");
    if (runtime == .zig and (std.mem.eql(u8, b.install_path, b.pathFromRoot("zig-out")) or std.mem.eql(u8, b.install_path, b.pathFromRoot("zig-out/online")))) {
        step.dependOn(&b.addFail("Zig replacement requires an isolated --prefix; production cutover is not qualified").step);
        b.getInstallStep().dependOn(step);
        return;
    }
    for ([_]config.Product{ .qagame, .cgame, .ui }) |product| {
        const artifact = if (runtime == .legacy) ioq3.addProduct(b, target, optimize, engine.settings, product, true) else @import("replacement.zig").addProduct(b, target, optimize, product, rules_identity);
        const install = b.addInstallFileWithDir(artifact.getEmittedBin(), .lib, b.fmt("dk3/{t}.so", .{product}));
        step.dependOn(&install.step);
    }
    b.getInstallStep().dependOn(step);
}
