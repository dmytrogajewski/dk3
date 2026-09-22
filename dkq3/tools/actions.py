"""Parse supplied action scripts into versioned instructions for the native scheduler.

The parser implements the asset grammar, without original runtime code or parser quirks.
"""
import math
import re
from pathlib import PurePosixPath

from tables import quoted

TOKEN = re.compile(r'\s+|//[^\n]*|"[^"\r\n]*"|[(){},;]|[^\s(){},;"]+')
ARITIES = {
    'spawn': (7, 9), 'set_state': (2, 3), 'send_message': (2, 2),
    'send_urgent_message': (2, 2), 'call': (1, 1), 'use': (1, 1),
    'remove': (1, 1), 'animate': (1, 2), 'set_moving_animation': (1, 1),
    'face_angle': (3, 3), 'sound': (1, 2), 'stream_sound': (1, 2),
    'wait': (1, 1), 'move_to': (3, 3), 'attack': (1, 2), 'print': (1, 1),
    'random_script': (1, 12),
}


class Parser:
    def __init__(self, name, data):
        self.name = name
        source = data.decode('latin1').rstrip('\0')
        self.tokens = []
        position = 0
        for match in TOKEN.finditer(source):
            if match.start() != position:
                self.error('invalid or unterminated token', source.count('\n', 0, position) + 1)
            token = match[0]
            if not token.isspace() and not token.startswith('//'):
                self.tokens.append((token[1:-1] if token.startswith('"') else token,
                                    source.count('\n', 0, match.start()) + 1))
            position = match.end()
        if position != len(source):
            self.error('unfinished token')
        self.at = 0

    def error(self, message, line=None):
        if line is None:
            line = self.tokens[min(getattr(self, 'at', 0), len(self.tokens) - 1)][1] if self.tokens else 1
        raise ValueError(f'{self.name}:{line}: {message}')

    def peek(self):
        return self.tokens[self.at][0] if self.at < len(self.tokens) else None

    def take(self, expected=None):
        value = self.peek()
        if value is None or expected is not None and value != expected:
            self.error(f'expected {expected or "token"}, got {value!r}')
        self.at += 1
        return value

    def command(self, used=False):
        name = self.take().lower()
        self.take('(')
        args = []
        if self.peek() != ')':
            args.append(self.take())
            while self.peek() == ',':
                self.take(',')
                args.append(self.take())
        self.take(')')
        self.take(';')
        if used:
            if name != 'idle' and not name.isdecimal():
                self.error(f'invalid when_used selector {name}')
            bounds = (1, 12)
        else:
            bounds = ARITIES.get(name)
            if bounds is None:
                self.error(f'unsupported operation {name}')
        if not bounds[0] <= len(args) <= bounds[1]:
            self.error(f'{name}: expected {bounds[0]}..{bounds[1]} arguments, got {len(args)}')
        return name, args

    def block(self, used=False):
        self.take('{')
        result = []
        while self.peek() != '}':
            result.append(self.command(used))
        self.take('}')
        return result


def compile_script(game, name, stack=()):
    if name in stack or len(stack) >= 16:
        raise ValueError(f'{name}: cyclic or excessive include nesting')
    found = game.find(name)
    if not found:
        raise ValueError(f'{name}: required included action script is missing')
    parser = Parser(name, found[1])
    result = []
    while parser.peek() is not None:
        kind = parser.take().lower()
        if kind == 'end_of_script':
            if parser.peek() is not None:
                parser.error('content after end_of_script')
            break
        if kind == 'include':
            include = parser.take().replace('\\', '/')
            path = PurePosixPath(include)
            if path.is_absolute() or any(part in ('.', '..') for part in path.parts):
                parser.error('unsafe include name')
            result.extend(compile_script(game, str(PurePosixPath(name).parent / path).lower(), (*stack, name)))
            if parser.peek() == ';':
                parser.take(';')
            continue
        if kind == 'level_start':
            result.append(('script', '$level_start', '', 1, parser.block()))
            continue
        if kind not in ('script', 'loop_script', 'when_used'):
            parser.error(f'unknown declaration {kind}')
        label, options = parser.take(), []
        while parser.peek() != '{':
            options.append(parser.take())
        if kind == 'when_used':
            if len(options) > 1:
                parser.error('when_used expects at most one delay')
            delay = float(options[0]) if options else 1.0
            if not math.isfinite(delay) or not 0 <= delay <= 3600:
                parser.error('when_used delay is outside 0..3600 seconds')
            result.append(('used', label, '', round(delay * 1000), parser.block(True)))
        else:
            owner, repeat = '', 1 if kind == 'script' else -1
            if options and not re.fullmatch(r'-?\d+', options[0]):
                owner = options.pop(0)
            if options:
                repeat = int(options.pop(0))
            if options or repeat == 0 or repeat < -1 or repeat > 100000:
                parser.error('invalid owner or loop count')
            result.append(('script', label, owner, repeat, parser.block()))
    return result


def entries(game, names):
    result = []
    for name in sorted(n for n in names if n.startswith('cin/aiscripts/') and n.endswith('.sca')):
        records = compile_script(game, name)
        seen = set()
        output = ['dk3_actions 1']
        for kind, label, owner, count, commands in records:
            key = kind, label.lower()
            if key in seen:
                raise ValueError(f'{name}: duplicate {kind} {label}')
            seen.add(key)
            output.append(f'{kind} {quoted(label)} {quoted(owner)} {count} {len(commands)}')
            for operation, args in commands:
                output.append(quoted(operation) + f' {len(args)} ' + ' '.join(quoted(arg) for arg in args))
        encoded = ('\n'.join(output) + '\n').encode('utf-8')
        if len(encoded) > 1024 * 1024:
            raise ValueError(f'{name}: normalized program exceeds runtime limit')
        result.append((f'dk3/actions/{PurePosixPath(name).stem}.cfg', encoded))
    return result
