// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 1999-2005 Id Software, Inc.
//! Bounded protocol-1346 message codec, ported from bundled ioquake3/msg.c.
//! C layouts are adapters only: ordered scalar fields define the wire schema.
//! The reviewed upstream Huffman implementation remains the compression library.
const std = @import("std");
const c = @import("abi.zig").c;
const schema = @import("message_schema.zig");
var huffman: c.huffman_t = undefined;
var initialized = false;
var string: [c.MAX_STRING_CHARS:0]u8 = @splat(0);
var big_string: [c.BIG_INFO_STRING:0]u8 = @splat(0);
var line_string: [c.MAX_STRING_CHARS:0]u8 = @splat(0);
fn fail(text: [*:0]const u8) noreturn {
    c.Com_Error(c.ERR_DROP, "%s", text);
    unreachable;
}
fn bitsOf(value: c_int) u32 {
    return @bitCast(value);
}
fn signed(value: u32) c_int {
    return @bitCast(value);
}
fn mask(bits: c_int) u32 {
    return if (bits == 32) 0xffffffff else (@as(u32, 1) << @intCast(bits)) - 1;
}
export fn MSG_initHuffman() callconv(.c) void {
    if (initialized) return;
    c.Huff_Init(&huffman);
    for (schema.frequencies, 0..) |count, index| for (0..count) |_| {
        c.Huff_addRef(&huffman.compressor, @intCast(index));
        c.Huff_addRef(&huffman.decompressor, @intCast(index));
    };
    initialized = true;
}
export fn MSG_Init(msg: *c.msg_t, data: [*]u8, length: c_int) callconv(.c) void {
    if (length < 0 or length > std.math.maxInt(c_int) / 8) fail("Invalid message capacity");
    MSG_initHuffman();
    msg.* = std.mem.zeroes(c.msg_t);
    msg.data = data;
    msg.maxsize = length;
}
export fn MSG_InitOOB(msg: *c.msg_t, data: [*]u8, length: c_int) callconv(.c) void {
    MSG_Init(msg, data, length);
    msg.oob = c.qtrue;
}
export fn MSG_Clear(msg: *c.msg_t) callconv(.c) void {
    msg.cursize = 0;
    msg.overflowed = c.qfalse;
    msg.bit = 0;
}
export fn MSG_Bitstream(msg: *c.msg_t) callconv(.c) void {
    msg.oob = c.qfalse;
}
export fn MSG_BeginReading(msg: *c.msg_t) callconv(.c) void {
    msg.readcount = 0;
    msg.bit = 0;
    msg.oob = c.qfalse;
}
export fn MSG_BeginReadingOOB(msg: *c.msg_t) callconv(.c) void {
    MSG_BeginReading(msg);
    msg.oob = c.qtrue;
}
export fn MSG_Copy(msg: *c.msg_t, data: [*]u8, length: c_int, source: *c.msg_t) callconv(.c) void {
    if (source.cursize < 0 or length < source.cursize) fail("MSG_Copy: destination too small");
    msg.* = source.*;
    msg.data = data;
    msg.maxsize = length;
    @memcpy(data[0..@intCast(source.cursize)], source.data[0..@intCast(source.cursize)]);
}
export fn MSG_WriteBits(msg: *c.msg_t, value: c_int, signed_bits: c_int) callconv(.c) void {
    if (msg.overflowed != 0) return;
    if (signed_bits == 0 or signed_bits < -31 or signed_bits > 32) fail("Invalid message bit width");
    const bits = if (signed_bits < 0) -signed_bits else signed_bits;
    var remaining = bitsOf(value) & mask(bits);
    if (msg.oob != 0) {
        if (bits != 8 and bits != 16 and bits != 32) fail("Invalid out-of-band bit width");
        const bytes = @divTrunc(bits, 8);
        if (msg.cursize < 0 or msg.cursize > msg.maxsize - bytes) {
            msg.overflowed = c.qtrue;
            return;
        }
        for (0..@intCast(bytes)) |i| {
            msg.data[@as(usize, @intCast(msg.cursize)) + i] = @truncate(remaining);
            remaining >>= 8;
        }
        msg.cursize += bytes;
        msg.bit += bits;
        return;
    }
    const tail = bits & 7;
    if (msg.bit < 0 or msg.bit + tail >= msg.maxsize * 8) {
        msg.overflowed = c.qtrue;
        return;
    }
    for (0..@intCast(tail)) |_| {
        c.Huff_putBit(@intCast(remaining & 1), msg.data, &msg.bit);
        remaining >>= 1;
    }
    var i = tail;
    while (i < bits) : (i += 8) {
        c.Huff_offsetTransmit(&huffman.compressor, @intCast(remaining & 255), msg.data, &msg.bit, msg.maxsize * 8);
        remaining >>= 8;
        if (msg.bit >= msg.maxsize * 8) {
            msg.overflowed = c.qtrue;
            return;
        }
    }
    msg.cursize = @divTrunc(msg.bit, 8) + 1;
}
export fn MSG_ReadBits(msg: *c.msg_t, signed_bits: c_int) callconv(.c) c_int {
    if (signed_bits == 0 or signed_bits < -31 or signed_bits > 32) fail("Invalid message bit width");
    if (msg.readcount > msg.cursize) return 0;
    const bits = if (signed_bits < 0) -signed_bits else signed_bits;
    var result: u32 = 0;
    if (msg.cursize < 0 or msg.cursize > msg.maxsize or msg.readcount < 0 or msg.bit < 0) {
        msg.readcount = msg.cursize + 1;
        return 0;
    }
    if (msg.oob != 0) {
        if (bits != 8 and bits != 16 and bits != 32) fail("Invalid out-of-band bit width");
        const bytes = @divTrunc(bits, 8);
        if (msg.readcount > msg.cursize - bytes) {
            msg.readcount = msg.cursize + 1;
            return 0;
        }
        for (0..@intCast(bytes)) |i| result |= @as(u32, msg.data[@as(usize, @intCast(msg.readcount)) + i]) << @intCast(i * 8);
        msg.readcount += bytes;
        msg.bit += bits;
        // The C adapter historically reads an OOB short as signed.
        if (bits == 16) return @as(i16, @bitCast(@as(u16, @truncate(result))));
    } else {
        const tail = bits & 7;
        if (msg.bit > msg.cursize * 8 - tail) {
            msg.readcount = msg.cursize + 1;
            return 0;
        }
        for (0..@intCast(tail)) |i| result |= @as(u32, @intCast(c.Huff_getBit(msg.data, &msg.bit))) << @intCast(i);
        var i = tail;
        while (i < bits) : (i += 8) {
            var byte: c_int = 0;
            c.Huff_offsetReceive(huffman.decompressor.tree, &byte, msg.data, &msg.bit, msg.cursize * 8);
            if (msg.bit > msg.cursize * 8) {
                msg.readcount = msg.cursize + 1;
                return 0;
            }
            result |= bitsOf(byte) << @intCast(i);
        }
        msg.readcount = @divTrunc(msg.bit, 8) + 1;
    }
    // Sign extension uses the original width, including any uncompressed tail.
    if (signed_bits < 0 and result & (@as(u32, 1) << @intCast(bits - 1)) != 0) result |= ~mask(bits);
    return signed(result);
}
export fn MSG_WriteChar(msg: *c.msg_t, value: c_int) callconv(.c) void {
    MSG_WriteBits(msg, value, 8);
}
export fn MSG_WriteByte(msg: *c.msg_t, value: c_int) callconv(.c) void {
    MSG_WriteBits(msg, value, 8);
}
export fn MSG_WriteShort(msg: *c.msg_t, value: c_int) callconv(.c) void {
    MSG_WriteBits(msg, value, 16);
}
export fn MSG_WriteLong(msg: *c.msg_t, value: c_int) callconv(.c) void {
    MSG_WriteBits(msg, value, 32);
}
export fn MSG_WriteFloat(msg: *c.msg_t, value: f32) callconv(.c) void {
    MSG_WriteBits(msg, @bitCast(value), 32);
}
export fn MSG_WriteData(msg: *c.msg_t, data: [*]const u8, length: c_int) callconv(.c) void {
    if (length < 0) fail("Negative message data length");
    for (data[0..@intCast(length)]) |byte| MSG_WriteByte(msg, byte);
}
fn writeString(msg: *c.msg_t, text: ?[*:0]const u8, limit: usize) void {
    if (text) |ptr| {
        const value = std.mem.span(ptr);
        if (value.len >= limit) {
            c.Com_Printf("Message string exceeds protocol limit\n");
            MSG_WriteByte(msg, 0);
            return;
        }
        for (value) |byte| MSG_WriteByte(msg, if (byte > 127 or byte == '%') '.' else byte);
    }
    MSG_WriteByte(msg, 0);
}
export fn MSG_WriteString(msg: *c.msg_t, text: ?[*:0]const u8) callconv(.c) void {
    writeString(msg, text, c.MAX_STRING_CHARS);
}
export fn MSG_WriteBigString(msg: *c.msg_t, text: ?[*:0]const u8) callconv(.c) void {
    writeString(msg, text, c.BIG_INFO_STRING);
}
fn angle(value: f32, scale: f32) c_int {
    if (!std.math.isFinite(value)) return 0;
    return @intFromFloat(@rem(value, 360) * scale / 360);
}
export fn MSG_WriteAngle(msg: *c.msg_t, value: f32) callconv(.c) void {
    MSG_WriteByte(msg, angle(value, 256) & 255);
}
export fn MSG_WriteAngle16(msg: *c.msg_t, value: f32) callconv(.c) void {
    MSG_WriteShort(msg, angle(value, 65536) & 65535);
}
export fn MSG_ReadByte(msg: *c.msg_t) callconv(.c) c_int {
    const value = MSG_ReadBits(msg, 8);
    return if (msg.readcount > msg.cursize) -1 else value & 255;
}
export fn MSG_ReadChar(msg: *c.msg_t) callconv(.c) c_int {
    const value = MSG_ReadByte(msg);
    return @as(i8, @bitCast(@as(u8, @truncate(bitsOf(value)))));
}
export fn MSG_ReadShort(msg: *c.msg_t) callconv(.c) c_int {
    const value = MSG_ReadBits(msg, 16);
    return if (msg.readcount > msg.cursize) -1 else @as(i16, @bitCast(@as(u16, @truncate(bitsOf(value)))));
}
export fn MSG_ReadLong(msg: *c.msg_t) callconv(.c) c_int {
    const value = MSG_ReadBits(msg, 32);
    return if (msg.readcount > msg.cursize) -1 else value;
}
export fn MSG_ReadFloat(msg: *c.msg_t) callconv(.c) f32 {
    const value = MSG_ReadBits(msg, 32);
    return if (msg.readcount > msg.cursize) -1 else @bitCast(value);
}
export fn MSG_ReadAngle16(msg: *c.msg_t) callconv(.c) f32 {
    return @as(f32, @floatFromInt(MSG_ReadShort(msg))) * (360.0 / 65536.0);
}
export fn MSG_LookaheadByte(msg: *c.msg_t) callconv(.c) c_int {
    const offset = c.Huff_getBloc();
    const saved = msg.*;
    const result = MSG_ReadByte(msg);
    msg.* = saved;
    c.Huff_setBloc(offset);
    return result;
}
fn readString(msg: *c.msg_t, output: []u8, line: bool) void {
    var count: usize = 0;
    while (true) {
        const byte = MSG_ReadByte(msg);
        if (byte == -1 or byte == 0 or (line and byte == '\n')) break;
        if (count == output.len - 1) break;
        output[count] = @intCast(if (byte > 127 or byte == '%') '.' else byte);
        count += 1;
    }
    output[count] = 0;
}
export fn MSG_ReadString(msg: *c.msg_t) callconv(.c) [*:0]u8 {
    readString(msg, &string, false);
    return &string;
}
export fn MSG_ReadBigString(msg: *c.msg_t) callconv(.c) [*:0]u8 {
    readString(msg, &big_string, false);
    return &big_string;
}
export fn MSG_ReadStringLine(msg: *c.msg_t) callconv(.c) [*:0]u8 {
    readString(msg, &line_string, true);
    return &line_string;
}
export fn MSG_ReadData(msg: *c.msg_t, data: [*]u8, length: c_int) callconv(.c) void {
    if (length < 0) fail("Negative message data length");
    for (data[0..@intCast(length)]) |*byte| byte.* = @truncate(bitsOf(MSG_ReadByte(msg)));
}
export fn MSG_HashKey(text: [*:0]const u8, length: c_int) callconv(.c) c_int {
    var hash: c_int = 0;
    var i: c_int = 0;
    while (i < length and text[@intCast(i)] != 0) : (i += 1) {
        const byte = text[@intCast(i)];
        hash +%= @as(c_int, if (byte > 127 or byte == '%') '.' else byte) *% (119 +% i);
    }
    return hash ^ (hash >> 10) ^ (hash >> 20);
}
export fn MSG_WriteDeltaKey(msg: *c.msg_t, key: c_int, old: c_int, new: c_int, bits: c_int) callconv(.c) void {
    MSG_WriteBits(msg, @intFromBool(old != new), 1);
    if (old != new) MSG_WriteBits(msg, new ^ key, bits);
}
export fn MSG_ReadDeltaKey(msg: *c.msg_t, key: c_int, old: c_int, bits: c_int) callconv(.c) c_int {
    if (bits < 1 or bits > 32) fail("Invalid keyed delta width");
    return if (MSG_ReadBits(msg, 1) != 0) MSG_ReadBits(msg, bits) ^ signed(bitsOf(key) & mask(bits)) else old;
}
export fn MSG_WriteDeltaKeyFloat(msg: *c.msg_t, key: c_int, old: f32, new: f32) callconv(.c) void {
    MSG_WriteBits(msg, @intFromBool(old != new), 1);
    if (old != new) MSG_WriteBits(msg, @as(c_int, @bitCast(new)) ^ key, 32);
}
export fn MSG_ReadDeltaKeyFloat(msg: *c.msg_t, key: c_int, old: f32) callconv(.c) f32 {
    return if (MSG_ReadBits(msg, 1) != 0) @bitCast(MSG_ReadBits(msg, 32) ^ key) else old;
}
export fn MSG_WriteDeltaUsercmdKey(msg: *c.msg_t, input_key: c_int, from: *c.usercmd_t, to: *c.usercmd_t) callconv(.c) void {
    const delta = to.serverTime -% from.serverTime;
    if (delta >= 0 and delta < 256) {
        MSG_WriteBits(msg, 1, 1);
        MSG_WriteBits(msg, delta, 8);
    } else {
        MSG_WriteBits(msg, 0, 1);
        MSG_WriteBits(msg, to.serverTime, 32);
    }
    const same = std.mem.eql(c_int, &from.angles, &to.angles) and from.forwardmove == to.forwardmove and from.rightmove == to.rightmove and from.upmove == to.upmove and from.buttons == to.buttons and from.weapon == to.weapon;
    MSG_WriteBits(msg, @intFromBool(!same), 1);
    if (same) return;
    const key = input_key ^ to.serverTime;
    for (from.angles, to.angles) |old, new| MSG_WriteDeltaKey(msg, key, old, new, 16);
    inline for (.{ "forwardmove", "rightmove", "upmove", "buttons", "weapon" }) |field| MSG_WriteDeltaKey(msg, key, @field(from, field), @field(to, field), if (std.mem.eql(u8, field, "buttons")) 16 else 8);
}
export fn MSG_ReadDeltaUsercmdKey(msg: *c.msg_t, input_key: c_int, from: *c.usercmd_t, to: *c.usercmd_t) callconv(.c) void {
    to.* = from.*;
    to.serverTime = if (MSG_ReadBits(msg, 1) != 0) from.serverTime +% MSG_ReadBits(msg, 8) else MSG_ReadBits(msg, 32);
    if (MSG_ReadBits(msg, 1) == 0) return;
    const key = input_key ^ to.serverTime;
    for (&to.angles, from.angles) |*new, old| new.* = MSG_ReadDeltaKey(msg, key, old, 16);
    inline for (.{ "forwardmove", "rightmove", "upmove" }) |field| {
        const byte: i8 = @bitCast(@as(u8, @truncate(bitsOf(MSG_ReadDeltaKey(msg, key, @field(from, field), 8)))));
        @field(to, field) = @max(-127, byte);
    }
    to.buttons = MSG_ReadDeltaKey(msg, key, from.buttons, 16);
    to.weapon = @truncate(bitsOf(MSG_ReadDeltaKey(msg, key, from.weapon, 8)));
}

