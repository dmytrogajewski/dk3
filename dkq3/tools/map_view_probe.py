# SPDX-License-Identifier: GPL-2.0-or-later
"""Photograph a multiplayer map the way a player arrives at it.

`map_sightlines` answers which shots exist; it cannot say whether the wall a shot
stops against has a face, or whether the neon the shader promises actually lands
on the street.  This tool hosts the installed map on a dedicated server, joins it
with the ordinary client, puts the camera on each authored deathmatch start, faces
the angle that start was written with, and takes the frame a player would see.

A capture is only evidence together with its identity, so the installed package's
bytes and digest, the engine binary digest and the renderer cvar travel with the
JPEGs, and a frame that comes back black fails the run instead of quietly filling
a report.

Run it inside dkguard.  Under `--headless` the frames come from the OpenGL 2
renderer running on the software stack: the same normal, specular and deluxemap
path the owner's GPU uses, without claiming hardware rendering.
"""
import argparse
import contextlib
import hashlib
import json
import math
import re
import shutil
import socket
import subprocess
import tempfile
from pathlib import Path

import map_sightlines
from runtime_input import NativeInput
from runtime_probe import client_settings, stage_client_modules, wait

# What the console prints that says who drew the frame and what it was given.
RENDERER_EVIDENCE = ('GL_VERSION', 'GL_RENDERER', 'OpenGL', 'renderer', 'deluxe', 'lightmap')


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def free_port():
    """-> an unused UDP port on the loopback address.

    The camera joins a real server, so the run owns two engine processes and both
    need a port; a fixed alternative collides with the next probe just as reliably
    as 27960 does with the one before it.
    """
    with contextlib.closing(socket.socket(socket.AF_INET, socket.SOCK_DGRAM)) as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def map_lines(text, needle):
    """-> the console lines that name the map, so the report shows what was loaded."""
    return [line.strip()[:160] for line in text.splitlines()
            if needle in line.lower()][:24]

def authored_labels(text):
    """-> {entity index: the name the author gave the object}, from the .map comments.

    `quake_map.write_map` writes `// entity 56 (spawn_w_lane_s)` above every block, and
    the reader hands back `info_player_deathmatch 56` because a label has to be unique.
    A photograph wants the authored name: it is what the design notes, the Blender scene
    and a bug report all use.
    """
    return dict((int(index), name) for index, name in
                re.findall(r'// entity (\d+) \(([^)]*)\)', text))


#: What `dk3_runtime_place` wants for Z: the runtime's own spawnPose lifts the
#: written origin nine units and traces a hull whose mins z is -24, so a body
#: standing on a floor f carries its origin at f + 24.  Nine units higher and the
#: body starts in the air; the probe mode zeroes velocity and clears the ground
#: entity on every placement, and a body that is airborne and has been told it has
#: no ground does not answer the walk the way a standing one does.
BODY_ABOVE_FLOOR = 24.0


