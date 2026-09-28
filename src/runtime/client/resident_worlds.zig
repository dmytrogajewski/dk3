// SPDX-License-Identifier: GPL-2.0-or-later
//! Client owner for resident map presentation. Selection is explicit and scoped;
//! preparation never changes prediction's collision world or snapshot identity.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const Admission = @import("world_admission.zig").State;
const wire = @import("../domain/world_admission.zig");
pub const Entry = struct { name: [64]u8 = @splat(0), handle: u32, ready: bool = false, failed: bool = false, total_ms: isize = 0, max_step_ms: isize = 0, polls: usize = 0, admission: ?*Admission = null };
pub const State = struct {
    entries: [128]?Entry = @splat(null),
    cursor: usize = 0,
    preview: ?struct { handle: u32, origin: [3]f32, angles: [3]f32 } = null,
    initial: ?*Initial = null,
    active_id: u32 = 0,
    waiting: bool = false,
    patches: [128]?struct { owner: u32, receiver: wire.Receiver } = @splat(null),
    portals: [256]?@import("../domain/world_aperture.zig").Aperture = @splat(null),
    const Initial = struct {
        render: u32,
        collision: u32,
        game: c.gameState_t,
        inline_models: [c.MAX_MODELS]c.qhandle_t,
        sky: @import("sky.zig").State,
    };
    const View = struct { render: u32, collision: u32, game: *c.gameState_t, inline_models: *[c.MAX_MODELS]c.qhandle_t, sky: *@import("sky.zig").State };
    pub fn captureInitial(self: *State, game: *const c.gameState_t, inline_models: *const [c.MAX_MODELS]c.qhandle_t) !void {
        const initial = try std.heap.c_allocator.create(Initial);
        initial.* = .{ .render = @intCast(engine.gateway.call(c.CG_DK3_WORLD_CURRENT_V1, .{})), .collision = @intCast(engine.gateway.call(c.CG_DK3_COLLISION_CURRENT_V1, .{})), .game = game.*, .inline_models = inline_models.*, .sky = @import("sky.zig").current() };
        self.initial = initial;
    }
    pub fn view(self: *State, id: u32) !View {
        if (id == 0) {
            const initial = self.initial orelse return error.InitialWorldUnavailable;
            return .{ .render = initial.render, .collision = initial.collision, .game = &initial.game, .inline_models = &initial.inline_models, .sky = &initial.sky };
        }
        for (&self.entries) |*maybe| if (maybe.*) |*entry| if (entry.admission) |admission| {
            if (admission.server_id != id) continue;
            if (!entry.ready or !admission.ready or admission.failed) return error.WorldNotAdmitted;
            return .{ .render = entry.handle, .collision = admission.collision, .game = &admission.game, .inline_models = &admission.inline_models, .sky = &admission.sky };
        };
        return error.WorldNotAdmitted;
    }
    pub fn selectPresentation(self: *State, id: u32) !engine.Presentation {
        const owner = try self.view(id);
        return (engine.Presentation{ .render = owner.render, .collision = owner.collision, .network = id }).select();
    }
    pub fn collision(self: *State) !u32 {
        return (try self.view(self.active_id)).collision;
    }
    pub fn enter(self: *State, inline_models: *[c.MAX_MODELS]c.qhandle_t) !bool {
        var buffer: [64]u8 = undefined;
        if (!std.mem.eql(u8, arg(0, &buffer), "dk3_world_enter")) return false;
        const id = try std.fmt.parseInt(u32, arg(1, &buffer), 10);
        const destination = try self.view(id);
        const source = try self.view(self.active_id);
        _ = engine.gateway.call(c.CG_GETGAMESTATE, .{source.game});
        source.sky.* = @import("sky.zig").current();
        if (engine.gateway.call(c.CG_DK3_GAMESTATE_SELECT_V1, .{destination.game}) == 0) return error.WorldConfigActivation;
        if (engine.gateway.call(c.CG_DK3_WORLD_SELECT_V1, .{@as(isize, destination.render)}) == 0) return error.WorldRenderActivation;
        if (engine.gateway.call(c.CG_DK3_COLLISION_SELECT_V1, .{@as(isize, destination.collision)}) == 0) return error.WorldCollisionActivation;
        inline_models.* = destination.inline_models.*;
        _ = @import("sky.zig").exchange(destination.sky.*);
        self.active_id = id;
        self.preview = null;
        @import("events.zig").reset();
        var message: [96]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 world presentation: entered={d} render={d} collision={d}\n", .{ id, destination.render, destination.collision }));
        return true;
    }
    pub fn deinit(self: *State) void {
        _ = engine.gateway.call(c.CG_CVAR_SET, .{ @as([*:0]const u8, "dk3_region_loading"), @as([*:0]const u8, "0") });
        for (self.entries) |maybe| if (maybe) |entry| if (entry.admission) |admission| admission.destroy();
        for (&self.patches) |*maybe| if (maybe.*) |*patch| patch.receiver.deinit(std.heap.c_allocator);
        if (self.initial) |initial| std.heap.c_allocator.destroy(initial);
        self.* = .{};
    }
    pub fn serverCommand(self: *State) !void {
        var buffer: [96]u8 = undefined;
        const command_name = arg(0, &buffer);
        if (std.mem.eql(u8, command_name, "dk3_world_patch")) {
            const id = try std.fmt.parseInt(u32, arg(1, &buffer), 10);
            const serial = try std.fmt.parseInt(u64, arg(2, &buffer), 10);
            const length = try std.fmt.parseInt(usize, arg(3, &buffer), 10);
            const digest = try std.fmt.parseInt(u64, arg(4, &buffer), 10);
            const offset = try std.fmt.parseInt(usize, arg(5, &buffer), 10);
            const owner = try self.view(id);
            var selected: ?usize = null;
            for (self.patches, 0..) |maybe, index| if (maybe) |patch| if (patch.owner == id) {
                selected = index;
                break;
            };
            if (selected == null) {
                if (offset != 0) return error.InvalidWorldChunk;
                for (&self.patches, 0..) |*maybe, index| if (maybe.* == null) {
                    maybe.* = .{ .owner = id, .receiver = try wire.Receiver.init(std.heap.c_allocator, length, digest) };
                    selected = index;
                    break;
                };
            }
            const index = selected orelse return error.WorldPatchCapacity;
            const receiver = &self.patches[index].?.receiver;
            if (receiver.digest != digest or receiver.bytes.len != length) return error.WorldConfigDigest;
            var hex: [wire.chunk_size * 2 + 1]u8 = undefined;
            var decoded: [wire.chunk_size]u8 = undefined;
            const encoded = arg(6, &hex);
            if (encoded.len % 2 != 0) return error.InvalidWorldChunk;
            try receiver.accept(offset, try std.fmt.hexToBytes(&decoded, encoded));
            if (receiver.received != receiver.bytes.len) {
                try patchAck(id, serial);
                return;
            }
            const bytes = try receiver.validatedBytes();
            if (bytes.len < 2) return error.InvalidWorldConfig;
            const field = std.mem.readInt(u16, bytes[0..2], .little);
            const value = bytes[2..];
            const scope = try self.selectPresentation(id);
            defer scope.deinit();
            if (value.len != 0) {
                if (field > c.CS_MODELS and field < c.CS_MODELS + c.MAX_MODELS) {
                    if (std.mem.endsWith(u8, value, ".sp2")) {
                        _ = try @import("sprites.zig").register(value);
                    } else if (try @import("models.zig").register(value) == 0) return error.MissingWorldModel;
                } else if (field > c.CS_SOUNDS and field < c.CS_SOUNDS + c.MAX_SOUNDS) {
                    if (try engine.registerSound(value) == 0) return error.MissingWorldSound;
                }
            }
            // Normal primary-world configstrings may have advanced other
            // indices since the last frame. Preserve those actual definitions.
            if (id == self.active_id) _ = engine.gateway.call(c.CG_GETGAMESTATE, .{owner.game});
            try @import("config_patch.zig").apply(owner.game, field, value);
            if (id == self.active_id and engine.gateway.call(c.CG_DK3_GAMESTATE_SELECT_V1, .{owner.game}) == 0) return error.WorldConfigActivation;
            receiver.deinit(std.heap.c_allocator);
            self.patches[index] = null;
            var message: [160]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&message, "dk3 world config: owner={d} index={d} applied\n", .{ id, field }));
            try patchAck(id, serial);
            return;
        }
        if (std.mem.eql(u8, command_name, "dk3_world_portal")) {
            const index = try std.fmt.parseInt(u8, arg(1, &buffer), 10);
            const source = try std.fmt.parseInt(u32, arg(2, &buffer), 10);
            const destination = try std.fmt.parseInt(u32, arg(3, &buffer), 10);
            const axis = try std.fmt.parseInt(u2, arg(4, &buffer), 10);
            const direction = try std.fmt.parseInt(i2, arg(5, &buffer), 10);
            const mins = try vector(arg(6, &buffer));
            const maxs = try vector(arg(7, &buffer));
            const aperture: @import("../domain/world_aperture.zig").Aperture = .{ .source = source, .destination = destination, .axis = axis, .direction = direction, .mins = mins, .maxs = maxs };
            try aperture.validate();
            _ = try self.view(source);
            _ = try self.view(destination);
            self.portals[index] = aperture;
            engine.print("dk3 world aperture: admitted\n");
            return;
        }
        if (std.mem.eql(u8, command_name, "dk3_region_wait")) {
            const value = arg(1, &buffer);
            if (!std.mem.eql(u8, value, "0") and !std.mem.eql(u8, value, "1")) return error.InvalidRegionWait;
            self.waiting = value[0] == '1';
            _ = engine.gateway.call(c.CG_CVAR_SET, .{ @as([*:0]const u8, "dk3_region_loading"), @as([*:0]const u8, if (self.waiting) "1" else "0") });
            _ = engine.gateway.call(c.CG_CVAR_SET, .{ @as([*:0]const u8, "dk3_loading_progress"), @as([*:0]const u8, if (self.waiting) "0" else "1") });
            return;
        }
        if (std.mem.eql(u8, command_name, "dk3_world_begin")) {
            if (try std.fmt.parseInt(u32, arg(1, &buffer), 10) != wire.version) return error.WorldAdmissionVersion;
            const server_id = try std.fmt.parseInt(u32, arg(2, &buffer), 10);
            var name_buffer: [64]u8 = undefined;
            const name = arg(3, &name_buffer);
            const checksum = try std.fmt.parseInt(u32, arg(4, &buffer), 10);
            const length = try std.fmt.parseInt(usize, arg(5, &buffer), 10);
            const digest = try std.fmt.parseInt(u64, arg(6, &buffer), 10);
            const handle = self.request(name) catch |err| {
                Admission.failure(server_id, err);
                return;
            };
            for (&self.entries) |*maybe| if (maybe.*) |*entry| {
                if (entry.handle != handle) continue;
                if (entry.admission) |previous| {
                    if (previous.server_id == server_id) {
                        try previous.acknowledge();
                        return;
                    }
                    previous.destroy();
                    entry.admission = null;
                }
                entry.admission = Admission.create(server_id, name, checksum, length, digest) catch |err| {
                    Admission.failure(server_id, err);
                    return;
                };
                try entry.admission.?.acknowledge();
                return;
            };
            return error.WorldAdmissionOwner;
        }
        const cancel = std.mem.eql(u8, command_name, "dk3_world_cancel");
        if (!cancel and !std.mem.eql(u8, command_name, "dk3_world_data")) return;
        const server_id = try std.fmt.parseInt(u32, arg(1, &buffer), 10);
        for (&self.entries) |*maybe| if (maybe.*) |*entry| if (entry.admission) |admission| {
            if (admission.server_id != server_id) continue;
            if (cancel) {
                admission.destroy();
                entry.admission = null;
                return;
            }
            const offset = try std.fmt.parseInt(usize, arg(2, &buffer), 10);
            var encoded: [wire.chunk_size * 2 + 1]u8 = undefined;
            admission.accept(offset, arg(3, &encoded)) catch |err| admission.fail(err);
            return;
        };
    }
    pub fn request(self: *State, name: []const u8) !u32 {
        if (!@import("../domain/snapshot.zig").validName(name) or name.len >= 64) return error.InvalidWorldName;
        for (self.entries) |maybe| if (maybe) |entry| {
            if (std.mem.eql(u8, name, std.mem.sliceTo(&entry.name, 0))) return entry.handle;
        };
        for (&self.entries) |*slot| if (slot.* == null) {
            var buffer: [80]u8 = undefined;
            const handle = engine.gateway.call(c.CG_DK3_WORLD_REQUEST_V1, .{(try std.fmt.bufPrintZ(&buffer, "maps/{s}.bsp", .{name})).ptr});
            if (handle <= 0) return error.RenderWorldUnavailable;
            var entry: Entry = .{ .handle = @intCast(handle) };
            @memcpy(entry.name[0..name.len], name);
            slot.* = entry;
            return entry.handle;
        };
        return error.RenderWorldCapacity;
    }
    pub fn apertures(self: *State, ref: *const c.refdef_t) !void {
        for (self.portals) |maybe| if (maybe) |portal| {
            if (portal.source != self.active_id) continue;
            const center = portal.center();
            if ((ref.vieworg[portal.axis] - center[portal.axis]) * @as(f32, @floatFromInt(portal.direction)) >= 0) continue;
            const destination = try self.view(portal.destination);
            var entity = std.mem.zeroes(c.refEntity_t);
            entity.reType = c.RT_PORTALSURFACE;
            entity.origin = center;
            entity.oldorigin = center;
            entity.oldorigin[portal.axis] += @as(f32, @floatFromInt(portal.direction));
            entity.dk3PortalWorld = destination.render;
            _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&entity});
            var polygon: [4]c.polyVert_t = undefined;
            for (&polygon, portal.vertices()) |*vertex, position| vertex.* = .{ .xyz = position, .st = .{ 0, 0 }, .modulate = .{ 255, 255, 255, 255 } };
            const shader = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/world-aperture")});
            if (shader == 0) return error.MissingWorldApertureShader;
            _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ shader, @as(isize, polygon.len), &polygon });
        };
    }
    pub fn step(self: *State) !void {
        for (0..self.entries.len) |_| {
            const index = self.cursor;
            self.cursor = (index + 1) % self.entries.len;
            const entry = if (self.entries[index]) |*value| value else continue;
            if (entry.failed) continue;
            if (entry.ready) {
                if (entry.admission) |admission| {
                    if (admission.ready or admission.failed) continue;
                    admission.step(entry.handle, std.mem.sliceTo(&entry.name, 0)) catch |err| admission.fail(err);
                    return;
                }
                continue;
            }
            const before = engine.gateway.call(c.CG_MILLISECONDS, .{});
            const status = engine.gateway.call(c.CG_DK3_WORLD_POLL_V1, .{@as(isize, entry.handle)});
            const elapsed = engine.gateway.call(c.CG_MILLISECONDS, .{}) - before;
            entry.total_ms += elapsed;
            entry.max_step_ms = @max(entry.max_step_ms, elapsed);
            entry.polls += 1;
            if (status == 0) return;
            entry.ready = status == 1;
            entry.failed = status < 0;
            if (entry.failed) if (entry.admission) |admission| admission.fail(error.RenderWorldUnavailable);
            var buffer: [192]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 render world: map={s} handle={d} ready={d} admission_ms={d} max_step_ms={d} polls={d}\n", .{ std.mem.sliceTo(&entry.name, 0), entry.handle, @intFromBool(entry.ready), entry.total_ms, entry.max_step_ms, entry.polls }));
            return;
        }
    }
    pub fn command(self: *State) !void {
        var verb_buffer: [32]u8 = undefined;
        const verb = arg(1, &verb_buffer);
        if (std.mem.eql(u8, verb, "close")) {
            self.preview = null;
            engine.print("dk3 render world: preview closed\n");
            return;
        }
        var name_buffer: [64]u8 = undefined;
        const name = arg(2, &name_buffer);
        if (std.mem.eql(u8, verb, "prepare")) {
            _ = try self.request(name);
            engine.print("dk3 render world: requested\n");
            return;
        }
        if (!std.mem.eql(u8, verb, "preview")) return error.InvalidRenderWorldCommand;
        for (self.entries) |maybe| if (maybe) |entry| {
            if (!std.mem.eql(u8, name, std.mem.sliceTo(&entry.name, 0))) continue;
            if (!entry.ready) return error.RenderWorldNotReady;
            var origin_buffer: [128]u8 = undefined;
            var angles_buffer: [128]u8 = undefined;
            self.preview = .{ .handle = entry.handle, .origin = try vector(arg(3, &origin_buffer)), .angles = try vector(arg(4, &angles_buffer)) };
            const previous = engine.gateway.call(c.CG_DK3_WORLD_CURRENT_V1, .{});
            if (engine.gateway.call(c.CG_DK3_WORLD_SELECT_V1, .{@as(isize, entry.handle)}) == 0) return error.RenderWorldNotReady;
            const model = engine.gateway.call(c.CG_R_REGISTERMODEL, .{@as([*:0]const u8, "*1")});
            if (engine.gateway.call(c.CG_DK3_WORLD_SELECT_V1, .{previous}) == 0) return error.RenderWorldSelectionLost;
            const active_model = engine.gateway.call(c.CG_R_REGISTERMODEL, .{@as([*:0]const u8, "*1")});
            var buffer: [256]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 render world: preview map={s} handle={d} inline1={d} active_inline1={d}\n", .{ name, entry.handle, model, active_model }));
            return;
        };
        return error.RenderWorldNotRequested;
    }
    pub fn renderPreview(self: *State, source: *const c.refdef_t) !bool {
        const preview = self.preview orelse return false;
        const previous = engine.gateway.call(c.CG_DK3_WORLD_CURRENT_V1, .{});
        if (engine.gateway.call(c.CG_DK3_WORLD_SELECT_V1, .{@as(isize, preview.handle)}) == 0) return error.RenderWorldNotReady;
        defer if (engine.gateway.call(c.CG_DK3_WORLD_SELECT_V1, .{previous}) == 0) @panic("lost active render world");
        _ = engine.gateway.call(c.CG_R_CLEARSCENE, .{});
        var ref = source.*;
        ref.vieworg = preview.origin;
        const orientation = v.basis(preview.angles);
        ref.viewaxis = .{ orientation.forward, v.scale(orientation.right, -1), v.cross(orientation.forward, v.scale(orientation.right, -1)) };
        @memset(&ref.areamask, 0);
        ref.rdflags = 0;
        _ = engine.gateway.call(c.CG_R_RENDERSCENE, .{&ref});
        return true;
    }
};
fn arg(index: i32, buffer: []u8) []const u8 {
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, index), buffer.ptr, @as(isize, @intCast(buffer.len)) });
    return std.mem.sliceTo(buffer, 0);
}
fn vector(text: []const u8) ![3]f32 {
    var values = std.mem.tokenizeAny(u8, text, " \t\r\n");
    var result: [3]f32 = undefined;
    for (&result) |*value| {
        value.* = try std.fmt.parseFloat(f32, values.next() orelse return error.InvalidWorldView);
        if (!std.math.isFinite(value.*)) return error.InvalidWorldView;
    }
    if (values.next() != null) return error.InvalidWorldView;
    return result;
}

fn patchAck(owner: u32, serial: u64) !void {
    var message: [96]u8 = undefined;
    _ = engine.gateway.call(c.CG_SENDCLIENTCOMMAND, .{(try std.fmt.bufPrintZ(&message, "dk3_world_patch_ack {d} {d}", .{ owner, serial })).ptr});
}
