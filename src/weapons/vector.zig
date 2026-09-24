// SPDX-License-Identifier: GPL-2.0-or-later
//! Value vectors keep engine ABI arrays at the boundary.
pub const Vec = [3]f32;
pub const zero: Vec = .{ 0, 0, 0 };
pub fn add(a: Vec, b: Vec) Vec {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
pub fn sub(a: Vec, b: Vec) Vec {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
pub fn scale(a: Vec, k: f32) Vec {
    return .{ a[0] * k, a[1] * k, a[2] * k };
}
pub fn madd(a: Vec, k: f32, b: Vec) Vec {
    return add(a, scale(b, k));
}
pub fn dot(a: Vec, b: Vec) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
pub fn length(a: Vec) f32 {
    return @sqrt(dot(a, a));
}
pub fn distance(a: Vec, b: Vec) f32 {
    return length(sub(a, b));
}
pub fn normal(a: Vec) Vec {
    const len = length(a);
    return if (len > 0) scale(a, 1 / len) else zero;
}
pub fn f(value: anytype) f32 {
    return @floatFromInt(value);
}
pub fn i(value: f32) c_int {
    return @intFromFloat(value);
}
