// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed ioquake3 source, flag and option mappings; no game or reference imports.
const std = @import("std");
const lists = @import("ioq3_sources.zig");

pub const Config = struct {
    /// `-DBUILD_STANDALONE`: ioq3 CMake `BUILD_STANDALONE` (CMakeLists.txt:20). On by default, unlike
    /// CMake: the port runs the standalone base game dkq3 (SPEC "Architecture decisions").
    build_standalone: bool = true,
    /// `-DUSE_VOIP`: ioq3 CMake `USE_VOIP` (CMakeLists.txt:28), on by default as in CMake.
    use_voip: bool = true,
    /// `-DUSE_HTTP`: ioq3 CMake `USE_HTTP` (CMakeLists.txt:25), on by default as in CMake.
    use_http: bool = true,
    /// `-DUSE_CODEC_VORBIS`: ioq3 CMake `USE_CODEC_VORBIS` (CMakeLists.txt:26), on by default as in CMake.
    use_codec_vorbis: bool = true,
    /// `-DUSE_CODEC_OPUS`: ioq3 CMake `USE_CODEC_OPUS` (CMakeLists.txt:27), on by default as in CMake.
    use_codec_opus: bool = true,
    /// `-DUSE_MUMBLE`: ioq3 CMake `USE_MUMBLE` (CMakeLists.txt:29), on by default as in CMake.
    use_mumble: bool = true,
    /// `-DUSE_OPENAL`: ioq3 CMake `USE_OPENAL` (CMakeLists.txt:23), on by default as in CMake.
    use_openal: bool = true,
    /// `-DUSE_FREETYPE`: ioq3 CMake `USE_FREETYPE` (CMakeLists.txt:30), off by default as in CMake.
    use_freetype: bool = false,
    /// `-DPRODUCT_VERSION`: ioq3 CMake `PRODUCT_VERSION` (CMakeLists.txt:57-83); the default is the
    /// project version (cmake/identity.cmake:2) without the git revision suffix.
    product_version: []const u8 = "1.36",
    /// `-DPRODUCT_DATE`: ioq3 `PRODUCT_DATE` (CMakeLists.txt:88-91), always defined so no compile date
    /// is embedded; empty by default.
    product_date: []const u8 = "",
};

/// Flags of every product's sources: the reference `flags.make` `C_FLAGS` without the build-type flags
/// `-O3 -DNDEBUG` and the IPO flags, which `-Doptimize` and `lto` replace (BUILD-ioq3.md, "Flags").
/// `-std=gnu99`: CMakeLists.txt:53-54 (C99 with CMake's default GNU extensions); warnings:
/// cmake/compilers/gnu.cmake:14-19; `-fno-strict-aliasing`: :23; `-fvisibility=hidden`: :27.
const c_flags = [_][]const u8{
    "-std=gnu99",              "-Wall",                                 "-Wimplicit",
    "-Wshadow",                "-Wstrict-prototypes",                   "-Wformat=2",
    "-Wformat-security",       "-Wstrict-aliasing=2",                   "-Wmissing-format-attribute",
    "-Wdisabled-optimization", "-Werror-implicit-function-declaration", "-Wno-format-zero-length",
    "-Wno-format-nonliteral",  "-fno-strict-aliasing",                  "-fvisibility=hidden",
};

/// UBSan check of Zig's C defaults disabled for a recorded trap (BUILD-ioq3.md, "Disabled sanitizer
/// checks"). `nonnull-attribute`: `FS_AddGameDirectory` passes the NULL list of an empty directory to glibc
/// `qsort`/`strlen` (code/qcommon/files.c), trapping at startup in the server and in the client;
/// `GeneratePermanentShader` passes a NULL `texMods` array of size 0 to `memcpy`
/// (code/renderergl1/tr_shader.c:2073, code/renderergl2/tr_shader.c:2807), trapping in `R_Init` of both renderers.
const nonnull_attribute_off = [_][]const u8{"-fno-sanitize=nonnull-attribute"};

/// The UBSan checks disabled for every source of `product`; every other check stays on.
pub fn sanitizerFlags(product: Product) []const []const u8 {
    return flag_sets.get(product).sanitizer;
}

