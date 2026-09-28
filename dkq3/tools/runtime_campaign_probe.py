#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Ordinary-input native campaign runner. Execute under dkguard --headless, without --gpu."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

from runtime_input import NativeInput, cinematic_shots, record_identity
from runtime_probe import client_settings, stage_client_modules, wait
from runtime_ui_probe import Input


def complete_opening(args, driver, intro_shots, final_state):
    if args.checkpoint or not args.opening:
        return False
    maps = []
    for entry in driver.inputs:
        name = entry.get("observed", {}).get("map")
        if name and (not maps or name != maps[-1]):
            maps.append(name)
    if maps != ["intro", "e1m1a", "e1m1b", "e1m1c", "e1m1b", "e1m1c", "e1m2a"]:
        raise RuntimeError(f"Fresh route did not retain its connected map sequence: {maps}")
    if not set(range(115)).issubset(intro_shots) or final_state["map"] != "e1m2a" or final_state["mode"] != "normal" or final_state["health"] <= 0 or final_state["skill"] != 3:
        raise RuntimeError("Fresh opening did not finish alive on normal difficulty")
    if not any(row.get("combat_target") and row.get("fired") and row.get("contacted") for row in driver.inputs):
        raise RuntimeError("Fresh opening has no observed attack and target contact")
    death = json.loads((args.report / "connected-death-reload.json").read_text())
    visit = json.loads((args.report / "visited-world-roundtrip.json").read_text())
    monitor = json.loads((args.report / "monitor-restoration.json").read_text())
    if death["death"]["health"] > 0 or death["restored"]["health"] <= 0 or death["restored"]["mode"] != "normal":
        raise RuntimeError("Death/reload evidence does not restore a living player")
    if visit["before"] != visit["after"] or visit["bridge_arrival"]["map"] != "e1m1b" or visit["factory_return"]["map"] != "e1m1c":
        raise RuntimeError("Visited-world evidence does not retain the authored round trip")
    if monitor["restored_player"]["mode"] != "frozen" or monitor["released_player"]["mode"] != "normal":
        raise RuntimeError("Monitor evidence does not restore and release player control")
    return True


