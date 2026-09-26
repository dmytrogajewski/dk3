// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const assets = @import("assets.zig");

pub fn declare(b: *std.Build, packages: assets.Assets, guard: *std.Build.Step.Compile) void {
    const install = b.step("play-install", "Prepare and verify an independent dk3 development installation");
    if (std.mem.eql(u8, b.install_path, b.pathFromRoot("zig-out")) or std.mem.eql(u8, b.install_path, b.pathFromRoot("zig-out/online"))) {
        const failure = &b.addFail("Use --prefix zig-out/native-dev for native development; preserved installations must not be overwritten").step;
        install.dependOn(failure);
        b.step("play", "Launch the independent dk3 development game with supplied assets").dependOn(failure);
        return;
    }
    const prepare = b.addSystemCommand(&.{ packages.python, "-B" });
    prepare.addFileArg(b.path("dkq3/tools/play.py"));
    prepare.addArgs(&.{ "install", "--prefix", b.install_path, "--assets", packages.directory });
    if (b.option([]const u8, "hd-textures", "Optional locally produced HD texture PK3")) |path| {
        prepare.addArgs(&.{ "--hd-textures", path });
    }
    prepare.has_side_effects = true;
    prepare.step.dependOn(packages.step);
    prepare.step.dependOn(b.getInstallStep());
    install.dependOn(&prepare.step);
    const play = b.step("play", "Launch the independent dk3 development game with supplied assets");
    const launch = b.addSystemCommand(&.{ packages.python, "-B" });
    launch.addFileArg(b.path("dkq3/tools/play.py"));
    launch.addArgs(&.{ "launch", "--prefix", b.install_path, "--dkguard" });
    launch.addArtifactArg(guard);
    launch.addArgs(&.{ "--", "+set", "dk3_runtime_probe", "2" });
    if (b.args) |args| {
        launch.addArgs(args);
    }
    launch.has_side_effects = true;
    launch.step.dependOn(install);
    play.dependOn(&launch.step);
}