pub const Field = struct {
    name: [:0]const u8,
    offset: usize,
    bits: c_int,
    pub fn of(comptime T: type, comptime path: [:0]const u8, comptime bits: c_int) Field {
        @setEvalBranchQuota(100000);
        if (bits < -31 or bits > 32) @compileError("Invalid wire field width");
        const offset = fieldOffset(T, path);
        if (offset + 4 > @sizeOf(T)) @compileError("Wire field exceeds ABI type");
        return .{ .name = path, .offset = offset, .bits = bits };
    }
    fn fieldOffset(comptime T: type, comptime path: []const u8) usize {
        if (std.mem.indexOfScalar(u8, path, '.')) |dot| {
            const head = path[0..dot];
            return @offsetOf(T, head) + fieldOffset(@TypeOf(@field(@as(T, undefined), head)), path[dot + 1 ..]);
        }
        if (std.mem.indexOfScalar(u8, path, '[')) |bracket| {
            const name = path[0..bracket];
            const index = std.fmt.parseInt(usize, path[bracket + 1 .. path.len - 1], 10) catch @compileError("Invalid field array index");
            const Array = @TypeOf(@field(@as(T, undefined), name));
            const array = @typeInfo(Array).array;
            if (index >= array.len or @sizeOf(array.child) != 4) @compileError("Invalid wire array element");
            return @offsetOf(T, name) + index * 4;
        }
        if (@sizeOf(@TypeOf(@field(@as(T, undefined), path))) != 4) @compileError("Wire fields must be 32-bit scalars");
        return @offsetOf(T, path);
    }
    fn read(self: Field, base: *const anyopaque) c_int {
        const bytes: [*]const u8 = @ptrCast(base);
        const value: *align(1) const c_int = @ptrCast(bytes + self.offset);
        return value.*;
    }
    fn write(self: Field, base: *anyopaque, value: c_int) void {
        const bytes: [*]u8 = @ptrCast(base);
        const destination: *align(1) c_int = @ptrCast(bytes + self.offset);
        destination.* = value;
    }
};
comptime {
    @setEvalBranchQuota(100000);
    if ((schema.entity.len + 1) * 4 != @sizeOf(c.entityState_t)) @compileError("Entity fields missing from protocol schema");
    if (schema.extension.len * 4 != @sizeOf(c.dkq3EntityExt_t)) @compileError("Extension fields missing from protocol schema");
    for (.{ schema.entity, schema.extension, schema.player }) |fields| {
        for (fields, 0..) |field, i| for (fields[0..i]) |previous| if (field.offset == previous.offset) @compileError("Duplicate protocol field");
    }
}
fn lastChange(fields: []const Field, from: *const anyopaque, to: *const anyopaque) usize {
    var count: usize = 0;
    for (fields, 0..) |field, i| if (field.read(from) != field.read(to)) {
        count = i + 1;
    };
    return count;
}
fn writeScalar(msg: *c.msg_t, field: Field, value: c_int, zero_prefix: bool) void {
    if (zero_prefix) {
        const zero = if (field.bits == 0) @as(f32, @bitCast(value)) == 0 else value == 0;
        MSG_WriteBits(msg, @intFromBool(!zero), 1);
        if (zero) return;
    }
    if (field.bits != 0) {
        MSG_WriteBits(msg, value, field.bits);
        return;
    }
    const float: f32 = @bitCast(value);
    // Check range before converting; NaN/Inf and large finite values take the
    // full-width path instead of invoking undefined C float-to-int conversion.
    if (float >= -4096 and float < 4096 and @trunc(float) == float) {
        MSG_WriteBits(msg, 0, 1);
        MSG_WriteBits(msg, @as(c_int, @intFromFloat(float)) + 4096, 13);
    } else {
        MSG_WriteBits(msg, 1, 1);
        MSG_WriteBits(msg, value, 32);
    }
}
fn readScalar(msg: *c.msg_t, field: Field, zero_prefix: bool) c_int {
    if (zero_prefix and MSG_ReadBits(msg, 1) == 0) return 0;
    if (field.bits != 0) return MSG_ReadBits(msg, field.bits);
    return if (MSG_ReadBits(msg, 1) == 0) @bitCast(@as(f32, @floatFromInt(MSG_ReadBits(msg, 13) - 4096))) else MSG_ReadBits(msg, 32);
}
fn writeFields(msg: *c.msg_t, fields: []const Field, count: usize, from: *const anyopaque, to: *const anyopaque, zero_prefix: bool) void {
    MSG_WriteByte(msg, @intCast(count));
    for (fields[0..count]) |field| {
        const value = field.read(to);
        const changed = field.read(from) != value;
        MSG_WriteBits(msg, @intFromBool(changed), 1);
        if (changed) writeScalar(msg, field, value, zero_prefix);
    }
}
fn readFields(msg: *c.msg_t, fields: []const Field, to: *anyopaque, zero_prefix: bool) void {
    const count = MSG_ReadByte(msg);
    if (count < 0 or count > fields.len) fail("Invalid snapshot field count");
    for (fields[0..@intCast(count)]) |field| if (MSG_ReadBits(msg, 1) != 0) field.write(to, readScalar(msg, field, zero_prefix));
}
export fn MSG_WriteDeltaEntity(msg: *c.msg_t, from_input: ?*c.entityState_t, to_input: ?*c.entityState_t, force: c.qboolean) callconv(.c) void {
    const to = to_input orelse {
        if (from_input) |from| {
            MSG_WriteBits(msg, from.number, c.GENTITYNUM_BITS);
            MSG_WriteBits(msg, 1, 1);
        }
        return;
    };
    if (to.number < 0 or to.number >= c.MAX_GENTITIES) fail("Invalid snapshot entity number");
    const zero = std.mem.zeroes(c.entityState_t);
    const from = from_input orelse &zero;
    const count = lastChange(&schema.entity, from, to);
    if (count == 0 and force == 0) return;
    MSG_WriteBits(msg, to.number, c.GENTITYNUM_BITS);
    MSG_WriteBits(msg, 0, 1);
    MSG_WriteBits(msg, @intFromBool(count != 0), 1);
    if (count != 0) writeFields(msg, &schema.entity, count, from, to, true);
}
export fn MSG_ReadDeltaEntity(msg: *c.msg_t, from: *c.entityState_t, to: *c.entityState_t, number: c_int) callconv(.c) void {
    if (number < 0 or number >= c.MAX_GENTITIES) fail("Invalid snapshot entity number");
    if (MSG_ReadBits(msg, 1) != 0) {
        to.* = std.mem.zeroes(c.entityState_t);
        to.number = c.MAX_GENTITIES - 1;
        return;
    }
    to.* = from.*;
    to.number = number;
    if (MSG_ReadBits(msg, 1) != 0) readFields(msg, &schema.entity, to, true);
}
export fn MSG_WriteDeltaEntityDkq3(msg: *c.msg_t, from: *c.entityState_t, to: ?*c.entityState_t, from_ext: *c.dkq3EntityExt_t, to_ext: *c.dkq3EntityExt_t, force: c.qboolean) callconv(.c) void {
    const target = to orelse {
        MSG_WriteDeltaEntity(msg, from, null, force);
        return;
    };
    const count = lastChange(&schema.extension, from_ext, to_ext);
    if (count == 0 and force == 0 and lastChange(&schema.entity, from, target) == 0) return;
    MSG_WriteDeltaEntity(msg, from, target, c.qtrue);
    MSG_WriteBits(msg, @intFromBool(count != 0), 1);
    if (count != 0) writeFields(msg, &schema.extension, count, from_ext, to_ext, true);
}
export fn MSG_ReadDeltaEntityDkq3(msg: *c.msg_t, from: *c.entityState_t, to: *c.entityState_t, from_ext: *c.dkq3EntityExt_t, to_ext: *c.dkq3EntityExt_t, number: c_int) callconv(.c) void {
    MSG_ReadDeltaEntity(msg, from, to, number);
    if (to.number == c.MAX_GENTITIES - 1) {
        to_ext.* = std.mem.zeroes(c.dkq3EntityExt_t);
        return;
    }
    to_ext.* = from_ext.*;
    if (MSG_ReadBits(msg, 1) != 0) readFields(msg, &schema.extension, to_ext, true);
}
const arrays = .{ "stats", "persistant", "ammo", "powerups" };
fn arrayChanges(from: []const c_int, to: []const c_int) u32 {
    var result: u32 = 0;
    for (from, to, 0..) |old, new, i| if (old != new) {
        result |= @as(u32, 1) << @intCast(i);
    };
    return result;
}
export fn MSG_WriteDeltaPlayerstate(msg: *c.msg_t, from_input: ?*c.playerState_t, to: *c.playerState_t) callconv(.c) void {
    const zero = std.mem.zeroes(c.playerState_t);
    const from = from_input orelse &zero;
    writeFields(msg, &schema.player, lastChange(&schema.player, from, to), from, to, false);
    var masks: [4]u32 = undefined;
    inline for (arrays, 0..) |name, i| masks[i] = arrayChanges(&@field(from, name), &@field(to, name));
    var changed = false;
    for (masks) |value| changed = changed or value != 0;
    MSG_WriteBits(msg, @intFromBool(changed), 1);
    if (!changed) return;
    inline for (arrays, 0..) |name, i| {
        const values = @field(to, name);
        if (values.len > 32) @compileError("Snapshot array mask exceeds 32 bits");
        MSG_WriteBits(msg, @intFromBool(masks[i] != 0), 1);
        if (masks[i] != 0) {
            MSG_WriteBits(msg, signed(masks[i]), values.len);
            for (values, 0..) |value, index| if (masks[i] & (@as(u32, 1) << @intCast(index)) != 0) MSG_WriteBits(msg, value, if (i == 3) 32 else 16);
        }
    }
}
export fn MSG_ReadDeltaPlayerstate(msg: *c.msg_t, from: ?*c.playerState_t, to: *c.playerState_t) callconv(.c) void {
    to.* = if (from) |source| source.* else std.mem.zeroes(c.playerState_t);
    readFields(msg, &schema.player, to, false);
    if (MSG_ReadBits(msg, 1) == 0) return;
    inline for (arrays, 0..) |name, i| if (MSG_ReadBits(msg, 1) != 0) {
        const values = &@field(to, name);
        const changed = bitsOf(MSG_ReadBits(msg, values.len));
        for (values, 0..) |*value, index| if (changed & (@as(u32, 1) << @intCast(index)) != 0) {
            value.* = if (i == 3) MSG_ReadLong(msg) else MSG_ReadShort(msg);
        };
    };
}
export fn MSG_ReportChangeVectors_f() callconv(.c) void {
    c.Com_Printf("dk3 codec: %d entity, %d extension and %d player scalar fields\n", @as(c_int, schema.entity.len), @as(c_int, schema.extension.len), @as(c_int, schema.player.len));
}

