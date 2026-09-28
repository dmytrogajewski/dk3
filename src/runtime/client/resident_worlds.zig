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
    fn view(self: *State, id: u32) !View {
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
        if (self.initial) |initial| std.heap.c_allocator.destroy(initial);
        self.* = .{};
    }
    pub fn serverCommand(self: *State) !void {
        var buffer: [96]u8 = undefined;
        const command_name = arg(0, &buffer);
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