/// The flags of one product: the mirrored CMake flags, then its disabled sanitizer checks, then for
/// `quiet` the per-file `COMPILE_FLAGS -w` of `disable_warnings` (utils/disable_warnings.cmake:14).
const FlagSet = struct {
    sanitizer: []const []const u8,
    normal: []const []const u8,
    quiet: []const []const u8,

    fn init(comptime sanitizer: []const []const u8) FlagSet {
        return .{ .sanitizer = sanitizer, .normal = &(c_flags ++ sanitizer[0..sanitizer.len].*), .quiet = &(c_flags ++ sanitizer[0..sanitizer.len].* ++ .{"-w"}) };
    }
};

/// The product-wide disabled checks of the products that trapped.
const client_sanitizer = nonnull_attribute_off;
const renderer_gl2_sanitizer = nonnull_attribute_off;

const flag_sets = std.enums.EnumArray(Product, FlagSet).init(.{
    .server = .init(&nonnull_attribute_off),
    .client = .init(&client_sanitizer),
    .renderer_opengl1 = .init(&nonnull_attribute_off),
    .renderer_opengl2 = .init(&renderer_gl2_sanitizer),
    .cgame = .init(&.{}),
    .qagame = .init(&.{}),
    .ui = .init(&.{}),
});

/// `pointer-overflow` off for the files of a product that add offsets to a NULL pointer on purpose, each for
/// a recorded trap (BUILD-ioq3.md, "Disabled sanitizer checks"); the product's other files keep the check.
const pointer_overflow_off = [_][]const u8{"-fno-sanitize=pointer-overflow"};

/// `function` off for the files of a product that call functions through a table of pointers cast to another
/// function type, each for a recorded trap (BUILD-ioq3.md, "Disabled sanitizer checks").
const function_off = [_][]const u8{"-fno-sanitize=function"};

/// `alignment` off for the files of a product that read structs through byte offsets of a file buffer, each for a
/// recorded trap (BUILD-ioq3.md, "Disabled sanitizer checks").
const alignment_off = [_][]const u8{"-fno-sanitize=alignment"};

/// `null` off for the files of a product that take the address of a member through a pointer that is NULL once a list
/// ends, each for a recorded trap (BUILD-ioq3.md, "Disabled sanitizer checks").
const null_off = [_][]const u8{"-fno-sanitize=null"};

/// `shift` off for the files of a product that shift a signed value into or past its sign bit where the result is used as unsigned, each
/// for a recorded trap (BUILD-ioq3.md, "Disabled sanitizer checks").
const shift_off = [_][]const u8{"-fno-sanitize=shift"};

/// `signed-integer-overflow` off for the files of a product that multiply signed values expecting two's-complement wrap-around, each for a
/// recorded trap (BUILD-ioq3.md, "Step 8 disabled sanitizer checks", row 12).
const signed_integer_overflow_off = [_][]const u8{"-fno-sanitize=signed-integer-overflow"};

/// Files of one product compiled with extra disabled checks.
const FileRule = struct { product: Product, paths: []const []const u8, flags: []const []const u8 };

