#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Isolated native client/movement probe; does not certify campaign acceptance."""
import argparse
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

from runtime_probe import send, wait, stage_client_modules, client_settings


def movement_scenario(args, issue, capture, log):
    issue("viewpos")
    capture("standing")
    issue("+forward", 1)
    issue("-forward")
    issue("viewpos")
    issue("+movedown", 0.5)
    capture("crouching")
    issue("-movedown")
    issue("+moveup", 0.3)
    issue("-moveup", 1)
    issue("viewpos")
    if args.mover is not None:
        issue(f"dk3_runtime_activate {args.mover}", 0.25)
        issue("dk3_runtime_movers", 0.05)
        issue(f"dk3_runtime_activate {args.mover}", 0.25)
        issue("dk3_runtime_movers", 2)
        issue("dk3_runtime_movers", 4)
        issue("dk3_runtime_movers")
    text = log.read_text(errors="replace")
    positions = re.findall(r"zig viewpos: ([^\n]+)", text)
    if len(positions) != 3:
        raise RuntimeError(f"missing movement diagnostics: {log}")
    if args.mover is not None:
        states = re.findall(rf"zig mover id={args.mover} .*state=(\w+)", text)
        if len(states) != 4 or states[:2] != ["opening", "opening"] or states[-1] != "open":
            raise RuntimeError(f"unexpected repeated activation/delayed arrival: {states}")
    return {"positions": positions, "scope": "native connection and movement diagnostics; authored gameplay unqualified"}


def lift_scenario(issue, capture, log):
    # Valid standing position from the existing recorded lift regression; no save is modified.
    issue("dk3_runtime_place 818.916 -479.481 -823.875", 0.5)
    issue("viewpos")
    capture("lift-bottom")
    issue("dk3_runtime_activate 3", 0.25)
    issue("dk3_runtime_activate 3", 0.25)
    samples = []
    top_captured = False
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        issue("dk3_runtime_trains", 0.05)
        issue("viewpos", 0.05)
        issue("dk3_runtime_status", 0.2)
        text = log.read_text(errors="replace")
        lines = re.findall(r"zig train id=3 name=bigplat ([^\n]+)", text)
        if not lines:
            raise RuntimeError("bigplat diagnostics missing")
        fields = dict(re.findall(r"(\w+)=([^ ]+)", lines[-1]))
        positions = re.findall(r"zig viewpos: ([^,]+),", text)
        times = re.findall(r"dk3 zig: entities=\d+ frames=\d+ time=(\d+)", text)
        sample = {"phase": fields["phase"], "wait": int(fields["wait"]),
                  "due": None if fields["due"] == "null" else int(fields["due"]),
                  "train_z": float(fields["pos"].split(",")[2]),
                  "player_z": float(positions[-1].split()[2]), "time": int(times[-1])}
        samples.append(sample)
        if sample["phase"] == "dwelling" and not top_captured:
            capture("lift-top")
            top_captured = True
        if top_captured and sample["phase"] == "paused":
            break
    (log.parent / "lift-samples.json").write_text(json.dumps(samples, indent=2) + "\n")
    top = [sample for sample in samples if sample["phase"] == "dwelling"]
    if not top or any(abs(sample["train_z"] + 274) > 0.01 or sample["wait"] != 10000 for sample in top):
        raise RuntimeError("lift did not reach the authored upper dwell")
    if len({sample["due"] for sample in top}) != 1 or top[-1]["time"] - top[0]["time"] < 9000:
        raise RuntimeError("lift returned before its ten-second dwell")
    if samples[-1]["phase"] != "paused" or abs(samples[-1]["train_z"] + 902) > 0.01:
        raise RuntimeError("lift did not return to trigger-only lower rest")
    if max(sample["player_z"] for sample in samples) - samples[-1]["player_z"] < 500:
        raise RuntimeError("rider was not carried to the upper stop")
    capture("lift-returned")
    return {"samples": len(samples), "scope": "e1m3a lift ride, departure dwell and return; diagnostic activation, not full campaign acceptance"}


def special_scenario(args, issue, capture, log):
    identity = 43 if args.scenario == "secret" else 72

    def sample():
        issue("dk3_runtime_special", 0.4)
        values = re.findall(rf"zig special id={identity} phase=(\w+) pos=([^\n]+) angles=([^\n]+)", log.read_text(errors="replace"))
        if not values:
            raise RuntimeError("special mover diagnostics missing")
        return values[-1]

    if args.scenario == "secret":
        issue(f"dk3_runtime_activate {identity}")
        phases = []
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            phases.append(sample()[0])
            if "open" in phases and phases[-1] == "closed":
                break
        if not all(phase in phases for phase in ("waiting_first", "open", "waiting_return")) or phases[-1] != "closed":
            raise RuntimeError(f"incomplete secret-door cycle: {phases}")
        return {"phases": phases, "scope": "e3dm1 secret-door cycle; diagnostic activation, shoot activation unqualified"}
    first, second = sample(), sample()
    if first[0] != "rotating" or second[0] != "rotating" or first[2] == second[2]:
        raise RuntimeError("authored rotation did not start")
    issue(f"dk3_runtime_activate {identity}")
    stopped, held = sample(), sample()
    if stopped != held or stopped[0] != "stopped":
        raise RuntimeError("rotation failed to remain stopped")
    issue(f"dk3_runtime_activate {identity}")
    resumed, moving = sample(), sample()
    if resumed[0] != "rotating" or moving[0] != "rotating" or resumed[2] == moving[2]:
        raise RuntimeError("rotation did not resume")
    return {"samples": [first, second, stopped, held, resumed, moving],
            "scope": "e1m3b rotating brush start, toggle and resume; rotating riders unqualified"}


