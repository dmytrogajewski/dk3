// SPDX-License-Identifier: GPL-2.0-or-later
// Derived from ioquake3 net_chan.c, Copyright (C) 1999-2005 Id Software, Inc.
//! Bounded UDP channels. Fragments may arrive out of order; no native wire structs.
const std = @import("std");
const c = @import("abi.zig").c;
const security = @import("security.zig");
const fragment_size = 1300;
const fragment_bit: u32 = 1 << 31;
extern var showpackets: [*c]c.cvar_t;
extern var showdrop: [*c]c.cvar_t;
extern var net_qport: [*c]c.cvar_t;
const Channel = c.netchan_t;
fn checksum(channel: *Channel, sequence: u32) u32 {
    const challenge: u32 = @bitCast(channel.challenge);
    return challenge ^ (sequence *% challenge);
}
fn send(channel: *Channel, bytes: []const u8) void {
    var encrypted: [1500]u8 = undefined;
    var packet = bytes;
    if (channel.dk3Secure != 0) {
        const offset: usize = if (channel.sock == c.NS_CLIENT) 10 else 8;
        var session = sessionFrom(channel);
        defer session.deinit();
        @memcpy(encrypted[0..offset], bytes[0..offset]);
        const payload = session.seal(encrypted[offset..], bytes[0..offset], bytes[offset..]) catch {
            c.Com_Error(c.ERR_DROP, "dk3: packet protection failed; reconnect");
            return;
        };
        channel.dk3SendCounter = session.next;
        packet = encrypted[0 .. offset + payload.len];
    }
    c.NET_SendPacket(channel.sock, @intCast(packet.len), packet.ptr, channel.remoteAddress);
    channel.lastSentTime = c.Sys_Milliseconds();
    channel.lastSentSize = @intCast(packet.len);
}
fn sessionFrom(channel: *Channel) security.Session {
    return .{ .send_key = channel.dk3SendKey, .receive_key = channel.dk3ReceiveKey, .next = channel.dk3SendCounter, .replay = .{ .highest = channel.dk3ReceiveHighest, .seen = channel.dk3ReceiveMask } };
}
fn header(channel: *Channel, buffer: []u8, fragmented: bool) usize {
    if (channel.outgoingSequence <= 0 or channel.outgoingSequence == std.math.maxInt(i32)) c.Com_Error(c.ERR_DROP, "dk3: channel sequence exhausted; reconnect");
    const sequence: u32 = @intCast(channel.outgoingSequence);
    std.mem.writeInt(u32, buffer[0..4], sequence | (if (fragmented) fragment_bit else @as(u32, 0)), .little);
    var offset: usize = 4;
    if (channel.sock == c.NS_CLIENT) {
        std.mem.writeInt(u16, buffer[offset..][0..2], @truncate(@as(u32, @bitCast(net_qport.*.integer))), .little);
        offset += 2;
    }
    std.mem.writeInt(u32, buffer[offset..][0..4], checksum(channel, sequence), .little);
    return offset + 4;
}
export fn Netchan_Init(port: c_int) callconv(.c) void {
    showpackets = c.Cvar_Get("showpackets", "0", c.CVAR_TEMP);
    showdrop = c.Cvar_Get("showdrop", "0", c.CVAR_TEMP);
    net_qport = c.Cvar_Get("net_qport", c.va("%i", port & 65535), c.CVAR_INIT);
}
export fn Netchan_Setup(sock: c.netsrc_t, channel: *Channel, address: c.netadr_t, qport: c_int, challenge: c_int, _: c.qboolean) callconv(.c) void {
    channel.* = std.mem.zeroes(Channel);
    channel.sock = sock;
    channel.remoteAddress = address;
    channel.qport = qport;
    channel.outgoingSequence = 1;
    channel.challenge = challenge;
    channel.fragmentTotal = -1;
}
export fn Netchan_TransmitNextFragment(channel: *Channel) callconv(.c) void {
    if (channel.unsentFragments == 0) return;
    if (channel.unsentFragmentStart < 0 or channel.unsentFragmentStart > channel.unsentLength or channel.unsentLength > c.MAX_MSGLEN - 4) c.Com_Error(c.ERR_DROP, "dk3: invalid outbound fragment state");
    var buffer: [1400]u8 = undefined;
    const offset = header(channel, &buffer, true);
    const start: usize = @intCast(channel.unsentFragmentStart);
    const length = @min(fragment_size, @as(usize, @intCast(channel.unsentLength)) - start);
    std.mem.writeInt(u32, buffer[offset..][0..4], @intCast(start), .little);
    std.mem.writeInt(u16, buffer[offset + 4 ..][0..2], @intCast(length), .little);
    @memcpy(buffer[offset + 6 ..][0..length], channel.unsentBuffer[start..][0..length]);
    send(channel, buffer[0 .. offset + 6 + length]);
    channel.unsentFragmentStart += @intCast(length);
    if (channel.unsentFragmentStart == channel.unsentLength and length != fragment_size) {
        channel.outgoingSequence += 1;
        channel.unsentFragments = c.qfalse;
    }
}
export fn Netchan_Transmit(channel: *Channel, length: c_int, data: [*c]const u8) callconv(.c) void {
    if (length < 0 or length > c.MAX_MSGLEN - 4 or (length != 0 and data == null)) c.Com_Error(c.ERR_DROP, "dk3: invalid outbound message length %i", length);
    const size: usize = @intCast(length);
    channel.unsentFragmentStart = 0;
    if (size >= fragment_size) {
        channel.unsentFragments = c.qtrue;
        channel.unsentLength = length;
        @memcpy(channel.unsentBuffer[0..size], data[0..size]);
        Netchan_TransmitNextFragment(channel);
        return;
    }
    var buffer: [1400]u8 = undefined;
    const offset = header(channel, &buffer, false);
    if (size > 0) @memcpy(buffer[offset..][0..size], data[0..size]);
    channel.outgoingSequence += 1;
    send(channel, buffer[0 .. offset + size]);
}
export fn Netchan_Process(channel: *Channel, message: *c.msg_t) callconv(.c) c.qboolean {
    if (message.cursize < 0 or message.cursize > message.maxsize or message.data == null) return c.qfalse;
    var bytes = message.data[0..@intCast(message.cursize)];
    var offset: usize = if (channel.sock == c.NS_SERVER) 6 else 4;
    if (bytes.len < offset + 4) return c.qfalse;
    const raw = std.mem.readInt(u32, bytes[0..4], .little);
    const sequence = raw & ~fragment_bit;
    if (sequence == 0 or sequence <= channel.incomingSequence or checksum(channel, sequence) != std.mem.readInt(u32, bytes[offset..][0..4], .little)) return c.qfalse;
    offset += 4;
    if (channel.dk3Secure != 0) {
        var plaintext: [1500]u8 = undefined;
        var session = sessionFrom(channel);
        defer session.deinit();
        const payload = session.open(&plaintext, bytes[0..offset], bytes[offset..]) catch return c.qfalse;
        channel.dk3ReceiveHighest = session.replay.highest;
        channel.dk3ReceiveMask = session.replay.seen;
        @memcpy(bytes[offset..][0..payload.len], payload);
        bytes = bytes[0 .. offset + payload.len];
        message.cursize = @intCast(bytes.len);
    }
    message.oob = c.qtrue;
    if (raw & fragment_bit != 0) {
        if (bytes.len < offset + 6) return c.qfalse;
        const start = std.mem.readInt(u32, bytes[offset..][0..4], .little);
        const length = std.mem.readInt(u16, bytes[offset + 4 ..][0..2], .little);
        offset += 6;
        if (length > fragment_size or start > c.MAX_MSGLEN - 4 or length > @as(u32, c.MAX_MSGLEN - 4) - start or start % fragment_size != 0 or bytes.len - offset != length) return c.qfalse;
        if (sequence < channel.fragmentSequence) return c.qfalse;
        if (sequence != channel.fragmentSequence) {
            channel.fragmentSequence = @intCast(sequence);
            channel.fragmentLength = 0;
            channel.fragmentTotal = -1;
            @memset(&channel.receivedFragments, 0);
        }
        const part = start / fragment_size;
        if (channel.fragmentTotal >= 0 and start + length > channel.fragmentTotal) return c.qfalse;
        if (length != fragment_size) {
            if (channel.fragmentTotal >= 0 and channel.fragmentTotal != start + length) return c.qfalse;
            channel.fragmentTotal = @intCast(start + length);
        }
        if (channel.receivedFragments[part] != 0) {
            if (!std.mem.eql(u8, channel.fragmentBuffer[start..][0..length], bytes[offset..])) return c.qfalse;
        } else {
            @memcpy(channel.fragmentBuffer[start..][0..length], bytes[offset..]);
            channel.receivedFragments[part] = 1;
        }
        if (channel.fragmentTotal < 0) return c.qfalse;
        const total: usize = @intCast(channel.fragmentTotal);
        for (channel.receivedFragments[0 .. total / fragment_size + 1]) |received| if (received == 0) return c.qfalse;
        if (total + 4 > message.maxsize) return c.qfalse;
        std.mem.writeInt(u32, message.data[0..4], sequence, .little);
        @memcpy(message.data[4..][0..total], channel.fragmentBuffer[0..total]);
        message.cursize = @intCast(total + 4);
        offset = 4;
        channel.fragmentLength = 0;
    }
    channel.dropped = @as(c_int, @intCast(sequence)) - channel.incomingSequence - 1;
    channel.incomingSequence = @intCast(sequence);
    message.readcount = @intCast(offset);
    message.bit = @intCast(offset * 8);
    return c.qtrue;
}
