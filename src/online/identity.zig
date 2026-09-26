// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const Ed25519 = std.crypto.sign.Ed25519;
pub fn hex(comptime count: usize, value: []const u8) ![count]u8 {
    if (value.len != count * 2) return error.InvalidEncoding;
    var bytes: [count]u8 = undefined;
    _ = std.fmt.hexToBytes(&bytes, value) catch return error.InvalidEncoding;
    return bytes;
}
pub fn verify(public_key: []const u8, signature: []const u8, message: []const u8) !void {
    const key = try Ed25519.PublicKey.fromBytes(try hex(32, public_key));
    const proof = Ed25519.Signature.fromBytes(try hex(64, signature));
    try proof.verifyStrict(message, key);
}
pub fn identifier(public_key: []const u8) ![64]u8 {
    const bytes = try hex(32, public_key);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&bytes, &hash, .{});
    return std.fmt.bytesToHex(hash, .lower);
}
pub fn token(io: std.Io) ![64]u8 {
    var bytes: [32]u8 = undefined;
    try io.randomSecure(&bytes);
    return std.fmt.bytesToHex(bytes, .lower);
}