def inventory_scenario(issue, capture, log):
    def mover_state(identity):
        issue("dk3_runtime_movers")
        states = re.findall(rf"zig mover id={identity} .*state=(\w+)", log.read_text(errors="replace"))
        if not states:
            raise RuntimeError(f"missing mover {identity}")
        return states[-1]

    issue("dk3_runtime_activate 85 player", 0.5)
    if mover_state(85) != "closed":
        raise RuntimeError("key-locked button opened without key")
    issue("dk3_runtime_items")
    text = log.read_text(errors="replace")
    values = re.findall(r"zig item id=2 class=item_control_card_blue visible=(\d) ground=(\w+) pos=([^\n]+)", text)
    if not values or values[-1][0] != "1" or values[-1][1] == "null":
        raise RuntimeError("key did not settle on the floor")
    x, y, z = map(float, values[-1][2].split(","))
    issue(f"dk3_runtime_place {x + 80} {y} {z + 24}", 0.2)
    issue("dk3_look 180 15")
    capture("key-before")
    issue(f"dk3_runtime_place {x} {y} {z + 24}", 0.5)
    issue("dk3_runtime_inventory")
    issue("dk3_runtime_items")
    text = log.read_text(errors="replace")
    keys = re.findall(r"zig inventory keys=([0-9a-f]+)", text)
    if not keys or int(keys[-1], 16) & (1 << 0) == 0:
        raise RuntimeError("touch failed to collect blue keycard")
    if not re.search(r"zig item id=2 class=item_control_card_blue visible=0", text):
        raise RuntimeError("collected key remained visible")
    issue("dk3_runtime_activate 85 player", 0.3)
    state = mover_state(85)
    if state not in ("opening", "open"):
        raise RuntimeError("collected key did not unlock button")
    issue("dk3_runtime_items", 1)
    if mover_state(82) not in ("opening", "open"):
        raise RuntimeError("button arrival failed to activate four-way door")
    capture("key-collected")
    return {"keys": keys[-1], "button_state": state,
            "scope": "e1m6a key floor settlement, touch pickup and locked button target; diagnostic positioning, full authored progression unqualified"}


