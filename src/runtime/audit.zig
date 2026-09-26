// SPDX-License-Identifier: GPL-2.0-or-later
//! Read-only validation/roundtrip of the existing portable save stream.
const std = @import("std");
const stream = @import("domain/save_stream.zig");
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 2) return error.ExpectedSavePath;
    const data = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], allocator, .limited(stream.limit));
    try stream.Reader.validate(data);
    const output = try allocator.alloc(u8, data.len);
    var writer = try stream.Writer.init(output);
    var reader = try stream.Reader.init(data);
    var records: usize = 0;
    var fields: usize = 0;
    while (try reader.nextRecord()) |record| {
        try writer.record(record.name, record.id);
        records += 1;
        while (try reader.nextField()) |field| {
            try writer.raw(field);
            fields += 1;
        }
    }
    if (!std.mem.eql(u8, data, try writer.finish())) return error.RoundtripMismatch;
    var bytes: [512]u8 = undefined;
    var out = std.Io.File.Writer.initStreaming(.stdout(), init.io, &bytes);
    try out.interface.print("save codec: {d} records, {d} fields, {d} bytes; exact roundtrip (world reconstruction not qualified)\n", .{ records, fields, data.len });
    try out.interface.flush();
}
