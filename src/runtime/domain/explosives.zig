// SPDX-License-Identifier: GPL-2.0-or-later
//! func_explosive material flags are different from decoration material flags.
pub const Material = enum { stone, wood, metal, glass };
pub fn material(flags: u32) Material {
    return if (flags & 16 != 0) .wood else if (flags & 32 != 0) .metal else if (flags & 8 != 0) .stone else .glass;
}
pub fn model(kind: Material, alternate: bool) []const u8 {
    return switch (kind) {
        .stone => if (alternate) "models/global/e_rock2.dkm" else "models/global/e_rock1.dkm",
        .wood => if (alternate) "models/global/e_wood2.dkm" else "models/global/e_wood1.dkm",
        .metal => if (alternate) "models/global/e_metal2.dkm" else "models/global/e_metal1.dkm",
        .glass => if (alternate) "models/global/e_glass2.dkm" else "models/global/e_glass1.dkm",
    };
}
pub fn count(base: f32, random_count: f32, chance: f32) usize {
    return @intFromFloat(@import("std").math.clamp(base + chance * random_count, @min(20, @max(0, base * 0.5)), 20));
}
test "bridge stone flag and metal boxes retain their distinct materials and bounded counts" {
    const t = @import("std").testing;
    try t.expectEqual(Material.stone, material(8));
    try t.expectEqual(Material.metal, material(32800));
    try t.expectEqual(Material.glass, material(4));
    try t.expectEqual(@as(usize, 10), count(10, 0, 0.5));
    try t.expectEqual(@as(usize, 20), count(30, 10, 1));
}
