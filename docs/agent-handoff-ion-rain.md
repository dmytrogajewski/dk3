# Agent handoff: running dk3 and continuing effects development

This handoff records the session through run-log sequence **196**. It is a snapshot,
not a claim that the port or its original-game parity is complete. Re-read current
files before making changes; later work may supersede these details.

## 1. Work in the correct checkout

| Purpose | Local path |
| --- | --- |
| Public development checkout | `/home/dmitriy/sources/dk3` |
| Private reference source | `/home/dmitriy/sources/daikatana/reference/dk-gold` |
| Preserved original executable | `/home/dmitriy/sources/daikatana/install/daikatana` |
| User-owned assets | `/home/dmitriy/sources/daikatana/install/data` |

Develop in **dk3**, not the old daikatana workspace. Read the applicable
[AGENTS.md](../AGENTS.md). Preserve existing changes, installations and saves.

Gold source is behavioural reference material. Do not copy its implementation or
introduce Gold headers, libraries, executables or generated code into the public
dependency graph. Keep public game/client/UI code in native C and builds/tooling
in Zig 0.16. Reuse reviewed independent code and the bundled ioquake3 foundations.

## 2. Run the installed game

```sh
dk3
```

The launcher is `/home/dmitriy/.local/bin/dk3`. It launches the installation selected
by `/home/dmitriy/sources/dk3/zig-out/play/current` through `dkguard`.

At this handoff, the installation uses the **1.3 asset profile**, the existing HD
texture overlay, and the latest Ion/rain changes. Restart the game after installing
updates. Inspect `zig-out/play/current/installation.json` for the selected products
and asset generation.

**The port remains incomplete.** Successful builds and individual scenarios do not
establish campaign completion or full original-game parity.

## 3. Build and install ordinary code changes

```sh
cd /home/dmitriy/sources/dk3
zig build -Doptimize=ReleaseSafe
python3 dkq3/tools/play.py install --prefix zig-out --assets zig-out/assets
dk3
```

`zig build` alone does **not** update the installation used by `dk3`.

Requirements include Linux x86-64, Zig 0.16.x, SDL2 development files discoverable
through pkg-config, and Python. Reuse existing converted assets for ordinary
gameplay/presentation code changes. See [building](building.md).

For a fresh asset installation:

```sh
cd /home/dmitriy/sources/dk3
python3 -m venv .venv-convert
.venv-convert/bin/python -m pip install -r dkq3/tools/requirements.txt

zig build play-install \
  -DDK_DATA=/home/dmitriy/sources/daikatana/install/data \
  -Dasset-profile=1.3 \
  -Dpython=.venv-convert/bin/python
```

Conversion requires ffmpeg 7. Consult [asset inputs](assets.md) before changing
converter inputs or profiles. Use `retail` for retail-only data; do not assume that
the private 1.3 conversion evidence also verifies the retail profile.

## 4. Follow the agreed development workflow

Read these once, then inspect relevant sections as needed:

- [Development workflow](development-workflow.md)
- [Rewrite roadmap](rewrite-roadmap.md)
- [Runtime gap audit](runtime-gap-audit.md)
- Local run log: `specs/runs/RUN-dk3-independent-port.md`

Latest session evidence ends at **seq:196**. The run log and private evidence may be
absent from a fresh public checkout; do not fabricate missing acceptance results.

1. Implement a coherent batch across dependent systems first.
2. Build the integrated result, run real scenarios, inspect results and repair failures.
3. Do not run baseline suites, lint or corpus sweeps after every edit.
4. Preserve passing evidence until relevant inputs change. Rerun affected scenarios
   after repairs; broaden testing when shared changes or observed failures justify it.
5. Run `make lint` once at the end of the repair batch. It already includes
   `zig build test`; do not duplicate it with another invocation or `make test`.
6. Distinguish **implemented**, **verified**, **failed** and **unverified**.

Use existing specifications and runners. Avoid per-item paperwork and compulsory
test-first sequences. Documentation-only changes need lightweight review, not game
builds or gameplay suites. Do not spawn agents or perform Git operations without
applicable authorization.

## 5. Compare with the original; do not invent effects

For visual or gameplay differences, trace the original behaviour from server event
through client effect to rendering and supplied artwork. Matching a model name or
light radius is insufficient. Treat hypotheses as hypotheses until measured.

Relevant files within the private reference source:

```text
dlls/weapons/ionblaster.cpp
base/Projectile_fx.cpp
base/client/cl_pv.cpp
base/ref_gl/gl_particle.cpp
base/ref_gl/gl_beams.cpp
base/ref_gl/gl_rmisc.cpp
```