const file_rules = [_]FileRule{
    // `VM_ArgPtr` returns `dataBase + intValue`; a native module's `dataBase` is NULL, so every pointer
    // argument of a module system call trips the check (code/qcommon/vm.c:757, :775; first `ui` call in the client,
    // G_InitGame's first trap_Print through SV_GameSystemCalls in the server).
    .{ .product = .client, .paths = &.{"code/qcommon/vm.c"}, .flags = &(c_flags ++ client_sanitizer ++ pointer_overflow_off) },
    .{ .product = .server, .paths = &.{"code/qcommon/vm.c"}, .flags = &(c_flags ++ nonnull_attribute_off ++ pointer_overflow_off) },
    // `BUFFER_OFFSET(i)` is `(char *)NULL + (i)` (code/renderergl2/tr_local.h:57), the GL buffer-offset idiom;
    // `R_InitVaos` traps in `Vao_SetVertexPointers` (tr_vbo.c:77). These are the files that expand it.
    .{ .product = .renderer_opengl2, .paths = &.{ "code/renderergl2/tr_vbo.c", "code/renderergl2/tr_shade.c", "code/renderergl2/tr_surface.c" }, .flags = &(c_flags ++ renderer_gl2_sanitizer ++ pointer_overflow_off) },
    // `rb_surfaceTable` holds every `RB_Surface*` function cast to `void (*)(void *)` (code/renderergl1/tr_surface.c:
    // 1092-1104); `RB_RenderDrawSurfList` calls `RB_SurfaceEntity` through it on the client's first rendered frame
    // (tr_backend.c:536). These are the files that call the table (tr_backend.c:536, :656, tr_main.c:864).
    .{ .product = .renderer_opengl1, .paths = &.{ "code/renderergl1/tr_backend.c", "code/renderergl1/tr_main.c" }, .flags = &(c_flags ++ nonnull_attribute_off ++ function_off) },
    // `BufferedFileRead` returns a pointer into the PNG file buffer, which `FindChunk` and the chunk readers cast to
    // `struct PNG_ChunkHeader *` and other chunk structs (code/renderercommon/tr_image_png.c:456-468); a chunk after
    // `IHDR` starts at byte 33, so the first PNG world texture traps in `FindChunk` (tr_image_png.c:501).
    .{ .product = .renderer_opengl1, .paths = &.{"code/renderercommon/tr_image_png.c"}, .flags = &(c_flags ++ nonnull_attribute_off ++ alignment_off) },
    // The same file, the same trap, in the other renderer: `R_LoadPNG`'s `FindChunk(ThePNG, PNG_ChunkType_tRNS)`
    // (tr_image_png.c:2211) reads a chunk header at an odd offset, so the first PNG the opengl2 renderer loads ends the
    // run. Measured on the Daikatana menu (`RE_RegisterModel` of the strip's `ib_button.dkm` through `R_FindShader`),
    // which is why `cl_renderer opengl2` could not reach the front end at all.
    .{ .product = .renderer_opengl2, .paths = &.{"code/renderercommon/tr_image_png.c"}, .flags = &(c_flags ++ renderer_gl2_sanitizer ++ alignment_off) },
    // The 16-bit mixer steps to `chunk->next` and takes `chunk->sndChunk` right after a sound's last sample
    // (code/client/snd_mix.c:306-308); for a sound ending on a chunk boundary `next` is NULL, so a map's looping speaker
    // traps in `S_PaintChannelFrom16` from `S_PaintChannels` (snd_mix.c:614) once the sound package loads (FRD-019).
    .{ .product = .client, .paths = &.{"code/client/snd_mix.c"}, .flags = &(c_flags ++ client_sanitizer ++ null_off) },
    // `vorbis_book_init_decode` computes `ogg_uint32_t word=i<<(32-c->dec_firsttablen)` from the signed `int i` of the first decode table,
    // a shift into the sign bit for every index of 128 or more (code/thirdparty/libvorbis-1.3.7/lib/sharedbook.c:425), so the first Ogg
    // Vorbis file a client decodes traps from `vorbis_synthesis_init` (FRD-020). The file keeps its reference `-w` (disable_warnings).
    .{ .product = .client, .paths = &.{"code/thirdparty/libvorbis-1.3.7/lib/sharedbook.c"}, .flags = &(c_flags ++ client_sanitizer ++ shift_off ++ .{"-w"}) },
    // `NETCHAN_GENCHECKSUM(challenge, sequence)` is `(challenge) ^ ((sequence) * (challenge))` on `int`s (code/qcommon/qcommon.h:191),
    // which overflows for most random challenges; the first netchan packet over a real socket traps in `Netchan_Transmit`
    // (code/qcommon/net_chan.c:210) in the server and the client of the Step 62 wire suite. Loopback runs never sent one. Only this file
    // expands the macro (net_chan.c:129, :210, :276).
    .{ .product = .client, .paths = &.{"code/qcommon/net_chan.c"}, .flags = &(c_flags ++ client_sanitizer ++ signed_integer_overflow_off) },
    .{ .product = .server, .paths = &.{"code/qcommon/net_chan.c"}, .flags = &(c_flags ++ nonnull_attribute_off ++ signed_integer_overflow_off) },
};

/// The flags `path` of `product` is compiled with.
pub fn sourceFlags(product: Product, path: []const u8) []const []const u8 {
    // Keep each client-game sanitizer trap at its originating operation. Merged
    // traps attributed an effect conversion failure to unrelated step smoothing.
    if (product == .cgame) return if (isQuiet(path))
        &(c_flags ++ .{ "-fno-sanitize-merge", "-w" })
    else
        &(c_flags ++ .{"-fno-sanitize-merge"});
    for (file_rules) |rule| {
        if (rule.product == product) for (rule.paths) |rule_path| if (std.mem.eql(u8, rule_path, path)) return rule.flags;
    }
    const set = flag_sets.get(product);
    return if (isQuiet(path)) set.quiet else set.normal;
}

