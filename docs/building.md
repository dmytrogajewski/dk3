# Building the bundled engine

The development checkout includes ioquake3 at `engine/ioquake3`. There is no `-Dioq3`
option and no dependency on a sibling checkout, Gold source, reference executable,
or game data for the engine build. The independent game runtime is still being implemented.

## Dependencies

- Linux x86-64, Zig 0.16.x, Make.
- SDL2 development package and pkg-config for the client and renderers.
- Vulkan headers and loader pkg-config files (`vulkan-headers`, `vulkan-loader-devel`) and
  `glslc` (shaderc) for `renderer_vulkan.so`; the build fails with a named message without them.
- Mesa lavapipe (`mesa-vulkan-drivers`) for headless Vulkan runs; `dkguard --headless`
  restricts the Vulkan loader to it.
- Python 3.10+ for the existing archive tools and their synthetic checks.
- Optional FreeType development package for `-DUSE_FREETYPE=true`.
- util-linux `prlimit` or a working systemd user session for dkguard resource limits.
- Xvfb and xauth for headless graphical runs.

## Commands

```sh
zig build
zig build engine-server
zig build game test-runtime
```

`zig build` builds the client `zig-out/native-dev/bin/dk3`, server `dk3ded`, the three renderer
shared libraries (`renderer_vulkan.so`, written in Zig under `src/renderer_vulkan`, plus the
OpenGL1/OpenGL2 renderers), native Zig modules in `lib/dk3/`, and `dkguard`.
`engine` builds only client/server/renderers; `game` builds the Zig modules. Legacy
native and QVM gameplay targets have been removed. Bundled upstream sources and
licenses remain intact; they are not another supported game runtime.

Native builds default to `zig-out/native-dev`, protecting the preserved installation.
An explicit `--prefix` can select another development directory; the historical
`zig-out` prefix is redirected to `zig-out/native-dev` and the online prefix is rejected.
After asset conversion, `zig build play` rebuilds and launches the current source using
the completed `zig-out/assets` cache. `play-install` performs the same preparation
without launching. Pass `-- +map e1m3b` to `play` for a specific map.
Native menus and campaign systems are connected; see the [acceptance matrix](native-acceptance.md)
for current verified outcomes and remaining defects.