Relevant public implementation:

```text
src/cgame/dk_effects.c
src/cgame/dk_presentation.c
src/cgame/dk3-projectile-weather.shader
src/game/dk_effects.c
src/game/dk_combat.c
dkq3/tools/play.py
```

The latest original screenshots supplied by the user were:

```text
/tmp/codex-clipboard-CjAvCk.png
/tmp/codex-clipboard-9a30DJ.png
```

Both are **original-game references**. Do not misidentify them as port captures.
Temporary files may disappear; verify availability before using them.

## 6. Current implementation and evidence

Implemented in the latest batch:

- Ion lightning arms, flare, spark trail, bounce mesh/sparks and terminal sparkles.
- Atlas-textured rain, corrected speed/wind/opacity, area-based emission and
  solid-surface splashes.
- Code-owned effect shader installation and verification without changing gameplay
  asset identity.

Earlier work corrected additive lights washing out surface textures in both renderers.

Latest verification: ReleaseSafe build and `make lint` passed, including **42 Python
tests plus Zig checks**. Native rendered scenarios exercised both renderers and
actual Ion wall contact.

Private evidence directories:

```text
zig-out/reports/ion-material-light-05/
zig-out/reports/ion-rain-reference-06/
```

The preserved-original waterfall capture verifies rain appearance only. Its attempted
weapon commands **did not equip the Ion blaster**. Do not describe it as an original
Ion-flight comparison. Ion comparison in this batch used the supplied screenshots
and the source contracts documented in the runtime gap audit.

Exact beam geometry, Ion liquid-discharge rings and full effects parity remain
unfinished. Bounded particle pools, collision clipping and simulation-time scheduling
differ from the original implementation. Do not claim pixel-exact matching.

## 7. Rain drops and splashes on water (repaired at seq:196)

Three defects were measured and repaired: solid-only drop traces, 2-unit padded weather
bounds, and PVS culling of the sky-level volume brushes. The original has no rain
ripples; splashes are floor-plane `SPLASH1`/`SPLASH3` sprites. Diagnostic noclip
captures over the e1m1a pool in both renderers show water splashes. The prior build
lacks them at the same viewpoint. See the runtime gap audit and
`zig-out/reports/rain-water-07/`.

Still open: the OpenGL2 yellow saturation on surfaces near that pool (pre-existing),
exact original population/phase, and a user check in normal play.

## 8. Use isolated verification installations

Run engines through `dkguard`; software rendering uses `--headless` without `--gpu`.
Never alter the user's running game or saves for diagnostics.

Existing temporary helpers, if still present:

```text
/tmp/dk3-presentation-repair/launch.py
/tmp/dk3-repair-batch.py
/tmp/dk3-reference-capture
```

Inspect scripts before reuse. The native helper uses separate
`/tmp/dk3-presentation-*` directories, `/tmp/dk3-repair-console` as its console FIFO,
and `/tmp/dk3-presentation-client.log`. It copies current native build products and
the runtime shader into the private installation while reusing installed assets.
Do not run two instances sharing those paths.

Prefer normal movement and attack commands. `dk3_look <yaw> <pitch>` provides
reproducible aiming. Record diagnostic placement or other controlled fixtures rather
than presenting them as authored progression.

GDB function calls can be unreliable in optimized builds because of compiler changes
to calling conventions. Prefer actual input and observation of normal event dispatch.
Do not infer damage or gameplay correctness from an unvalidated debugger call.

After abnormal diagnostic termination, a recovery dialog may block startup. Inspect
the private display rather than interpreting a stalled runner as a gameplay failure.
An exit code from a capture helper is not sufficient: inspect its logs and images to
confirm the intended scenario actually occurred.

## 9. Preserve installation and provenance contracts

Code-owned effect shaders install with the runtime at:

```text
share/dk3/scripts/dk3-projectile-weather.shader
```

They reference existing supplied artwork and remain separate from converted gameplay
assets. This permits presentation updates without invalidating saves. Keep their
installation hashes and corruption checks intact. The synthetic regression lives in
`dkq3/tools/tests/test_runtime_media.py`.

Use unique shader filenames: `dk3-effects.shader` already exists in the asset packages.
Shadowing it previously hid unrelated effects.

When changing bundled engine files, update their hashes in `engine/DEVELOPMENT.json`.
Preserve upstream notices. Keep proprietary assets and captures out of Git. Report
what changed, what was actually verified, and what remains unresolved.
