# Building the bundled engine

The development checkout includes ioquake3 at `engine/ioquake3`. There is no `-Dioq3`
option and no dependency on a sibling checkout, Gold source, reference executable,
or game data for the engine build. The independent game runtime is still being implemented.

## Dependencies

- Linux x86-64, Zig 0.16.x, Make.
- SDL2 development package and pkg-config for the client and renderers.
- Python 3.10+ for the existing archive tools and their synthetic checks.
- Optional FreeType development package for `-DUSE_FREETYPE=true`.
- util-linux `prlimit` or a working systemd user session for dkguard resource limits.
- Xvfb and xauth for headless graphical runs.

## Commands

```sh
zig build
zig build engine-server
zig build qvm-tools
zig build qvms
```

`zig build` builds the client `zig-out/bin/dk3`, server `dk3ded`, both renderer shared
libraries, native upstream module foundations in `bin/baseq3/`, independent modules in `lib/dk3/`,
and `dkguard`.
`engine` selects engine products and `game` selects independent modules. The campaign
is incomplete. No launcher substitutes the local legacy game.

`qvm-tools` builds the upstream compiler tools under `bin/qvm-tools/`; `qvms` compiles
its foundation modules under `bin/baseq3/vm/`. These are optional development targets.
The upstream LCC compiler has separate distribution terms in
[`COPYRIGHT`](../engine/ioquake3/code/tools/lcc/COPYRIGHT); it is not covered by the
project's GPL grant. Qualification of the all-open-source QVM build path remains
open, and the default native build does not depend on LCC.

The default target is `x86_64-linux-gnu` and optimization is `ReleaseSafe`. Use
`-Doptimize=Debug` or another Zig mode when diagnosing a relevant problem. Mirrored
options are `USE_HTTP`, `USE_VOIP`, `USE_CODEC_VORBIS`, `USE_CODEC_OPUS`, `USE_MUMBLE`,
`USE_OPENAL`, and `USE_FREETYPE`. VOIP requires Opus; Opus requires Vorbis's Ogg dependency.
`PKG_CONFIG` selects the package configuration executable. Missing development packages
and source files produce named diagnostics.

Engine C/C++ inputs come directly from the bundled tree. Only GLSL-to-C strings and
the QVM compiler's generated grammar output are generated in the build cache. Source
lists and compiler settings reuse the previous independently written Zig graph.
`engine/UPSTREAM.json` records the pinned archive and per-file source identities;
`engine/CHANGES.json` records the admitted engine changes and resulting source hashes.

Do not run full checks after every build edit. At the end of scenario verification,
`make lint` runs formatting and the existing synthetic/process suite. `make test` and
`zig build test` select the same suite, so they are alternatives rather than extra gates.

The `assets`, `play-install`, and `play` commands are wired for independent development.
See [assets and installation](assets.md). Corpus and gameplay verification remain pending.

Native C compilation includes a sorted hash of bundled `.h`/`.inc` inputs in each
module's compiler command. A local Zig 0.16 cache hit retained old renderer limits
after a header edit; the explicit input signature prevents that stale reuse. Engine
and game sources still compile directly from their canonical paths. BSPC tracks its
own header tree independently. Changes to C implementation files use normal caching.

Client-game C builds keep sanitizer traps separate (`-fno-sanitize-merge`). This
preserves the originating operation in GDB when optimized code is inlined; a shared
trap previously attributed a floating conversion failure to unrelated view smoothing.
The sanitizer checks remain enabled.

The default native build has completed from an explicit source copy inside a
bubblewrap filesystem with the reference workspace, assets, prior caches and
network unavailable. The isolated dedicated executable also reaches common
initialization using only the generated original base package. This is build
and startup evidence, not campaign acceptance; see the run log for exact scope.

Piped console input is line-buffered: fragmented writes and batches retain command
boundaries, and a final command at EOF does not require a newline. An oversized
line is rejected as a whole with a diagnostic; its fragments are never executed.
This applies to both the client console and dedicated-server administration.
