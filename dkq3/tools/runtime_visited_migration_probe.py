#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Restore an unmodified older native save and inspect its visited worlds in-engine."""
import argparse
import hashlib
import json
import re
import shutil
import struct
import zlib
from pathlib import Path

from runtime_bugfix_probe import run
from runtime_opening_route import actors
from runtime_region_progression_probe import event


def records(raw):
    assert raw[:8] == b'DK3SAVE\0'
    version, length, count, checksum = struct.unpack_from('<IIII', raw, 8)
    assert version == 1 and length == len(raw) and zlib.crc32(raw[24:]) == checksum
    cursor = 24
    result = []
    for _ in range(count):
        size, identity, fields_count, name_length, reserved = struct.unpack_from('<IIHBB', raw, cursor)
        assert reserved == 0
        name = raw[cursor + 12:cursor + 12 + name_length].decode()
        at = cursor + 12 + name_length
        fields = {}
        for _ in range(fields_count):
            kind, n, reserved, length = struct.unpack_from('<BBHI', raw, at)
            assert reserved == 0 and kind in (1, 2, 3, 4)
            at += 8
            key = raw[at:at + n].decode()
            at += n
            length *= 4 if kind in (1, 2) else 1
            assert key not in fields
            fields[key] = raw[at:at + length]
            at += length
        assert at == cursor + size
        result.append((name, identity, fields))
        cursor += size
    assert cursor == len(raw)
    return result


def world(raw):
    rows = records(raw)
    assert rows[0][0] == 'campaign'
    header = json.loads(rows[0][2]['state'])
    entities = {identity: {key: json.loads(value) for key, value in fields.items()}
                for name, identity, fields in rows if name == 'native_entity'}
    members = {fields['map'].decode(): fields['snapshot']
               for name, _, fields in rows if name in ('visited_level', 'resident_level')}
    return rows[0][2]['map'].decode(), header, entities, members


def migration(driver, report, capture, fixture):
    raw = fixture.read_bytes()
    source_hash = hashlib.sha256(raw).hexdigest()
    map_name, header, entities, archives = world(raw)
    assert map_name == 'e1m1c' and set(archives) == {'e1m1a', 'e1m1b'}
    assert header.get('namespace') is None and header['player_id'] == 574
    expected_health = entities[header['player_id']]['health']['current']
    saves = driver.home / 'state/dk3/saves'
    saves.mkdir(parents=True, exist_ok=True)
    shutil.copy2(fixture, saves / 'old_visited.sav')
    start = len(driver.text())
    restored = driver.load('old_visited')
    event(driver, 'dk3 region: initial admission committed', start)
    assert restored['map'] == map_name and restored['player_id'] == header['player_id']
    assert restored['health'] == expected_health
    for name in archives:
        event(driver, f'dk3 region: visited archive admitted map={name}', start)
        event(driver, f'map={name} stage=client_ready', start)
    save = driver.save('migrated_region')
    shutil.copy2(save, report / save.name)
    saved_map, saved_header, saved_entities, residents = world(save.read_bytes())
    assert saved_map == map_name and saved_header['player_id'] == header['player_id']
    assert saved_entities[header['player_id']]['health']['current'] == expected_health
    evidence = {}
    for name, original in archives.items():
        _, old_header, old_entities, _ = world(original)
        _, new_header, new_entities, _ = world(residents[name])
        namespace = new_header['namespace']
        assert namespace > 0 and new_header['player_id'] == 0
        assert not any('player' in entity for entity in new_entities.values())
        expected = {namespace << 24 | identity: entity['health']['current']
                    for identity, entity in old_entities.items() if 'actor' in entity}
        assert expected and any(health <= 0 for health in expected.values()), name
        boundary = {int(identity): int(health) for owner, identity, health in re.findall(
            r'dk3 restore actor: map=(\w+) id=(\d+) health=(-?\d+) at=\d+', driver.text()[start:]) if owner == name}
        assert f'dk3 restore actors complete: map={name} ' in driver.text()[start:]
        assert boundary == expected, (name, expected, boundary)
        retired = {int(identity) for owner, identity, reason in re.findall(
            r'dk3 actor retired: map=(\w+) id=(\d+) reason=(gibbed|turret) at=\d+', driver.text()[start:]) if owner == name}
        for identity, health in expected.items():
            if identity in new_entities:
                assert new_entities[identity]['health']['current'] == health, (name, identity)
            else:
                assert health <= 0 and identity in retired, (name, identity, health)
        evidence[name] = dict(namespace=namespace, actors=expected, restoration_boundary=boundary,
                              archived_player=old_header['player_id'])
    # Controlled transfer permits direct inspection of each actual restored ECS.
    # The old worlds are already admitted; placement avoids crossing an exit while
    # measuring. No health/equipment/world-state modifications are made.
    for name in archives:
        presentation_start = len(driver.text())
        point = '-752 -1400 525' if name == 'e1m1a' else '-544 -1392 533'
        driver.issue(f'dk3_runtime_enter_world {name}; dk3_runtime_place {point}')
        state = driver.until(lambda s: s['map'] == name)
        assert state['player_id'] == header['player_id']
        actual = actors(driver)
        retired = []
        for identity, health in evidence[name]['actors'].items():
            if identity not in actual:
                # The boundary audit must prove this actor was restored first;
                # only an observed class-owned retirement permits later absence.
                retired_ids = {int(value) for owner, value in re.findall(
                    r'dk3 actor retired: map=(\w+) id=(\d+) reason=(?:gibbed|turret) at=\d+', driver.text()[start:]) if owner == name}
                assert health <= 0 and identity in retired_ids, (name, identity, health, state)
                retired.append(identity)
            else:
                assert actual[identity]['health'] == health, (name, identity, health, actual[identity])
        evidence[name]['retired_after_restore'] = retired
        event(driver, 'dk3 world presentation: entered=', presentation_start)
        capture(f'{name}-migrated')
    # A second actual load must use schema-2 residents, not migrate the same
    # archives again or duplicate their entities.
    start = len(driver.text())
    # Exercise the legitimate race explicitly: queue another world handoff and
    # a load in the same console batch, before its presentation command executes.
    driver.issue('dk3_runtime_enter_world e1m1a; load migrated_region')
    event(driver, 'dk3 region: restoration committed', start)
    event(driver, 'dk3 zig client: restoration applied', start)
    reloaded = driver.until(lambda s: s['map'] == map_name, seconds=120)
    assert reloaded['map'] == map_name and reloaded['player_id'] == header['player_id']
    assert 'visited archive admitted' not in driver.text()[start:]
    assert 'obsolete=dk3_world_enter' in driver.text()[start:]
    assert hashlib.sha256(fixture.read_bytes()).hexdigest() == source_hash
    return dict(scope='Unmodified sequence-294 native save with two flat visited archives, actual load, namespace migration, all archived actor health including dead actors, controlled inspection in both maps, schema-2 save and second load. No fresh campaign or ordinary traversal claim.',
                source=str(fixture), source_sha256=source_hash, restored=restored, reloaded=reloaded, worlds=evidence)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--fixture', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl2')
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.scenario = 'visited-migration'
    args.restore_audit = True
    run(args, lambda driver, report, capture: migration(driver, report, capture, args.fixture.resolve()))
