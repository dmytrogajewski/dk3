// SPDX-License-Identifier: GPL-2.0-or-later
//! Explicit asset conversion. It is never a dependency of the default code build.
const std = @import("std");

pub const Assets = struct {
    step: *std.Build.Step,
    directory: []const u8,
    python: []const u8,
};

pub fn declare(b: *std.Build, guard: *std.Build.Step.Compile, python: []const u8, navigation: *std.Build.Step.Compile) Assets {
    const step = b.step("assets", "Convert user-owned assets using the selected retail or 1.3 profile");
    const data = b.option([]const u8, "DK_DATA", "Explicit path to legally acquired Daikatana data");
    const profile = b.option([]const u8, "asset-profile", "Asset profile: retail or 1.3") orelse "retail";
    const workers = b.option(u8, "asset-workers", "Asset conversion workers, 1 through 12") orelse 4;
    const ffmpeg = b.option([]const u8, "ffmpeg", "ffmpeg executable") orelse "ffmpeg";
    const major = b.option(u8, "ffmpeg-major", "ffmpeg major version used for reproducible encoding") orelse 7;
    const directory = b.getInstallPath(.prefix, "assets");
    if (data) |path| {
        const run = b.addRunArtifact(guard);
        run.addArgs(&.{ "--mem", "8G", "--timeout", "14400", "--", python, "-B" });
        run.addFileArg(b.path("dkq3/tools/assets.py"));
        run.addArgs(&.{ "--data", b.pathFromRoot(path), "--profile", profile, "--out", directory, "--workers", b.fmt("{d}", .{workers}), "--ffmpeg", ffmpeg, "--ffmpeg-major", b.fmt("{d}", .{major}), "--dkguard" });
        run.addArtifactArg(guard);
        run.addArg("--bspc");
        run.addArtifactArg(navigation);
        // The converter fingerprints content, resumes completed stages and publishes atomically.
        run.has_side_effects = true;
        step.dependOn(&run.step);
    } else {
        step.dependOn(&b.addFail("assets requires -DDK_DATA=/path/to/data; choose -Dasset-profile=retail or 1.3").step);
    }
    return .{ .step = step, .directory = directory, .python = python };
}