def effects_scenario(issue, capture, log):
    issue("set developer 1")

    def collect(identity, classname):
        issue("dk3_runtime_items")
        values = re.findall(rf"zig item id={identity} class={classname} visible=(\d) ground=(\w+) pos=([^\n]+)", log.read_text(errors="replace"))
        if not values or values[-1][0] != "1" or values[-1][1] == "null":
            raise RuntimeError(f"pickup {identity} missing or not settled")
        x, y, z = map(float, values[-1][2].split(","))
        issue(f"dk3_runtime_place {x} {y} {z + 24}", 0.5)
        issue("dk3_runtime_items")
        if not re.search(rf"zig item id={identity} class={classname} visible=0", log.read_text(errors="replace")):
            raise RuntimeError(f"pickup {identity} not collected")

    def character():
        issue("dk3_runtime_character")
        lines = re.findall(r"zig character ([^\n]+)", log.read_text(errors="replace"))
        return {key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", lines[-1])}

    collect(320, "item_speed_boost")
    boosted = character()
    if boosted["speed"] != 1 or not 28000 <= boosted["boost_until"] - boosted["time"] <= 30000:
        raise RuntimeError("speed boost did not apply for thirty seconds")
    collect(14, "item_invincibility")
    protected = character()
    issue("dk3_runtime_damage 40")
    if not re.search(r"zig damage blood=0 armor=0 killed=0", log.read_text(errors="replace")):
        raise RuntimeError("invincibility failed to protect the player")
    deadline = time.monotonic() + 40
    samples = []
    while time.monotonic() < deadline:
        current = character()
        samples.append(current)
        if current["time"] >= max(protected["invincible"], boosted["boost_until"]):
            break
        issue("dk3_runtime_status", 1)
    if samples[-1]["speed"] != 0 or samples[-1]["time"] < protected["invincible"]:
        raise RuntimeError("timed pickups failed to expire")
    issue("dk3_runtime_damage 40")
    damage = re.findall(r"zig damage blood=(\d+) armor=(\d+)", log.read_text(errors="replace"))
    if not damage or int(damage[-1][0]) <= 0:
        raise RuntimeError("expired protection still blocked damage")
    text = log.read_text(errors="replace")
    sounds = text.count("dk3 zig: snapshot sound dispatched")
    if sounds < 2 or "could not find sounds/" in text.lower():
        raise RuntimeError("pickup sound assets/dispatch missing")
    capture("effects-expired")
    return {"boosted": boosted, "protected": protected, "expired": samples[-1], "sound_events": sounds,
            "scope": "e4m4b pickup timers, protection and snapshot audio dispatch; diagnostic positioning/damage, physical audio and combat parity unqualified"}


def combat_scenario(issue, capture, log):
    issue("developer 1")
    results = []
    for weapon in (21, 2, 4, 22, 23):
        issue("dk3_runtime_clear_targets")
        issue(f"dk3_runtime_equip {weapon}")
        issue("dk3_runtime_target")
        issue("dk3_runtime_targets")
        before = len(log.read_text(errors="replace"))
        issue("+attack", 4)
        issue("-attack", 0.3)
        issue("dk3_runtime_targets")
        text = log.read_text(errors="replace")[before:]
        health = re.findall(r"zig combat: target=(\d+) health=(-?\d+)", text)
        if not health or int(health[-1][1]) > 0 or "killed=1" not in text:
            raise RuntimeError(f"weapon {weapon} did not kill target through normal attack input: {log}")
        results.append({"weapon": weapon, "target": int(health[-1][0]), "health": int(health[-1][1])})
        capture(f"combat-{weapon}")
    text = log.read_text(errors="replace")
    for weapon in (4, 23):
        if f"zig pellets: weapon={weapon}" not in text:
            raise RuntimeError(f"weapon {weapon} did not dispatch its pellet policy")
    return {"attacks": results, "scope": "normal fire input against diagnostic ECS targets; Glock/Ion/Shotcycler/Ripgun/Slugger damage and death; not actor/campaign or complete visual parity acceptance"}


def presentation_scenario(issue, capture, log):
    issue("developer 1")
    issue("cg_shinyWeapons 0")
    for weapon in (1, 21, 2):
        issue(f"dk3_runtime_equip {weapon}", 1)
        issue(f"weapon {weapon}", 1)
        capture(f"weapon-{weapon}-idle")
        issue("+attack", 0.02)
        capture(f"weapon-{weapon}-fire")
        issue("-attack", 1)
    issue("weapon 21", 1)
    issue("+attack", 5.9)
    capture("glock-reload")
    issue("-attack", 2)
    capture("glock-idle-after-reload")
    issue("cg_shinyWeapons 2")
    capture("glock-shine")
    issue("inventory")
    capture("inventory")
    text = log.read_text(errors="replace")
    for weapon in (1, 21, 2):
        for phase in ("fire", "idle"):
            if f"zig view: weapon={weapon} phase={phase}" not in text:
                raise RuntimeError(f"missing view transition {weapon}/{phase}")
    if "zig view: weapon=21 phase=reload" not in text:
        raise RuntimeError("Glock did not enter its class-owned reload animation")
    if "missing weapon animation" in text or "could not find sounds/" in text.lower():
        raise RuntimeError("missing weapon presentation media")
    return {"scope": "three native view weapons, finite attacks/idle, Glock reload, shine and inventory; captures require visual inspection, all-weapon presentation remains open"}


def impacts_scenario(issue, capture, log):
    issue("developer 1")
    issue("dk3_runtime_equip 2")
    issue("dk3_runtime_face_target 10", 0.3)
    placements = re.findall(r"zig combat: fixture player=([\d.,-]+) target=10", log.read_text(errors="replace"))
    if not placements:
        raise RuntimeError("no standing point near authored worker 10")
    player = list(map(float, placements[-1].split(',')))
    for _ in range(40):
        issue("dk3_runtime_actors", 0.05)
        samples = re.findall(r"zig actor: id=10 state=\w+ health=(-?\d+) pos=([\d.,-]+)", log.read_text(errors="replace"))
        if not samples or int(samples[-1][0]) <= 0:
            break
        target = list(map(float, samples[-1][1].split(',')))
        dx, dy, dz = target[0] - player[0], target[1] - player[1], target[2] + 8 - (player[2] + 22)
        issue(f"dk3_look {math.degrees(math.atan2(dy, dx))} {-math.degrees(math.atan2(dz, math.hypot(dx, dy)))}", 0.05)
        issue("+attack", 0.1)
    issue("-attack", 0.2)
    capture("ion-worker-impact")
    issue("dk3_look 0 65")
    issue("+attack", 0.6)
    capture("ion-world-impact")
    issue("-attack", 0.3)
    for weapon, duration in ((4, 1.9), (22, 1.1), (23, 0.2)):
        issue(f"dk3_runtime_equip {weapon}", 0.8)
        issue("dk3_look 0 65")
        issue("+attack", duration)
        capture(f"impact-{weapon}-fire")
        issue("-attack", 2.2)
        capture(f"impact-{weapon}-settled")
    text = log.read_text(errors="replace")
    if not re.search(r"impact: weapon=2 kind=flesh sound=e1/we_ionexplode", text):
        raise RuntimeError("Ion did not select a flesh explosion sound")
    if not re.search(r"impact: weapon=2 kind=(?:world|metal|wood) sound=global/e_electronspr", text):
        raise RuntimeError("Ion did not select a world spark sound")
    if not re.search(r"impact: weapon=(?:4|22|23).*marks=[1-9]", text):
        raise RuntimeError("weapon impacts did not project world decals")
    if "weapon=22 phase=settle pose=spdn" not in text:
        raise RuntimeError("Ripgun did not spin down after releasing fire")
    if "missing weapon animation" in text or "could not find sounds/" in text.lower():
        raise RuntimeError("missing weapon presentation media")
    return {"scope": "Ion authored flesh/world sound selection, clipped world marks, Shotcycler burst and Ripgun spin-down; diagnostic placement/equipment, captures require inspection, physical audio/full weapon parity open"}


def ballistics_scenario(issue, capture, log, process):
    def impact_frame(name, weapon, after):
        wait(process, log, lambda text: f"impact: weapon={weapon}" in text[after:] and
             (weapon != 27 or "sound=global/e_explode1.wav" in text[after:]), 8)
        capture(name)

    issue("developer 1")
    issue("dk3_runtime_probe_health 500")
    results = []
    for weapon in (16, 5):
        issue("dk3_runtime_clear_targets")
        issue(f"dk3_runtime_equip {weapon}", 0.8)
        issue(f"weapon {weapon}", 0.6)
        issue("dk3_runtime_target")
        before = len(log.read_text(errors="replace"))
        issue("+attack", 0.15)
        if weapon == 5:
            impact_frame(f"ballistics-{weapon}-fire", weapon, before)
        else:
            capture(f"ballistics-{weapon}-fire")
        issue("+attack", 3.85)
        issue("-attack", 0.4)
        issue("dk3_runtime_targets")
        text = log.read_text(errors="replace")[before:]
        health = re.findall(r"zig combat: target=(\d+) health=(-?\d+)", text)
        if not health or int(health[-1][1]) > 0 or "killed=1" not in text:
            raise RuntimeError(f"projectile weapon {weapon} did not kill its target: {log}")
        results.append({"weapon": weapon, "health": int(health[-1][1])})
        capture(f"ballistics-{weapon}")
    issue("dk3_runtime_clear_targets")
    issue("dk3_runtime_equip 16", 0.8)
    issue("weapon 16", 0.6)
    issue("dk3_look 0 65")
    issue("+attack", 0.05)
    issue("-attack", 0.3)
    before = len(log.read_text(errors="replace"))
    issue("dk3_runtime_projectiles")
    text = log.read_text(errors="replace")[before:]
    bolts = re.findall(r"projectile state: id=(\d+) weapon=16 stuck=1", text)
    if not bolts:
        raise RuntimeError("Bolter did not stick in the static floor")
    issue("save stuck_bolt", 0.2)
    issue("load stuck_bolt", 0.3)
    before = len(log.read_text(errors="replace"))
    issue("dk3_runtime_projectiles")
    if f"projectile state: id={bolts[-1]} weapon=16 stuck=1" not in log.read_text(errors="replace")[before:]:
        raise RuntimeError("native save lost the stuck bolt")
    capture("bolter-restored")
    issue("dk3_runtime_equip 27", 0.8)
    issue("weapon 27", 0.6)
    issue("dk3_runtime_probe_health 500")
    issue("dk3_look 0 45")
    issue("+attack", 0.05)
    issue("-attack", 0.3)
    issue("save grenade_fuse", 0.2)
    before = len(log.read_text(errors="replace"))
    issue("load grenade_fuse", 0.3)
    issue("dk3_runtime_projectiles")
    impact_frame("cordite-detonation", 27, before)
    issue("viewpos", 0.5)
    issue("dk3_runtime_projectiles")
    text = log.read_text(errors="replace")[before:]
    if "saved world restored" not in text or not re.search(r"projectile: weapon=27 exploded age=3\d\d\d bounces=[1-9]", text):
        raise RuntimeError("Cordite did not resume its saved bouncing/fuse state and explode")
    capture("cordite-restored-detonation")
    text = log.read_text(errors="replace")
    if "missing weapon animation" in text or "could not find sounds/" in text.lower():
        raise RuntimeError("missing ballistic weapon media")
    return {"attacks": results, "scope": "Bolter/Sidewinder normal fire damage, Bolter world stick and save restoration, Cordite bounce/fuse restoration and blast dispatch; diagnostic targets/equipment, full flight/water/actor/visual parity remains open"}


def grenade_contact_scenario(issue, capture, log):
    issue("developer 1")
    issue("dk3_runtime_probe_health 500")
    issue("dk3_runtime_equip 27", 0.6)
    issue("weapon 27", 0.6)
    issue("dk3_runtime_face_target 166", 0.2)
    placement = re.findall(r"zig combat: fixture player=([\d.,-]+) target=166", log.read_text(errors="replace"))
    if not placement:
        raise RuntimeError("no clear standing point near guard 166")
    player = list(map(float, placement[-1].split(',')))
    before = len(log.read_text(errors="replace"))
    for _ in range(40):
        issue("dk3_runtime_actors", 0.05)
        samples = re.findall(r"zig actor: id=166 state=\w+ health=(-?\d+) pos=([\d.,-]+)", log.read_text(errors="replace"))
        if not samples or int(samples[-1][0]) <= 0:
            break
        target = list(map(float, samples[-1][1].split(',')))
        dx, dy, dz = target[0] - player[0], target[1] - player[1], target[2] + 8 - (player[2] + 22)
        issue(f"dk3_look {math.degrees(math.atan2(dy, dx))} {-math.degrees(math.atan2(dz, math.hypot(dx, dy)))}", 0.05)
        issue("+attack", 0.1)
    issue("-attack", 0.3)
    text = log.read_text(errors="replace")[before:]
    ages = re.findall(r"projectile: weapon=27 exploded age=(\d+)", text)
    if not any(int(age) < 1000 for age in ages) or "impact: weapon=27 kind=flesh" not in text:
        raise RuntimeError("Cordite did not detonate on the authored actor before its fuse")
    if not re.search(r"combat: target=166 blood=[1-9]", text):
        raise RuntimeError("Cordite actor contact did not damage the guard")
    capture("cordite-actor-contact")
    return {"explosion_ages_ms": list(map(int, ages)), "scope": "normal Cordite attacks detonate on an authored guard and apply blast damage before fuse expiry; diagnostic positioning/equipment, complete actor/campaign parity open"}


def melee_scenario(issue, capture, log, process):
    def progression():
        issue("dk3_runtime_progression", 0.1)
        samples = re.findall(r"progression state: experience=(\d+) sword=(\d+) level=(\d+) points=(\d+)", log.read_text(errors="replace"))
        if not samples:
            raise RuntimeError("missing progression state")
        return tuple(map(int, samples[-1]))

    def actor(identity):
        issue("dk3_runtime_actors", 0.04)
        samples = re.findall(rf"zig actor: id={identity} state=\w+ health=(-?\d+) pos=([\d.,-]+)", log.read_text(errors="replace"))
        if not samples:
            raise RuntimeError(f"missing authored melee target {identity}")
        return int(samples[-1][0]), list(map(float, samples[-1][1].split(',')))

    issue("developer 1")
    initial = progression()
    results = []
    for weapon, identity in ((15, 10), (8, 9)):
        issue(f"dk3_runtime_equip {weapon}", 0.7)
        issue(f"weapon {weapon}", 0.7)
        before = len(log.read_text(errors="replace"))
        for _ in range(50):
            health, _ = actor(identity)
            if health <= 0:
                break
            # Collision-checked setup follows the moving civilian. Damage still
            # comes exclusively from ordinary attack input and class strike timing.
            issue(f"dk3_runtime_face_target {identity} 48", 0.04)
            placements = re.findall(rf"fixture player=([\d.,-]+) target={identity}", log.read_text(errors="replace"))
            if not placements:
                raise RuntimeError("no close standing point for melee scenario")
            player = list(map(float, placements[-1].split(',')))
            _, target = actor(identity)
            dx, dy = target[0] - player[0], target[1] - player[1]
            issue(f"dk3_look {math.degrees(math.atan2(dy, dx))} 0", 0.04)
            issue("+attack", 0.15)
        issue("-attack", 0.4)
        health, _ = actor(identity)
        text = log.read_text(errors="replace")[before:]
        if health > 0 or not re.search(rf"melee: weapon={weapon} .*hit=1", text):
            raise RuntimeError(f"melee weapon {weapon} did not kill authored actor {identity}")
        results.append({"weapon": weapon, "actor": identity, "health": health, "progression": progression()})
        capture(f"melee-{weapon}-victim")
    after = progression()
    if after[0] <= initial[0] or results[0]["progression"][1] != initial[1] or after[1] <= initial[1]:
        raise RuntimeError("melee kills failed ordinary/sword experience ownership")
    issue("save melee_rewards", 0.1)
    issue("load melee_rewards", 0.3)
    if progression() != after:
        raise RuntimeError("restored dead actors changed kill rewards")

    # Save between the two class-owned strikes of a real generated swing. No
    # selected-sequence or action-state override is used by this fixture.
    issue("dk3_look 0 65", 0.1)
    cursor = len(log.read_text(errors="replace"))
    issue("+attack", 0.02)
    selected = None
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        text = log.read_text(errors="replace")
        for sequence, age, identity in re.findall(r"melee: weapon=8 sequence=(\d+) strike=0 age=(\d+) hit=\d+ id=(\d+)", text[cursor:]):
            if int(sequence) & 7 == 1:
                selected = int(identity)
                break
        cursor = len(text)
        if selected is not None:
            break
        time.sleep(0.025)
    if selected is None:
        raise RuntimeError("normal sword attack did not generate its two-strike swing")
    issue("save sword_second_strike", 0.02)
    issue("-attack", 0.02)
    before = len(log.read_text(errors="replace"))
    issue("load sword_second_strike", 0.02)
    wait(process, log, lambda text: re.search(rf"melee: weapon=8 .*strike=1 .*id={selected}\b", text[before:]) is not None, 5)
    capture("sword-restored-strike")
    text = log.read_text(errors="replace")[before:]
    if "saved world restored" not in text or re.search(rf"melee: weapon=8 .*strike=0 .*id={selected}\b", text):
        raise RuntimeError("restored sword action repeated its consumed strike")
    if "zig view: weapon=8 phase=fire pose=atakb" not in text or "zig view: weapon=8 phase=ready" in text:
        raise RuntimeError("restored sword resumed damage without its matching attack pose")
    if progression() != after:
        raise RuntimeError("corpse melee or a second restore awarded repeated experience")
    text = log.read_text(errors="replace")
    for weapon in (8, 15):
        if f"zig view: weapon={weapon} phase=fire" not in text:
            raise RuntimeError(f"missing melee view animation for weapon {weapon}")
    if "missing weapon animation" in text or "could not find sounds/" in text.lower():
        raise RuntimeError("missing melee media")
    return {"kills": results, "saved_action": selected, "scope": "normal Silverclaw/Daikatana attacks against authored civilians, kill experience and persistent corpse rewards, two-strike save continuation without replay; collision-checked diagnostic placement/equipment, full arc/defense/visual parity remains open"}


def save_scenario(issue, capture, log, home):
    def inventory():
        issue("dk3_runtime_inventory")
        values = re.findall(r"zig inventory .*health=(-?\d+) armor=(\d+)", log.read_text(errors="replace"))
        if not values:
            raise RuntimeError("missing saved-player diagnostics")
        return list(map(int, values[-1]))

    def position():
        issue("viewpos", 0.05)
        values = re.findall(r"zig viewpos: ([^,]+),", log.read_text(errors="replace"))
        return list(map(float, values[-1].split()))

    def saved(slot):
        path = home / f"state/dk3/saves/{slot}.sav"
        if not path.exists():
            raise RuntimeError(f"native save not written: {log}")
        return path

    issue("dk3_runtime_place 818.916 -479.481 -823.875", 0.5)
    issue("dk3_runtime_probe_health 100")
    issue("dk3_runtime_equip 21")
    issue("dk3_runtime_activate 3", 0.7)
    issue("save native_lift", 0.1)
    saved("native_lift")
    initial = position()
    capture("lift-saved")
    issue("dk3_runtime_damage 40", 2)
    moved = position()
    if inventory()[0] != 60 or math.dist(initial, moved) < 50:
        raise RuntimeError("save fixture failed to change health and lift position")
    issue("load native_lift", 0.1)
    restored = position()
    if inventory()[0] != 100 or math.dist(initial, restored) > 32:
        raise RuntimeError(f"mid-lift state not restored: {initial}, {restored}")
    capture("lift-restored")
    issue("save quick")
    issue("dk3_runtime_damage 40")
    issue("save quick")
    saved("quick")
    issue("load quick previous")
    if inventory()[0] != 100:
        raise RuntimeError("previous native save was not recovered")
    damaged = bytearray(saved("quick").read_bytes())
    damaged[-1] ^= 1
    (home / "state/dk3/saves/damaged.sav").write_bytes(damaged)
    before = len(log.read_text(errors="replace"))
    issue("load damaged")
    if inventory()[0] != 100 or "Save/load refused: Checksum" not in log.read_text(errors="replace")[before:]:
        raise RuntimeError("corrupt save changed the live world or lacked a checksum diagnostic")
    issue("dk3_runtime_trains")
    capture("corruption-refused")
    return {"saved_position": initial, "moved_position": moved, "restored_position": restored,
            "scope": "native mid-lift world/player restoration, atomic previous-save recovery and corruption rejection; diagnostic placement/activation/damage; original schema-5 migration, other mid-action states and menu load remain open"}


def civilians_scenario(issue, capture, log):
    def actors():
        issue("dk3_runtime_actors", 0.05)
        result = {}
        for identity, mode, health, position, threat, witness in re.findall(
                r"zig actor: id=(\d+) state=(\w+) health=(-?\d+) pos=([\d.,-]+) threat=(\d+) witness=(-?\d+)",
                log.read_text(errors="replace")):
            result[int(identity)] = {"state": mode, "health": int(health), "position": list(map(float, position.split(','))),
                                     "threat": int(threat), "witness": int(witness)}
        return result
    issue("developer 1")
    issue("cl_debugMove 3")
    initial = actors()
    issue("dk3_runtime_face_target 10", 0.3)
    placement = re.findall(r"zig combat: fixture player=([\d.,-]+) target=10", log.read_text(errors="replace"))
    if not placement:
        raise RuntimeError("no clear standing point near authored worker 10")
    player = list(map(float, placement[-1].split(',')))
    issue("dk3_runtime_equip 21")
    issue("dk3_runtime_inventory")
    issue("viewpos")
    capture("workers-before")
    latest = initial
    for _ in range(70):
        latest = actors()
        if latest[10]["health"] <= 0:
            break
        target = latest[10]["position"]
        dx, dy, dz = target[0] - player[0], target[1] - player[1], target[2] + 8 - (player[2] + 22)
        yaw = math.degrees(math.atan2(dy, dx))
        pitch = -math.degrees(math.atan2(dz, math.hypot(dx, dy)))
        issue(f"dk3_look {yaw} {pitch}", 0.05)
        issue("+attack", 0.1)
    issue("-attack", 0.2)
    issue("dk3_runtime_inventory")
    issue("viewpos")
    after = actors()
    capture("worker-death-witness")
    if after[10]["health"] > 0 or after[10]["state"] != "dead":
        raise RuntimeError(f"authored worker 10 did not die: {after[10]}")
    if after[9]["state"] != "flee" or after[9]["witness"] < 0:
        raise RuntimeError(f"nearby worker 9 did not witness the killing: {after[9]}")
    if math.dist(after[9]["position"], initial[9]["position"]) < 1:
        issue("dk3_runtime_actors", 0.5)
        after = actors()
    return {"before": {str(i): initial[i] for i in (9, 10)}, "after": {str(i): after[i] for i in (9, 10)},
            "scope": "e1m2a authored civilian bodies, normal Glock input, death and witness panic; diagnostic player positioning/equipment, navigation and full actor parity unqualified"}


def guard_scenario(issue, capture, log):
    identity = 166
    issue("developer 1")
    issue("dk3_runtime_probe_health 1000")
    issue(f"dk3_runtime_face_target {identity}", 0.3)
    placement = re.findall(rf"zig combat: fixture player=([\d.,-]+) target={identity}", log.read_text(errors="replace"))
    if not placement:
        raise RuntimeError(f"no clear standing point near guard {identity}")
    player = list(map(float, placement[-1].split(',')))
    issue("dk3_runtime_equip 21")
    issue("dk3_runtime_actors")
    matches = re.findall(rf"zig actor: id={identity} state=(\w+) health=(-?\d+) pos=([\d.,-]+)", log.read_text(errors="replace"))
    if not matches:
        raise RuntimeError("guard did not spawn")
    target = list(map(float, matches[-1][2].split(',')))
    dx, dy, dz = target[0] - player[0], target[1] - player[1], target[2] + 8 - (player[2] + 22)
    issue(f"dk3_look {math.degrees(math.atan2(dy, dx))} {-math.degrees(math.atan2(dz, math.hypot(dx, dy)))}")
    issue("+attack", 0.15)
    issue("-attack", 0.2)
    capture("guard-retaliation")
    deadline = time.monotonic() + 25
    text = ""
    while time.monotonic() < deadline:
        issue("dk3_runtime_inventory", 0.4)
        text = log.read_text(errors="replace")
        if f"guard: id={identity} reload sound dispatched" in text:
            break
    shots = [int(value) for value in re.findall(rf"guard: id={identity} fired rounds=(\d+)", text)]
    health = re.findall(r"zig inventory .*health=(-?\d+)", text)
    if shots[:8] != list(range(7, -1, -1)) or f"guard: id={identity} reload sound dispatched" not in text:
        raise RuntimeError(f"guard did not complete eight rounds and reload: {shots}")
    if not health or int(health[-1]) >= 1000:
        raise RuntimeError("guard fire did not damage the player")
    capture("guard-reload")
    return {"guard": identity, "rounds": shots, "player_health": int(health[-1]),
            "scope": "e1m3b authored guard retaliation, eight-round firing cycle, reload and player damage; diagnostic placement/equipment/1000 health, navigation/cover/pain and full actor parity unqualified"}


def navigation_scenario(issue, capture, log):
    issue("developer 1")
    issue("dk3_runtime_chase 166", 0.2)
    text = log.read_text(errors="replace")
    fixtures = re.findall(r"navigation fixture: actor=166 start=([\d.,-]+) goal=([\d.,-]+) travel=(\d+) occluded=1", text)
    if not fixtures:
        raise RuntimeError("no occluded reachable pursuit fixture")
    start = list(map(float, fixtures[-1][0].split(',')))
    goal = list(map(float, fixtures[-1][1].split(',')))
    issue(f"dk3_look {math.degrees(math.atan2(start[1] - goal[1], start[0] - goal[0]))} 0")
    capture("pursuit-start")
    deadline = time.monotonic() + 9
    samples = []
    while time.monotonic() < deadline:
        issue("dk3_runtime_actors", 0.3)
        text = log.read_text(errors="replace")
        states = re.findall(r"zig actor: id=166 state=(\w+) health=(-?\d+) pos=([\d.,-]+)", text)
        if states:
            samples.append(states[-1])
        if "guard: id=166 fired" in text:
            break
    capture("pursuit-arrival")
    displacement = max((math.dist(start, list(map(float, sample[2].split(',')))) for sample in samples), default=0)
    if displacement < 24 or "guard: id=166 fired" not in text:
        raise RuntimeError(f"guard failed to navigate from occlusion into a firing position: {displacement=} {samples=}")
    return {"fixture": fixtures[-1], "samples": samples, "displacement": displacement,
            "scope": "e1m3b guard physically pursues a seeded last-seen goal around occlusion and resumes normal fire; diagnostic player placement, sight memory and health; full navigation matrix open"}


def laser_scenario(issue, capture, log):
    issue("developer 1")
    issue("dk3_runtime_probe_health 1000")
    issue("dk3_runtime_world")
    text = log.read_text(errors="replace")
    fields = re.findall(r"hazard: id=110 name=laser_dam enabled=(\d) center=([\d.,-]+)", text)
    if not fields or fields[-1][0] != '0':
        raise RuntimeError("laser damage field must start disabled")
    center = list(map(float, fields[-1][1].split(',')))
    issue("dk3_runtime_activate 110 player")
    issue("dk3_runtime_place " + ' '.join(map(str, center)), 0.6)
    if "hazard hit: id=110" not in log.read_text(errors="replace"):
        raise RuntimeError("enabled damage field did not hurt the player")
    issue("dk3_runtime_face_target 125", 0.2)
    text = log.read_text(errors="replace")
    placements = re.findall(r"fixture player=([\d.,-]+) target=125", text)
    boxes = re.findall(r"destructible: id=125 .*center=([\d.,-]+)", text)
    if not placements or not boxes:
        raise RuntimeError("no clear firing position near the supply box")
    player = list(map(float, placements[-1].split(',')))
    box = list(map(float, boxes[-1].split(',')))
    dx, dy, dz = box[0] - player[0], box[1] - player[1], box[2] + 8 - (player[2] + 22)
    issue("dk3_runtime_equip 21")
    issue(f"dk3_look {math.degrees(math.atan2(dy, dx))} {-math.degrees(math.atan2(dz, math.hypot(dx, dy)))}")
    capture("laser-box-intact")
    for _ in range(3):
        issue("+attack", 0.15)
        issue("-attack", 0.8)
    issue("dk3_runtime_world", 4.5)
    issue("dk3_runtime_world")
    text = log.read_text(errors="replace")
    if not re.search(r"destructible: id=125 health=-?\d+ broken=1", text) or "disabled e1m3b laser damage with removed controls" not in text:
        raise RuntimeError("shooting supply box did not finish laser shutdown")
    cutoff = len(text)
    for y in (center[1] - 72, center[1], center[1] + 72, center[1]):
        issue(f"dk3_runtime_place {center[0]} {y} {center[2]}", 0.6)
    capture("lasers-disabled")
    after = log.read_text(errors="replace")[cutoff:]
    if "hazard hit: id=110" in after:
        raise RuntimeError("disabled lasers still caused damage from the reverse approach")
    issue("save laser_off")
    issue("dk3_runtime_damage 40")
    cutoff = len(log.read_text(errors="replace"))
    issue("load laser_off")
    issue("dk3_runtime_world")
    after = log.read_text(errors="replace")[cutoff:]
    if "saved world restored" not in after or not re.search(r"destructible: id=125 health=-?\d+ broken=1", after):
        raise RuntimeError("save did not restore the broken laser control")
    for y in (center[1] + 72, center[1], center[1] - 72, center[1]):
        issue(f"dk3_runtime_place {center[0]} {y} {center[2]}", 0.6)
    if "hazard hit: id=110" in log.read_text(errors="replace")[cutoff:]:
        raise RuntimeError("loading a save reactivated the disabled lasers")
    capture("laser-shutdown-restored")
    return {"hazard_center": center, "box": 125,
            "scope": "ordinary Glock fire breaks authored supply box; timed target chain removes controls; enabled hurt field damages, disabled field stays harmless at both approaches before and after native save/load; diagnostic placement/equipment/health, beam/audio presentation unqualified"}


def travel_scenario(issue, capture, log, home, process):
    # Exercise a changed authored world, then visit/revisit through its real exits.
    laser_scenario(issue, capture, log)
    issue("dk3_runtime_probe_health 333")
    issue("dk3_runtime_equip 21")

    def leave(identity, destination):
        issue("dk3_runtime_world")
        matches = re.findall(rf"zig exit: id={identity} map={destination} .*center=([\d.,-]+)", log.read_text(errors="replace"))
        if not matches:
            raise RuntimeError(f"missing authored exit {identity} to {destination}")
        center = list(map(float, matches[-1].split(',')))
        # Clear any arrival latch before making ordinary touch contact.
        issue(f"dk3_runtime_place {center[0] + 400} {center[1]} {center[2]}", 0.1)
        before = len(log.read_text(errors="replace"))
        issue("dk3_runtime_place " + ' '.join(map(str, center)), 0.05)
        wait(process, log, lambda text: "traveler entered authored landing" in text[before:])
        time.sleep(0.7)
        segment = log.read_text(errors="replace")[before:]
        maps = re.findall(r"^Server: ([^\n]+)", segment, re.M)
        if maps != [destination]:
            raise RuntimeError(f"authored exit started unexpected maps: {maps}")
        departed = re.findall(r"campaign departure .*health=(\d+)", segment)
        arrived = re.findall(r"traveler entered authored landing health=(\d+) weapon=(\d+)", segment)
        if not departed or not arrived or departed[-1] != arrived[-1][0] or arrived[-1][1] != "21":
            raise RuntimeError(f"travel lost incoming health or equipment: {departed}, {arrived}")
        issue("viewpos")
        return int(arrived[-1][0])

    leave(127, "e1m3a")
    capture("arrival-e1m3a")
    issue("dk3_runtime_probe_health 333")
    issue("save visited_lasers")
    save = home / "state/dk3/saves/visited_lasers.sav"
    if not save.exists() or b"visited_level" not in save.read_bytes():
        raise RuntimeError("campaign save omitted the visited laser world")
    saved_health = int(re.search(r"^health (-?\d+)$", save.with_suffix(".info").read_text(), re.M)[1])
    issue("dk3_runtime_probe_health 222")
    leave(131, "e1m3b")
    issue("dk3_runtime_world")
    text = log.read_text(errors="replace")
    if not re.search(r"destructible: id=125 health=-?\d+ broken=1", text[text.rfind("saved world restored"):]):
        raise RuntimeError("revisit lost world changes or replaced the incoming traveler")
    capture("revisited-laser-world")
    before = len(log.read_text(errors="replace"))
    issue("devmap e1m3a", 0.05)  # Discard live campaign state before loading its archive.
    wait(process, log, lambda text: "player entered isolated movement runtime" in text[before:])
    for path in save.parent.glob("dk3-*"):
        if path.is_file():
            path.unlink()  # Only this fixture's temporary internal transfer files.
    before = len(log.read_text(errors="replace"))
    issue("load visited_lasers", 0.4)
    restored = re.findall(r"saved world restored health=(-?\d+)", log.read_text(errors="replace")[before:])
    if not restored or int(restored[-1]) != saved_health:
        raise RuntimeError("campaign save did not restore its player")
    leave(131, "e1m3b")
    before = len(log.read_text(errors="replace"))
    issue("dk3_runtime_world")
    text = log.read_text(errors="replace")[before:]
    if not re.search(r"destructible: id=125 health=-?\d+ broken=1", text):
        raise RuntimeError("saved visited-world archive was not restored independently")
    capture("saved-archive-revisited")
    return {"scope": "authored e1m3b/e1m3a exit touch, named arrival, incoming inventory/health, changed visited-world restoration and complete native campaign save after discarding internal transfer files; diagnostic placement/equipment, not authored route traversal or companion/cinematic acceptance"}


def run(args):
    args.report.mkdir(parents=True, exist_ok=True)
    log = args.report / "client.log"
    inputs = []
    with tempfile.TemporaryDirectory(prefix="dk3-runtime-client-") as temporary:
        home = Path(temporary)
        stage_client_modules(args.prefix, home)
        command = [str(args.guard), "--headless", "--screen", "960x540",
                   "--timeout", "90s", "--mem", "8G", "--", str(args.engine / "bin/dk3")]
        settings = client_settings(args.engine, home, args.renderer, args.workers)
        for name, value in settings.items():
            command += ["+set", name, value]
        command += ["+devmap", args.map]
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            pipe = home / "dk3/commands.fifo"

            def issue(value, delay=0.15):
                inputs.append({"command": value, "settle_seconds": delay})
                send(pipe, value)
                time.sleep(delay)

            def capture(name):
                issue(f"screenshotJPEG {name}")
                source = home / f"dk3/screenshots/{name}.jpg"
                wait(process, log, lambda _: source.exists(), 10)
                shutil.copy2(source, args.report / f"{name}.jpg")

            try:
                wait(process, log, lambda text: "player entered isolated movement runtime" in text)
                if args.scenario == "navigation":
                    result = navigation_scenario(issue, capture, log)
                elif args.scenario == "travel":
                    result = travel_scenario(issue, capture, log, home, process)
                elif args.scenario == "laser":
                    result = laser_scenario(issue, capture, log)
                elif args.scenario == "lift":
                    result = lift_scenario(issue, capture, log)
                elif args.scenario == "guard":
                    result = guard_scenario(issue, capture, log)
                elif args.scenario == "civilians":
                    result = civilians_scenario(issue, capture, log)
                elif args.scenario == "combat":
                    result = combat_scenario(issue, capture, log)
                elif args.scenario == "presentation":
                    result = presentation_scenario(issue, capture, log)
                elif args.scenario == "impacts":
                    result = impacts_scenario(issue, capture, log)
                elif args.scenario == "ballistics":
                    result = ballistics_scenario(issue, capture, log, process)
                elif args.scenario == "grenade-contact":
                    result = grenade_contact_scenario(issue, capture, log)
                elif args.scenario == "melee":
                    result = melee_scenario(issue, capture, log, process)
                elif args.scenario == "save":
                    result = save_scenario(issue, capture, log, home)
                elif args.scenario == "effects":
                    result = effects_scenario(issue, capture, log)
                elif args.scenario == "inventory":
                    result = inventory_scenario(issue, capture, log)
                elif args.scenario in ("secret", "rotation"):
                    result = special_scenario(args, issue, capture, log)
                else:
                    result = movement_scenario(args, issue, capture, log)
                issue("quit", 0)
                if process.wait(timeout=15) != 0:
                    raise RuntimeError(f"engine shutdown failed: {log}")
                (args.report / "result.json").write_text(json.dumps({**result, "workers": args.workers}, indent=2) + "\n")
            finally:
                (args.report / "inputs.json").write_text(json.dumps({"launch": command, "inputs": inputs}, indent=2) + "\n")
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)
    print(f"Native client probe passed. Inspect captures in {args.report}; gameplay acceptance remains open.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--prefix", type=Path, required=True)
    parser.add_argument("--guard", type=Path, default=Path("zig-out/bin/dkguard"))
    parser.add_argument("--report", type=Path, default=None)
    parser.add_argument("--map")
    parser.add_argument("--scenario", choices=("movement", "lift", "secret", "rotation", "inventory", "effects", "combat", "presentation", "impacts", "ballistics", "grenade-contact", "melee", "save", "travel", "civilians", "guard", "navigation", "laser"), default="movement")
    parser.add_argument("--workers", type=int, choices=range(9), default=4)
    parser.add_argument("--renderer", choices=("opengl1", "opengl2"), default="opengl1")
    parser.add_argument("--mover", type=int, help="optional known delayed-door persistent ID; e1m3b uses 255")
    args = parser.parse_args()
    defaults = {
        "movement": ("e1m3b", "runtime-zig-218/client"),
        "lift": ("e1m3a", "runtime-zig-219/lift"),
        "secret": ("e3dm1", "runtime-zig-220/secret"),
        "rotation": ("e1m3b", "runtime-zig-220/rotation"),
        "inventory": ("e1m6a", "runtime-zig-221/inventory"),
        "effects": ("e4m4b", "runtime-zig-222/effects"),
        "combat": ("e1m3b", "runtime-zig-224/combat"),
        "presentation": ("e1m3b", "runtime-zig-228/presentation"),
        "impacts": ("e1m2a", "runtime-zig-232/impacts"),
        "ballistics": ("e1m3b", "runtime-zig-233/ballistics"),
        "grenade-contact": ("e1m3b", "runtime-zig-233/grenade-contact"),
        "melee": ("e1m2a", "runtime-zig-234/melee"),
        "save": ("e1m3a", "runtime-zig-230/save"),
        "civilians": ("e1m2a", "runtime-zig-225/civilians"),
        "guard": ("e1m3b", "runtime-zig-226/guard"),
        "navigation": ("e1m3b", "runtime-zig-227/navigation"),
        "laser": ("e1m3b", "runtime-zig-227/laser"),
        "travel": ("e1m3b", "runtime-zig-231/travel"),
    }
    expected_map, report_name = defaults[args.scenario]
    if args.map is None:
        args.map = expected_map
    if args.report is None:
        args.report = Path("zig-out/reports") / report_name
    if args.scenario != "movement" and (args.map != expected_map or args.mover is not None):
        parser.error(f"{args.scenario} scenario uses {expected_map}; omit --mover")
    if not re.fullmatch(r"[a-zA-Z0-9_]+", args.map):
        parser.error("map must be a simple map name")
    for name in ("engine", "prefix", "guard", "report"):
        setattr(args, name, getattr(args, name).resolve())
    run(args)


if __name__ == "__main__":
    main()
