// SPDX-License-Identifier: GPL-2.0-or-later
//! Reused upstream QVM compiler graph, independent of the legacy game.
const std = @import("std");
const lists = @import("ioq3_sources.zig");
const Options = struct { optimize: std.builtin.OptimizeMode };

/// The host tools of `cmake/tools/CMakeLists.txt`, in the order the build needs them: lburg generates `dagcheck.c` for q3rcc.
pub const Tool = enum { lburg, q3rcc, q3cpp, q3lcc, q3asm };

/// `Q3ASM_SOURCES`, cmake/tools/CMakeLists.txt:6-9.
const q3asm_sources = [_][]const u8{ "code/tools/asm/q3asm.c", "code/tools/asm/cmdlib.c" };
/// `Q3LCC_SOURCES`, cmake/tools/CMakeLists.txt:11-14.
const q3lcc_sources = [_][]const u8{ "code/tools/lcc/etc/lcc.c", "code/tools/lcc/etc/bytecode.c" };
/// The directory of q3rcc's sources, also its include directory (`target_include_directories`, cmake/tools/CMakeLists.txt:90).
const lcc_src_dir = "code/tools/lcc/src";
/// `Q3RCC_SOURCES`, cmake/tools/CMakeLists.txt:16-45; the generated `dagcheck.c` is added to them (:88).
const q3rcc_sources = [_][]const u8{
    lcc_src_dir ++ "/alloc.c",    lcc_src_dir ++ "/bind.c",   lcc_src_dir ++ "/bytecode.c", lcc_src_dir ++ "/dag.c",
    lcc_src_dir ++ "/decl.c",     lcc_src_dir ++ "/enode.c",  lcc_src_dir ++ "/error.c",    lcc_src_dir ++ "/event.c",
    lcc_src_dir ++ "/expr.c",     lcc_src_dir ++ "/gen.c",    lcc_src_dir ++ "/init.c",     lcc_src_dir ++ "/inits.c",
    lcc_src_dir ++ "/input.c",    lcc_src_dir ++ "/lex.c",    lcc_src_dir ++ "/list.c",     lcc_src_dir ++ "/main.c",
    lcc_src_dir ++ "/null.c",     lcc_src_dir ++ "/output.c", lcc_src_dir ++ "/prof.c",     lcc_src_dir ++ "/profio.c",
    lcc_src_dir ++ "/simp.c",     lcc_src_dir ++ "/stmt.c",   lcc_src_dir ++ "/string.c",   lcc_src_dir ++ "/sym.c",
    lcc_src_dir ++ "/symbolic.c", lcc_src_dir ++ "/trace.c",  lcc_src_dir ++ "/tree.c",     lcc_src_dir ++ "/types.c",
};
/// `Q3RCC_DAGCHECK_SOURCE`, cmake/tools/CMakeLists.txt:47: the lburg grammar of the bytecode back end.
const dagcheck_grammar = lcc_src_dir ++ "/dagcheck.md";
/// `Q3CPP_SOURCES`, cmake/tools/CMakeLists.txt:49-60.
const q3cpp_sources = [_][]const u8{
    "code/tools/lcc/cpp/cpp.c",    "code/tools/lcc/cpp/lex.c",  "code/tools/lcc/cpp/nlist.c",   "code/tools/lcc/cpp/tokens.c",
    "code/tools/lcc/cpp/macro.c",  "code/tools/lcc/cpp/eval.c", "code/tools/lcc/cpp/include.c", "code/tools/lcc/cpp/hideset.c",
    "code/tools/lcc/cpp/getopt.c", "code/tools/lcc/cpp/unix.c",
};
/// `LBURG_SOURCES`, cmake/tools/CMakeLists.txt:62-65.
const lburg_sources = [_][]const u8{ "code/tools/lcc/lburg/lburg.c", "code/tools/lcc/lburg/gram.c" };

/// The sources of `tool`, relative to the checkout root, in CMake order.
pub fn toolSources(tool: Tool) []const []const u8 {
    return switch (tool) {
        .lburg => &lburg_sources,
        .q3rcc => &q3rcc_sources,
        .q3cpp => &q3cpp_sources,
        .q3lcc => &q3lcc_sources,
        .q3asm => &q3asm_sources,
    };
}

/// `add_compile_options` for GCC and Clang, cmake/tools/CMakeLists.txt:73-75. It applies to the targets declared after it:
/// lburg (:80), q3rcc (:88) and q3cpp (:92), not q3asm (:67) and q3lcc (:69). The tools project sets no C standard, and
/// `-O3 -DNDEBUG` (`CMAKE_BUILD_TYPE` Release) is replaced by `-Doptimize`, as for every ioq3 product.
const lcc_cast_flags = [_][]const u8{ "-fno-strict-aliasing", "-Wno-unused-result", "-Wno-pointer-to-int-cast", "-Wno-int-to-pointer-cast" };

