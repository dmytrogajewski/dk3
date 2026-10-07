// SPDX-License-Identifier: GPL-2.0-or-later
//! Optional, installation-validated skeletal presentation. Authoritative model
//! paths and frame timelines stay intact for saves, collision and networking.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const Entry = struct {
    source: [64:0]u8 = @splat(0),
    target: [64:0]u8 = @splat(0),
    handle: c.qhandle_t = 0,
    legacy_handle: c.qhandle_t = 0,
    skins: [4]c.qhandle_t = @splat(0),
};
var entries: [160]Entry = @splat(.{});
var count: usize = 0;
var loaded = false;
var player_skins: [60]c.qhandle_t = @splat(0);
const motion = @import("../domain/skeletal_animation.zig");
const Animation = struct {
    source: [64:0]u8 = @splat(0),
    first: u16 = 0,
    last: u16 = 0,
    clip: motion.Clip = .{ .first = 0, .last = 0, .rate = 0 },
    attack_first: u16 = 0,
    attack_count: u16 = 0,
};
var animations: [2048]Animation = @splat(.{});
var animation_count: usize = 0;
var animations_loaded = false;
const Blend = struct { model: c.qhandle_t = 0, sequence: usize = 0, frame: i32 = 0, oldframe: i32 = 0, backlerp: f32 = 0, from: i32 = 0, started: i64 = 0, seen: i64 = 0, animation_started: i32 = 0, fired: i32 = 0 };
var blends: [c.MAX_GENTITIES]Blend = @splat(.{});

fn legacyFrame(entry: *Entry, state: c.entityState_t, rendered: *c.refEntity_t) !void {
    // A partial authored clip table must keep every unconverted cinematic
    // sequence playable from its original converted DKM/MD3 presentation.
    const source = std.mem.sliceTo(&entry.source, 0);
    if (!std.mem.startsWith(u8, source, "models/cinematic/") or
        !std.mem.endsWith(u8, source, ".dkm") or rendered.hModel != entry.handle) return;
    if (entry.legacy_handle == 0) {
        var path: [c.MAX_QPATH + 5]u8 = undefined;
        const converted = try std.fmt.bufPrintZ(&path, "{s}.md3", .{source});
        entry.legacy_handle = @intCast(engine.gateway.call(c.CG_R_REGISTERMODEL, .{converted.ptr}));
        if (entry.legacy_handle == 0) return error.LegacyModelUnavailable;
    }
    rendered.hModel = entry.legacy_handle;
    rendered.customSkin = 0;
    if (state.number >= 0 and state.number < blends.len) blends[@intCast(state.number)] = .{};
}

pub fn reset() void {
    @import("ragdolls.zig").reset();
    entries = @splat(.{});
    count = 0;
    loaded = false;
    player_skins = @splat(0);
    animation_count = 0;
    animations_loaded = false;
    blends = @splat(.{});
}

