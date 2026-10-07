// SPDX-License-Identifier: GPL-2.0-or-later
//! Lua boundary of the co-op bot: loads the sandboxed route through the engine
//! filesystem, exposes read-only `dk3.*` queries and decodes yielded actions.
//! Native functions never mutate the world; actions are typed requests only.
const std = @import("std");
const lua = @import("../engine/lua.zig");
const L_ = lua.c;
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const route = @import("../domain/coop_route.zig");
const targets = @import("coop_targets.zig");
const catalog = @import("actor_catalog");
const Frame = @import("coop_motor.zig").Frame;
const prelude = @embedFile("coop_prelude.lua");
const script_limit = 1024 * 1024;
/// World access for queries, present only while the driver resumes a level body.
pub const Query = struct { frame: Frame, map: []const u8, visit: u32, stage: *u32, stage_actions: *u32, operated: []const u32 = &.{} };
var active_query: ?*const Query = null;
pub const Yield = union(enum) { action: route.Action, returned, failed };
pub const Script = struct {
    vm: *lua.Vm,
    thread: ?lua.Thread = null,

    pub fn load(path: []const u8) !Script {
        const vm = try lua.Vm.create(64 * 1024 * 1024, 50_000_000);
        errdefer vm.destroy();
        var self: Script = .{ .vm = vm };
        for ([_]struct { [:0]const u8, lua.Function }{
            .{ "time", &time },                        .{ "map", &mapName },          .{ "position", &position },
            .{ "health", &health },                    .{ "alive", &alive },          .{ "mode", &mode },
            .{ "weapon", &weapon },                    .{ "has_weapon", &hasWeapon }, .{ "entity", &entity },
            .{ "hostiles", &hostiles },                .{ "mover", &mover },          .{ "cinematic", &cinematic },
            .{ "log", &log },                          .{ "event", &event },          .{ "include", &include },
            .{ "visit", &visit },                      .{ "visible", &visible },      .{ "stage", &stage },
            .{ "checkpoint_stage", &checkpointStage }, .{ "where", &where },          .{ "skipped", &skipped },
            .{ "reachable", &reachable },              .{ "controls", &controls },    .{ "exit_to", &exitTo },
            .{ "route", &routeTo },                    .{ "trace", &traceLine },      .{ "pickups", &pickups },
            .{ "contents", &pointContents },           .{ "ammo", &ammo },            .{ "plan", &plan },
            .{ "sidekick", &sidekick },
        }) |entry| vm.register("dk3", entry[0], entry[1], vm);
        vm.run(prelude, "=coop_prelude") catch return self.report(error.ScriptLoad);
        var name: [c.MAX_QPATH + 1]u8 = undefined;
        if (path.len >= name.len) return error.ScriptPath;
        @memcpy(name[0..path.len], path);
        name[path.len] = 0;
        try runFile(vm, vm.state, name[0..path.len :0]);
        return self;
    }
    pub fn deinit(self: *Script) void {
        self.close();
        self.vm.destroy();
    }
    fn report(self: *Script, err: anyerror) anyerror {
        printFailure(self.vm.message());
        return err;
    }
    pub fn message(self: *const Script) []const u8 {
        return self.vm.message();
    }
    pub fn option(self: *Script, name: [:0]const u8) i64 {
        return self.optionFor(name, "");
    }
    /// A run option as it applies on `map` (per-map overrides such as
    /// `settings { map_deaths = { e1m2a = 8 } }` for `level_deaths`).
    pub fn optionFor(self: *Script, name: [:0]const u8, map: []const u8) i64 {
        const L = self.vm.state;
        defer L_.lua_settop(L, 0);
        _ = L_.lua_getglobal(L, "__dk3_option");
        _ = L_.lua_pushstring(L, name.ptr);
        _ = L_.lua_pushlstring(L, map.ptr, map.len);
        if (L_.lua_pcallk(L, 2, 1, 0, 0, null) != L_.LUA_OK) return 0;
        return if (L_.lua_isinteger(L, -1) != 0) L_.lua_tointegerx(L, -1, null) else 0;
    }
    /// Starts the body registered for `map`; false when the route has none.
    pub fn begin(self: *Script, map: []const u8, number: u32, resumed: bool) !bool {
        self.close();
        const L = self.vm.state;
        _ = L_.lua_getglobal(L, "__dk3_level");
        _ = L_.lua_pushlstring(L, map.ptr, map.len);
        L_.lua_callk(L, 1, 1, 0, null);
        if (L_.lua_type(L, -1) != L_.LUA_TFUNCTION) {
            L_.lua_settop(L, 0);
            return false;
        }
        const thread = try lua.Thread.create(self.vm);
        L_.lua_xmove(L, thread.state, 1);
        L_.lua_settop(L, 0);
        L_.lua_pushinteger(thread.state, number);
        L_.lua_pushboolean(thread.state, @intFromBool(resumed));
        self.thread = thread;
        return true;
    }
    pub fn close(self: *Script) void {
        if (self.thread) |thread| thread.release(self.vm);
        self.thread = null;
    }
    /// Resumes the body. The first resume passes the level arguments pushed by
    /// `begin`; later ones deliver the previous action's outcome.
    pub fn advance(self: *Script, query: *const Query, outcome: ?Outcome) Yield {
        const thread = self.thread orelse return .returned;
        const T = thread.state;
        const arguments: c_int = 2;
        if (outcome) |value| {
            L_.lua_settop(T, 0);
            L_.lua_pushboolean(T, @intFromBool(value.ok));
            _ = L_.lua_pushlstring(T, value.detail.ptr, value.detail.len);
        }
        active_query = query;
        defer active_query = null;
        var results: c_int = 0;
        const status = thread.resume_(self.vm, arguments, &results) catch {
            printFailure(self.vm.message());
            self.close();
            return .failed;
        };
        if (status == .finished) {
            self.close();
            return .returned;
        }
        const decoded = if (results < 1 or L_.lua_type(T, -results) != L_.LUA_TTABLE) error.NotAnActionTable else decode(T, L_.lua_absindex(T, -results));
        L_.lua_settop(T, 0);
        const action = decoded catch |err| {
            var text: [160]u8 = undefined;
            printFailure(std.fmt.bufPrint(&text, "route yielded an invalid action: {s}", .{@errorName(err)}) catch "invalid action");
            self.close();
            return .failed;
        };
        return .{ .action = action };
    }
};
pub const Outcome = struct { ok: bool, detail: []const u8 };
fn printFailure(text: []const u8) void {
    var buffer: [640]u8 = undefined;
    engine.print(std.fmt.bufPrintZ(&buffer, "dk3 coop: event=script_error message=\"{s}\"\n", .{text}) catch return);
}
fn runFile(vm: *lua.Vm, L: *lua.State, path: [:0]const u8) !void {
    const bytes = try @import("../engine/files.zig").readOptional(.server, &engine.gateway, std.heap.c_allocator, path, script_limit) orelse {
        var text: [160]u8 = undefined;
        printFailure(std.fmt.bufPrint(&text, "missing route file {s}", .{path}) catch "missing route file");
        return error.MissingScript;
    };
    defer std.heap.c_allocator.free(bytes);
    var chunk: [c.MAX_QPATH + 2]u8 = undefined;
    const name = try std.fmt.bufPrintZ(&chunk, "@{s}", .{path});
    vm.steps = 0;
    if (L_.luaL_loadbufferx(L, bytes.ptr, bytes.len, name.ptr, "t") != L_.LUA_OK or L_.lua_pcallk(L, 0, 0, 0, 0, null) != L_.LUA_OK) {
        vm.capture(L);
        printFailure(vm.message());
        return error.ScriptLoad;
    }
}
fn decode(L: *lua.State, index: c_int) !route.Action {
    const op_name = lua.string(L, index, "op") orelse return error.MissingOperation;
    var action: route.Action = .{ .op = std.meta.stringToEnum(route.Op, op_name) orelse return error.UnknownOperation };
    if (lua.number(L, index, "timeout")) |seconds| action.timeout_ms = milliseconds(seconds);
    if (lua.number(L, index, "duration")) |seconds| action.duration_ms = milliseconds(seconds);
    if (lua.number(L, index, "radius")) |value| action.radius = @floatCast(value);
    if (lua.number(L, index, "yaw")) |value| action.yaw = @floatCast(value);
    if (lua.number(L, index, "pitch")) |value| action.pitch = @floatCast(value);
    if (lua.number(L, index, "pace")) |value| action.pace = std.math.clamp(@as(f32, @floatCast(value)), 0.1, 1);
    if (lua.number(L, index, "weapon")) |value| action.weapon = std.math.cast(u5, @as(i64, @intFromFloat(value))) orelse return error.InvalidWeapon;
    if (lua.number(L, index, "count")) |value| action.count = std.math.cast(u32, @as(i64, @intFromFloat(value))) orelse return error.InvalidCount;
    if (lua.boolean(L, index, "fight")) |value| action.fight = value;
    if (lua.boolean(L, index, "hold")) |value| action.hold = value;
    if (lua.boolean(L, index, "direct")) |value| action.direct = value;
    if (lua.boolean(L, index, "crouch")) |value| action.crouch = value;
    if (lua.boolean(L, index, "cautious")) |value| action.cautious = value;
    if (lua.boolean(L, index, "blast")) |value| action.blast = value;
    if (L_.lua_getfield(L, index, "arena") == L_.LUA_TTABLE) {
        const box = L_.lua_absindex(L, -1);
        var corners: [2][2]f32 = undefined;
        for (0..2) |corner| {
            if (L_.lua_geti(L, box, @intCast(corner + 1)) != L_.LUA_TTABLE) return error.InvalidArena;
            for (0..2) |axis| {
                _ = L_.lua_geti(L, -1, @intCast(axis + 1));
                corners[corner][axis] = @floatCast(L_.lua_tonumberx(L, -1, null));
                L_.lua_settop(L, -2);
            }
            L_.lua_settop(L, -2);
        }
        action.arena = .{ .{ @min(corners[0][0], corners[1][0]), @min(corners[0][1], corners[1][1]) }, .{ @max(corners[0][0], corners[1][0]), @max(corners[0][1], corners[1][1]) } };
    }
    L_.lua_settop(L, -2);
    if (lua.vector(L, index, "around")) |point| action.around = point;
    if (lua.string(L, index, "map")) |text| action.map = try route.Name.from(text);
    if (lua.string(L, index, "slot")) |text| action.slot = try route.Name.from(text);
    if (L_.lua_getfield(L, index, "target") == L_.LUA_TTABLE) {
        action.target = try selector(L, L_.lua_absindex(L, -1));
    }
    L_.lua_settop(L, -2);
    if (action.target == null) if (lua.string(L, index, "class")) |text| {
        action.target = .{ .class = try route.Name.from(text) };
    };
    return action;
}
fn milliseconds(seconds: f64) i64 {
    return @intFromFloat(std.math.clamp(seconds, 0, 86_400) * 1000);
}
/// `"name"`, `{x, y, z}` or `{name=, class=, id=, point=, near=}`.
fn selector(L: *lua.State, index: c_int) !route.Target {
    if (L_.lua_type(L, index) == L_.LUA_TSTRING) {
        var length: usize = 0;
        const text = L_.lua_tolstring(L, index, &length);
        return .{ .name = try route.Name.from(text[0..length]) };
    }
    if (L_.lua_type(L, index) != L_.LUA_TTABLE) return error.InvalidTarget;
    var result: route.Target = .{};
    if (L_.lua_geti(L, index, 1) == L_.LUA_TNUMBER) {
        var point: v.Vec3 = undefined;
        for (0..3) |axis| {
            _ = L_.lua_geti(L, index, @intCast(axis + 1));
            point[axis] = @floatCast(L_.lua_tonumberx(L, -1, null));
            L_.lua_settop(L, -2);
        }
        result.point = point;
    }
    L_.lua_settop(L, -2);
    if (lua.string(L, index, "name")) |text| result.name = try route.Name.from(text);
    if (lua.string(L, index, "class")) |text| result.class = try route.Name.from(text);
    if (lua.number(L, index, "id")) |value| result.id = std.math.cast(u32, @as(i64, @intFromFloat(value))) orelse return error.InvalidTarget;
    if (lua.number(L, index, "index")) |value| result.index = std.math.cast(u24, @as(i64, @intFromFloat(value))) orelse return error.InvalidTarget;
    if (lua.vector(L, index, "point")) |point| result.point = point;
    if (lua.vector(L, index, "near")) |point| result.near = point;
    if (result.point == null and result.name.empty() and result.class.empty() and result.id == 0 and result.index == 0) return error.EmptyTarget;
    return result;
}