/// The flags every source of `tool` is compiled with.
pub fn toolFlags(tool: Tool) []const []const u8 {
    return switch (tool) {
        .lburg, .q3rcc, .q3cpp => &lcc_cast_flags,
        .q3lcc, .q3asm => &.{},
    };
}

/// Files of one tool compiled with a UBSan check of Zig's C defaults turned off, each for a recorded trap (specs/build/BUILD-ioq3.md,
/// "Step 60 disabled sanitizer checks").
const ToolFileRule = struct { tool: Tool, paths: []const []const u8, flags: []const []const u8 };

const tool_file_rules = [_]ToolFileRule{
    // `quickset` and `quicklook` shift 1 by a name character masked to 5 bits (code/tools/lcc/cpp/cpp.h:84-85); `__STDC__` gives
    // `1<<31`, a shift into the sign bit, which trapped q3cpp in `setup_kwtab` (nlist.c:100). These are the files that expand them.
    .{ .tool = .q3cpp, .paths = &.{ "code/tools/lcc/cpp/nlist.c", "code/tools/lcc/cpp/macro.c", "code/tools/lcc/cpp/lex.c" }, .flags = &(lcc_cast_flags ++ [_][]const u8{"-fno-sanitize=shift"}) },
    // `extend` shifts 1 by `8*ty->size-1` in `int` (code/tools/lcc/src/c.h:35), `1<<31` for a 4-byte type; clang merges every shift
    // check of `simplify` into one `ud1 0x14`, which trapped q3rcc on the fixture's `(int)sizeof(...)` cast (expr.c:604 `cast`).
    // `foldaddp` adds a constant offset to a NULL constant pointer (simp.c:39), the `FOFS` field offsets of g_spawn.c's `fields[]`,
    // which trapped `simplify` at its one `ud1 0x13`.
    .{ .tool = .q3rcc, .paths = &.{"code/tools/lcc/src/simp.c"}, .flags = &(lcc_cast_flags ++ [_][]const u8{"-fno-sanitize=shift,pointer-overflow"}) },
    // `movetokenrow` passes the row's `bp` to `memmove` (code/tools/lcc/cpp/tokens.c:185), NULL with 0 bytes for an empty macro
    // body; glibc declares `memmove` `__nonnull`, which trapped q3cpp in `copytokenrow` (:221) from `expand` (macro.c:186).
    .{ .tool = .q3cpp, .paths = &.{"code/tools/lcc/cpp/tokens.c"}, .flags = &(lcc_cast_flags ++ [_][]const u8{"-fno-sanitize=nonnull-attribute"}) },
};

/// The flags `path` of `tool` is compiled with: `toolFlags`, or those of its file rule.
pub fn toolSourceFlags(tool: Tool, path: []const u8) []const []const u8 {
    for (tool_file_rules) |rule| {
        if (rule.tool == tool) for (rule.paths) |rule_path| if (std.mem.eql(u8, rule_path, path)) return rule.flags;
    }
    return toolFlags(tool);
}

/// The stock baseq3 modules compiled to QVMs (`add_qvm`, cmake/basegame.cmake:163-179), named as the engine loads them
/// (`vm/<name>.qvm`, code/qcommon/vm.c:377).
pub const Module = enum { cgame, qagame, ui };

/// One q3asm input: the asm file q3lcc makes of a C source, or an asm source used as is (cmake/utils/qvm_tools.cmake:59-76).
pub const Input = union(enum) {
    compiled: []const u8,
    assembled: []const u8,

    /// The checkout-relative source path.
    pub fn path(input: Input) []const u8 {
        return switch (input) {
            inline else => |source| source,
        };
    }
};

fn compiledInputs(comptime paths: []const []const u8) [paths.len]Input {
    var inputs: [paths.len]Input = undefined;
    for (paths, &inputs) |source, *input| input.* = .{ .compiled = source };
    return inputs;
}

/// `<MODULE>_SOURCES_BASEGAME` (cmake/basegame.cmake:126-128) then `<MODULE>_QVM_SOURCES` (:35, :72, :119).
const cgame_inputs = compiledInputs(&(lists.cgame_sources ++ lists.game_module_shared_sources)) ++ [_]Input{.{ .assembled = "code/cgame/cg_syscalls.asm" }};
const qagame_inputs = compiledInputs(&(lists.game_sources ++ lists.game_module_shared_sources)) ++ [_]Input{.{ .assembled = "code/game/g_syscalls.asm" }};
const ui_inputs = compiledInputs(&(lists.ui_sources ++ lists.game_module_shared_sources)) ++ [_]Input{.{ .assembled = "code/ui/ui_syscalls.asm" }};

