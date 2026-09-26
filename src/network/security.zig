// SPDX-License-Identifier: GPL-2.0-or-later
//! Packet protection; session keys are provisioned over authenticated HTTPS.
const std = @import("std");
const Aead = std.crypto.aead.chacha_poly.ChaCha20Poly1305;
pub const Key = [32]u8;
pub const overhead = 8 + Aead.tag_length;
pub const ReplayWindow = struct {
    highest: u64 = 0,
    seen: u64 = 0,
    pub fn contains(self: ReplayWindow, counter: u64) bool {
        if (counter == 0) return true;
        if (counter > self.highest) return false;
        const distance = self.highest - counter;
        return distance >= 64 or self.seen & (@as(u64, 1) << @intCast(distance)) != 0;
    }
    pub fn accept(self: *ReplayWindow, counter: u64) void {
        std.debug.assert(!self.contains(counter));
        if (counter > self.highest) {
            const distance = counter - self.highest;
            self.seen = if (distance >= 64) 1 else (self.seen << @intCast(distance)) | 1;
            self.highest = counter;
        } else self.seen |= @as(u64, 1) << @intCast(self.highest - counter);
    }
};
pub const Session = struct {
    send_key: Key,
    receive_key: Key,
    next: u64 = 1,
    replay: ReplayWindow = .{},
    pub fn seal(self: *Session, output: []u8, header: []const u8, payload: []const u8) ![]const u8 {
        if (self.next == std.math.maxInt(u64)) return error.KeyExhausted;
        if (output.len < payload.len + overhead) return error.NoSpace;
        std.mem.writeInt(u64, output[0..8], self.next, .little);
        var nonce: [12]u8 = @splat(0);
        std.mem.writeInt(u64, nonce[4..12], self.next, .little);
        var tag: [Aead.tag_length]u8 = undefined;
        Aead.encrypt(output[overhead..][0..payload.len], &tag, payload, header, nonce, self.send_key);
        @memcpy(output[8..overhead], &tag);
        self.next += 1;
        return output[0 .. overhead + payload.len];
    }
    pub fn open(self: *Session, output: []u8, header: []const u8, packet: []const u8) ![]const u8 {
        if (packet.len < overhead or packet.len - overhead > output.len) return error.InvalidLength;
        const counter = std.mem.readInt(u64, packet[0..8], .little);
        if (self.replay.contains(counter)) return error.Replayed;
        var nonce: [12]u8 = @splat(0);
        std.mem.writeInt(u64, nonce[4..12], counter, .little);
        const plaintext = output[0 .. packet.len - overhead];
        try Aead.decrypt(plaintext, packet[overhead..], packet[8..overhead].*, header, nonce, self.receive_key);
        // Never let unauthenticated packets advance the replay window.
        self.replay.accept(counter);
        return plaintext;
    }
    pub fn deinit(self: *Session) void {
        std.crypto.secureZero(u8, std.mem.asBytes(self));
    }
};
test "authenticated packets accept reordering, reject replay and tampering without state changes" {
    var sender: Session = .{ .send_key = @splat(1), .receive_key = @splat(2) };
    var receiver: Session = .{ .send_key = @splat(2), .receive_key = @splat(1) };
    var one: [100]u8 = undefined;
    var two: [100]u8 = undefined;
    var plain: [100]u8 = undefined;
    const first = try sender.seal(&one, "room/header", "first");
    const second = try sender.seal(&two, "room/header", "second");
    try std.testing.expectError(error.AuthenticationFailed, receiver.open(&plain, "other/header", second));
    try std.testing.expectEqual(@as(u64, 0), receiver.replay.highest);
    try std.testing.expectEqualStrings("second", try receiver.open(&plain, "room/header", second));
    try std.testing.expectEqualStrings("first", try receiver.open(&plain, "room/header", first));
    try std.testing.expectError(error.Replayed, receiver.open(&plain, "room/header", first));
}

test "forged future counter and ciphertext cannot discard pending legitimate packets" {
    var sender: Session = .{ .send_key = @splat(3), .receive_key = @splat(4) };
    var receiver: Session = .{ .send_key = @splat(4), .receive_key = @splat(3) };
    var buffer: [64]u8 = undefined;
    var output: [64]u8 = undefined;
    const legitimate = try sender.seal(&buffer, "header", "authoritative state");
    var forged = buffer;
    std.mem.writeInt(u64, forged[0..8], 1_000_000, .little);
    try std.testing.expectError(error.AuthenticationFailed, receiver.open(&output, "header", forged[0..legitimate.len]));
    try std.testing.expectEqual(@as(u64, 0), receiver.replay.highest);
    forged = buffer;
    forged[legitimate.len - 1] ^= 1;
    try std.testing.expectError(error.AuthenticationFailed, receiver.open(&output, "header", forged[0..legitimate.len]));
    try std.testing.expectEqualStrings("authoritative state", try receiver.open(&output, "header", legitimate));
}
test "replay window bounds old packets and reconnect keys separate sessions" {
    var sender: Session = .{ .send_key = @splat(5), .receive_key = @splat(6) };
    var receiver: Session = .{ .send_key = @splat(6), .receive_key = @splat(5) };
    var first: [64]u8 = undefined;
    var last: [64]u8 = undefined;
    var output: [64]u8 = undefined;
    const oldest = try sender.seal(&first, "header", "first");
    sender.next = 65;
    const newest = try sender.seal(&last, "header", "latest");
    _ = try receiver.open(&output, "header", newest);
    try std.testing.expectError(error.Replayed, receiver.open(&output, "header", oldest));
    var reconnected: Session = .{ .send_key = @splat(8), .receive_key = @splat(7) };
    try std.testing.expectError(error.AuthenticationFailed, reconnected.open(&output, "header", newest));
    sender.next = std.math.maxInt(u64);
    try std.testing.expectError(error.KeyExhausted, sender.seal(&last, "header", "cannot reuse nonce"));
}
