// SPDX-License-Identifier: GPL-2.0-or-later
//! Supplied HUD artwork and fonts, driven by replicated/predicted domain values.
const std = @import("std");
const data = @import("../domain/components.zig");
const catalog = @import("weapon_catalog");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const canvas = @import("../engine/canvas.zig");
const v = @import("../domain/vector.zig");
const draw: canvas.Canvas(.client) = .{ .gateway = &engine.gateway };
pub const Hud = struct {
    font: canvas.Font = undefined,
    numbers: canvas.Font = undefined,
    red_numbers: canvas.Font = undefined,
    plates: [3]c.qhandle_t = @splat(0),
    faces: [8]c.qhandle_t = @splat(0),
    icons: [4]c.qhandle_t = @splat(0),
    skill: c.qhandle_t = 0,
    window: c.qhandle_t = 0,
    selection: c.qhandle_t = 0,
    crosshair: c.qhandle_t = 0,
    white: c.qhandle_t = 0,
    models: [29]c.qhandle_t = @splat(0),
    inventory_open: bool = false,
    item_choice: i32 = 0,
    attribute_choice: u3 = 0,
    pub fn command(self: *Hud, name: []const u8) bool {
        if (std.mem.eql(u8, name, "inventory")) {
            self.inventory_open = !self.inventory_open;
        } else if (std.mem.eql(u8, name, "invnext") or std.mem.eql(u8, name, "invprev")) {
            self.item_choice += if (std.mem.eql(u8, name, "invnext")) @as(i32, 1) else -1;
            self.inventory_open = true;
        } else if (std.mem.eql(u8, name, "attribute_next")) {
            self.attribute_choice = (self.attribute_choice + 1) % 5;
            self.inventory_open = true;
        } else if (std.mem.eql(u8, name, "attribute_increase")) {
            const names = [_][*:0]const u8{ "attribute power", "attribute attack", "attribute speed", "attribute acro", "attribute vita" };
            _ = engine.gateway.call(c.CG_SENDCLIENTCOMMAND, .{names[self.attribute_choice]});
            self.inventory_open = true;
        } else return false;
        return true;
    }
    pub fn init(self: *Hud) !void {
        self.* = .{};
        self.font = try draw.font("statbar_font");
        self.numbers = try draw.font("mainnums");
        self.red_numbers = try draw.font("mainnumsred");
        for ([_][]const u8{ "bottom_1", "bottom_3", "bottom_4" }, &self.plates) |name, *handle| handle.* = try picture(name);
        for (&self.faces, 0..) |*handle, i| {
            var name: [24]u8 = undefined;
            handle.* = try picture(try std.fmt.bufPrint(&name, "bottom_2_0{c}", .{@as(u8, 'a') + @as(u8, @intCast(i))}));
        }
        for ([_][]const u8{ "armoricon", "healthicon", "ammoicon", "explevicon" }, &self.icons) |name, *handle| handle.* = try picture(name);
        self.skill = try picture("skill_window");
        self.window = try picture("weapn_win");
        self.selection = try picture("selec_weapn");
        self.crosshair = draw.shader("pics/crosshair/ch_center.tga");
        self.white = draw.shader("white");
        _ = engine.gateway.call(c.CG_CVAR_REGISTER, .{ @as(?*c.vmCvar_t, null), @as([*:0]const u8, "cg_hudScale"), @as([*:0]const u8, "1"), @as(isize, c.CVAR_ARCHIVE) });
    }
    pub fn render(self: *Hud, display: c.glconfig_t, health: data.Health, character: data.Character, keys: data.Keys, loadout: data.Weapons, table: *const @import("../domain/weapons.zig").Table, selected: i32, now: i64) !void {
        const width: f32 = @floatFromInt(display.vidWidth);
        const height: f32 = @floatFromInt(display.vidHeight);
        const scale = @min(width / 640, height / 480 * std.math.clamp(engine.number("cg_hudScale", 1), 0.75, 1.5));
        const center = width * 0.5;
        const white = canvas.white;
        const translucent: canvas.Color = .{ 1, 1, 1, 0.7 };
        for (self.plates, [_]f32{ -222, 34, 162 }) |handle, offset| draw.rect(center + offset * scale, height - 128 * scale, 128 * scale, 128 * scale, handle, translucent);
        const face: usize = if (health.current <= 0) 7 else @intCast(std.math.clamp(@divTrunc(100 - health.current, 15), 0, 6));
        draw.rect(center - 94 * scale, height - 128 * scale, 128 * scale, 128 * scale, self.faces[face], translucent);
        const ammo = if (loadout.weapon > 0 and loadout.weapon < table.entries.len and table.entries[@intCast(loadout.weapon)].ammoCost > 0) loadout.ammo[@intCast(loadout.weapon)] else -1;
        const values = [_]i32{ health.armor, @max(0, health.current), ammo, character.level - 1 };
        const labels = [_][]const u8{ "ARMOR", "HEALTH", "AMMO", "LEVEL" };
        const icon_x = [_]f32{ -208, -118, 34, 132 };
        const icon_y = [_]f32{ -64, -67, -66, -64 };
        const label_x = [_]f32{ -186, -104, 62, 148 };
        const value_x = [_]f32{ -162, -71, 82, 172 };
        for (values, 0..) |value, i| {
            draw.rect(center + icon_x[i] * scale, height + icon_y[i] * scale, 64 * scale, 64 * scale, self.icons[i], translucent);
            draw.text(self.font, center + label_x[i] * scale, height - 22 * scale, scale, labels[i], white);
            const low: i32 = if (i < 2) 25 else if (i == 2) 5 else -1;
            const digits = if (value >= 0 and value <= low) self.red_numbers else self.numbers;
            var buffer: [24]u8 = undefined;
            const text = if (value < 0) "--" else try std.fmt.bufPrint(&buffer, "{d}", .{value});
            const x = center + value_x[i] * scale - digits.metrics.width(text, scale) + digits.metrics.width("0", scale);
            draw.text(digits, x, height - 35 * scale, scale, text, white);
        }
        for ([_][]const u8{ "POWER", "ATTACK", "SPEED", "ACRO", "VITALITY" }, 0..) |label, i| {
            const y = height - (268 - @as(f32, @floatFromInt(i)) * 36) * scale;
            draw.text(self.font, 0, y - 6 * scale, scale, label, if (character.points > 0 and i == self.attribute_choice) .{ 1, 0.8, 0.25, 1 } else white);
            draw.rect(0, y + 9 * scale, 64 * scale, 32 * scale, self.skill, translucent);
            const filled = character.attribute(@enumFromInt(i), now);
            for (0..5) |n| draw.rect((9 + @as(f32, @floatFromInt(n)) * 8) * scale, y + 16 * scale, 6 * scale, 8 * scale, self.white, if (n < filled) .{ 0.45, 0.95, 0.2, 1 } else .{ 0.10, 0.16, 0.09, 0.85 });
        }
        if (character.points > 0) {
            var buffer: [64]u8 = undefined;
            const text = try std.fmt.bufPrint(&buffer, "+{d} skill points", .{character.points});
            draw.text(self.font, center - self.font.metrics.width(text, scale * 0.7) * 0.5, height - 145 * scale, scale * 0.7, text, .{ 1, 0.8, 0.25, 1 });
        }
        if (health.current > 0) draw.rect(center - 12 * scale, height * 0.5 - 12 * scale, 24 * scale, 24 * scale, self.crosshair, white);
        var owned: [28]u5 = undefined;
        var count: usize = 0;
        var active: usize = 0;
        for (catalog.entries) |entry| {
            if (!entry.spec.auto_select or @as(u32, @bitCast(loadout.dk3Inventory)) & (@as(u32, 1) << entry.id) == 0) continue;
            if (entry.id == selected) active = count;
            owned[count] = entry.id;
            count += 1;
        }
        const first = active / 6 * 6;
        const x = width - 88 * scale;
        for (0..6) |row| {
            const index = first + row;
            const y = (16 + @as(f32, @floatFromInt(row)) * 61) * scale;
            draw.rect(x, y, 128 * scale, 128 * scale, self.window, translucent);
            if (index >= count) continue;
            const id = owned[index];
            const spec = catalog.find(id).?.spec;
            if (self.models[id] == 0) self.models[id] = try @import("models.zig").register(if (spec.inventory_view_model) spec.animation.view_model else spec.world_model orelse "");
            model(self.models[id], x + 8 * scale, y + 10 * scale, 73 * scale, 39 * scale, now);
            if (index == active) draw.rect(x, y, 128 * scale, 128 * scale, self.selection, translucent);
            var buffer: [24]u8 = undefined;
            const text = if (table.entries[id].ammoCost == 0) "--" else try std.fmt.bufPrint(&buffer, "{d}", .{loadout.ammo[id]});
            draw.text(self.font, x + 48 * scale, y + 50 * scale, scale * 0.52, text, white);
        }
        if (self.inventory_open) {
            var items: [32]u5 = undefined;
            var item_count: usize = 0;
            for (0..32) |index| if (keys.mask & (@as(u32, 1) << @intCast(index)) != 0) {
                items[item_count] = @intCast(index);
                item_count += 1;
            };
            self.item_choice = if (item_count > 0) @mod(self.item_choice, @as(i32, @intCast(item_count))) else 0;
            const panel_x = center - 180 * scale;
            const panel_y = 80 * scale;
            draw.rect(panel_x - 12 * scale, panel_y - 8 * scale, 360 * scale, 155 * scale, self.white, .{ 0, 0, 0, 0.7 });
            var buffer: [120]u8 = undefined;
            draw.text(self.font, panel_x, panel_y, scale * 0.6, try std.fmt.bufPrint(&buffer, "SAVE GEMS: {d}   EXPERIENCE: {d}", .{ character.save_gems, character.experience }), white);
            const page: usize = @as(usize, @intCast(self.item_choice)) / 3 * 3;
            for (0..3) |row| {
                const index = page + row;
                if (index >= item_count) break;
                draw.text(self.font, panel_x, panel_y + (30 + @as(f32, @floatFromInt(row)) * 26) * scale, scale * 0.6, @import("item_catalog").keys[items[index]].value, if (index == self.item_choice) .{ 1, 0.8, 0.25, 1 } else white);
            }
            if (item_count == 0) draw.text(self.font, panel_x, panel_y + 35 * scale, scale * 0.6, "No campaign items", white);
            if (keys.quest & 1 != 0) draw.text(self.font, panel_x, panel_y + 112 * scale, scale * 0.6, "Assembled bomb", white);
        }
    }
};
fn picture(name: []const u8) !c.qhandle_t {
    var path: [64]u8 = undefined;
    return draw.shader(try std.fmt.bufPrintZ(&path, "pics/statusbar/{s}.tga", .{name}));
}
fn model(handle: c.qhandle_t, x: f32, y: f32, width: f32, height: f32, now: i64) void {
    if (handle == 0) return;
    var mins: v.Vec3 = undefined;
    var maxs: v.Vec3 = undefined;
    _ = engine.gateway.call(c.CG_R_MODELBOUNDS, .{ @as(isize, handle), &mins, &maxs });
    const center = v.scale(v.add(mins, maxs), 0.5);
    const radius = @max(1, v.length(v.subtract(maxs, mins)) * 0.5);
    var view = std.mem.zeroes(c.refdef_t);
    view.x = @intFromFloat(x);
    view.y = @intFromFloat(y);
    view.width = @intFromFloat(width);
    view.height = @intFromFloat(height);
    view.fov_y = 30;
    view.fov_x = std.math.atan(@tan(15.0 * std.math.pi / 180.0) * width / height) * 360 / std.math.pi;
    view.viewaxis = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
    view.rdflags = c.RDF_NOWORLDMODEL;
    view.time = @intCast(now);
    var entity = std.mem.zeroes(c.refEntity_t);
    entity.hModel = handle;
    entity.reType = c.RT_MODEL;
    entity.renderfx = c.RF_NOSHADOW | c.RF_MINLIGHT;
    const orientation = v.basis(.{ 0, 35, 0 });
    entity.axis = .{ orientation.forward, v.scale(orientation.right, -1), .{ 0, 0, 1 } };
    for (entity.axis, center) |axis, offset| entity.origin = v.add(entity.origin, v.scale(axis, -offset));
    entity.origin[0] += radius / @sin(15.0 * std.math.pi / 180.0);
    entity.shaderRGBA = @splat(255);
    _ = engine.gateway.call(c.CG_R_CLEARSCENE, .{});
    _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&entity});
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &view.vieworg, engine.floatArg(radius * 12), engine.floatArg(1), engine.floatArg(1), engine.floatArg(1) });
    _ = engine.gateway.call(c.CG_R_RENDERSCENE, .{&view});
}
