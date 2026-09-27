// SPDX-License-Identifier: GPL-2.0-or-later
//! Native screen composition and input routing. Widgets hold typed actions, not command text.
const std = @import("std");
const engine = @import("../engine/ui.zig");
const c = engine.c;
const domain = @import("../domain/menu.zig");
const settings = @import("settings.zig");
const controls = @import("controls.zig");
const art_module = @import("art.zig");
const Action = union(enum) { multiplayer: @import("multiplayer.zig").Action, difficulty: usize, setting: usize, bind: usize, save_pick: usize, save_commit, invert_mouse, video_apply, input_apply, config_save, config_load, back, quit, options };
const Widget = struct { rect: domain.Rect, action: Action };
pub const Menu = struct {
    active: bool = false,
    music: bool = false,
    page: usize = 0,
    navigation: domain.Selection = .{ .selected = 0 },
    panel: domain.Selection = .{ .selected = 0 },
    navigation_focus: bool = false,
    keyboard: bool = false,
    cursor_x: f32 = 320,
    cursor_y: f32 = 240,
    layout: domain.Layout = domain.Layout.fit(640, 480),
    art: art_module.Art = .{},
    capture: controls.Capture = .{},
    widgets: [64]Widget = undefined,
    count: usize = 0,
    control_page: usize = 0,
    feedback: [256]u8 = @splat(0),
    saves: @import("saves.zig").Browser = .{},
    multiplayer: @import("multiplayer.zig").Browser = .{},
    pub fn init(self: *Menu) !void {
        self.* = .{};
        try self.art.init();
        settings.init();
        self.multiplayer.init();
        self.resize();
    }
    fn resize(self: *Menu) void {
        var display: c.glconfig_t = undefined;
        _ = engine.gateway.call(c.UI_GETGLCONFIG, .{&display});
        self.layout = domain.Layout.fit(@floatFromInt(display.vidWidth), @floatFromInt(display.vidHeight));
    }
    pub fn close(self: *Menu) void {
        if (self.active) engine.sound("sounds/menus/exit menu_001.wav");
        self.active = false;
        self.capture = .{};
        engine.catchInput(false);
        if (self.music) {
            _ = engine.gateway.call(c.UI_S_STOPBACKGROUNDTRACK, .{});
            self.music = false;
        }
    }
    pub fn open(self: *Menu) void {
        if (!self.active) engine.sound("sounds/menus/enter menu_001.wav");
        self.active = true;
        self.page = 0;
        self.navigation = .{ .selected = if (engine.inGame()) 12 else 0 };
        self.navigation_focus = engine.inGame();
        self.panel = .{ .selected = 1 };
        self.capture = .{};
        self.message("");
        self.count = 0;
        engine.catchInput(true);
    }
    pub fn message(self: *Menu, value: []const u8) void {
        @memset(&self.feedback, 0);
        const len = @min(value.len, self.feedback.len - 1);
        @memcpy(self.feedback[0..len], value[0..len]);
    }
    fn selectPage(self: *Menu, page: usize) void {
        if (!engine.inGame() and (page == 3 or page == 12)) return;
        if (page == 12) {
            self.close();
            return;
        }
        if (page != self.page) engine.sound("sounds/menus/600ms rotate descend_001.wav");
        self.page = page;
        self.navigation.selected = page;
        self.panel = .{ .selected = 0 };
        self.navigation_focus = false;
        self.capture = .{};
        self.count = 0;
        self.message("");
        if (page == 2 or page == 3) self.saves.refresh(page == 3) catch self.message("Could not read save slots.");
    }
    fn add(self: *Menu, rect: domain.Rect, label: []const u8, action: Action) void {
        std.debug.assert(self.count < self.widgets.len);
        const selected = !self.navigation_focus and ((self.keyboard and self.panel.selected == self.count) or (!self.keyboard and self.panel.hovered == self.count));
        if (selected) self.art.rect(self.layout, rect.x - 4, rect.y - 2, rect.width + 8, rect.height + 4, self.art.white, .{ 0.3, 0.03, 0.01, 0.5 });
        self.art.text(self.layout, rect.x, rect.y, label, selected);
        self.widgets[self.count] = .{ .rect = rect, .action = action };
        self.count += 1;
    }
    pub fn button(self: *Menu, x: f32, y: f32, width: f32, label: []const u8, action: Action) void {
        self.add(.{ .x = x, .y = y, .width = width, .height = 22 }, label, action);
    }
    fn group(self: *Menu, value: settings.Group) !void {
        var row: usize = 0;
        for (settings.entries, 0..) |setting, i| if (setting.group == value) {
            var buffer: [160]u8 = undefined;
            var number: [48]u8 = undefined;
            const text = try std.fmt.bufPrint(&buffer, "{s}: {s}", .{ setting.label, try setting.labelValue(&number) });
            self.button(92, 138 + @as(f32, @floatFromInt(row)) * 48, 330, text, .{ .setting = i });
            row += 1;
        };
        switch (value) {
            .video => self.button(110, 380, 300, "Apply video changes", .video_apply),
            .mouse => self.button(92, 234, 300, if (engine.number("m_pitch") < 0) "Invert mouse: On" else "Invert mouse: Off", .invert_mouse),
            .joystick => self.button(110, 380, 300, "Apply input changes", .input_apply),
            else => {},
        }
    }
    fn panelDraw(self: *Menu) !void {
        switch (self.page) {
            0 => {
                self.art.text(self.layout, 190, 112, "Select Difficulty", true);
                for ([_][]const u8{ "Ronin", "Samurai", "Shogun" }, 0..) |name, i| {
                    const x = 88 + @as(f32, @floatFromInt(i)) * 130;
                    self.art.rect(self.layout, x, 80, 128, 256, self.art.figures[i], .{ 1, 1, 1, 0.9 });
                    self.button(x + 12, 340, 106, name, .{ .difficulty = i });
                }
                self.button(330, 390, 125, "Extra Options", .options);
            },
            1 => try self.multiplayer.render(self),
            2, 3 => {
                const writing = self.page == 3;
                self.art.text(self.layout, 90, 110, if (writing) "Save Game" else "Load Game", true);
                for (self.saves.first..@min(self.saves.first + 8, self.saves.count)) |i| {
                    var buffer: [64]u8 = undefined;
                    const label = try std.fmt.bufPrint(&buffer, "{s}{s}", .{ if (self.saves.choice.selected == i) "> " else "  ", self.saves.name(i) });
                    self.button(90, 140 + @as(f32, @floatFromInt(i - self.saves.first)) * 27, 180, label, .{ .save_pick = i });
                }
                if (self.saves.count == 0) self.art.text(self.layout, 90, 150, "No saved games.", false);
                if (self.saves.selected()) |slot| {
                    self.art.text(self.layout, 285, 145, "Selected:", false);
                    self.art.text(self.layout, 285, 177, slot, true);
                }
                self.button(300, 335, 120, if (writing) "Save game" else "Load game", .save_commit);
                self.art.text(self.layout, 90, 388, "Page Up / Down: more slots", false);
            },
            4 => try self.group(.sound),
            5 => try self.group(.video),
            6 => try self.group(.mouse),
            7 => {
                const first = self.control_page * 8;
                for (controls.entries[first..@min(first + 8, controls.entries.len)], first..) |entry, i| {
                    var buffer: [180]u8 = undefined;
                    var key_name: [64]u8 = undefined;
                    const name = if (controls.bound(i)) |code| engine.keyName(code, &key_name) else "Unbound";
                    self.button(88, 135 + @as(f32, @floatFromInt(i - first)) * 28, 340, try std.fmt.bufPrint(&buffer, "{s}: {s}", .{ entry.label, name }), .{ .bind = i });
                }
                self.art.text(self.layout, 88, 386, "Page Up / Down: more controls", false);
            },
            8 => try self.group(.joystick),
            9 => try self.group(.options),
            10 => {
                self.button(110, 160, 300, "Save configuration", .config_save);
                self.button(110, 210, 300, "Load configuration", .config_load);
            },
            11 => {
                self.art.text(self.layout, 90, 140, "Daikatana - independent dk3 runtime", true);
                self.art.text(self.layout, 90, 190, "Engine: ioquake3 / id Software", false);
                self.art.text(self.layout, 90, 220, "Original game: Ion Storm", false);
                self.art.text(self.layout, 90, 270, "See project notices for contributors", false);
                self.art.text(self.layout, 90, 300, "and component licenses.", false);
            },
            13 => {
                self.art.text(self.layout, 150, 150, "Quit Daikatana?", true);
                self.button(150, 210, 90, "Quit", .quit);
                self.button(280, 210, 90, "Cancel", .back);
            },
            else => {},
        }
    }
    pub fn render(self: *Menu, now: i32) !void {
        if (!self.active) return;
        self.resize();
        if (!self.music and engine.client().connState == c.CA_DISCONNECTED) {
            _ = engine.gateway.call(c.UI_S_STARTBACKGROUNDTRACK, .{ @as([*:0]const u8, "music/menu_01.mp3.ogg"), @as([*:0]const u8, "music/menu_02.mp3.ogg") });
            self.music = true;
        }
        self.art.render(self.layout, now, self.page, if (self.keyboard and self.navigation_focus) self.navigation.selected else self.navigation.hovered, engine.inGame());
        self.count = 0;
        try self.panelDraw();
        if (self.capture.action) |action| {
            self.art.rect(self.layout, 76, 350, 370, 77, self.art.white, .{ 0, 0, 0, 0.9 });
            var buffer: [220]u8 = undefined;
            if (self.capture.conflict) |key_code| {
                var name: [64]u8 = undefined;
                var prior: [128]u8 = undefined;
                self.art.text(self.layout, 84, 357, try std.fmt.bufPrint(&buffer, "{s} is bound to {s}", .{ engine.keyName(key_code, &name), engine.binding(key_code, &prior) }), true);
                self.art.text(self.layout, 84, 390, "Enter: replace    Escape: cancel", false);
            } else self.art.text(self.layout, 84, 365, try std.fmt.bufPrint(&buffer, "Press a key for {s}", .{controls.entries[action].label}), true);
        }
        self.art.text(self.layout, 82, 435, std.mem.sliceTo(&self.feedback, 0), true);
        self.art.rect(self.layout, self.cursor_x, self.cursor_y, 32, 32, self.art.cursors[@as(usize, @intCast(@max(0, now))) / 45 % 9], @splat(1));
        self.hover();
    }
    fn hover(self: *Menu) void {
        self.panel.hovered = null;
        self.navigation.hovered = null;
        for (self.widgets[0..self.count], 0..) |widget, i| if (widget.rect.contains(self.cursor_x, self.cursor_y)) {
            self.panel.hovered = i;
            break;
        };
        if (self.panel.hovered == null and self.cursor_x >= 440 and self.cursor_x < 640 and self.cursor_y >= 58 and self.cursor_y < 449) self.navigation.hovered = @intFromFloat((self.cursor_y - 58) / (391.0 / 14.0));
    }
    pub fn mouse(self: *Menu, dx: i32, dy: i32) void {
        if (!self.active or (dx == 0 and dy == 0)) return;
        self.keyboard = false;
        self.cursor_x = std.math.clamp(self.cursor_x + @as(f32, @floatFromInt(dx)) / self.layout.scale, 0, 639);
        self.cursor_y = std.math.clamp(self.cursor_y + @as(f32, @floatFromInt(dy)) / self.layout.scale, 0, 479);
        self.hover();
    }
    pub fn key(self: *Menu, code: i32, down: bool) !void {
        if (!self.active or !down) return;
        if (self.page == 1 and self.multiplayer.key(code)) return;
        if (self.capture.key(code)) return;
        if (code == c.K_ESCAPE or code == c.K_MOUSE2) {
            if (engine.inGame()) self.close() else self.selectPage(0);
            return;
        }
        if (code == c.K_MOUSE1) {
            self.keyboard = false;
            self.hover();
            if (self.navigation.click()) self.selectPage(self.navigation.selected.?) else if (self.panel.click()) {
                self.navigation_focus = false;
                try self.activate(self.widgets[self.panel.selected.?].action, 1);
            }
            return;
        }
        self.keyboard = true;
        if (code == c.K_TAB) {
            self.navigation_focus = !self.navigation_focus;
            return;
        }
        if ((self.page == 2 or self.page == 3) and (code == c.K_PGDN or code == c.K_PGUP)) {
            self.saves.page(if (code == c.K_PGDN) 1 else -1);
            self.panel.selected = 0;
            return;
        }
        if (self.page == 7 and (code == c.K_PGDN or code == c.K_PGUP)) {
            const pages = (controls.entries.len + 7) / 8;
            self.control_page = if (code == c.K_PGDN) (self.control_page + 1) % pages else (self.control_page + pages - 1) % pages;
            self.panel.selected = 0;
            return;
        }
        if (code == c.K_UPARROW or code == c.K_DOWNARROW or code == c.K_MWHEELUP or code == c.K_MWHEELDOWN) {
            const direction: i32 = if (code == c.K_UPARROW or code == c.K_MWHEELUP) -1 else 1;
            if (self.navigation_focus) self.navigation.move(art_module.plates.len, direction) else self.panel.move(self.count, direction);
            return;
        }
        if (code == c.K_ENTER or code == c.K_KP_ENTER or code == c.K_SPACE or code == c.K_LEFTARROW or code == c.K_RIGHTARROW) {
            if (self.navigation_focus) {
                if (self.navigation.selected) |page| self.selectPage(page);
            } else if (self.panel.selected) |index| if (index < self.count) {
                const action = self.widgets[index].action;
                if ((code == c.K_LEFTARROW or code == c.K_RIGHTARROW) and action != .setting) return;
                try self.activate(action, if (code == c.K_LEFTARROW) -1 else 1);
            };
        }
    }
    fn activate(self: *Menu, action: Action, direction: i32) !void {
        engine.sound("sounds/menus/button_003.wav");
        switch (action) {
            .multiplayer => |choice| try self.multiplayer.activate(self, choice),
            .difficulty => |skill| {
                engine.setNumber("g_spSkill", @floatFromInt(1 + skill * 2));
                engine.set("g_gametype", "2");
                engine.set("dk3_loadRequest", "");
                engine.set("dk3_resume", "0");
                self.close();
                engine.set("dk3_cinematics", "1");
                engine.set("dk3_travel_pending", "0");
                engine.execute("map intro\n");
            },
            .setting => |index| settings.entries[index].change(direction),
            .bind => |index| {
                self.capture = .{ .action = index };
            },
            .save_pick => |index| self.saves.choice.selected = index,
            .save_commit => {
                const slot = self.saves.selected() orelse {
                    self.message("Select a save slot first.");
                    return;
                };
                if (self.page == 2) self.saves.validate() catch |err| {
                    var message_buffer: [192]u8 = undefined;
                    self.message(try std.fmt.bufPrint(&message_buffer, "Cannot load save: {s}", .{@errorName(err)}));
                    return;
                };
                var command: [96]u8 = undefined;
                const verb = if (self.page == 3) "save" else if (engine.inGame()) "load" else "dk3_loadmenu";
                const text = try std.fmt.bufPrintZ(&command, "{s} {s}\n", .{ verb, slot });
                self.close();
                engine.execute(text);
            },
            .invert_mouse => engine.setNumber("m_pitch", if (engine.number("m_pitch") < 0) 0.022 else -0.022),
            .video_apply => {
                self.close();
                engine.execute("vid_restart\n");
            },
            .input_apply => {
                self.close();
                engine.execute("in_restart\n");
            },
            .config_save => {
                engine.execute("writeconfig dk3-user.cfg\n");
                self.message("Configuration saved.");
            },
            .config_load => {
                engine.execute("exec dk3-user.cfg\n");
                self.message("Configuration loaded.");
            },
            .options => self.selectPage(9),
            .back => self.selectPage(0),
            .quit => engine.execute("quit\n"),
        }
    }
    pub fn connect(self: *Menu) void {
        self.resize();
        self.art.rect(self.layout, 0, 0, 640, 480, self.art.white, .{ 0, 0, 0, 1 });
        self.art.text(self.layout, 190, 190, "Loading Daikatana", true);
        const client = engine.client();
        self.art.text(self.layout, 90, 230, std.mem.sliceTo(&client.servername, 0), false);
        self.art.text(self.layout, 90, 270, std.mem.sliceTo(&client.messageString, 0), false);
    }
};
