// SPDX-License-Identifier: GPL-2.0-or-later
//! Actor death material and authored gib eligibility, independent of difficulty scaling.
const Kind = @import("catalog.zig").Kind;
pub const Policy = struct {
    robotic: bool = false,
    no_blood: bool = false,
    bone: bool = false,
    always: bool = false,
    never: bool = false,
    pub fn eligible(self: Policy, flags: u32, damage: i32, remaining: i32, base_health: f32) bool {
        return !self.never and (self.always or flags & 0x400 != 0 or @as(f64, @floatFromInt(damage)) >= @as(f64, base_health) * 0.3 or @as(f32, @floatFromInt(remaining)) < -base_health * 0.5);
    }
};
pub fn forKind(kind: Kind) Policy {
    return switch (kind) {
        .cambot, .deathsphere, .lasergat, .protopod, .thunderskeet, .skeeter, .rockgat => .{ .robotic = true, .no_blood = true, .always = true },
        .battleboar, .crox, .venomvermin, .ragemaster, .inmater, .sludgeminion, .froginator => .{ .robotic = true, .no_blood = true },
        .dragon, .harpy, .griffon, .lycanthir, .dopefish, .fish, .seagull => .{ .always = true },
        .ghost => .{ .never = true, .no_blood = true },
        .garroth, .companion => .{ .never = true },
        .column => .{ .never = true, .no_blood = true, .robotic = true },
        .skeleton => .{ .bone = true, .no_blood = true },
        else => .{},
    };
}
pub fn forClass(kind: Kind, classname: []const u8) Policy {
    var result = forKind(kind);
    if (@import("std").mem.eql(u8, classname, "monster_fatworker")) result.always = true;
    return result;
}
test "fragment thresholds retain no-gib overrides and mechanical materials" {
    const t = @import("std").testing;
    try t.expect(forKind(.skeeter).eligible(0, 1, 0, 100));
    try t.expect(forKind(.skeeter).no_blood);
    try t.expect(!forKind(.crox).eligible(0, 29, -50, 100));
    try t.expect(forKind(.crox).eligible(0, 30, 0, 100));
    try t.expect(forKind(.crox).eligible(0, 1, -51, 100));
    try t.expect(!forKind(.garroth).eligible(0x400, 1000, -1000, 100));
    try t.expect(forKind(.mishima_guard).eligible(0x400, 1, 0, 100));
}
