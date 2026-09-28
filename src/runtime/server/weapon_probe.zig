// SPDX-License-Identifier: GPL-2.0-or-later
//! Read-only physical controller ownership, for explicit development fixtures.
const std = @import("std");
const data = @import("../domain/components.zig");
const access = @import("region_access.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
fn inspectLocal(world: *data.World, slots: *const Slots, name: []const u8) !void {
    for (slots.occupants) |maybe| if (maybe) |entity| {
        const pose = world.get(entity, data.Transform) catch continue;
        var buffer: [640]u8 = undefined;
        var details: [320]u8 = undefined;
        var owner: u32 = 0;
        const kind: []const u8, const state: []const u8 = blk: {
            if (world.get(entity, data.Projectile) catch null) |projectile| {
                owner = projectile.owner;
                const text = switch (projectile.flight) {
                    .wyndrax => |wisp| try std.fmt.bufPrint(&details, "phase={s} enemy={d} targets={d},{d},{d},{d}", .{ @tagName(wisp.phase), wisp.enemy orelse 0, wisp.targets[0], wisp.targets[1], wisp.targets[2], wisp.targets[3] }),
                    .metamaser => |cube| try std.fmt.bufPrint(&details, "phase={s} charges={d} locks={d},{d},{d},{d} bursts={d}", .{ @tagName(cube.phase), cube.charges, cube.acquired[0].target, cube.acquired[1].target, cube.acquired[2].target, cube.acquired[3].target, cube.bursts }),
                    .trident => |tip| try std.fmt.bufPrint(&details, "tip={s} leader={d} left={d} right={d} charged={d}", .{ @tagName(tip.kind), tip.leader, tip.left, tip.right, @intFromBool(tip.charged) }),
                    .discus => |disc| try std.fmt.bufPrint(&details, "target={d} reflected={d} dropped={d} pickup={d}", .{ disc.target orelse 0, @intFromBool(disc.reflected), @intFromBool(disc.dropped), @intFromBool(disc.pickup_only) }),
                    .sunflare => |flame| try std.fmt.bufPrint(&details, "phase={s} floating={d}", .{ @tagName(flame.phase), @intFromBool(flame.floating) }),
                    else => "",
                };
                break :blk .{ @tagName(projectile.flight), text };
            }
            if (world.get(entity, data.Nightmare) catch null) |ritual| {
                owner = ritual.owner;
                const victim = access.find(world, ritual.victim orelse 0);
                const motion = if (victim) |ref| (try ref.get(data.Body)).motion_owner orelse 0 else 0;
                break :blk .{ "nightmare", try std.fmt.bufPrint(&details, "phase={s} victim={d} freeze={d} targets={d}", .{ @tagName(ritual.phase), ritual.victim orelse 0, motion, ritual.count }) };
            }
            if (world.get(entity, data.Zeus) catch null) |chain| {
                owner = chain.owner;
                break :blk .{ "zeus", try std.fmt.bufPrint(&details, "phase={s} targets={d} active={d} zaps={d}", .{ @tagName(chain.phase), chain.count, chain.active, chain.zaps }) };
            }
            if (world.get(entity, data.ZeusBolt) catch null) |bolt| {
                owner = bolt.owner;
                break :blk .{ "zeus_bolt", try std.fmt.bufPrint(&details, "phase={s} source={d} target={d} chain={d}", .{ @tagName(bolt.phase), bolt.source, bolt.target, bolt.chain }) };
            }
            if (world.get(entity, data.Charge) catch null) |charge| {
                owner = charge.owner;
                break :blk .{ "c4", try std.fmt.bufPrint(&details, "attached={d} detonate={d}", .{ @intFromBool(charge.attached), charge.detonate_ms orelse -1 }) };
            }
            continue;
        };
        engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 region weapon: id={d} map={s} kind={s} owner={d} pos={d:.3},{d:.3},{d:.3} {s}\n", .{ try world.persistentId(entity), name, kind, owner, pose.position[0], pose.position[1], pose.position[2], state }));
    };
}
pub fn inspect(world: *data.World, slots: *const Slots) !void {
    const context = access.contextFor(world);
    try inspectLocal(world, slots, if (context) |owner| std.mem.sliceTo(&owner.map_name, 0) else "local");
    if (context) |owner| {
        var neighbors = access.Neighbors.init(owner);
        while (neighbors.next()) |neighbor| if (&neighbor.world.? != world) {
            try inspectLocal(&neighbor.world.?, &neighbor.slots, std.mem.sliceTo(&neighbor.map_name, 0));
        };
    }
    engine.print("dk3 region weapons complete\n");
}
