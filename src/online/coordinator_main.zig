// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const authority = @import("coordinator.zig");
const Coordinator = authority.Coordinator;
var connections = std.atomic.Value(usize).init(0);
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if ((args.len != 2 and args.len != 4) or std.mem.eql(u8, args[1], "--help")) {
        var buf: [1024]u8 = undefined;
        var out = std.Io.File.stdout().writer(init.io, &buf);
        try out.interface.writeAll("usage: dk3-coordinator CONFIG.json [backup NEW_DATABASE]\nBackend binds loopback; expose through the supplied HTTPS proxy configuration.\n");
        try out.interface.flush();
        return;
    }
    const data = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .limited(65536));
    const config = (try std.json.parseFromSlice(authority.Config, a, data, .{})).value;
    if (args.len == 4) {
        if (!std.mem.eql(u8, args[2], "backup")) return error.InvalidArguments;
        // Refuse overwrite and make the snapshot private even with a loose umask.
        const destination = try std.Io.Dir.cwd().createFile(init.io, args[3], .{ .exclusive = true, .permissions = @enumFromInt(0o600) });
        defer destination.close(init.io);
        errdefer std.Io.Dir.cwd().deleteFile(init.io, args[3]) catch {};
        var source = try Coordinator.init(config, a);
        defer source.deinit();
        try source.store.backup(try a.dupeZ(u8, args[3]));
        try destination.sync(init.io);
        return;
    }
    const address = try std.Io.net.IpAddress.parseLiteral(config.bind);
    switch (address) {
        .ip4 => |ip| if (ip.bytes[0] != 127) return error.BackendMustBindLoopback,
        .ip6 => |ip| {
            const loopback = try std.Io.net.IpAddress.parse("::1", 0);
            if (!std.mem.eql(u8, &ip.bytes, &loopback.ip6.bytes)) return error.BackendMustBindLoopback;
        },
    }
    var coordinator = try Coordinator.init(config, a);
    defer coordinator.deinit();
    var listener = try address.listen(init.io, .{ .reuse_address = true });
    defer listener.deinit(init.io);
    var group: std.Io.Group = .init;
    defer group.cancel(init.io);
    while (true) {
        const stream = try listener.accept(init.io);
        if (connections.fetchAdd(1, .monotonic) >= 64) {
            _ = connections.fetchSub(1, .monotonic);
            stream.close(init.io);
            continue;
        }
        group.concurrent(init.io, serve, .{ &coordinator, init.io, stream }) catch {
            _ = connections.fetchSub(1, .monotonic);
            stream.close(init.io);
        };
    }
}
fn serve(coordinator: *Coordinator, io: std.Io, stream: std.Io.net.Stream) void {
    defer _ = connections.fetchSub(1, .monotonic);
    defer stream.close(io);
    serveRequest(coordinator, io, stream) catch {};
}
fn serveRequest(coordinator: *Coordinator, io: std.Io, stream: std.Io.net.Stream) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var read_buffer: [16384]u8 = undefined;
    var write_buffer: [8192]u8 = undefined;
    var reader = stream.reader(io, &read_buffer);
    var writer = stream.writer(io, &write_buffer);
    var server = std.http.Server.init(&reader.interface, &writer.interface);
    var request = try server.receiveHead();
    const path = try a.dupe(u8, request.head.target);
    const method = request.head.method;
    var bearer: []const u8 = "";
    var address: []const u8 = "loopback";
    var headers = request.iterateHeaders();
    while (headers.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "authorization") and std.mem.startsWith(u8, header.value, "Bearer ")) bearer = try a.dupe(u8, header.value[7..]);
        // Only the loopback reverse proxy can supply this header.
        if (std.ascii.eqlIgnoreCase(header.name, "x-real-ip")) address = try a.dupe(u8, header.value);
    }
    if (request.head.content_length) |length| if (length > 65536) {
        try request.respond("{\"code\":\"InvalidLength\"}", .{ .status = .payload_too_large, .keep_alive = false });
        return;
    };
    var body_buffer: [4096]u8 = undefined;
    const body_reader = try request.readerExpectContinue(&body_buffer);
    const body = try body_reader.allocRemaining(a, .limited(65536));
    const result = coordinator.handle(io, a, method, path, bearer, address, body);
    try request.respond(result.body, .{ .status = result.status, .keep_alive = false, .extra_headers = &.{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "cache-control", .value = "no-store" },
        .{ .name = "x-content-type-options", .value = "nosniff" },
    } });
}
