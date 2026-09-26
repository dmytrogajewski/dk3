// SPDX-License-Identifier: GPL-2.0-or-later
//! First-person presentation owns media and animation, never authoritative ammunition or damage.
const std = @import("std");
const catalog = @import("weapon_catalog");
const data = @import("../domain/components.zig");
const animation = @import("../domain/animation.zig");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const Model = struct {
    handle: c.qhandle_t,
    metadata: []u8,
    fn load(path: []const u8) !Model {
        var name: [c.MAX_QPATH + 6]u8 = undefined;
        const bytes = try @import("../engine/files.zig").read(.client, &engine.gateway, std.heap.c_allocator, try std.fmt.bufPrintZ(&name, "{s}.anim", .{path}), 1 << 20);
        errdefer std.heap.c_allocator.free(bytes);
        const model = try @import("models.zig").register(path);
        if (model == 0) return error.MissingWeaponModel;
        return .{ .handle = model, .metadata = bytes };
    }
    fn sequence(self: Model, name: []const u8) !animation.Sequence {
        if (try animation.find(self.metadata, name)) |value| return value;
        // Single-frame effect models legitimately have no named animation.
        var header = std.mem.tokenizeAny(u8, self.metadata, " \t\r\n");
        _ = header.next();
        _ = header.next();
        if (std.mem.eql(u8, header.next() orelse "", "1")) return .{};
        var message: [192]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig: missing weapon animation {s}\n", .{name}));
        return error.MissingWeaponAnimation;
    }
};
const Media = struct { view: ?Model = null, flash: ?Model = null, flash_sprite: ?u8 = null, hum: c.sfxHandle_t = 0, flash_shader: c.qhandle_t = 0 };
pub const View = struct {
    media: [29]Media = @splat(.{}),
    state: catalog.presentation.State = .{},
    sequence: animation.Sequence = .{},
    started_ms: i64 = 0,
    looping: bool = false,
    shine: c.qhandle_t = 0,
    cloak: c.qhandle_t = 0,
    finish_ms: ?i64 = null,
    reselect_pending: bool = false,
    charge_sound_ms: i32 = 0,
    pub fn reselect(self: *View) void {
        self.reselect_pending = true;
    }
    pub fn deinit(self: *View) void {
        for (self.media) |media| {
            if (media.view) |model| std.heap.c_allocator.free(model.metadata);
            if (media.flash) |model| std.heap.c_allocator.free(model.metadata);
        }
        self.* = .{};
    }
    pub fn init(self: *View) void {
        self.deinit();
        for ([_]struct { name: [:0]const u8, value: [:0]const u8 }{
            .{ .name = "cg_drawGun", .value = "1" },
            .{ .name = "cg_shinyWeapons", .value = "1" },
        }) |option| _ = engine.gateway.call(c.CG_CVAR_REGISTER, .{ @as(?*c.vmCvar_t, null), option.name.ptr, option.value.ptr, @as(isize, c.CVAR_ARCHIVE) });
        self.shine = @intCast(engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/weapon-shine")}));
        self.cloak = @intCast(engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/cloak")}));
    }
    pub fn fire(self: *View, weapon: u5, serial: u32, now: i64) void {
        self.state.noteFire(weapon, serial, now);
    }
    pub fn draw(self: *View, loadout: data.Weapons, character: data.Character, ref: *const c.refdef_t, client: i32, now: i64, weapon_end_ms: ?i64) !void {
        if (loadout.weapon <= 0 or loadout.weapon >= self.media.len or engine.integer("cg_drawGun") == 0) return;
        const id: u5 = @intCast(loadout.weapon);
        const entry = catalog.find(id) orelse return;
        const spec = entry.spec;
        if (spec.animation.view_model.len == 0) return;
        const media = &self.media[id];
        if (media.view == null) {
            media.view = try Model.load(spec.animation.view_model);
            if (spec.muzzle) |muzzle| {
                if (muzzle.sprite) media.flash_sprite = try @import("sprites.zig").register(muzzle.model) else media.flash = try Model.load(muzzle.model);
                if (muzzle.shader) |name| media.flash_shader = @intCast(engine.gateway.call(c.CG_R_REGISTERSHADER, .{name.ptr}));
            }
            if (spec.audio.hum) |name| media.hum = try sound(name);
        }
        const attack_animation = catalog.attackAnimation(id, loadout.dk3WeaponSequence, loadout.dk3SwordExperience);
        if (self.state.update(spec, .{ .weapon = id, .state = loadout.weaponstate, .sequence = loadout.dk3WeaponSequence, .reloading = catalog.isReloading(&loadout), .attack_factor = catalog.transitions.attackFactor(character.attribute(.attack, now)), .now_ms = now, .fire_pose = attack_animation.pose, .fire_rate = attack_animation.rate, .finish_ms = weapon_end_ms })) |cue| {
            self.sequence = try media.view.?.sequence(cue.pose);
            self.sequence.fps = cue.rate;
            self.started_ms = if (cue.phase == .fire) (if (self.state.fire_weapon == id and !spec.animation.fire_loop) self.state.fire_ms else now) + spec.animation.fire_start_ms else now;
            if (cue.phase == .settle) if (weapon_end_ms) |at| {
                self.started_ms = at;
            };
            if (cue.phase == .fire) if (spec.animation.charge) |charge| {
                const frame = @min(charge.max_frame, @divTrunc(@max(0, loadout.dk3Charge), charge.frame_ms));
                self.started_ms -= @divTrunc(@as(i64, frame) * 1000, cue.rate);
            };
            if (cue.phase == .ready or cue.phase == .away) self.finish_ms = null;
            if (cue.phase == .fire and spec.animation.finish_ms > 0) self.finish_ms = self.started_ms + spec.animation.finish_ms;
            self.looping = cue.loop;
            self.state.ended_ms = self.started_ms + self.sequence.duration();
            if (engine.integer("developer") != 0) {
                var message: [192]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig view: weapon={d} phase={s} pose={s} frames={d}..{d} rate={d}\n", .{ id, @tagName(cue.phase), cue.pose, self.sequence.first, self.sequence.last, cue.rate }));
            }
            if (cue.sound) |name| _ = engine.gateway.call(c.CG_S_STARTLOCALSOUND, .{ @as(isize, try sound(name)), @as(isize, c.CHAN_WEAPON) });
        }
        if (self.reselect_pending) {
            self.reselect_pending = false;
            if (spec.animation.reselect) |pose| {
                self.sequence = try media.view.?.sequence(pose);
                self.sequence.fps = 20;
                self.started_ms = now;
                self.looping = false;
                self.state.ended_ms = now + self.sequence.duration();
                self.state.phase = .settle;
            }
        }
        if (self.finish_ms) |at| if (now >= at) {
            if (spec.audio.finish) |name| _ = engine.gateway.call(c.CG_S_STARTLOCALSOUND, .{ @as(isize, try sound(name)), @as(isize, c.CHAN_WEAPON) });
            self.finish_ms = null;
        };
        var rendered = std.mem.zeroes(c.refEntity_t);
        rendered.reType = c.RT_MODEL;
        rendered.hModel = media.view.?.handle;
        rendered.origin = ref.vieworg;
        rendered.oldorigin = rendered.origin;
        rendered.axis = ref.viewaxis;
        rendered.renderfx = c.RF_DEPTHHACK | c.RF_FIRST_PERSON | c.RF_MINLIGHT;
        rendered.shaderRGBA = @splat(255);
        var sample = self.sequence.sample(now - self.started_ms, self.looping);
        if (spec.animation.charge) |charge| {
            if (loadout.dk3AttackHeld != 0 and loadout.dk3Charge > 0) {
                var sequence = try media.view.?.sequence(spec.animation.fire);
                sequence.last = @min(sequence.last, sequence.first + charge.max_frame);
                sequence.fps = @divTrunc(1000, charge.frame_ms);
                sample = sequence.sample(loadout.dk3Charge, false);
                if (loadout.dk3Charge < self.charge_sound_ms) self.charge_sound_ms = 0;
                const threshold = @divTrunc(loadout.dk3Charge, charge.sound_ms) * charge.sound_ms;
                if (threshold > self.charge_sound_ms) {
                    _ = engine.gateway.call(c.CG_S_STARTLOCALSOUND, .{ @as(isize, try sound(charge.sound)), @as(isize, c.CHAN_WEAPON) });
                    self.charge_sound_ms = threshold;
                }
            } else self.charge_sound_ms = 0;
        }
        rendered.frame = sample.frame;
        rendered.oldframe = sample.oldframe;
        rendered.backlerp = sample.backlerp;
        if (character.invisible_until > now) {
            rendered.customShader = self.cloak;
            rendered.shaderRGBA[3] = 100;
        }
        _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&rendered});
        const shine = engine.integer("cg_shinyWeapons");
        if (shine > 0 and rendered.customShader == 0 and self.shine != 0) {
            var overlay = rendered;
            overlay.customShader = self.shine;
            overlay.shaderRGBA = .{ 200, 215, 255, if (shine >= 2) 110 else 45 };
            _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&overlay});
        }
        if (media.hum != 0) {
            const zero: v.Vec3 = @splat(0);
            _ = engine.gateway.call(c.CG_S_ADDLOOPINGSOUND, .{ @as(isize, client), &ref.vieworg, &zero, @as(isize, media.hum) });
        }
        if (spec.muzzle) |muzzle| {
            const flash_at = self.state.fire_ms + @as(i64, @intFromFloat(@as(f32, @floatFromInt(muzzle.delay_ms)) / catalog.transitions.attackFactor(character.attribute(.attack, now))));
            if (self.state.fire_weapon != id or now < flash_at or now - flash_at > 50) return;
            var flash = std.mem.zeroes(c.refEntity_t);
            flash.reType = c.RT_MODEL;
            flash.renderfx = rendered.renderfx;
            flash.hModel = if (media.flash) |model| model.handle else 0;
            flash.origin = v.add(try muzzlePoint(&rendered), v.scale(rendered.axis[0], muzzle.offset));
            flash.oldorigin = flash.origin;
            for (&flash.axis, rendered.axis) |*axis, source| axis.* = v.scale(source, muzzle.scale);
            flash.nonNormalizedAxes = c.qtrue;
            flash.frame = if (media.flash) |model| (try model.sequence(muzzle.animation)).frame(now - flash_at, false) else 0;
            flash.oldframe = flash.frame;
            flash.customShader = media.flash_shader;
            flash.shaderRGBA = .{ 255, 255, 255, muzzle.alpha };
            if (media.flash_sprite) |sprite| @import("sprites.zig").draw(sprite, 0, flash.origin, muzzle.scale, true, ref) else _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&flash});
            _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &flash.origin, engine.floatArg(muzzle.light_radius), engine.floatArg(muzzle.color[0]), engine.floatArg(muzzle.color[1]), engine.floatArg(muzzle.color[2]) });
        }
    }
};
fn sound(name: []const u8) !c.sfxHandle_t {
    return engine.registerSound(name);
}
fn muzzlePoint(parent: *const c.refEntity_t) !v.Vec3 {
    for ([_][:0]const u8{ "hr_muzzle", "fire" }) |name| {
        var tag: c.orientation_t = undefined;
        if (engine.gateway.call(c.CG_R_LERPTAG, .{ &tag, @as(isize, parent.hModel), @as(isize, parent.oldframe), @as(isize, parent.frame), engine.floatArg(1 - parent.backlerp), name.ptr }) == 0) continue;
        var point = parent.origin;
        for (parent.axis, tag.origin) |axis, offset| point = v.add(point, v.scale(axis, offset));
        return point;
    }
    return v.add(parent.origin, v.scale(parent.axis[0], 24));
}
