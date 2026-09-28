#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Focused native effects, hatching and death recovery; explicitly controlled fixtures."""
import argparse
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

from runtime_input import NativeInput, record_identity
from runtime_opening_route import actors
from runtime_probe import client_settings, stage_client_modules, wait


def presentation(driver):
    text = driver.diagnostics("dk3_runtime_presentation", "dk3 presentation:")
    return {key: float(value) for key, value in re.findall(r"(\w+)=([-\d.]+)", text.split("dk3 presentation:")[-1])}


def sample(driver, function, predicate, description, seconds=8):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        driver.observe()
        value = function()
        if predicate(value):
            return value
    raise TimeoutError(f"{description}: last sample {value}")


def aim_actor(driver, row):
    player = driver.observe()
    delta = [row["aim"][i] - player["pos"][i] for i in range(3)]
    delta[2] -= 22
    driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))


def opening(driver, report, capture):
    driver.until(lambda s: s["mode"] == "normal" and s["map"] == "e1m1a", description="fresh fixture admitted")
    wait(driver.process, driver.log, lambda text: "dk3 checkpoint: ready" in text, 5)
    assert "textures/dkq3/sky/e1m1 -> dk3/sky/e1m1a/1" in driver.text()
    checkpoint = driver.home / "state/dk3/saves/dk3-restart-internal.sav"
    assert checkpoint.exists() and checkpoint.read_bytes().startswith(b"DK3SAVE")
    recoveries = []
    for expected in (100, 73):
        if expected == 73:
            driver.issue("dk3_runtime_damage 27")
            driver.until(lambda s: s["health"] == 73, description="manual checkpoint fixture health")
            saved = driver.save("recovery_fixture")
            shutil.copy2(saved, report / saved.name)
        before = len(driver.text())
        driver.issue("dk3_runtime_damage 2000")
        dead = driver.until(lambda s: s["mode"] == "dead" and s["health"] <= 0, description="actual player death")
        driver.issue("+attack")
        delayed = driver.until(lambda s: s["now"] >= dead["now"] + 3000, description="death delay remains active")
        assert delayed["health"] <= 0 and "restoring after death" not in driver.text()[before:]
        wait(driver.process, driver.log, lambda text: "dk3 checkpoint: restoring after death" in text[before:] and "restoration applied" in text[before:], 10)
        driver.issue("-attack")
        recovered = driver.until(lambda s: s["mode"] == "normal" and s["health"] == expected, description="checkpoint restored and processing input")
        recoveries.append(dict(dead=dead, recovered=recovered))
    capture("checkpoint-restored")
    driver.issue("dk3_runtime_probe_health 1000")
    driver.until(lambda s: s["health"] == 1000, description="controlled actor-test health")
    driver.save("actor_start")
    camera = actors(driver)[9]
    assert camera["class"] == "monster_cambot" and camera["ignore"] == "0"
    yaw = math.radians(camera["angles"][1])
    point = (camera["pos"][0] + 96 * math.cos(yaw), camera["pos"][1] + 96 * math.sin(yaw), camera["pos"][2] - 40)
    driver.issue("dk3_runtime_place " + " ".join(map(str, point)))
    driver.until(lambda s: math.dist(s["pos"], point) < 40, description="camera placement accepted")
    camera = sample(driver, lambda: actors(driver), lambda rows: rows[9]["camera_seen"] == "1", "camera acquires player")[9]
    aim_actor(driver, camera)
    lamp = sample(driver, lambda: presentation(driver), lambda row: row["lamps"] > 0, "cambot lamp actually submitted")
    capture("cambot-searchlight")
    motion = sample(driver, lambda: presentation(driver), lambda row: row["motion_blended"] > 0 and row["now"] < row["snapshot"], "actual intermediate actor motion")
    driver.load("actor_start")
    driver.diagnostics("dk3_runtime_face_target 15 128", "target=15")
    pod = actors(driver)[15]
    player = driver.observe()
    assert pod["class"] == "monster_protopod" and pod["ignore"] == "0"
    assert math.dist(pod["pos"][:2], player["pos"][:2]) < 200 and pod["sight"] == "1"
    text = wait(driver.process, driver.log, lambda text: "dk3 pod: id=15 hatched=" in text, 8)
    child = int(re.search(r"dk3 pod: id=15 hatched=(\d+)", text)[1])
    rows = actors(driver)
    assert child in rows and rows[child]["class"] == "monster_slaughterskeet" and rows[child]["threat"] == str(player["player_id"])
    capture("pod-hatched")
    driver.issue("dk3_runtime_equip 2")
    driver.ready(2)
    driver.aim(180, -30)
    event = driver.observe()["event"]
    driver.issue("+attack")
    fired = driver.until(lambda s: s["event"] > event, description="actual Ion attack occurred")
    ion = sample(driver, lambda: presentation(driver), lambda row: row["ions"] > 0, "Ion electrical projectile actually rendered", seconds=4)
    capture("ion-electrical-projectile")
    driver.issue("-attack")
    driver.ready(2)
    # A real shot at a live authored/hatch actor exercises death dispatch and fragments.
    rows = actors(driver)
    target = next(i for i, row in rows.items() if row["class"] == "monster_protopod" and row["health"] > 0 and row["sight"] == "1")
    driver.diagnostics(f"dk3_runtime_face_target {target} 128", f"target={target}")
    driver.issue(f"dk3_runtime_probe_health 1 {target}")
    assert actors(driver)[target]["health"] == 1
    deadline = time.monotonic() + 6
    damage_event = driver.observe()["event"]
    driver.issue("+attack")
    while time.monotonic() < deadline:
        rows = actors(driver)
        if target not in rows or rows[target]["health"] <= 0:
            break
        aim_actor(driver, rows[target])
    else:
        raise TimeoutError("Ion aiming fixture failed to hit its live pod")
    driver.issue("-attack")
    assert driver.observe()["event"] > damage_event
    gibs = sample(driver, lambda: presentation(driver), lambda row: row["gibs"] > 0, "mechanical fragments actually rendered", seconds=3)
    capture("pod-mechanical-fragments")
    return dict(scope="Controlled e1m1a entry/manual death recovery, authored Cambot and pod, real Ion fire and actor death. Placement, equipment and health fixtures; not connected campaign acceptance.", recoveries=recoveries, lamp=lamp, motion=motion, pod=pod, child=child, ion=ion, fired=fired, gibs=gibs)


