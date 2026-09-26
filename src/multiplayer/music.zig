// SPDX-License-Identifier: GPL-2.0-or-later
//! Authoritative map/trigger music resolution. Published configstrings own playback.
const std = @import("std");
const c = @import("../weapons/abi.zig").c;
var map: [c.MAX_QPATH]u8 = @splat(0);
var song: [c.MAX_QPATH]u8 = @splat(0);
var warned: [32][c.MAX_QPATH]u8 = @splat(@splat(0));
var warnings: usize = 0;
fn episodeIndex() usize {
    return if (map[0] == 'e' and map[1] >= '1' and map[1] <= '4') map[1] - '1' else 0;
}
const fallbacks = [_][]const [:0]const u8{
    &.{ "music/e1a.mp3.ogg", "music/dm1_modern_muck.mp3.ogg", "music/e1b.mp3.ogg" },
    &.{ "music/e2a.mp3.ogg", "music/dm2_medusa.mp3.ogg", "music/dm2_titans.mp3.ogg" },
    &.{ "music/e3a.mp3.ogg", "music/dm3_evil.mp3.ogg", "music/dm3_death.mp3.ogg" },
    &.{ "music/e4a.mp3.ogg", "music/dm4_kick.mp3.ogg", "music/dm4_stalked.mp3.ogg" },
};
pub fn normalize(name: []const u8, output: []u8) ![:0]const u8 {
    var normalized: [c.MAX_QPATH]u8 = undefined;
    var count: usize = 0;
    for (name) |value| {
        const ch = if (value == '\\') '/' else value;
        if (ch == '/' and (count == 0 or normalized[count - 1] == '/')) continue;
        if (ch < 32 or ch == '"' or count == normalized.len) return error.InvalidPath;
        normalized[count] = ch;
        count += 1;
    }
    var text: []const u8 = normalized[0..count];
    if (std.ascii.startsWithIgnoreCase(text, "data/")) text = text[5..];
    var segments = std.mem.splitScalar(u8, text, '/');
    while (segments.next()) |segment| if (std.mem.eql(u8, segment, "..")) return error.InvalidPath;
    const prefix = if (std.ascii.startsWithIgnoreCase(text, "music/") or std.ascii.startsWithIgnoreCase(text, "sounds/")) "" else "music/";
    const extension = std.fs.path.extension(text);
    const suffix = if (extension.len == 0) ".mp3.ogg" else if (std.ascii.eqlIgnoreCase(extension, ".mp3")) ".ogg" else "";
    return std.fmt.bufPrintZ(output, "{s}{s}{s}", .{ prefix, text, suffix });
}
fn exists(path: [*:0]const u8) bool {
    return c.trap_FS_FOpenFile(path, null, c.FS_READ) > 0;
}
export fn DK_SetMusic(name: [*c]const u8) callconv(.c) void {
    if (name == null or name[0] == 0) {
        c.trap_SetConfigstring(c.CS_MUSIC, "");
        return;
    }
    var buffer: [c.MAX_QPATH]u8 = undefined;
    const desired = normalize(std.mem.span(name), &buffer) catch {
        c.G_Printf("dk3: invalid music path; playback stopped\n");
        c.trap_SetConfigstring(c.CS_MUSIC, "");
        return;
    };
    var resolved: ?[:0]const u8 = if (exists(desired)) desired else null;
    if (resolved == null) {
        for (fallbacks[episodeIndex()]) |candidate| if (exists(candidate)) {
            resolved = candidate;
            break;
        };
        var seen = false;
        for (warned[0..warnings]) |previous| if (std.mem.eql(u8, std.mem.sliceTo(&previous, 0), desired)) {
            seen = true;
            break;
        };
        if (!seen and warnings < warned.len) {
            c.Q_strncpyz(&warned[warnings], desired.ptr, c.MAX_QPATH);
            warnings += 1;
            c.G_Printf("dk3: music %s unavailable; fallback %s\n", desired.ptr, if (resolved) |path| path.ptr else @as([*:0]const u8, "silence"));
        }
    }
    if (resolved) |path| {
        var config: [c.MAX_QPATH * 2 + 2]u8 = undefined;
        const value = std.fmt.bufPrintZ(&config, "{s} {s}", .{ path, path }) catch unreachable;
        c.trap_SetConfigstring(c.CS_MUSIC, value);
        c.G_Printf("dk3: map %s music %s\n", &map, path.ptr);
    } else c.trap_SetConfigstring(c.CS_MUSIC, "");
}
fn row(record: [*c]const c.dkRecord_t) callconv(.c) void {
    // The first matching authored row wins, including an intentional empty song.
    if (matched or c.Q_stricmp(c.DK_Field(record, "mapname"), &map) != 0) return;
    matched = true;
    c.Q_strncpyz(&song, c.DK_Field(record, "song"), song.len);
}
var matched = false;
export fn DK_WorldMusic() callconv(.c) void {
    c.trap_Cvar_VariableStringBuffer("mapname", &map, map.len);
    song = @splat(0);
    matched = false;
    warnings = 0;
    c.DK_ReadTable("music", row);
    var override: [*c]u8 = null;
    _ = c.G_SpawnString("musictrack", "", &override);
    DK_SetMusic(if (override != null and override[0] != 0) override else if (matched) &song else fallbacks[episodeIndex()][0].ptr);
}