extern fn Ref_MSG_Init(*c.msg_t, [*]u8, c_int) void;
extern fn Ref_MSG_WriteDeltaEntityDkq3(*c.msg_t, *c.entityState_t, ?*c.entityState_t, *c.dkq3EntityExt_t, *c.dkq3EntityExt_t, c.qboolean) void;
extern fn Ref_MSG_ReadDeltaEntityDkq3(*c.msg_t, *c.entityState_t, *c.entityState_t, *c.dkq3EntityExt_t, *c.dkq3EntityExt_t, c_int) void;
extern fn Ref_MSG_WriteDeltaPlayerstate(*c.msg_t, ?*c.playerState_t, *c.playerState_t) void;
extern fn Ref_MSG_ReadDeltaPlayerstate(*c.msg_t, ?*c.playerState_t, *c.playerState_t) void;
extern fn Ref_MSG_WriteDeltaUsercmdKey(*c.msg_t, c_int, *c.usercmd_t, *c.usercmd_t) void;
extern fn Ref_MSG_ReadDeltaUsercmdKey(*c.msg_t, c_int, *c.usercmd_t, *c.usercmd_t) void;
fn expectWire(a: *c.msg_t, b: *c.msg_t) !void {
    try std.testing.expectEqual(a.bit, b.bit);
    try std.testing.expectEqual(a.cursize, b.cursize);
    try std.testing.expectEqualSlices(u8, a.data[0..@intCast(a.cursize)], b.data[0..@intCast(b.cursize)]);
}
fn randomFields(random: std.Random, fields: []const Field, value: *anyopaque) void {
    for (fields) |field| {
        const next: c_int = if (field.bits == 0) @bitCast(switch (random.intRangeAtMost(u8, 0, 3)) {
            0 => @as(f32, 0),
            1 => @as(f32, @floatFromInt(random.intRangeAtMost(i32, -4096, 4095))),
            2 => random.float(f32) * 100000 - 50000,
            else => @as(f32, -0.125),
        }) else random.int(c_int);
        if (random.boolean()) field.write(value, next);
    }
}
test "Zig entity and extension wire schema matches reviewed C codec" {
    var generator = std.Random.DefaultPrng.init(1346);
    const random = generator.random();
    var from = std.mem.zeroes(c.entityState_t);
    var from_ext = std.mem.zeroes(c.dkq3EntityExt_t);
    for (0..128) |iteration| {
        var to = from;
        var to_ext = from_ext;
        to.number = @intCast(iteration);
        randomFields(random, &schema.entity, &to);
        randomFields(random, &schema.extension, &to_ext);
        var a_data: [8192]u8 = @splat(0);
        var b_data = a_data;
        var a: c.msg_t = undefined;
        var b: c.msg_t = undefined;
        MSG_Init(&a, &a_data, a_data.len);
        Ref_MSG_Init(&b, &b_data, b_data.len);
        MSG_WriteDeltaEntityDkq3(&a, &from, &to, &from_ext, &to_ext, c.qtrue);
        Ref_MSG_WriteDeltaEntityDkq3(&b, &from, &to, &from_ext, &to_ext, c.qtrue);
        try expectWire(&a, &b);
        MSG_BeginReading(&a);
        MSG_BeginReading(&b);
        const number = MSG_ReadBits(&a, c.GENTITYNUM_BITS);
        _ = MSG_ReadBits(&b, c.GENTITYNUM_BITS);
        var decoded: c.entityState_t = undefined;
        var reference: c.entityState_t = undefined;
        var decoded_ext: c.dkq3EntityExt_t = undefined;
        var reference_ext: c.dkq3EntityExt_t = undefined;
        MSG_ReadDeltaEntityDkq3(&a, &from, &decoded, &from_ext, &decoded_ext, number);
        Ref_MSG_ReadDeltaEntityDkq3(&b, &from, &reference, &from_ext, &reference_ext, number);
        try std.testing.expectEqualSlices(u8, std.mem.asBytes(&reference), std.mem.asBytes(&decoded));
        try std.testing.expectEqualSlices(u8, std.mem.asBytes(&reference_ext), std.mem.asBytes(&decoded_ext));
        from = decoded;
        from_ext = decoded_ext;
    }
}
test "Zig player and command schemas match C snapshots including signed timers" {
    var generator = std.Random.DefaultPrng.init(1347);
    const random = generator.random();
    var from = std.mem.zeroes(c.playerState_t);
    var previous = std.mem.zeroes(c.usercmd_t);
    for (0..128) |_| {
        var to = from;
        randomFields(random, &schema.player, &to);
        inline for (arrays) |name| for (&@field(to, name)) |*value| {
            if (random.boolean()) value.* = random.int(i16);
        };
        var command = previous;
        command.serverTime +%= random.intRangeAtMost(c_int, 1, 500);
        for (&command.angles) |*value| value.* = random.int(u16);
        command.forwardmove = random.int(i8);
        command.rightmove = random.int(i8);
        command.upmove = random.int(i8);
        command.buttons = random.int(u16);
        command.weapon = random.int(u8);
        var a_data: [8192]u8 = @splat(0);
        var b_data = a_data;
        var a: c.msg_t = undefined;
        var b: c.msg_t = undefined;
        MSG_Init(&a, &a_data, a_data.len);
        Ref_MSG_Init(&b, &b_data, b_data.len);
        MSG_WriteDeltaPlayerstate(&a, &from, &to);
        Ref_MSG_WriteDeltaPlayerstate(&b, &from, &to);
        MSG_WriteDeltaUsercmdKey(&a, 0x123456, &previous, &command);
        Ref_MSG_WriteDeltaUsercmdKey(&b, 0x123456, &previous, &command);
        try expectWire(&a, &b);
        MSG_BeginReading(&a);
        MSG_BeginReading(&b);
        var decoded: c.playerState_t = undefined;
        var reference: c.playerState_t = undefined;
        MSG_ReadDeltaPlayerstate(&a, &from, &decoded);
        Ref_MSG_ReadDeltaPlayerstate(&b, &from, &reference);
        try std.testing.expectEqualSlices(u8, std.mem.asBytes(&reference), std.mem.asBytes(&decoded));
        var decoded_command = std.mem.zeroes(c.usercmd_t);
        var reference_command = decoded_command;
        MSG_ReadDeltaUsercmdKey(&a, 0x123456, &previous, &decoded_command);
        Ref_MSG_ReadDeltaUsercmdKey(&b, 0x123456, &previous, &reference_command);
        try std.testing.expectEqualSlices(u8, std.mem.asBytes(&reference_command), std.mem.asBytes(&decoded_command));
        from = decoded;
        previous = decoded_command;
    }
}
test "signed tail widths, truncated packets and output bounds" {
    var data: [256]u8 = @splat(0);
    var msg: c.msg_t = undefined;
    for (1..32) |bits| {
        MSG_Init(&msg, &data, data.len);
        MSG_WriteBits(&msg, -1, -@as(c_int, @intCast(bits)));
        MSG_BeginReading(&msg);
        try std.testing.expectEqual(@as(c_int, -1), MSG_ReadBits(&msg, -@as(c_int, @intCast(bits))));
    }
    MSG_Init(&msg, &data, 0);
    MSG_WriteBits(&msg, 42, 32);
    try std.testing.expect(msg.overflowed != 0);
    MSG_BeginReading(&msg);
    try std.testing.expectEqual(@as(c_int, -1), MSG_ReadLong(&msg));
    var guarded: [3]u8 = .{ 0x5a, 0, 0xa5 };
    MSG_Init(&msg, guarded[1..].ptr, 1);
    MSG_WriteBits(&msg, -1, 32);
    try std.testing.expect(msg.overflowed != 0);
    try std.testing.expectEqual(@as(u8, 0x5a), guarded[0]);
    try std.testing.expectEqual(@as(u8, 0xa5), guarded[2]);
}
