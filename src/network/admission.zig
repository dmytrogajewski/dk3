// SPDX-License-Identifier: GPL-2.0-or-later
//! Managed-room tickets. Only the trusted local worker writes admission.json.
const std = @import("std");
const c = @import("abi.zig").c;
const api = @import("../online/api.zig");
const identity = @import("../online/identity.zig");
const security = @import("security.zig");
const Hmac = std.crypto.auth.hmac.sha2.HmacSha256;
const Used = struct { id: [32]u8 = @splat(0), expires: i64 = 0 };
var used: [1024]Used = @splat(.{});
var client_ticket: ?struct { id: [64:0]u8, client: security.Key, server: security.Key, expires: i64 } = null;
fn now() i64 {
    return @intCast(c.time(null));
}
fn proof(key: security.Key, id: []const u8, challenge: c_int) [64]u8 {
    var text: [160]u8 = undefined;
    const message = std.fmt.bufPrint(&text, "dk3-ticket-v1\n{s}\n{d}", .{ id, challenge }) catch unreachable;
    var mac: [32]u8 = undefined;
    Hmac.create(&mac, message, &key);
    return std.fmt.bytesToHex(mac, .lower);
}
fn secure(channel: *c.netchan_t, send: security.Key, receive: security.Key) void {
    channel.dk3Secure = c.qtrue;
    channel.dk3SendKey = send;
    channel.dk3ReceiveKey = receive;
    channel.dk3SendCounter = 1;
    channel.dk3ReceiveHighest = 0;
    channel.dk3ReceiveMask = 0;
}
fn admit(channel: *c.netchan_t, userinfo: [*c]u8) !void {
    const token = std.mem.span(c.Info_ValueForKey(userinfo, "dk3_ticket"));
    const token_bytes = try identity.hex(32, token);
    const timestamp = now();
    var free: ?*Used = null;
    for (&used) |*entry| {
        if (entry.expires <= timestamp) {
            free = entry;
            continue;
        }
        if (std.mem.eql(u8, &entry.id, &token_bytes)) return error.ReusedTicket;
    }
    if (free == null) return error.Capacity;
    const length = c.FS_ReadFile("admission.json", null);
    if (length <= 0 or length > 1024 * 1024) return error.NoAdmission;
    var data: ?*anyopaque = null;
    const read = c.FS_ReadFile("admission.json", &data);
    if (read != length or data == null) {
        if (data != null) c.FS_FreeFile(data);
        return error.NoAdmission;
    }
    defer c.FS_FreeFile(data);
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const bytes: [*]const u8 = @ptrCast(data.?);
    const tickets = try std.json.parseFromSlice([]api.Ticket, arena.allocator(), bytes[0..@intCast(length)], .{});
    for (tickets.value) |ticket| {
        if (!std.mem.eql(u8, ticket.id, token)) continue;
        if (ticket.expires <= timestamp or ticket.expires > timestamp + 60) return error.Expired;
        if (!std.mem.eql(u8, ticket.room, std.mem.span(c.Cvar_VariableString("dk3_room"))) or ticket.generation != c.Cvar_VariableIntegerValue("dk3_generation")) return error.WrongRoom;
        const client_key = try identity.hex(32, ticket.client_key);
        const server_key = try identity.hex(32, ticket.server_key);
        const supplied = try identity.hex(32, std.mem.span(c.Info_ValueForKey(userinfo, "dk3_proof")));
        const expected = try identity.hex(32, &proof(client_key, ticket.id, channel.challenge));
        if (!std.crypto.timing_safe.eql([32]u8, supplied, expected)) return error.InvalidProof;
        _ = try identity.hex(32, ticket.identity);
        @memcpy(channel.dk3Identity[0..64], ticket.identity);
        channel.dk3Identity[64] = 0;
        @memcpy(channel.dk3Ticket[0..64], ticket.id);
        channel.dk3Ticket[64] = 0;
        c.Info_SetValueForKey(userinfo, "dk3_identity", &channel.dk3Identity);
        secure(channel, server_key, client_key);
        free.?.* = .{ .id = token_bytes, .expires = ticket.expires };
        var file: c.fileHandle_t = 0;
        var receipt: [100:0]u8 = undefined;
        const receipt_path = try std.fmt.bufPrintZ(&receipt, "admission-used/{s}", .{ticket.id});
        _ = c.FS_FOpenFileByMode(receipt_path.ptr, &file, c.FS_WRITE);
        if (file != 0) {
            _ = c.FS_Write(ticket.id.ptr, @intCast(ticket.id.len), file);
            _ = c.FS_Write("\n", 1, file);
            c.FS_FCloseFile(file);
        }
        return;
    }
    return error.NoAdmission;
}
export fn DK_NetAdmit(channel: *c.netchan_t, userinfo: [*c]u8) callconv(.c) c.qboolean {
    c.Info_SetValueForKey(userinfo, "dk3_identity", "");
    if (c.Cvar_VariableIntegerValue("dk3_public") == 0) return c.qtrue;
    admit(channel, userinfo) catch return c.qfalse;
    return c.qtrue;
}
export fn DK_NetRepeat(channel: *c.netchan_t, userinfo: [*c]const u8, challenge: c_int) callconv(.c) c.qboolean {
    if (channel.dk3Secure == 0 or channel.challenge != challenge) return c.qfalse;
    const id = std.mem.sliceTo(&channel.dk3Ticket, 0);
    if (!std.mem.eql(u8, id, std.mem.span(c.Info_ValueForKey(userinfo, "dk3_ticket")))) return c.qfalse;
    const supplied = identity.hex(32, std.mem.span(c.Info_ValueForKey(userinfo, "dk3_proof"))) catch return c.qfalse;
    const expected = identity.hex(32, &proof(channel.dk3ReceiveKey, id, challenge)) catch unreachable;
    return @intFromBool(std.crypto.timing_safe.eql([32]u8, supplied, expected));
}
export fn DK_NetLoadTicket(path: [*:0]const u8) callconv(.c) c.qboolean {
    client_ticket = null;
    const length = c.FS_ReadFile(path, null);
    if (length <= 0 or length > 8192) return c.qfalse;
    var data: ?*anyopaque = null;
    if (c.FS_ReadFile(path, &data) != length or data == null) {
        if (data != null) c.FS_FreeFile(data);
        return c.qfalse;
    }
    defer c.FS_FreeFile(data);
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const bytes: [*]const u8 = @ptrCast(data.?);
    const parsed = std.json.parseFromSlice(api.Ticket, arena.allocator(), bytes[0..@intCast(length)], .{}) catch return c.qfalse;
    return installTicket(parsed.value);
}
pub fn installTicket(ticket: api.Ticket) c.qboolean {
    if (ticket.expires <= now()) return c.qfalse;
    _ = identity.hex(32, ticket.id) catch return c.qfalse;
    const client_key = identity.hex(32, ticket.client_key) catch return c.qfalse;
    const server_key = identity.hex(32, ticket.server_key) catch return c.qfalse;
    var token: [64:0]u8 = undefined;
    @memcpy(token[0..64], ticket.id);
    token[64] = 0;
    client_ticket = .{ .id = token, .client = client_key, .server = server_key, .expires = ticket.expires };
    return c.qtrue;
}
export fn DK_NetProof(userinfo: [*c]u8, challenge: c_int) callconv(.c) void {
    c.Info_SetValueForKey(userinfo, "dk3_ticket", "");
    c.Info_SetValueForKey(userinfo, "dk3_proof", "");
    if (client_ticket) |ticket| {
        if (ticket.expires <= now()) {
            client_ticket = null;
            return;
        }
        var mac: [65]u8 = undefined;
        @memcpy(mac[0..64], &proof(ticket.client, &ticket.id, challenge));
        mac[64] = 0;
        c.Info_SetValueForKey(userinfo, "dk3_ticket", &ticket.id);
        c.Info_SetValueForKey(userinfo, "dk3_proof", &mac);
    }
}
export fn DK_NetClientReady(channel: *c.netchan_t) callconv(.c) void {
    if (client_ticket) |ticket| {
        secure(channel, ticket.client, ticket.server);
        client_ticket = null;
    }
}