def walk_bodies(document, index, specs, starts):
    """-> one walk per `--walk` spec, standing on a floor the compiled map confirms.

    A hand-written Z is the reason a walk test silently photographs a frozen body:
    `dk3_runtime_place` accepts any coordinate, and a body put inside a brush or
    nine units above its tread reports `ground=2047` and never moves, which looks
    exactly like a staircase nobody can climb.  So the floor is measured here, from
    the exported faces, and the caller supplies only x, y, angle and (optionally)
    which of several stacked tiers to stand on.
    """
    named = {one['name']: one for one in starts}
    made = []
    for spec in specs:
        label, coordinates = spec.split('=', 1)
        if ' ' in label:
            raise SystemExit('--walk names must be one word: %s' % label)
        parts = coordinates.split(',')
        head, rest = parts[0].strip(), [float(value) for value in parts[1:]]
        if head.startswith('@'):
            host = named.get(head[1:])
            if host is None:
                raise SystemExit('--walk %s: %s is not an authored start (%s)'
                                 % (label, head[1:], ', '.join(sorted(named))))
            body, rest, angle, rise = host['body'], rest, rest[0], (rest[1] if len(rest) > 1 else 0.0)
            if not rest:
                raise SystemExit('--walk %s wants @START,ANGLE[,RISE]' % label)
        else:
            if len(rest) < 2:
                raise SystemExit('--walk %s wants NAME=X,Y,ANGLE[,RISE[,FLOOR]]' % label)
            x, y, angle = float(head), rest[0], rest[1]
            rise, hint = (rest[2] if len(rest) > 2 else 0.0), None
            if len(rest) > 3:
                rise, hint = rest[2], rest[3]
            # `reach` is not decoration: a face only reports a standing point 8
            # units inside its own outline (`EDGE_MARGIN`), and japanDM's treads
            # are 13 deep, so an unreached query finds no floor on a staircase at
            # all and the walk audit reports "no floor near 8 (see 1536)" -- the
            # sky's lid -- which reads exactly like an unclimbable flight.
            floors = map_sightlines.Index.floor_heights(index, x, y,
                                                        reach=map_sightlines.EDGE_MARGIN)
            standing = [floor for floor in floors
                        if index.cast((x, y, floor + 1.0), (x, y, floor + 57.0))[1] is None]
            if not standing:
                raise SystemExit('--walk %s: nothing to stand on at %g,%g (floors seen: %s)'
                                 % (label, x, y, ', '.join('%g' % f for f in floors) or 'none'))
            # The sky shell's lid at z 1536 is a face like any other to a sampler,
            # so "the highest floor" is always the lid.  Without a hint the caller
            # means the street, and every candidate is printed so a hint can be
            # added instead of a guess being quietly accepted.
            floor = min(standing, key=lambda value: abs(value - hint)) if hint is not None \
                else min(standing)
            if hint is None and len(standing) > 1:
                print('map-view: walk %s: %g chosen among floors %s at %g,%g -- pass a'
                      ' FLOOR to choose' % (label, floor,
                                            ', '.join('%g' % f for f in standing), x, y))
            if hint is not None and abs(floor - hint) > 40:
                raise SystemExit('--walk %s: no floor near %g at %g,%g (see %s)'
                                 % (label, hint, x, y, ', '.join('%g' % f for f in standing)))
            body = (x, y, floor + BODY_ABOVE_FLOOR)
        made.append(dict(name=label, body=tuple(body), angle=float(angle), air=True,
                         walk=(0.0, float(rise or 0.0)),
                         # The tread the face sampler found and the surface the
                         # movement code will stop on are the same plane, but the
                         # body has to be told about it from outside the brush.
                         settle=(0.0, 6.0, 12.0, 24.0, 48.0, 96.0, -6.0),
                         floor=round(body[2] - BODY_ABOVE_FLOOR, 1)))
    return made

def authored_starts(document, text):
    """-> one camera per authored deathmatch start, facing the angle it was written with.

    An authored spawn origin is a body centre, not a spot on the floor: the runtime's own
    `multiplayer.spawnPose` lifts the origin nine units and traces the player hull, whose
    mins z is -24, from there.  So feet sit 24 below the written origin, and the camera asks
    for the same centre with the same nine-unit lift -- exactly where a real spawn lands it.
    Asking for origin-24 instead puts the body inside its own floor, where it hangs forever
    reporting `ground=2047` and the run dies looking like a map with no floor in it.
    """
    labels = authored_labels(text)
    starts = []
    for entity in document.entities:
        if not entity.classname.startswith('info_player_'):
            continue
        origin = [float(value) for value in entity.keys['origin'].split()]
        index = int(entity.source.rsplit(' ', 1)[1])
        name = labels.get(index, entity.source.replace(' ', '_'))
        assert ' ' not in name, 'an authored object name must be one word: %s' % name
        starts.append(dict(name=name, body=(origin[0], origin[1], origin[2] + 9.0),
                           angle=float(entity.keys.get('angle', 0.0))))
    return starts


def frame(capture):
    """-> (mean, spread) of one capture over 0..1, read back from the JPEG.

    An unlit frame and an empty frame are the same grey to the eye and both are a
    renderer that drew nothing, so the pixels are asked directly instead of the
    console being trusted to have said something.
    """
    outcome = subprocess.run(
        ['magick', str(capture), '-colorspace', 'Gray', '-format',
         '%[fx:mean] %[fx:standard_deviation]', 'info:'],
        capture_output=True, text=True, check=True)
    mean, spread = outcome.stdout.split()[:2]
    return float(mean), float(spread)


