# dk3

An open-source project to bring **Daikatana to the ioquake3 engine**, built with Zig.

**Playable development build; the game rewrite is incomplete.** The checkout includes
the bundled ioquake3 engine, both renderers, independent native game/client/UI modules,
all 28 selectable weapons implemented in Zig, and asset conversion/install tooling.
The private 1.3 profile converts all 84 maps and 97 navigation variants. Recorded
campaign traversal reaches partway into e1m2b; no complete episode is verified.

The latest weapon correction pass verifies all 28 firing paths, representative combat,
underwater attacks, multiplayer volleys and mid-action saves. The ReleaseSafe build
and broad suite pass. Full campaign progression, companion behavior, multiplayer
acceptance and Gold visual/audio parity remain open. See the
[current completion state](docs/status.md) for what is implemented, verified and
still missing, and the [roadmap](docs/rewrite-roadmap.md) for the full accepted scope.

## Build the engine and tools

You need Linux x86-64, Zig 0.16.x, Make, and SDL2 development files discoverable by
pkg-config. Python 3.10+ is needed for archive tools and synthetic checks.

```sh
git clone https://github.com/dmytrogajewski/dk3.git
cd dk3
zig build
./zig-out/bin/dkguard --help
```

The repository includes the engine, native game/client/UI modules, asset converters,
and build/install tools together. It is a development snapshot, not a completed game port.

The client and server are `zig-out/bin/dk3` and `zig-out/bin/dk3ded`. The engine source
is included under `engine/ioquake3`; no separate ioq3 or Gold checkout is required.
See [building](docs/building.md) for products, optional QVM tools, and dependencies.

`dkguard` runs commands with memory limits, timeouts, and optional headless graphics. For example:

```sh
./zig-out/bin/dkguard --mem 512M --timeout 30s -- python3 --version
```

No game assets, GPU, ioquake3 checkout, or Python packages are needed for this example.
See [getting started](docs/getting-started.md) for setup and format-tool examples.

## Supply assets and play the development build

Development commands require **your own legally acquired Daikatana game data**, Python
with `dkq3/tools/requirements.txt`, and ffmpeg 7:

```sh
python3 -m venv .venv-convert
.venv-convert/bin/python -m pip install -r dkq3/tools/requirements.txt
zig build play-install -DDK_DATA=/path/to/data -Dasset-profile=retail -Dpython=.venv-convert/bin/python
zig build play -DDK_DATA=/path/to/data -Dasset-profile=retail -Dpython=.venv-convert/bin/python
```

`play-install` includes conversion and verifies the installed files; `assets` selects conversion
alone. ffmpeg 7 must be available on `PATH`. Use `-Dasset-profile=1.3` for the documented
1.3 overrides. That private profile has been converted and installed; the retail profile and
complete new-game-to-ending path still require verification. See
[asset inputs and installation](docs/assets.md). Original and converted assets stay local
and are not covered by the project's GPL license.

## Project layout

```text
engine/ioquake3/   Bundled engine, upstream foundations, and third-party notices
engine/bspc/       Bundled navigation compiler and its notices
src/game/         Independent authoritative game and campaign systems
src/cgame/        Client presentation and shared prediction integration
src/ui/           Native menus and input configuration
src/shared/       Shared state, weapons, movement contracts and text layout
src/weapons/      Native Zig weapon types, prediction, combat and presentation
src/dkguard/       Process runner and its existing checks
dkq3/tools/        Asset conversion, archive tools and installation
build/            Engine, modules, navigation, assets and launcher build graph
docs/             Setup, provenance, publication boundaries, and rewrite roadmap
build.zig         Engine and reviewed component build
```

The [rewrite roadmap](docs/rewrite-roadmap.md) separates implemented systems from verified
gameplay. [Publication notes](docs/publication.md) explain how reviewed source is
separated from the local playable workspace.

## Contributing

Bug reports, original implementations, and documentation improvements are welcome.
Start with [CONTRIBUTING.md](CONTRIBUTING.md). Maintained by
[@dmytrogajewski](https://github.com/dmytrogajewski).

## License

Original project code is **GPL-2.0-or-later**; see [LICENSE](LICENSE) and
[COPYRIGHT.md](COPYRIGHT.md). The target engine, [ioquake3](https://ioquake3.org/), is GPL software.
Bundled third-party sources retain their own terms. No engine license grants rights to
Daikatana's original code or assets. This is an independent
community project, unaffiliated with the original game's rights holders.

<!-- README structure informed by https://github.com/RichardLitt/standard-readme -->
