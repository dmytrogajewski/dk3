"""Shared helpers for the dkq3/tools contract tests: run a tool as a subprocess with the GPU hidden,
and probe a module import for side effects with an audit hook.

FRD: specs/frds/FRD-003-converter-tooling-contract-paths-as-arguments-pinned-runtime.md
"""
import ast
import json
import os
import re
import subprocess
import sys

TOOLS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_ROOT = os.path.dirname(os.path.dirname(TOOLS_DIR))
DEFAULT_CORPUS = os.path.join(REPO_ROOT, "install", "data")
MAIN_GUARD = re.compile(r"^if __name__ == ['\"]__main__['\"]:", re.M)
MISSING_MODULE = re.compile(r"ModuleNotFoundError: No module named '([^'.]+)")


def tool_modules():
    """Every top-level module in dkq3/tools, sorted."""
    return sorted(f[:-3] for f in os.listdir(TOOLS_DIR) if f.endswith(".py"))


def source(module):
    with open(os.path.join(TOOLS_DIR, module + ".py"), encoding="utf-8") as f:
        return f.read()


def entry_points():
    """Modules that run as scripts (`if __name__ == '__main__':`)."""
    return [m for m in tool_modules() if MAIN_GUARD.search(source(m))]


def child_env():
    """Environment for tool subprocesses: GPU hidden, no bytecode written."""
    env = dict(os.environ, CUDA_VISIBLE_DEVICES="", PYTHONDONTWRITEBYTECODE="1")
    env["PYTHONPATH"] = os.pathsep.join(p for p in (TOOLS_DIR, os.environ.get("PYTHONPATH")) if p)
    return env


GUARD_MEM = "2G"
GUARD_MEM_BYTES = 2 << 30
GUARD_TIMEOUT_S = 120
SUBPROCESS_SLACK_S = 60
CAP_EXITS = {124: "timeout elapsed", 137: "killed by SIGKILL, usually the memory cap"}


class GuardCapExceeded(AssertionError):
    """A tool subprocess hit its dkguard cap: the test fails instead of hanging or passing."""


def dkguard():
    """zig build test passes the freshly built guard in DKGUARD; a manual run uses zig-out."""
    path = os.path.abspath(os.environ.get("DKGUARD") or
                           os.path.join(REPO_ROOT, "zig-out", "bin", "dkguard"))
    if not os.access(path, os.X_OK):
        raise RuntimeError(f"dkguard not found at {path}: run `zig build` or set DKGUARD")
    return path


def run_guarded(argv, cwd, env=None, mem=GUARD_MEM, timeout_s=GUARD_TIMEOUT_S):
    """Runs argv under `dkguard --mem --timeout` (spec R7); a cap hit raises GuardCapExceeded."""
    guarded = [dkguard(), "--mem", mem, "--timeout", str(timeout_s), "--", *argv]
    proc = subprocess.run(guarded, cwd=cwd, env=child_env() if env is None else env,
                          capture_output=True, text=True, timeout=timeout_s + SUBPROCESS_SLACK_S)
    if proc.returncode in CAP_EXITS:
        raise GuardCapExceeded(f"{argv[:3]}: dkguard exit {proc.returncode} "
                               f"({CAP_EXITS[proc.returncode]}) under --mem {mem} "
                               f"--timeout {timeout_s}s\n{proc.stderr[-2000:]}")
    return proc


def run_python(args, cwd, mem=GUARD_MEM, timeout_s=GUARD_TIMEOUT_S):
    """Runs this interpreter with args under dkguard, GPU hidden."""
    return run_guarded([sys.executable, "-B", *args], cwd, mem=mem, timeout_s=timeout_s)


def missing_pinned_package(stderr, pins):
    """The pinned import name a subprocess failed to import, or None."""
    m = MISSING_MODULE.search(stderr)
    return m.group(1) if m and m.group(1) in pins else None


def module_level_imports(module, seen=None):
    """Top-level names imported at module level by `module` and the local modules it imports."""
    seen = set() if seen is None else seen
    if module in seen:
        return set()
    seen.add(module)
    names = set()
    for node in ast.parse(source(module)).body:
        found = [a.name for a in node.names] if isinstance(node, ast.Import) else \
            [node.module] if isinstance(node, ast.ImportFrom) and node.module and not node.level else []
        for name in (n.split(".")[0] for n in found):
            local = os.path.exists(os.path.join(TOOLS_DIR, name + ".py"))
            names |= module_level_imports(name, seen) if local else {name}
    return names - set(sys.stdlib_module_names)