class Camera:
    """One camera, two endpoints: the host owns the body, the client draws the frame.

    `dk3_runtime_place` and `dk3_runtime_observe` are server-side game commands, so on a
    real connection they belong to the dedicated host's console.  The joined client has no
    listen server of its own, and asking it for either answers nothing at all -- the wait
    simply expires and the run dies looking like a broken map.  `dk3_look` and the shutter
    are client commands and stay on the viewer.
    """

    def __init__(self, host, viewer, home, report):
        self.host, self.viewer, self.home, self.report = host, viewer, home, report

    def photograph(self, name):
        """-> the frame the viewer is drawing right now."""
        self.viewer.issue('screenshotJPEG %s' % name)
        source = self.home / ('dk3/screenshots/%s.jpg' % name)
        wait(self.viewer.process, self.viewer.log,
             lambda _: source.is_file() and source.stat().st_size > 0, 15)
        destination = self.report / source.name
        shutil.copy2(source, destination)
        mean, spread = frame(destination)
        return dict(image=destination.name, bytes=destination.stat().st_size,
                    sha256=sha256(destination), mean=mean, spread=spread)

    def walk_forward(self, seconds, expected_rise=0.0):
        """-> the track of one held-forward run: what the engine really walks.

        A sampling model of the compiled brush list can say a tread is too shallow
        to stand on and be wrong; this says what the shipped movement code did with
        the same stairs.  `step()` in the runtime steps 18 units per footfall, so a
        flight that will not carry a body held at full forward is a flight a player
        cannot use, whatever the geometry audit claims.

        The track is the evidence, not a pass/fail bit: the same run answers "did it
        climb", "did it stop dead at a wall", and "did it walk off a floating deck".
        """
        self.viewer.issue('+forward')
        first = self.host.observe()
        track = []
        grounded, airborne = 0, 0
        deadline = first['now'] + int(seconds * 1000)
        while True:
            state = self.host.observe()
            if state['ground'] == 2047:
                airborne += 1
            else:
                grounded += 1
            track.append((state['now'] - first['now'],
                          [round(value, 1) for value in state['pos']],
                          state['ground'] != 2047))
            if state['now'] >= deadline or len(track) > 400:
                break
        self.viewer.issue('-forward')
        self.host.until(lambda s: s['now'] > track[-1][0] + first['now'] + 400, seconds=20,
                        description='the body settle after the run')
        last = self.host.observe()
        rise = last['pos'][2] - first['pos'][2]
        run = math.hypot(last['pos'][0] - first['pos'][0], last['pos'][1] - first['pos'][1])
        # Three different failures wear the same face in a raw track, so name them
        # apart: a body that never moved was frozen or walled in; a body that was
        # never on the ground was placed inside a brush or over a void; and a body
        # grounded first and airborne later walked off the edge it was crossing.
        # The old `fell_off = airborne > 6` reported all three as falling, which is
        # how four flights came back "fell off" without moving one unit.
        return dict(track=track, samples=len(track), rise=round(rise, 1),
                    run=round(run, 1), grounded=grounded, airborne=airborne,
                    climbed=abs(rise) >= max(16.0, expected_rise * 0.5),
                    never_moved=run < 8.0, never_grounded=grounded == 0,
                    fell_off=airborne > 6 and grounded > 0)

    def stand(self, start):
        """-> the capture for one authored start.

        Placement is a probe command; facing and the shutter are ordinary input.
        `ground != 2047` is the engine saying the feet are on something: a floating
        camera photographs a void and calls it level design.  The facing is read back from
        the host rather than assumed, so the frame is only taken once the turn has crossed
        the network and the server has settled the body on the ground it is standing on.
        """
        self.host.issue('dk3_runtime_place %g %g %g' % start['body'])
        placed = self.host.until(
            lambda s: abs(s['pos'][0] - start['body'][0]) < 32
            and abs(s['pos'][1] - start['body'][1]) < 32, seconds=30,
            description='placement at the authored start')
        landed = None
        standing = True
        try:
            self.host.until(lambda s: s['ground'] != 2047, seconds=20,
                            description='feet on walkable ground')
        except TimeoutError:
            # An inspection camera that finds no floor under it has answered the
            # question it was sent to ask -- that is what an unreachable deck looks
            # like from its own height.  An authored start with no floor is still
            # fatal, because the map is supposed to hold a player there.
            if not start.get('air'):
                raise
            standing = False
            # A face sample and the physics hull disagree by a hair more often
            # than either is wrong, and a frozen body on the first try reads as
            # "these stairs cannot be climbed".  So an inspection body is asked
            # several times, a few units apart, and only a run that never finds
            # ground is reported as a place the engine will not stand a player.
            for offset in start.get('settle', ()):
                probe = (start['body'][0], start['body'][1], start['body'][2] + offset)
                self.host.issue('dk3_runtime_place %g %g %g' % probe)
                try:
                    self.host.until(lambda s: s['ground'] != 2047, seconds=6,
                                    description='feet on walkable ground')
                except TimeoutError:
                    continue
                placed = self.host.observe()
                standing, landed = True, offset
                break
            else:
                landed = None
        self.viewer.issue('dk3_look %g %g' % (start['angle'], start.get('pitch', 0.0)))
        faced = self.host.until(
            lambda s: abs((s['angles'][1] - start['angle'] + 180) % 360 - 180) < 0.03,
            seconds=30, description='view angle reported back by the camera client')
        self.host.until(lambda s: s['now'] > faced['now'] + 1200, seconds=30,
                        description='frames after facing')
        walked = None
        if start.get('walk'):
            seconds, expected_rise = start['walk']
            walked = self.walk_forward(seconds, expected_rise)
            self.host.issue('dk3_runtime_place %g %g %g' % start['body'])
            self.host.until(lambda s: abs(s['pos'][2] - start['body'][2]) < 40, seconds=30,
                            description='camera back on the rung it started from')
        row = self.photograph(start['name'])
        row.update(start=start['name'], placed=list(placed['pos']), angle=list(faced['angles']),
                   standing=standing, landed_by=landed, walk=walked)
        return row