/// The q3asm inputs of `module`, in the order of the reference q3asm command line.
pub fn assemblerInputs(module: Module) []const Input {
    return switch (module) {
        .cgame => &cgame_inputs,
        .qagame => &qagame_inputs,
        .ui => &ui_inputs,
    };
}

/// The option that moves q3lcc's temporary files out of `/tmp` (code/tools/lcc/etc/lcc.c:676-678).
pub const temporary_directory_option = "-tempdir=";

/// One argument of a q3lcc run: fixed text, or a path the build graph supplies.
pub const LccArg = union(enum) {
    text: []const u8,
    /// `-tempdir=` and a fresh output directory of the run.
    temporary_directory,
    /// The asm file the run writes.
    assembly_output,
    /// The C source.
    source,
};

/// The arguments after q3lcc for one C source of `module`: the reference `${Q3LCC} ${LCC_FLAGS} -o ${ASM_FILE} ${SOURCE}`
/// (cmake/utils/qvm_tools.cmake:71), with the module's one definition (`DEFINITIONS`, cmake/basegame.cmake:164, :170, :176),
/// preceded by the temporary directory.
pub fn lccArgs(module: Module) [5]LccArg {
    const definition: []const u8 = switch (module) {
        .cgame => "-DCGAME",
        .qagame => "-DQAGAME",
        .ui => "-DUI",
    };
    return .{ .temporary_directory, .{ .text = definition }, .{ .text = "-o" }, .assembly_output, .source };
}

/// lburg, the `dagcheck.c` it generates from the grammar (cmake/tools/CMakeLists.txt:82-86), and q3rcc, q3cpp, q3lcc and q3asm,
/// copied side by side into one directory: q3lcc runs q3cpp and q3rcc from its own directory (`UpdatePaths`,
/// code/tools/lcc/etc/bytecode.c:28-51). Returns that directory.
fn addToolchain(b: *std.Build, opts: Options, tree: std.Build.LazyPath) std.Build.LazyPath {
    const directory = b.addWriteFiles();
    const lburg = addTool(b, opts, tree, .lburg, null);
    const generate = b.addRunArtifact(lburg);
    generate.setName("lburg dagcheck.md dagcheck.c");
    generate.addFileArg(tree.path(b, dagcheck_grammar));
    const dagcheck = generate.addOutputFileArg("dagcheck.c");
    expectSilentSuccess(generate);
    for (std.enums.values(Tool)) |tool| {
        const artifact = if (tool == .lburg) lburg else addTool(b, opts, tree, tool, dagcheck);
        _ = directory.addCopyFile(artifact.getEmittedBin(), @tagName(tool));
    }
    return directory.getDirectory();
}

/// The host executable of `tool` (`add_executable`, cmake/tools/CMakeLists.txt:67-92); q3rcc also compiles `dagcheck`.
fn addTool(b: *std.Build, opts: Options, tree: std.Build.LazyPath, tool: Tool, dagcheck: ?std.Build.LazyPath) *std.Build.Step.Compile {
    const module = b.createModule(.{ .target = b.graph.host, .optimize = opts.optimize, .link_libc = true });
    for (toolSources(tool)) |path| module.addCSourceFile(.{ .file = tree.path(b, path), .flags = toolSourceFlags(tool, path) });
    if (tool == .q3rcc) {
        module.addCSourceFile(.{ .file = dagcheck.?, .flags = toolFlags(tool) });
        module.addIncludePath(tree.path(b, lcc_src_dir));
    }
    return b.addExecutable(.{ .name = @tagName(tool), .root_module = module });
}

/// A tool run passes only with exit 0 and nothing on stderr, where lcc, rcc, q3asm and lburg print every warning and error,
/// so a warning fails the step and its text is printed.
fn expectSilentSuccess(run: *std.Build.Step.Run) void {
    run.addCheck(.{ .expect_term = .{ .exited = 0 } });
    run.addCheck(.{ .expect_stderr_exact = "" });
}

/// q3lcc from `toolchain` on `source` with `args`; returns the run and the asm file it writes.
fn addCompile(b: *std.Build, toolchain: std.Build.LazyPath, name: []const u8, args: []const LccArg, source: std.Build.LazyPath, assembly_name: []const u8) struct { *std.Build.Step.Run, std.Build.LazyPath } {
    const run = std.Build.Step.Run.create(b, name);
    run.addFileArg(toolchain.path(b, @tagName(Tool.q3lcc)));
    var assembly: ?std.Build.LazyPath = null;
    for (args) |arg| switch (arg) {
        .text => |text| run.addArg(text),
        .temporary_directory => _ = run.addPrefixedOutputDirectoryArg(temporary_directory_option, "tmp"),
        .assembly_output => assembly = run.addOutputFileArg(assembly_name),
        .source => run.addFileArg(source),
    };
    return .{ run, assembly.? };
}

