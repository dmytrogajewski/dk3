//! ioquake3 source lists as data, relative to the checkout root, in CMake order (specs/build/BUILD-ioq3.md).
//! `${SOURCE_DIR}` is `code` (CMakeLists.txt:93). Globs of the CMake files are resolved against the
//! checkout into fixed lists; build/ioq3.zig checks every entry exists before compiling.
// FRD: specs/frds/FRD-007-ioquake3-dedicated-server-built-by-zig-build.md
// FRD: specs/frds/FRD-008-ioquake3-client-renderers-and-game-modules-built-by-zig-build.md

/// `SERVER_SOURCES`, cmake/shared_sources.cmake:48-58.
pub const server_sources = [_][]const u8{
    "code/server/sv_bot.c",      "code/server/sv_client.c",   "code/server/sv_ccmds.c",
    "code/server/sv_game.c",     "code/server/sv_init.c",     "code/server/sv_main.c",
    "code/server/sv_net_chan.c", "code/server/sv_snapshot.c", "code/server/sv_world.c",
};

/// `NULL_SOURCES`, cmake/server.cmake:9-13.
pub const null_sources = [_][]const u8{ "code/null/null_client.c", "code/null/null_input.c", "code/null/null_snddma.c" };

/// `COMMON_SOURCES`, cmake/shared_sources.cmake:6-32.
pub const common_sources = [_][]const u8{
    "code/qcommon/cm_load.c",        "code/qcommon/cm_patch.c",   "code/qcommon/cm_polylib.c",
    "code/qcommon/cm_test.c",        "code/qcommon/cm_trace.c",   "code/qcommon/cmd.c",
    "code/qcommon/common.c",         "code/qcommon/cvar.c",       "code/qcommon/files.c",
    "code/qcommon/md4.c",            "code/qcommon/md5.c",        "code/qcommon/msg.c",
    "code/qcommon/net_chan.c",       "code/qcommon/net_ip.c",     "code/qcommon/huffman.c",
    "code/qcommon/q_math.c",         "code/qcommon/q_shared.c",   "code/qcommon/unzip.c",
    "code/qcommon/ioapi.c",          "code/qcommon/vm.c",         "code/qcommon/vm_armv7l.c",
    "code/qcommon/vm_interpreted.c", "code/qcommon/vm_powerpc.c", "code/qcommon/vm_sparc.c",
    "code/qcommon/vm_x86.c",
};

/// `BOTLIB_SOURCES`, cmake/shared_sources.cmake:60-89.
pub const botlib_sources = [_][]const u8{
    "code/botlib/be_aas_bspq3.c",  "code/botlib/be_aas_cluster.c",  "code/botlib/be_aas_debug.c",
    "code/botlib/be_aas_entity.c", "code/botlib/be_aas_file.c",     "code/botlib/be_aas_main.c",
    "code/botlib/be_aas_move.c",   "code/botlib/be_aas_optimize.c", "code/botlib/be_aas_reach.c",
    "code/botlib/be_aas_route.c",  "code/botlib/be_aas_routealt.c", "code/botlib/be_aas_sample.c",
    "code/botlib/be_ai_char.c",    "code/botlib/be_ai_chat.c",      "code/botlib/be_ai_gen.c",
    "code/botlib/be_ai_goal.c",    "code/botlib/be_ai_move.c",      "code/botlib/be_ai_weap.c",
    "code/botlib/be_ai_weight.c",  "code/botlib/be_ea.c",           "code/botlib/be_interface.c",
    "code/botlib/l_crc.c",         "code/botlib/l_libvar.c",        "code/botlib/l_log.c",
    "code/botlib/l_memory.c",      "code/botlib/l_precomp.c",       "code/botlib/l_script.c",
    "code/botlib/l_struct.c",
};

/// `SYSTEM_SOURCES` without `${SYSTEM_PLATFORM_SOURCES}`, cmake/shared_sources.cmake:41-46.
pub const system_sources = [_][]const u8{ "code/sys/con_log.c", "code/sys/sys_autoupdater.c", "code/sys/sys_main.c" };

/// `SYSTEM_PLATFORM_SOURCES` on Linux, cmake/platforms/unix.cmake:7 and :12 (not Emscripten).
pub const unix_system_sources = [_][]const u8{ "code/sys/sys_unix.c", "code/sys/con_tty.c" };

/// `ASM_SOURCES` for GCC and Clang, cmake/compilers/gnu.cmake:9-12.
pub const asm_sources = [_][]const u8{ "code/asm/ftola.c", "code/asm/snapvector.c" };

