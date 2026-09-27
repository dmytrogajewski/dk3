# SPDX-License-Identifier: GPL-2.0-or-later
"""Captured shallow-pond jump regression; separate from campaign traversal."""
import hashlib
import json
import shutil
import time

from runtime_opening_route import actors


def scenario(driver, report, checkpoint):
    if checkpoint is None:
        raise RuntimeError("Frog landing regression requires the captured native campaign checkpoint")
    fixture = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
    if fixture != "26f2a9c7c891ebbd13de6202baaea4fb014485d2795bd60a8cfe38f5f8b1304f":
        raise RuntimeError("This regression requires the captured descending-jump checkpoint")
    saves = driver.home / "state/dk3/saves"
    saves.mkdir(parents=True, exist_ok=True)
    shutil.copy2(checkpoint, saves / "frog_landing.sav")
    state = driver.load("frog_landing")
    if state["map"] != "e1m1a" or state["skill"] != 3 or state["health"] <= 0:
        raise RuntimeError("Captured pond setup did not restore a living normal-difficulty player")
    selected = (27,)
    before = actors(driver)
    for identity in selected:
        row = before[identity]
        if row["class"] != "monster_froginator" or row["health"] <= 0:
            raise RuntimeError(f"Captured frog {identity} did not restore alive")
        # The exact captured save contains an airborne jump. The repaired engine
        # may land during the acknowledged restoration frames before this sample.
        if row["frog"] != "jump" and row["ground"] == "2047":
            raise RuntimeError(f"Frog {identity} neither continued its jump nor landed")
    landed = {}
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and len(landed) != len(selected):
        for identity, row in actors(driver).items():
            if identity in selected and row["frog"] != "jump" and row["ground"] != "2047":
                landed[identity] = row
    evidence = {"checkpoint_sha256": fixture, "before": {i: before[i] for i in selected}, "landed": landed,
                "scope": "Captured low-bounce frog landing only; no campaign traversal acceptance."}
    (report / "frog-landings.json").write_text(json.dumps(evidence, indent=2) + "\n")
    if len(landed) != len(selected):
        raise RuntimeError(f"Frogs never completed floor contact: {set(selected) - landed.keys()}")
    return evidence
