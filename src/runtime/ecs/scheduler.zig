// SPDX-License-Identifier: GPL-2.0-or-later
//! Explicit DAG plus component/resource conflicts. Engine-affine jobs stay serial.
const std = @import("std");
const jobs = @import("jobs.zig");
pub const Access = struct {
    read: u64 = 0,
    write: u64 = 0,
    resource_read: u64 = 0,
    resource_write: u64 = 0,
    pub fn conflicts(a: Access, b: Access) bool {
        return a.write & (b.read | b.write) != 0 or b.write & a.read != 0 or
            a.resource_write & (b.resource_read | b.resource_write) != 0 or b.resource_write & a.resource_read != 0;
    }
};
pub const System = struct {
    name: []const u8,
    access: Access,
    after: u64 = 0,
    affinity: enum { worker, owner } = .worker,
    job: jobs.Job,
};
pub const Schedule = struct {
    prerequisites: [64]u64 = @splat(0),
    count: usize = 0,
    manifests: [64]Manifest = undefined,
    const Manifest = struct { access: Access, after: u64, affinity: @FieldType(System, "affinity"), run: @FieldType(jobs.Job, "run") };
    pub fn init(systems: []const System) !Schedule {
        if (systems.len > 64) return error.SystemLimit;
        var self: Schedule = .{ .count = systems.len };
        const all = bits(systems.len);
        for (systems, 0..) |system, i| {
            self.manifests[i] = .{ .access = system.access, .after = system.after, .affinity = system.affinity, .run = system.job.run };
            const bit = @as(u64, 1) << @intCast(i);
            if (system.after & ~all != 0 or system.after & bit != 0) return error.InvalidDependency;
            self.prerequisites[i] = system.after;
            for (systems[0..i], 0..) |prior, j| {
                if (std.mem.eql(u8, system.name, prior.name)) return error.DuplicateSystem;
                if (system.access.conflicts(prior.access)) self.prerequisites[i] |= @as(u64, 1) << @intCast(j);
            }
        }
        var complete: u64 = 0;
        while (complete != all) {
            const available = self.ready(complete);
            if (available == 0) return error.DependencyCycle;
            complete |= available;
        }
        return self;
    }
    fn bits(count: usize) u64 {
        return if (count == 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(count)) - 1;
    }
    fn ready(self: Schedule, complete: u64) u64 {
        var result: u64 = 0;
        for (self.prerequisites[0..self.count], 0..) |required, i| {
            const bit = @as(u64, 1) << @intCast(i);
            if (complete & bit == 0 and required & ~complete == 0) result |= bit;
        }
        return result;
    }
    pub fn run(self: Schedule, pool: *jobs.Pool, systems: []System) !void {
        if (systems.len != self.count) return error.ScheduleMismatch;
        if (pool.owner != std.Thread.getCurrentId()) return error.WrongThread;
        for (systems, self.manifests[0..self.count]) |system, manifest| {
            if (!std.meta.eql(system.access, manifest.access) or system.after != manifest.after or
                system.affinity != manifest.affinity or system.job.run != manifest.run) return error.ScheduleMismatch;
        }
        var complete: u64 = 0;
        while (complete != bits(self.count)) {
            const ready_set = self.ready(complete);
            var batch: [64]jobs.Job = undefined;
            var count: usize = 0;
            for (systems, 0..) |*system, i| {
                if (ready_set & (@as(u64, 1) << @intCast(i)) == 0) continue;
                if (system.affinity == .owner) try system.job.run(system.job.context) else {
                    batch[count] = system.job;
                    count += 1;
                }
            }
            try pool.run(batch[0..count]);
            complete |= ready_set;
        }
    }
};

test "dependencies and conflicts reject cycles" {
    const Noop = struct {
        fn run(_: *anyopaque) !void {}
    };
    var context: u8 = 0;
    var systems = [_]System{
        .{ .name = "movement", .access = .{ .write = 1 }, .job = .{ .run = Noop.run, .context = &context } },
        .{ .name = "collision", .access = .{ .read = 1 }, .affinity = .owner, .job = .{ .run = Noop.run, .context = &context } },
    };
    const schedule = try Schedule.init(&systems);
    try std.testing.expectEqual(@as(u64, 1), schedule.prerequisites[1]);
    systems[0].after = 2;
    try std.testing.expectError(error.DependencyCycle, Schedule.init(&systems));
}

test "conflicting workers finish before owner and changed manifests are rejected" {
    const Context = struct {
        value: u32 = 0,
        owner: std.Thread.Id,
        fn produce(raw: *anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.value = 41;
        }
        fn consume(raw: *anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try std.testing.expectEqual(self.owner, std.Thread.getCurrentId());
            try std.testing.expectEqual(@as(u32, 41), self.value);
            self.value += 1;
        }
    };
    for ([_]usize{ 0, 1, 4 }) |workers| {
        const pool = try jobs.Pool.create(std.testing.allocator, workers);
        defer pool.destroy();
        var context: Context = .{ .owner = std.Thread.getCurrentId() };
        var systems = [_]System{
            .{ .name = "produce", .access = .{ .write = 1 }, .job = .{ .run = Context.produce, .context = &context } },
            .{ .name = "consume", .access = .{ .read = 1 }, .affinity = .owner, .job = .{ .run = Context.consume, .context = &context } },
        };
        const schedule = try Schedule.init(&systems);
        try schedule.run(pool, &systems);
        try std.testing.expectEqual(@as(u32, 42), context.value);
        systems[1].access = .{};
        try std.testing.expectError(error.ScheduleMismatch, schedule.run(pool, &systems));
        try std.testing.expectEqual(@as(u32, 42), context.value);
    }
}