pub fn animate(name: []const u8, state: c.entityState_t, now: i64, rendered: *c.refEntity_t) !void {
    const mapped = try find(name) orelse return;
    if (state.dk3AnimationRate <= 0) {
        try legacyFrame(mapped, state, rendered);
        return;
    }
    var animation_model = name;
    if (state.eType == c.ET_PLAYER) for (entries[0..count]) |entry| {
        const source = std.mem.sliceTo(&entry.source, 0);
        if (entry.handle == rendered.hModel and std.mem.startsWith(u8, source, "player/")) {
            animation_model = source;
            break;
        }
    };
    if (!animations_loaded) {
        animations_loaded = true;
        if (try @import("../engine/files.zig").readOptional(.client, &engine.gateway, std.heap.c_allocator, "dk3/neural-animations.cfg", 256 * 1024)) |bytes| {
            defer std.heap.c_allocator.free(bytes);
            var lines = std.mem.tokenizeScalar(u8, bytes, '\n');
            while (lines.next()) |line| {
                var words = std.mem.tokenizeAny(u8, line, " \t\r");
                const source = words.next() orelse return error.InvalidNeuralAnimation;
                if (source.len >= 64 or animation_count == animations.len) return error.InvalidNeuralAnimation;
                var numbers: [5]u16 = undefined;
                for (&numbers) |*number| number.* = try std.fmt.parseInt(u16, words.next() orelse return error.InvalidNeuralAnimation, 10);
                const attack_first = if (words.next()) |word| try std.fmt.parseInt(u16, word, 10) else 0;
                const attack_count = if (attack_first != 0) try std.fmt.parseInt(u16, words.next() orelse return error.InvalidNeuralAnimation, 10) else blk: {
                    if (words.next()) |word| if (!std.mem.eql(u8, word, "0")) return error.InvalidNeuralAnimation;
                    break :blk 0;
                };
                if (words.next() != null or numbers[1] < numbers[0] or numbers[3] < numbers[2] or numbers[4] > 240) return error.InvalidNeuralAnimation;
                const entry = &animations[animation_count];
                entry.* = .{ .first = numbers[0], .last = numbers[1], .clip = .{ .first = numbers[2], .last = numbers[3], .rate = numbers[4] } };
                if (@as(u32, attack_first) + @as(u32, attack_count) * (@as(u32, numbers[3]) - numbers[2] + 1) > 65536) return error.InvalidNeuralAnimation;
                entry.attack_first = attack_first;
                entry.attack_count = attack_count;
                @memcpy(entry.source[0..source.len], source);
                animation_count += 1;
            }
        }
    }
    const first = @min(state.dk3AnimationFirst, state.dk3AnimationLast);
    const last = @max(state.dk3AnimationFirst, state.dk3AnimationLast);
    for (animations[0..animation_count], 0..) |entry, index| {
        if (first != entry.first or last != entry.last or !std.mem.eql(u8, std.mem.sliceTo(&entry.source, 0), animation_model)) continue;
        const value = motion.sample(entry.clip, @as(u32, entry.last) - entry.first + 1, @intCast(state.dk3AnimationRate), now - state.dk3AnimationStart, state.dk3AnimationLoop != 0, state.dk3AnimationFirst > state.dk3AnimationLast);
        rendered.frame = value.frame;
        rendered.oldframe = value.oldframe;
        rendered.backlerp = value.backlerp;
        if (state.eType == c.ET_PLAYER and state.weapon != 0 and state.time2 > 0 and entry.attack_count > 0) {
            const elapsed = now - state.time2;
            if (elapsed >= 0 and elapsed < @divTrunc(@as(i64, entry.attack_count) * 1000, 30)) {
                const offset = @as(i32, entry.attack_first) + @as(i32, @intCast(@divTrunc(elapsed * 30, 1000))) * (@as(i32, entry.clip.last) - entry.clip.first + 1) - entry.clip.first;
                rendered.frame += offset;
                rendered.oldframe += offset;
            }
        }
        if (state.number >= 0 and state.number < blends.len) {
            const blend = &blends[@intCast(state.number)];
            if (blend.model != rendered.hModel or now < blend.seen or now - blend.seen > 250) {
                blend.* = .{ .model = rendered.hModel, .sequence = index, .frame = rendered.frame, .from = rendered.frame, .started = now - 100, .seen = now };
            } else if (blend.sequence != index) {
                blend.from = blend.frame;
                blend.started = now;
                blend.sequence = index;
            }
            if (now - blend.started < 100) {
                rendered.oldframe = blend.from;
                rendered.backlerp = 1 - @as(f32, @floatFromInt(now - blend.started)) * 0.01;
            }
            blend.frame = rendered.frame;
            blend.oldframe = rendered.oldframe;
            blend.backlerp = rendered.backlerp;
            blend.animation_started = state.dk3AnimationStart;
            blend.fired = if (state.eType == c.ET_PLAYER) state.time2 else 0;
            blend.seen = now;
        }
        return;
    }
    try legacyFrame(mapped, state, rendered);
}

pub fn diagnostics(now: i64) void {
    var message: [384]u8 = undefined;
    for (blends, 0..) |blend, entity| {
        if (blend.model == 0 or now < blend.seen or now - blend.seen > 100) continue;
        const entry = animations[blend.sequence];
        engine.print(std.fmt.bufPrintZ(&message, "dk3 skeletal presentation: entity={d} now={d} frame={d} oldframe={d} backlerp={d:.4} source_first={d} source_last={d} clip_first={d} clip_last={d} rate={d} started={d} model={s} attack_first={d} attack_count={d} fired={d}\n", .{ entity, blend.seen, blend.frame, blend.oldframe, blend.backlerp, entry.first, entry.last, entry.clip.first, entry.clip.last, entry.clip.rate, blend.animation_started, std.mem.sliceTo(&entry.source, 0), entry.attack_first, entry.attack_count, blend.fired }) catch unreachable);
    }
}

