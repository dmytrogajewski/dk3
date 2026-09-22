"""Bounded reader for supplied GCE version-15 cinematic assets.

Only data layout is shared with the original format; output is dk3's named records.
"""
import math
import struct
from pathlib import PurePosixPath
from tables import quoted


class Reader:
    def __init__(self, name, data):
        self.name, self.data, self.at = name, data, 0

    def error(self, message):
        raise ValueError(f'{self.name}: byte {self.at}: {message}')

    def take(self, count):
        if count < 0 or self.at + count > len(self.data):
            self.error(f'truncated field of {count} bytes')
        result = self.data[self.at:self.at + count]
        self.at += count
        return result

    def integer(self):
        return struct.unpack('<i', self.take(4))[0]

    def count(self, maximum):
        value = self.integer()
        if not 0 <= value <= maximum:
            self.error(f'array count {value} outside 0..{maximum}')
        return value

    def floats(self, count=1):
        values = struct.unpack('<' + 'f' * count, self.take(4 * count))
        if any(not math.isfinite(v) for v in values):
            self.error('non-finite scalar')
        return list(values)

    def scalar(self):
        return self.floats()[0]

    def flag(self):
        value = self.take(1)[0]
        if value not in (0, 1):
            self.error(f'invalid boolean {value}')
        return value

    def string(self, size):
        return self.take(size).split(b'\0', 1)[0].decode('latin1').replace('\\', '/')

    def component(self):
        count = self.count(8192)
        points = []
        for _ in range(count):
            points.append(self.floats(3))
            self.floats(4)  # normalized velocity and magnitude, baked into the splines below
        curves = [self.floats(12) for _ in range(max(0, count - 1))]
        return points, curves

    def sequence(self):
        count = self.count(8192)
        position, angles = self.component(), self.component()
        if len(position[0]) != count or len(angles[0]) != count:
            self.error('sequence/component point count disagreement')
        segments = []
        for _ in range(self.count(8192)):
            duration = self.scalar()
            fov_flags, fov = [self.flag(), self.flag()], self.floats(2)
            speed_flags, speed = [self.flag(), self.flag()], self.floats(2)
            color_flags, color = [self.flag(), self.flag()], self.floats(8)
            if duration < 0:
                self.error('negative segment duration')
            segments.append([duration, *fov_flags, *fov, *speed_flags, *speed, *color_flags, *color])
        velocity_modes, duration = [self.integer(), self.integer()], self.scalar()
        if len(segments) < max(0, count - 1) or duration < 0:
            self.error(f'invalid sequence: points={count}, segments={len(segments)}, duration={duration}')
        return position, angles, segments, velocity_modes, duration

    def task(self):
        kind, when = self.integer(), self.scalar()
        destination, direction, attribute = self.floats(3), self.floats(3), self.scalar()
        if not 0 <= kind <= 20:
            self.error(f'unsupported entity task {kind}')
        head = self.component() if kind == 14 else None
        animation, use, sound = self.string(16), self.string(16), self.string(16)
        duration, unique_id = self.scalar(), self.string(32)
        return kind, when, destination, direction, attribute, head, animation, use, sound, duration, unique_id


def numbers(values):
    return ' '.join(format(v, '.9g') if isinstance(v, float) else str(v) for v in values)


def compile_script(name, data):
    reader = Reader(name, data)
    if reader.integer() != 15:
        reader.error('only cinematic asset version 15 is supported')
    count = reader.count(256)
    output = [f'dk3_cinematic 1 {count}']
    for _ in range(count):
        position, angles, segments, modes, duration = reader.sequence()
        target, end = reader.integer(), reader.integer()
        pre, post = reader.scalar(), reader.scalar()
        sounds = [(reader.string(64), reader.flag(), reader.integer(), reader.scalar())
                  for _ in range(reader.count(4096))]
        entities = [(reader.string(32), reader.string(32), [reader.task() for _ in range(reader.count(32768))])
                    for _ in range(reader.count(8192))]
        camera_target, end_target = reader.string(16), reader.string(16)
        has_fov, fov, sky = reader.flag(), reader.scalar(), reader.integer()
        if target not in (0, 1) or end not in (0, 1) or pre < 0 or post < 0:
            reader.error('invalid shot flags or timing')
        output.append('shot ' + numbers([duration, pre, post, target, end, has_fov, fov, sky, *modes]) +
                      ' ' + quoted(camera_target) + ' ' + quoted(end_target))
        output.append(f'camera {len(position[0])} {len(segments)}')
        output.append(numbers((position[0][0] if position[0] else [0, 0, 0]) +
                              (angles[0][0] if angles[0] else [0, 0, 0])))
        for index, segment in enumerate(segments):
            output.append('segment ' + numbers(segment + (position[1][index] if index < len(position[1]) else [0] * 12) + (angles[1][index] if index < len(angles[1]) else [0] * 12)))
        output.append('sounds ' + str(len(sounds)))
        for sound, loop, channel, when in sounds:
            output.append(quoted(sound) + ' ' + numbers([loop, channel, when]))
        output.append('entities ' + str(len(entities)))
        for actor, unique_id, tasks in entities:
            output.append(quoted(actor) + ' ' + quoted(unique_id) + ' ' + str(len(tasks)))
            for kind, when, destination, direction, attribute, head, animation, use, sound, length, task_id in tasks:
                output.append(numbers([kind, when, *destination, *direction, attribute, length]) + ' ' +
                              ' '.join(quoted(v) for v in (animation, use, sound, task_id)))
                if head:
                    output.append('head ' + str(len(head[0])))
                    output.append(numbers(head[0][0] if head[0] else [0, 0, 0]))
                    output.extend(numbers(curve) for curve in head[1])
    if reader.at != len(data):
        reader.error(f'{len(data) - reader.at} trailing bytes')
    encoded = ('\n'.join(output) + '\n').encode('utf-8')
    if len(encoded) > 4 * 1024 * 1024:
        reader.error('normalized program exceeds runtime limit')
    return encoded


def entries(game, names):
    return [(f'dk3/cinematics/{PurePosixPath(name).stem}.cfg', compile_script(name, game.find(name)[1]))
            for name in sorted(names) if name.startswith('cin/scripts/') and name.endswith('.script')]
