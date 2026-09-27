#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Native menu, real Escape skip, loading artwork and rendered interpolation regression."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
import time

from runtime_input import NativeInput, record_identity
from runtime_probe import client_settings, stage_client_modules, send, wait
from runtime_ui_probe import Input


def run(args):
    if not __debug__ or (args.report.exists() and any(args.report.iterdir())):
        raise RuntimeError("Presentation evidence requires assertions and a fresh directory")
    args.report.mkdir(parents=True, exist_ok=True)
    identity = record_identity(args.engine, args.engine, args.report, require_installation=True)
    inputs, plaques = [], []
    result = dict(identity=identity, scope="Normal New Game menu, real XTest Escape skips, supplied loading artwork, rendered frame blending, save/load and pause/resume. Skipped intro is not fresh campaign acceptance.")
    with tempfile.TemporaryDirectory(prefix="dk3-native-presentation-") as temporary:
        home = Path(temporary)
        stage_client_modules(args.engine, home, installation=args.engine)
        settings = client_settings(args.engine, home, args.renderer)
        settings.update(dk3_cinematics="1", g_spSkill="3", in_nograb="1", developer="1")
        settings["s_useOpenAL"] = "1" if args.audio == "openal" else "0"
        command = [str(args.engine / "bin/dk3")]
        for key, value in settings.items():
            command += ["+set", key, value]
        log = args.report / "client.log"
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            driver = NativeInput(process, home / "dk3/commands.fifo", log, home, inputs)
            window = None
            done = threading.Event()

            def loading_frames():
                seen = 0
                while not done.is_set():
                    rows = re.findall(r"dk3 loading: artwork=(\w+)", log.read_text(errors="replace"))
                    for index in range(seen, len(rows)):
                        name = f"loading-{index}-{rows[index]}.png"
                        capture = subprocess.run(["import", "-window", "root", str(args.report / name)], capture_output=True, timeout=5)
                        plaques.append(dict(artwork=rows[index], capture=name, status=capture.returncode))
                    seen = len(rows)
                    done.wait(0.02)

            watcher = threading.Thread(target=loading_frames, daemon=True)
            watcher.start()

            def capture(name):
                send(driver.pipe, f"screenshotJPEG {name}")
                source = home / f"dk3/screenshots/{name}.jpg"
                wait(process, log, lambda _: source.exists() and source.stat().st_size > 0, 10)
                shutil.copy2(source, args.report / source.name)

            try:
                wait(process, log, lambda text: "native menus initialized" in text and driver.pipe.exists())
                if args.audio == "openal" and "OpenAL info:" not in driver.text():
                    raise RuntimeError("Requested OpenAL backend was not actually initialized")
                window = Input(inputs)
                capture("new-game-menu")
                window.align_menu()
                window.click(530, 190)
                capture("sound-controls")
                window.click(530, 83)
                window.click(278, 350)
                intro = driver.until(lambda s: s["map"] == "intro" and s["cinematic"] and s["mode"] == "frozen", seconds=45, description="normal menu starts the actual intro")
                if intro["skill"] != 3:
                    raise RuntimeError("Normal difficulty selection failed")
                # The first establishing shot has no performers; the second
                # starts Hiro in a held pose. Wait for the authored close-up.
                driver.until(lambda s: s["map"] == "intro" and s["cinematic"] and s["shot"] >= 2,
                             seconds=25, description="authored animated Hiro shot is active")
                deadline = time.monotonic() + 10
                samples = []
                while time.monotonic() < deadline:
                    text = driver.diagnostics("dk3_runtime_presentation", "dk3 presentation:")
                    match = re.search(r"dk3 presentation: now=(\d+) camera=(\d+) models=(\d+) blended=(\d+) entity=(\d+) frame=(\d+) oldframe=(\d+) backlerp=([\d.]+)", text)
                    if match:
                        row = dict(zip(("now", "camera", "models", "blended", "entity", "frame", "oldframe"), map(int, match.groups()[:7])))
                        row["backlerp"] = float(match[8])
                        samples.append(row)
                        if len([s for s in samples if s["blended"] > 0 and s["frame"] != s["oldframe"] and 0 < s["backlerp"] < 1]) >= 3:
                            break
                else:
                    raise RuntimeError("Running renderer did not show actual intermediate animation poses")
                capture("intro-interpolated")
                transition = len(driver.text())
                window.key("Escape")
                arrival = driver.until(lambda s: s["map"] == "e1m1a" and s["cinematic"] and s["mode"] == "frozen", seconds=45, description="Escape completes intro cleanup and authored map exit")
                # Server ClientBegin precedes the rendered client's admission.
                # Escape during connection cancels that connection by design.
                wait(process, log, lambda text: "first snapshot applied" in text[transition:], 15)
                driver.until(lambda s: s["map"] == "e1m1a" and s["cinematic"] and s["input"] > 0,
                             description="arrival client is submitting actual user commands")
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if "camera=1" in driver.diagnostics("dk3_runtime_presentation", "dk3 presentation:"):
                        break
                else:
                    raise RuntimeError("Arrival camera was never applied by the renderer")
                window.key("Escape")
                playing = driver.until(lambda s: s["map"] == "e1m1a" and not s["cinematic"] and s["mode"] == "normal", description="Escape releases arrival cinematic control")
                if playing["health"] != 100 or playing["weapon"] != 1:
                    raise RuntimeError("Skip changed ordinary starting health/inventory")
                saved = driver.save("presentation_resume")
                shutil.copy2(saved, args.report / saved.name)
                restored = driver.load("presentation_resume")
                capture("skipped-arrival-restored")
                window.key("Escape")
                capture("ordinary-pause-menu")
                window.key("Escape")
                driver.elapsed(100)
                if log.read_text(errors="replace").count("dk3 cinematic: completed") < 2:
                    raise RuntimeError("Both skips must execute actual completion paths")
                if not any(row["artwork"] == "e1m1" and row["status"] == 0 for row in plaques):
                    raise RuntimeError("Actual e1m1 chapter loading-screen capture is missing")
                result.update(status="passed", intro=intro, arrival=arrival, playing=playing, restored=restored, interpolation=samples)
                driver.issue("quit")
                if process.wait(timeout=15) != 0:
                    raise RuntimeError("Presentation scenario shutdown failed")
            except Exception as error:
                result.update(status="failed", error=str(error))
                raise
            finally:
                done.set()
                watcher.join(timeout=6)
                result["loading_captures"] = plaques
                (args.report / "result.json").write_text(json.dumps(result, indent=2) + "\n")
                (args.report / "inputs.json").write_text(json.dumps(dict(launch=command, inputs=inputs), indent=2) + "\n")
                if window:
                    window.close()
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--renderer", choices=("opengl1", "opengl2"), default="opengl1")
    parser.add_argument("--audio", choices=("software", "openal"), default="software")
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    run(args)