def bridge(driver, report, capture):
    driver.until(lambda s: s["map"] == "e1m1b" and s["mode"] == "normal", description="bridge fixture admitted")
    driver.issue("dk3_runtime_probe_health 1000")
    driver.until(lambda s: s["health"] == 1000, description="bridge fixture health")
    driver.diagnostics("dk3_runtime_face_target 82 160", "target=82")
    player = driver.observe()
    # Center of supplied e1m1b inline model *20, plus the initial rising chunks.
    delta = [a - b for a, b in zip((-1158.667, 668.0, 998.0), player["pos"])]
    delta[2] -= 22
    driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
    before = len(driver.text())
    driver.issue("dk3_runtime_activate 82 player")
    wait(driver.process, driver.log, lambda text: "dk3 explosive: target=piece_01 material=stone chunks=10" in text[before:], 5)
    fragments = sample(driver, lambda: presentation(driver), lambda row: row["chunks"] > 0, "bridge stone fragments reach renderer", seconds=3)
    capture("bridge-fragments")
    save = driver.save("bridge_fragments")
    shutil.copy2(save, report / save.name)
    driver.load("bridge_fragments")
    restored = sample(driver, lambda: presentation(driver), lambda row: row["chunks"] > 0, "bridge fragments restored", seconds=3)
    capture("bridge-fragments-restored")
    return dict(scope="Diagnostic activation of authored bridge piece_01, rendered stone chunks and actual save/load restoration; not connected bridge cinematic acceptance.", fragments=fragments, restored=restored)


