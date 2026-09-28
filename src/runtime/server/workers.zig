// SPDX-License-Identifier: GPL-2.0-or-later
//! Fear decisions use the existing actor navigation and audio services.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
const catalog = @import("actor_catalog");
const policy = catalog.workers;
const v = @import("../domain/vector.zig");
pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: @import("../domain/actors.zig").Definition, now: i64) !void {
    const thin = policy.skinny(catalog.entries[actor.definition].classname);
    if (actor.worker.phase == .cower and now >= actor.worker.retry_ms) {
        const enemy = @import("region_access.zig").find(world, actor.threat);
        if (enemy) |target| {
            const point = (try target.get(data.Transform)).position;
            const distance = v.length(v.subtract(pose.position, point));
            if (distance > definition.sight_range or !thin) {
                actor.worker.phase = .calm;
                actor.threat = 0;
            } else if (distance < policy.retry_distance) {
                if (try @import("actors.zig").Actors.visible(v.add(pose.position, .{ 0, 0, 16 }), point, (try world.get(entity, data.Binding)).slot, (try target.get(data.Binding)).slot)) actor.panic(actor.threat, point, now);
            }
        } else {
            actor.worker.phase = .calm;
            actor.threat = 0;
        }
    }
    if (actor.worker.voice_pending) {
        actor.worker.voice_pending = false;
        const random = try world.get(entity, data.Random);
        actor.worker.variant = if (random.next() < 0.5) 0 else 1;
        const chance = random.next();
        const choice = random.next();
        if (policy.voice(thin, chance, choice)) |name| {
            try @import("actor_audio.zig").play(world, slots, projections, entity, definition, name, now);
            if (@import("../engine/server.zig").integer("developer") != 0) {
                var message: [160]u8 = undefined;
                @import("../engine/server.zig").print(try @import("std").fmt.bufPrintZ(&message, "dk3 worker: fear voice id={d} sound={s}\n", .{ try world.persistentId(entity), name }));
            }
        }
    }
}