/// `ZLIB_SOURCES`, cmake/libraries/zlib.cmake:7 (`file(GLOB_RECURSE ${INTERNAL_ZLIB_DIR}/*.c)`),
/// resolved against the checkout: `zlib-${ZLIB_VERSION}` with `ZLIB_VERSION=1.3.1` from
/// misc/lib-versions.sh, read by cmake/libraries/all.cmake:2-8.
pub const zlib_sources = [_][]const u8{
    zlib_dir ++ "/adler32.c", zlib_dir ++ "/crc32.c",    zlib_dir ++ "/inffast.c",
    zlib_dir ++ "/inflate.c", zlib_dir ++ "/inftrees.c", zlib_dir ++ "/zutil.c",
};

/// `INTERNAL_ZLIB_DIR`, cmake/libraries/zlib.cmake:4; also the server include directory (:9, :18).
pub const zlib_dir = "code/thirdparty/zlib-1.3.1";

/// `SERVER_BINARY_SOURCES`, cmake/server.cmake:28-36 (`SERVER_PLATFORM_SOURCES` is Windows-only,
/// cmake/platforms/windows.cmake:13; `SERVER_LIBRARY_SOURCES` is the internal zlib, zlib.cmake:11).
pub const server_binary_sources = server_sources ++ null_sources ++ common_sources ++ botlib_sources ++
    system_sources ++ unix_system_sources ++ asm_sources ++ zlib_sources;

/// `CLIENT_SOURCES`, cmake/client.cmake:11-40 (`${CLIENT_PLATFORM_SOURCES}` at :39 is `http_sources`).
/// `libmumblelink.c` stays at this position only: client.cmake:66 appends it again with `USE_MUMBLE`,
/// and CMake keeps the first occurrence of a target source (266 objects, no repeat, on the reference link line).
pub const client_sources = [_][]const u8{
    "code/client/cl_cgame.c",
    "code/client/cl_cin.c",
    "code/client/cl_console.c",
    "code/client/cl_input.c",
    "code/client/cl_keys.c",
    "code/client/cl_main.c",
    "code/client/cl_net_chan.c",
    "code/client/cl_parse.c",
    "code/client/cl_scrn.c",
    "code/client/cl_ui.c",
    "code/client/cl_avi.c",
    "code/client/libmumblelink.c",
    "code/client/snd_altivec.c",
    "code/client/snd_adpcm.c",
    "code/client/snd_dma.c",
    "code/client/snd_mem.c",
    "code/client/snd_mix.c",
    "code/client/snd_wavelet.c",
    "code/client/snd_main.c",
    "code/client/snd_codec.c",
    "code/client/snd_codec_wav.c",
    "code/client/snd_codec_ogg.c",
    "code/client/snd_codec_opus.c",
    "code/client/qal.c",
    "code/client/snd_openal.c",
    "code/sdl/sdl_input.c",
    "code/sdl/sdl_snd.c",
};

/// `CLIENT_PLATFORM_SOURCES` on Linux with `USE_HTTP`, cmake/platforms/unix.cmake:15-17.
pub const http_sources = [_][]const u8{
    "code/client/cl_http_curl.c",
};

/// `RENDERER_COMMON_SOURCES`, cmake/renderer_common.cmake:3-13.
pub const renderer_common_sources = [_][]const u8{
    "code/renderercommon/tr_font.c",
    "code/renderercommon/tr_image_bmp.c",
    "code/renderercommon/tr_image_jpg.c",
    "code/renderercommon/tr_image_pcx.c",
    "code/renderercommon/tr_image_png.c",
    "code/renderercommon/tr_image_pvr.c",
    "code/renderercommon/tr_image_tga.c",
    "code/renderercommon/tr_noise.c",
    "code/renderercommon/puff.c",
};

/// `SDL_RENDERER_SOURCES`, cmake/renderer_common.cmake:15-18.
pub const sdl_renderer_sources = [_][]const u8{
    "code/sdl/sdl_gamma.c",
    "code/sdl/sdl_glimp.c",
};

/// `DYNAMIC_RENDERER_SOURCES`, cmake/renderer_common.cmake:20-24.
pub const dynamic_renderer_sources = [_][]const u8{
    "code/renderercommon/tr_subs.c",
    "code/qcommon/q_shared.c",
    "code/qcommon/q_math.c",
};