def sky(driver, report, capture):
    driver.until(lambda s: s["mode"] == "normal" and s["ground"] != 2047, description="stationary outdoor sky observation")
    driver.aim(115, -89)
    initial = driver.observe()
    images, times, means = [], [], []
    for index in range(12):
        state = driver.until(lambda row: row["now"] >= initial["now"] + index * 333, description="actual sky animation time")
        assert math.dist(state["pos"], initial["pos"]) < 0.01 and state["angles"] == initial["angles"], "Camera movement invalidates sky comparison"
        name = f"sky-{index:02}"
        capture(name)
        image = subprocess.run(["magick", str(report / (name + ".jpg")), "-crop", "560x140+200+80", "-colorspace", "Gray", "-depth", "8", "gray:-"], capture_output=True, check=True, timeout=5).stdout
        assert len(image) == 560 * 140
        images.append(image)
        means.append(sum(image) / len(image))
        times.append(state["now"])
    differences = [sum(abs(a - b) for a, b in zip(images[0], image)) / len(image) for image in images[1:]]
    assert max(differences) > 2, "Sky surface did not animate with a fixed camera"
    assert max(means) - min(means) > 5, "No visible authored sky illumination variation"
    return dict(scope="Fixed actual camera, advancing native render time, supplied moving cloud/lightning shader. Pixel motion and illumination variance; not full original sky timing equivalence.", times=times, mean_luminance=means, differences=differences)


def run(args, scenario=None):
    if not __debug__ or (args.report.exists() and any(args.report.iterdir())):
        raise RuntimeError("Evidence requires assertions and a fresh report directory")
    args.report.mkdir(parents=True, exist_ok=True)
    identity = record_identity(args.engine, args.engine, args.report, require_installation=True)
    inputs, result = [], None
    with tempfile.TemporaryDirectory(prefix="dk3-native-bugfix-") as temporary:
        home = Path(temporary)
        stage_client_modules(args.engine, home, installation=args.engine)
        settings = client_settings(args.engine, home, args.renderer)
        settings.update(g_spSkill="3", r_picmip="0")
        if getattr(args, "restore_audit", False):
            settings["dk3_runtime_restore_audit"] = "1"
        if getattr(args, "cinematics", False):
            settings['dk3_cinematics'] = '1'
        command = [str(args.engine / "bin/dk3")]
        for key, value in settings.items():
            command += ["+set", key, value]
        command += ["+devmap", getattr(args, "start_map", "e1m1b" if args.scenario == "bridge" else "e1m1a")]
        if getattr(args, 'debugger', False):
            command = ['gdb', '--batch', '-ex', 'set pagination off', '-ex', 'handle SIGILL stop print nopass',
                       '-ex', 'run', '-ex', 'thread apply all bt', '-ex', 'info registers', '--args'] + command
        log = args.report / "client.log"
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            driver = NativeInput(process, home / "dk3/commands.fifo", log, home, inputs, diagnostic=True)
            def capture(name):
                driver.issue(f"screenshotJPEG {name}")
                source = home / f"dk3/screenshots/{name}.jpg"
                wait(process, log, lambda _: source.exists() and source.stat().st_size > 0, 5)
                shutil.copy2(source, args.report / source.name)
            try:
                wait(process, log, lambda text: "first snapshot applied" in text and driver.pipe.exists(), 40)
                exercise = scenario or {"opening": opening, "bridge": bridge, "sky": sky}[args.scenario]
                result = exercise(driver, args.report, capture)
                driver.issue("quit")
                assert process.wait(timeout=10) == 0
                (args.report / "passed.json").write_text(json.dumps(dict(identity=identity, result=result), indent=2))
            except Exception as error:
                (args.report / "failure.json").write_text(json.dumps(dict(error=str(error), identity=identity, result=result), indent=2))
                raise
            finally:
                (args.report / "inputs.json").write_text(json.dumps(inputs, indent=2))
                if process.poll() is None:
                    try:
                        driver.issue("quit")
                        process.wait(timeout=5)
                    except (OSError, subprocess.TimeoutExpired):
                        process.kill()
                        process.wait(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--scenario", choices=("opening", "bridge", "sky"), default="opening")
    parser.add_argument("--renderer", default="opengl1")
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    run(args)
