// SPDX-License-Identifier: GPL-2.0-or-later
//! Persistent bounded workers. Only the owner starts batches and joins them.
const std = @import("std");
const assert = std.debug.assert;
pub const Job = struct {
    run: *const fn (*anyopaque) anyerror!void,
    context: *anyopaque,
    failure: ?anyerror = null,
};
pub const Pool = struct {
    allocator: std.mem.Allocator,
    owner: std.Thread.Id,
    threads: [8]std.Thread = undefined,
    thread_count: usize = 0,
    mutex: std.c.pthread_mutex_t = .{},
    wake: std.c.pthread_cond_t = .{},
    done: std.c.pthread_cond_t = .{},
    stopping: bool = false,
    active: bool = false,
    jobs: []Job = &.{},
    next: usize = 0,
    remaining: usize = 0,

    pub fn defaultWorkers() usize {
        return @min(8, (std.Thread.getCpuCount() catch 1) -| 1);
    }
    pub fn create(allocator: std.mem.Allocator, workers: usize) !*Pool {
        if (workers > 8) return error.WorkerLimit;
        const self = try allocator.create(Pool);
        self.* = .{ .allocator = allocator, .owner = std.Thread.getCurrentId() };
        errdefer self.destroy();
        while (self.thread_count < workers) : (self.thread_count += 1)
            self.threads[self.thread_count] = try std.Thread.spawn(.{}, worker, .{self});
        return self;
    }
    fn lock(self: *Pool) void {
        assert(std.c.pthread_mutex_lock(&self.mutex) == .SUCCESS);
    }
    fn unlock(self: *Pool) void {
        assert(std.c.pthread_mutex_unlock(&self.mutex) == .SUCCESS);
    }
    pub fn run(self: *Pool, jobs: []Job) !void {
        if (std.Thread.getCurrentId() != self.owner) return error.WrongThread;
        if (self.active) return error.NestedBatch;
        if (jobs.len == 0) return;
        for (jobs) |*job| job.failure = null;
        if (self.thread_count == 0) {
            self.active = true;
            defer self.active = false;
            for (jobs) |*job| job.run(job.context) catch |err| {
                job.failure = err;
            };
        } else {
            self.lock();
            self.active = true;
            self.jobs = jobs;
            self.next = 0;
            self.remaining = jobs.len;
            assert(std.c.pthread_cond_broadcast(&self.wake) == .SUCCESS);
            while (self.remaining != 0) assert(std.c.pthread_cond_wait(&self.done, &self.mutex) == .SUCCESS);
            self.jobs = &.{};
            self.next = 0;
            self.active = false;
            self.unlock();
        }
        // Completion order never determines which failure is reported.
        for (jobs) |job| if (job.failure) |err| return err;
    }
    fn worker(self: *Pool) void {
        self.lock();
        defer self.unlock();
        while (true) {
            while (!self.stopping and self.next >= self.jobs.len)
                assert(std.c.pthread_cond_wait(&self.wake, &self.mutex) == .SUCCESS);
            if (self.stopping) return;
            const index = self.next;
            self.next += 1;
            const job = &self.jobs[index];
            self.unlock();
            job.run(job.context) catch |err| {
                job.failure = err;
            };
            self.lock();
            self.remaining -= 1;
            if (self.remaining == 0) assert(std.c.pthread_cond_signal(&self.done) == .SUCCESS);
        }
    }
    pub fn destroy(self: *Pool) void {
        assert(self.owner == std.Thread.getCurrentId() and !self.active);
        self.lock();
        self.stopping = true;
        assert(std.c.pthread_cond_broadcast(&self.wake) == .SUCCESS);
        self.unlock();
        for (self.threads[0..self.thread_count]) |thread| thread.join();
        assert(std.c.pthread_cond_destroy(&self.wake) == .SUCCESS);
        assert(std.c.pthread_cond_destroy(&self.done) == .SUCCESS);
        assert(std.c.pthread_mutex_destroy(&self.mutex) == .SUCCESS);
        self.allocator.destroy(self);
    }
};

test "persistent workers finish all jobs before reporting errors" {
    const Context = struct {
        value: usize = 0,
        fail: bool = false,
        fn run(raw: *anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.value += 1;
            if (self.fail) return error.Expected;
        }
    };
    for ([_]usize{ 0, 1, 4 }) |workers| {
        const pool = try Pool.create(std.testing.allocator, workers);
        defer pool.destroy();
        var contexts: [32]Context = @splat(.{});
        var jobs: [32]Job = undefined;
        for (&jobs, &contexts) |*job, *context| job.* = .{ .run = Context.run, .context = context };
        try pool.run(&jobs);
        contexts[0].fail = true;
        try std.testing.expectError(error.Expected, pool.run(&jobs));
        for (contexts) |context| try std.testing.expectEqual(@as(usize, 2), context.value);
    }
}

test "batch handoff tolerates idle workers and changing queue lengths" {
    const Context = struct {
        count: usize = 0,
        fn run(raw: *anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.count += 1;
        }
    };
    const pool = try Pool.create(std.testing.allocator, 8);
    defer pool.destroy();
    var contexts: [17]Context = @splat(.{});
    var batch: [17]Job = undefined;
    var expected: [17]usize = @splat(0);
    for (&batch, &contexts) |*job, *context| job.* = .{ .run = Context.run, .context = context };
    for (0..1024) |iteration| {
        const count = iteration % batch.len + 1;
        try pool.run(batch[0..count]);
        for (expected[0..count]) |*value| value.* += 1;
        // Let workers observe the empty queue before the next batch.
        if (iteration % 16 == 0) std.Thread.yield() catch {};
    }
    for (contexts, expected) |context, count| try std.testing.expectEqual(count, context.count);
}