/// `RENDERER_GL1_SOURCES`, cmake/renderer_gl1.cmake:8-32.
pub const renderer_gl1_sources = [_][]const u8{
    "code/renderergl1/tr_altivec.c",
    "code/renderergl1/tr_animation.c",
    "code/renderergl1/tr_backend.c",
    "code/renderergl1/tr_bloom.c",
    "code/renderergl1/tr_bsp.c",
    "code/renderergl1/tr_cmds.c",
    "code/renderergl1/tr_curve.c",
    "code/renderergl1/tr_flares.c",
    "code/renderergl1/tr_image.c",
    "code/renderergl1/tr_init.c",
    "code/renderergl1/tr_light.c",
    "code/renderergl1/tr_main.c",
    "code/renderergl1/tr_marks.c",
    "code/renderergl1/tr_mesh.c",
    "code/renderergl1/tr_model.c",
    "code/renderergl1/tr_model_iqm.c",
    "code/renderergl1/tr_scene.c",
    "code/renderergl1/tr_shade.c",
    "code/renderergl1/tr_shade_calc.c",
    "code/renderergl1/tr_shader.c",
    "code/renderergl1/tr_shadows.c",
    "code/renderergl1/tr_sky.c",
    "code/renderergl1/tr_surface.c",
    "code/renderergl1/tr_world.c",
};

/// `RENDERER_GL2_SOURCES`, cmake/renderer_gl2.cmake:8-39.
pub const renderer_gl2_sources = [_][]const u8{
    "code/renderergl2/tr_animation.c",
    "code/renderergl2/tr_backend.c",
    "code/renderergl2/tr_bsp.c",
    "code/renderergl2/tr_cmds.c",
    "code/renderergl2/tr_curve.c",
    "code/renderergl2/tr_dsa.c",
    "code/renderergl2/tr_extramath.c",
    "code/renderergl2/tr_extensions.c",
    "code/renderergl2/tr_fbo.c",
    "code/renderergl2/tr_flares.c",
    "code/renderergl2/tr_glsl.c",
    "code/renderergl2/tr_image.c",
    "code/renderergl2/tr_image_dds.c",
    "code/renderergl2/tr_init.c",
    "code/renderergl2/tr_light.c",
    "code/renderergl2/tr_main.c",
    "code/renderergl2/tr_marks.c",
    "code/renderergl2/tr_mesh.c",
    "code/renderergl2/tr_model.c",
    "code/renderergl2/tr_model_iqm.c",
    "code/renderergl2/tr_postprocess.c",
    "code/renderergl2/tr_scene.c",
    "code/renderergl2/tr_shade.c",
    "code/renderergl2/tr_shade_calc.c",
    "code/renderergl2/tr_shader.c",
    "code/renderergl2/tr_shadows.c",
    "code/renderergl2/tr_sky.c",
    "code/renderergl2/tr_surface.c",
    "code/renderergl2/tr_vbo.c",
    "code/renderergl2/tr_world.c",
};

/// `CGAME_SOURCES`, cmake/basegame.cmake:8-32.
pub const cgame_sources = [_][]const u8{
    "code/cgame/cg_main.c",
    "code/game/bg_misc.c",
    "code/game/bg_pmove.c",
    "code/game/bg_slidemove.c",
    "code/game/bg_lib.c",
    "code/cgame/cg_consolecmds.c",
    "code/cgame/cg_draw.c",
    "code/cgame/cg_drawtools.c",
    "code/cgame/cg_effects.c",
    "code/cgame/cg_ents.c",
    "code/cgame/cg_event.c",
    "code/cgame/cg_info.c",
    "code/cgame/cg_localents.c",
    "code/cgame/cg_marks.c",
    "code/cgame/cg_particles.c",
    "code/cgame/cg_players.c",
    "code/cgame/cg_playerstate.c",
    "code/cgame/cg_predict.c",
    "code/cgame/cg_scoreboard.c",
    "code/cgame/cg_servercmds.c",
    "code/cgame/cg_snapshot.c",
    "code/cgame/cg_view.c",
    "code/cgame/cg_weapons.c",
};

