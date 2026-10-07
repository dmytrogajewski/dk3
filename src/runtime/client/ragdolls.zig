// SPDX-License-Identifier: GPL-2.0-or-later
//! Cosmetic ragdolls: live bone matrices, fixed-step world collision and bounded
//! corpse retention. Authoritative health, hits and movement remain on the server.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
const m = @import("../domain/bone_matrix.zig");
const physics = @import("../domain/ragdoll.zig");
const creature_physics = @import("../domain/creature_body.zig");
const Rig = struct {
    handle: c.qhandle_t = 0,
    count: usize = 0,
    names: [64][64:0]u8 = @splat(@splat(0)),
    parent: [64]i32 = @splat(-1),
    bind: [64]m.Mat = @splat(m.identity),
    inverse: [64]m.Mat = @splat(m.identity),
    particle: [64]?usize = @splat(null),
    bones: [physics.count]usize = @splat(0),
    creature_count: usize = 0,
    anchored: bool = false,
    padding: f32 = 10,
};
const History = struct { identity: i32 = 0, model: c.qhandle_t = 0, now: i32 = 0, born: i32 = -1, dead: bool = false, velocity: v.Vec3 = @splat(0), entity: c.refEntity_t = std.mem.zeroes(c.refEntity_t) };
const Corpse = struct {
    used: bool = false,
    rig: usize = 0,
    slot: u16 = 0,
    identity: i32 = 0,
    born: i32 = 0,
    now: i32 = 0,
    seen: i32 = 0,
    impulse: v.Vec3 = @splat(0),
    impulse_serial: i32 = 0,
    hits: u32 = 0,
    body: physics.Body = undefined,
    creature: creature_physics.Body = undefined,
    initial: [64]m.Mat = undefined,
    core: m.Mat = m.identity,
    entity: c.refEntity_t = std.mem.zeroes(c.refEntity_t),
};
var rigs: [64]Rig = @splat(.{});
var rig_count: usize = 0;
var history: [c.MAX_GENTITIES]History = @splat(.{});
var corpses: [32]Corpse = @splat(.{});
pub fn reset() void {
    rigs = @splat(.{});
    rig_count = 0;
    history = @splat(.{});
    corpses = @splat(.{});
}
fn word(bytes: []const u8, offset: usize) !u32 {
    if (offset + 4 > bytes.len) return error.InvalidRagdollRig;
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}
fn real(bytes: []const u8, offset: usize) !f32 {
    const value: f32 = @bitCast(try word(bytes, offset));
    if (!std.math.isFinite(value)) return error.InvalidRagdollRig;
    return value;
}
/// Creature physics modes listed in dk3/neural-physics.cfg, read once: model
/// registration consults it for every skeletal model of every map admitted.
const PhysicsMode = enum { humanoid, articulated, anchored };
const Listed = struct { name: [64]u8 = @splat(0), mode: PhysicsMode = .humanoid };
var listed: [256]Listed = @splat(.{});
var listed_count: usize = 0;
var listed_loaded = false;
fn listedMode(path: []const u8) !?PhysicsMode {
    if (!listed_loaded) {
        listed_count = 0;
        if (try @import("../engine/files.zig").readOptional(.client, &engine.gateway, std.heap.c_allocator, "dk3/neural-physics.cfg", 32768)) |config| {
            defer std.heap.c_allocator.free(config);
            try parseListed(config);
        }
        listed_loaded = true;
    }
    for (listed[0..listed_count]) |entry| if (std.mem.eql(u8, std.mem.sliceTo(&entry.name, 0), path)) return entry.mode;
    return null;
}
fn parseListed(config: []const u8) !void {
    var lines = std.mem.tokenizeScalar(u8, config, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \r\t");
        const name = fields.next() orelse return error.InvalidCreaturePhysics;
        const mode = fields.next() orelse return error.InvalidCreaturePhysics;
        if (fields.next() != null or !std.mem.startsWith(u8, name, "models/neural/") or !std.mem.endsWith(u8, name, ".iqm")) return error.InvalidCreaturePhysics;
        const physics_mode = std.meta.stringToEnum(PhysicsMode, mode) orelse return error.InvalidCreaturePhysics;
        if (name.len >= 64) return error.InvalidCreaturePhysics;
        if (listed_count == listed.len) return error.CreaturePhysicsCapacity;
        listed[listed_count] = .{ .mode = physics_mode };
        @memcpy(listed[listed_count].name[0..name.len], name);
        listed_count += 1;
    }
}
/// Rigs parsed from their files, by path. They depend on file contents only,
/// so a re-registration after an in-place load or a renderer restart reuses
/// them instead of reading the model again.
const Parsed = struct { path: [64]u8 = @splat(0), rig: Rig = .{} };
var parsed: [64]Parsed = @splat(.{});
var parsed_count: usize = 0;
pub fn register(handle: c.qhandle_t, path: [:0]const u8) !void {
    for (rigs[0..rig_count]) |rig| if (rig.handle == handle) return;
    for (parsed[0..parsed_count]) |entry| if (std.mem.eql(u8, std.mem.sliceTo(&entry.path, 0), path)) {
        if (rig_count == rigs.len) return error.RagdollRigCapacity;
        rigs[rig_count] = entry.rig;
        rigs[rig_count].handle = handle;
        rig_count += 1;
        return;
    };
    // Scripted cinematic/carrying skeletons keep their authored performance.
    const base = std.fs.path.basename(path);
    var allowed = false;
    var creature = false;
    var anchored = false;
    for ([_][]const u8{ "m_hiro.iqm", "m_mikiko.iqm", "m_superfly.iqm", "m_kage.iqm", "player_mishima.iqm", "player_usagi.iqm" }) |name| if (std.mem.eql(u8, base, name)) {
        allowed = true;
        break;
    };
    if (!allowed) if (try listedMode(path)) |mode| {
        allowed = true;
        creature = mode != .humanoid;
        anchored = mode == .anchored;
    };
    if (!allowed) return;
    if (rig_count == rigs.len) return error.RagdollRigCapacity;
    const bytes = try @import("../engine/files.zig").read(.client, &engine.gateway, std.heap.c_allocator, path, 16 << 20);
    defer std.heap.c_allocator.free(bytes);
    if (bytes.len < 124 or !std.mem.eql(u8, bytes[0..16], "INTERQUAKEMODEL\x00") or try word(bytes, 16) != 2) return error.InvalidRagdollRig;
    const count = try word(bytes, 68);
    const joints = try word(bytes, 72);
    const text = try word(bytes, 32);
    const text_len = try word(bytes, 28);
    if (count == 0 or count > 64 or @as(u64, joints) + count * 48 > bytes.len or @as(u64, text) + text_len > bytes.len) return error.InvalidRagdollRig;
    var rig: Rig = .{ .handle = handle, .count = count, .anchored = anchored };
    var found: usize = 0;
    for (0..count) |i| {
        const offset = joints + i * 48;
        const name_offset = try word(bytes, offset);
        if (name_offset >= text_len) return error.InvalidRagdollRig;
        const name = std.mem.sliceTo(bytes[text + name_offset .. text + text_len], 0);
        if (name.len == 0 or name.len >= 64) return error.InvalidRagdollRig;
        @memcpy(rig.names[i][0..name.len], name);
        const parent: i32 = @bitCast(try word(bytes, offset + 4));
        if (parent < -1 or parent >= @as(i32, @intCast(i))) return error.InvalidRagdollRig;
        rig.parent[i] = parent;
        var channels: [10]f32 = undefined;
        for (&channels, 0..) |*n, j| n.* = try real(bytes, offset + 8 + j * 4);
        const local = m.quaternion(channels[3..7].*, channels[7..10].*, channels[0..3].*);
        rig.bind[i] = if (parent >= 0) m.mul(rig.bind[@intCast(parent)], local) else local;
        rig.inverse[i] = m.inverse(rig.bind[i]);
        if (creature and std.mem.startsWith(u8, name, "creature_")) {
            if (i != rig.creature_count or (i == 0 and parent != -1) or (i > 0 and parent < 0)) return error.InvalidCreaturePhysics;
            rig.creature_count += 1;
        }
        for (physics.names, 0..) |particle, j| if (std.mem.eql(u8, std.mem.trimEnd(u8, name, "_"), particle)) {
            rig.particle[i] = j;
            rig.bones[j] = i;
            found += 1;
            break;
        };
    }
    if (creature) {
        if (rig.creature_count < 2) return error.InvalidCreaturePhysics;
        for (0..rig.creature_count) |i| rig.padding = @max(rig.padding, v.length(v.subtract(m.position(rig.bind[i]), m.position(rig.bind[0]))) * 0.4);
    } else if (found != physics.count) return error.InvalidRagdollRig;
    rigs[rig_count] = rig;
    rig_count += 1;
    if (parsed_count < parsed.len and path.len < 64) {
        parsed[parsed_count] = .{ .rig = rig };
        @memcpy(parsed[parsed_count].path[0..path.len], path);
        parsed_count += 1;
    }
}
fn index(handle: c.qhandle_t) ?usize {
    for (rigs[0..rig_count], 0..) |rig, i| if (rig.handle == handle) return i;
    return null;
}
fn root(entity: *const c.refEntity_t) m.Mat {
    return m.basis(entity.axis[0], entity.axis[1], entity.axis[2], entity.origin);
}
fn core(points: [physics.count]v.Vec3) m.Mat {
    const f = physics.frame(points);
    return m.basis(f.forward, f.left, f.up, points[0]);
}
fn start(rig_index: usize, state: c.entityState_t, now: i32, source: *const c.refEntity_t, velocity: v.Vec3) !*Corpse {
    var selected = &corpses[0];
    for (&corpses) |*corpse| {
        if (!corpse.used) {
            selected = corpse;
            break;
        }
        if (corpse.born < selected.born) selected = corpse;
    }
    selected.* = .{ .used = true, .rig = rig_index, .slot = @intCast(state.number), .identity = state.dk3Identity, .born = state.dk3AnimationStart, .now = now, .seen = now, .entity = source.*, .impulse = state.dk3BodyImpulse, .impulse_serial = state.dk3BodyImpulseSerial };
    const rig = &rigs[rig_index];
    const transform = root(source);
    for (0..rig.count) |i| {
        var tag: c.orientation_t = undefined;
        if (engine.gateway.call(c.CG_R_LERPTAG, .{ &tag, @as(isize, source.hModel), @as(isize, source.oldframe), @as(isize, source.frame), engine.floatArg(1 - source.backlerp), &rig.names[i] }) == 0) return error.RagdollJointUnavailable;
        selected.initial[i] = m.mul(transform, m.basis(tag.axis[0], tag.axis[1], tag.axis[2], tag.origin));
    }
    if (rig.creature_count > 0) {
        var points: [creature_physics.capacity]v.Vec3 = @splat(@splat(0));
        for (0..rig.creature_count) |i| points[i] = m.position(selected.initial[i]);
        selected.creature = try creature_physics.Body.init(rig.creature_count, points, rig.parent, velocity, rig.anchored);
        selected.entity.axis = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
        selected.entity.nonNormalizedAxes = c.qfalse;
        selected.entity.renderfx &= ~@as(i32, c.RF_THIRD_PERSON);
        return selected;
    }
    var points: [physics.count]v.Vec3 = undefined;
    for (rig.bones, 0..) |bone, i| points[i] = m.position(selected.initial[bone]);
    selected.core = core(points);
    // A bounded loss-of-balance impulse prevents perfectly symmetric standing
    // poses from balancing indefinitely. Actual travel velocity is inherited.
    const f = physics.frame(points);
    const side: f32 = if (state.dk3Identity & 1 == 0) 1 else -1;
    const impulse = v.add(v.scale(f.forward, -18), v.scale(f.left, side * 6));
    selected.body = physics.Body.init(points, velocity, impulse);
    selected.entity.axis = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
    selected.entity.nonNormalizedAxes = c.qfalse;
    selected.entity.renderfx &= ~@as(i32, c.RF_THIRD_PERSON);
    return selected;
}
pub fn apply(state: c.entityState_t, now: i32, entity: *c.refEntity_t) !bool {
    const rig = index(entity.hModel) orelse return false;
    if (state.number < 0 or state.number >= history.len or engine.number("cg_ragdolls", 1) == 0) return false;
    const old = &history[@intCast(state.number)];
    const dead = state.eFlags & c.EF_DEAD != 0;
    if (old.identity != state.dk3Identity or old.model != entity.hModel or now < old.now) old.* = .{ .identity = state.dk3Identity, .model = entity.hModel };
    if (!dead) {
        if (old.now > 0 and now > old.now and now - old.now < 250) {
            const delta = v.subtract(entity.origin, old.entity.origin);
            old.velocity = if (v.length(delta) < 100) v.scale(delta, 1000 / @as(f32, @floatFromInt(now - old.now))) else @splat(0);
        }
        old.entity = entity.*;
        old.now = now;
        old.dead = false;
        return false;
    }
    var active: ?*Corpse = null;
    for (&corpses) |*corpse| if (corpse.used and corpse.identity == state.dk3Identity and corpse.entity.dk3World == entity.dk3World and corpse.born == state.dk3AnimationStart) {
        active = corpse;
        corpse.slot = @intCast(state.number);
        break;
    };
    if (active == null and (!old.dead or old.born != state.dk3AnimationStart)) {
        var source = entity.*;
        if (old.now > 0 and now - old.now < 250) source = old.entity else {
            source.frame = entity.oldframe;
            source.backlerp = 0;
        }
        const velocity = if (v.length(state.pos.trDelta) > 0.001) state.pos.trDelta else old.velocity;
        active = try start(rig, state, now, &source, velocity);
    }
    old.dead = true;
    old.born = state.dk3AnimationStart;
    old.now = now;
    if (active) |corpse| {
        if (corpse.impulse_serial != state.dk3BodyImpulseSerial) {
            const kick = v.subtract(state.dk3BodyImpulse, corpse.impulse);
            if (rigs[corpse.rig].creature_count > 0) corpse.creature.applyImpulse(kick, state.dk3BodyImpulsePoint) else corpse.body.applyImpulse(kick, state.dk3BodyImpulsePoint);
            corpse.impulse = state.dk3BodyImpulse;
            corpse.impulse_serial = state.dk3BodyImpulseSerial;
            corpse.hits +%= 1;
        }
        corpse.seen = now;
        try update(corpse, now);
        entity.* = corpse.entity;
        return true;
    }
    // Expired persistent corpses retain the authored fallback pose.
    return false;
}
fn update(corpse: *Corpse, now: i32) !void {
    if (now < corpse.now) return;
    if (rigs[corpse.rig].creature_count > 0) return updateCreature(corpse, now);
    try corpse.body.advance(@as(f32, @floatFromInt(now - corpse.now)) / 1000, engine.collisionService(), corpse.slot, c.MASK_SOLID);
    corpse.now = now;
    const rig = &rigs[corpse.rig];
    const delta = m.mul(core(corpse.body.points), m.inverse(corpse.core));
    var posed: [64]m.Mat = undefined;
    const ends = [_]?usize{ 1, 2, null, 4, 5, null, 7, 8, null, 10, 11, 12, null, 14, 15, 16, null };
    for (0..rig.count) |i| {
        const parent = rig.parent[i];
        const inherited = if (parent >= 0) m.attached(posed[@intCast(parent)], corpse.initial[@intCast(parent)], corpse.initial[i]) else m.mul(delta, corpse.initial[i]);
        // The physics targets may have constraint residuals. Never transfer
        // those residuals into independent translations of connected bones.
        const anchor = m.position(inherited);
        if (rig.particle[i]) |p| {
            var rotated = m.mul(delta, corpse.initial[i]);
            if (ends[p]) |end| {
                if (p >= 3) {
                    const direction = m.direction(delta, v.subtract(m.position(corpse.initial[rig.bones[end]]), m.position(corpse.initial[i])));
                    const swing = m.swing(direction, v.subtract(corpse.body.points[end], anchor));
                    rotated = m.mul(swing, rotated);
                }
            } else if (parent >= 0) rotated = inherited;
            posed[i] = m.translated(rotated, anchor);
        } else posed[i] = inherited;
    }
    const origin = corpse.body.points[0];
    corpse.entity.origin = origin;
    corpse.entity.oldorigin = origin;
    corpse.entity.lightingOrigin = origin;
    corpse.entity.dk3BoneCount = @intCast(rig.count);
    corpse.entity.dk3BoneBounds = .{ @splat(100000), @splat(-100000) };
    for (0..rig.count) |i| {
        const local = m.translated(posed[i], v.subtract(m.position(posed[i]), origin));
        corpse.entity.dk3BoneMatrices[i] = m.mul(local, rig.inverse[i]);
        const position = m.position(local);
        for (0..3) |axis| {
            corpse.entity.dk3BoneBounds[0][axis] = @min(corpse.entity.dk3BoneBounds[0][axis], position[axis] - 10);
            corpse.entity.dk3BoneBounds[1][axis] = @max(corpse.entity.dk3BoneBounds[1][axis], position[axis] + 10);
        }
    }
}
fn updateCreature(corpse: *Corpse, now: i32) !void {
    const rig = &rigs[corpse.rig];
    try corpse.creature.advance(@as(f32, @floatFromInt(now - corpse.now)) / 1000, engine.collisionService(), corpse.slot, c.MASK_SOLID);
    corpse.now = now;
    var posed: [64]m.Mat = undefined;
    const origin = corpse.creature.points[0];
    const delta = v.subtract(origin, m.position(corpse.initial[0]));
    for (0..rig.count) |i| {
        const parent = rig.parent[i];
        var inherited = if (parent >= 0) m.attached(posed[@intCast(parent)], corpse.initial[@intCast(parent)], corpse.initial[i]) else m.translated(corpse.initial[i], origin);
        if (i < rig.creature_count) {
            // Rotate toward the longest child, keeping each anchor attached to
            // its parent. Particle constraint residues cannot stretch the skin.
            var child: ?usize = null;
            var distance: f32 = 0;
            for (i + 1..rig.creature_count) |j| if (rig.parent[j] == @as(i32, @intCast(i))) {
                const length = v.length(v.subtract(m.position(corpse.initial[j]), m.position(corpse.initial[i])));
                if (length > distance) {
                    child = j;
                    distance = length;
                }
            };
            if (child) |j| {
                const initial_direction = v.subtract(m.position(corpse.initial[j]), m.position(corpse.initial[i]));
                const inherited_delta = m.mul(inherited, m.inverse(corpse.initial[i]));
                const target = v.subtract(corpse.creature.points[j], m.position(inherited));
                const rotated = m.mul(m.swing(m.direction(inherited_delta, initial_direction), target), inherited);
                inherited = m.translated(rotated, m.position(inherited));
            } else if (parent < 0) inherited = m.translated(inherited, v.add(m.position(corpse.initial[i]), delta));
        }
        posed[i] = inherited;
    }
    corpse.entity.origin = origin;
    corpse.entity.oldorigin = origin;
    corpse.entity.lightingOrigin = origin;
    corpse.entity.dk3BoneCount = @intCast(rig.count);
    corpse.entity.dk3BoneBounds = .{ @splat(100000), @splat(-100000) };
    for (0..rig.count) |i| {
        const local = m.translated(posed[i], v.subtract(m.position(posed[i]), origin));
        corpse.entity.dk3BoneMatrices[i] = m.mul(local, rig.inverse[i]);
        for (0..3) |axis| {
            corpse.entity.dk3BoneBounds[0][axis] = @min(corpse.entity.dk3BoneBounds[0][axis], m.position(local)[axis] - rig.padding);
            corpse.entity.dk3BoneBounds[1][axis] = @max(corpse.entity.dk3BoneBounds[1][axis], m.position(local)[axis] + rig.padding);
        }
    }
}
pub fn drawDetached(worlds: *@import("resident_worlds.zig").State, now: i32) !void {
    if (engine.number("cg_ragdolls", 1) == 0) {
        corpses = @splat(.{});
        history = @splat(.{});
        return;
    }
    for (&corpses) |*corpse| {
        if (!corpse.used) continue;
        if (now < corpse.now or (corpse.seen != now and now - corpse.born > 15000)) {
            corpse.used = false;
            continue;
        }
        if (corpse.seen == now) continue;
        const scope = worlds.selectPresentation(corpse.entity.dk3World) catch |err| switch (err) {
            error.WorldNotAdmitted, error.InitialWorldUnavailable => {
                corpse.used = false;
                continue;
            },
        };
        defer scope.deinit();
        try update(corpse, now);
        _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&corpse.entity});
    }
}
pub fn reconcile(states: []const c.entityState_t) void {
    for (states) |state| if (state.dk3BodyFlags & 1 != 0) {
        for (&corpses) |*corpse| if (corpse.used and corpse.identity == state.dk3Identity and corpse.entity.dk3World == state.dk3World) {
            corpse.used = false;
        };
    };
}
pub fn diagnostics() void {
    var buffer: [256]u8 = undefined;
    for (corpses) |corpse| if (corpse.used) {
        const creature = rigs[corpse.rig].creature_count > 0;
        const position = if (creature) corpse.creature.points[0] else corpse.body.points[0];
        const contacts = if (creature) corpse.creature.contacts else corpse.body.contacts;
        const sleeping = if (creature) corpse.creature.sleeping else corpse.body.sleeping;
        engine.print(std.fmt.bufPrintZ(&buffer, "dk3 ragdoll: slot={d} identity={d} born={d} now={d} contacts={d} sleep={d} pelvis={d:.2},{d:.2},{d:.2} bones={d} hits={d} impulse={d}\n", .{ corpse.slot, corpse.identity, corpse.born, corpse.now, contacts, @intFromBool(sleeping), position[0], position[1], position[2], corpse.entity.dk3BoneCount, corpse.hits, corpse.impulse_serial }) catch unreachable);
    };
}
test "creature physics listings are validated and looked up by exact model path" {
    listed_count = 0;
    defer listed_count = 0;
    try parseListed("models/neural/m_rat.iqm anchored\nmodels/neural/m_crox.iqm articulated\r\n");
    try std.testing.expectEqual(@as(usize, 2), listed_count);
    try std.testing.expectEqual(PhysicsMode.anchored, listed[0].mode);
    try std.testing.expectEqualStrings("models/neural/m_crox.iqm", std.mem.sliceTo(&listed[1].name, 0));
    try std.testing.expectError(error.InvalidCreaturePhysics, parseListed("models/neural/m_rat.iqm floating\n"));
    try std.testing.expectError(error.InvalidCreaturePhysics, parseListed("textures/m_rat.iqm anchored\n"));
}
