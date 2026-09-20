//! Test-only fixture for the dkguard e2e suite: allocates `<MiB>` mebibytes, writes every page so
//! the memory is resident, then prints a success line. A memory cap must stop it before that line.
// FRD: specs/frds/FRD-002-dkguard-resource-guard-for-heavy-workloads.md
const std = @import("std");

const mib = 1 << 20;
/// R7: probes stay far below 1 GB even when no cap applies.
const max_mib = 256;
const fill_byte = 0xA5;

const status_usage = 64;
const status_allocation_failed = 71;

pub fn main(init: std.process.Init) !u8 {
    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    if (argv.len != 2) return status_usage;
    const size_mib = std.fmt.parseUnsigned(usize, argv[1], 10) catch return status_usage;
    if (size_mib == 0 or size_mib > max_mib) return status_usage;

    const block = std.heap.page_allocator.alloc(u8, size_mib * mib) catch return status_allocation_failed;
    defer std.heap.page_allocator.free(block);
    @memset(block, fill_byte);

    var buf: [64]u8 = undefined;
    var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &buf);
    try stdout.interface.print("alloc-probe: touched {d} MiB\n", .{size_mib});
    try stdout.interface.flush();
    return 0;
}
