// SPDX-License-Identifier: GPL-2.0-or-later
//! Bundled Lua 5.4 (engine/lua, MIT) for development drivers. Only pure libraries
//! are opened: scripts cannot reach files, processes, native modules, bytecode or
//! the debug API. Memory and uninterrupted instruction counts are bounded.
const std = @import("std");
pub const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
});
pub const State = c.lua_State;
pub const Function = *const fn (?*State) callconv(.c) c_int;
/// Instructions between budget checks; also bounds the overshoot of a runaway loop.
const hook_interval = 10_000;
pub const Vm = struct {
    state: *State,
    used: usize = 0,
    limit: usize,
    /// Instructions executed since the current host call began.
    steps: u64 = 0,
    step_limit: u64,
    failure: [512]u8 = @splat(0),
    failure_len: usize = 0,

    pub fn create(limit: usize, step_limit: u64) !*Vm {
        const self = try std.heap.c_allocator.create(Vm);
        errdefer std.heap.c_allocator.destroy(self);
        self.* = .{ .state = undefined, .limit = limit, .step_limit = step_limit };
        self.state = c.lua_newstate(allocate, self) orelse return error.OutOfMemory;
        errdefer c.lua_close(self.state);
        const L = self.state;
        for ([_]struct { name: [*:0]const u8, open: Function }{
            .{ .name = "_G", .open = c.luaopen_base },
            .{ .name = c.LUA_COLIBNAME, .open = c.luaopen_coroutine },
            .{ .name = c.LUA_TABLIBNAME, .open = c.luaopen_table },
            .{ .name = c.LUA_STRLIBNAME, .open = c.luaopen_string },
            .{ .name = c.LUA_MATHLIBNAME, .open = c.luaopen_math },
            .{ .name = c.LUA_UTF8LIBNAME, .open = c.luaopen_utf8 },
        }) |library| {
            c.luaL_requiref(L, library.name, library.open, 1);
            c.lua_settop(L, -2);
        }
        // Text chunks enter only through the host. Bytecode and file loaders are
        // removed; a fixed random seed keeps script decisions reproducible.
        try self.run(
            \\dofile, loadfile, load = nil, nil, nil
            \\string.dump = nil
            \\math.randomseed(0x6b3)
        , "=sandbox");
        c.lua_sethook(L, hook, c.LUA_MASKCOUNT, hook_interval);
        return self;
    }
    pub fn destroy(self: *Vm) void {
        c.lua_close(self.state);
        std.heap.c_allocator.destroy(self);
    }
    /// Compile and run a text chunk to completion on the main thread.
    pub fn run(self: *Vm, source: []const u8, name: [:0]const u8) !void {
        const L = self.state;
        self.steps = 0;
        if (c.luaL_loadbufferx(L, source.ptr, source.len, name.ptr, "t") != c.LUA_OK) return self.fail(L);
        if (c.lua_pcallk(L, 0, 0, 0, 0, null) != c.LUA_OK) return self.fail(L);
    }
    /// Copies the error value at the top of `L` and pops it.
    pub fn fail(self: *Vm, L: *State) error{Script} {
        self.capture(L);
        return error.Script;
    }
    pub fn capture(self: *Vm, L: *State) void {
        var length: usize = 0;
        const text: []const u8 = if (c.lua_tolstring(L, -1, &length)) |pointer| pointer[0..length] else "non-string error";
        self.failure_len = @min(text.len, self.failure.len);
        @memcpy(self.failure[0..self.failure_len], text[0..self.failure_len]);
        c.lua_settop(L, -2);
    }
    pub fn message(self: *const Vm) []const u8 {
        return self.failure[0..self.failure_len];
    }
    pub fn register(self: *Vm, table: [:0]const u8, name: [:0]const u8, function: Function, owner: *anyopaque) void {
        const L = self.state;
        if (c.lua_getglobal(L, table.ptr) != c.LUA_TTABLE) {
            c.lua_settop(L, -2);
            c.lua_createtable(L, 0, 16);
            c.lua_pushvalue(L, -1);
            c.lua_setglobal(L, table.ptr);
        }
        c.lua_pushlightuserdata(L, owner);
        c.lua_pushcclosure(L, function, 1);
        c.lua_setfield(L, -2, name.ptr);
        c.lua_settop(L, -2);
    }
    pub fn from(L: *State) *Vm {
        var owner: ?*anyopaque = null;
        _ = c.lua_getallocf(L, &owner);
        return @ptrCast(@alignCast(owner.?));
    }
};
/// The light userdata bound by `Vm.register`.
pub fn bound(comptime T: type, L: ?*State) *T {
    return @ptrCast(@alignCast(c.lua_touserdata(L, c.lua_upvalueindex(1)).?));
}
fn allocate(raw: ?*anyopaque, pointer: ?*anyopaque, old: usize, new: usize) callconv(.c) ?*anyopaque {
    const self: *Vm = @ptrCast(@alignCast(raw.?));
    const previous = if (pointer == null) 0 else old;
    if (new == 0) {
        std.c.free(pointer);
        self.used -= previous;
        return null;
    }
    if (new > previous and self.used + (new - previous) > self.limit) return null;
    const result = std.c.realloc(pointer, new) orelse return null;
    self.used = self.used - previous + new;
    return result;
}
fn hook(L: ?*State, _: [*c]c.lua_Debug) callconv(.c) void {
    const self = Vm.from(L.?);
    self.steps += hook_interval;
    if (self.steps > self.step_limit) _ = c.luaL_error(L, "script exceeded %d instructions without yielding", @as(c_int, @intCast(@min(self.step_limit, std.math.maxInt(c_int)))));
}
/// A coroutine anchored in the registry so the collector keeps it alive.
pub const Thread = struct {
    state: *State,
    reference: c_int,
    pub fn create(vm: *Vm) !Thread {
        const thread = c.lua_newthread(vm.state) orelse return error.OutOfMemory;
        return .{ .state = thread, .reference = c.luaL_ref(vm.state, c.LUA_REGISTRYINDEX) };
    }
    pub fn release(self: Thread, vm: *Vm) void {
        _ = c.lua_closethread(self.state, vm.state);
        c.luaL_unref(vm.state, c.LUA_REGISTRYINDEX, self.reference);
    }
    pub const Status = enum { yielded, finished };
    /// Resumes with `arguments` already pushed on the thread. Yielded values stay
    /// on the thread stack (`results` of them) until the caller pops them.
    pub fn resume_(self: Thread, vm: *Vm, arguments: c_int, results: *c_int) !Status {
        vm.steps = 0;
        return switch (c.lua_resume(self.state, vm.state, arguments, results)) {
            c.LUA_OK => .finished,
            c.LUA_YIELD => .yielded,
            else => vm.fail(self.state),
        };
    }
};
pub fn number(L: *State, index: c_int, key: [:0]const u8) ?f64 {
    defer c.lua_settop(L, -2);
    if (c.lua_getfield(L, index, key.ptr) != c.LUA_TNUMBER) return null;
    return c.lua_tonumberx(L, -1, null);
}
pub fn boolean(L: *State, index: c_int, key: [:0]const u8) ?bool {
    defer c.lua_settop(L, -2);
    if (c.lua_getfield(L, index, key.ptr) != c.LUA_TBOOLEAN) return null;
    return c.lua_toboolean(L, -1) != 0;
}
/// The returned slice is owned by Lua and only valid while the table holds it.
pub fn string(L: *State, index: c_int, key: [:0]const u8) ?[]const u8 {
    defer c.lua_settop(L, -2);
    if (c.lua_getfield(L, index, key.ptr) != c.LUA_TSTRING) return null;
    var length: usize = 0;
    const pointer = c.lua_tolstring(L, -1, &length) orelse return null;
    return pointer[0..length];
}
/// Reads `{x, y, z}` or `{x=, y=, z=}` from field `key` of the table at `index`.
pub fn vector(L: *State, index: c_int, key: [:0]const u8) ?[3]f32 {
    defer c.lua_settop(L, -2);
    if (c.lua_getfield(L, index, key.ptr) != c.LUA_TTABLE) return null;
    var result: [3]f32 = undefined;
    for (0..3) |axis| {
        const kind = c.lua_geti(L, -1, @intCast(axis + 1));
        defer c.lua_settop(L, -2);
        if (kind != c.LUA_TNUMBER) return null;
        result[axis] = @floatCast(c.lua_tonumberx(L, -1, null));
    }
    return result;
}

