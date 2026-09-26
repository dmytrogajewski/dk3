// SPDX-License-Identifier: GPL-2.0-or-later
//! Explicit owner-thread barriers: activation, deadlines, collision, arrival, targets.
const data = @import("../domain/components.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Router = @import("targets.zig").Router;
const binary = @import("movers.zig");
const trains = @import("trains.zig");
const special = @import("special_movers.zig");
pub fn spawn(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    try @import("brushes.zig").spawn(world, slots, projections);
    try binary.spawn(world, slots, projections);
    try @import("targets.zig").spawn(world);
    try trains.spawn(world, slots, projections, now);
    try special.spawn(world, slots, projections, now);
    try @import("attachments.zig").spawn(world);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, targets: *Router, now: i64, elapsed: u32) !void {
    try @import("interactions.zig").touch(world, slots, projections, targets, now);
    try binary.prepare(world, slots, projections, now);
    try trains.prepare(world, slots, projections, now);
    try special.prepare(world, slots, projections, now);
    try binary.step(world, slots, projections, now, elapsed);
    try trains.step(world, slots, projections, now, elapsed);
    try special.step(world, slots, projections, now, elapsed);
    try @import("pusher.zig").staticRoots(world, slots, projections, now, elapsed);
    const arrivals = try binary.finish(world, slots, projections, now);
    const train_arrivals = try trains.finish(world, slots, projections, now);
    const secret_arrivals = try special.finish(world, slots, projections, now);
    for (arrivals.entities[0..arrivals.count]) |entity| {
        if (!world.alive(entity)) continue;
        try targets.fire(world, slots, projections, entity, (try world.get(entity, data.Mover)).owner, now);
    }
    for (secret_arrivals.entities[0..secret_arrivals.count]) |entity| {
        if (!world.alive(entity)) continue;
        try targets.fire(world, slots, projections, entity, (try world.get(entity, data.Secret)).owner, now);
    }
    for (train_arrivals.entities[0..train_arrivals.count]) |entity| {
        if (!world.alive(entity)) continue;
        const train = (try world.get(entity, data.Train)).*;
        if (world.find(train.destination)) |point| {
            const object = (try world.get(point, data.MapObject)).*;
            const name = @import("properties.zig").text(object, "pathtarget") orelse "";
            try targets.fireNamed(world, slots, projections, name, entity, train.owner, now);
        }
    }
    try targets.step(world, slots, projections, now);
}
