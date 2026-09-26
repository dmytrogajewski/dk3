// SPDX-License-Identifier: GPL-2.0-or-later
pub const ecs = @import("ecs/world.zig");
pub const jobs = @import("ecs/jobs.zig");
pub const scheduler = @import("ecs/scheduler.zig");
pub const save_stream = @import("domain/save_stream.zig");
pub const commands = @import("ecs/commands.zig");
pub const components = @import("domain/components.zig");
pub const motion = @import("server/motion.zig");
pub const map = @import("server/map.zig");
test {
    _ = @import("domain/movers.zig");
    _ = @import("domain/weapons.zig");
    _ = @import("domain/tables.zig");
    _ = @import("tests/movement.zig");
    _ = @import("tests/weapons.zig");
    _ = @import("domain/player_move.zig");
    _ = @import("domain/slide.zig");
    _ = @import("domain/time.zig");
    _ = @import("engine/slots.zig");
    _ = @import("inventory_rules");
    _ = ecs;
    _ = jobs;
    _ = scheduler;
    _ = save_stream;
    _ = commands;
    _ = components;
    _ = motion;
    _ = map;
}
