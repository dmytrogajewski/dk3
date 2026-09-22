// SPDX-License-Identifier: GPL-2.0-or-later
//! Pinned GPL BSP-to-AAS compiler, built from bundled source.
const std = @import("std");
const sources = [_][]const u8{
    "_files.c",
    "aas_areamerging.c",
    "aas_cfg.c",
    "aas_create.c",
    "aas_edgemelting.c",
    "aas_facemerging.c",
    "aas_file.c",
    "aas_gsubdiv.c",
    "aas_map.c",
    "aas_prunenodes.c",
    "aas_store.c",
    "be_aas_bspc.c",
    "deps/botlib/be_aas_bspq3.c",
    "deps/botlib/be_aas_cluster.c",
    "deps/botlib/be_aas_move.c",
    "deps/botlib/be_aas_optimize.c",
    "deps/botlib/be_aas_reach.c",
    "deps/botlib/be_aas_sample.c",
    "brushbsp.c",
    "bspc.c",
    "deps/qcommon/cm_load.c",
    "deps/qcommon/cm_patch.c",
    "deps/qcommon/cm_test.c",
    "deps/qcommon/cm_trace.c",
    "csg.c",
    "glfile.c",
    "l_bsp_ent.c",
    "l_bsp_hl.c",
    "l_bsp_q1.c",
    "l_bsp_q2.c",
    "l_bsp_q3.c",
    "l_bsp_sin.c",
    "l_cmd.c",
    "deps/botlib/l_libvar.c",
    "l_log.c",
    "l_math.c",
    "l_mem.c",
    "l_poly.c",
    "deps/botlib/l_precomp.c",
    "l_qfiles.c",
    "deps/botlib/l_script.c",
    "deps/botlib/l_struct.c",
    "l_threads.c",
    "l_utils.c",
    "leakfile.c",
    "map.c",
    "map_hl.c",
    "map_q1.c",
    "map_q2.c",
    "map_q3.c",
    "map_sin.c",
    "deps/qcommon/md4.c",
    "nodraw.c",
    "portals.c",
    "textures.c",
    "tree.c",
    "deps/qcommon/unzip.c",
};

pub fn declare(b: *std.Build, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const module = b.createModule(.{ .target = b.graph.host, .optimize = optimize, .link_libc = true });
    @import("header_inputs.zig").track(b, module, &.{"engine/bspc"});
    module.addCSourceFiles(.{ .root = b.path("engine/bspc"), .files = &sources, .flags = &.{ "-std=gnu99", "-fno-strict-aliasing" } });
    module.addIncludePath(b.path("engine/bspc"));
    module.addIncludePath(b.path("engine/bspc/deps"));
    module.addCMacro("stricmp", "strcasecmp");
    module.addCMacro("Com_Memcpy", "memcpy");
    module.addCMacro("Com_Memset", "memset");
    module.addCMacro("MAC_STATIC", "");
    module.addCMacro("QDECL", "");
    module.addCMacro("LINUX", "1");
    module.addCMacro("BSPC", "1");
    module.linkSystemLibrary("m", .{});
    module.linkSystemLibrary("pthread", .{});
    const compiler = b.addExecutable(.{ .name = "bspc", .root_module = module });
    const install = b.addInstallArtifact(compiler, .{});
    b.getInstallStep().dependOn(&install.step);
    b.step("navigation-compiler", "Build and install the bundled GPL BSP-to-AAS compiler").dependOn(&install.step);
    return compiler;
}
