// SPDX-License-Identifier: GPL-2.0-or-later
pub const Swing = struct { pose: ?[:0]const u8, hits: i32, damageFrame: [2]i32, followThrough: i32, next: i32, from: [2][3]f32, to: [2][3]f32 };
const Vec = [3]f32;
const zero: Vec = .{ 0, 0, 0 };

fn swingSpec(pose: ?[:0]const u8, hits: c_int, first: c_int, second: c_int, follow: c_int, next: c_int, from_a: Vec, from_b: Vec, to_a: Vec, to_b: Vec) Swing {
    return .{
        .pose = pose,
        .hits = hits,
        .damageFrame = .{ first, second },
        .followThrough = follow,
        .next = next,
        .from = .{ from_a, from_b },
        .to = .{ to_a, to_b },
    };
}

pub const swings = [7]Swing{
    swingSpec("ataka", 1, 7, 0, 11, (1 << 5) | (1 << 2) | (1 << 4) | (1 << 6), .{ 0.25, 1, 0 }, zero, .{ 1, -0.25, 0 }, zero),
    swingSpec("atakb", 2, 7, 18, 24, (1 << 0) | (1 << 1) | (1 << 6), .{ 0.25, 1, 1 }, .{ 0.25, -1, -0.25 }, .{ 1, -0.25, 0 }, .{ 1, 0.25, 0 }),
    swingSpec("atakc", 1, 7, 0, 11, (1 << 0) | (1 << 1) | (1 << 4), .{ 0.25, -1, 1 }, zero, .{ 1, 0.25, 0 }, zero),
    swingSpec(null, 0, 0, 0, 0, 0, zero, zero, zero, zero),
    swingSpec("atake", 1, 15, 0, 22, (1 << 0) | (1 << 2) | (1 << 5) | (1 << 6), zero, zero, zero, zero),
    swingSpec("atakf", 1, 6, 0, 10, (1 << 0) | (1 << 1) | (1 << 4) | (1 << 6), .{ 0.25, -1, 0 }, zero, .{ 1, 0.25, 0 }, zero),
    swingSpec("atakg", 1, 10, 0, 16, (1 << 1) | (1 << 2) | (1 << 6) | (1 << 4), .{ 0, 0, 1 }, zero, .{ 1, 0, 0 }, zero),
};

pub fn level(experience: c_int) c_int {
    return if (experience >= 3000) 5 else if (experience >= 1500) 4 else if (experience >= 750) 3 else if (experience >= 250) 2 else 1;
}

pub fn frameTime(experience: c_int) c_int {
    return @max(40 - 4 * level(experience), 20);
}

pub fn select(previous: c_int, seed: c_uint) c_int {
    const mask: c_int = if (previous < 0 or previous >= 7) 0x77 else swings[@intCast(previous)].next;
    var count: c_uint = 0;
    for (0..7) |index| {
        if ((mask & (@as(c_int, 1) << @intCast(index))) != 0) count += 1;
    }
    if (count == 0) return -1;
    var pick = ((seed *% 2654435761) >> 8) % count;
    for (0..7) |index| {
        if ((mask & (@as(c_int, 1) << @intCast(index))) == 0) continue;
        if (pick == 0) return @intCast(index);
        pick -= 1;
    }
    return -1;
}
