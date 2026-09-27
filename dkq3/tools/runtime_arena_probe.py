# SPDX-License-Identifier: GPL-2.0-or-later
"""Protected arena damage diagnosis; never ordinary campaign acceptance."""
import json
import shutil

from runtime_arena_combat import battle
from runtime_bridge_route import collect_boss_drop
from runtime_opening_route import actors
from runtime_probe import wait


def scenario(driver, report, checkpoint):
    if not driver.diagnostic or checkpoint is None:
        raise RuntimeError('Arena damage diagnosis requires an explicit checkpoint fixture')
    saves = driver.home / 'state/dk3/saves'
    saves.mkdir(parents=True, exist_ok=True)
    shutil.copy2(checkpoint, saves / 'arena_damage.sav')
    before = driver.load('arena_damage')
    bosses = [row for row in actors(driver).values() if row['unique'] == 'tskeet']
    if before['map'] != 'e1m1b' or before['skill'] != 3 or before['health'] <= 0 or len(bosses) != 1 or bosses[0]['health'] <= 0:
        raise RuntimeError('Arena fixture did not restore its living player and authored boss')
    driver.issue('dk3_runtime_probe_health 10000')
    driver.until(lambda s: s['health'] == 10000, description='diagnostic protection confirmed')

    def capture(name):
        driver.issue(f'screenshotJPEG {name}')
        source = driver.home / f'dk3/screenshots/{name}.jpg'
        wait(driver.process, driver.log, lambda _: source.is_file() and source.stat().st_size > 0, 5)
        shutil.copy2(source, report / source.name)

    offset = len(driver.inputs)
    contacts, waves = battle(driver, capture)
    collect_boss_drop(driver, capture, report)
    injuries, prior = [], before
    for row in driver.inputs[offset:]:
        state = row.get('observed')
        if state is None:
            continue
        if state['hurt_revision'] != prior['hurt_revision']:
            injuries.append({key: state[key] for key in ('now', 'health', 'armor', 'player_id', 'hurt', 'hurt_at', 'hurt_revision', 'source', 'hit_weapon', 'pos', 'water')})
        prior = state
    if not contacts or not injuries:
        raise RuntimeError('Arena diagnosis requires both real weapon contact and actual incoming damage')
    result = dict(scope='Restored arena with diagnostic 10000 health. Actual combat damage receipts and reward contact only; no campaign acceptance.',
                  starting_state=before, contacts=contacts, waves=sorted(waves), injuries=injuries, final_state=driver.observe())
    (report / 'arena-damage.json').write_text(json.dumps(result, indent=2) + '\n')
    return result