/// `GAME_SOURCES`, cmake/basegame.cmake:37-69.
pub const game_sources = [_][]const u8{
    "code/game/g_main.c",
    "code/game/ai_chat.c",
    "code/game/ai_cmd.c",
    "code/game/ai_dmnet.c",
    "code/game/ai_dmq3.c",
    "code/game/ai_main.c",
    "code/game/ai_team.c",
    "code/game/ai_vcmd.c",
    "code/game/bg_misc.c",
    "code/game/bg_pmove.c",
    "code/game/bg_slidemove.c",
    "code/game/bg_lib.c",
    "code/game/g_active.c",
    "code/game/g_arenas.c",
    "code/game/g_bot.c",
    "code/game/g_client.c",
    "code/game/g_cmds.c",
    "code/game/g_combat.c",
    "code/game/g_items.c",
    "code/game/g_mem.c",
    "code/game/g_misc.c",
    "code/game/g_missile.c",
    "code/game/g_mover.c",
    "code/game/g_session.c",
    "code/game/g_spawn.c",
    "code/game/g_svcmds.c",
    "code/game/g_target.c",
    "code/game/g_team.c",
    "code/game/g_trigger.c",
    "code/game/g_utils.c",
    "code/game/g_weapon.c",
};

/// `UI_SOURCES`, cmake/basegame.cmake:74-116.
pub const ui_sources = [_][]const u8{
    "code/q3_ui/ui_main.c",
    "code/game/bg_misc.c",
    "code/game/bg_lib.c",
    "code/q3_ui/ui_addbots.c",
    "code/q3_ui/ui_atoms.c",
    "code/q3_ui/ui_cdkey.c",
    "code/q3_ui/ui_cinematics.c",
    "code/q3_ui/ui_confirm.c",
    "code/q3_ui/ui_connect.c",
    "code/q3_ui/ui_controls2.c",
    "code/q3_ui/ui_credits.c",
    "code/q3_ui/ui_demo2.c",
    "code/q3_ui/ui_display.c",
    "code/q3_ui/ui_gameinfo.c",
    "code/q3_ui/ui_ingame.c",
    "code/q3_ui/ui_loadconfig.c",
    "code/q3_ui/ui_menu.c",
    "code/q3_ui/ui_mfield.c",
    "code/q3_ui/ui_mods.c",
    "code/q3_ui/ui_network.c",
    "code/q3_ui/ui_options.c",
    "code/q3_ui/ui_playermodel.c",
    "code/q3_ui/ui_players.c",
    "code/q3_ui/ui_playersettings.c",
    "code/q3_ui/ui_preferences.c",
    "code/q3_ui/ui_qmenu.c",
    "code/q3_ui/ui_removebots.c",
    "code/q3_ui/ui_saveconfig.c",
    "code/q3_ui/ui_serverinfo.c",
    "code/q3_ui/ui_servers2.c",
    "code/q3_ui/ui_setup.c",
    "code/q3_ui/ui_sound.c",
    "code/q3_ui/ui_sparena.c",
    "code/q3_ui/ui_specifyserver.c",
    "code/q3_ui/ui_splevel.c",
    "code/q3_ui/ui_sppostgame.c",
    "code/q3_ui/ui_spskill.c",
    "code/q3_ui/ui_startserver.c",
    "code/q3_ui/ui_team.c",
    "code/q3_ui/ui_teamorders.c",
    "code/q3_ui/ui_video.c",
};

/// `GAME_MODULE_SHARED_SOURCES`, cmake/basegame.cmake:121-124.
pub const game_module_shared_sources = [_][]const u8{
    "code/qcommon/q_math.c",
    "code/qcommon/q_shared.c",
};

/// `RENDERER_GL2_SHADER_SOURCES`, cmake/renderer_gl2.cmake:41 (`file(GLOB ${SOURCE_DIR}/renderergl2/glsl/*.glsl)`),
/// as shader names in glob order; each `<name>.glsl` becomes `<name>.c` (:46-63).
pub const renderer_gl2_shaders = [_][]const u8{
    "bokeh_fp",
    "bokeh_vp",
    "calclevels4x_fp",
    "calclevels4x_vp",
    "depthblur_fp",
    "depthblur_vp",
    "dlight_fp",
    "dlight_vp",
    "down4x_fp",
    "down4x_vp",
    "fogpass_fp",
    "fogpass_vp",
    "generic_fp",
    "generic_vp",
    "greyscale_fp",
    "greyscale_vp",
    "lightall_fp",
    "lightall_vp",
    "pshadow_fp",
    "pshadow_vp",
    "shadowfill_fp",
    "shadowfill_vp",
    "shadowmask_fp",
    "shadowmask_vp",
    "ssao_fp",
    "ssao_vp",
    "texturecolor_fp",
    "texturecolor_vp",
    "tonemap_fp",
    "tonemap_vp",
};

