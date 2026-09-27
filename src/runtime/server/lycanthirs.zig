// SPDX-License-Identifier: GPL-2.0-or-later
//! Resurrection preserves identity and never dispatches a false kill or authored death output.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub fn revive(world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, body: *data.Body, definition: @import("../domain/actors.zig").Definition, now: i64) !bool {
    const state = &actor.lycanthir;
    if (state.phase == .living) return false;
    actor.mode = .idle;
    actor.melee.active = false;
    actor.reaction = null;
    actor.reaction_until_ms = null;
    actor.scripted_pose = null;
    (try world.get(entity, data.Velocity)).linear = @splat(0);
    const slot = (try world.get(entity, data.Binding)).slot;
    if (state.phase == .collapsed) {
        if (!state.prepared) {
            const radius = @max(@max(@max(@abs(definition.mins[0]), @abs(definition.mins[1])), @abs(definition.mins[2])), @max(@max(@abs(definition.maxs[0]), @abs(definition.maxs[1])), @abs(definition.maxs[2])));
            body.mins = .{ -radius, -radius, definition.mins[2] };
            body.maxs = .{ radius, radius, 5 };
            body.contents = c.CONTENTS_CORPSE;
            state.prepared = true;
        }
        if (now <= state.wake_ms) return true;
        // Check the restored standing hull too: resurrection must not trap a
        // player or stand up inside a closed mover.
        const trace = try engine.collisionService().trace(.{ .start = pose.position, .end = pose.position, .mins = definition.mins, .maxs = definition.maxs, .slot = slot, .mask = c.MASK_PLAYERSOLID });
        if (trace.start_solid or trace.all_solid) {
            state.wake_ms = now + 1000;
            return true;
        }
        state.phase = .rising;
        state.started_ms = now;
        body.mins = definition.mins;
        body.maxs = definition.maxs;
        body.contents = c.CONTENTS_BODY;
        return true;
    }
    if (now - state.started_ms < definition.death.duration()) return true;
    state.* = .{};
    (try world.get(entity, data.Health)).current = definition.health;
    actor.receipt = (try world.get(entity, data.Hurt)).revision;
    actor.changed_ms = now;
    actor.think_ms = now;
    return false;
}
pub fn frame(actor: data.Actor, definition: @import("../domain/actors.zig").Definition, now: i64) ?u16 {
    if (actor.mode == .dead or actor.lycanthir.phase == .living) return null;
    const forward = definition.death.frame(now - actor.lycanthir.started_ms, false);
    return if (actor.lycanthir.phase == .rising) definition.death.last - (forward - definition.death.first) else forward;
}
