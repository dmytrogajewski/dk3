// SPDX-License-Identifier: GPL-2.0-or-later
//! Body-agnostic bot locomotion and combat shared by the co-op player bot and
//! the companions. Converts one frame of intent into a movement command (view,
//! world-space heading, buttons): AAS routing, authored route controls, lifts,
//! teleporter passages, hazard avoidance and hostile engagement. Nothing here
//! moves entities or changes inventory; the caller's sink runs the shared
//! player motor (a user command for a client, `player_move.run` for a body
//! that has its own motor state).
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const nav = @import("../domain/navigation.zig");
const steering = @import("../domain/navigation_input.zig");
const skill = @import("../domain/bot_skill.zig");
const combat = @import("../domain/bot_combat.zig");
const route = @import("../domain/coop_route.zig");
const routes = @import("bot_routes.zig");
const Slots = @import("../engine/slots.zig").Slots;
const catalog = @import("actor_catalog");
const evasion = @import("bot_evasion.zig");
const collision_module = @import("../domain/collision.zig");
const weapons = @import("../domain/weapons.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const access = @import("region_access.zig");

/// A target this weak is finished even by a body told to hold its fire.
pub const finish_health: i32 = 15;
pub const Hull = struct {
    mins: v.Vec3 = .{ -15, -15, -24 },
    maxs: v.Vec3 = .{ 15, 15, 32 },
};
/// What the body may do beyond walking and fighting. A player bot does it
/// all; a companion never presses controls, never takes teleporter detours
/// on its own, and has no campaign exits to keep out of.
pub const Capabilities = struct {
    /// Authored route controls (buttons, touch plates, shootable switches)
    /// detoured to and operated when a closed gate holds the way.
    controls: bool = true,
    /// Send or call a lift with its control; otherwise only ride it.
    operate_lifts: bool = true,
    /// Teleporter passages taken when the area graph stalls.
    passages: bool = true,
    /// Campaign exit volumes other than the intended one are avoided.
    /// Lethal hazards and harmful liquids are avoided regardless.
    exits: bool = true,
    use: bool = true,
    /// A civilian blocking a narrow passage for seconds may be shot.
    nuisance: bool = true,
    /// Ambient wildlife is no enemy.
    ignore_ambient: bool = false,
    /// Being hit turns the view toward the shooter's bearing (with the
    /// ladder's error) when nothing else holds it.
    alert: bool = false,
    /// With nothing to fight or operate, look around (the ladder's scan
    /// headings) while walking the route.
    sweep: bool = false,
    /// Keep the last rounds of a ranged weapon for a kill order or an
    /// authored target (the campaign's scarce ammunition).
    conserve_ammo: bool = true,
    /// Step aside for an allied player blocking the way.
    yield_to_allies: bool = false,
    /// Duck while standing to shoot (a shooter's rounds aimed at the chest
    /// mostly pass over a crouched player), and put blast weapons away when
    /// badly hurt while another weapon reaches.
    duck_to_shoot: bool = true,
};
/// Who this body fights: hostile actors (campaign), or the enemy players of
/// a match (by team alliance).
pub const Targets = union(enum) {
    actors,
    players: struct { entities: []const ?ecs.Entity, session: data.Session },
};
/// Team play: a control an ally is already fetching is left to it; the body
/// waits at the gate it opens instead.
pub const Coordination = struct {
    context: *const anyopaque,
    claimed: *const fn (context: *const anyopaque, route_obstacle: u32) bool,
};
/// Weapons this body must not choose against an enemy here (bit per id).
pub const Exclusion = struct {
    context: *const anyopaque,
    mask: *const fn (context: *const anyopaque, frame: Frame, enemy: ?v.Vec3) anyerror!i32,
};
pub const Frame = struct {
    world: *data.World,
    slots: *Slots,
    projections: []abi.EntityProjection,
    service: nav.Service,
    /// Trace/contents for every probe (the engine's for a client, the
    /// region-aware probe for a companion that may stand across a seam).
    collision: collision_module.Collision,
    table: *const weapons.Table,
    /// Engine slot of the body; its traces skip it.
    slot: u16,
    entity: ecs.Entity,
    /// Movement state of the body (the client's player, a companion's motor).
    state: data.Player,
    hull: Hull = .{},
    now: i64,
    /// Live navigation gates of this world, for planning past closed ones.
    gates: ?*@import("navigation_gates.zig").State = null,
    /// Enemies may stand in neighbouring resident worlds.
    region: bool = false,
    capabilities: Capabilities = .{},
    targets: Targets = .actors,
    coordination: ?Coordination = null,
    /// Diagnostic view-cone override in degrees (the ladder's otherwise).
    field_of_view: ?f32 = null,
    exclusion: ?Exclusion = null,
    /// Least damage of an enabled hazard volume the body keeps out of.
    hazard_damage: i32 = 25,
    /// Clearance kept from a lethal volume (laser barrier, crusher) against
    /// knockback; steps inside it may run alongside but not close in.
    lethal_margin: f32 = 48,
    /// Developer log prefix ("dk3 <label>:").
    label: []const u8 = "coop",
};
pub const Intent = struct {
    destination: ?v.Vec3 = null,
    /// Steer straight at the destination when routing has no answer near it
    /// (thin exit brushes, trigger volumes and authored ground-node segments
    /// can lie outside every connected AAS area).
    direct_radius: f32 = 600,
    /// Steer straight at the destination, ignoring navigation.
    direct: bool = false,
    /// Hold crouch.
    crouch: bool = false,
    /// Slow down approaching a precise goal (off for run-ups).
    brake: bool = false,
    /// Fraction of full movement input (a short hop onto a narrow ledge).
    pace: f32 = 1,
    /// The only campaign exit this step may touch; every other exit volume is
    /// avoided so a detour can never travel to an unintended map.
    exit: u32 = 0,
    /// Point the view must face for use/shoot; suppresses automatic engagement aim.
    face: ?v.Vec3 = null,
    /// Absolute view for `look`.
    view: ?[2]f32 = null,
    /// Press use once the view is centred on this engine slot within reach.
    use_slot: ?u16 = null,
    /// Fire at `face` once the shot trace reaches this engine slot.
    shoot_slot: ?u16 = null,
    fight: bool = true,
    /// Persistent id of the actor a kill action pursues; preferred when visible.
    preferred: u32 = 0,
    weapon: ?u5 = null,
    jump: bool = false,
    /// Respawn/death-checkpoint request while dead.
    attack_when_dead: bool = false,
    /// "Press a key to continue" after a campaign ending's intermission.
    press_to_continue: bool = false,
    /// Pull the trigger now (a shotcycler jump), whatever is in view.
    trigger: bool = false,
    /// Fighting from a held position: keep strafing on a short tether here.
    leash: ?v.Vec3 = null,
    /// Horizontal box that evasion and strafing must not leave.
    arena: ?[2][2]f32 = null,
    /// Where the hunted target is believed to be; the view turns there when
    /// nothing is in sight, like a player watching where the boss flew off.
    look_at: ?v.Vec3 = null,
    /// Trigger discipline: hold keeps aiming without firing; finish_only
    /// fires only at a target with almost no health left.
    fire: enum { free, hold, finish_only } = .free,
    /// Meet an enemy head on with a close-quarters weapon, and back off a
    /// brawler while holding a fight. Off: keep the distance there is.
    close_in: bool = true,
    /// Persistent id of a body this one guards: hostiles hunting it are
    /// engaged at any sighted range, as those hunting this body are.
    guard: u32 = 0,
    /// Unprovoked hostiles further than this are let be.
    engage_range: f32 = 450,
};
pub const Report = struct {
    waypoint: ?nav.Waypoint = null,
    blocked: bool = false,
    enemy: u32 = 0,
    enemy_distance: f32 = 0,
    fired: bool = false,
    used: bool = false,
    /// The prey is seen but a shot at it would meet cover first.
    lane_blocked: bool = false,
    /// What the use pressed (a control on the way, or the action's own target).
    used_slot: u16 = c.ENTITYNUM_NONE,
    control: u32 = 0,
    /// Where the bot stands to operate that control.
    control_point: ?v.Vec3 = null,
    passage: u32 = 0,
    no_route: bool = false,
    /// Steering straight at a near goal because the area graph has no way
    /// there (or no area under the body).
    routeless: bool = false,
    /// An unintended exit or a lethal hazard volume stopped this step.
    avoided_exit: u32 = 0,
    /// Survival movement replaced the route step this frame.
    dodging: bool = false,
    enemy_health: i32 = 0,
    /// Three seconds of fire at this target have not hurt it (a ledge or the
    /// water takes the shots): hold fire and find another line.
    futile: bool = false,
    /// Engine slot the forward probe hit (ENTITYNUM_NONE when clear), and
    /// whether local avoidance turned the step around it.
    obstacle: u16 = c.ENTITYNUM_NONE,
    /// Persistent id of what the forward probe hit (0: geometry or nothing).
    obstacle_id: u32 = 0,
    /// Team play: the destination is out of reach for now (nobody opened the
    /// gate in time, or nothing opens it); pursue other goals this long.
    give_up_ms: i64 = 0,
    sidestepped: bool = false,
};
/// One frame of movement input, before any sink encodes it.
pub const Command = struct {
    /// View after the turn-rate limit (pitch, yaw, 0).
    angles: v.Vec3,
    /// Forward and right resolved against `angles` yaw; up is jump/crouch,
    /// ladder climb and swim stroke.
    forward: i8 = 0,
    right: i8 = 0,
    up: i8 = 0,
    attack: bool = false,
    /// A client holding any key (an ending's "press to continue").
    any: bool = false,
    use: bool = false,
    weapon: u5 = 0,
};
pub const Steering = struct { report: Report, command: Command };
/// Look-around headings relative to travel: the sides are swept, never behind.
pub const sweep_headings = [_]f32{ 0, 40, -40, 80, -80, 0 };
pub const Pilot = struct {
    route: nav.State = .{},
    /// Shots at `futile_target` since its health last fell (see Report.futile).
    futile_target: u32 = 0,
    futile_health: i32 = 0,
    futile_ms: i64 = 0,
    futile_shots: u32 = 0,
    /// A weapon whose shots did not hurt `futile_target` (rockets corkscrewing
    /// into a narrow ramp's walls): set aside for it until then.
    spent_weapon: i32 = 0,
    spent_until: i64 = 0,
    hold_fire_until: i64 = 0,
    jump_until: i64 = 0,
    jump_ready: i64 = 0,
    use_ready: i64 = 0,
    control: ?routes.Control = null,
    control_until: i64 = 0,
    seek_ms: i64 = 0,
    unblock_ms: i64 = 0,
    /// Holding still while a gate on the way opens.
    hold_until: i64 = 0,
    /// Routing round lifts until then: one stood away that this body
    /// may not call, with a way on foot.
    lifts_off_until: i64 = 0,
    avoided: u32 = 0,
    avoid_until: i64 = 0,
    passage: ?struct { route: routes.Passage, teleport_bit: bool, until_ms: i64 } = null,
    target: u32 = 0,
    seen_ms: i64 = 0,
    reaction_ready: i64 = 0,
    shot_ready: i64 = 0,
    locked_ms: i64 = 0,
    wobble_ready: i64 = 0,
    noise_yaw: f32 = 0,
    noise_pitch: f32 = 0,
    seed: u32 = 0x5eed,
    step_ms: i64 = 0,
    unstick_until: i64 = 0,
    unstick_side: f32 = 1,
    strafe_until: i64 = 0,
    strafe_side: f32 = 1,
    detour_side: f32 = 1,
    /// Recently dodged: the strafe tether must not pull back into the blast area.
    dodge_until: i64 = 0,
    dodge_log_ms: i64 = 0,
    scan_until: i64 = 0,
    scan_yaw: f32 = 0,
    submerged_ms: i64 = 0,
    direct_mark: v.Vec3 = @splat(0),
    direct_ms: i64 = 0,
    /// A civilian in the way since `blocker_ms`; one that stayed there long
    /// enough becomes the `nuisance` the bot is allowed to shoot.
    blocker: u32 = 0,
    blocker_ms: i64 = 0,
    nuisance: u32 = 0,
    /// Closest the player came to the current step target, and when.
    approach_point: v.Vec3 = @splat(0),
    approach_best: f32 = 0,
    approach_ms: i64 = 0,
    /// The route's point the player keeps circling (overshooting it each
    /// way against a closed door) and since when.
    hover_point: v.Vec3 = @splat(0),
    hover_ms: i64 = 0,
    direct_fallback_until: i64 = 0,
    /// A goal the area graph cannot reach (a step-up lip into a console's
    /// alcove it has no link for), and the nearest point near it it can.
    near_goal: v.Vec3 = @splat(0),
    near_point: ?v.Vec3 = null,
    near_ms: i64 = 0,
    direct_retry_ms: i64 = 0,
    committed: ?nav.Waypoint = null,
    committed_until: i64 = 0,
    /// The waypoint chosen before the current one: a route flipping back to
    /// it is two adjacent areas each routing through the other's entrance.
    previous_point: ?v.Vec3 = null,
    level: i32 = 10,
    attempt: u32 = 0,
    /// Hurt revision last seen, and the shooter bearing it turned toward.
    receipt: ?u32 = null,
    alert_yaw: ?f32 = null,
    alert_until: i64 = 0,
    /// Look-around: the heading held and until when.
    sweep_index: usize = 0,
    sweep_until: i64 = 0,
    /// Waiting at a gate an ally opens: where, until when, since when.
    gate_point: ?v.Vec3 = null,
    gate_until: i64 = 0,
    gate_since: i64 = 0,
    /// Stepping aside for an ally: where and until when.
    yield_point: ?v.Vec3 = null,
    yield_until: i64 = 0,

    /// Per-attempt variation of the bot's own choices (strafe/detour sides,
    /// dodge ordering, aim noise); deterministic for a given attempt number.
    pub fn vary(self: *Pilot, attempt: u32) void {
        self.seed = 0x5eed +% attempt *% 0x9e3779b9;
        if (self.seed == 0) self.seed = 1;
        self.attempt = attempt;
        const odd = attempt % 2 == 1;
        self.strafe_side = if (odd) -1 else 1;
        self.detour_side = if (odd) -1 else 1;
    }
    /// Forget routing state when the scripted goal or the world changes.
    pub fn reset(self: *Pilot) void {
        self.* = .{ .seed = self.seed, .level = self.level, .step_ms = self.step_ms, .attempt = self.attempt, .strafe_side = self.strafe_side, .detour_side = self.detour_side };
    }

    pub fn steer(self: *Pilot, frame: Frame, intent: Intent) !Steering {
        var outcome = try self.plan(frame, intent);
        if (outcome.report.enemy != 0) if (self.find(frame, outcome.report.enemy)) |seen| {
            if (seen.get(data.Health) catch null) |health| outcome.report.enemy_health = health.current;
        };
        return outcome;
    }
    fn find(_: *const Pilot, frame: Frame, id: u32) ?Ref {
        if (frame.region) return access.find(frame.world, id);
        return .{ .world = frame.world, .entity = frame.world.find(id) orelse return null };
    }
    fn plan(self: *Pilot, frame: Frame, intent: Intent) !Steering {
        const world = frame.world;
        const entity = frame.entity;
        var report: Report = .{};
        const player = frame.state;
        const pose = (try world.get(entity, data.Transform)).*;
        const loadout = (try world.get(entity, data.Weapons)).*;
        var command: Command = .{ .angles = .{ pose.angles[0], pose.angles[1], 0 }, .weapon = @intCast(loadout.weapon) };
        if (player.mode == .dead) {
            // A dead player requests the authored death checkpoint with attack.
            if (intent.attack_when_dead and @mod(@divTrunc(frame.now, 250), 2) == 0) command.attack = true;
            self.reset();
            return .{ .report = report, .command = command };
        }
        if (player.mode != .normal) {
            // Frozen by a cinematic: hold still and keep the view, like an idle player.
            // A client sets BUTTON_ANY for any key held; the ending waits on that.
            if (intent.press_to_continue and @mod(@divTrunc(frame.now, 250), 2) == 0) {
                command.attack = true;
                command.any = true;
            }
            self.step_ms = frame.now;
            return .{ .report = report, .command = command };
        }
        var policy = skill.profile(self.level);
        if (frame.field_of_view) |cone| policy.field_of_view = cone;
        const eye = v.add(pose.position, .{ 0, 0, player.view_height });
        const facing = v.basis(pose.angles).forward;
        // Being hit is a cue rather than sight: face the shooter's bearing,
        // more accurately the higher the skill.
        if (frame.capabilities.alert) if (world.get(entity, data.Hurt) catch null) |hurt| {
            if (self.receipt) |seen| if (hurt.revision != seen and hurt.source != 0) if (world.find(hurt.source)) |shooter| if (shooter.index != entity.index) {
                const point = (try world.get(shooter, data.Transform)).position;
                self.alert_yaw = skill.yaw(v.subtract(point, eye)) + skill.noise(&self.seed) * policy.alert_error;
                self.alert_until = frame.now + policy.alert_ms;
            };
            self.receipt = hurt.revision;
        };
        if (self.passage) |passage| if (player.teleport_bit != passage.teleport_bit or frame.now >= passage.until_ms) {
            self.passage = null;
            self.route = .{};
        };

        // Engagement: hostile actors inside the view cone (or close enough to
        // sense) with a clear shot line. A scripted kill target wins ties.
        var scan: Scan = .{ .frame = frame, .intent = intent, .policy = policy, .facing = facing, .eye = eye, .self_id = try world.persistentId(entity), .target = self.target, .nuisance = if (frame.capabilities.nuisance) self.nuisance else 0 };
        if (intent.fight and intent.face == null) switch (frame.targets) {
            .players => |match| for (match.entities) |maybe| {
                const candidate = maybe orelse continue;
                if (candidate.index == entity.index) continue;
                try scan.considerPlayer(.{ .world = world, .entity = candidate }, match.session);
            },
            .actors => if (frame.region) {
                var candidates = access.Damageables.init(world, frame.slots);
                while (candidates.next()) |candidate| {
                    if (candidate.world == world and candidate.entity.index == entity.index) continue;
                    try scan.consider(candidate);
                }
            } else {
                var query = world.queryAccess(data.World.mask(.{ data.Actor, data.Health, data.Transform, data.Binding, data.Body }), 0, 0);
                defer query.deinit();
                while (query.next()) |view| for (view.entities()) |candidate| try scan.consider(.{ .world = world, .entity = candidate });
            },
        };
        const enemy = scan.enemy;
        const enemy_point = scan.point;
        if (enemy) |seen| {
            const identity = try seen.id();
            if (identity != self.target) {
                self.target = identity;
                self.reaction_ready = frame.now + policy.reaction_ms;
                self.locked_ms = frame.now;
            }
            self.seen_ms = frame.now;
            report.enemy = identity;
            report.enemy_distance = v.length(v.subtract(enemy_point, eye));
        } else if (frame.now - self.seen_ms > policy.memory_ms) self.target = 0;
        // Choose for what will be shot: the visible enemy, else a shoot target.
        // With nothing in view, keep ready a weapon for the close encounters
        // corridors bring (not a splash weapon such as C4, which would have to
        // be swapped out the moment something rounds a corner).
        const range: f32 = if (enemy != null) report.enemy_distance else if (intent.shoot_slot != null and intent.face != null) v.length(v.subtract(intent.face.?, eye)) else 150;
        // An ion bolt discharges where it meets water, hurting everything
        // within 64 units: not from the water, nor into water close by.
        const wet = try waterNear(frame, eye, pose.position, if (enemy != null) enemy_point else intent.face);
        // Weapons the body must not use here (a companion's splash weapons
        // with its leader beside the target).
        var excluded: i32 = if (frame.exclusion) |rule| try rule.mask(rule.context, frame, if (enemy != null) enemy_point else null) else 0;
        if (enemy != null and self.target == self.futile_target and frame.now < self.spent_until) excluded |= @as(i32, 1) << @intCast(self.spent_weapon);
        // Badly hurt, a blast weapon's own splash (a round meeting a door
        // that shuts in front of it, an enemy stepping into the lane) is
        // the last hit: another weapon that reaches comes first.
        const hurt = if (world.get(entity, data.Health)) |health| health.current * 2 < health.maximum else |_| false;
        if (frame.capabilities.duck_to_shoot and hurt) {
            var blasts: i32 = 0;
            for (@import("weapon_catalog").entries) |entry| if (entry.spec.splash_hazard) {
                blasts |= @as(i32, 1) << entry.id;
            };
            var others = loadout;
            others.dk3Inventory &= ~blasts;
            if (combat.rangedFor(others, frame.table, .{ .advancing = true, .excluded = excluded })) excluded |= blasts;
        }
        // Blowing up an object (a grate, a crate) with one of the party in
        // the way or beside it: not with a blast weapon while another reaches.
        if (enemy == null and intent.shoot_slot != null and intent.face != null and try allyNear(frame, eye, intent.face.?, 192)) {
            var blasts: i32 = 0;
            for (@import("weapon_catalog").entries) |entry| if (entry.spec.splash_hazard) {
                blasts |= @as(i32, 1) << entry.id;
            };
            var others = loadout;
            others.dk3Inventory &= ~blasts;
            if (combat.rangedFor(others, frame.table, .{ .advancing = true, .excluded = excluded })) excluded |= blasts;
        }
        var selected = if (intent.weapon) |wanted| wanted else combat.selectFor(loadout, frame.table, range, .{ .wet = wet, .advancing = true, .ranged_first = true, .excluded = excluded });
        const discharge = wet and combat.dischargesInWater(selected);
        // Ammunition reserve: with the last rounds left and no kill ordered,
        // fight only up close with a melee weapon; authored targets that only a
        // shot can trigger (turret controls) need what remains.
        var reserved = false;
        if (frame.capabilities.conserve_ammo and intent.weapon == null and intent.shoot_slot == null and enemy != null and weaponReach(frame, selected) >= 160 and loadout.ammo[selected] <= 12) {
            // Another ranged weapon with rounds to spare comes first.
            var others = loadout;
            others.dk3Inventory &= ~(@as(i32, 1) << selected);
            const other = combat.selectFor(others, frame.table, range, .{ .wet = wet, .advancing = true, .ranged_first = true, .excluded = excluded });
            if (other != selected and others.dk3Inventory & (@as(i32, 1) << other) != 0 and weaponReach(frame, other) >= 160 and others.ammo[other] > 12) selected = other;
        }
        if (frame.capabilities.conserve_ammo and intent.weapon == null and intent.shoot_slot == null and enemy != null) {
            const ranged = weaponReach(frame, selected) >= 160;
            if (ranged and loadout.ammo[selected] <= 12) {
                // A kill order may still spend rounds at range; anything else waits.
                reserved = intent.preferred == 0;
                if (melee(loadout, frame, excluded)) |glove| if (report.enemy_distance < 220) {
                    selected = glove;
                    reserved = false;
                };
            }
        }
        // Nothing allowed to choose leaves the weapon in hand; if that one is
        // excluded too, it stays raised but silent.
        if (intent.weapon == null and excluded & (@as(i32, 1) << selected) != 0) reserved = true;
        command.weapon = selected;

        // Locomotion toward the scripted destination, with the same authored
        // control, passage and lift handling as multiplayer bots.
        var destination = intent.destination;
        var control_aim: ?v.Vec3 = null;
        if (self.control) |previous| {
            self.control_until = @max(self.control_until, self.route.progress_ms + 15000);
            if (routes.completed(world, previous) or frame.now >= self.control_until) {
                if (!routes.completed(world, previous)) {
                    self.avoided = previous.id;
                    self.avoid_until = frame.now + 10000;
                }
                self.control = null;
                self.route = .{};
            } else {
                var control = previous;
                control_aim = try routes.aim(world, control);
                if (control_aim == null) if (try routes.advance(world, frame.slots, frame.projections, entity, control, frame.service, frame.now)) |next| {
                    control = next;
                    self.control = next;
                    self.route = .{};
                    control_aim = try routes.aim(world, next);
                };
                destination = if (control_aim == null) pose.position else control.point;
                if (control.action == .touch and nav.horizontalDistance(pose.position, control.point) < 24 and control_aim != null) destination = control_aim;
                report.control = control.id;
                report.control_point = control.point;
            }
        }
        // Stepping aside for an ally, or waiting at a gate an ally opens.
        if (frame.now < self.yield_until) {
            destination = self.yield_point;
        } else self.yield_point = null;
        if (frame.now < self.gate_until and self.control == null) {
            if (destination != null) destination = self.gate_point;
        } else self.gate_point = null;
        if (self.control == null and self.passage == null) if (destination) |goal| {
            if (try routes.ridePoint(world, frame.slots, entity, player.ground_entity, goal)) |point| destination = point;
        };
        var movement: v.Vec3 = @splat(0);
        var crouch = false;
        var ladder = false;
        // Steering straight at a near goal because navigation has no way there.
        var routeless = false;
        if (destination) |goal| {
            // Holding a spot (riding at a lift's centre) is not a stall.
            if (intent.direct and frame.now - self.direct_ms > 1500 and frame.now >= self.direct_retry_ms and nav.horizontalDistance(pose.position, goal) > 32) {
                // Straight steering stalled even after a hop: the player was
                // displaced off the authored line. Route back over navigation.
                self.direct_fallback_until = frame.now + 2500;
                self.direct_retry_ms = frame.now + 4000;
                self.direct_mark = pose.position;
                self.direct_ms = frame.now;
            }
            if (intent.direct and frame.now >= self.direct_fallback_until) {
                movement = v.subtract(goal, pose.position);
            } else if (self.passage) |passage| {
                movement = v.subtract(passage.route.point, pose.position);
                report.passage = passage.route.id;
            } else if (try self.follow(frame, pose.position, try self.reachableNear(frame, pose.position, goal, intent.direct_radius))) |waypoint| {
                report.waypoint = waypoint;
                if (frame.now >= self.gate_until) self.gate_since = 0;
                movement = v.subtract(waypoint.point, pose.position);
                // The route takes a lift: board it, call it or send it, and ride.
                // Also on the way to a control (a button the lift carries the
                // player up to): the lift's own control comes first, and the
                // planner names the other again once the route is clear.
                // Aboard a lift whose route goes on far above or below within
                // its shaft (the area graph has the shaft empty): send it.
                var lift_entrance: ?v.Vec3 = if (waypoint.elevator) waypoint.entrance else null;
                if (lift_entrance == null and @abs(waypoint.point[2] - pose.position[2]) > 64 and player.ground_entity < frame.slots.occupants.len) if (frame.slots.occupants[player.ground_entity]) |ground| {
                    const lift = (world.get(ground, data.Train) catch null) != null or (world.get(ground, data.Mover) catch null) != null;
                    const box = frame.projections[player.ground_entity].shared;
                    if (lift and waypoint.point[0] > box.absmin[0] - 32 and waypoint.point[0] < box.absmax[0] + 32 and waypoint.point[1] > box.absmin[1] - 32 and waypoint.point[1] < box.absmax[1] + 32) lift_entrance = pose.position;
                };
                if (engine.integer("developer") >= 2) if (lift_entrance) |entrance| {
                    var text: [192]u8 = undefined;
                    engine.print(std.fmt.bufPrintZ(&text, "dk3 {s}: t={d} event=lift entrance={d:.0},{d:.0},{d:.0} elevator={d} ground={d}\n", .{ frame.label, frame.now, entrance[0], entrance[1], entrance[2], @intFromBool(waypoint.elevator), player.ground_entity }) catch "");
                };
                if (lift_entrance) |entrance| if (try routes.liftStep(world, frame.slots, frame.projections, entity, .{ .ground = player.ground_entity, .view_height = player.view_height, .collision = frame.collision, .operate = frame.capabilities.operate_lifts }, entrance, frame.service, frame.now)) |step| switch (step) {
                    .board => |point| movement = v.subtract(point, pose.position),
                    .hold => |point| movement = if (nav.horizontalDistance(point, pose.position) > 8) v.subtract(point, pose.position) else @splat(0),
                    .operate => |found| if (self.control == null or self.control.?.id != found.id) {
                        self.control = found;
                        self.control_until = frame.now + 15000;
                        self.route = .{};
                        movement = @splat(0);
                    },
                    .wait => movement = @splat(0),
                    .away => {
                        movement = @splat(0);
                        const round = try frame.service.next(.{ .position = pose.position, .destination = goal, .slot = frame.slot, .player = true, .allow_slime_escape = true, .lifts = false });
                        if (engine.integer("developer") >= 2) {
                            var text: [160]u8 = undefined;
                            const point: v.Vec3 = if (round) |w| w.point else @splat(0);
                            engine.print(std.fmt.bufPrintZ(&text, "dk3 {s}: t={d} event=lift-away round={d:.0},{d:.0},{d:.0}\n", .{ frame.label, frame.now, point[0], point[1], point[2] }) catch "");
                        }
                        if (round != null) {
                            self.lifts_off_until = frame.now + 10000;
                            self.route = .{};
                            self.committed = null;
                        }
                    },
                };
                ladder = waypoint.ladder;
                const hull = (try world.get(entity, data.Body)).*;
                crouch = waypoint.crouch or try steering.crouch(frame.collision, pose.position, waypoint.point, hull.mins, .{ hull.maxs[0], hull.maxs[1], frame.hull.maxs[2] }, frame.slot, hull.collision_mask);
                if (waypoint.jump and player.ground_entity != c.ENTITYNUM_NONE and frame.now >= self.jump_ready) {
                    self.jump_until = frame.now + 200;
                    self.jump_ready = frame.now + 800;
                }
            } else if (nav.horizontalDistance(pose.position, goal) < intent.direct_radius) {
                movement = v.subtract(goal, pose.position);
                routeless = !intent.direct;
            } else report.no_route = true;
            // Straight steering (an authored line, a near goal the area graph
            // has no way to) ducks under a low ceiling as a routed stride does.
            if (!crouch and v.length(.{ movement[0], movement[1], 0 }) > 1) {
                const hull = (try world.get(entity, data.Body)).*;
                crouch = try steering.crouch(frame.collision, pose.position, v.add(pose.position, movement), hull.mins, .{ hull.maxs[0], hull.maxs[1], frame.hull.maxs[2] }, frame.slot, hull.collision_mask);
            }
            // No route while a closed navigation gate (a door, toggled wall,
            // damaging volume, retracted floor or breakable) holds the way:
            // detour to whatever authored control opens it.
            if ((report.no_route or routeless) and frame.capabilities.controls and self.control == null and self.passage == null and frame.now >= self.unblock_ms) if (frame.gates) |state| {
                self.unblock_ms = frame.now + 1000;
                var waiting = false;
                var fetching = false;
                if (try routes.unblockWaiting(world, frame.slots, frame.projections, state, entity, goal, frame.service, frame.now, if (frame.now < self.avoid_until) self.avoided else 0, &waiting)) |found| {
                    // An ally already fetching this control keeps it; this
                    // body stays available to cross the gate meanwhile.
                    if (!claimed(frame, found.route_obstacle)) {
                        self.control = found;
                        self.control_until = frame.now + 15000;
                        self.route = .{};
                        fetching = true;
                    }
                }
                if (frame.coordination == null) {
                    // A door in the way is opening: hold here until it is open.
                    if (!fetching and waiting) self.hold_until = frame.now + 1000;
                } else if (fetching) self.gate_since = 0 else {
                    if (self.gate_since == 0) self.gate_since = frame.now;
                    if (frame.now - self.gate_since > 20000) {
                        // Nobody opened it: other goals meanwhile, then again.
                        report.give_up_ms = 10000;
                        self.gate_since = 0;
                    } else if (try routes.gateFront(world, state, entity, goal)) |point| {
                        self.gate_point = point;
                        self.gate_until = frame.now + 1000;
                    } else if (!waiting) report.give_up_ms = 3000;
                }
            };
            if ((report.no_route or routeless) and frame.now < self.hold_until) movement = @splat(0);
            report.blocked = self.route.blocked;
            report.routeless = routeless;
            // A stride that stalls with input held means a lip or step the
            // route did not mark: hop it, the way a player would.
            // Horizontal only: bobbing at a surface or hopping in place is no progress.
            if (nav.horizontalDistance(pose.position, self.direct_mark) > 8) {
                self.direct_mark = pose.position;
                self.direct_ms = frame.now;
            }
            // Sliding along an obstruction moves the player without bringing
            // the step target any closer: that is a stall too.
            const aim_point = v.add(pose.position, movement);
            const aim_distance = nav.horizontalDistance(pose.position, aim_point);
            if (nav.horizontalDistance(aim_point, self.approach_point) > 16 or aim_distance < self.approach_best - 8) {
                self.approach_point = aim_point;
                self.approach_best = aim_distance;
                self.approach_ms = frame.now;
            }
            const sliding = aim_distance > 24 and frame.now - self.approach_ms > 1500;
            // Standing on a mover (riding a lift to its centre) is carried,
            // not stuck: a hop there only lands beside it.
            const on_mover = player.ground_entity < frame.slots.occupants.len and if (frame.slots.occupants[player.ground_entity]) |ground| (world.get(ground, data.Mover) catch null) != null or (world.get(ground, data.Train) catch null) != null else false;
            if ((frame.now - self.direct_ms > 700 or sliding) and !(on_mover and intent.direct) and player.ground_entity != c.ENTITYNUM_NONE and player.water_level < 2 and frame.now >= self.jump_ready and v.length(.{ movement[0], movement[1], 0 }) > 4) {
                self.jump_until = frame.now + 200;
                self.jump_ready = frame.now + 900;
                report.blocked = true;
            }
            const changing_floor = self.control == null and player.ground_entity != c.ENTITYNUM_NONE and @abs(movement[2]) > 18;
            // Circling the same route point without the route moving on
            // (the next step lies through a door the hull is pressed to).
            // (Not while steering straight or standing on a mover: a rider
            // holds its spot on purpose.)
            var hovering = false;
            if (!intent.direct and !on_mover) if (report.waypoint) |waypoint| {
                if (v.length(v.subtract(waypoint.point, self.hover_point)) > 16 or nav.horizontalDistance(waypoint.point, pose.position) > 24) {
                    self.hover_point = waypoint.point;
                    self.hover_ms = frame.now;
                } else hovering = frame.now - self.hover_ms > 2500;
            };
            const stalled = frame.now - self.direct_ms > 1500 or sliding or hovering;
            if (self.passage == null and (self.route.blocked or stalled or changing_floor) and frame.now >= self.seek_ms) {
                self.seek_ms = frame.now + 500;
                // A waypoint at the player's feet gives no heading: use the goal.
                // (A door the hull already touches leaves the waypoint just
                // beyond it, a few units away: that still gives the heading.)
                const toward = if (self.route.waypoint) |waypoint| (if (nav.horizontalDistance(waypoint.point, pose.position) > 6) waypoint.point else goal) else goal;
                if (engine.integer("developer") >= 2) {
                    var text: [192]u8 = undefined;
                    engine.print(std.fmt.bufPrintZ(&text, "dk3 {s}: t={d} event=seek pos={d:.0},{d:.0},{d:.0} toward={d:.0},{d:.0},{d:.0} blocked={d} stalled={d}\n", .{ frame.label, frame.now, pose.position[0], pose.position[1], pose.position[2], toward[0], toward[1], toward[2], @intFromBool(self.route.blocked), @intFromBool(stalled) }) catch "");
                    if (frame.capabilities.controls) try routes.diagnose(world, frame.slots, frame.projections, entity, toward, frame.service, frame.now);
                }
                const passage = if (self.control == null and frame.capabilities.passages) try routes.teleportPassage(world, frame.projections, entity, toward, goal, frame.service, frame.now) else null;
                if (passage) |found| {
                    self.passage = .{ .route = found, .teleport_bit = player.teleport_bit, .until_ms = frame.now + 5000 };
                    self.route = .{};
                    movement = v.subtract(found.point, pose.position);
                } else if (if (frame.capabilities.yield_to_allies) try routes.yieldPoint(world, frame.slots, entity, toward) else null) |point| {
                    self.yield_point = point;
                    self.yield_until = frame.now + 1000;
                    self.route = .{};
                } else if (if (frame.capabilities.controls) try routes.seek(world, frame.slots, frame.projections, entity, toward, frame.service, frame.now, if (frame.now < self.avoid_until) self.avoided else 0) else null) |found| {
                    if (self.control == null and claimed(frame, found.route_obstacle)) {
                        // An ally fetches the remote control while this body
                        // stays to cross the door.
                        movement = @splat(0);
                    } else if (self.control == null or found.id != self.control.?.id) {
                        var next = found;
                        if (self.control) |parent| next.route_obstacle = parent.route_obstacle;
                        self.control = next;
                        self.control_until = frame.now + 15000;
                        self.route = .{};
                    }
                } else if ((self.route.blocked or stalled or report.no_route) and frame.now - @min(self.route.progress_ms, self.direct_ms) >= 1500 and frame.now >= self.unstick_until) {
                    // Nothing authored explains the obstruction: sidestep and hop
                    // briefly, the way a player shakes loose from a ledge or prop.
                    self.unstick_until = frame.now + 600;
                    self.unstick_side = -self.unstick_side;
                    if (player.ground_entity != c.ENTITYNUM_NONE and frame.now >= self.jump_ready) {
                        self.jump_until = frame.now + 200;
                        self.jump_ready = frame.now + 800;
                    }
                }
            }
        }

        // Standing on an actor (a worker who stopped on the goal, a corpse
        // mid-fall) is no footing: step off it, away from its centre.
        if (player.ground_entity < frame.slots.occupants.len) if (frame.slots.occupants[player.ground_entity]) |under| {
            if ((world.get(under, data.Actor) catch null) != null) {
                var away = v.subtract(pose.position, (try world.get(under, data.Transform)).position);
                away[2] = 0;
                if (v.length(away) < 4) away = .{ @cos(self.detour_side), @sin(self.detour_side), 0 };
                movement = v.scale(v.normalize(away), 64);
            }
        };

        // Ladders the route steers straight at (rungs that slide out of a
        // wall are not in the area graph): with the goal well above and a
        // climbable face within reach, press into it and climb.
        if (!ladder and movement[2] > 24 and player.water_level < 2) if (try climbable(frame, pose.position)) |normal| {
            const rise = movement[2];
            movement = v.scale(normal, -16);
            movement[2] = rise;
            ladder = true;
        };

        // Navigation areas do not model actors or static props; steer around a
        // body in the way like a player would. Closed doors stay obstacles so
        // the authored-control search above can open them.
        // Straight-steered segments are precise (pipes, ledges): no deviations.
        const precise_path = intent.direct;
        // A body standing on a precise segment (a worker on a walkway) is
        // stepped around too; geometry there stays the route's decision.
        if ((!precise_path or try actorAhead(frame, pose.position, movement)) and !ladder and player.water_level < 2 and v.length(.{ movement[0], movement[1], 0 }) > 0.01) {
            if (try self.sidestep(frame, pose.position, movement, &report)) |turned| {
                movement = turned;
                report.sidestepped = true;
            }
        }

        // With only a close-quarters weapon, a near enemy is met head on.
        const melee_reach = weaponReach(frame, selected);
        if (!precise_path and !ladder and enemy != null and intent.close_in and intent.leash == null and melee_reach < 160 and report.enemy_distance > melee_reach * 0.8 and report.enemy_distance < 320 and self.control == null) {
            const charge = v.subtract(enemy_point, pose.position);
            const stride = v.scale(v.normalize(.{ charge[0], charge[1], 0 }), 64);
            if (player.water_level < 2 and try evasion.supported(frame, pose.position, v.add(pose.position, stride))) movement = charge;
        }

        // Survival movement: step away from incoming shots and forecast spray
        // impacts; when holding a fight, keep moving on a short tether. Not
        // from a ladder or in mid-air, where the step only steers the player
        // off the rungs or past a narrow landing into whatever lies below.
        const airborne = player.ground_entity == c.ENTITYNUM_NONE and player.water_level < 2;
        const threats = if (precise_path or ladder or airborne or !policy.evasion) evasion.Threats{} else try evasion.gather(frame, pose.position);
        if (threats.len > 0) {
            self.dodge_until = frame.now + 1500;
            const velocity = (try world.get(entity, data.Velocity)).linear;
            const chosen = try evasion.escape(frame, pose.position, velocity, threats.slice(), intent.leash, intent.arena, self.attempt, blocked);
            if (chosen) |step| {
                movement = step;
                report.dodging = true;
            }
            if (engine.integer("developer") > 0 and frame.now >= self.dodge_log_ms) {
                self.dodge_log_ms = frame.now + 250;
                var text: [512]u8 = undefined;
                var cursor = (try std.fmt.bufPrint(&text, "dk3 {s}: t={d} event=threats pos={d:.0},{d:.0} step={d:.0},{d:.0}", .{ frame.label, frame.now, pose.position[0], pose.position[1], if (chosen) |step| step[0] else 0, if (chosen) |step| step[1] else 0 })).len;
                for (threats.slice()) |threat| cursor += (std.fmt.bufPrint(text[cursor .. text.len - 2], " {d:.0},{d:.0}@{d:.2}", .{ threat.point[0], threat.point[1], threat.eta }) catch break).len;
                text[cursor] = '\n';
                text[cursor + 1] = 0;
                engine.print(text[0 .. cursor + 1 :0]);
            }
        } else if (intent.leash) |anchor| if (policy.evasion and enemy != null and intent.destination == null and self.control == null) {
            if (frame.now >= self.strafe_until) {
                self.strafe_until = frame.now + 1200;
                self.strafe_side = -self.strafe_side;
            }
            if (try evasion.strafe(frame, pose.position, enemy_point, anchor, self.strafe_side, frame.now >= self.dodge_until, intent.arena, blocked)) |step| movement = step;
        };

        // Track a civilian standing in the way (not a companion).
        var in_the_way: u32 = 0;
        if (report.obstacle_id != 0) if (self.find(frame, report.obstacle_id)) |blocker| {
            if (blocker.get(data.Actor) catch null) |actor| if (catalog.entries[actor.definition].kind == .civilian) {
                in_the_way = report.obstacle_id;
            };
        };
        if (in_the_way == 0 or in_the_way != self.blocker) {
            self.blocker = in_the_way;
            self.blocker_ms = frame.now;
        } else if (frame.now - self.blocker_ms > 3000) self.nuisance = in_the_way;

        // View: use/shoot/look targets first, then a visible enemy, else travel.
        var aim = movement;
        var precise = false;
        var fighting = false;
        if (intent.face) |point| {
            aim = v.subtract(point, eye);
            precise = true;
        } else if (control_aim) |point| {
            const delta = v.subtract(point, eye);
            if (self.control.?.action == .shoot or v.length(delta) < 144) {
                aim = delta;
                precise = self.control.?.action != .touch;
            }
        }
        if (!precise) if (enemy) |seen| {
            // Lead a moving target by the selected weapon's projectile flight.
            var lead = enemy_point;
            const speed = frame.table.entries[selected].speed;
            if (speed > 0) if (seen.get(data.Velocity) catch null) |velocity| {
                lead = v.add(enemy_point, v.scale(velocity.linear, policy.lead * @min(@as(f32, 1), report.enemy_distance / speed)));
            };
            aim = v.subtract(lead, eye);
            fighting = true;
        };
        var sweep_offset: f32 = 0;
        var alert_view: ?f32 = null;
        if (!fighting and !precise and intent.view == null) {
            if (frame.capabilities.alert and frame.now < self.alert_until and self.alert_yaw != null) {
                alert_view = self.alert_yaw;
            } else if (intent.look_at) |point| {
                aim = v.subtract(point, eye);
            } else if (frame.capabilities.sweep) {
                // Nothing to look at directly: look around while walking, so an
                // enemy becomes visible instead of staying behind.
                if (frame.now >= self.sweep_until) {
                    self.sweep_until = frame.now + policy.scan_period_ms;
                    self.sweep_index = (self.sweep_index + 1) % sweep_headings.len;
                }
                sweep_offset = sweep_headings[self.sweep_index];
            } else if (intent.leash != null) {
                // Holding ground with nothing in view: sweep the surroundings.
                if (frame.now >= self.scan_until) {
                    self.scan_until = frame.now + 700;
                    self.scan_yaw = skill.wrap(pose.angles[1] + 75);
                }
                const radians = self.scan_yaw * std.math.pi / 180;
                aim = .{ @cos(radians), @sin(radians), 0 };
            }
        }
        if (v.length(aim) < 0.01) aim = facing;
        const step_ms: f32 = @floatFromInt(std.math.clamp(frame.now - self.step_ms, @as(i64, 1), 250));
        self.step_ms = frame.now;
        const limit = policy.turn_rate * step_ms / 1000;
        var wanted_yaw = skill.yaw(aim) + sweep_offset;
        var wanted_pitch = if (fighting or precise or intent.look_at != null) skill.pitch(aim) else 0;
        if (alert_view) |yaw| wanted_yaw = yaw;
        if (intent.view) |view| {
            wanted_yaw = view[0];
            wanted_pitch = view[1];
        }
        if (fighting) {
            if (frame.now >= self.wobble_ready) {
                self.wobble_ready = frame.now + policy.wobble_ms;
                self.noise_yaw = skill.noise(&self.seed);
                self.noise_pitch = skill.noise(&self.seed);
            }
            const settle = @min(@as(f32, 1), @as(f32, @floatFromInt(frame.now - self.locked_ms)) / @as(f32, @floatFromInt(policy.settle_ms)));
            wanted_yaw += self.noise_yaw * policy.aim_error * (1 - settle);
            wanted_pitch += self.noise_pitch * policy.aim_error * (1 - settle);
        }
        const angles: v.Vec3 = .{ skill.pitchTurn(pose.angles[0], wanted_pitch, limit), skill.turn(pose.angles[1], wanted_yaw, limit), 0 };
        command.angles = angles;
        const view_forward = v.basis(angles).forward;
        const centred = v.dot(view_forward, v.normalize(aim)) > 0.99;

        // Fire discipline: only once the view has settled on the lead point, so
        // ammunition is not spent while the view is still swinging round.
        var on_target = v.dot(view_forward, v.normalize(aim)) > policy.discipline;
        // A target lurching through water is not a settled shot: wait for it.
        if (enemy) |seen| if (try frame.collision.contents(enemy_point, frame.slot) & c.MASK_WATER != 0 or
            try frame.collision.contents(v.subtract(enemy_point, .{ 0, 0, 12 }), frame.slot) & c.MASK_WATER != 0)
        {
            if (seen.get(data.Velocity) catch null) |velocity| if (nav.horizontalDistance(velocity.linear, @splat(0)) > 40) {
                on_target = false;
            };
        };
        // A shot meeting something else right in front (a station, a pillar
        // beside the prey) comes back: bolts bounce and blasts splash. And a
        // bolt is a box: an edge a sight line just clears stops every shot.
        if (fighting) if (enemy) |seen| if (seen.get(data.Binding) catch null) |binding| {
            const lane = try frame.collision.trace(.{ .start = eye, .end = v.add(eye, v.scale(view_forward, @min(@as(f32, 96), report.enemy_distance))), .mins = @splat(0), .maxs = @splat(0), .slot = frame.slot, .mask = c.MASK_SHOT });
            if (on_target and !lineReaches(frame, lane, seen, binding.slot)) on_target = false;
            const line = try frame.collision.trace(.{ .start = eye, .end = enemy_point, .mins = @splat(-3), .maxs = @splat(3), .slot = frame.slot, .mask = @as(u32, c.MASK_SHOT) & ~@as(u32, c.CONTENTS_BODY) });
            if (!lineReaches(frame, line, seen, binding.slot)) {
                on_target = false;
                report.lane_blocked = true;
            }
            // A blast weapon's round is wider than a sight line: a door
            // frame or corner it clips within its own radius blows up on the
            // shooter.
            // It leaves from the muzzle, below the eye: up a slope the
            // floor rising between meets it (e1m4b's ramp), not the sight line.
            if (@import("weapon_catalog").find(@intCast(loadout.weapon))) |entry| if (entry.spec.splash_hazard) {
                const launch = @import("weapon_catalog").flightLaunch(@intCast(loadout.weapon), frame.table.entries[@intCast(loadout.weapon)], 0, 0);
                const muzzle = @import("../domain/combat.zig").muzzle(eye, angles, launch.muzzle);
                // Bodies count: another enemy stepping into the lane close by
                // takes the round as surely as a wall.
                const blast = try frame.collision.trace(.{ .start = muzzle, .end = enemy_point, .mins = @splat(-6), .maxs = @splat(6), .slot = frame.slot, .mask = c.MASK_SHOT });
                const near_self = v.length(v.subtract(blast.end, muzzle)) < entry.spec.projectile.splash_radius * 1.25;
                if (blast.start_solid or (blast.fraction < 1 and !lineReaches(frame, blast, seen, binding.slot) and (near_self or v.length(v.subtract(blast.end, enemy_point)) > 48))) {
                    on_target = false;
                    report.lane_blocked = true;
                }
            };
        };
        // Nobody of the party in the line of fire: the sight lane above sees
        // through bodies past arm's length, and a spread of pellets fans out.
        if (fighting) if (enemy != null) if (try allyInFire(frame, eye, enemy_point)) {
            on_target = false;
            report.lane_blocked = true;
        };
        if (intent.trigger and selected == loadout.weapon and loadout.weaponstate != 1 and loadout.weaponstate != 2) {
            command.attack = true;
            report.fired = true;
        }
        // Trigger discipline the caller asked for (a hurt companion falling
        // back still finishes what is nearly dead).
        const allowed = switch (intent.fire) {
            .free => true,
            .hold => false,
            .finish_only => if (enemy) |seen| if (seen.get(data.Health) catch null) |health| health.current <= finish_health else false else false,
        };
        if (fighting and engine.integer("developer") >= 3) {
            var text: [200]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&text, "dk3 {s} fire: t={d} target={d} distance={d:.0} on_target={d} lane_blocked={d} allowed={d} reserved={d} discharge={d} hold={d} selected={d} weapon={d} reaction={d} attack={d} ducked={d} hp={d}\n", .{ frame.label, frame.now, self.target, report.enemy_distance, @intFromBool(on_target), @intFromBool(report.lane_blocked), @intFromBool(allowed), @intFromBool(reserved), @intFromBool(discharge), @intFromBool(frame.now < self.hold_fire_until), selected, loadout.weapon, @intFromBool(frame.now >= self.reaction_ready), @intFromBool(combat.attack(loadout, frame.table, report.enemy_distance)), @intFromBool(player.ducked), if (world.get(entity, data.Health)) |health| health.current else |_| 0 }) catch "");
        }
        if (fighting and allowed and on_target and !reserved and !discharge and frame.now >= self.hold_fire_until and !player.respawned and selected == loadout.weapon and frame.now >= self.reaction_ready and frame.now >= self.shot_ready and combat.attack(loadout, frame.table, report.enemy_distance)) {
            command.attack = true;
            self.shot_ready = frame.now + policy.burst_ms;
            report.fired = true;
        }
        // Fire that does not hurt the target is ammunition thrown away.
        if (enemy) |seen| if (seen.get(data.Health) catch null) |health| {
            if (self.target != self.futile_target or health.current < self.futile_health) {
                self.futile_target = self.target;
                self.futile_health = health.current;
                self.futile_ms = frame.now;
                self.futile_shots = 0;
            }
            if (report.fired) self.futile_shots += 1;
            // A blast weapon's burst lands within a second: two rounds that
            // did not hurt it (bursting on a stair's edge short of it) tell.
            const blast = if (@import("weapon_catalog").find(@intCast(loadout.weapon))) |entry| entry.spec.splash_hazard else false;
            const futile_after: u32 = if (blast) 2 else 5;
            const futile_window: i64 = if (blast) 1500 else 3000;
            if (self.futile_shots >= futile_after and frame.now - self.futile_ms > futile_window) {
                // Another weapon that can reach it is tried first; only with
                // none is the target futile.
                var others = loadout;
                others.dk3Inventory &= ~(@as(i32, 1) << @intCast(loadout.weapon));
                if (self.spent_until <= frame.now and combat.rangedFor(others, frame.table, .{ .advancing = true })) {
                    self.spent_weapon = loadout.weapon;
                    self.spent_until = frame.now + 15000;
                    self.futile_ms = frame.now;
                    self.futile_shots = 0;
                } else {
                    report.futile = true;
                    self.hold_fire_until = frame.now + 2500;
                    self.futile_ms = frame.now;
                    self.futile_shots = 0;
                }
            }
        };
        var use_slot = intent.use_slot;
        var shoot_slot = intent.shoot_slot;
        if (self.control) |control| if (control_aim != null and precise) if (world.find(control.id)) |target| {
            const slot = (try world.get(target, data.Binding)).slot;
            if (control.action == .use) use_slot = slot;
            if (control.action == .shoot) shoot_slot = slot;
        };
        if (centred and (use_slot != null or shoot_slot != null)) {
            const reach: f32 = if (use_slot != null) 96 else @max(96, v.length(aim) + 8);
            // As the game's own use and shots trace: through trigger volumes
            // (a music trigger across a doorway, e1m4c).
            const hit = try frame.collision.trace(.{ .start = eye, .end = v.add(eye, v.scale(view_forward, reach)), .mins = @splat(0), .maxs = @splat(0), .slot = frame.slot, .mask = c.MASK_SHOT });
            if (use_slot) |slot| if (frame.capabilities.use and hit.entity == slot and frame.now >= self.use_ready) {
                self.use_ready = frame.now + 1000;
                report.used = true;
                report.used_slot = slot;
            };
            if (shoot_slot) |slot| if (hit.entity == slot and !discharge and !player.respawned and selected == loadout.weapon and combat.attack(loadout, frame.table, v.length(aim)) and try objectBlastSafe(frame, eye, angles, loadout.weapon, slot, v.add(eye, aim))) {
                command.attack = true;
                report.fired = true;
            };
        }

        // Locomotion follows the route heading, independent of where the view
        // points: player movement is applied relative to the view the command
        // carries, so the heading is resolved against that view (the yaw sent
        // this frame, still turning toward a look-at point or the travel way).
        const travel_yaw = angles[1];
        const axes = v.basis(.{ 0, travel_yaw, 0 });
        var direction = v.normalize(.{ movement[0], movement[1], 0 });
        if (frame.now < self.unstick_until) {
            const shaken = v.normalize(v.add(direction, v.scale(axes.right, self.unstick_side)));
            if (try evasion.supported(frame, pose.position, v.add(pose.position, v.scale(shaken, 40)))) direction = shaken else self.unstick_until = 0;
        }
        // Hazards overhead count against the hull the player moves with: a
        // crouch passes under a fan's guard a standing player would touch.
        const head: f32 = if (crouch or intent.crouch) 4 else frame.hull.maxs[2];
        // Under a lift that is moving close overhead (a raised platform
        // called down): step out of its shaft before it arrives.
        if (try crushOverhead(frame, pose.position)) |away| direction = away;
        // A current (a targetless push: a draught, a water flow) beside a drop
        // shoves whoever touches it over the edge: lean away from it while
        // going on, as a player keeps off it. Precise segments that steer
        // into a draught on purpose keep their line.
        if (!intent.direct and player.ground_entity != c.ENTITYNUM_NONE and v.length(direction) > 0.01) direction = try leanFromCurrents(frame, pose.position, direction);
        // Walking along a lethal volume (a floor fan's blades at the edge of
        // the way): keep a hand's breadth off it, as a player does.
        if (player.ground_entity != c.ENTITYNUM_NONE and v.length(direction) > 0.01) direction = try leanFromHazards(frame, pose.position, direction, head, nav.horizontalDistance(movement, @splat(0)));
        // The wide berth by lethal hazards is against knockback: in a fight.
        // Out of one, the route's own line along the edge (beside e1m4b's
        // floor fans) is walked.
        if (v.length(direction) > 0.01) report.avoided_exit = try avoidExits(frame, pose.position, direction, intent.exit, head, fighting, nav.horizontalDistance(movement, @splat(0)));
        // A stride into a wall slides along it: the way the player actually
        // goes must not run into an exit either (e1m3b's arrival ledge slides
        // along its wall into the way back to e1m3a).
        if (report.avoided_exit == 0 and v.length(direction) > 0.01) {
            const velocity = (try world.get(entity, data.Velocity)).linear;
            if (nav.horizontalDistance(velocity, @splat(0)) > 60) report.avoided_exit = try avoidExits(frame, pose.position, velocity, intent.exit, head, fighting, 40);
        }
        if (engine.integer("developer") >= 3) {
            var trace_text: [200]u8 = undefined;
            const velocity = (try world.get(entity, data.Velocity)).linear;
            engine.print(std.fmt.bufPrintZ(&trace_text, "dk3 {s} motor: t={d} pos={d:.0},{d:.0},{d:.0} direction={d:.2},{d:.2} vel={d:.0},{d:.0} avoided={d} yaw={d:.0} travel={d:.0} view={d:.0} fighting={d} crouch={d}\n", .{ frame.label, frame.now, pose.position[0], pose.position[1], pose.position[2], direction[0], direction[1], velocity[0], velocity[1], report.avoided_exit, pose.angles[1], travel_yaw, angles[1], @intFromBool(fighting), @intFromBool(crouch or intent.crouch) }) catch "");
        }
        if (report.avoided_exit != 0) {
            direction = @splat(0);
            self.unstick_until = 0;
            self.jump_until = 0;
        }
        // Precise straight steering brakes into its goal instead of overrunning it.
        var magnitude: f32 = 127 * intent.pace;
        if (intent.direct and intent.brake) if (intent.destination) |goal| {
            magnitude *= std.math.clamp(nav.horizontalDistance(pose.position, goal) / 96, 0.15, 1);
        };
        // Walking off a ledge onto a landing (beside a pit, say): step off
        // slowly, so the fall ends on the landing rather than past it.
        if (!intent.direct and player.ground_entity != c.ENTITYNUM_NONE) if (self.route.waypoint) |waypoint| if (waypoint.drop and nav.horizontalDistance(waypoint.point, pose.position) < 112) {
            magnitude *= 0.35;
        };
        // Narrow footing (a beam over a pit): where the floor a stride ahead
        // falls away while the way stays level, walk instead of running so a
        // turn does not carry the player off the edge. Precise segments keep
        // the route's own pace (their braking, a door's timed window).
        if (!intent.direct and player.ground_entity != c.ENTITYNUM_NONE and player.water_level < 2 and movement[2] > -18 and v.length(direction) > 0.01) {
            const stride = v.add(pose.position, v.scale(v.normalize(.{ direction[0], direction[1], 0 }), 24));
            const below = try frame.collision.trace(.{ .start = stride, .end = v.add(stride, .{ 0, 0, -64 }), .mins = @splat(0), .maxs = @splat(0), .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
            if (below.fraction == 1) magnitude *= 0.4;
        }
        command.forward = @intFromFloat(std.math.clamp(v.dot(direction, axes.forward) * magnitude, -127, 127));
        command.right = @intFromFloat(std.math.clamp(v.dot(direction, axes.right) * magnitude, -127, 127));
        if (crouch or intent.crouch) command.up = -127;
        // Standing to shoot, a player ducks where the target stays in sight
        // from down there.
        if (frame.capabilities.duck_to_shoot and fighting and enemy != null and !precise and player.ground_entity != c.ENTITYNUM_NONE and player.water_level < 2 and v.length(.{ direction[0], direction[1], 0 }) * magnitude < 64) {
            const low = v.add(pose.position, .{ 0, 0, -2 });
            const sight = try frame.collision.trace(.{ .start = low, .end = enemy_point, .mins = @splat(0), .maxs = @splat(0), .slot = frame.slot, .mask = @as(u32, c.MASK_SHOT) & ~@as(u32, c.CONTENTS_BODY) });
            if (sight.fraction == 1) command.up = -127;
        }
        if (frame.now < self.jump_until or intent.jump) command.up = 127;
        if (ladder and @abs(movement[2]) > 8) command.up = if (movement[2] > 0) 127 else -127;
        // Swimming: rise toward a higher goal, dive toward a deeper one (also
        // a waypoint more below than beside, such as the gap under a submerged
        // barrier), and otherwise keep the full stroke horizontal (vertical
        // input splits the swim speed, and a current then wins).
        if (player.water_level >= 2 and !ladder) {
            const across = nav.horizontalDistance(movement, @splat(0));
            if (movement[2] > 8) command.up = 127 else if (movement[2] < -48 or (movement[2] < -12 and across < -movement[2] * 2)) command.up = -127;
            // A ceiling edge ahead (the low gap of a flooded passage): where the
            // stroke is blocked at this depth but clear a little lower, dive.
            if (command.up >= 0 and across > 0.01) {
                const flat = v.normalize(.{ movement[0], movement[1], 0 });
                const hull_mins = frame.hull.mins;
                const hull_maxs = frame.hull.maxs;
                const level = try frame.collision.trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(flat, 24)), .mins = hull_mins, .maxs = hull_maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
                if (level.fraction < 1 and !level.start_solid) {
                    const lower = v.add(pose.position, .{ 0, 0, -16 });
                    const under = try frame.collision.trace(.{ .start = lower, .end = v.add(lower, v.scale(flat, 24)), .mins = hull_mins, .maxs = hull_maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
                    if (!under.start_solid and under.fraction == 1) command.up = -127;
                }
            }
        }
        // Under water the route's own depth is followed (tunnels and passages
        // under barriers); a player has twelve seconds of air, so after nine
        // the bot surfaces wherever air lies straight above. Under a ceiling
        // the stroke stays on the route: rising there only slows the swim out.
        if (player.water_level != 3) self.submerged_ms = frame.now;
        if (player.water_level == 3 and frame.now - self.submerged_ms > 9000 and try airAbove(frame, pose.position)) command.up = 127;
        command.use = report.used;
        return .{ .report = report, .command = command };
    }
    /// Route step with commitment: a chosen waypoint is followed until reached,
    /// blocked or 2.5 s old. Adjacent AAS areas can each route through the
    /// other's entrance; re-planning on every boundary crossing then oscillates.
    fn reachableNear(self: *Pilot, frame: Frame, position: v.Vec3, goal: v.Vec3, direct_radius: f32) !v.Vec3 {
        return reachableNearImpl(self, frame, position, goal, direct_radius);
    }
    fn follow(self: *Pilot, frame: Frame, position: v.Vec3, goal: v.Vec3) !?nav.Waypoint {
        const lifts = frame.now >= self.lifts_off_until;
        const fresh = try self.route.update(frame.service, .{ .position = position, .destination = goal, .slot = frame.slot, .player = true, .allow_slime_escape = true, .lifts = lifts }, frame.now);
        if (self.committed) |held| {
            const reached = v.length(v.subtract(position, held.point)) < 24;
            if (!reached and !self.route.blocked and frame.now < self.committed_until and v.length(v.subtract(held.point, goal)) <= v.length(v.subtract(position, goal)) + 256) return held;
        }
        var chosen = fresh;
        if (fresh) |waypoint| if (!waypoint.jump and !waypoint.crouch and !waypoint.ladder) {
            if (try lookAhead(frame, position, goal)) |far| chosen.?.point = far;
        };
        // Flipping back to the waypoint before last: aim at a point further
        // along the predicted route instead, beyond both entrances.
        if (chosen) |waypoint| if (self.previous_point) |before| if (self.committed) |current| {
            if (v.length(v.subtract(waypoint.point, before)) < 8 and v.length(v.subtract(current.point, waypoint.point)) > 8) {
                var points: [6]v.Vec3 = undefined;
                const count = try frame.service.predict(.{ .position = position, .destination = goal, .slot = frame.slot, .player = true, .allow_slime_escape = true, .lifts = lifts }, &points);
                var index = count;
                while (index > 0) {
                    index -= 1;
                    const point = points[index];
                    if (nav.horizontalDistance(point, position) < 40 or nav.horizontalDistance(point, position) > 256) continue;
                    if (v.length(v.subtract(point, waypoint.point)) < 8 or v.length(v.subtract(point, current.point)) < 8) continue;
                    if (@abs(point[2] - position[2]) > 20 or !try walkable(frame, position, point)) continue;
                    chosen.?.point = point;
                    break;
                }
            }
        };
        if (self.committed) |current| self.previous_point = current.point;
        self.committed = chosen;
        self.committed_until = frame.now + 2500;
        return chosen;
    }
    fn sidestep(self: *Pilot, frame: Frame, position: v.Vec3, movement: v.Vec3, report: *Report) !?v.Vec3 {
        const collision = frame.collision;
        const hull_mins = frame.hull.mins;
        const hull_maxs = frame.hull.maxs;
        const direction = v.normalize(.{ movement[0], movement[1], 0 });
        const ahead = try collision.trace(.{ .start = position, .end = v.add(position, v.scale(direction, 40)), .mins = hull_mins, .maxs = hull_maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
        if (ahead.fraction == 1 or ahead.start_solid or ahead.normal[2] >= 0.7) return null;
        report.obstacle = ahead.entity;
        const blocker = occupant(frame, ahead) orelse return null;
        report.obstacle_id = try blocker.id();
        // A closed or moving door is opened or waited for; one standing open
        // with a part still in the way (a sliding door's lip in the
        // doorway) is walked round once pressing on along it has stalled or
        // keeps circling the route's point by it (hops there are not
        // progress); a doorway the route threads exactly is slid through.
        if (blocker.get(data.Mover) catch null) |mover| {
            if (engine.integer("developer") >= 3) {
                var text: [160]u8 = undefined;
                engine.print(std.fmt.bufPrintZ(&text, "dk3 {s} sidestep mover: t={d} state={s} moving={d} blocked={d} hover_ms={d}\n", .{ frame.label, frame.now, @tagName(mover.state), @intFromBool(mover.moving()), @intFromBool(self.route.blocked), frame.now - self.hover_ms }) catch "");
            }
            if (mover.state != .open or mover.moving() or !(self.route.blocked or frame.now - self.hover_ms > 1500 or frame.now - self.direct_ms > 1500)) return null;
        }
        // The walls of a cart the player stands in are not walked around.
        if (ahead.world == 0 and ahead.entity == frame.state.ground_entity) return null;
        // A ledge the player can step onto is not an obstruction.
        const raised = v.add(position, .{ 0, 0, 18 });
        if ((try collision.trace(.{ .start = raised, .end = v.add(raised, v.scale(direction, 40)), .mins = hull_mins, .maxs = hull_maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID })).fraction == 1) return null;
        for ([_]f32{ 35, 70, 100 }) |degrees| for ([_]f32{ self.detour_side, -self.detour_side }) |side| {
            const angle = std.math.atan2(direction[1], direction[0]) + side * degrees * std.math.pi / 180;
            const turned: v.Vec3 = .{ @cos(angle), @sin(angle), 0 };
            const clear = try collision.trace(.{ .start = position, .end = v.add(position, v.scale(turned, 40)), .mins = hull_mins, .maxs = hull_maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
            if (clear.fraction < 1 or clear.start_solid) continue;
            if (!try evasion.supported(frame, position, v.add(position, v.scale(turned, 40)))) continue;
            self.detour_side = side;
            return v.scale(turned, v.length(.{ movement[0], movement[1], 0 }));
        };
        return null;
    }
};
/// Engagement choice: hostile actors inside the view cone (or close enough to
/// sense) with a clear shot line. A scripted kill target wins ties.
const Scan = struct {
    frame: Frame,
    intent: Intent,
    policy: skill.Profile,
    facing: v.Vec3,
    eye: v.Vec3,
    self_id: u32,
    target: u32,
    nuisance: u32,
    enemy: ?Ref = null,
    point: v.Vec3 = @splat(0),
    nearest: f32 = std.math.inf(f32),
    fn consider(self: *Scan, candidate: Ref) !void {
        const frame = self.frame;
        const intent = self.intent;
        const actor = (candidate.get(data.Actor) catch return).*;
        const health = (candidate.get(data.Health) catch return).*;
        const transform = (candidate.get(data.Transform) catch return).*;
        const binding = (candidate.get(data.Binding) catch return).*;
        const body = (candidate.get(data.Body) catch return).*;
        if (health.current <= 0) return;
        const kind = catalog.entries[actor.definition].kind;
        if (frame.capabilities.ignore_ambient and catalog.ambient(kind)) return;
        const identity = try candidate.id();
        // A civilian who has blocked a narrow passage for seconds is
        // dealt with as a player would; otherwise only hostiles.
        if (!route.hostile(kind) and (self.nuisance == 0 or identity != self.nuisance)) return;
        var point = v.add(transform.position, .{ 0, 0, (body.mins[2] + body.maxs[2]) * 0.5 });
        // Partly submerged bodies (wading Crox) are hit above the surface;
        // a shot at the centre only strikes the water.
        if (try frame.collision.contents(point, frame.slot) & c.MASK_WATER != 0) point[2] = transform.position[2] + body.maxs[2] - 2;
        var distance = v.length(v.subtract(point, self.eye));
        // Ammunition is finite: shoot what hunts this body (or the one it
        // guards), what is close, or what the route asked to kill; let the
        // rest be.
        const provoked = actor.threat == self.self_id or (intent.guard != 0 and actor.threat == intent.guard);
        if (distance > intent.engage_range and !provoked and identity != intent.preferred) return;
        if (!skill.sees(self.policy, self.facing, self.eye, point)) return;
        var trace = try frame.collision.trace(.{ .start = self.eye, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = frame.slot, .mask = c.MASK_SHOT });
        // Behind low cover (a worker at a console, a guard behind a
        // crate) the head may still be in the open: aim there.
        if (!lineReaches(frame, trace, candidate, binding.slot)) {
            point[2] = transform.position[2] + body.maxs[2] - 6;
            trace = try frame.collision.trace(.{ .start = self.eye, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = frame.slot, .mask = c.MASK_SHOT });
        }
        if (!lineReaches(frame, trace, candidate, binding.slot)) return;
        if (intent.preferred != 0 and identity == intent.preferred) distance *= 0.25;
        // Keep the current target unless another is clearly nearer:
        // switching on near ties swaps weapons instead of firing.
        if (identity == self.target) distance *= 0.6;
        if (distance >= self.nearest) return;
        self.nearest = distance;
        self.enemy = candidate;
        self.point = point;
    }
    fn considerPlayer(self: *Scan, candidate: Ref, session: data.Session) !void {
        return considerPlayerImpl(self, candidate, session);
    }
};
/// A match's enemy players: any living, non-spectating, non-allied client in
/// the cone and in sight, aimed at the chest. No unprovoked-range limit: the
/// ladder's sight range is the limit.
fn considerPlayerImpl(self: *Scan, candidate: Ref, session: data.Session) !void {
    const frame = self.frame;
    if ((candidate.get(data.Health) catch return).current <= 0) return;
    const member = (candidate.get(data.Session) catch return).*;
    if (member.team == .spectator or @import("../domain/multiplayer.zig").allied(session, member)) return;
    const point = v.add((try candidate.get(data.Transform)).position, .{ 0, 0, 12 });
    const distance = v.length(v.subtract(point, self.eye));
    if (distance >= self.nearest or !skill.sees(self.policy, self.facing, self.eye, point)) return;
    const binding = (candidate.get(data.Binding) catch return).*;
    const trace = try frame.collision.trace(.{ .start = self.eye, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = frame.slot, .mask = c.MASK_SHOT });
    if (!lineReaches(frame, trace, candidate, binding.slot)) return;
    self.nearest = distance;
    self.enemy = candidate;
    self.point = point;
}
/// Whether a line trace ended at `target` (or ran clear). A trace that crossed
/// into a neighbouring world names the slot there; a local one the slot here.
/// Whether a shot line runs clear from `eye` to the middle of `target`.
pub fn inSight(frame: Frame, eye: v.Vec3, target: Ref) !bool {
    const transform = (target.get(data.Transform) catch return false).*;
    const body = (target.get(data.Body) catch return false).*;
    const binding = (target.get(data.Binding) catch return false).*;
    const point = v.add(transform.position, .{ 0, 0, (body.mins[2] + body.maxs[2]) * 0.5 });
    const trace = try frame.collision.trace(.{ .start = eye, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = frame.slot, .mask = c.MASK_SHOT });
    return lineReaches(frame, trace, target, binding.slot);
}
/// A blast round fired at an object: its lane from the muzzle reaches the
/// object, and none of the party stands within its splash where it lands
/// (a bolt has no splash; a shot through a companion is caught by the
/// sight line).
fn objectBlastSafe(frame: Frame, eye: v.Vec3, angles: v.Vec3, weapon: i32, slot: u16, point: v.Vec3) !bool {
    const entry = @import("weapon_catalog").find(@intCast(weapon)) orelse return true;
    if (!entry.spec.splash_hazard) return true;
    const launch = @import("weapon_catalog").flightLaunch(@intCast(weapon), frame.table.entries[@intCast(weapon)], 0, 0);
    const muzzle = @import("../domain/combat.zig").muzzle(eye, angles, launch.muzzle);
    const blast = try frame.collision.trace(.{ .start = muzzle, .end = point, .mins = @splat(-6), .maxs = @splat(6), .slot = frame.slot, .mask = c.MASK_SHOT });
    if (blast.start_solid or (blast.fraction < 1 and blast.entity != slot and v.length(v.subtract(blast.end, point)) > 48)) return false;
    return !try allyNear(frame, blast.end, blast.end, entry.spec.projectile.splash_radius * 1.25);
}
/// Whether another of the party stands between the eye and the target,
/// within a widening cone about the line (a body's breadth, plus a spread).
fn allyInFire(frame: Frame, eye: v.Vec3, target: v.Vec3) !bool {
    const line = v.subtract(target, eye);
    const length = v.length(line);
    if (length < 1) return false;
    const direction = v.scale(line, 1 / length);
    for (frame.slots.occupants) |slot_entity| {
        const other = slot_entity orelse continue;
        if (other.index == frame.entity.index) continue;
        if ((frame.world.get(other, data.Player) catch null) == null and (frame.world.get(other, data.Companion) catch null) == null) continue;
        const health = frame.world.get(other, data.Health) catch continue;
        if (health.current <= 0) continue;
        const centre = v.add((frame.world.get(other, data.Transform) catch continue).position, .{ 0, 0, 8 });
        const along = v.dot(v.subtract(centre, eye), direction);
        if (along <= 0 or along >= length - 16) continue;
        const across = v.length(v.subtract(centre, v.add(eye, v.scale(direction, along))));
        if (across < 28 + along * 0.15) return true;
    }
    return false;
}
/// Whether another of the party (a player or a companion) stands within
/// `radius` of `to`, or within a stride of the line from `from` to it.
fn allyNear(frame: Frame, from: v.Vec3, to: v.Vec3, radius: f32) !bool {
    for (frame.slots.occupants) |slot_entity| {
        const other = slot_entity orelse continue;
        if (other.index == frame.entity.index) continue;
        if ((frame.world.get(other, data.Player) catch null) == null and (frame.world.get(other, data.Companion) catch null) == null) continue;
        const health = frame.world.get(other, data.Health) catch continue;
        if (health.current <= 0) continue;
        const at = (frame.world.get(other, data.Transform) catch continue).position;
        if (v.length(v.subtract(at, to)) < radius) return true;
        const line = v.subtract(to, from);
        const length = v.length(line);
        if (length < 1) continue;
        const along = std.math.clamp(v.dot(v.subtract(at, from), line) / (length * length), 0, 1);
        if (v.length(v.subtract(at, v.add(from, v.scale(line, along)))) < 48) return true;
    }
    return false;
}
fn lineReaches(frame: Frame, hit: collision_module.Trace, target: Ref, slot: u16) bool {
    const owner = if (hit.world == 0) frame.world else &(access.byHandle(@enumFromInt(hit.world)) orelse return false).world.?;
    if (owner != target.world) return false;
    return hit.fraction == 1 or hit.entity == slot;
}
fn claimed(frame: Frame, route_obstacle: u32) bool {
    const team = frame.coordination orelse return false;
    return team.claimed(team.context, route_obstacle);
}
/// What a probe hit, in whichever world the trace ended.
fn occupant(frame: Frame, hit: collision_module.Trace) ?Ref {
    if (frame.region) return access.victim(frame.world, frame.slots, hit);
    if (hit.entity >= frame.slots.occupants.len) return null;
    return .{ .world = frame.world, .entity = frame.slots.occupants[hit.entity] orelse return null };
}
/// The way out from under a moving lift whose underside is within 200 units
/// above the player's head (null when none threatens).
pub fn crushOverhead(frame: Frame, position: v.Vec3) !?v.Vec3 {
    var query = frame.world.queryAccess(data.World.mask(.{ data.MapObject, data.Binding }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Binding)) |entity, binding| {
        if (binding.slot >= frame.projections.len) continue;
        const moving = if (frame.world.get(entity, data.Train) catch null) |train| train.phase == .moving else if (frame.world.get(entity, data.Mover) catch null) |mover| !mover.angular and mover.moving() and @abs(mover.opened[2] - mover.closed[2]) > 32 else false;
        if (!moving) continue;
        const box = frame.projections[binding.slot].shared;
        const hull = frame.hull;
        if (position[0] + hull.maxs[0] <= box.absmin[0] or position[0] + hull.mins[0] >= box.absmax[0] or position[1] + hull.maxs[1] <= box.absmin[1] or position[1] + hull.mins[1] >= box.absmax[1]) continue;
        const gap = box.absmin[2] - (position[2] + hull.maxs[2]);
        if (gap < 0 or gap > 200) continue;
        // Out toward the nearest side of its footprint.
        const centre = v.scale(v.add(box.absmin, box.absmax), 0.5);
        var out: v.Vec3 = .{ position[0] - centre[0], position[1] - centre[1], 0 };
        if (v.length(out) < 1) out = .{ 1, 0, 0 };
        return v.normalize(out);
    };
    return null;
}
/// `direction` bent away from an active current within reach whose push would
/// carry the player over a drop.
fn leanFromCurrents(frame: Frame, position: v.Vec3, direction: v.Vec3) !v.Vec3 {
    var bias: v.Vec3 = @splat(0);
    var controls = frame.world.queryAccess(data.World.mask(.{ data.WorldControl, data.Binding }), 0, 0);
    defer controls.deinit();
    while (controls.next()) |view| for (view.read(data.WorldControl), view.read(data.Binding)) |control, binding| {
        const push = switch (control.action) {
            .push => |value| value,
            else => continue,
        };
        const flat: v.Vec3 = .{ push.velocity[0], push.velocity[1], 0 };
        if (!push.enabled or v.length(flat) < 1 or binding.slot >= frame.projections.len) continue;
        const box = frame.projections[binding.slot].shared;
        // Within a stride of the hull's edge, at the height the hull spans.
        const reach: f32 = frame.hull.maxs[0] + 24;
        if (position[0] < box.absmin[0] - reach or position[0] > box.absmax[0] + reach or position[1] < box.absmin[1] - reach or position[1] > box.absmax[1] + reach) continue;
        if (position[2] + frame.hull.maxs[2] < box.absmin[2] or position[2] + frame.hull.mins[2] > box.absmax[2]) continue;
        const along = v.normalize(flat);
        const centre = v.scale(v.add(box.absmin, box.absmax), 0.5);
        const beyond = v.add(.{ centre[0], centre[1], position[2] }, v.scale(along, 64));
        const floor = try frame.collision.trace(.{ .start = beyond, .end = v.add(beyond, .{ 0, 0, -96 }), .mins = @splat(0), .maxs = @splat(0), .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
        if (floor.fraction < 1) continue;
        bias = v.subtract(bias, along);
    };
    if (v.length(bias) < 0.01) return direction;
    const ahead = v.normalize(.{ direction[0], direction[1], 0 });
    // Keep the way's own heading but never toward the current.
    const toward = v.dot(ahead, v.scale(bias, -1));
    var bent = if (toward > 0) v.subtract(ahead, v.scale(v.normalize(v.scale(bias, -1)), toward)) else ahead;
    bent = v.add(bent, v.scale(v.normalize(bias), 0.35));
    return v.scale(v.normalize(bent), v.length(.{ direction[0], direction[1], 0 }));
}
/// Bends a heading away from an enabled lethal hazard the hull runs within a
/// few units of, keeping the way's own progress.
/// `extent`: how far the heading goes before the route turns.
fn leanFromHazards(frame: Frame, position: v.Vec3, direction: v.Vec3, head: f32, extent: f32) !v.Vec3 {
    var bias: v.Vec3 = @splat(0);
    var hazards = frame.world.queryAccess(data.World.mask(.{ data.Hazard, data.Binding }), 0, 0);
    defer hazards.deinit();
    while (hazards.next()) |view| for (view.read(data.Hazard), view.read(data.Binding)) |hazard, binding| {
        if (!hazard.enabled or hazard.damage < 100 or hazard.damage < frame.hazard_damage or binding.slot >= frame.projections.len) continue;
        const box = frame.projections[binding.slot].shared;
        if (box.linked == 0) continue;
        if (position[2] + head < box.absmin[2] or position[2] + frame.hull.mins[2] > box.absmax[2]) continue;
        // Here, or a stride on (passing the volume's corner).
        const stride = v.add(position, v.scale(v.normalize(.{ direction[0], direction[1], 0 }), @min(extent, 32)));
        const at = if (clearance(frame, binding.slot, stride) < clearance(frame, binding.slot, position)) stride else position;
        if (clearance(frame, binding.slot, at) >= 12) continue;
        // Away from the nearest point of the volume.
        const nearest: v.Vec3 = .{ std.math.clamp(at[0], box.absmin[0], box.absmax[0]), std.math.clamp(at[1], box.absmin[1], box.absmax[1]), at[2] };
        const away: v.Vec3 = .{ at[0] - nearest[0], at[1] - nearest[1], 0 };
        if (v.length(away) < 0.01) continue;
        bias = v.add(bias, v.normalize(away));
    };
    if (v.length(bias) < 0.01) return direction;
    const ahead = v.normalize(.{ direction[0], direction[1], 0 });
    const outward = v.normalize(bias);
    // No component toward the volume; a small one away from it. Heading
    // straight in is left to the stride check (it stops short).
    const toward = v.dot(ahead, v.scale(outward, -1));
    if (toward > 0.8) return direction;
    var bent = if (toward > 0) v.add(ahead, v.scale(outward, toward)) else ahead;
    bent = v.add(bent, v.scale(outward, 0.4));
    if (!try evasion.supportedUnder(frame, position, v.add(position, v.scale(v.normalize(bent), 40)), head)) return direction;
    return v.scale(v.normalize(bent), v.length(.{ direction[0], direction[1], 0 }));
}
/// An actor (not geometry or a mover) right ahead of the player's stride.
fn actorAhead(frame: Frame, position: v.Vec3, movement: v.Vec3) !bool {
    const flat: v.Vec3 = .{ movement[0], movement[1], 0 };
    if (v.length(flat) < 0.01) return false;
    const ahead = try frame.collision.trace(.{ .start = position, .end = v.add(position, v.scale(v.normalize(flat), 40)), .mins = frame.hull.mins, .maxs = frame.hull.maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
    if (ahead.fraction == 1 or ahead.start_solid) return false;
    const blocker = occupant(frame, ahead) orelse return false;
    return (blocker.get(data.Actor) catch null) != null;
}
/// The furthest of the route's next few points the player can walk to in a
/// straight line (clear hull sweep, level, floor all the way), so the bot
/// cuts corners the area graph's entrance points would make it turn at. On
/// a ledge split lengthwise into two thin areas, each routes through the
/// other's entrance far behind; walking straight to the point beyond both
/// stops the bot turning back and forth between them.
fn lookAhead(frame: Frame, position: v.Vec3, goal: v.Vec3) !?v.Vec3 {
    const player = frame.state;
    if (player.ground_entity == c.ENTITYNUM_NONE or player.water_level >= 2) return null;
    var points: [6]v.Vec3 = undefined;
    const count = try frame.service.predict(.{ .position = position, .destination = goal, .slot = frame.slot, .player = true, .allow_slime_escape = true }, &points);
    var index = count;
    while (index > 0) {
        index -= 1;
        const point = points[index];
        if (nav.horizontalDistance(point, position) > 256 or nav.horizontalDistance(point, position) < 24 or @abs(point[2] - position[2]) > 20) continue;
        if (try walkable(frame, position, point)) return point;
    }
    return null;
}
/// A straight walk with no gap, drop, steep slope or new liquid along it:
/// the hull sweeps clear at stepping height and finds level floor every
/// 16 units, never more than a step below the line.
pub fn walkable(frame: Frame, from: v.Vec3, to: v.Vec3) !bool {
    const collision = frame.collision;
    const mins = frame.hull.mins;
    const maxs = frame.hull.maxs;
    const lift: v.Vec3 = .{ 0, 0, 18 };
    const sweep = try collision.trace(.{ .start = v.add(from, lift), .end = v.add(to, lift), .mins = mins, .maxs = maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
    if (sweep.start_solid or sweep.fraction < 1) return false;
    const wading = try collision.contents(v.add(from, .{ 0, 0, mins[2] + 1 }), frame.slot) & c.MASK_WATER != 0;
    const harmful: u32 = @as(u32, c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO) | (if (wading) 0 else @as(u32, c.CONTENTS_WATER));
    const length = nav.horizontalDistance(from, to);
    const samples: usize = @max(1, @as(usize, @intFromFloat(@ceil(length / 16))));
    for (1..samples + 1) |sample| {
        const point = v.add(v.add(from, v.scale(v.subtract(to, from), @as(f32, @floatFromInt(sample)) / @as(f32, @floatFromInt(samples)))), lift);
        const floor = try collision.trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -40 }), .mins = mins, .maxs = maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
        if (floor.fraction == 1 or floor.normal[2] < 0.7) return false;
        if (try collision.contents(v.add(floor.end, .{ 0, 0, mins[2] + 1 }), frame.slot) & harmful != 0) return false;
    }
    return true;
}
/// Whether a shot from `eye` would meet water within an ion discharge's reach
/// (64 units) of the shooter at `origin`: the eye under water, or the line's
/// first water close by.
fn waterNear(frame: Frame, eye: v.Vec3, origin: v.Vec3, aim: ?v.Vec3) !bool {
    const collision = frame.collision;
    if (try collision.contents(eye, frame.slot) & c.MASK_WATER != 0) return true;
    const point = aim orelse return false;
    const direction = v.normalize(v.subtract(point, eye));
    const span = @min(v.length(v.subtract(point, eye)), 128);
    var along: f32 = 8;
    while (along <= span) : (along += 8) {
        const sample = v.add(eye, v.scale(direction, along));
        if (try collision.contents(sample, frame.slot) & c.MASK_WATER != 0) return v.length(v.subtract(sample, origin)) < 64;
    }
    return false;
}
/// Whether a submerged player rising straight up would get its head out of
/// the water within a short climb.
fn airAbove(frame: Frame, position: v.Vec3) !bool {
    const collision = frame.collision;
    const rise = try collision.trace(.{ .start = position, .end = v.add(position, .{ 0, 0, 160 }), .mins = frame.hull.mins, .maxs = frame.hull.maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
    return try collision.contents(v.add(rise.end, .{ 0, 0, frame.state.view_height }), frame.slot) & c.MASK_WATER == 0;
}
/// Outward normal of a ladder surface touching the player hull, if any (the
/// same four-way probe the movement code uses to start climbing).
fn climbable(frame: Frame, position: v.Vec3) !?v.Vec3 {
    for (0..4) |axis| {
        var direction: v.Vec3 = @splat(0);
        direction[axis / 2] = if (axis & 1 == 0) 1 else -1;
        const hit = try frame.collision.trace(.{ .start = position, .end = v.add(position, v.scale(direction, 4)), .mins = frame.hull.mins, .maxs = frame.hull.maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
        if (hit.fraction < 1 and hit.ladder and @abs(hit.normal[2]) < 0.5) return hit.normal;
    }
    return null;
}
/// `goal`, or when the area graph has no route there but the last stretch
/// can be walked straight (within `direct_radius`), the nearest point within
/// 96 units of it that the graph does reach.
fn reachableNearImpl(self: *Pilot, frame: Frame, position: v.Vec3, goal: v.Vec3, direct_radius: f32) !v.Vec3 {
    if (direct_radius < 96) return goal;
    // There already: the last stretch is walked straight (routing to the goal
    // fails, and the caller steers at it directly).
    if (v.length(v.subtract(goal, self.near_goal)) < 1) if (self.near_point) |point| if (nav.horizontalDistance(position, point) < 32) return goal;
    if (v.length(v.subtract(goal, self.near_goal)) < 1 and frame.now - self.near_ms < 3000) return self.near_point orelse goal;
    self.near_goal = goal;
    self.near_ms = frame.now;
    self.near_point = null;
    if (try frame.service.next(.{ .position = position, .destination = goal, .slot = frame.slot, .player = true }) != null) return goal;
    // Nearest the goal first, and only where the last stretch to it is a
    // supported straight walk (not the far side of a wall).
    const hull = (try frame.world.get(frame.entity, data.Body)).*;
    for ([_]f32{ 32, 64, 96 }) |radius| {
        var best: ?v.Vec3 = null;
        var shortest: f32 = std.math.inf(f32);
        for (0..8) |heading| {
            const angle = @as(f32, @floatFromInt(heading)) * std.math.pi / 4;
            const candidate = v.add(goal, .{ @cos(angle) * radius, @sin(angle) * radius, 0 });
            if (try frame.service.next(.{ .position = position, .destination = candidate, .slot = frame.slot, .player = true }) == null) continue;
            // Raised a little: goal points sit on the floor plane.
            // The goal itself may be pressed against a console (a touch
            // volume's middle): the walk need only end a hull short of it.
            const lift: v.Vec3 = .{ 0, 0, 8 };
            const short = v.add(goal, v.scale(v.normalize(.{ candidate[0] - goal[0], candidate[1] - goal[1], 0 }), 16));
            if (try steering.walkPath(frame.collision, .{ .start = v.add(candidate, lift), .end = v.add(short, lift), .mins = hull.mins, .maxs = hull.maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID }, c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO, &.{}) == null) continue;
            const span = v.length(v.subtract(candidate, position));
            if (span >= shortest) continue;
            shortest = span;
            best = candidate;
        }
        if (best) |point| {
            self.near_point = point;
            return point;
        }
    }
    return goal;
}
/// Persistent id of a volume the next stride must not enter: a campaign exit
/// other than the targeted one, or an enabled hazard harmful enough to kill
/// (laser barriers and crushers are authored as hurt triggers).
/// `extent`: how far the stride goes before turning (the route's next corner):
/// a hazard past the corner is not walked into.
fn avoidExits(frame: Frame, position: v.Vec3, movement: v.Vec3, allowed: u32, head: f32, wary: bool, extent: f32) !u32 {
    const stride = v.add(position, v.scale(v.normalize(.{ movement[0], movement[1], 0 }), 40));
    // A running player needs room to stop: look as far ahead as its speed
    // carries it, at a few points so a thin exit is not stepped over.
    const speed = nav.horizontalDistance((try frame.world.get(frame.entity, data.Velocity)).linear, @splat(0));
    const reach = @max(@as(f32, 40), speed * 0.3 + 24);
    var exits = frame.world.queryAccess(data.World.mask(.{ data.Exit, data.Binding }), 0, 0);
    defer exits.deinit();
    while (frame.capabilities.exits) {
        const view = exits.next() orelse break;
        for (view.entities(), view.read(data.Binding)) |entity, binding| {
            const id = try frame.world.persistentId(entity);
            if (id == allowed) continue;
            for ([_]f32{ 0.34, 0.67, 1 }) |part| {
                const ahead = v.add(position, v.scale(v.normalize(.{ movement[0], movement[1], 0 }), reach * part));
                if (enteringWithin(frame, binding.slot, position, ahead, 0, head)) return id;
            }
        }
    }
    // Harmful liquids are authored as brush contents, not entities: never step
    // from dry ground into slime, lava or nitro.
    const harmful = c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO;
    const collision = frame.collision;
    const feet = frame.hull.mins[2] + 1;
    if (try collision.contents(v.add(position, .{ 0, 0, feet }), frame.slot) & harmful == 0) {
        const floor = try collision.trace(.{ .start = stride, .end = v.add(stride, .{ 0, 0, -64 }), .mins = frame.hull.mins, .maxs = frame.hull.maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
        if (try collision.contents(v.add(floor.end, .{ 0, 0, feet }), frame.slot) & harmful != 0) return std.math.maxInt(u32);
    }
    const step = v.add(position, v.scale(v.normalize(.{ movement[0], movement[1], 0 }), std.math.clamp(extent, 16, 40)));
    var hazards = frame.world.queryAccess(data.World.mask(.{ data.Hazard, data.Binding }), 0, 0);
    defer hazards.deinit();
    while (hazards.next()) |view| for (view.entities(), view.read(data.Hazard), view.read(data.Binding)) |entity, hazard, binding| {
        // Lethal brushes (laser barriers, crushers) keep a margin across
        // against knockback.
        const margin: f32 = if (hazard.damage >= 100) (if (wary) frame.lethal_margin else @min(frame.lethal_margin, 8)) else 0;
        if (hazard.enabled and hazard.damage >= frame.hazard_damage and closesOn(frame, binding.slot, position, step, margin, head)) return try frame.world.persistentId(entity);
    };
    return 0;
}
/// The owned melee weapon with the most damage, if any.
fn melee(loadout: data.Weapons, frame: Frame, excluded: i32) ?u5 {
    var best: ?u5 = null;
    var damage: f32 = 0;
    for (@import("weapon_catalog").entries) |entry| {
        if (loadout.dk3Inventory & (@as(i32, 1) << entry.id) == 0 or !entry.spec.auto_select or excluded & (@as(i32, 1) << entry.id) != 0) continue;
        if (weaponReach(frame, entry.id) >= 160) continue;
        const tuning = frame.table.entries[entry.id];
        if (tuning.damage <= damage or loadout.ammo[entry.id] < tuning.ammoCost) continue;
        damage = tuning.damage;
        best = entry.id;
    }
    return best;
}
fn weaponReach(frame: Frame, weapon: u5) f32 {
    const entry = @import("weapon_catalog").find(weapon) orelse return 0;
    return entry.spec.bot_range orelse frame.table.entries[weapon].range;
}
fn blocked(frame: Frame, position: v.Vec3, step: v.Vec3) anyerror!bool {
    return try avoidExits(frame, position, step, 0, frame.hull.maxs[2], true, 40) != 0;
}
/// Whether a body standing at `point` would be inside an enabled hazard
/// volume harmful enough for this frame to avoid.
pub fn insideHazard(frame: Frame, point: v.Vec3) !bool {
    var hazards = frame.world.queryAccess(data.World.mask(.{ data.Hazard, data.Binding }), 0, 0);
    defer hazards.deinit();
    while (hazards.next()) |view| for (view.read(data.Hazard), view.read(data.Binding)) |hazard, binding| {
        if (!hazard.enabled or hazard.damage < frame.hazard_damage or binding.slot >= frame.projections.len) continue;
        const box = frame.projections[binding.slot].shared;
        if (box.linked == 0) continue;
        const margin: v.Vec3 = if (hazard.damage >= 100) .{ 48, 48, 0 } else @splat(0);
        if (route.overlaps(point, frame.hull.mins, frame.hull.maxs, v.subtract(box.absmin, margin), v.add(box.absmax, margin))) return true;
    };
    return false;
}
/// A step into a hazard volume, or within `margin` of it while getting
/// closer: walking alongside a laser at a safe distance is no approach.
fn closesOn(frame: Frame, slot: u16, position: v.Vec3, stride: v.Vec3, margin: f32, head: f32) bool {
    if (enteringWithin(frame, slot, position, stride, 0, head)) return true;
    if (margin == 0 or !enteringWithin(frame, slot, position, stride, margin, head)) return false;
    return clearance(frame, slot, stride) < clearance(frame, slot, position) - 1;
}
/// Horizontal clearance between the body's hull at `position` and a volume.
fn clearance(frame: Frame, slot: u16, position: v.Vec3) f32 {
    const box = frame.projections[slot].shared;
    var squared: f32 = 0;
    for (0..2) |axis| {
        const low = position[axis] + frame.hull.mins[axis];
        const high = position[axis] + frame.hull.maxs[axis];
        const outside = @max(box.absmin[axis] - high, low - box.absmax[axis], 0);
        squared += outside * outside;
    }
    return @sqrt(squared);
}
fn enteringWithin(frame: Frame, slot: u16, position: v.Vec3, stride: v.Vec3, margin: f32, head: f32) bool {
    if (slot >= frame.projections.len) return false;
    const box = frame.projections[slot].shared;
    if (box.linked == 0) return false;
    const pad: v.Vec3 = .{ margin, margin, 0 };
    const mins = v.subtract(box.absmin, pad);
    const maxs = v.add(box.absmax, pad);
    const hull_mins = frame.hull.mins;
    const hull_maxs: v.Vec3 = .{ frame.hull.maxs[0], frame.hull.maxs[1], head };
    return route.overlaps(stride, hull_mins, hull_maxs, mins, maxs) and
        !route.overlaps(position, hull_mins, hull_maxs, mins, maxs);
}
