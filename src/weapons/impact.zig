// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared presentation values. Concrete weapons select their response to contact.
pub const Kind = enum(u8) { world, flesh, water, metal, wood };
pub const Context = struct { kind: Kind, serial: u32, charged: bool = false };
pub const Style = enum { none, bullet, pellets, disruptor };
pub const Cue = struct {
    sound: ?[:0]const u8 = null,
    mark: ?[:0]const u8 = null,
    radius: f32 = 4,
    particles: u8 = 0,
    particle_shader: [:0]const u8 = "dk3/particle/sparks",
    color: [3]f32 = .{ 1, 0.7, 0.2 },
    light_radius: f32 = 0,
    light_ms: u16 = 120,
};
pub fn standard(style: Style, context: Context) Cue {
    var cue: Cue = switch (style) {
        .none => .{},
        .bullet => .{ .mark = "models/global/we_bhole.sp2/0@mark", .sound = if (context.kind == .flesh) "global/bullethitflesh.wav" else "global/e_ricocheta.wav", .particles = 4 },
        .pellets => .{ .mark = "dk3/fx/shotcycler-mark", .radius = 8, .particles = 6 },
        .disruptor => .{ .mark = "models/global/we_dispunch.sp2/0@mark", .radius = 8, .sound = if (context.kind == .flesh) "e1/we_dglovehita.wav" else "e1/we_dglovehitc.wav", .particles = if (context.charged) 5 else 0, .light_radius = if (context.charged) 350 else 0, .light_ms = 150, .color = .{ 0.3, 0.3, 1 } },
    };
    if (context.kind == .flesh) {
        cue.mark = null;
        if (style == .bullet or style == .pellets) {
            cue.particle_shader = "dk3/particle/blood1";
            cue.color = .{ 0.65, 0.05, 0.02 };
        }
    } else if (context.kind == .water) {
        cue.mark = null;
        cue.sound = null;
        cue.particles = 0;
    }
    return cue;
}
