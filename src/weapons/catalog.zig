// SPDX-License-Identifier: GPL-2.0-or-later
//! Read-only concrete weapon descriptions, shared without linking legacy behavior.
pub const weapons = .{ @import("descriptions/disruptor.zig"), @import("descriptions/ion.zig"), @import("descriptions/c4.zig"), @import("descriptions/shotcycler.zig"), @import("descriptions/sidewinder.zig"), @import("descriptions/shockwave.zig"), @import("descriptions/gas_hands.zig"), @import("descriptions/sword.zig"), @import("descriptions/discus.zig"), @import("descriptions/sunflare.zig"), @import("descriptions/venom.zig"), @import("descriptions/hammer.zig"), @import("descriptions/trident.zig"), @import("descriptions/zeus.zig"), @import("descriptions/silverclaw.zig"), @import("descriptions/bolter.zig"), @import("descriptions/stavros.zig"), @import("descriptions/ballista.zig"), @import("descriptions/wyndrax.zig"), @import("descriptions/nightmare.zig"), @import("descriptions/glock.zig"), @import("descriptions/ripgun.zig"), @import("descriptions/slugger.zig"), @import("descriptions/kineticore.zig"), @import("descriptions/novabeam.zig"), @import("descriptions/metamaser.zig"), @import("descriptions/cordite.zig"), @import("descriptions/flashlight.zig") };
pub const Spec = @import("profiles.zig").Spec;
pub const Entry = struct { id: u5, classname: [:0]const u8, label: [:0]const u8, episode: u8, interval: i32, spec: Spec };
pub const entries = blk: {
    var result: [weapons.len]Entry = undefined;
    for (weapons, 0..) |W, i| result[i] = .{ .id = W.id, .classname = W.identity.classname, .label = W.identity.label, .episode = W.identity.episode, .interval = W.identity.interval, .spec = W.spec };
    break :blk result;
};
pub fn find(id: u5) ?*const Entry {
    for (&entries) |*entry| if (entry.id == id) return entry;
    return null;
}
pub fn starting(episode: u8) u5 {
    for (entries) |entry| if (entry.spec.start_episode == episode) return entry.id;
    return 1;
}

pub fn update(controller: anytype) void {
    inline for (weapons) |W| if (controller.ps.weapon == W.id) {
        W.update(controller);
        return;
    };
}
pub fn isReloading(ps: anytype) bool {
    return ps.weapon == 21 and @import("descriptions/glock.zig").isReloading(ps);
}

pub const transitions = @import("controller.zig");
pub const Shot = @import("shot.zig").Shot;

pub const values = @import("values.zig");

pub const gas = @import("gas_rules.zig");
