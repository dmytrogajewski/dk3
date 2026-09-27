// SPDX-License-Identifier: GPL-2.0-or-later
//! Chaingang owns its ground/hover transitions and overlapping gun callbacks.
pub const attacks = [_][]const u8{ "ataka", "atakf", "transd", "transb", "flyb", "flyc" };
pub const jet_tag = 10018;
pub const flash_model = "models/global/me_mflash.dkm";
pub const State = struct {
    phase: enum { chase, attack, dodge, approach_land, landing, settling, takeoff, rising, wander } = .chase,
    flying: bool = false,
    started_ms: i64 = 0,
    until_ms: i64 = 0,
    strafe_ms: i64 = 0,
    strafe: u3 = 0,
    swoop: bool = false,
    burst: u5 = 0,
    start_position: [3]f32 = @splat(0),
    destination: [3]f32 = @splat(0),
    pub fn gunTick(self: *State) bool {
        const fire = self.burst % 3 != 0;
        self.burst = if (self.burst == 22) 0 else self.burst + 1;
        return fire;
    }
    pub fn reflectStrafe(self: *State) void {
        self.strafe = switch (self.strafe) {
            0 => 1,
            1 => 0,
            2 => 5,
            3 => 4,
            4 => 3,
            5 => 2,
            else => unreachable,
        };
    }
};
test "chaingang burst retains its silent first tick and every-third-tick gaps" {
    const t = @import("std").testing;
    var state: State = .{};
    try t.expect(!state.gunTick());
    var fired: usize = 0;
    for (1..23) |_| if (state.gunTick()) {
        fired += 1;
    };
    try t.expectEqual(@as(usize, 15), fired);
    try t.expectEqual(@as(u5, 0), state.burst);
    var restored = state;
    try t.expect(!restored.gunTick());
}