def renderer_lines(text):
    """-> the console lines that say which renderer drew the frames."""
    return [line.strip()[:200] for line in text.splitlines()
            if any(marker in line for marker in RENDERER_EVIDENCE)][:40]


def run(args):
    """-> the report, and a failure if anything came back dark.

    The installed package is the subject: a map that is not in the tree the client
    loads from cannot be photographed, so a passing report always names the bytes a
    player would have downloaded.
    """
    if args.report.exists() and any(args.report.iterdir()):
        raise RuntimeError('view evidence requires a fresh report directory')
    args.report.mkdir(parents=True, exist_ok=True)
    package = args.engine / ('share/dk3/zz-dk3-%s.pk3' % args.map.lower())
    if not package.is_file():
        raise RuntimeError('%s is not installed in %s' % (args.map, args.engine))
    document = args.work / args.map / ('%s.map' % args.map)
    if not document.is_file():
        raise RuntimeError('%s is missing; compile the map first' % document)
    source_text = document.read_text(encoding='utf-8')
    # `document` is the path; the parsed map is what the walk audit and the solid
    # brush list need.  Naming both `document` made the walk pass hand a PosixPath
    # to a brush list and the probe died on `'PosixPath' object has no attribute
    # 'entities'` before it photographed anything.
    parsed = map_sightlines.read_map(document, map_sightlines.non_solid_shaders(args.materials))
    starts = authored_starts(parsed, source_text)
    for spec in args.view:
        # A body centre, not a floor point: `dk3_runtime_place` traces the hull from
        # where it is told, and a camera 24 units too low hangs forever reporting
        # `ground=2047`.  `--view` is for inspecting a place the authored starts
        # never look at -- a deck the walk audit says is unreachable, a stair mouth
        # -- so the caller decides the height and this says what it means.
        label, coordinates = spec.split('=', 1)
        parts = [float(value) for value in coordinates.split(',')]
        if len(parts) not in (3, 4, 5):
            raise SystemExit('--view %s wants NAME=X,Y,Z[,YAW[,PITCH]]' % label)
        if ' ' in label:
            raise SystemExit('--view names must be one word: %s' % label)
        # The pitch is what turns this from a first-person tour into an
        # inspection: `is that deck supported?` and `is that tread climbable?`
        # are both questions about something above or below eye level, and a
        # camera that can only look straight ahead photographs the wall in front
        # of it and calls the level judged.
        starts.append(dict(name=label, body=tuple(parts[:3]),
                           angle=parts[3] if len(parts) >= 4 else 0.0,
                           pitch=parts[4] if len(parts) == 5 else 0.0, air=True))
    solids = [brush for entity in parsed.entities for brush in entity.brushes
              if any(face.style.solid for face in brush.faces)]
    grid = map_sightlines.Index(solids, cell=96.0)
    for one in walk_bodies(parsed, grid, args.walk, starts):
        one['walk'] = (args.walk_seconds, one['walk'][1])
        starts.append(one)
        print('map-view: walk %-12s stands on floor %g at %g,%g facing %g'
              % (one['name'], one['floor'], one['body'][0], one['body'][1], one['angle']))
    if args.no_starts:
        starts = [one for one in starts if one.get('air')]
    if args.only:
        picked = [one for one in starts if one['name'] == args.only]
        if not picked:
            raise RuntimeError('%s is not one of %s'
                               % (args.only, ', '.join(sorted(one['name'] for one in starts))))
        starts = picked
    width, height = (int(part) for part in args.size.lower().split('x'))
    identity = dict(map=args.map, package=str(package), package_bytes=package.stat().st_size,
                    package_sha256=sha256(package), engine_binary=sha256(args.engine / 'bin/dk3'),
                    renderer=args.renderer, size=[width, height], captures=len(starts),
                    dedicated=str(args.engine / 'bin/dk3ded'))
    ports = (free_port(), free_port())
    inputs, views = [], []
    with tempfile.TemporaryDirectory(prefix='dk3-map-view-') as temporary:
        root = Path(temporary)
        server_home, client_home = root / 'server', root / 'client'
        stage_client_modules(args.prefix, server_home, installation=None)
        stage_client_modules(args.prefix, client_home, installation=None)
        # The map is hosted by a dedicated server, which is the only way this fork's
        # client reaches a multiplayer map: at cold start it sits in the native menu
        # for a console `map` or `devmap` and never leaves it, so the camera joins the
        # way every real player does -- over the command pipe, with `connect`.
        #
        # The host runs deathmatch, which in this engine is gametype 0 (GT_FFA).  Gametype
        # 2 is GT_SINGLE_PLAYER -- see game/bg_public.h -- and SV_GetChallenge() answers
        # nothing in that mode, so a 2 here leaves the camera re-issuing `getchallenge`
        # against a silent server until the guard kills both processes.
        server = {'fs_basepath': str(args.engine / 'share'), 'fs_homepath': str(server_home),
                  'fs_homedatapath': str(server_home),
                  'fs_homestatepath': str(server_home / 'state'), 'com_basegame': 'dk3',
                  'com_pipefile': 'commands.fifo', 'vm_game': '0', 'dk3_runtime_probe': '2',
                  'net_enabled': '1', 'net_ip': '127.0.0.1', 'net_port': str(ports[0]),
                  'dedicated': '1', 'g_gametype': '0', 'sv_maxclients': '8',
                  'bot_minplayers': str(args.bots), 'sv_pure': '0', 'dk3_public': '0',
                  'developer': '1', 'fraglimit': '0', 'timelimit': '0'}
        settings = client_settings(args.engine, client_home, args.renderer)
        settings.update(r_customwidth=str(width), r_customheight=str(height), r_picmip='0',
                        developer='1', net_enabled='1', net_ip='127.0.0.1',
                        net_port=str(ports[1]), g_gametype='0', in_nograb='1',
                        name='MapView', cl_allowDownload='0', dk3_public='0')
        server_command = [args.engine / 'bin/dk3ded']
        for key, value in server.items():
            server_command += ['+set', key, value]
        server_command += ['+map', args.map]
        client_command = [args.engine / 'bin/dk3']
        for key, value in settings.items():
            client_command += ['+set', key, value]
        server_log, client_log = (args.report / 'server.log', args.report / 'client.log')
        with server_log.open('w') as server_stream, client_log.open('w') as client_stream:
            server_process = subprocess.Popen([str(part) for part in server_command],
                                              stdout=server_stream, stderr=subprocess.STDOUT)
            server_pipe = server_home / 'dk3/commands.fifo'
            driver = None
            try:
                wait(server_process, server_log,
                     lambda text: server_pipe.exists()
                     and 'dk3 zig: isolated bootstrap' in text, 120)
                process = subprocess.Popen([str(part) for part in client_command],
                                           stdout=client_stream, stderr=subprocess.STDOUT)
                driver = NativeInput(process, client_home / 'dk3/commands.fifo', client_log,
                                     client_home, inputs, diagnostic=True)
                wait(process, client_log, lambda text: 'native menus initialized' in text
                     and driver.pipe.exists(), 120)
                host = NativeInput(server_process, server_pipe, server_log, server_home,
                                   inputs, diagnostic=True)
                driver.issue('connect 127.0.0.1:%d' % ports[0])
                wait(process, client_log, lambda text: 'first snapshot applied' in text, 120)
                # Nothing is probed until the host itself says the camera is in the match.
                wait(server_process, server_log,
                     lambda text: 'player entered isolated movement runtime' in text, 60)
                camera = Camera(host, driver, client_home, args.report)
                for start in starts:
                    views.append(camera.stand(start))
                    walked = views[-1]['walk']
                    print('map-view: %-14s mean %.4f spread %.4f%s'
                          % (start['name'], views[-1]['mean'], views[-1]['spread'],
                             '' if not walked else '  rise %g run %g (%d samples, %d airborne)'
                             % (walked['rise'], walked['run'], walked['samples'],
                                walked['airborne'])))
                driver.issue('quit')
                if process.wait(timeout=20) != 0:
                    raise RuntimeError('client shutdown failed: %s' % client_log)
            finally:
                if driver is not None and driver.process.poll() is None:
                    driver.issue('quit')
                for pending in [row for row in (driver.process if driver else None,
                                              server_process) if row is not None]:
                    if pending.poll() is None:
                        try:
                            pending.terminate()
                            pending.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            pending.kill()
                            pending.wait(timeout=5)

    dark = [one['start'] for one in views if one['mean'] < 0.005]
    broken = [one['start'] for one in views if one.get('walk')
              and (one['walk']['never_grounded'] or one['walk']['never_moved']
                   or one['walk']['fell_off'])]
    result = dict(identity=identity, views=views, dark=dark,
                  walks=broken,
                  renderer=renderer_lines(client_log.read_text(errors='replace')),
                  server=map_lines(server_log.read_text(errors='replace'),
                                   args.map.lower()),
                  ports=list(ports), bots=args.bots,
                  setup='Ordinary client, no grants, no cheats; the camera is placed on each'
                        ' authored start and faced along the angle that start carries.',
                  scope='Presentation only: what the map shows from every start. Navigation,'
                        ' combat and mode acceptance are runtime_match_probe, and a run under'
                        ' dkguard --headless is the software GL stack, not owner hardware.')
    (args.report / 'views.json').write_text(json.dumps(result, indent=2) + '\n')
    if dark:
        raise RuntimeError('captures came back black: %s' % ', '.join(dark))
    if broken:
        print('map-view: WALKS THAT DID NOT WORK: %s' % ', '.join(broken))
        for one in views:
            row = one.get('walk')
            if one['start'] in broken and row:
                print('           %-12s run %5.1f rise %6.1f grounded %3d airborne %3d'
                      % (one['start'], row['run'], row['rise'], row['grounded'],
                         row['airborne']))
    print('map-view: %d captures, mean luma %s'
          % (len(views), ', '.join('%.3f' % one['mean'] for one in views)))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--map', required=True)
    parser.add_argument('--engine', type=Path, default=Path('zig-out/native-dev/play/current'))
    parser.add_argument('--prefix', type=Path, default=Path('zig-out/native-dev'))
    parser.add_argument('--work', type=Path, default=Path('zig-out/map-dev'))
    parser.add_argument('--materials', type=Path, default=None,
                        help='the map material table (default maps/<map>/materials.py)')
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl2', choices=('opengl1', 'opengl2'))
    parser.add_argument('--size', default='1280x720')
    parser.add_argument('--only', default=None, help='photograph one authored start only')
    parser.add_argument('--no-starts', action='store_true',
                        help='photograph only the --view cameras, not the authored starts')
    parser.add_argument('--view', action='append', default=[], metavar='NAME=X,Y,Z[,ANGLE]',
                        help='photograph an extra named camera at a body centre (floor + 33)'
                             " as well as the authored starts; repeatable")
    parser.add_argument('--walk', action='append', default=[],
                        metavar='NAME=X,Y,ANGLE[,RISE[,FLOOR]]|NAME=@START,ANGLE[,RISE]',
                        help='hold forward for --walk-seconds and report how far the engine'
                             ' actually walked it; the floor is measured from the compiled'
                             ' map, RISE is what the route is supposed to climb, and FLOOR'
                             ' picks one of several stacked tiers; repeatable')
    parser.add_argument('--walk-seconds', type=float, default=6.0)
    parser.add_argument('--bots', type=int, default=0,
                        help='bot_minplayers for the host; 0 keeps the camera the'
                             ' only player, so placement cannot land on a bot')
    args = parser.parse_args()
    for name in ('engine', 'prefix', 'work', 'report'):
        setattr(args, name, getattr(args, name).resolve())
    args.materials = (args.materials or Path('maps') / args.map / 'materials.py').resolve()
    return run(args)


if __name__ == '__main__':
    main()
