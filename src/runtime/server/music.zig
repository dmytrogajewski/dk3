// SPDX-License-Identifier: GPL-2.0-or-later
//! Map-table selection and authored music changes retain their supplied paths.
const std = @import("std");
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
pub fn publish(path: []const u8, volume: f32) !void {
    if (path.len >= c.MAX_QPATH or !std.mem.startsWith(u8, path, "music/") and !std.mem.startsWith(u8, path, "music\\") or std.mem.indexOf(u8, path, "..") != null or !std.math.isFinite(volume)) return error.InvalidMusicPath;
    var clean: [c.MAX_QPATH]u8 = undefined;
    for (path, 0..) |ch, i| {
        if (ch == '"' or ch < 32 or ch == ';') return error.InvalidMusicPath;
        clean[i] = if (ch == '\\') '/' else std.ascii.toLower(ch);
    }
    var value: [128]u8 = undefined;
    engine.config(c.CS_MUSIC, try std.fmt.bufPrintZ(&value, "{s} {d:.3}", .{ clean[0..path.len], volume }));
}
pub fn restore(world: *data.World, allocator: std.mem.Allocator) !void {
    var latest: ?i64 = null;
    var selected: ?[]const u8 = null;
    var volume: f32 = 1;
    {
        var query = world.queryAccess(data.World.mask(.{data.WorldControl}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.read(data.WorldControl)) |control| switch (control.action) {
            .music => |music| if (music.changed_ms) |at| {
                if (latest == null or at >= latest.?) {
                    latest = at;
                    selected = music.path;
                    volume = music.volume;
                }
            },
            else => {},
        };
    }
    if (selected) |path| return publish(path, volume);
    var map_name: [c.MAX_QPATH]u8 = @splat(0);
    _ = engine.gateway.call(c.G_CVAR_VARIABLE_STRING_BUFFER, .{ @as([*:0]const u8, "mapname"), &map_name, @as(isize, map_name.len) });
    const bytes = try @import("../engine/files.zig").read(.server, &engine.gateway, allocator, "dk3/tables/music.cfg", 65536);
    defer allocator.free(bytes);
    var reader = try @import("../domain/tables.zig").Reader.init(bytes);
    while (try reader.next()) |row| {
        if (!std.ascii.eqlIgnoreCase(row.field("mapname") orelse "", std.mem.sliceTo(&map_name, 0))) continue;
        const song = row.field("song") orelse return error.MissingMapMusic;
        var path: [c.MAX_QPATH]u8 = undefined;
        return publish(try std.fmt.bufPrint(&path, "music/{s}.mp3", .{song}), 1);
    }
    engine.config(c.CS_MUSIC, "");
}
