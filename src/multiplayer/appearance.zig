// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared human/bot/UI catalog. Material variants are not character skin colors.
const std = @import("std");
pub const Entry = struct { selection: [:0]const u8, model: [:0]const u8, skin: [:0]const u8, source: [:0]const u8, label: [:0]const u8 };
pub const entries = blk: {
    @setEvalBranchQuota(30000);
    var result: [36]Entry = undefined;
    var lines = std.mem.tokenizeScalar(u8, @embedFile("appearances.csv"), '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, ',');
        var values: [5][:0]const u8 = undefined;
        for (&values) |*value| {
            const field = fields.next() orelse @compileError("incomplete appearance");
            value.* = (field ++ "\x00")[0..field.len :0];
        }
        if (fields.next() != null) @compileError("extra appearance fields");
        result[count] = .{ .selection = values[0], .model = values[1], .skin = values[2], .source = values[3], .label = values[4] };
        count += 1;
    }
    if (count != result.len) @compileError("appearance catalog count");
    break :blk result;
};
pub fn parse(selection: []const u8) ?usize {
    for (entries, 0..) |entry, i| if (std.ascii.eqlIgnoreCase(entry.selection, selection)) return i;
    // Preserve legacy model-only selections as the character's first skin.
    for (entries[0..3], 0..) |entry, i| if (std.ascii.eqlIgnoreCase(entry.selection[0 .. entry.selection.len - 2], selection)) return i;
    return null;
}
fn getEntry(index: c_int) Entry {
    return entries[if (index >= 0 and index < entries.len) @intCast(index) else 0];
}
export fn DK_AppearanceCount() callconv(.c) c_int {
    return entries.len;
}
export fn DK_AppearanceFind(value: [*:0]const u8) callconv(.c) c_int {
    return if (parse(std.mem.span(value))) |i| @intCast(i) else -1;
}
export fn DK_AppearanceSelection(index: c_int) callconv(.c) [*:0]const u8 {
    return getEntry(index).selection;
}
export fn DK_AppearanceModel(index: c_int) callconv(.c) [*:0]const u8 {
    return getEntry(index).model;
}
export fn DK_AppearanceSkin(index: c_int) callconv(.c) [*:0]const u8 {
    return getEntry(index).skin;
}
export fn DK_AppearanceLabel(index: c_int) callconv(.c) [*:0]const u8 {
    return getEntry(index).label;
}
export fn DK_AppearanceNext(index: c_int, character: c_int) callconv(.c) c_int {
    const valid: usize = if (index >= 0 and index < entries.len) @intCast(index) else 0;
    return @intCast(if (character != 0) (valid / 3) * 3 + (valid + 1) % 3 else (valid + 3) % entries.len);
}

export fn DK_AppearanceChoose(counts: [*c]const c_int, count: c_int) callconv(.c) c_int {
    if (counts == null or count != entries.len) return 0;
    var chosen: usize = 0;
    // Coprime stride visits every combination while varying both character and
    // color immediately, even with just two or three bots.
    for (1..entries.len) |i| {
        const candidate = i * 7 % entries.len;
        if (counts[candidate] < counts[chosen]) chosen = candidate;
    }
    return @intCast(chosen);
}
