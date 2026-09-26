# dk3

An open-source project to bring **Daikatana to the ioquake3 engine**, built with Zig.

**Native Zig runtime under development; gameplay is incomplete.**

The old gameplay runtime has been removed. The only game/client/UI implementation
is now `src/runtime`, built on the bundled ioquake3 engine. Weapon definitions,
movement, ECS world systems, movers and pickups are connected. Combat and civilian
actors are partially implemented; hostile actors, scripts, save restoration and
complete presentation/UI remain unfinished. Development stays on
`rewrite/native-zig-runtime`; `main` preserves the working pre-rewrite game.

See the [native architecture and progress](docs/runtime-zig.md),
[current status](docs/status.md), and [full roadmap](docs/rewrite-roadmap.md).
Earlier screenshots and gameplay results describe the retired runtime and are
historical evidence, not acceptance of this runtime.

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
zig build play-install --prefix zig-out/native-dev -DDK_DATA=/path/to/data -Dasset-profile=retail -Dpython=.venv-convert/bin/python
zig build play --prefix zig-out/native-dev -DDK_DATA=/path/to/data -Dasset-profile=retail -Dpython=.venv-convert/bin/python -- +map e1m3b
```

Native menus are incomplete; launch a map explicitly as above. Development uses an
isolated prefix/profile and does not update the preserved game or saves.

`play-install` includes conversion and verifies the installed files; `assets` selects conversion
alone. ffmpeg 7 must be available on `PATH`. Use `-Dasset-profile=1.3` for the documented
1.3 overrides. That private profile has been converted and installed; the retail profile and
complete new-game-to-ending path still require verification. See
[asset inputs and installation](docs/assets.md). Original and converted assets stay local
and are not covered by the project's GPL license.

For a private RPM containing an existing converted installation, HD textures and
default Internet-server trust, see [RPM packaging](docs/rpm.md).

## Project layout

```text
engine/ioquake3/   Bundled engine, upstream foundations, and third-party notices
engine/bspc/       Bundled navigation compiler and its notices
src/runtime/  Native Zig game/client/UI, domain, ECS and engine adapters
src/weapons/      Pure weapon descriptions and shared policies
src/items/        Item metadata and key policies
src/network/      Zig protocol and security
src/online/       Room services and operator tools
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
