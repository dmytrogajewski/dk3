// SPDX-License-Identifier: GPL-2.0-or-later
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const Random = @import("../domain/components.zig").Random;
const Emitter = struct { serial: i32 = -1, next_tick: i64 = 0 };
var emitters: [2048]Emitter = @splat(.{});
pub fn reset() void {
    emitters = @splat(.{});
}
pub fn emit(model: *const c.refEntity_t, entity: c.entityState_t, now: i32) void {
    if (entity.origin2[1] == 0 or entity.number < 0 or entity.number >= emitters.len) return;
    const emitter = &emitters[@intCast(entity.number)];
    const tick = @divTrunc(@as(i64, now) * 60, 1000);
    if (emitter.serial != entity.time or emitter.next_tick > tick + 1) emitter.* = .{ .serial = entity.time, .next_tick = tick };
    emitter.next_tick = @max(emitter.next_tick, tick - 5);
    while (emitter.next_tick <= tick) : (emitter.next_tick += 1) {
        const at: i32 = @intCast(@divTrunc(emitter.next_tick * 1000, 60));
        var random: Random = .{ .state = @as(u32, @bitCast(at)) ^ (@as(u32, @intCast(entity.number)) *% 2654435761) };
        @import("fx_particles.zig").cloud(v.add(model.origin, .{ 0, 0, -24 }), .{ 0, 0, 1 }, @splat(0.25), .{ 0.45, 0.35, 0.1 }, 3.1 + (random.next() * 2 - 1) * 3, 2, 45, 150, .{ 0, 0, -100 }, 5, .smoke, at, &random);
    }
}