pub fn isSkeletal(handle: c.qhandle_t) bool {
    for (entries[0..count]) |entry| if (entry.handle != 0 and entry.handle == handle) return true;
    return false;
}
fn find(name: []const u8) !?*Entry {
    // Reconstructed cinematic performances have not passed native visual
    // review. Keep the original vertex-model acting even when a general
    // skeletal gameplay package is installed. Explicit preview runs opt in
    // before model registration with +set cg_neuralCinematics 1.
    if (std.mem.startsWith(u8, name, "models/cinematic/") and engine.integer("cg_neuralCinematics") != 1) return null;
    if (!loaded) {
        loaded = true;
        if (try @import("../engine/files.zig").readOptional(.client, &engine.gateway, std.heap.c_allocator, "dk3/neural-models.cfg", 32768)) |bytes| {
            defer std.heap.c_allocator.free(bytes);
            var lines = std.mem.tokenizeScalar(u8, bytes, '\n');
            while (lines.next()) |line| {
                var fields = std.mem.tokenizeAny(u8, line, " \r\t");
                const source = fields.next() orelse return error.InvalidNeuralModelManifest;
                const target = fields.next() orelse return error.InvalidNeuralModelManifest;
                if (fields.next() != null or count == entries.len or source.len >= 64 or target.len >= 64 or
                    !std.mem.startsWith(u8, target, "models/neural/") or !std.mem.endsWith(u8, target, ".iqm") or
                    std.mem.indexOf(u8, target, "..") != null) return error.InvalidNeuralModelManifest;
                @memcpy(entries[count].source[0..source.len], source);
                @memcpy(entries[count].target[0..target.len], target);
                count += 1;
            }
            engine.print("dk3 neural: skeletal character package enabled\n");
        }
    }
    for (entries[0..count]) |*entry| if (std.mem.eql(u8, std.mem.sliceTo(&entry.source, 0), name)) return entry;
    return null;
}
pub fn model(name: []const u8) !?c.qhandle_t {
    const entry = try find(name) orelse return null;
    if (entry.handle == 0) {
        entry.handle = @intCast(engine.gateway.call(c.CG_R_REGISTERMODEL, .{&entry.target}));
        if (entry.handle == 0) return error.NeuralModelUnavailable;
        try @import("ragdolls.zig").register(entry.handle, std.mem.sliceTo(&entry.target, 0));
        var message: [180]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 neural: {s} -> {s}\n", .{ std.mem.sliceTo(&entry.source, 0), std.mem.sliceTo(&entry.target, 0) }));
    }
    return entry.handle;
}
pub fn material(name: []const u8, variant: usize) !?c.qhandle_t {
    const entry = try find(name) orelse return null;
    if (variant >= entry.skins.len) return error.InvalidNeuralSkin;
    if (entry.skins[variant] == 0) {
        var path: [80]u8 = undefined;
        const skin = try std.fmt.bufPrintZ(&path, "{s}.{d}.skin", .{ std.mem.sliceTo(&entry.target, 0), variant });
        entry.skins[variant] = @intCast(engine.gateway.call(c.CG_R_REGISTERSKIN, .{skin.ptr}));
        if (entry.skins[variant] == 0) return error.NeuralSkinUnavailable;
    }
    return entry.skins[variant];
}
pub fn player(game: *const c.gameState_t, slot: i32, rendered: *c.refEntity_t) !void {
    if (slot < 0 or slot >= c.MAX_CLIENTS) return;
    const info = try engine.config(game, c.CS_PLAYERS + @as(usize, @intCast(slot)));
    const catalog = @import("appearance_catalog");
    const selection = engine.info(info, "appearance") orelse blk: {
        const skin = engine.info(info, "skin") orelse return;
        for (catalog.entries[0..36]) |entry| if (std.mem.eql(u8, entry.skin, skin)) break :blk entry.selection;
        return;
    };
    const index = catalog.parse(selection) orelse return error.UnknownPlayerAppearance;
    try playerAppearance(index, rendered);
}
pub fn playerAppearance(index: usize, rendered: *c.refEntity_t) !void {
    const catalog = @import("appearance_catalog");
    if (index >= catalog.entries.len) return error.UnknownPlayerAppearance;
    const entry = catalog.entries[index];
    const selection = entry.selection;
    const slash = std.mem.indexOfScalar(u8, selection, '/') orelse return error.UnknownPlayerAppearance;
    var path: [80]u8 = undefined;
    const key = if (index < 36) entry.model else try std.fmt.bufPrint(&path, "player/{s}", .{selection[0..slash]});
    rendered.hModel = try model(key) orelse return;
    if (player_skins[index] == 0) {
        const name = try std.fmt.bufPrintZ(&path, "models/neural/{s}.skin", .{selection});
        player_skins[index] = @intCast(engine.gateway.call(c.CG_R_REGISTERSKIN, .{name.ptr}));
        if (player_skins[index] == 0) return error.NeuralPlayerSkinUnavailable;
    }
    rendered.customSkin = player_skins[index];
}
