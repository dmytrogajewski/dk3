// SPDX-License-Identifier: GPL-2.0-or-later
//! Native menus bind the existing asynchronous browser and authenticated room API.
const std = @import("std");
const engine = @import("../engine/ui.zig");
const c = engine.c;
const info = @import("../engine/info.zig");
pub const Page = enum { rooms, create, filters, connection, private, lan, player, lobby };
pub const Field = enum { room_name, region, map, rotation, coordinator, certificate, search, filter_region, private_id, code, address, player_name };
const fields = [_]struct { name: [:0]const u8, label: []const u8, initial: [:0]const u8 }{
    .{ .name = "ui_roomName", .label = "Room", .initial = "My room" },
    .{ .name = "ui_roomRegion", .label = "Region", .initial = "default" },
    .{ .name = "ui_roomMap", .label = "Map", .initial = "e1dm1" },
    .{ .name = "ui_roomRotation", .label = "Rotation", .initial = "" },
    .{ .name = "dk3_coordinator", .label = "Coordinator URL", .initial = "" },
    .{ .name = "dk3_ca_file", .label = "Trusted CA file", .initial = "" },
    .{ .name = "ui_roomSearch", .label = "Search", .initial = "" },
    .{ .name = "ui_roomFilterRegion", .label = "Region filter", .initial = "" },
    .{ .name = "ui_privateRoom", .label = "Private room ID", .initial = "" },
    .{ .name = "ui_roomCode", .label = "Access code", .initial = "" },
    .{ .name = "ui_lanAddress", .label = "Server address", .initial = "localhost:27960" },
    .{ .name = "name", .label = "Player name", .initial = "Hiro" },
};
pub const Action = union(enum) { page: Page, edit: Field, select: usize, cycle: enum { mode, slots, bots, skill, privacy, filter_mode, favorites, available, appearance }, refresh, join, favorite, create, join_private, reconnect, host_lan, join_lan, next, previous, ready, red, blue, spectator, free };
pub const Browser = struct {
    page: Page = .rooms,
    first: usize = 0,
    selected: ?usize = null,
    selected_id: [65]u8 = @splat(0),
    editing: ?Field = null,
    text: [256:0]u8 = @splat(0),
    pub fn init(_: *Browser) void {
        for (fields) |field| engine.register(field.name, field.initial);
        for ([_][2][:0]const u8{ .{ "ui_roomMode", "0" }, .{ "ui_roomSlots", "8" }, .{ "ui_roomBots", "0" }, .{ "ui_roomSkill", "3" }, .{ "ui_roomPrivate", "0" }, .{ "ui_roomFilterMode", "-1" }, .{ "ui_roomFavoritesOnly", "0" }, .{ "ui_roomAvailableOnly", "1" }, .{ "model", "hiro/0" } }) |pair| engine.register(pair[0], pair[1]);
    }
    fn row(self: *Browser, menu: anytype, y: f32, field: Field) !void {
        var buffer: [256]u8 = undefined;
        const value = engine.get(fields[@intFromEnum(field)].name, &buffer);
        var label: [320]u8 = undefined;
        const shown = if (self.editing == field) std.mem.sliceTo(&self.text, 0) else value;
        try button(menu, 90, y, 340, try std.fmt.bufPrint(&label, "{s}: {s}{s}", .{ fields[@intFromEnum(field)].label, shown[0..@min(shown.len, 38)], if (self.editing == field) "_" else "" }), .{ .edit = field });
    }
    fn button(menu: anytype, x: f32, y: f32, width: f32, label: []const u8, action: Action) !void {
        menu.button(x, y, width, label, .{ .multiplayer = action });
    }
    fn valueButton(menu: anytype, y: f32, title: []const u8, variable: [:0]const u8, action: Action) !void {
        var buffer: [192]u8 = undefined;
        try button(menu, 90, y, 340, try std.fmt.bufPrint(&buffer, "{s}: {d}", .{ title, @as(i32, @intFromFloat(engine.number(variable))) }), action);
    }
    pub fn render(self: *Browser, menu: anytype) !void {
        try button(menu, 90, 95, 85, "Rooms", .{ .page = .rooms });
        try button(menu, 180, 95, 85, "Create", .{ .page = .create });
        try button(menu, 270, 95, 85, "Player", .{ .page = .player });
        try button(menu, 360, 95, 75, "LAN", .{ .page = .lan });
        switch (self.page) {
            .rooms => {
                const count: usize = @intFromFloat(std.math.clamp(engine.number("dk3_roomCount"), 0, 128));
                if (self.first >= count) self.first = if (count > 0) (count - 1) / 6 * 6 else 0;
                for (self.first..@min(self.first + 6, count)) |index| {
                    var name: [32]u8 = undefined;
                    var buffer: [1024]u8 = undefined;
                    const room = engine.get(try std.fmt.bufPrintZ(&name, "dk3_room{d}", .{index}), &buffer);
                    var label: [256]u8 = undefined;
                    const title = info.get(room, "name") orelse "Room";
                    try button(menu, 90, 135 + @as(f32, @floatFromInt(index - self.first)) * 30, 340, try std.fmt.bufPrint(&label, "{s}{s} {s} {s}ms", .{ if (self.selected == index) "> " else "", title[0..@min(title.len, 24)], info.get(room, "players") orelse "0/?", info.get(room, "ping") orelse "?" }), .{ .select = index });
                }
                try button(menu, 90, 322, 75, "Refresh", .refresh);
                try button(menu, 175, 322, 65, "Join", .join);
                try button(menu, 245, 322, 85, "Favorite", .favorite);
                try button(menu, 335, 322, 45, "<", .previous);
                try button(menu, 390, 322, 45, ">", .next);
                try button(menu, 90, 356, 90, "Filters", .{ .page = .filters });
                try button(menu, 195, 356, 90, "Private", .{ .page = .private });
                try button(menu, 310, 356, 120, "Connection", .{ .page = .connection });
                if (engine.inGame()) try button(menu, 90, 389, 170, "Match / lobby", .{ .page = .lobby });
                var status: [256]u8 = undefined;
                menu.art.text(menu.layout, 90, 416, engine.get("dk3_onlineStatus", &status), false);
            },
            .create, .lan => {
                try self.row(menu, 130, .map);
                try valueButton(menu, 160, "Mode (0 DM / 1 CTF / 2 DT)", "ui_roomMode", .{ .cycle = .mode });
                try valueButton(menu, 190, "Players", "ui_roomSlots", .{ .cycle = .slots });
                try valueButton(menu, 220, "Bots", "ui_roomBots", .{ .cycle = .bots });
                if (self.page == .create) {
                    try self.row(menu, 250, .room_name);
                    try self.row(menu, 280, .region);
                    try self.row(menu, 310, .rotation);
                    try valueButton(menu, 340, "Private room", "ui_roomPrivate", .{ .cycle = .privacy });
                    try button(menu, 90, 382, 180, "Create Internet room", .create);
                } else {
                    try valueButton(menu, 250, "Bot skill", "ui_roomSkill", .{ .cycle = .skill });
                    try button(menu, 90, 285, 180, "Host LAN game", .host_lan);
                    try self.row(menu, 330, .address);
                    try button(menu, 90, 370, 180, "Join LAN server", .join_lan);
                }
            },
            .filters => {
                try self.row(menu, 145, .search);
                try self.row(menu, 185, .filter_region);
                try valueButton(menu, 225, "Mode (-1 all / 0 DM / 1 CTF / 2 DT)", "ui_roomFilterMode", .{ .cycle = .filter_mode });
                try valueButton(menu, 265, "Favorites only", "ui_roomFavoritesOnly", .{ .cycle = .favorites });
                try valueButton(menu, 305, "Available only", "ui_roomAvailableOnly", .{ .cycle = .available });
                try button(menu, 90, 360, 180, "Apply and refresh", .refresh);
            },
            .connection => {
                try self.row(menu, 150, .coordinator);
                try self.row(menu, 205, .certificate);
                try button(menu, 90, 280, 190, "Reconnect to room", .reconnect);
                try button(menu, 90, 335, 190, "Refresh rooms", .refresh);
            },
            .private => {
                try self.row(menu, 155, .private_id);
                try self.row(menu, 225, .code);
                try button(menu, 90, 315, 200, "Join private room", .join_private);
            },
            .player => {
                try self.row(menu, 160, .player_name);
                var model: [64]u8 = undefined;
                const catalog = @import("appearance_catalog");
                const appearance = catalog.entries[catalog.parse(engine.get("model", &model)) orelse 0];
                var label: [120]u8 = undefined;
                try button(menu, 90, 230, 340, try std.fmt.bufPrint(&label, "Appearance: {s} ({s})", .{ appearance.selection, appearance.label }), .{ .cycle = .appearance });
            },
            .lobby => {
                try button(menu, 90, 150, 200, "Ready / unready", .ready);
                try button(menu, 90, 195, 200, "Join Red", .red);
                try button(menu, 90, 240, 200, "Join Blue", .blue);
                try button(menu, 90, 285, 200, "Join Deathmatch", .free);
                try button(menu, 90, 330, 200, "Spectate", .spectator);
            },
        }
    }
    pub fn key(self: *Browser, code: i32) bool {
        const field = self.editing orelse return false;
        if (code == c.K_ESCAPE) {
            self.editing = null;
            return true;
        }
        if (code == c.K_ENTER or code == c.K_KP_ENTER) {
            engine.set(fields[@intFromEnum(field)].name, std.mem.sliceTo(&self.text, 0));
            self.editing = null;
            return true;
        }
        const length = std.mem.sliceTo(&self.text, 0).len;
        if (code == c.K_BACKSPACE and length > 0) self.text[length - 1] = 0;
        if (code & c.K_CHAR_FLAG != 0) {
            const byte = code & ~@as(i32, c.K_CHAR_FLAG);
            if (byte >= 32 and byte < 127 and length < self.text.len - 1) {
                self.text[length] = @intCast(byte);
                self.text[length + 1] = 0;
            }
        }
        return true;
    }
    pub fn activate(self: *Browser, menu: anytype, action: Action) !void {
        var buffer: [512]u8 = undefined;
        switch (action) {
            .page => |page| {
                self.page = page;
                self.editing = null;
            },
            .edit => |field| {
                _ = engine.get(fields[@intFromEnum(field)].name, &self.text);
                self.editing = field;
            },
            .select => |index| {
                var name: [32]u8 = undefined;
                const room = engine.get(try std.fmt.bufPrintZ(&name, "dk3_room{d}", .{index}), &buffer);
                const id = info.get(room, "id") orelse return;
                if (id.len != 64) return;
                self.selected = index;
                @memcpy(self.selected_id[0..64], id);
            },
            .join, .favorite => {
                const index = self.selected orelse {
                    menu.message("Select a room first.");
                    return;
                };
                var name: [32]u8 = undefined;
                const room = engine.get(try std.fmt.bufPrintZ(&name, "dk3_room{d}", .{index}), &buffer);
                if (!std.mem.eql(u8, info.get(room, "id") orelse "", self.selected_id[0..64])) {
                    self.selected = null;
                    menu.message("The room list changed. Select the room again.");
                    return;
                }
                engine.execute(try std.fmt.bufPrintZ(&buffer, "dk3_online {s} {d}\n", .{ if (action == .join) @as([]const u8, "join") else "favorite", index }));
            },
            .refresh => {
                self.selected = null;
                self.page = .rooms;
                engine.execute("dk3_online list\n");
            },
            .create => engine.execute("dk3_online create\n"),
            .join_private => engine.execute("dk3_online private\n"),
            .reconnect => engine.execute("dk3_online reconnect\n"),
            .next => self.first = @min(self.first + 6, 126),
            .previous => self.first -|= 6,
            .cycle => |item| {
                if (item == .appearance) {
                    const catalog = @import("appearance_catalog");
                    const current = catalog.parse(engine.get("model", &buffer)) orelse 0;
                    engine.set("model", catalog.entries[(current + 1) % catalog.entries.len].selection);
                    return;
                }
                const parameter: struct { name: [:0]const u8, min: i32, max: i32 } = switch (item) {
                    .mode => .{ .name = "ui_roomMode", .min = 0, .max = 2 },
                    .slots => .{ .name = "ui_roomSlots", .min = 2, .max = 32 },
                    .bots => .{ .name = "ui_roomBots", .min = 0, .max = @intFromFloat(engine.number("ui_roomSlots") - 1) },
                    .skill => .{ .name = "ui_roomSkill", .min = 1, .max = 5 },
                    .privacy => .{ .name = "ui_roomPrivate", .min = 0, .max = 1 },
                    .filter_mode => .{ .name = "ui_roomFilterMode", .min = -1, .max = 2 },
                    .favorites => .{ .name = "ui_roomFavoritesOnly", .min = 0, .max = 1 },
                    .available => .{ .name = "ui_roomAvailableOnly", .min = 0, .max = 1 },
                    .appearance => unreachable,
                };
                const value: i32 = @intFromFloat(engine.number(parameter.name));
                engine.setNumber(parameter.name, @floatFromInt(if (value >= parameter.max) parameter.min else value + 1));
            },
            .host_lan => {
                var map_buffer: [64]u8 = undefined;
                const map = engine.get("ui_roomMap", &map_buffer);
                if (!@import("../domain/snapshot.zig").validName(map)) {
                    menu.message("Enter a valid map name.");
                    return;
                }
                engine.setNumber("g_gametype", switch (@as(i32, @intFromFloat(engine.number("ui_roomMode")))) {
                    1 => c.GT_CTF,
                    2 => c.GT_DK3_DEATHTAG,
                    else => c.GT_FFA,
                });
                engine.setNumber("sv_maxclients", std.math.clamp(engine.number("ui_roomSlots"), 2, 32));
                engine.setNumber("bot_minplayers", std.math.clamp(engine.number("ui_roomBots"), 0, engine.number("sv_maxclients") - 1) + 1);
                engine.setNumber("g_spSkill", std.math.clamp(engine.number("ui_roomSkill"), 1, 5));
                engine.set("dk3_public", "0");
                engine.set("dk3_resume", "0");
                engine.set("dk3_travel_pending", "0");
                menu.close();
                engine.execute(try std.fmt.bufPrintZ(&buffer, "map {s}\n", .{map}));
            },
            .join_lan => {
                var address_buffer: [256]u8 = undefined;
                const address = engine.get("ui_lanAddress", &address_buffer);
                if (address.len == 0) return;
                for (address) |byte| if (!std.ascii.isAlphanumeric(byte) and std.mem.indexOfScalar(u8, ".:-[]", byte) == null) {
                    menu.message("Enter a hostname or IP address and port.");
                    return;
                };
                menu.close();
                engine.execute(try std.fmt.bufPrintZ(&buffer, "connect {s}\n", .{address}));
            },
            .ready, .red, .blue, .spectator, .free => {
                menu.close();
                engine.execute(switch (action) {
                    .ready => "cmd ready\n",
                    .red => "cmd team red\n",
                    .blue => "cmd team blue\n",
                    .spectator => "cmd team spectator\n",
                    .free => "cmd team free\n",
                    else => unreachable,
                });
            },
        }
    }
};
