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
zig build game test-runtime --prefix zig-out/replacement
```

`zig build` builds the client `zig-out/bin/dk3`, server `dk3ded`, both renderer shared
libraries, native Zig modules in `lib/dk3/`, and `dkguard`.
`engine` builds only client/server/renderers; `game` builds the Zig modules. Legacy
native and QVM gameplay targets have been removed. Bundled upstream sources and
licenses remain intact; they are not another supported game runtime.

Native `play-install` and `play` require a separate prefix such as
`--prefix zig-out/native-dev`, protecting the preserved default installation.
Pass `-- +map e1m3b` to `play`; full native menus/campaign are not implemented yet.