/// The ioq3 CMake products this graph builds: `SERVER_BINARY` (cmake/server.cmake:38), `CLIENT_BINARY`
/// (cmake/client.cmake:79), `RENDERER_GL1_BINARY` (cmake/renderer_gl1.cmake:46), `RENDERER_GL2_BINARY`
/// (cmake/renderer_gl2.cmake:78) and the `baseq3` game modules (cmake/basegame.cmake:139-155).
pub const Product = enum { server, client, renderer_opengl1, renderer_opengl2, cgame, qagame, ui };

/// Every source of `product` for `config`, in the order of its CMake link line. `renderer_opengl2`
/// lists each GLSL file where CMake links the C source generated from it (see `isShader`).
pub fn productSources(arena: std.mem.Allocator, product: Product, config: Config) error{OutOfMemory}![]const []const u8 {
    var paths: std.ArrayList([]const u8) = .empty;
    switch (product) {
        .server => try paths.appendSlice(arena, &lists.server_binary_sources),
        .client => try appendClientSources(arena, &paths, config),
        .renderer_opengl1 => try appendRendererSources(arena, &paths, &lists.renderer_gl1_sources, &.{}),
        .renderer_opengl2 => try appendRendererSources(arena, &paths, &lists.renderer_gl2_sources, try shaderPaths(arena)),
        .cgame => try appendGameModuleSources(arena, &paths, &lists.cgame_sources, &lists.cgame_binary_sources),
        .qagame => try appendGameModuleSources(arena, &paths, &lists.game_sources, &lists.game_binary_sources),
        .ui => try appendGameModuleSources(arena, &paths, &lists.ui_sources, &lists.ui_binary_sources),
    }
    return paths.items;
}

/// `CLIENT_BINARY_SOURCES`, cmake/client.cmake:69-77. `CLIENT_PLATFORM_SOURCES` ends `CLIENT_SOURCES`
/// (client.cmake:39); `CLIENT_ASM_SOURCES` is never set; `CLIENT_LIBRARY_SOURCES` collects the internal
/// libraries in the include order of cmake/libraries/all.cmake:10-18.
fn appendClientSources(arena: std.mem.Allocator, paths: *std.ArrayList([]const u8), config: Config) error{OutOfMemory}!void {
    try paths.appendSlice(arena, &(lists.server_sources ++ lists.client_sources));
    if (config.use_http) try paths.appendSlice(arena, &lists.http_sources); // cmake/platforms/unix.cmake:15-17
    try paths.appendSlice(arena, &(lists.common_sources ++ lists.botlib_sources ++ lists.system_sources ++
        lists.unix_system_sources ++ lists.asm_sources));
    if (config.use_codec_vorbis) try paths.appendSlice(arena, &lists.ogg_sources); // ogg.cmake:1-3, :17
    if (config.use_codec_opus) try paths.appendSlice(arena, &(lists.opus_sources ++ lists.opusfile_sources)); // opus.cmake:1-3, :22
    if (config.use_codec_vorbis) try paths.appendSlice(arena, &lists.vorbis_sources); // vorbis.cmake:1-3, :17
    try paths.appendSlice(arena, &lists.zlib_sources); // zlib.cmake:12
}

/// `RENDERER_GL1_BINARY_SOURCES` / `RENDERER_GL2_BINARY_SOURCES` with `USE_RENDERER_DLOPEN`:
/// renderer_gl1.cmake:37-44, renderer_gl2.cmake:68-76 (the internal jpeg is `RENDERER_LIBRARY_SOURCES`).
fn appendRendererSources(arena: std.mem.Allocator, paths: *std.ArrayList([]const u8), renderer: []const []const u8, shaders: []const []const u8) error{OutOfMemory}!void {
    try paths.appendSlice(arena, &lists.renderer_common_sources);
    try paths.appendSlice(arena, renderer);
    try paths.appendSlice(arena, shaders);
    try paths.appendSlice(arena, &(lists.sdl_renderer_sources ++ lists.jpeg_sources ++ lists.dynamic_renderer_sources));
}