/// Directory of `renderer_gl2_shaders`.
pub const renderer_gl2_shader_dir = "code/renderergl2/glsl";

/// `JPEG` library directory; the version comes from misc/lib-versions.sh (cmake/libraries/all.cmake:2-8).
pub const jpeg_dir = "code/thirdparty/jpeg-9f";

/// Resolved glob of cmake/libraries/jpeg.cmake:11 (`file(GLOB_RECURSE ${INTERNAL_JPEG_DIR}/j*.c)`), directory :8, in CMake's sorted glob order.
pub const jpeg_sources = [_][]const u8{
    jpeg_dir ++ "/jaricom.c",
    jpeg_dir ++ "/jcapimin.c",
    jpeg_dir ++ "/jcapistd.c",
    jpeg_dir ++ "/jcarith.c",
    jpeg_dir ++ "/jccoefct.c",
    jpeg_dir ++ "/jccolor.c",
    jpeg_dir ++ "/jcdctmgr.c",
    jpeg_dir ++ "/jchuff.c",
    jpeg_dir ++ "/jcinit.c",
    jpeg_dir ++ "/jcmainct.c",
    jpeg_dir ++ "/jcmarker.c",
    jpeg_dir ++ "/jcmaster.c",
    jpeg_dir ++ "/jcomapi.c",
    jpeg_dir ++ "/jcparam.c",
    jpeg_dir ++ "/jcprepct.c",
    jpeg_dir ++ "/jcsample.c",
    jpeg_dir ++ "/jctrans.c",
    jpeg_dir ++ "/jdapimin.c",
    jpeg_dir ++ "/jdapistd.c",
    jpeg_dir ++ "/jdarith.c",
    jpeg_dir ++ "/jdatadst.c",
    jpeg_dir ++ "/jdatasrc.c",
    jpeg_dir ++ "/jdcoefct.c",
    jpeg_dir ++ "/jdcolor.c",
    jpeg_dir ++ "/jddctmgr.c",
    jpeg_dir ++ "/jdhuff.c",
    jpeg_dir ++ "/jdinput.c",
    jpeg_dir ++ "/jdmainct.c",
    jpeg_dir ++ "/jdmarker.c",
    jpeg_dir ++ "/jdmaster.c",
    jpeg_dir ++ "/jdmerge.c",
    jpeg_dir ++ "/jdpostct.c",
    jpeg_dir ++ "/jdsample.c",
    jpeg_dir ++ "/jdtrans.c",
    jpeg_dir ++ "/jerror.c",
    jpeg_dir ++ "/jfdctflt.c",
    jpeg_dir ++ "/jfdctfst.c",
    jpeg_dir ++ "/jfdctint.c",
    jpeg_dir ++ "/jidctflt.c",
    jpeg_dir ++ "/jidctfst.c",
    jpeg_dir ++ "/jidctint.c",
    jpeg_dir ++ "/jmemmgr.c",
    jpeg_dir ++ "/jmemnobs.c",
    jpeg_dir ++ "/jquant1.c",
    jpeg_dir ++ "/jquant2.c",
    jpeg_dir ++ "/jutils.c",
};

/// `OGG` library directory; the version comes from misc/lib-versions.sh (cmake/libraries/all.cmake:2-8).
pub const ogg_dir = "code/thirdparty/libogg-1.3.6";

/// Resolved glob of cmake/libraries/ogg.cmake:14 (`file(GLOB_RECURSE ${INTERNAL_OGG_DIR}/*.c)`), directory :11, in CMake's sorted glob order.
pub const ogg_sources = [_][]const u8{
    ogg_dir ++ "/src/bitwise.c",
    ogg_dir ++ "/src/framing.c",
};

/// `OPUS` library directory; the version comes from misc/lib-versions.sh (cmake/libraries/all.cmake:2-8).
pub const opus_dir = "code/thirdparty/opus-1.5.2";