test "sandboxed scripts run, yield and cannot reach files or bytecode" {
    const t = std.testing;
    const vm = try Vm.create(4 * 1024 * 1024, 1_000_000);
    defer vm.destroy();
    try vm.run("value = 1 + 2", "=test");
    try t.expectEqual(c.LUA_TNUMBER, c.lua_getglobal(vm.state, "value"));
    try t.expectEqual(@as(f64, 3), c.lua_tonumberx(vm.state, -1, null));
    c.lua_settop(vm.state, 0);
    for ([_][:0]const u8{ "io", "os", "package", "debug", "require", "dofile", "loadfile", "load" }) |name| {
        try t.expectEqual(c.LUA_TNIL, c.lua_getglobal(vm.state, name.ptr));
        c.lua_settop(vm.state, 0);
    }
    try t.expectError(error.Script, vm.run("string.dump(print)", "=test"));
    try t.expect(std.mem.indexOf(u8, vm.message(), "dump") != null);
    try t.expectError(error.Script, vm.run("while true do end", "=test"));
    try t.expect(std.mem.indexOf(u8, vm.message(), "without yielding") != null);
    try vm.run("function route() local got = coroutine.yield({op = 'move', to = {1, 2, 3}}) assert(got == 'done') end", "=test");
    const thread = try Thread.create(vm);
    defer thread.release(vm);
    _ = c.lua_getglobal(thread.state, "route");
    var results: c_int = 0;
    try t.expectEqual(Thread.Status.yielded, try thread.resume_(vm, 0, &results));
    try t.expectEqual(@as(c_int, 1), results);
    try t.expectEqualStrings("move", string(thread.state, -1, "op").?);
    try t.expectEqual([3]f32{ 1, 2, 3 }, vector(thread.state, -1, "to").?);
    c.lua_settop(thread.state, 0);
    _ = c.lua_pushstring(thread.state, "done");
    try t.expectEqual(Thread.Status.finished, try thread.resume_(vm, 1, &results));
}

test "allocation limit fails the script instead of the host" {
    const vm = try Vm.create(512 * 1024, 100_000_000);
    defer vm.destroy();
    try std.testing.expectError(error.Script, vm.run("local t = {} for i = 1, 1e7 do t[i] = tostring(i) end", "=test"));
    try std.testing.expect(std.mem.indexOf(u8, vm.message(), "memory") != null);
    try vm.run("small = {1, 2, 3}", "=test");
}
