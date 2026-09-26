// SPDX-License-Identifier: GPL-2.0-or-later
//! Ballistic proposals run on workers; engine collision is resolved on the owner.
//! Player pmove, movers and weapon-specific projectile controllers are separate systems.
const std = @import("std");
const data = @import("../domain/components.zig");
const collision = @import("../domain/collision.zig");
const jobs = @import("../ecs/jobs.zig");
const W = data.World;
const scheduler = @import("../ecs/scheduler.zig");
const required = W.mask(.{ data.Transform, data.Velocity, data.Gravity, data.Body, data.Motion, data.Binding });
const Proposal = struct {
    view: W.View,
    delta_seconds: f32,
    fn run(raw: *anyopaque) !void {
        const self: *Proposal = @ptrCast(@alignCast(raw));
        const positions = self.view.read(data.Transform);
        const velocities = self.view.read(data.Velocity);
        const gravities = self.view.read(data.Gravity);
        const bodies = self.view.read(data.Body);
        for (self.view.write(data.Motion), 0..) |*motion, i| {
            motion.velocity = velocities[i].linear;
            if (!bodies[i].grounded) motion.velocity[2] -= gravities[i].acceleration * self.delta_seconds;
            for (0..3) |axis| motion.destination[axis] = positions[i].position[axis] + motion.velocity[axis] * self.delta_seconds;
        }
    }
};
const Frame = struct {
    world: *W,
    pool: *jobs.Pool,
    service: collision.Collision,
    delta_ms: u32,
    fn propose(raw: *anyopaque) !void {
        const self: *Frame = @ptrCast(@alignCast(raw));
        try proposals(self.world, self.pool, self.delta_ms);
    }
    fn collide(raw: *anyopaque) !void {
        const self: *Frame = @ptrCast(@alignCast(raw));
        try resolveCollisions(self.world, self.service);
    }
};
pub fn step(world: *W, pool: *jobs.Pool, service: collision.Collision, delta_ms: u32) !void {
    if (std.Thread.getCurrentId() != pool.owner) return error.WrongThread;
    if (delta_ms == 0) return;
    var frame: Frame = .{ .world = world, .pool = pool, .service = service, .delta_ms = delta_ms };
    var systems = [_]scheduler.System{
        // Dispatch on owner so the query epoch encloses all disjoint chunk jobs.
        .{ .name = "ballistic proposals", .affinity = .owner, .access = .{ .read = required & ~W.mask(.{data.Motion}), .write = W.mask(.{data.Motion}) }, .job = .{ .run = Frame.propose, .context = &frame } },
        .{ .name = "collision resolution", .affinity = .owner, .access = .{ .read = required, .write = W.mask(.{ data.Transform, data.Velocity, data.Body }), .resource_write = 1 }, .job = .{ .run = Frame.collide, .context = &frame } },
    };
    const schedule = try scheduler.Schedule.init(&systems);
    try schedule.run(pool, &systems);
}
fn proposals(world: *W, pool: *jobs.Pool, delta_ms: u32) !void {
    var query = world.queryAccess(required, 0, W.mask(.{data.Motion}));
    var contexts: [1024]Proposal = undefined;
    var batch: [1024]jobs.Job = undefined;
    var count: usize = 0;
    {
        defer query.deinit();
        while (query.next()) |view| {
            if (count == contexts.len) return error.JobCapacity;
            contexts[count] = .{ .view = view, .delta_seconds = @as(f32, @floatFromInt(delta_ms)) / 1000 };
            batch[count] = .{ .run = Proposal.run, .context = &contexts[count] };
            count += 1;
        }
        try pool.run(batch[0..count]);
    }
}
fn resolveCollisions(world: *W, service: collision.Collision) !void {
    var resolve = world.queryAccess(required, 0, W.mask(.{ data.Transform, data.Velocity, data.Body }));
    defer resolve.deinit();
    while (resolve.next()) |view| {
        const motions = view.read(data.Motion);
        const bindings = view.read(data.Binding);
        const velocities = view.write(data.Velocity);
        const bodies = view.write(data.Body);
        for (view.write(data.Transform), 0..) |*transform, i| {
            const hit = try service.trace(.{ .start = transform.position, .end = motions[i].destination, .mins = bodies[i].mins, .maxs = bodies[i].maxs, .slot = bindings[i].slot, .mask = bodies[i].collision_mask });
            if (!std.math.isFinite(hit.fraction) or hit.fraction < 0 or hit.fraction > 1) return error.InvalidCollision;
            if (hit.start_solid) continue;
            transform.position = hit.end;
            velocities[i].linear = motions[i].velocity;
            bodies[i].grounded = hit.fraction < 1 and hit.normal[2] > 0.7;
            if (hit.fraction < 1) {
                var into: f32 = 0;
                for (0..3) |axis| into += velocities[i].linear[axis] * hit.normal[axis];
                if (into < 0) for (0..3) |axis| {
                    velocities[i].linear[axis] -= into * hit.normal[axis];
                };
            }
        }
    }
}
test "worker counts produce identical motion; collision always runs on owner" {
    const TraceContext = struct {
        owner: std.Thread.Id,
        calls: usize = 0,
        fn trace(raw: *anyopaque, request: collision.Request) !collision.Trace {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (std.Thread.getCurrentId() != self.owner) return error.EngineCalledByWorker;
            self.calls += 1;
            return .{ .fraction = 1, .end = request.end, .normal = .{ 0, 0, 1 } };
        }
    };
    var hashes: [3]u64 = undefined;
    for ([_]usize{ 0, 1, 4 }, 0..) |workers, result| {
        var world = W.init(std.testing.allocator, 128);
        defer world.deinit();
        const pool = try jobs.Pool.create(std.testing.allocator, workers);
        defer pool.destroy();
        for (0..1024) |i| _ = try world.create(null, .{
            data.Transform{ .position = .{ @floatFromInt(i), 0, 100 } },
            data.Velocity{ .linear = .{ 3, 2, 1 } },
            data.Gravity{},
            data.Motion{},
            data.Body{},
            data.Binding{ .slot = @intCast(i) },
        });
        var context: TraceContext = .{ .owner = std.Thread.getCurrentId() };
        for (0..20) |_| try step(&world, pool, .{ .context = &context, .trace_fn = TraceContext.trace }, 50);
        try std.testing.expectEqual(@as(usize, 20480), context.calls);
        var hash = std.hash.Wyhash.init(0);
        var query = world.queryAccess(W.mask(.{data.Transform}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.read(data.Transform)) |transform| {
            hash.update(std.mem.asBytes(&transform.position));
        };
        hashes[result] = hash.final();
    }
    try std.testing.expectEqual(hashes[0], hashes[1]);
    try std.testing.expectEqual(hashes[0], hashes[2]);
}