// Native queries. Errors raised here unwind with longjmp, so they must not own
// resources or deferred work at the point of the call.
fn current(L: ?*lua.State) *const Query {
    return active_query orelse {
        _ = L_.luaL_error(L, "dk3 world queries are available only while a level body runs");
        unreachable;
    };
}
fn player(L: ?*lua.State, comptime T: type) T {
    const query = current(L);
    return (query.frame.world.get(query.frame.entity, T) catch {
        _ = L_.luaL_error(L, "player state unavailable");
        unreachable;
    }).*;
}
fn time(L: ?*lua.State) callconv(.c) c_int {
    L_.lua_pushinteger(L, current(L).frame.now);
    return 1;
}
fn mapName(L: ?*lua.State) callconv(.c) c_int {
    const name = current(L).map;
    _ = L_.lua_pushlstring(L, name.ptr, name.len);
    return 1;
}
fn visit(L: ?*lua.State) callconv(.c) c_int {
    L_.lua_pushinteger(L, current(L).visit);
    return 1;
}
fn position(L: ?*lua.State) callconv(.c) c_int {
    const pose = player(L, data.Transform);
    for (pose.position) |value| L_.lua_pushnumber(L, value);
    return 3;
}
fn health(L: ?*lua.State) callconv(.c) c_int {
    const value = player(L, data.Health);
    L_.lua_pushinteger(L, value.current);
    L_.lua_pushinteger(L, value.maximum);
    L_.lua_pushinteger(L, value.armor);
    return 3;
}
fn alive(L: ?*lua.State) callconv(.c) c_int {
    const state = player(L, data.Player);
    L_.lua_pushboolean(L, @intFromBool(state.mode != .dead and player(L, data.Health).current > 0));
    return 1;
}
fn mode(L: ?*lua.State) callconv(.c) c_int {
    _ = L_.lua_pushstring(L, @tagName(player(L, data.Player).mode).ptr);
    return 1;
}
fn weapon(L: ?*lua.State) callconv(.c) c_int {
    const loadout = player(L, data.Weapons);
    L_.lua_pushinteger(L, loadout.weapon);
    L_.lua_pushinteger(L, loadout.ammo[@intCast(std.math.clamp(loadout.weapon, 0, 31))]);
    return 2;
}
/// Rounds held for weapon `id` (whether or not the weapon is owned).
fn ammo(L: ?*lua.State) callconv(.c) c_int {
    const id = L_.luaL_checkinteger(L, 1);
    const loadout = player(L, data.Weapons);
    L_.lua_pushinteger(L, loadout.ammo[@intCast(std.math.clamp(id, 0, 31))]);
    return 1;
}
fn hasWeapon(L: ?*lua.State) callconv(.c) c_int {
    const id = L_.luaL_checkinteger(L, 1);
    const loadout = player(L, data.Weapons);
    L_.lua_pushboolean(L, @intFromBool(id >= 0 and id < 31 and loadout.dk3Inventory & (@as(i32, 1) << @intCast(id)) != 0));
    return 1;
}
fn checkedSelector(L: ?*lua.State, index: c_int) route.Target {
    return selector(L.?, index) catch {
        _ = L_.luaL_error(L, "invalid target selector");
        unreachable;
    };
}
fn entity(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    const target = checkedSelector(L, 1);
    const found = (targets.resolve(query.frame, target, .any) catch null) orelse {
        L_.lua_pushnil(L);
        return 1;
    };
    L_.lua_createtable(L, 0, 8);
    L_.lua_pushinteger(L, found.id);
    L_.lua_setfield(L, -2, "id");
    for (found.point, [_][*:0]const u8{ "x", "y", "z" }) |value, key| {
        L_.lua_pushnumber(L, value);
        L_.lua_setfield(L, -2, key);
    }
    if (found.entity) |handle| {
        const world = query.frame.world;
        if (world.get(handle, data.MapObject) catch null) |object| {
            _ = L_.lua_pushlstring(L, object.classname.ptr, object.classname.len);
            L_.lua_setfield(L, -2, "classname");
        }
        if (world.get(handle, data.Health) catch null) |value| {
            L_.lua_pushinteger(L, value.current);
            L_.lua_setfield(L, -2, "health");
        }
        if (targets.moverState(world, handle)) |state| {
            _ = L_.lua_pushlstring(L, state.ptr, state.len);
            L_.lua_setfield(L, -2, "state");
        }
        if (world.get(handle, data.HealthTree) catch null) |value| {
            L_.lua_pushinteger(L, value.fruit);
            L_.lua_setfield(L, -2, "fruit");
        }
        if (world.get(handle, data.Pickup) catch null) |value| {
            L_.lua_pushboolean(L, @intFromBool(value.visible));
            L_.lua_setfield(L, -2, "visible");
        }
    }
    return 1;
}
/// Clear shot line from the player's eye to the target's centre.
fn visible(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    const found = (targets.resolve(query.frame, checkedSelector(L, 1), .any) catch null) orelse {
        L_.lua_pushboolean(L, 0);
        return 1;
    };
    const world = query.frame.world;
    const pose = (world.get(query.frame.entity, data.Transform) catch unreachable).*;
    const eye = v.add(pose.position, .{ 0, 0, (world.get(query.frame.entity, data.Player) catch unreachable).view_height });
    const sight = engine.collisionService().trace(.{ .start = eye, .end = found.point, .mins = @splat(0), .maxs = @splat(0), .slot = query.frame.index, .mask = c.MASK_SHOT }) catch {
        L_.lua_pushboolean(L, 0);
        return 1;
    };
    L_.lua_pushboolean(L, @intFromBool(sight.fraction == 1 or (found.slot != null and sight.entity == found.slot.?)));
    return 1;
}
/// Visible pickups within `radius` of the player, nearest first is up to the
/// route: `{id, index, classname, x, y, z, health}` where `health` is what a
/// health item or soul restores (0 for other items).
fn pickups(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    const radius: f32 = @floatCast(L_.luaL_optnumber(L, 1, 1536));
    const world = query.frame.world;
    const origin = (world.get(query.frame.entity, data.Transform) catch unreachable).position;
    L_.lua_createtable(L, 8, 0);
    var count: i64 = 0;
    var items = world.queryAccess(data.World.mask(.{ data.Pickup, data.Transform, data.MapObject }), 0, 0);
    defer items.deinit();
    while (items.next()) |view| for (view.entities(), view.read(data.Pickup), view.read(data.Transform), view.read(data.MapObject)) |item, pickup, pose, object| {
        if (!pickup.visible or v.length(v.subtract(pose.position, origin)) > radius) continue;
        const id = world.persistentId(item) catch continue;
        count += 1;
        L_.lua_createtable(L, 0, 7);
        L_.lua_pushinteger(L, id);
        L_.lua_setfield(L, -2, "id");
        L_.lua_pushinteger(L, id & 0xffffff);
        L_.lua_setfield(L, -2, "index");
        _ = L_.lua_pushlstring(L, object.classname.ptr, object.classname.len);
        L_.lua_setfield(L, -2, "classname");
        for ([_][:0]const u8{ "x", "y", "z" }, pose.position) |key, value| {
            L_.lua_pushnumber(L, value);
            L_.lua_setfield(L, -2, key);
        }
        L_.lua_pushinteger(L, switch (pickup.kind) {
            .health => |amount| amount,
            .soul => 100,
            else => 0,
        });
        L_.lua_setfield(L, -2, "health");
        // The weapon an ammunition pack (or a weapon pickup) feeds, 0 for none.
        L_.lua_pushinteger(L, switch (pickup.kind) {
            .ammunition => |weapon_id| weapon_id,
            .weapon => |weapon_id| weapon_id,
            else => 0,
        });
        L_.lua_setfield(L, -2, "ammo");
        L_.lua_rawseti(L, -2, count);
    };
    return 1;
}
/// Collision probe for authoring: `dk3.trace(start, end, hull)` sweeps a point
/// (or the player hull when `hull` is true, the crouched hull when it is
/// "crouch") against world and movers and returns
/// `{fraction, x, y, z, normal_z, class, index, start_solid}` of the first
/// contact.
fn traceLine(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    var ends: [2]v.Vec3 = undefined;
    for (&ends, 1..) |*point, argument| {
        if (L_.lua_type(L, @intCast(argument)) != L_.LUA_TTABLE) return L_.luaL_error(L, "trace: expected {x, y, z}");
        for (0..3) |axis| {
            if (L_.lua_geti(L, @intCast(argument), @intCast(axis + 1)) != L_.LUA_TNUMBER) return L_.luaL_error(L, "trace: expected {x, y, z}");
            point[axis] = @floatCast(L_.lua_tonumberx(L, -1, null));
            L_.lua_settop(L, -2);
        }
    }
    // A third argument: true or "crouch" sweeps the player's hull; "shot"
    // traces a line as a bullet does (MASK_SHOT: through player clips).
    const shot = L_.lua_type(L, 3) == L_.LUA_TSTRING and std.mem.eql(u8, std.mem.span(L_.lua_tolstring(L, 3, null)), "shot");
    const hull = L_.lua_toboolean(L, 3) != 0 and !shot;
    const crouched = L_.lua_type(L, 3) == L_.LUA_TSTRING and std.mem.eql(u8, std.mem.span(L_.lua_tolstring(L, 3, null)), "crouch");
    const result = engine.collisionService().trace(.{ .start = ends[0], .end = ends[1], .mins = if (hull) .{ -15, -15, -24 } else @splat(0), .maxs = if (crouched) .{ 15, 15, 4 } else if (hull) .{ 15, 15, 32 } else @splat(0), .slot = query.frame.index, .mask = if (shot) c.MASK_SHOT else c.MASK_PLAYERSOLID }) catch return 0;
    L_.lua_createtable(L, 0, 9);
    for ([_][:0]const u8{ "fraction", "x", "y", "z", "normal_z" }, [_]f32{ result.fraction, result.end[0], result.end[1], result.end[2], result.normal[2] }) |key, value| {
        L_.lua_pushnumber(L, value);
        L_.lua_setfield(L, -2, key);
    }
    var class: []const u8 = if (result.fraction < 1) "world" else "-";
    var index: u32 = 0;
    if (result.fraction < 1 and result.entity < query.frame.slots.occupants.len) if (query.frame.slots.occupants[result.entity]) |hit| {
        if (query.frame.world.get(hit, data.MapObject) catch null) |object| class = object.classname;
        index = (query.frame.world.persistentId(hit) catch 0) & 0xffffff;
    };
    _ = L_.lua_pushlstring(L, class.ptr, class.len);
    L_.lua_setfield(L, -2, "class");
    L_.lua_pushinteger(L, index);
    L_.lua_setfield(L, -2, "index");
    L_.lua_pushboolean(L, @intFromBool(result.start_solid));
    L_.lua_setfield(L, -2, "start_solid");
    L_.lua_pushboolean(L, @intFromBool(result.ladder));
    L_.lua_setfield(L, -2, "ladder");
    return 1;
}
/// Contents bits at a point (water 32, slime 16, lava 8, solid 1), entities
/// included: where liquids and movers stand when a route needs to know.
fn pointContents(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    if (L_.lua_type(L, 1) != L_.LUA_TTABLE) return L_.luaL_error(L, "contents: expected {x, y, z}");
    var point: v.Vec3 = undefined;
    for (0..3) |axis| {
        if (L_.lua_geti(L, 1, @intCast(axis + 1)) != L_.LUA_TNUMBER) return L_.luaL_error(L, "contents: expected {x, y, z}");
        point[axis] = @floatCast(L_.lua_tonumberx(L, -1, null));
        L_.lua_settop(L, -2);
    }
    const bits = engine.collisionService().contents(point, @intCast(query.frame.index)) catch 0;
    L_.lua_pushinteger(L, bits);
    return 1;
}
/// `file:line` of the innermost route-script frame, skipping the prelude, so a
/// failed action names the route line that asked for it (tail calls included).
fn where(L: ?*lua.State) callconv(.c) c_int {
    var level: c_int = 1;
    var info: L_.lua_Debug = undefined;
    while (L_.lua_getstack(L, level, &info) != 0) : (level += 1) {
        if (L_.lua_getinfo(L, "Sl", &info) == 0) break;
        const source = std.mem.sliceTo(&info.short_src, 0);
        if (info.currentline <= 0 or std.mem.indexOf(u8, source, "coop_prelude") != null) continue;
        _ = L_.lua_pushfstring(L, "%s:%d", &info.short_src, info.currentline);
        return 1;
    }
    _ = L_.lua_pushstring(L, "route");
    return 1;
}
/// Whether the navigation graph has a route from the player to the target now.
/// Brush controls are judged by a supported standing point that can operate
/// them; trigger volumes and points by the floor below them.
fn reachable(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    const target = checkedSelector(L, 1);
    var kind_length: usize = 0;
    const kind = L_.luaL_optlstring(L, 2, "", &kind_length)[0..kind_length];
    const found = (targets.resolve(query.frame, target, .any) catch null) orelse {
        L_.lua_pushboolean(L, 0);
        return 1;
    };
    const result = reach(query.frame, found, kind) catch false;
    L_.lua_pushboolean(L, @intFromBool(result));
    return 1;
}
fn reach(frame: Frame, found: targets.Resolved, kind: []const u8) !bool {
    const world = frame.world;
    const origin = (try world.get(frame.entity, data.Transform)).position;
    if (found.entity) |control| if (kind.len != 0) {
        const action: @FieldType(@import("bot_routes.zig").Control, "action") = if (std.mem.eql(u8, kind, "shoot")) .shoot else if (std.mem.eql(u8, kind, "touch")) .touch else .use;
        var obstructions: [@import("bot_routes.zig").approach_points]u16 = @splat(c.ENTITYNUM_NONE);
        const diagnostic = engine.integer("developer") >= 2;
        return try @import("bot_routes.zig").approach(world, control, frame.entity, action, frame.service, frame.projections, diagnostic, &obstructions) != null;
    };
    return try frame.service.next(.{ .position = origin, .destination = try standingGoal(frame, found), .slot = frame.index, .player = true, .allow_slime_escape = true }) != null;
}
/// The control the navigation planner would operate first to reach the target:
/// the route with every navigation gate open crosses a closed one (a door,
/// toggled wall, damaging volume, retracted floor or breakable), and the
/// authored chain that opens it ends in this control, possibly itself behind
/// another gate. `{id, index, gate, action = "use"|"touch"|"shoot", x, y, z}` (the
/// point to operate it from), `{wait = true}` while the gate in the way is
/// already moving, or nil when a live route exists or none is known.
fn plan(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    const target = checkedSelector(L, 1);
    const frame = query.frame;
    const state = frame.gates orelse {
        L_.lua_pushnil(L);
        return 1;
    };
    const found = (targets.resolve(frame, target, .any) catch null) orelse {
        L_.lua_pushnil(L);
        return 1;
    };
    const goal = standingGoal(frame, found) catch {
        L_.lua_pushnil(L);
        return 1;
    };
    var waiting = false;
    const control = (@import("bot_routes.zig").unblockWaiting(frame.world, frame.slots, frame.projections, state, frame.entity, goal, frame.service, frame.now, 0, &waiting) catch null) orelse {
        if (!waiting) {
            L_.lua_pushnil(L);
            return 1;
        }
        // The gate in the way is already moving: nothing to operate, wait.
        L_.lua_createtable(L, 0, 1);
        L_.lua_pushboolean(L, 1);
        L_.lua_setfield(L, -2, "wait");
        return 1;
    };
    L_.lua_createtable(L, 0, 7);
    L_.lua_pushinteger(L, control.id);
    L_.lua_setfield(L, -2, "id");
    L_.lua_pushinteger(L, control.id & 0xffffff);
    L_.lua_setfield(L, -2, "index");
    L_.lua_pushinteger(L, control.route_obstacle);
    L_.lua_setfield(L, -2, "gate");
    _ = L_.lua_pushstring(L, @tagName(control.action).ptr);
    L_.lua_setfield(L, -2, "action");
    for ([_][*:0]const u8{ "x", "y", "z" }, control.point) |key, value| {
        L_.lua_pushnumber(L, value);
        L_.lua_setfield(L, -2, key);
    }
    return 1;
}
/// Brush targets and points are approached at the floor below them.
fn standingGoal(frame: Frame, found: targets.Resolved) !v.Vec3 {
    if (found.brush) if (try @import("bot_routes.zig").touchPointFrom(found.mins, found.maxs, frame.index, .{ .position = (try frame.world.get(frame.entity, data.Transform)).position, .service = frame.service })) |point| return point;
    var goal = found.point;
    if (found.brush) goal[2] = @min(found.maxs[2], found.mins[2] + 32);
    const floor = try engine.collisionService().trace(.{ .start = goal, .end = v.add(goal, .{ 0, 0, -512 }), .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 32 }, .slot = frame.index, .mask = c.MASK_PLAYERSOLID });
    if (!floor.start_solid and !floor.all_solid and floor.fraction < 1) goal = floor.end;
    return goal;
}
/// The area graph's predicted route to the target, from the player or from an
/// optional point `{x, y, z}`, as a list of up to 64 reachability points;
/// empty without a route. For authoring: it shows which passages navigation
/// believes are open.
fn routeTo(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    const target = checkedSelector(L, 1);
    var point = (query.frame.world.get(query.frame.entity, data.Transform) catch unreachable).position;
    if (L_.lua_type(L, 2) == L_.LUA_TTABLE) for (0..3) |axis| {
        if (L_.lua_geti(L, 2, @intCast(axis + 1)) != L_.LUA_TNUMBER) return L_.luaL_error(L, "route: start must be {x, y, z}");
        point[axis] = @floatCast(L_.lua_tonumberx(L, -1, null));
        L_.lua_settop(L, -2);
    };
    L_.lua_createtable(L, 16, 0);
    const found = (targets.resolve(query.frame, target, .any) catch null) orelse return 1;
    const goal = standingGoal(query.frame, found) catch return 1;
    var points: [64]v.Vec3 = undefined;
    const count = query.frame.service.predict(.{ .position = point, .destination = goal, .slot = query.frame.index, .player = true }, &points) catch 0;
    for (points[0..count], 1..) |step, index| {
        L_.lua_createtable(L, 3, 0);
        for (0..3) |axis| {
            L_.lua_pushnumber(L, step[axis]);
            L_.lua_rawseti(L, -2, @intCast(axis + 1));
        }
        L_.lua_rawseti(L, -2, @intCast(index));
    }
    return 1;
}
/// Authored controls a player can operate: buttons (used, touched or shot),
/// touch triggers and shootable breakables that fire targets. `ready` means it
/// can still react (an unpressed button, an unfired trigger, an unbroken target).
fn controls(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    const world = query.frame.world;
    L_.lua_createtable(L, 16, 0);
    var count: i64 = 0;
    var objects = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
    while (objects.next()) |view| for (view.entities(), view.read(data.MapObject)) |handle, object| {
        const button = std.mem.eql(u8, object.classname, "func_button");
        const trigger = std.mem.eql(u8, object.classname, "trigger_once") or std.mem.eql(u8, object.classname, "trigger_multiple");
        // Breakables that fire targets, or remove them (walls, crushers in a passage).
        const breakable = std.mem.eql(u8, object.classname, "func_explosive") and object.targetname.len == 0 and
            (object.target.len != 0 or @import("properties.zig").text(object, "killtarget") != null);
        // Untargeted doors without the proximity flag open only when used.
        const door = std.mem.startsWith(u8, object.classname, "func_door") and object.targetname.len == 0 and object.flags & 16 == 0;
        if (!button and !trigger and !breakable and !door) continue;
        // A beam that switches damage on (a laser across a corridor) is a hazard.
        if (button and @import("navigation_gates.zig").tripwire(world, object)) continue;
        // Triggers fired only by other entities (targetname set) are not player controls.
        if (trigger and object.targetname.len != 0) continue;
        const shootable = (@import("properties.zig").number(object, "health", 0) catch 0) > 0;
        const kind: [:0]const u8 = if (shootable or breakable) "shoot" else if (trigger or (button and object.flags & 1 != 0)) "touch" else "use";
        var ready = true;
        if (world.get(handle, data.Mover) catch null) |motion| ready = motion.state == .closed;
        if (world.get(handle, data.Trigger) catch null) |state| if (state.limit > 0 and state.uses >= state.limit) {
            ready = false;
        };
        if (world.get(handle, data.Health) catch null) |vitality| if (shootable and vitality.current <= 0) {
            ready = false;
        };
        if (world.get(handle, data.Destructible) catch null) |state| if (state.broken) {
            ready = false;
        };
        const found = targets.describe(query.frame, handle) catch continue;
        count += 1;
        L_.lua_createtable(L, 0, 8);
        L_.lua_pushinteger(L, found.id);
        L_.lua_setfield(L, -2, "id");
        L_.lua_pushinteger(L, found.id & 0xffffff);
        L_.lua_setfield(L, -2, "index");
        _ = L_.lua_pushlstring(L, object.classname.ptr, object.classname.len);
        L_.lua_setfield(L, -2, "classname");
        _ = L_.lua_pushlstring(L, object.target.ptr, object.target.len);
        L_.lua_setfield(L, -2, "target");
        _ = L_.lua_pushstring(L, kind.ptr);
        L_.lua_setfield(L, -2, "kind");
        L_.lua_pushboolean(L, @intFromBool(ready));
        L_.lua_setfield(L, -2, "ready");
        L_.lua_pushboolean(L, @intFromBool(std.mem.indexOfScalar(u32, query.operated, found.id) != null));
        L_.lua_setfield(L, -2, "operated");
        for (found.point, [_][*:0]const u8{ "x", "y", "z" }) |value, key| {
            L_.lua_pushnumber(L, value);
            L_.lua_setfield(L, -2, key);
        }
        L_.lua_seti(L, -2, count);
    };
    objects.deinit();
    return 1;
}
/// Persistent id of the nearest authored exit leading to the named map.
fn exitTo(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    var length: usize = 0;
    const wanted = L_.luaL_checklstring(L, 1, &length)[0..length];
    const world = query.frame.world;
    const origin = (world.get(query.frame.entity, data.Transform) catch unreachable).position;
    var best: u32 = 0;
    var nearest: f32 = std.math.inf(f32);
    var best_fired = true;
    var exits = world.queryAccess(data.World.mask(.{ data.Exit, data.MapObject, data.Transform }), 0, 0);
    while (exits.next()) |view| for (view.entities(), view.read(data.MapObject)) |handle, object| {
        const destination = @import("properties.zig").text(object, "map") orelse continue;
        if (!std.ascii.eqlIgnoreCase(destination, wanted)) continue;
        const found = targets.describe(query.frame, handle) catch continue;
        const distance = v.length(v.subtract(found.point, origin));
        // An exit another entity fires (e1m3b's "chlevel", up in the air
        // after the ending scene) is not one to walk into: touchable first.
        const fired = object.targetname.len != 0;
        if (fired and !best_fired) continue;
        if (fired == best_fired and distance >= nearest) continue;
        nearest = distance;
        best = found.id;
        best_fired = fired;
    };
    exits.deinit();
    if (best == 0) L_.lua_pushnil(L) else L_.lua_pushinteger(L, best);
    return 1;
}
/// Counts an action the route skipped while fast-forwarding a restored stage.
fn skipped(L: ?*lua.State) callconv(.c) c_int {
    current(L).stage_actions.* += 1;
    return 0;
}
/// Records the running stage; the next game save remembers it for restoration.
fn stage(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    const number = L_.luaL_checkinteger(L, 1);
    var length: usize = 0;
    const name = L_.luaL_checklstring(L, 2, &length);
    query.stage.* = std.math.cast(u32, number) orelse 0;
    query.stage_actions.* = 0;
    // `dk3.stage(n, name, true)` only restarts the action count (after the
    // stage's own checkpoint save, which is not one of the body's actions).
    if (L_.lua_toboolean(L, 3) != 0) return 0;
    var buffer: [256]u8 = undefined;
    engine.print(std.fmt.bufPrintZ(&buffer, "dk3 coop: t={d} event=stage map={s} stage={d} name={s}\n", .{ query.frame.now, query.map, number, name[0..@min(length, 64)] }) catch unreachable);
    return 0;
}
/// Stage recorded with the save the world was restored from, on this map.
fn checkpointStage(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    var value: [96]u8 = @splat(0);
    _ = engine.gateway.call(c.G_CVAR_VARIABLE_STRING_BUFFER, .{ @as([*:0]const u8, "dk3_coop_checkpoint"), &value, @as(isize, value.len) });
    var words = std.mem.tokenizeScalar(u8, std.mem.sliceTo(&value, 0), ' ');
    const map = words.next() orelse "";
    const number = std.fmt.parseInt(i64, words.next() orelse "0", 10) catch 0;
    const completed = std.fmt.parseInt(i64, words.next() orelse "0", 10) catch 0;
    const same = std.mem.eql(u8, map, query.map);
    L_.lua_pushinteger(L, if (same) number else 0);
    L_.lua_pushinteger(L, if (same) completed else 0);
    return 2;
}
fn hostiles(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    const radius: f32 = @floatCast(L_.luaL_optnumber(L, 1, 1536));
    // Around the player, or around a given point {x, y, z}.
    var origin = (query.frame.world.get(query.frame.entity, data.Transform) catch unreachable).position;
    if (L_.lua_type(L, 2) == L_.LUA_TTABLE) for (0..3) |axis| {
        _ = L_.lua_rawgeti(L, 2, @intCast(axis + 1));
        origin[axis] = @floatCast(L_.luaL_checknumber(L, -1));
        L_.lua_settop(L, -2);
    };
    var count: i64 = 0;
    var actors = query.frame.world.queryAccess(data.World.mask(.{ data.Actor, data.Health, data.Transform }), 0, 0);
    while (actors.next()) |view| for (view.read(data.Actor), view.read(data.Health), view.read(data.Transform)) |actor, value, pose| {
        if (value.current > 0 and route.hostile(catalog.entries[actor.definition].kind) and v.length(v.subtract(pose.position, origin)) <= radius) count += 1;
    };
    actors.deinit();
    L_.lua_pushinteger(L, count);
    return 1;
}
fn mover(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    const found = (targets.resolve(query.frame, checkedSelector(L, 1), .mover) catch null) orelse {
        L_.lua_pushnil(L);
        return 1;
    };
    const state = targets.moverState(query.frame.world, found.entity.?) orelse "-";
    _ = L_.lua_pushlstring(L, state.ptr, state.len);
    return 1;
}
fn cinematic(L: ?*lua.State) callconv(.c) c_int {
    L_.lua_pushboolean(L, @intFromBool(@import("cinematics.zig").active(current(L).frame.world)));
    return 1;
}
/// `dk3.sidekick(who, order)`: the player's companion order ("superfly",
/// "mikiko" or "all"; "follow", "stay", ...), sent as the client command a
/// player's key binding sends. Returns nothing; the companion may refuse.
fn sidekick(L: ?*lua.State) callconv(.c) c_int {
    const query = current(L);
    var who_length: usize = 0;
    var order_length: usize = 0;
    const who = L_.luaL_checklstring(L, 1, &who_length)[0..who_length];
    const order = L_.luaL_checklstring(L, 2, &order_length)[0..order_length];
    for (who) |byte| if (!std.ascii.isAlphabetic(byte)) return L_.luaL_error(L, "sidekick: bad companion name");
    for (order) |byte| if (!std.ascii.isAlphabetic(byte)) return L_.luaL_error(L, "sidekick: bad order");
    var buffer: [96]u8 = undefined;
    const command = std.fmt.bufPrintZ(&buffer, "sidekick {s} {s}", .{ who[0..@min(who.len, 16)], order[0..@min(order.len, 16)] }) catch return 0;
    @import("coop_link.zig").client(query.frame.index, command);
    return 0;
}
fn log(L: ?*lua.State) callconv(.c) c_int {
    var length: usize = 0;
    const text = L_.luaL_checklstring(L, 1, &length);
    var buffer: [640]u8 = undefined;
    engine.print(std.fmt.bufPrintZ(&buffer, "dk3 coop: event=log message=\"{s}\"\n", .{text[0..@min(length, 512)]}) catch unreachable);
    return 0;
}
fn event(L: ?*lua.State) callconv(.c) c_int {
    var kind_length: usize = 0;
    var text_length: usize = 0;
    const kind = L_.luaL_checklstring(L, 1, &kind_length);
    const text = L_.luaL_optlstring(L, 2, "", &text_length);
    const time_ms: i64 = if (active_query) |query| query.frame.now else -1;
    var buffer: [640]u8 = undefined;
    engine.print(std.fmt.bufPrintZ(&buffer, "dk3 coop: t={d} event={s} detail=\"{s}\"\n", .{ time_ms, kind[0..@min(kind_length, 32)], text[0..@min(text_length, 512)] }) catch unreachable);
    return 0;
}
/// Load-time composition of route files: `include "coop/episode1.lua"`.
fn include(L: ?*lua.State) callconv(.c) c_int {
    if (active_query != null) {
        _ = L_.luaL_error(L, "include is only available while the route loads");
        unreachable;
    }
    var length: usize = 0;
    const text = L_.luaL_checklstring(L, 1, &length);
    var path: [c.MAX_QPATH + 1]u8 = undefined;
    if (length >= path.len) {
        _ = L_.luaL_error(L, "include path too long");
        unreachable;
    }
    @memcpy(path[0..length], text[0..length]);
    path[length] = 0;
    const bytes = (@import("../engine/files.zig").readOptional(.server, &engine.gateway, std.heap.c_allocator, path[0..length :0], script_limit) catch null) orelse {
        _ = L_.luaL_error(L, "cannot read route file %s", path[0..length :0].ptr);
        unreachable;
    };
    var chunk: [c.MAX_QPATH + 2]u8 = undefined;
    const name = std.fmt.bufPrintZ(&chunk, "@{s}", .{path[0..length]}) catch unreachable;
    const loaded = L_.luaL_loadbufferx(L, bytes.ptr, bytes.len, name.ptr, "t");
    std.heap.c_allocator.free(bytes);
    if (loaded != L_.LUA_OK) {
        _ = L_.lua_error(L);
        unreachable;
    }
    L_.lua_callk(L, 0, 0, 0, null);
    return 0;
}