/// `<MODULE>_SOURCES_BASEGAME` then `<MODULE>_BINARY_SOURCES`, cmake/basegame.cmake:126-128, :139-151.
fn appendGameModuleSources(arena: std.mem.Allocator, paths: *std.ArrayList([]const u8), module: []const []const u8, binary: []const []const u8) error{OutOfMemory}!void {
    try paths.appendSlice(arena, module);
    try paths.appendSlice(arena, &lists.game_module_shared_sources);
    try paths.appendSlice(arena, binary);
}

/// The checkout include directories of `product` for `config`, in the order of the reference `C_INCLUDES`
/// (`<TARGET>_INCLUDE_DIRS` collected in the include order of cmake/libraries/all.cmake:10-18). Host
/// libraries (SDL2, FreeType) are system include directories resolved by `productSystemLibraries`.
pub fn productIncludeDirs(arena: std.mem.Allocator, product: Product, config: Config) error{OutOfMemory}![]const []const u8 {
    var dirs: std.ArrayList([]const u8) = .empty;
    switch (product) {
        .server => try dirs.append(arena, lists.zlib_dir), // zlib.cmake:9, :18
        .client => {
            if (config.use_http) try dirs.appendSlice(arena, &lists.curl_include_dirs); // curl.cmake:19
            if (config.use_codec_vorbis) try dirs.appendSlice(arena, &lists.ogg_include_dirs); // ogg.cmake:24
            if (config.use_codec_opus) try dirs.appendSlice(arena, &(lists.opus_include_dirs ++ lists.opusfile_include_dirs)); // opus.cmake:30
            if (config.use_openal) try dirs.appendSlice(arena, &lists.openal_include_dirs); // openal.cmake:20
            if (config.use_codec_vorbis) try dirs.appendSlice(arena, &lists.vorbis_include_dirs); // vorbis.cmake:25
            try dirs.append(arena, lists.zlib_dir); // zlib.cmake:21
        },
        .renderer_opengl1, .renderer_opengl2 => try dirs.appendSlice(arena, &lists.jpeg_include_dirs), // jpeg.cmake:21
        .cgame, .qagame, .ui => {},
    }
    return dirs.items;
}

/// The GLSL file of each `renderer_gl2_shaders` entry.
fn shaderPaths(arena: std.mem.Allocator) error{OutOfMemory}![]const []const u8 {
    const paths = try arena.alloc([]const u8, lists.renderer_gl2_shaders.len);
    for (paths, lists.renderer_gl2_shaders) |*path, name| path.* = try std.fmt.allocPrint(arena, "{s}/{s}{s}", .{ lists.renderer_gl2_shader_dir, name, shader_extension });
    return paths;
}

const shader_extension = ".glsl";

/// Whether a `productSources` entry is a GLSL file, compiled through the generated C source.
pub fn isShader(path: []const u8) bool {
    return std.mem.endsWith(u8, path, shader_extension);
}

/// A preprocessor definition as `Module.addCMacro` takes it (`-D<name>=<value>`).
pub const Macro = struct { name: []const u8, value: []const u8 };

/// A plain CMake definition (`-DNAME`), which the C preprocessor defines as 1.
const defined = "1";

/// `BASEGAME`, cmake/identity.cmake:7: the game directory of the native modules.
pub const basegame = "baseq3";

