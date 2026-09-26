// SPDX-License-Identifier: GPL-2.0-or-later
//! Native objective ownership and transitions. Engine entities expose geometry only.
const std = @import("std");
const c = @import("../weapons/abi.zig").c;
const v = @import("../weapons/vector.zig");
const Entity = c.gentity_t;
const State = enum { home, carried, dropped, planted, resetting };
const Objective = struct {
    entity: c_uint = 0,
    carrier: c_uint = 0,
    state: State = .home,
    home: v.Vec = v.zero,
    angles: v.Vec = v.zero,
    deadline: c_int = 0,
    pickup_after: c_int = 0,
    next_beep: c_int = 0,
    next_heartbeat: c_int = 0,
    warned: bool = false,

    fn clearCarrier(self: *Objective) void {
        const carrier = c.DK_FindEntity(self.carrier);
        if (carrier != null and carrier[0].client != null) {
            carrier[0].client[0].ps.dk3Objective = 0;
            carrier[0].client[0].ps.dk3ObjectiveUntil = 0;
        }
        self.carrier = 0;
    }
    fn place(self: *Objective, origin: v.Vec, visible: bool, touchable: bool) void {
        const entity = c.DK_FindEntity(self.entity);
        if (entity == null) return;
        const carrier = c.DK_FindEntity(self.carrier);
        entity[0].s.dk3Carrier = if (carrier != null and carrier[0].client != null) carrier[0].s.number + 1 else 0;
        var position = origin;
        c.G_SetOrigin(entity, &position);
        entity[0].r.contents = if (touchable) c.CONTENTS_TRIGGER else 0;
        entity[0].r.svFlags = if (visible) 0 else c.SVF_NOCLIENT;
        c.trap_LinkEntity(entity);
    }
    fn reset(self: *Objective) void {
        self.clearCarrier();
        self.state = .home;
        self.deadline = 0;
        self.pickup_after = 0;
        self.next_beep = 0;
        self.next_heartbeat = 0;
        self.warned = false;
        self.place(self.home, true, true);
        status();
    }
    fn explode(self: *Objective) void {
        const entity = c.DK_FindEntity(self.entity);
        if (entity == null) return;
        self.clearCarrier();
        self.state = .resetting;
        self.deadline = now() + 10000;
        self.place(entity[0].r.currentOrigin, false, false);
        const effect = c.G_TempEntity(entity[0].r.currentOrigin[0..].ptr, c.EV_DK3_BLAST);
        effect[0].r.svFlags |= c.SVF_BROADCAST;
        sound(effect, "sounds/global/a_ames.wav");
        c.G_LogPrintf("DK3Objective: %d explode\n", entity[0].s.dk3Team);
        for (0..@intCast(c.level.maxclients)) |i| {
            const victim = &c.g_entities[i];
            if (player(victim) and v.distance(victim.r.currentOrigin, entity[0].r.currentOrigin) < 400)
                c.G_Damage(victim, entity, victim, null, entity[0].r.currentOrigin[0..].ptr, 1000, c.DAMAGE_NO_PROTECTION | c.DAMAGE_NO_ARMOR, c.MOD_GRENADE_SPLASH);
        }
        status();
    }
};
var objectives: [2]Objective = .{ .{}, .{} };
fn now() c_int {
    return c.level.time;
}
fn ctf() bool {
    return c.g_gametype.integer == c.GT_CTF;
}
fn active() bool {
    return ctf() or c.g_gametype.integer == c.GT_DK3_DEATHTAG;
}
fn index(team: c_int) usize {
    return @intCast(team - c.TEAM_RED);
}
fn player(entity: [*c]Entity) bool {
    return entity != null and entity[0].inuse != 0 and entity[0].client != null and
        entity[0].client[0].pers.connected == c.CON_CONNECTED and entity[0].health > 0 and
        (entity[0].client[0].sess.sessionTeam == c.TEAM_RED or entity[0].client[0].sess.sessionTeam == c.TEAM_BLUE);
}
fn status() void {
    var text: [3]u8 = .{ 0, 0, 0 };
    for (objectives, 0..) |objective, i| text[i] = switch (objective.state) {
        .home => '0',
        .carried => '1',
        else => '2',
    };
    c.trap_SetConfigstring(c.CS_FLAGSTATUS, &text);
}
fn sound(entity: [*c]Entity, name: [*:0]const u8) void {
    c.G_AddEvent(entity, c.EV_GENERAL_SOUND, c.G_SoundIndex(@constCast(name)));
}
fn find(previous: [*c]Entity, name: [*:0]const u8) [*c]Entity {
    return c.G_Find(previous, @offsetOf(Entity, "classname"), @constCast(name));
}
fn teamStart(team: c_int) [*:0]const u8 {
    return if (team == c.TEAM_RED) "info_player_team1" else "info_player_team2";
}
fn touch(entity: [*c]Entity, who: [*c]Entity, _: [*c]c.trace_t) callconv(.c) void {
    const team = entity[0].s.dk3Team;
    if (!player(who) or team < c.TEAM_RED or team > c.TEAM_BLUE or c.level.intermissiontime != 0 or c.level.warmupTime != 0) return;
    const objective = &objectives[index(team)];
    if ((objective.state != .home and objective.state != .dropped) or now() < objective.pickup_after) return;
    const own = who[0].client[0].sess.sessionTeam == team;
    if (!ctf()) {
        if (!own) {
            if (objective.state == .dropped) objective.explode();
            return;
        }
    } else if (own) {
        if (objective.state == .dropped) {
            objective.reset();
            c.AddScore(who, who[0].r.currentOrigin[0..].ptr, 1);
            c.G_LogPrintf("DK3Objective: %d return %d\n", team, who[0].s.number);
            c.trap_SendServerCommand(-1, c.va("print \"%s flag returned.\n\"", c.TeamName(@intCast(team))));
        }
        return;
    }
    if (who[0].client[0].ps.dk3Objective != 0) return;
    if (!ctf() and objective.state == .home) objective.deadline = now() + 90000;
    if (ctf()) objective.deadline = 0;
    objective.state = .carried;
    objective.carrier = who[0].dk.id;
    who[0].client[0].ps.dk3Objective = @intCast(index(team) + 1);
    who[0].client[0].ps.dk3ObjectiveUntil = objective.deadline;
    objective.place(who[0].r.currentOrigin, true, false);
    sound(who, "sounds/global/a_hpick.wav");
    c.G_LogPrintf("DK3Objective: %d pickup %d\n", team, who[0].s.number);
    c.trap_SendServerCommand(-1, c.va("print \"%s objective taken.\n\"", c.TeamName(@intCast(team))));
    status();
}
export fn DK_DropObjective(who: [*c]Entity) callconv(.c) void {
    if (who == null or who[0].client == null) return;
    const held = who[0].client[0].ps.dk3Objective;
    if (held < 1 or held > 2) return;
    const objective = &objectives[@intCast(held - 1)];
    if (objective.carrier != who[0].dk.id) return;
    const entity = c.DK_FindEntity(objective.entity);
    objective.clearCarrier();
    if (entity == null) return;
    objective.state = .dropped;
    if (ctf()) objective.deadline = now() + 60000;
    objective.pickup_after = now() + 750;
    c.G_LogPrintf("DK3Objective: %d drop %d\n", entity[0].s.dk3Team, who[0].s.number);
    var bottom = who[0].r.currentOrigin;
    bottom[2] -= 512;
    var trace: c.trace_t = undefined;
    c.trap_Trace(&trace, who[0].r.currentOrigin[0..].ptr, entity[0].r.mins[0..].ptr, entity[0].r.maxs[0..].ptr, &bottom, who[0].s.number, c.MASK_SOLID);
    objective.place(if (trace.startsolid != 0) who[0].r.currentOrigin else trace.endpos, true, true);
    if ((@as(u32, @bitCast(c.trap_PointContents(entity[0].r.currentOrigin[0..].ptr, entity[0].s.number))) & (@as(u32, c.CONTENTS_LAVA | c.CONTENTS_SLIME) | (@as(u32, 1) << 31))) != 0) {
        if (ctf()) objective.reset() else objective.explode();
    }
    status();
}
fn capture(zone: [*c]Entity, who: [*c]Entity, _: [*c]c.trace_t) callconv(.c) void {
    if (!player(who) or c.level.warmupTime != 0 or c.level.intermissiontime != 0) return;
    const held = who[0].client[0].ps.dk3Objective;
    if (held < 1 or held > 2) return;
    const team = who[0].client[0].sess.sessionTeam;
    if ((zone[0].spawnflags & 3 == 1 and team != c.TEAM_RED) or (zone[0].spawnflags & 3 == 2 and team != c.TEAM_BLUE)) return;
    const objective = &objectives[@intCast(held - 1)];
    if (objective.state != .carried or objective.carrier != who[0].dk.id) return;
    if (ctf() and objectives[index(@intCast(team))].state != .home) return;
    objective.clearCarrier();
    const points: c_int = @max(1, zone[0].count);
    c.AddTeamScore(who[0].r.currentOrigin[0..].ptr, @intCast(team), points);
    c.AddScore(who, who[0].r.currentOrigin[0..].ptr, points * 5);
    if (ctf()) {
        var home = objectives[index(@intCast(team))].home;
        for (0..@intCast(c.level.maxclients)) |i| {
            const mate = &c.g_entities[i];
            if (mate.inuse == 0 or mate.client == null or mate.client[0].pers.connected != c.CON_CONNECTED or mate.client[0].sess.sessionTeam != team) continue;
            c.AddScore(mate, mate.r.currentOrigin[0..].ptr, 5);
            if (mate != who and mate.health > 0 and c.CanDamage(mate, &home) != 0) c.AddScore(mate, mate.r.currentOrigin[0..].ptr, 1);
        }
    }
    who[0].client[0].ps.persistant[c.PERS_CAPTURES] += 1;
    c.G_LogPrintf("DK3Capture: %d %d %d %d\n", who[0].s.number, team, points, c.level.teamScores[team]);
    if (ctf()) objective.reset() else {
        objective.state = .planted;
        objective.deadline = @min(objective.deadline, now() + 5000);
        objective.place(v.scale(v.add(zone[0].r.absmin, zone[0].r.absmax), 0.5), true, false);
    }
    c.trap_SendServerCommand(-1, c.va("cp \"%s scores!\"", c.TeamName(@intCast(team))));
    sound(who, "sounds/global/bossdeath6.wav");
    c.G_UseTargets(zone, who);
    status();
}
export fn DK_ObjectiveMode() callconv(.c) c.qboolean {
    return @intFromBool(active());
}
export fn DK_InitMultiplayer() callconv(.c) void {
    objectives = .{ .{}, .{} };
}
export fn DK_SpawnMultiplayer(entity: [*c]Entity) callconv(.c) c.qboolean {
    const name = std.mem.span(entity[0].classname);
    const team: c_int = if (std.mem.eql(u8, name, "item_flag_team1")) c.TEAM_RED else if (std.mem.eql(u8, name, "item_flag_team2")) c.TEAM_BLUE else c.TEAM_FREE;
    if (std.mem.eql(u8, name, "info_player_team1") or std.mem.eql(u8, name, "info_player_team2")) {
        if (c.g_gametype.integer != c.GT_SINGLE_PLAYER and !active()) entity[0].classname = @constCast("info_player_deathmatch");
        entity[0].r.svFlags |= c.SVF_NOCLIENT;
        c.G_SetOrigin(entity, entity[0].s.origin[0..].ptr);
        return c.qtrue;
    }
    if (team == c.TEAM_FREE and !std.mem.eql(u8, name, "trigger_capture")) return c.qfalse;
    if (!active()) {
        c.G_FreeEntity(entity);
        return c.qtrue;
    }
    if (team != c.TEAM_FREE) {
        const objective = &objectives[index(team)];
        if (objective.entity != 0) c.G_Error("dk3: duplicate %s objective", c.TeamName(@intCast(team)));
        var map: [c.MAX_QPATH]u8 = @splat(0);
        c.trap_Cvar_VariableStringBuffer("mapname", &map, map.len);
        entity[0].model = if (!ctf()) @constCast("models/global/dt_bpack.dkm") else if (map[1] == '2' or map[1] == '3')
            c.G_NewString(c.va(@constCast(if (map[1] == '2') @as([*:0]const u8, "models/e2/ctflag_%s.dkm") else "models/e3/e3ctflag_%s.dkm"), if (team == c.TEAM_RED) @as([*:0]const u8, "red") else "blue"))
        else
            @constCast("models/global/a_ctf_flag.dkm");
        entity[0].s.modelindex = c.G_ModelIndex(entity[0].model);
        entity[0].s.dk3Team = team;
        entity[0].s.eType = c.ET_DK3_ITEM;
        entity[0].touch = touch;
        entity[0].r.mins = @as(v.Vec, .{ -16, -16, -16 });
        entity[0].r.maxs = @as(v.Vec, .{ 16, 16, 24 });
        objective.entity = entity[0].dk.id;
        objective.home = entity[0].s.origin;
        objective.angles = entity[0].s.angles;
        objective.reset();
    } else {
        if (entity[0].model == null or entity[0].model[0] != '*') c.G_Error("dk3: capture zone needs a brush model");
        _ = c.G_SpawnInt("points", "1", &entity[0].count);
        if (entity[0].count < 1 or entity[0].count > 100) c.G_Error("dk3: capture points must be between 1 and 100");
        c.trap_SetBrushModel(entity, entity[0].model);
        entity[0].r.svFlags |= c.SVF_NOCLIENT;
        entity[0].r.contents = c.CONTENTS_TRIGGER;
        entity[0].touch = capture;
        c.trap_LinkEntity(entity);
        entity[0].s.origin = v.scale(v.add(entity[0].r.absmin, entity[0].r.absmax), 0.5);
    }
    return c.qtrue;
}
export fn DK_CheckMultiplayer() callconv(.c) void {
    if (!active()) return;
    for (0..2) |i| {
        const team: c_int = c.TEAM_RED + @as(c_int, @intCast(i));
        if (objectives[i].entity == 0 or find(null, teamStart(team)) == null) c.G_Error("dk3: map lacks %s objective or team spawn", c.TeamName(@intCast(team)));
    }
}
export fn DK_TeamSpawn(team: c_int, origin: [*c]f32, angles: [*c]f32) callconv(.c) [*c]Entity {
    if (team != c.TEAM_RED and team != c.TEAM_BLUE) return null;
    var spot: [*c]Entity = null;
    var chosen: [*c]Entity = null;
    var fallback: [*c]Entity = null;
    var count: c_int = 0;
    while (true) {
        spot = find(spot, teamStart(team));
        if (spot == null) break;
        if (fallback == null) fallback = spot;
        if (c.SpotWouldTelefrag(spot) == 0) {
            count += 1;
            if (@mod(c.rand(), count) == 0) chosen = spot;
        }
    }
    if (chosen == null) chosen = fallback;
    if (chosen != null) {
        @memcpy(origin[0..3], chosen[0].s.origin[0..]);
        origin[2] += 9;
        @memcpy(angles[0..3], chosen[0].s.angles[0..]);
    }
    return chosen;
}
export fn DK_RunMultiplayer() callconv(.c) void {
    if (!active()) return;
    for (&objectives) |*objective| {
        const entity = c.DK_FindEntity(objective.entity);
        const carrier = c.DK_FindEntity(objective.carrier);
        if (entity == null) continue;
        if (objective.state == .carried) {
            if (!player(carrier)) {
                if (carrier != null) DK_DropObjective(carrier) else objective.reset();
                continue;
            }
            var forward: v.Vec = undefined;
            c.AngleVectors(carrier[0].client[0].ps.viewangles[0..].ptr, &forward, null, null);
            var origin = v.madd(carrier[0].r.currentOrigin, -14, forward);
            origin[2] += 12;
            objective.place(origin, true, false);
        }
        if (!ctf() and objective.state == .carried and carrier != null) {
            const left = objective.deadline - now();
            if (left <= 10000 and !objective.warned) {
                c.trap_SendServerCommand(carrier[0].s.number, "cp \"Bomb timer: ten seconds remaining!\"");
                objective.warned = true;
            }
            if (left <= 10000 and now() >= objective.next_heartbeat) {
                c.G_Sound(carrier, c.CHAN_ITEM, c.DK_SoundIndex("artifacts/goldensoulwait.wav"));
                objective.next_heartbeat = now() + 1000;
                objective.next_beep = objective.next_heartbeat;
            }
            if (left <= 0) c.trap_SendServerCommand(carrier[0].s.number, "cp \"Bomb timer expired!\"");
        }
        if (objective.deadline != 0 and now() >= objective.deadline) {
            if (ctf() or objective.state == .resetting) objective.reset() else objective.explode();
        } else if (!ctf() and objective.deadline > 0 and objective.deadline - now() <= 10000 and objective.state != .resetting and now() >= objective.next_beep) {
            sound(entity, "sounds/global/a_ames.wav");
            objective.next_beep = now() + 1000;
        }
    }
}
export fn DK_ObjectiveGoal(who: [*c]Entity) callconv(.c) [*c]Entity {
    if (who == null or who[0].client == null) return null;
    const team = who[0].client[0].sess.sessionTeam;
    if (!active() or team < c.TEAM_RED or team > c.TEAM_BLUE) return null;
    if (who[0].client[0].ps.dk3Objective != 0) {
        const own = &objectives[index(@intCast(team))];
        if (ctf() and own.state != .home) return c.DK_FindEntity(if (own.carrier != 0) own.carrier else own.entity);
        var zone: [*c]Entity = null;
        var goal: [*c]Entity = null;
        var distance: f32 = 1e30;
        while (true) {
            zone = find(zone, "trigger_capture");
            if (zone == null) break;
            if ((zone[0].spawnflags & 3 == 1 and team != c.TEAM_RED) or (zone[0].spawnflags & 3 == 2 and team != c.TEAM_BLUE)) continue;
            const candidate = v.distance(who[0].r.currentOrigin, zone[0].s.origin);
            if (candidate < distance) {
                goal = zone;
                distance = candidate;
            }
        }
        return goal;
    }
    const objective = &objectives[index(@intCast(if (ctf()) c.OtherTeam(@intCast(team)) else @as(c_int, @intCast(team))))];
    return switch (objective.state) {
        .carried => c.DK_FindEntity(objective.carrier),
        .home, .dropped => c.DK_FindEntity(objective.entity),
        else => null,
    };
}
export fn DK_ObjectiveProtects(who: [*c]Entity, mod: c_int) callconv(.c) c.qboolean {
    return @intFromBool(!ctf() and active() and who != null and who[0].client != null and who[0].client[0].ps.dk3Objective != 0 and
        (mod == c.MOD_WATER or mod == c.MOD_SLIME or mod == c.MOD_LAVA or mod == c.MOD_FALLING));
}