/// A QVM and, when asked for, the symbol map q3asm writes beside it: `-m` names it after the image with `.map` and lists each global
/// symbol as `<segment> <value in hex> <name>`, the code segment first (code/tools/asm/q3asm.c:1314-1339, `CODESEG` 0 at :130).
pub const Image = struct { qvm: std.Build.LazyPath, map: ?std.Build.LazyPath };

/// The option that makes q3asm write the symbol map (code/tools/asm/q3asm.c:1603-1606); the reference rule never passes it.
pub const map_option = "-m";

/// q3asm on the inputs of `image_name`: `${Q3ASM} -o ${QVM_FILE} ${ASM_FILES}` (cmake/utils/qvm_tools.cmake:81), preceded by
/// `map_option` when `map_file` is set. `label` names the step.
fn addAssemble(b: *std.Build, toolchain: std.Build.LazyPath, image_name: []const u8, label: []const u8, inputs: []const std.Build.LazyPath, map_file: bool) Image {
    const run = std.Build.Step.Run.create(b, b.fmt("q3asm {s} ({s})", .{ image_name, label }));
    run.addFileArg(toolchain.path(b, @tagName(Tool.q3asm)));
    if (map_file) run.addArg(map_option);
    run.addArg("-o");
    const image = run.addOutputFileArg(image_name);
    for (inputs) |input| run.addFileArg(input);
    expectSilentSuccess(run);
    const map = if (map_file) image.dirname().path(b, b.fmt("{s}.map", .{std.fs.path.stem(image_name)})) else null;
    return .{ .qvm = image, .map = map };
}

/// A QVM named `image_name` from `inputs` below `tree`: one q3lcc run per C source with the definition of `module` (`lccArgs`), each
/// cached on its own, then q3asm in input order, with its symbol map when `map_file` is set. Every run must exit 0 with an empty
/// stderr. `label` names the steps.
pub fn addModuleImage(b: *std.Build, toolchain: std.Build.LazyPath, tree: std.Build.LazyPath, module: Module, label: []const u8, inputs: []const Input, image_name: []const u8, map_file: bool) Image {
    // q3lcc emits no dependency file. Track module headers explicitly while compiling
    // original sources in place so a header edit invalidates the generated assembly.
    var headers: std.ArrayList(std.Build.LazyPath) = .empty;
    for ([_][]const u8{ "code/qcommon", "code/game", "code/cgame", "code/ui", "code/q3_ui", "code/client", "code/botlib", "code/renderercommon", "ui" }) |directory| {
        var dir = std.Io.Dir.cwd().openDir(b.graph.io, tree.path(b, directory).getPath(b), .{ .iterate = true }) catch |err|
            @panic(b.fmt("QVM header directory {s}: {t}", .{ directory, err }));
        defer dir.close(b.graph.io);
        var walker = dir.walk(b.allocator) catch @panic("OOM");
        defer walker.deinit();
        while (walker.next(b.graph.io) catch |err| @panic(b.fmt("QVM headers: {t}", .{err}))) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.path, ".h"))
                headers.append(b.allocator, tree.path(b, b.pathJoin(&.{ directory, entry.path }))) catch @panic("OOM");
        }
    }
    const assemblies = b.allocator.alloc(std.Build.LazyPath, inputs.len) catch @panic("OOM");
    for (inputs, assemblies) |input, *path| path.* = switch (input) {
        .assembled => |source| tree.path(b, source),
        .compiled => |source| compiled: {
            const run, const assembly = addCompile(b, toolchain, b.fmt("q3lcc {s} ({s})", .{ source, label }), &lccArgs(module), tree.path(b, source), b.fmt("{s}.asm", .{std.fs.path.stem(source)}));
            for (headers.items) |header| run.addFileInput(header);
            expectSilentSuccess(run);
            break :compiled assembly;
        },
    };
    return addAssemble(b, toolchain, image_name, label, assemblies, map_file);
}

/// Build the compiler tools and upstream foundation QVMs from bundled source.
pub fn declare(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const tree = b.path("engine/ioquake3");
    const tools = addToolchain(b, .{ .optimize = optimize }, tree);
    const tools_step = b.step("qvm-tools", "Build lburg, q3rcc, q3cpp, q3lcc and q3asm");
    const install_tools = b.addInstallDirectory(.{ .source_dir = tools, .install_dir = .bin, .install_subdir = "qvm-tools" });
    tools_step.dependOn(&install_tools.step);
    const images = b.step("qvms", "Compile the upstream foundation modules with the bundled QVM toolchain");
    for (std.enums.values(Module)) |module| {
        const output = addModuleImage(b, tools, tree, module, "upstream foundation", assemblerInputs(module), b.fmt("{t}.qvm", .{module}), false);
        images.dependOn(&b.addInstallFileWithDir(output.qvm, .bin, b.fmt("baseq3/vm/{t}.qvm", .{module})).step);
    }
}
