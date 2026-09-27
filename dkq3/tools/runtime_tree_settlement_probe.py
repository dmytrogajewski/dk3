# SPDX-License-Identifier: GPL-2.0-or-later
"""Focused health-tree floor, restoration and use regression; diagnostic setup."""
import math
import shutil

from runtime_bridge_route import aim_at, world_rows
from runtime_probe import wait


def scenario(driver, report):
    if not driver.diagnostic:
        raise ValueError("Tree settlement fixture requires diagnostic mode")
    driver.until(lambda s: s["map"] == "e1m1b" and s["skill"] == 3 and s["mode"] == "normal", description="fresh bridge fixture")
    driver.elapsed(4000)
    initial = world_rows(driver, "tree")
    for identity, expected in ((110, (-2032, -432)), (139, (192, -672))):
        tree = initial[identity]
        assert math.dist(tree["pos"][:2], expected) < 4, f"Tree {identity} slid away from authored floor: {tree}"
    save = driver.save("trees_settled")
    shutil.copy2(save, report / save.name)
    driver.elapsed(4000)
    later = world_rows(driver, "tree")
    for identity in (110, 139):
        assert math.dist(initial[identity]["pos"], later[identity]["pos"]) < 0.01
    driver.load("trees_settled")
    driver.elapsed(4000)
    restored = world_rows(driver, "tree")
    for identity in (110, 139):
        assert math.dist(initial[identity]["pos"], restored[identity]["pos"]) < 0.01
        assert restored[identity]["fruit"] == initial[identity]["fruit"]
    driver.diagnostics("dk3_runtime_face_target 110 64", "target=110")
    driver.issue("dk3_runtime_probe_health 50")
    driver.until(lambda s: s["health"] == 50, description="controlled healing need")
    aim_at(driver, restored[110]["pos"])
    before = len(driver.text())
    driver.issue("use")
    wait(driver.process, driver.log, lambda text: "dk3 tree: id=110 fruit=4" in text[before:], 3)
    driver.until(lambda s: s["health"] == 60, description="actual fruit healing")
    driver.save("tree_used")
    driver.load("tree_used")
    assert world_rows(driver, "tree")[110]["fruit"] == "4"
    driver.issue("screenshotJPEG tree-settled-restored")
    image = driver.home / "dk3/screenshots/tree-settled-restored.jpg"
    wait(driver.process, driver.log, lambda _: image.exists() and image.stat().st_size > 0, 5)
    shutil.copy2(image, report / image.name)
    return {"scope": "Fresh sloped and flat tree settlement, timed stability before/after restoration, one actual use and partial-fruit restoration. Diagnostic placement and health for use; no connected campaign acceptance.", "initial": {i: initial[i] for i in (110, 139)}, "restored": {i: restored[i] for i in (110, 139)}}