/// Resolved glob of cmake/libraries/opus.cmake:16 (`file(GLOB_RECURSE ${INTERNAL_OPUS_DIR}/*.c)`), directory :12, in CMake's sorted glob order.
pub const opus_sources = [_][]const u8{
    opus_dir ++ "/celt/bands.c",
    opus_dir ++ "/celt/celt.c",
    opus_dir ++ "/celt/celt_decoder.c",
    opus_dir ++ "/celt/celt_encoder.c",
    opus_dir ++ "/celt/celt_lpc.c",
    opus_dir ++ "/celt/cwrs.c",
    opus_dir ++ "/celt/entcode.c",
    opus_dir ++ "/celt/entdec.c",
    opus_dir ++ "/celt/entenc.c",
    opus_dir ++ "/celt/kiss_fft.c",
    opus_dir ++ "/celt/laplace.c",
    opus_dir ++ "/celt/mathops.c",
    opus_dir ++ "/celt/mdct.c",
    opus_dir ++ "/celt/modes.c",
    opus_dir ++ "/celt/pitch.c",
    opus_dir ++ "/celt/quant_bands.c",
    opus_dir ++ "/celt/rate.c",
    opus_dir ++ "/celt/vq.c",
    opus_dir ++ "/silk/A2NLSF.c",
    opus_dir ++ "/silk/CNG.c",
    opus_dir ++ "/silk/HP_variable_cutoff.c",
    opus_dir ++ "/silk/LPC_analysis_filter.c",
    opus_dir ++ "/silk/LPC_fit.c",
    opus_dir ++ "/silk/LPC_inv_pred_gain.c",
    opus_dir ++ "/silk/LP_variable_cutoff.c",
    opus_dir ++ "/silk/NLSF2A.c",
    opus_dir ++ "/silk/NLSF_VQ.c",
    opus_dir ++ "/silk/NLSF_VQ_weights_laroia.c",
    opus_dir ++ "/silk/NLSF_decode.c",
    opus_dir ++ "/silk/NLSF_del_dec_quant.c",
    opus_dir ++ "/silk/NLSF_encode.c",
    opus_dir ++ "/silk/NLSF_stabilize.c",
    opus_dir ++ "/silk/NLSF_unpack.c",
    opus_dir ++ "/silk/NSQ.c",
    opus_dir ++ "/silk/NSQ_del_dec.c",
    opus_dir ++ "/silk/PLC.c",
    opus_dir ++ "/silk/VAD.c",
    opus_dir ++ "/silk/VQ_WMat_EC.c",
    opus_dir ++ "/silk/ana_filt_bank_1.c",
    opus_dir ++ "/silk/biquad_alt.c",
    opus_dir ++ "/silk/bwexpander.c",
    opus_dir ++ "/silk/bwexpander_32.c",
    opus_dir ++ "/silk/check_control_input.c",
    opus_dir ++ "/silk/code_signs.c",
    opus_dir ++ "/silk/control_SNR.c",
    opus_dir ++ "/silk/control_audio_bandwidth.c",
    opus_dir ++ "/silk/control_codec.c",
    opus_dir ++ "/silk/debug.c",
    opus_dir ++ "/silk/dec_API.c",
    opus_dir ++ "/silk/decode_core.c",
    opus_dir ++ "/silk/decode_frame.c",
    opus_dir ++ "/silk/decode_indices.c",
    opus_dir ++ "/silk/decode_parameters.c",
    opus_dir ++ "/silk/decode_pitch.c",
    opus_dir ++ "/silk/decode_pulses.c",
    opus_dir ++ "/silk/decoder_set_fs.c",
    opus_dir ++ "/silk/enc_API.c",
    opus_dir ++ "/silk/encode_indices.c",
    opus_dir ++ "/silk/encode_pulses.c",
    opus_dir ++ "/silk/float/LPC_analysis_filter_FLP.c",
    opus_dir ++ "/silk/float/LPC_inv_pred_gain_FLP.c",
    opus_dir ++ "/silk/float/LTP_analysis_filter_FLP.c",
    opus_dir ++ "/silk/float/LTP_scale_ctrl_FLP.c",
    opus_dir ++ "/silk/float/apply_sine_window_FLP.c",
    opus_dir ++ "/silk/float/autocorrelation_FLP.c",
    opus_dir ++ "/silk/float/burg_modified_FLP.c",
    opus_dir ++ "/silk/float/bwexpander_FLP.c",
    opus_dir ++ "/silk/float/corrMatrix_FLP.c",
    opus_dir ++ "/silk/float/encode_frame_FLP.c",
    opus_dir ++ "/silk/float/energy_FLP.c",
    opus_dir ++ "/silk/float/find_LPC_FLP.c",
    opus_dir ++ "/silk/float/find_LTP_FLP.c",
    opus_dir ++ "/silk/float/find_pitch_lags_FLP.c",
    opus_dir ++ "/silk/float/find_pred_coefs_FLP.c",
    opus_dir ++ "/silk/float/inner_product_FLP.c",
    opus_dir ++ "/silk/float/k2a_FLP.c",
    opus_dir ++ "/silk/float/noise_shape_analysis_FLP.c",
    opus_dir ++ "/silk/float/pitch_analysis_core_FLP.c",
    opus_dir ++ "/silk/float/process_gains_FLP.c",
    opus_dir ++ "/silk/float/regularize_correlations_FLP.c",
    opus_dir ++ "/silk/float/residual_energy_FLP.c",
    opus_dir ++ "/silk/float/scale_copy_vector_FLP.c",
    opus_dir ++ "/silk/float/scale_vector_FLP.c",
    opus_dir ++ "/silk/float/schur_FLP.c",
    opus_dir ++ "/silk/float/sort_FLP.c",
    opus_dir ++ "/silk/float/warped_autocorrelation_FLP.c",
    opus_dir ++ "/silk/float/wrappers_FLP.c",
    opus_dir ++ "/silk/gain_quant.c",
    opus_dir ++ "/silk/init_decoder.c",
    opus_dir ++ "/silk/init_encoder.c",
    opus_dir ++ "/silk/inner_prod_aligned.c",
    opus_dir ++ "/silk/interpolate.c",
    opus_dir ++ "/silk/lin2log.c",
    opus_dir ++ "/silk/log2lin.c",
    opus_dir ++ "/silk/pitch_est_tables.c",
    opus_dir ++ "/silk/process_NLSFs.c",
    opus_dir ++ "/silk/quant_LTP_gains.c",
    opus_dir ++ "/silk/resampler.c",
    opus_dir ++ "/silk/resampler_down2.c",
    opus_dir ++ "/silk/resampler_down2_3.c",
    opus_dir ++ "/silk/resampler_private_AR2.c",
    opus_dir ++ "/silk/resampler_private_IIR_FIR.c",
    opus_dir ++ "/silk/resampler_private_down_FIR.c",
    opus_dir ++ "/silk/resampler_private_up2_HQ.c",
    opus_dir ++ "/silk/resampler_rom.c",
    opus_dir ++ "/silk/shell_coder.c",
    opus_dir ++ "/silk/sigm_Q15.c",
    opus_dir ++ "/silk/sort.c",
    opus_dir ++ "/silk/stereo_LR_to_MS.c",
    opus_dir ++ "/silk/stereo_MS_to_LR.c",
    opus_dir ++ "/silk/stereo_decode_pred.c",
    opus_dir ++ "/silk/stereo_encode_pred.c",
    opus_dir ++ "/silk/stereo_find_predictor.c",
    opus_dir ++ "/silk/stereo_quant_pred.c",
    opus_dir ++ "/silk/sum_sqr_shift.c",
    opus_dir ++ "/silk/table_LSF_cos.c",
    opus_dir ++ "/silk/tables_LTP.c",
    opus_dir ++ "/silk/tables_NLSF_CB_NB_MB.c",
    opus_dir ++ "/silk/tables_NLSF_CB_WB.c",
    opus_dir ++ "/silk/tables_gain.c",
    opus_dir ++ "/silk/tables_other.c",
    opus_dir ++ "/silk/tables_pitch_lag.c",
    opus_dir ++ "/silk/tables_pulses_per_block.c",
    opus_dir ++ "/src/analysis.c",
    opus_dir ++ "/src/extensions.c",
    opus_dir ++ "/src/mlp.c",
    opus_dir ++ "/src/mlp_data.c",
    opus_dir ++ "/src/opus.c",
    opus_dir ++ "/src/opus_decoder.c",
    opus_dir ++ "/src/opus_encoder.c",
    opus_dir ++ "/src/opus_multistream.c",
    opus_dir ++ "/src/opus_multistream_decoder.c",
    opus_dir ++ "/src/opus_multistream_encoder.c",
    opus_dir ++ "/src/repacketizer.c",
};

