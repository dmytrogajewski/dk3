// SPDX-License-Identifier: GPL-2.0-or-later
//! Co-op bot locomotion and combat as a client. The shared pilot plans one
//! frame of scripted intent; this adapter encodes it as an ordinary user
//! command (and a "use" when pressed) for the single-player client. Nothing
//! here moves entities or changes inventory; the shared player motor does that.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const nav = @import("../domain/navigation.zig");
const pilot = @import("bot_pilot.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Clients = @import("clients.zig").Clients;

pub const Frame = struct {
    world: *data.World,
    slots: *Slots,
    projections: []abi.EntityProjection,
    clients: *Clients,
    service: nav.Service,
    index: u16,
    entity: ecs.Entity,
    now: i64,
    /// Live navigation gates of this world, for planning past closed ones.
    gates: ?*@import("navigation_gates.zig").State = null,
};
pub const Intent = pilot.Intent;
pub const Report = pilot.Report;
pub const Motor = pilot.Pilot;

/// The pilot's view of the client: its own player state, the engine's
/// collision and the client weapon table, with every capability.
pub fn pilotFrame(frame: Frame) !pilot.Frame {
    return .{
        .world = frame.world,
        .slots = frame.slots,
        .projections = frame.projections,
        .service = frame.service,
        .collision = engine.collisionService(),
        .table = &frame.clients.weapon_table,
        .slot = frame.index,
        .entity = frame.entity,
        .state = (try frame.world.get(frame.entity, data.Player)).*,
        .now = frame.now,
        .gates = frame.gates,
    };
}
pub fn drive(motor: *Motor, frame: Frame, intent: Intent) !Report {
    const steering = try motor.steer(try pilotFrame(frame), intent);
    @import("bot_input.zig").submit(frame.index, steering.command, (try frame.world.get(frame.entity, data.Player)).delta_angles, frame.now);
    return steering.report;
}
