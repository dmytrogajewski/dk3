# The existing playable workspace

This guide describes the maintainer's separate, existing development workspace. These commands
are **not available in the public component checkout**. Its root build graph, runtime adapters,
Gold reference code, and assets were intentionally left out of the public export.

Keeping that workspace in place preserves the playable game and its saves during the rewrite.
The public component build does not overwrite its `build.zig` or move its source directories.

## Current game build requirements

- Linux x86-64, Zig 0.16.x, Make, and Python 3.10+ with `numpy>=1.26,<3`.
- SDL2 development files discoverable through `pkg-config`, and working desktop OpenGL/audio.
- FFmpeg major version 7 with PCM, IMA ADPCM, MP3, and Vorbis support required by the converters.
- An ioquake3 checkout. The verified checkout is commit
  `588393618dbc82e7207c21c6ddecca229944a03a` from [ioquake/ioq3](https://github.com/ioquake/ioq3).
  The local graph reads `../ioq3` by default; `-Dioq3=/path/to/ioq3` overrides it.
- The existing Gold source dependency at `reference/dk-gold`. A redistribution grant has not
  been established, so it is neither included nor downloaded by this project.
- Legally acquired Daikatana data. The local working corpus includes the 1.3 update's data;
  an unpatched retail-only corpus has not been qualified. Keep the full data directory intact,
  including archives and loose overrides. Default location: `install/data`.

## Build, verify, and play

In the existing complete workspace:

```sh
zig build assets-env -DDK_DATA=/path/to/daikatana/data
zig build play-install -DDK_DATA=/path/to/daikatana/data
zig build play -DDK_DATA=/path/to/daikatana/data
```

`play-install` converts locally supplied assets, builds the game, and checks installed files
without opening a window. `play` opens the main menu. Pick **Single Player**, then a difficulty.
Configure controls under **Keyboard** and **Mouse**; Esc opens the menu during play.

The local default paths allow simply `zig build play`. The full game is installed to
`zig-out/play-full/`. Saves are in `zig-out/play-full/home/dkq3/save/`; settings are in
`zig-out/play-full/home/dkq3/fooconfig.cfg`. Preserve that directory before cleaning build output.
Original 1.3 saves and port saves are not interchangeable.

HD textures are optional and remain local. Original assets, converted packages, upscaled images,
and saves must not be committed or uploaded as release downloads.

## Moving toward the public game build

The goal is a checkout that needs only the documented open-source dependencies and user-supplied
game assets. It must compile and run with `reference/` absent. The
[rewrite roadmap](rewrite-roadmap.md) tracks this requirement; the current component release does
not claim it is met.