/// `OPUSFILE` library directory; the version comes from misc/lib-versions.sh (cmake/libraries/all.cmake:2-8).
pub const opusfile_dir = "code/thirdparty/opusfile-0.12";

/// Resolved glob of cmake/libraries/opus.cmake:17 (`file(GLOB_RECURSE ${INTERNAL_OPUSFILE_DIR}/*.c)`), directory :13, in CMake's sorted glob order.
pub const opusfile_sources = [_][]const u8{
    opusfile_dir ++ "/src/http.c",
    opusfile_dir ++ "/src/info.c",
    opusfile_dir ++ "/src/internal.c",
    opusfile_dir ++ "/src/opusfile.c",
    opusfile_dir ++ "/src/stream.c",
    opusfile_dir ++ "/src/wincerts.c",
};

/// `VORBIS` library directory; the version comes from misc/lib-versions.sh (cmake/libraries/all.cmake:2-8).
pub const vorbis_dir = "code/thirdparty/libvorbis-1.3.7";

/// Resolved glob of cmake/libraries/vorbis.cmake:14 (`file(GLOB_RECURSE ${INTERNAL_VORBIS_DIR}/*.c)`), directory :11, in CMake's sorted glob order.
pub const vorbis_sources = [_][]const u8{
    vorbis_dir ++ "/lib/analysis.c",
    vorbis_dir ++ "/lib/bitrate.c",
    vorbis_dir ++ "/lib/block.c",
    vorbis_dir ++ "/lib/codebook.c",
    vorbis_dir ++ "/lib/envelope.c",
    vorbis_dir ++ "/lib/floor0.c",
    vorbis_dir ++ "/lib/floor1.c",
    vorbis_dir ++ "/lib/info.c",
    vorbis_dir ++ "/lib/lookup.c",
    vorbis_dir ++ "/lib/lpc.c",
    vorbis_dir ++ "/lib/lsp.c",
    vorbis_dir ++ "/lib/mapping0.c",
    vorbis_dir ++ "/lib/mdct.c",
    vorbis_dir ++ "/lib/psy.c",
    vorbis_dir ++ "/lib/registry.c",
    vorbis_dir ++ "/lib/res0.c",
    vorbis_dir ++ "/lib/sharedbook.c",
    vorbis_dir ++ "/lib/smallft.c",
    vorbis_dir ++ "/lib/synthesis.c",
    vorbis_dir ++ "/lib/vorbisfile.c",
    vorbis_dir ++ "/lib/window.c",
};