/// The definitions of `product` for `config`: its `<TARGET>_DEFINITIONS` and CMake's `<target>_EXPORTS`
/// for shared libraries, then the global `PRODUCT_VERSION` (CMakeLists.txt:83) and `PRODUCT_DATE`
/// (:88-91), which is always defined so q_shared.h:71-73 never falls back to `__DATE__`.
pub fn productMacros(arena: std.mem.Allocator, product: Product, config: Config) error{OutOfMemory}![]const Macro {
    var names: std.ArrayList([]const u8) = .empty;
    switch (product) {
        // cmake/server.cmake:17-26; NO_GZIP from cmake/libraries/zlib.cmake:10,19 (internal zlib).
        .server => {
            try names.appendSlice(arena, &.{ "DEDICATED", "BOTLIB", "NO_GZIP" });
            if (config.build_standalone) try names.append(arena, "STANDALONE");
            if (config.use_voip) try names.append(arena, "USE_VOIP");
        },
        .client => try appendClientDefinitions(arena, &names, config),
        // cmake/platforms/linux.cmake:8, cmake/renderer_common.cmake:26-31. cmake/libraries/jpeg.cmake:22
        // appends the misspelled, empty `${JPEG_DEFINTIONS}`, so `USE_INTERNAL_JPEG` is never defined.
        .renderer_opengl1, .renderer_opengl2 => {
            try names.appendSlice(arena, &.{ "USE_ICON", "USE_RENDERER_DLOPEN", try exportsName(arena, @tagName(product)) });
            if (config.use_freetype) try names.append(arena, "BUILD_FREETYPE");
        },
        // cmake/basegame.cmake:140, :146, :152; the CMake targets are `<module>_baseq3` (:135-137).
        .cgame, .qagame, .ui => {
            const module_definition = switch (product) {
                .cgame => "CGAME",
                .qagame => "QAGAME",
                else => "UI",
            };
            try names.appendSlice(arena, &.{ module_definition, try exportsName(arena, try std.fmt.allocPrint(arena, "{t}_{s}", .{ product, basegame })) });
        },
    }
    var macros: std.ArrayList(Macro) = .empty;
    for (names.items) |name| try macros.append(arena, .{ .name = name, .value = defined });
    try macros.append(arena, .{ .name = "PRODUCT_VERSION", .value = try cString(arena, config.product_version) });
    try macros.append(arena, .{ .name = "PRODUCT_DATE", .value = try cString(arena, config.product_date) });
    return macros.items;
}

/// CMake's `DEFINE_SYMBOL` default for a shared library target: `<target>_EXPORTS`.
fn exportsName(arena: std.mem.Allocator, target: []const u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(arena, "{s}_EXPORTS", .{target});
}

/// `CLIENT_DEFINITIONS`: the libraries in the include order of cmake/libraries/all.cmake:10-18, then
/// cmake/platforms/linux.cmake:7 and cmake/client.cmake:46-67.
fn appendClientDefinitions(arena: std.mem.Allocator, names: *std.ArrayList([]const u8), config: Config) error{OutOfMemory}!void {
    // curl.cmake:1-3, :13-18 (internal headers: build/ioq3.zig never reads host curl headers).
    if (config.use_http) try names.append(arena, "USE_INTERNAL_CURL_HEADERS");
    // opus.cmake:1-3, :21, :31.
    if (config.use_codec_opus) try names.appendSlice(arena, &.{ "USE_CODEC_OPUS", "OPUS_BUILD", "HAVE_LRINTF", "FLOATING_POINT", "FLOAT_APPROX", "USE_ALLOCA" });
    // openal.cmake:1-3, :13-23 (internal headers, `USE_OPENAL_DLOPEN` fixed on).
    if (config.use_openal) try names.appendSlice(arena, &.{ "USE_INTERNAL_OPENAL_HEADERS", "USE_OPENAL", "USE_OPENAL_DLOPEN" });
    // vorbis.cmake:1-3, :26; zlib.cmake:10, :22; linux.cmake:7; client.cmake:46, :52-54 (dlopen renderers).
    if (config.use_codec_vorbis) try names.append(arena, "USE_CODEC_VORBIS");
    try names.appendSlice(arena, &.{ "NO_GZIP", "USE_ICON", "BOTLIB", "USE_RENDERER_DLOPEN" });
    // client.cmake:48-50, :56-67.
    if (config.build_standalone) try names.append(arena, "STANDALONE");
    if (config.use_http) try names.append(arena, "USE_HTTP");
    if (config.use_voip) try names.append(arena, "USE_VOIP");
    if (config.use_mumble) try names.append(arena, "USE_MUMBLE");
}

/// Sources CMake compiles with `-w` appended: `disable_warnings` calls in cmake/shared_sources.cmake:34-37,
/// cmake/libraries/zlib.cmake:8, jpeg.cmake:12, ogg.cmake:15, opus.cmake:18 and vorbis.cmake:15
/// (utils/disable_warnings.cmake:14).
pub const quiet_sources = [_][]const u8{ "code/qcommon/unzip.c", "code/qcommon/ioapi.c" } ++ lists.zlib_sources ++
    lists.jpeg_sources ++ lists.ogg_sources ++ lists.opus_sources ++ lists.opusfile_sources ++ lists.vorbis_sources;

