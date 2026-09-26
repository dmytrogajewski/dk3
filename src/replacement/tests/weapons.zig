// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const weapons = @import("../domain/weapons.zig");
const collision = @import("../domain/collision.zig");
const move = @import("../domain/player_move.zig");
const slide = @import("../domain/slide.zig");
const catalog = @import("weapon_catalog");
fn clear(_: *anyopaque, request: collision.Request) !collision.Trace {
    return .{ .fraction = 1, .end = request.end, .normal = .{ 0, 0, 1 } };
}
const Fixture = struct {
    state: weapons.State = .{},
    table: weapons.Table = .{},
    events: weapons.Events = .{},
    player: move.Player = .{},
    motion: slide.State = .{ .position = .{ 0, 0, 24 }, .velocity = @splat(0) },
    now: i64 = 0,
    fn init(id: u5) Fixture {
        var self: Fixture = .{};
        self.table.entries[id] = .{ .ammoMax = 100, .initialAmmo = 100, .ammoCost = 1, .lifetime = 5 };
        _ = self.state.acquire(&self.table, id, 100);
        return self;
    }
    fn tick(self: *Fixture, milliseconds: u32, attack: bool) !void {
        self.now += milliseconds;
        var context: weapons.Context = .{ .ps = &self.state, .table = &self.table, .events = &self.events, .service = .{ .context = self, .trace_fn = clear }, .slot = 0, .shot_mask = 1 };
        const hook = context.hook();
        try hook.run_fn(hook.context, &self.player, &self.motion, .{ .time_ms = self.now, .angles = @splat(0), .weapon = @intCast(self.state.weapon), .attack = attack }, milliseconds);
    }
};
test "Shotcycler completes six-shot burst after trigger release" {
    var fixture = Fixture.init(4);
    try fixture.tick(1, true);
    for (0..5) |_| try fixture.tick(270, false);
    try std.testing.expectEqual(@as(usize, 6), fixture.events.count);
    try std.testing.expectEqual(@as(i32, 94), fixture.state.ammo[4]);
    try std.testing.expectEqual(@as(i32, 0), fixture.state.dk3Burst);
    try fixture.tick(1000, false);
    try std.testing.expectEqual(@as(usize, 6), fixture.events.count);
    try std.testing.expect(fixture.state.weaponTime > 0);
}
test "Glock ten rounds enter reload and refill from remaining ammunition" {
    var fixture = Fixture.init(21);
    try fixture.tick(1, true);
    for (0..9) |_| try fixture.tick(500, true);
    try std.testing.expectEqual(@as(usize, 10), fixture.events.count);
    try std.testing.expect(catalog.isReloading(&fixture.state));
    try std.testing.expectEqual(@as(i32, 0), fixture.state.dk3GlockClip);
    try fixture.tick(1649, false);
    try std.testing.expect(catalog.isReloading(&fixture.state));
    try fixture.tick(1, false);
    try std.testing.expect(!catalog.isReloading(&fixture.state));
    try std.testing.expectEqual(@as(i32, 10), fixture.state.dk3GlockClip);
    try std.testing.expectEqual(@as(i32, 90), fixture.state.ammo[21]);
}
test "Hammer releases one charged shot and Ripgun waits for spin-up" {
    var hammer = Fixture.init(12);
    for (0..18) |_| try hammer.tick(100, true);
    try std.testing.expectEqual(@as(usize, 0), hammer.events.count);
    try hammer.tick(1, false);
    try std.testing.expectEqual(@as(usize, 1), hammer.events.count);
    try std.testing.expectEqual(@as(i32, 1800), hammer.events.values[0].fired.charge);
    var ripgun = Fixture.init(22);
    for (0..6) |_| try ripgun.tick(50, true);
    try std.testing.expectEqual(@as(usize, 0), ripgun.events.count);
    try ripgun.tick(50, true);
    try std.testing.expectEqual(@as(usize, 1), ripgun.events.count);
}
test "all concrete input policies emit bounded events without engine globals" {
    for (catalog.entries) |entry| {
        var fixture = Fixture.init(entry.id);
        // Some policies need release, and some launch by frame-delayed controllers.
        for (0..80) |frame| try fixture.tick(50, frame < 60);
        try std.testing.expect(fixture.state.ammo[entry.id] >= 0);
        if (entry.id != 28) try std.testing.expect(fixture.events.count > 0);
    }
}
