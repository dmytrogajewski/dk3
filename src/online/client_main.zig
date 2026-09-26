// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const api = @import("api.zig");
const room_client = @import("client.zig");
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buffer);
    const out = &stdout.interface;
    if (args.len < 3) {
        try out.writeAll("usage: dk3-online CONFIG.json list|create ROOM.json REQUEST_ID|join ROOM_ID TICKET_PATH [ACCESS_CODE]\n");
        try out.flush();
        return;
    }
    const config_data = try std.Io.Dir.cwd().readFileAlloc(io, args[1], a, .limited(65536));
    const config = (try std.json.parseFromSlice(room_client.Config, a, config_data, .{})).value;
    var client = try room_client.Client.init(a, io, config);
    defer client.deinit();
    if (std.mem.eql(u8, args[2], "list") and args.len == 3) {
        try out.print("{s}\n", .{try std.json.Stringify.valueAlloc(a, try client.list(), .{})});
    } else if (std.mem.eql(u8, args[2], "create") and args.len == 5) {
        try client.login();
        const room_data = try std.Io.Dir.cwd().readFileAlloc(io, args[3], a, .limited(65536));
        const room = (try std.json.parseFromSlice(api.RoomConfig, a, room_data, .{})).value;
        try out.print("{s}\n", .{try std.json.Stringify.valueAlloc(a, try client.create(args[4], room), .{})});
    } else if (std.mem.eql(u8, args[2], "join") and (args.len == 5 or args.len == 6)) {
        try client.login();
        const joined = try client.join(args[3], if (args.len == 6) args[5] else "");
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[4], .data = try std.json.Stringify.valueAlloc(a, joined.ticket, .{}), .flags = .{ .permissions = @enumFromInt(0o600) } });
        // Gameplay keys stay in the private ticket file, never in console output.
        try out.print("{s}\n", .{joined.endpoint});
    } else return error.InvalidArguments;
    try out.flush();
}
