// SPDX-License-Identifier: GPL-2.0-or-later
//! Explicit operator commands. Credentials are read from a private configuration,
//! never passed in argv or printed in diagnostics.
const std = @import("std");
const Http = @import("http.zig").Client;
const Config = struct { url: []const u8, admin_token: []const u8, ca_file: ?[]const u8 = null };
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &output.interface;
    if (args.len < 3 or args.len > 4) {
        try out.writeAll("usage: dk3-operator CONFIG.json status|audit\n       dk3-operator CONFIG.json enroll|drain|revoke|end|kick|ban REQUEST.json\n");
        try out.flush();
        return;
    }
    const data = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .limited(65536));
    const config = (try std.json.parseFromSlice(Config, a, data, .{ .ignore_unknown_fields = true })).value;
    if (config.admin_token.len < 32) return error.InvalidConfig;
    var client = try Http.init(a, init.io, config.url, config.admin_token, config.ca_file);
    defer client.deinit();
    const read = std.mem.eql(u8, args[2], "status") or std.mem.eql(u8, args[2], "audit");
    var known = read;
    for ([_][]const u8{ "enroll", "drain", "revoke", "end", "kick", "ban" }) |verb| known = known or std.mem.eql(u8, args[2], verb);
    if (!known or (read and args.len != 3) or (!read and args.len != 4)) return error.InvalidArguments;
    const path = try std.fmt.allocPrint(a, "/v1/operator/{s}", .{args[2]});
    const result = if (read) try client.get(a, std.json.Value, path) else block: {
        const request = try std.Io.Dir.cwd().readFileAlloc(init.io, args[3], a, .limited(65536));
        const value = (try std.json.parseFromSlice(std.json.Value, a, request, .{})).value;
        break :block try client.call(a, std.json.Value, path, value);
    };
    try out.print("{s}\n", .{try std.json.Stringify.valueAlloc(a, result, .{ .whitespace = .indent_2 })});
    try out.flush();
}
