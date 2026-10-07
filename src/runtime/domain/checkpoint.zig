// SPDX-License-Identifier: GPL-2.0-or-later
//! Single-player recovery is gated by an admitted checkpoint and post-death input.
pub const slot = "dk3-restart-internal";
pub const arrival_slot = "autosave-arrival";
pub const periodic_slot = "autosave";
pub const Autosave = struct {
    next_ms: ?i64 = null,
    retry_ms: i64 = 0,
    pub fn healthy(current: i32, maximum: i32) bool {
        return maximum > 0 and @as(i64, current) * 10 > @as(i64, maximum) * 9;
    }
    /// An arrival replaces an existing death checkpoint only with at least
    /// half health: arriving at 2 health beside a guard post would otherwise
    /// make every restart a death. It stays pending until then.
    pub fn arrivalAdmits(current: i32, maximum: i32, existing: bool) bool {
        return !existing or (maximum > 0 and @as(i64, current) * 2 >= maximum);
    }
    pub fn due(self: *Autosave, now: i64) bool {
        if (self.next_ms == null) self.completed(now);
        return now >= self.next_ms.? and now >= self.retry_ms;
    }
    pub fn completed(self: *Autosave, now: i64) void {
        self.* = .{ .next_ms = now + 60000 };
    }
};
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
test "a hurt arrival keeps an existing checkpoint" {
    const t = @import("std").testing;
    try t.expect(Autosave.arrivalAdmits(2, 100, false));
    try t.expect(!Autosave.arrivalAdmits(2, 100, true));
    try t.expect(!Autosave.arrivalAdmits(49, 100, true));
    try t.expect(Autosave.arrivalAdmits(50, 100, true));
}
test "periodic saving requires strictly more than ninety percent and a completed minute" {
    const t = @import("std").testing;
    var autosave: Autosave = .{};
    try t.expect(!autosave.due(100));
    try t.expect(!autosave.due(60099));
    try t.expect(autosave.due(60100));
    try t.expect(!Autosave.healthy(90, 100));
    try t.expect(Autosave.healthy(91, 100));
    try t.expect(!Autosave.healthy(180, 200));
    try t.expect(Autosave.healthy(181, 200));
    try t.expect(!Autosave.healthy(0, 100));
    autosave.retry_ms = 65100;
    try t.expect(!autosave.due(61000));
    try t.expect(autosave.due(65100));
    autosave.completed(65100);
    try t.expect(!autosave.due(65101));
}
