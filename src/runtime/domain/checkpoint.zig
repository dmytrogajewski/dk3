// SPDX-License-Identifier: GPL-2.0-or-later
//! Single-player recovery is gated by an admitted checkpoint and post-death input.
pub const slot = "dk3-restart-internal";
pub const State = struct {
    pending: bool = true,
    available: bool = false,
    died_ms: ?i64 = null,
    retry_ms: i64 = 0,
    pub fn saved(self: *State) void {
        self.* = .{ .pending = false, .available = true };
    }
    pub fn wantsRestart(self: *State, alive: bool, pressed: bool, now: i64) bool {
        if (alive) {
            self.died_ms = null;
            self.retry_ms = 0;
            return false;
        }
        if (self.died_ms == null) self.died_ms = now;
        if (!pressed or now < self.died_ms.? + 4000 or now < self.retry_ms) return false;
        self.retry_ms = now + 5000;
        return true;
    }
};
test "death recovery waits for input and cannot repeatedly enqueue loads" {
    const t = @import("std").testing;
    var state: State = .{};
    state.saved();
    try t.expect(!state.wantsRestart(false, true, 100));
    try t.expect(!state.wantsRestart(false, true, 4099));
    try t.expect(!state.wantsRestart(false, false, 4100));
    try t.expect(state.wantsRestart(false, true, 4100));
    try t.expect(!state.wantsRestart(false, true, 4200));
    try t.expect(!state.wantsRestart(true, true, 4300));
    try t.expect(!state.wantsRestart(false, true, 4400));
}