PROBE = r"""
import importlib, json, os, sys
module, corpus, preload = sys.argv[1], os.path.realpath(sys.argv[2]), sys.argv[3:]
for name in preload:
    try:
        importlib.import_module(name)
    except ImportError:
        pass
WRITE_FLAGS = os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND
MUTATING = ('os.remove', 'os.rename', 'os.mkdir', 'os.rmdir', 'os.symlink', 'os.link',
            'os.truncate', 'os.chmod', 'os.chown', 'os.utime', 'shutil.', 'socket.',
            'subprocess.', 'os.system', 'os.exec', 'os.posix_spawn', 'os.spawn', 'os.fork',
            'os.kill', 'urllib.', 'http.client.')
effects = []
def hook(event, args):
    if event == 'open':
        path, mode, flags = args
        if not isinstance(path, (str, bytes)):
            return
        path = os.fsdecode(path)
        writes = (isinstance(mode, str) and any(c in mode for c in 'wax+')) or \
            (isinstance(flags, int) and flags & WRITE_FLAGS)
        if writes:
            effects.append('write ' + path)
        elif os.path.realpath(path).startswith(corpus + os.sep):
            effects.append('corpus read ' + path)
    elif event.startswith(MUTATING):
        effects.append(event + ' ' + repr(args)[:160])
sys.addaudithook(hook)
importlib.import_module(module)
torch = sys.modules.get('torch')
if torch is not None and torch.cuda.is_initialized():
    effects.append('gpu: torch.cuda initialized')
sys.stdout.write('PROBE ' + json.dumps(effects) + '\n')
"""


GUARD = r"""
import importlib, os, runpy, sys
script, preload = sys.argv[1], sys.argv[2:]
for name in preload:
    try:
        importlib.import_module(name)
    except ImportError:
        pass
WRITE_FLAGS = os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND
BLOCKED = ('os.remove', 'os.rename', 'os.mkdir', 'os.rmdir', 'os.symlink', 'os.link',
           'os.truncate', 'shutil.', 'socket.', 'subprocess.', 'os.system', 'os.exec',
           'os.posix_spawn', 'os.spawn', 'os.fork', 'urllib.', 'http.client.')
def hook(event, args):
    if event == 'open' and isinstance(args[0], (str, bytes)):
        mode, flags = args[1], args[2]
        if (isinstance(mode, str) and any(c in mode for c in 'wax+')) or \
                (isinstance(flags, int) and flags & WRITE_FLAGS):
            raise PermissionError('guard blocked write: ' + os.fsdecode(args[0]))
    elif event.startswith(BLOCKED):
        raise PermissionError('guard blocked ' + event)
sys.addaudithook(hook)
sys.argv = [script]
try:
    runpy.run_path(script, run_name='__main__')
finally:
    heavy = sorted(m for m in sys.modules if m.split('.')[0] in HEAVY)
    sys.stderr.write(REPORT + repr(sorted({m.split('.')[0] for m in heavy})) + '\n')
"""

# GPU frameworks an entry point must not import before its arguments parse (FRD-003 M2).
HEAVY_MODULES = {"torch", "diffusers", "transformers", "bitsandbytes", "accelerate", "xformers"}
GUARD_HEAVY_REPORT = "GUARD heavy-imports "

# Tools exempt from the usage-on-missing-arguments contract, with the recorded reason.
ZERO_CONFIG_TOOLS = {
    "fetch_models": "fetch_models.py is a zero-config model download utility by explicit user "
                    "requirement, not a converter (FRD-003 In Scope); running it without "
                    "arguments starts downloads",
}


def run_tool_guarded(tool, cwd):
    """Runs `tool` as __main__ with no arguments; any write, filesystem change, process or socket
    raises inside the tool, so a tool that does real work without arguments fails harmlessly."""
    script = os.path.join(TOOLS_DIR, tool + ".py")
    code = f"HEAVY = {sorted(HEAVY_MODULES)!r}\nREPORT = {GUARD_HEAVY_REPORT!r}\n{GUARD}"
    return run_python(["-c", code, script, *sorted(module_level_imports(tool))], cwd)


def probe_import(module, cwd, corpus=DEFAULT_CORPUS):
    """-> (completed process, list of side effects or None when the import failed)."""
    preload = sorted(module_level_imports(module))
    proc = run_python(["-c", PROBE, module, corpus, *preload], cwd)
    line = next((l for l in proc.stdout.splitlines() if l.startswith("PROBE ")), None)
    return proc, (json.loads(line[len("PROBE "):]) if line else None)
