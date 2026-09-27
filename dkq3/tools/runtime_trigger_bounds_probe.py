# SPDX-License-Identifier: GPL-2.0-or-later
"""Focused trigger-angle regression, with explicit diagnostic placement."""
import math
from runtime_probe import wait


def scenario(driver, report):
    if not driver.diagnostic:
        raise ValueError("Trigger regression requires diagnostic placement")
    driver.until(lambda s: s["map"] == "e1m1a" and s["mode"] == "normal", description="trigger regression connected")
    # Ordinary progression first exposed the false exit near this point, over
    # a thousand units from the authored brush. Keep the exact defective case.
    driver.issue("dk3_runtime_place 410 -1750 488")
    state = driver.until(lambda s: s["map"] != "e1m1a" or math.dist(s["pos"], (410, -1750, 488)) < 8, description="diagnostic placement applied")
    if state["map"] != "e1m1a":
        raise RuntimeError("Regression reproduced: authored angle rotated/expanded the trigger and caused a remote exit")
    start = state["now"]
    driver.until(lambda s: s["map"] != "e1m1a" or s["now"] >= start + 500, description="several native touch frames observed")
    if driver.observe()["map"] != "e1m1a":
        raise RuntimeError("Regression reproduced: player outside exit bounds changed level")
    driver.save("trigger_bounds")
    driver.load("trigger_bounds")
    state = driver.observe()
    if state["map"] != "e1m1a":
        raise RuntimeError("Restoration reintroduced rotated trigger bounds")
    start = state["now"]
    driver.until(lambda s: s["map"] != "e1m1a" or s["now"] >= start + 500, description="restored trigger touch frames observed")
    if driver.observe()["map"] != "e1m1a":
        raise RuntimeError("Restored world falsely triggered a remote exit")
    # Authored e1m1a brush *2 spans x -608..-592, y -1480..-1288,
    # z 488..704; a valid interior touch must still travel normally.
    before = len(driver.text())
    driver.issue("dk3_runtime_place -600 -1384 550")
    wait(driver.process, driver.log, lambda text: "traveler entered authored landing" in text[before:], 30)
    state = driver.until(lambda s: s["map"] == "e1m1b" and s["mode"] == "normal", description="actual authored exit contact")
    return {"scope": "Trigger angle no longer expands touch bounds; remote point stays e1m1a before/after save-load, real brush contact reaches e1m1b. Diagnostic placements, not campaign traversal.", "arrival": state}
