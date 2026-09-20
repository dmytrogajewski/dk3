# dk3

An open-source project to bring **Daikatana to the ioquake3 engine**, built with Zig.

**The game rewrite is incomplete.** This repository currently contains reviewed GPL development
components: the process runner and archive/texture format tools. It does **not** yet contain a
playable game or the complete game runtime. A separate local development build is playable, but
still depends on original game source that is excluded from this repository.

## Try the published tools

You need **Linux x86-64**, **Zig 0.16.x**, **Python 3.10+**, and **Make**. Install Zig from
[ziglang.org](https://ziglang.org/download/), then:

```sh
git clone https://github.com/dmytrogajewski/dk3.git
cd dk3
make build
./zig-out/bin/dkguard --help
```

`dkguard` runs commands with memory limits, timeouts, and optional headless graphics. For example:

```sh
./zig-out/bin/dkguard --mem 512M --timeout 30s -- python3 --version
```

No game assets, GPU, ioquake3 checkout, or Python packages are needed for this example.
See [getting started](docs/getting-started.md) for setup and format-tool examples.

## What about playing Daikatana?

The intended game build will require **your own legally acquired Daikatana game data**.
Maps, textures, models, sounds, music, and other original assets are not included and are not
covered by this project's GPL license. Converted and upscaled versions stay local too.

**Retail assets alone cannot build the game from this repository yet.** The remaining game code
must be replaced before that is possible. We are keeping the working local game available during
that work; [local development](docs/local-development.md) records its requirements and launch commands.

## Project layout

```text
src/dkguard/       Process runner and its existing checks
dkq3/tools/        PAK/WAL readers, PAK/PK3 writers, ZIP member extraction
build/            Zig toolchain version check
docs/             Setup, provenance, publication boundaries, and rewrite roadmap
build.zig         Build for the published components only
```

The [rewrite roadmap](docs/rewrite-roadmap.md) describes what must be replaced before a public
game build can run. [Publication notes](docs/publication.md) explain how reviewed source is
separated from the local playable workspace.

## Contributing

Bug reports, original implementations, and documentation improvements are welcome.
Start with [CONTRIBUTING.md](CONTRIBUTING.md). Maintained by
[@dmytrogajewski](https://github.com/dmytrogajewski).

## License

Published project code is **GPL-2.0-or-later**; see [LICENSE](LICENSE) and
[COPYRIGHT.md](COPYRIGHT.md). The target engine, [ioquake3](https://ioquake3.org/), is GPL software.
Its license does not grant rights to Daikatana's original code or assets. This is an independent
community project, unaffiliated with the original game's rights holders.

<!-- README structure informed by https://github.com/RichardLitt/standard-readme -->