/// Whether `path` is one of `quiet_sources`.
pub fn isQuiet(path: []const u8) bool {
    for (quiet_sources) |quiet| if (std.mem.eql(u8, quiet, path)) return true;
    return false;
}

/// Every option combination the reference CMake build accepts but cannot compile, each message naming
/// both options (BUILD-ioq3.md, "Step 8 options"). Only client steps check them.
pub fn optionConflicts(arena: std.mem.Allocator, config: Config) error{OutOfMemory}![]const []const u8 {
    var conflicts: std.ArrayList([]const u8) = .empty;
    if (config.use_voip and !config.use_codec_opus) try conflicts.append(arena, "-DUSE_VOIP=true needs -DUSE_CODEC_OPUS=true: " ++
        "code/client/client.h:37-38 includes <opus.h> under USE_VOIP, and only USE_CODEC_OPUS compiles opus (cmake/libraries/opus.cmake:1-3)");
    if (config.use_codec_opus and !config.use_codec_vorbis) try conflicts.append(arena, "-DUSE_CODEC_OPUS=true needs -DUSE_CODEC_VORBIS=true: " ++
        "opusfile.h:109 includes <ogg/ogg.h>, and only USE_CODEC_VORBIS compiles libogg (cmake/libraries/ogg.cmake:1-3)");
    return conflicts.items;
}

/// A host library resolved through pkg-config the way CMake's package configuration does: headers in
/// `<includedir>/<include_subdir>`, the library in `<libdir>`, linked by name (BUILD-ioq3.md, "SDL2").
pub const SystemLibrary = struct {
    /// The pkg-config package.
    package: []const u8,
    /// The directory below the package's `includedir` that holds its headers.
    include_subdir: []const u8,
    /// The `-l` name.
    link_name: []const u8,
};

/// SDL2, `find_package(SDL2 REQUIRED)` in cmake/libraries/sdl.cmake:56.
pub const sdl2: SystemLibrary = .{ .package = "sdl2", .include_subdir = "SDL2", .link_name = "SDL2" };

/// FreeType, `find_package(Freetype REQUIRED)` in cmake/libraries/freetype.cmake:9.
pub const freetype: SystemLibrary = .{ .package = "freetype2", .include_subdir = "freetype2", .link_name = "freetype" };

/// The host libraries of `product`, in reference link order: `CLIENT_LIBRARIES` (sdl.cmake:59) and
/// `RENDERER_LIBRARIES` (freetype.cmake:12, then sdl.cmake:62).
pub fn productSystemLibraries(arena: std.mem.Allocator, product: Product, config: Config) error{OutOfMemory}![]const SystemLibrary {
    var libraries: std.ArrayList(SystemLibrary) = .empty;
    switch (product) {
        .client => try libraries.append(arena, sdl2),
        .renderer_opengl1, .renderer_opengl2 => {
            if (config.use_freetype) try libraries.append(arena, freetype);
            try libraries.append(arena, sdl2);
        },
        .server, .cgame, .qagame, .ui => {},
    }
    return libraries.items;
}

/// The directory `pkg-config --variable=<dir>` printed, or null unless it is one absolute path.
pub fn pkgConfigDirectory(stdout: []const u8) ?[]const u8 {
    const path = std.mem.trim(u8, stdout, &std.ascii.whitespace);
    if (path.len == 0 or !std.fs.path.isAbsolute(path)) return null;
    return path;
}

/// The target matrix, `x86_64-linux-gnu` only (SPEC R1 and Non-goals).
pub const target_matrix = "x86_64-linux-gnu";

/// Whether a target is in `target_matrix`.
pub fn inTargetMatrix(arch: std.Target.Cpu.Arch, os: std.Target.Os.Tag, abi: std.Target.Abi) bool {
    return arch == .x86_64 and os == .linux and abi == .gnu;
}

/// `text` as a C string literal: quoted, with `\` and `"` escaped.
fn cString(arena: std.mem.Allocator, text: []const u8) error{OutOfMemory}![]const u8 {
    var literal: std.ArrayList(u8) = .empty;
    try literal.append(arena, '"');
    for (text) |char| {
        if (char == '\\' or char == '"') try literal.append(arena, '\\');
        try literal.append(arena, char);
    }
    try literal.append(arena, '"');
    return literal.items;
}
