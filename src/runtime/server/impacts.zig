// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("../domain/components.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
pub const Options = struct { charged: bool = false, detonation: bool = false, sequence: i32 = 0 };
pub fn contact(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, weapon: u5, hit: @import("../domain/collision.zig").Trace, options: Options, now: i64) !void {
    if (hit.fraction == 1 or hit.sky or hit.no_impact) return;
    var no_blood = false;
    var kind: @import("weapon_catalog").impact_rules.Kind = switch (hit.material) {
        .ordinary => .world,
        .metal => .metal,
        .wood => .wood,
    };
    if (hit.contents & abi.c.MASK_WATER != 0) kind = .water else if (hit.entity < slots.occupants.len) {
        if (slots.occupants[hit.entity]) |target| if ((world.get(target, data.Actor) catch null) != null or (world.get(target, data.Player) catch null) != null) {
            kind = .flesh;
            if (world.get(target, data.Actor) catch null) |actor| no_blood = @import("actor_catalog").entries[actor.definition].kind == .ghost;
        } else if (world.get(target, data.Scenery) catch null) |scenery| {
            kind = switch (scenery.material) {
                .metal => .metal,
                .wood => .wood,
                .flesh => .flesh,
                else => kind,
            };
        };
    }
    try @import("events.zig").impact(world, slots, projections, .{ .weapon = weapon, .kind = kind, .normal = hit.normal, .charged = options.charged, .detonation = options.detonation, .sequence = options.sequence, .no_blood = no_blood }, hit.end, now);
}
