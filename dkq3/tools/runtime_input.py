#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Normal-input synchronization. Mutating fixtures require an explicit diagnostic driver."""
import json
from pathlib import Path
import re
import time

from runtime_probe import send, wait


class NativeInput:
    def __init__(self, process, pipe, log, home, inputs, *, diagnostic=False):
        if not __debug__:
            raise RuntimeError("Native acceptance requires Python assertions enabled")
        self.process, self.pipe, self.log, self.home = process, pipe, log, home
        self.inputs, self.diagnostic, self.serial = inputs, diagnostic, 0
        self.forward_ms = 0
        self._activity_sample = None

    def text(self):
        return self.log.read_text(errors="replace")

    def issue(self, command):
        verb = command.split()[0]
        allowed = {"weapon", "attribute", "save", "load", "use", "dk3_look", "viewpos", "screenshotJPEG",
                   "dk3_runtime_observe", "dk3_runtime_actors", "dk3_runtime_world",
                   "dk3_runtime_items", "dk3_runtime_character", "dk3_runtime_projectiles", "dk3_runtime_beams", "dk3_runtime_ion_aim", "dk3_runtime_movers", "quit"}
        buttons = {sign + name for sign in ("+", "-") for name in
                   ("forward", "back", "moveleft", "moveright", "moveup", "movedown", "attack", "speed")}
        if not self.diagnostic and (verb not in allowed | buttons or ";" in command or "\n" in command):
            raise ValueError(f"Command is outside ordinary campaign input: {command}")
        self.inputs.append({"command": command, "synchronization": "observed state"})
        send(self.pipe, command)

    def observe(self):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            result, offset = self._observe_once()
            if not result.get("connecting"):
                previous = self._activity_sample
                if previous and result.get("mode") == previous.get("mode") == "normal" and result.get("map") == previous.get("map"):
                    if result.get("forward", 0) > 0 and previous.get("forward", 0) > 0:
                        self.forward_ms += max(0, result["cmd"] - previous["cmd"])
                self._activity_sample = result
                return result
            # A map handoff may accept console commands before ClientBegin.
            # Wait for the connection event, including one emitted just after
            # the pending response, then request authoritative state again.
            wait(self.process, self.log, lambda text, offset=offset:
                 "player entered isolated movement runtime" in text[offset:] or
                 "ERROR: Zig runtime:" in text[offset:], max(0.1, deadline - time.monotonic()))
        raise TimeoutError("Native player connection did not finish")

    def _observe_once(self):
        prior = self.text()
        if "ERROR: Zig runtime:" in prior:
            raise RuntimeError(next(line for line in reversed(prior.splitlines()) if "ERROR: Zig runtime:" in line))
        self.serial += 1
        marker = f"dk3 observe {self.serial}: "
        before = len(self.text())
        self.issue(f"dk3_runtime_observe {self.serial}")
        text = wait(self.process, self.log, lambda value: marker in value[before:] or "ERROR: Zig runtime:" in value[before:], 5)[before:]
        if "ERROR: Zig runtime:" in text:
            raise RuntimeError(next(line for line in text.splitlines() if "ERROR: Zig runtime:" in line))
        line = next(line.split(marker, 1)[1] for line in text.splitlines() if marker in line)
        result = {}
        for key, value in re.findall(r"(\w+)=([^ ]+)", line):
            result[key] = tuple(map(float, value.split(","))) if key in ("pos", "angles") else value if key in ("mode", "map") else int(value)
        self.inputs.append({"observed": result})
        return result, before

    def until(self, predicate, *, seconds=10, description="expected native state"):
        deadline = time.monotonic() + seconds
        last = None
        while time.monotonic() < deadline:
            last = self.observe()
            if last["processed"] and predicate(last):
                return last
        raise TimeoutError(f"{description}: last observation {last}")

    def ready(self, weapon=None):
        return self.until(lambda s: s["ready"] and (weapon is None or s["weapon"] == weapon), description="weapon ready")

    def select(self, weapon):
        self.issue(f"weapon {weapon}")
        return self.ready(weapon)

    def stop_forward(self, *, settle_vertical=False):
        """Release acknowledgement precedes physical stopping under friction."""
        self.issue("-forward")
        previous = self.until(lambda s: s["forward"] == 0, description="processed forward release")

        def stationary(state):
            nonlocal previous
            if state["map"] != previous["map"]:
                raise RuntimeError("Unexpected map transition while stopping")
            # A released swimmer can still be carried by authored currents.
            # Steering resumes from the observed moving position in that case.
            if state.get("water", 0) > 1:
                return state["forward"] == 0
            elapsed = state["cmd"] - previous["cmd"]
            if elapsed < 50:
                return False
            distance = sum((state["pos"][i] - previous["pos"][i]) ** 2 for i in range(3 if settle_vertical else 2)) ** 0.5
            previous = state
            return state["forward"] == 0 and distance * 1000 / elapsed < 1

        return self.until(stationary, seconds=3, description="horizontal motion settled after release")

    def aim(self, yaw, pitch):
        limit = 16000 * 360 / 65536  # Authoritative movement short-angle clamp.
        pitch = max(-limit, min(limit, pitch))
        self.issue(f"dk3_look {yaw} {pitch}")
        def close(a, b):
            return abs((a - b + 180) % 360 - 180) < 0.03
        return self.until(lambda s: close(s["angles"][0], pitch) and close(s["angles"][1], yaw), description="processed view angles")

    def fire(self):
        previous = self.ready()
        self.issue("+attack")
        try:
            return self.until(lambda s: s["event"] != previous["event"] and s["fire"] != previous["fire"], description="actual fire event")
        finally:
            self.issue("-attack")
            self.until(lambda s: not s["buttons"] & 1, description="processed attack release")

    def elapsed(self, milliseconds):
        start = self.observe()["cmd"]
        return self.until(lambda s: s["cmd"] >= start + milliseconds,
                          seconds=milliseconds / 1000 + 5, description="processed command time")

    def diagnostics(self, command, marker):
        before = len(self.text())
        self.issue(command)
        text = wait(self.process, self.log, lambda text: marker in text[before:], 5)[before:]
        self.inputs.append({"diagnostic": command, "result": text})
        return text

    def save(self, slot):
        before = len(self.text())
        self.issue(f"save {slot}")
        result = wait(self.process, self.log, lambda text: "dk3 zig: world saved" in text[before:]
                      or "Save/load refused:" in text[before:], 10)[before:]
        if "Save/load refused:" in result:
            raise RuntimeError(next(line for line in result.splitlines() if "Save/load refused:" in line))
        path = self.home / f"state/dk3/saves/{slot}.sav"
        if not path.exists() or not path.read_bytes().startswith(b"DK3SAVE"):
            raise RuntimeError(f"Save completion did not produce a native save: {slot}")
        self.last_save = slot
        return path

    def load(self, slot):
        before = len(self.text())
        self.issue(f"load {slot}")
        result = wait(self.process, self.log, lambda text: ("saved world restored" in text[before:] and
             "dk3 zig client: restoration applied" in text[before:]) or "Save/load refused:" in text[before:], 15)[before:]
        if "Save/load refused:" in result:
            raise RuntimeError(next(line for line in result.splitlines() if "Save/load refused:" in line))
        restored = self.until(lambda _: True, description="restored input processing")
        self.last_save = slot
        return restored


def record_identity(engine, prefix, report):
    """Hash the actual executable, modules, shaders and admitted local packages."""
    import hashlib
    files = [engine / "bin/dk3"]
    files += sorted((prefix / "lib/dk3").glob("*.so"))
    files += sorted((prefix / "share/dk3/scripts").glob("*.shader"))
    files += sorted((engine / "share/dk3").glob("*.pk3"))
    # Renderers can be built in or adjacent to the engine executable.
    files += sorted((engine / "bin").glob("*renderer*.so"))
    records = {str(path): hashlib.file_digest(path.open("rb"), "sha256").hexdigest() for path in files}
    digest = hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest()
    (report / "identity.json").write_text(json.dumps({"sha256": digest, "files": records}, indent=2) + "\n")
    return digest
