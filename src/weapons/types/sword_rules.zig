// SPDX-License-Identifier: GPL-2.0-or-later
const c = @import("../abi.zig").c;
const rules = @import("../sword_rules.zig");
pub export const dk_swordSwings = blk: {
    var output: [c.DK_SWORD_SWINGS]c.dkSwordSwing_t = undefined;
    for (rules.swings, 0..) |swing, i| output[i] = .{ .pose = if (swing.pose) |pose| pose.ptr else null, .hits = swing.hits, .damageFrame = swing.damageFrame, .followThrough = swing.followThrough, .next = swing.next, .from = swing.from, .to = swing.to };
    break :blk output;
};
pub export fn DK_SwordLevel(experience: c_int) callconv(.c) c_int {
    return rules.level(experience);
}
pub export fn DK_SwordFrameTime(experience: c_int) callconv(.c) c_int {
    return rules.frameTime(experience);
}
pub export fn DK_SwordSelect(previous: c_int, seed: c_uint) callconv(.c) c_int {
    return rules.select(previous, seed);
}
