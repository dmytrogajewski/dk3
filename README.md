# dk3

An open-source project to bring **Daikatana to the ioquake3 engine**, built with Zig.

**Native Zig runtime under development; gameplay is incomplete.**

The old gameplay runtime has been removed. The only game/client/UI implementation
is now `src/runtime`, built on the bundled ioquake3 engine. Weapon definitions,
movement, ECS world systems, movers, pickups, all 28 weapon controllers, episode
actors, scripts, cinematics, companions, saves and multiplayer modes are connected.
The consolidated native implementation still requires gameplay verification and
repairs; no complete episode is accepted. Development stays on
`rewrite/native-zig-runtime`; `main` preserves the working pre-rewrite game.

See the [native architecture and progress](docs/runtime-zig.md),
[current acceptance](docs/native-acceptance.md), and [full roadmap](docs/rewrite-roadmap.md).
Earlier screenshots and gameplay results describe the retired runtime and are
historical evidence, not acceptance of this runtime.

## Build the engine and tools

You need Linux x86-64, Zig 0.16.x, Make, and SDL2 development files discoverable by
pkg-config. Python 3.10+ is needed for archive tools and synthetic checks.

```sh
git clone https://github.com/dmytrogajewski/dk3.git
cd dk3
zig build
./zig-out/native-dev/bin/dkguard --help
```

The repository includes the engine, native game/client/UI modules, asset converters,
and build/install tools together. It is a development snapshot, not a completed game port.

The client and server are `zig-out/native-dev/bin/dk3` and `zig-out/native-dev/bin/dk3ded`. The engine source
is included under `engine/ioquake3`; no separate ioq3 or Gold checkout is required.
See [building](docs/building.md) for products, optional QVM tools, and dependencies.

`dkguard` runs commands with memory limits, timeouts, and optional headless graphics. For example:

```sh
./zig-out/native-dev/bin/dkguard --mem 512M --timeout 30s -- python3 --version
```

No game assets, GPU, ioquake3 checkout, or Python packages are needed for this example.
See [getting started](docs/getting-started.md) for setup and format-tool examples.

## Supply assets and play the development build

Development commands require **your own legally acquired Daikatana game data**, Python
with `dkq3/tools/requirements.txt`, and ffmpeg 7:

```sh
python3 -m venv .venv-convert
.venv-convert/bin/python -m pip install -r dkq3/tools/requirements.txt
zig build assets -DDK_DATA=/path/to/data -Dasset-profile=retail -Dpython=.venv-convert/bin/python
zig build play
```

After the first conversion, `zig build play` rebuilds the current checkout and launches
it using the completed asset cache. It needs no repeated data path or conversion
environment. Extra engine arguments follow `--`, for example `zig build play -- +map e1m3b`.
Builds default to `zig-out/native-dev`; settings and saves remain under that prefix's
`play/home` and `play/state` directories. The preserved installation is untouched.
Use `-Dassets-dir=/path/to/cache` for a different converted cache or `-Dheadless=true`
for a software-rendered test on a virtual display.

Normal launches use OpenGL2 with model shadows enabled. **Video → Model shadows**
toggles shadows. To explicitly use OpenGL1, pass `-- +set cl_renderer opengl1`.

Press **Escape** during a cinematic to skip it and continue its authored exit.
Outside cinematics, Escape opens or closes the pause menu.

HD textures are used at full resolution automatically when the local package is
available in `zig-out/hd-textures` or the build prefix's `hd-textures` directory.
See [HD texture setup](docs/getting-started.md) for package overrides.

The optional [local neural character package](docs/neural-assets.md) adds skeletal
Hiro, Mikiko, Superfly, Mishima/Kage and Usagi models, gameplay clips, converted
cinematic motion and multiplayer appearances. Once generated locally, it is
included by `play-install` and `play` automatically.

Native New Game, save/load and multiplayer menus are connected; their current
acceptance is recorded in the matrix. Development uses an isolated prefix/profile
and does not update the preserved game or saves.

`play-install` builds and verifies the installed files without launching. Supplying
`-DDK_DATA` to either play command also requests conversion; `assets` selects conversion
alone. Conversion requires ffmpeg 7 on `PATH`. Use `-Dasset-profile=1.3` for the documented
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