/// `CGAME_BINARY_SOURCES`, cmake/basegame.cmake:34.
pub const cgame_binary_sources = [_][]const u8{
    "code/cgame/cg_syscalls.c",
};

/// `GAME_BINARY_SOURCES`, cmake/basegame.cmake:71.
pub const game_binary_sources = [_][]const u8{
    "code/game/g_syscalls.c",
};

/// `UI_BINARY_SOURCES`, cmake/basegame.cmake:118.
pub const ui_binary_sources = [_][]const u8{
    "code/ui/ui_syscalls.c",
};

// Include directories, relative to the checkout root, in the order of the reference `C_INCLUDES`.

/// `CURL_INCLUDE_DIRS` of the internal headers, cmake/libraries/curl.cmake:9, :15.
pub const curl_include_dirs = [_][]const u8{"code/thirdparty/curl-8.15.0/include"};

/// `OGG_INCLUDE_DIRS`, cmake/libraries/ogg.cmake:16.
pub const ogg_include_dirs = [_][]const u8{ogg_dir ++ "/include"};

/// `OPUS_INCLUDE_DIRS`: `find_include_dirs` (cmake/utils/find_include_dirs.cmake) at
/// cmake/libraries/opus.cmake:19, resolved against the checkout: every directory holding a `.h`, sorted.
pub const opus_include_dirs = [_][]const u8{ opus_dir ++ "/celt", opus_dir ++ "/include", opus_dir ++ "/silk", opus_dir ++ "/silk/float", opus_dir ++ "/src" };

/// `OPUSFILE_INCLUDE_DIRS`: `find_include_dirs` at cmake/libraries/opus.cmake:20, resolved as above.
pub const opusfile_include_dirs = [_][]const u8{ opusfile_dir ++ "/include", opusfile_dir ++ "/src" };

/// `OPENAL_INCLUDE_DIR` of the internal headers, cmake/libraries/openal.cmake:9, :15.
pub const openal_include_dirs = [_][]const u8{"code/thirdparty/openal-soft-1.24.3/include"};

/// `VORBIS_INCLUDE_DIRS`, cmake/libraries/vorbis.cmake:16.
pub const vorbis_include_dirs = [_][]const u8{ vorbis_dir ++ "/include", vorbis_dir ++ "/lib" };

/// `JPEG_INCLUDE_DIRS`: `find_include_dirs` at cmake/libraries/jpeg.cmake:13, which finds the directory itself.
pub const jpeg_include_dirs = [_][]const u8{jpeg_dir};