def run(args):
    if not __debug__:
        raise RuntimeError("Campaign acceptance requires assertions")
    if args.report.exists() and any(args.report.iterdir()):
        raise RuntimeError("Campaign evidence requires a fresh report directory")
    args.report.mkdir(parents=True, exist_ok=True)
    identity = record_identity(args.engine, args.prefix, args.report, require_installation=True)
    log = args.report / "client.log"
    inputs = []
    with tempfile.TemporaryDirectory(prefix="dk3-native-campaign-") as temporary:
        home = Path(temporary)
        stage_client_modules(args.prefix, home, installation=args.engine)
        settings = client_settings(args.engine, home)
        settings.update({"dk3_cinematics": "1", "g_spSkill": "3", "in_nograb": "1", "developer": "1"})
        command = [str(args.engine / "bin/dk3")]
        for key, value in settings.items():
            command += ["+set", key, value]
        if args.checkpoint:
            saves = home / "state/dk3/saves"
            saves.mkdir(parents=True, exist_ok=True)
            shutil.copy2(args.checkpoint, saves / "intro_resume.sav")
            command += ["+map", args.checkpoint_map]
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            pipe = home / "dk3/commands.fifo"
            ui = None
            driver = NativeInput(process, pipe, log, home, inputs)

            def capture(name):
                source = home / f"dk3/screenshots/{name}.jpg"
                driver.issue(f"screenshotJPEG {name}")
                wait(process, log, lambda _: source.exists() and source.stat().st_size > 0, 5)
                shutil.copy2(source, args.report / source.name)

            try:
                wait(process, log, lambda text: "native menus initialized" in text and pipe.exists(), 30)
                if not args.checkpoint:
                    ui = Input(inputs)
                    ui.focus()
                    ui.align_menu()
                    ui.click(265, 349)  # Normal difficulty, through the native New Game menu.
                wait(process, log, lambda text: "dk3 zig client: first snapshot applied" in text, 45)
                if args.checkpoint:
                    driver.load("intro_resume")
                if args.checkpoint_map in ("e1m1b", "e1m1c"):
                    if args.checkpoint_map == "e1m1b":
                        from runtime_bridge_route import bridge_route as route
                    else:
                        from runtime_factory_route import factory_route as route
                    driver.until(lambda s: s["map"] == args.checkpoint_map and s["mode"] == "normal", description="legitimate campaign checkpoint restored")
                    capture("route-checkpoint-start")
                    outcome = route(driver, capture, args.report, args.checkpoint_phase)
                    (args.report / "result.json").write_text(json.dumps({"identity": identity, "checkpoint": str(args.checkpoint), "scope": "Development replay from a legitimate checkpoint; not fresh campaign acceptance.", "route": outcome}, indent=2) + "\n")
                    driver.issue("quit")
                    if process.wait(timeout=15) != 0:
                        raise RuntimeError("Campaign shutdown failed")
                    return
                state = driver.until(lambda s: (s["map"] == "intro" and s["cinematic"] and s["mode"] == "frozen") or (args.checkpoint and args.checkpoint_map == "e1m1a" and s["map"] == "e1m1a" and s["mode"] == "normal"), description="authored intro or legitimate arrival checkpoint ready")
                if state["skill"] != 3 or (args.checkpoint_phase == "arrival" and (state["health"] != 100 or state["weapon"] != 1)):
                    raise RuntimeError(f"New Game did not start with ordinary normal-difficulty state: {state}")
                capture("checkpoint-start" if args.checkpoint else "intro-start")
                seen = set()
                deadline = time.monotonic() + 650
                while time.monotonic() < deadline:
                    state = driver.observe()
                    marker = (state["map"], state["shot"])
                    if marker not in seen:
                        seen.add(marker)
                        print(f"campaign: map={state['map']} shot={state['shot']} cinematic={state['cinematic']} health={state['health']}", flush=True)
                        if state["map"] == "intro" and state["shot"] in (20, 50, 80):
                            checkpoint = driver.save(f"intro_{state['shot']}")
                            shutil.copy2(checkpoint, args.report / checkpoint.name)
                        if state["shot"] in (1, 20, 50, 80, 110) or state["map"] == "e1m1a":
                            capture(f"{state['map']}-shot-{state['shot']:03}")
                    arrival_complete = (args.checkpoint and args.checkpoint_map == "e1m1a") or "shot=7/7 name=e1m1_cinestart" in driver.text()
                    if state["map"] == "e1m1a" and state["cinematic"] == 0 and state["mode"] == "normal" and arrival_complete:
                        break
                    if state["health"] <= 0:
                        raise RuntimeError("Player died during the intro or arrival cinematic")
                    # Wait for a shot/map transition with a bounded timeout; timeout triggers
                    # a state observation, not an inference that playback has advanced.
                    offset = len(driver.text())
                    try:
                        wait(process, log, lambda text: "dk3 cinematic:" in text[offset:] or "Server:" in text[offset:], 2)
                    except TimeoutError:
                        pass
                else:
                    raise TimeoutError("Full intro did not reach playable e1m1a")
                intro_shots = cinematic_shots(driver.text(), inputs, "intro", "intro", 115)
                (args.report / "intro-coverage.json").write_text(json.dumps({
                    "scope": "Actual active player observations and one-based server shot-transition events; completed cursor excluded.",
                    "shots": sorted(intro_shots)}, indent=2) + "\n")
                if not args.checkpoint and not set(range(115)).issubset(intro_shots):
                    raise RuntimeError(f"Intro observation incomplete: {len(intro_shots)}/115 shots")
                save = driver.save("opening_arrival")
                driver.load("opening_arrival")
                state = driver.until(lambda s: s["map"] == "e1m1a" and s["mode"] == "normal" and not s["cinematic"], description="arrival save restored without replaying intro")
                capture("e1m1a-restored-arrival")
                shutil.copy2(save, args.report / save.name)
                opening = None
                if args.opening:
                    from runtime_opening_route import opening_route
                    opening = opening_route(driver, capture, args.report, args.checkpoint_phase)
                final_state = driver.observe()
                completed = complete_opening(args, driver, intro_shots, final_state)
                result = {"identity": identity, "checkpoint": str(args.checkpoint) if args.checkpoint else None,
                          "scope": ("Development replay from a legitimate checkpoint; never fresh campaign acceptance."
                                    if args.checkpoint else "Ordinary New Game, normal difficulty and full intro; only the recorded connected route is exercised."),
                          "intro_shots": sorted(intro_shots), "arrival": state, "final_state": final_state,
                          "opening": opening, "complete_opening_milestone": completed}
                (args.report / "result.json").write_text(json.dumps(result, indent=2) + "\n")
                driver.issue("quit")
                if process.wait(timeout=15) != 0:
                    raise RuntimeError("Campaign shutdown failed")
            except Exception as error:
                # A natural death may verify the reload boundary while the route
                # itself remains failed. Do not retry gameplay from the same save.
                observation_error = None
                try:
                    failed = driver.observe()
                except Exception as failure:
                    observation_error = str(failure)
                    failed = None
                (args.report / "failure.json").write_text(json.dumps({
                    "identity": identity, "error": str(error), "observed_failure_state": failed,
                    "last_observed_state": driver._activity_sample,
                    "observation_error": observation_error,
                    "scope": "Failed route; last observation is historical if the engine disconnected."
                }, indent=2) + "\n")
                slot = "intro_resume" if args.checkpoint else "opening_arrival" if (home / "state/dk3/saves/opening_arrival.sav").exists() else None
                if failed and failed["health"] <= 0 and slot:
                    restored = driver.load(slot)
                    if restored["health"] <= 0 or restored["mode"] != "normal":
                        raise RuntimeError("Death reload failed to restore a living player") from error
                    capture("death-reload-restored")
                    (args.report / "death-reload.json").write_text(json.dumps({
                        "identity": identity, "route_failed": str(error), "slot": slot,
                        "scope": "Natural death and acknowledged gameplay restoration only; the route remains failed.",
                        "death": failed, "restored": restored}, indent=2) + "\n")
                raise
            finally:
                (args.report / "inputs.json").write_text(json.dumps({"launch": command, "inputs": inputs}, indent=2) + "\n")
                if ui:
                    ui.close()
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--prefix", type=Path, help="Runtime source; defaults to the immutable --engine installation")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--opening", action="store_true", help="Continue with ordinary-input opening route development")
    parser.add_argument("--checkpoint-phase", choices=("arrival", "first-encounter", "marsh-middle", "marsh-late", "marsh-exit", "bridge-arrival", "bridge-control", "bridge-river", "bridge-health", "bridge-ford", "bridge-supplies", "bridge-climb", "bridge-crossing", "bridge-boss", "bridge-cleared", "factory-arrival", "factory-outside", "factory-gate", "factory-pipe", "factory-upper", "factory-passage", "factory-yard", "factory-yard-turn", "factory-interior", "factory-switch", "factory-departure", "factory-lower", "factory-exit"), default="arrival")
    parser.add_argument("--checkpoint-map", choices=("intro", "e1m1a", "e1m1b", "e1m1c"), default="intro")
    parser.add_argument("--checkpoint", type=Path, help="Legitimate checkpoint for development replay; never fresh campaign acceptance")
    args = parser.parse_args()
    phase_map = "e1m1c" if args.checkpoint_phase.startswith("factory-") else "e1m1b" if args.checkpoint_phase.startswith("bridge-") else "e1m1a"
    if args.checkpoint_phase != "arrival" and not (args.checkpoint and args.checkpoint_map == phase_map and args.opening):
        parser.error("A later route phase requires a legitimate checkpoint in its map and --opening")
    if args.checkpoint_map == "e1m1b" and not args.checkpoint_phase.startswith("bridge-"):
        parser.error("A bridge checkpoint requires its bridge phase")
    if args.checkpoint_map == "e1m1c" and not args.checkpoint_phase.startswith("factory-"):
        parser.error("A factory checkpoint requires its factory phase")
    args.engine = args.engine.resolve()
    args.prefix, args.report = (args.prefix or args.engine).resolve(), args.report.resolve()
    run(args)


if __name__ == "__main__":
    main()
