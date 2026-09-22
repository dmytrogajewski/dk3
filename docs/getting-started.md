# Getting started

You can build the published tools without owning Daikatana. The development checkout includes native game modules and an asset/install graph;
the [campaign rewrite](rewrite-roadmap.md) is incomplete and gameplay verification is pending.

## Requirements

| Component | Requirement |
|---|---|
| OS | Linux x86-64 |
| Compiler | Zig 0.16.x, at least 0.16.0 |
| Archive tools | Python 3.10 or newer; standard library only |
| Asset conversion | NumPy from requirements.txt; ffmpeg 7 |
| Convenience commands | Make |
| Engine client/renderers | SDL2 development files and pkg-config |
| Memory limits | `prlimit` from util-linux, or a working systemd user session |
| Optional headless graphics | `xvfb-run` and `xauth` |

Download Zig from [the official download page](https://ziglang.org/download/) and put its directory
on `PATH`. `zig version` should report a supported version. Zig supplies the C/C++ compiler; the engine requires SDL2 development headers and pkg-config.

## Build and run

```sh
git clone https://github.com/dmytrogajewski/dk3.git
cd dk3
make build
./zig-out/bin/dkguard --mem 512M --timeout 30s -- python3 --version
```

You should see the Python version and `dkguard: finished status=0 (exited)`.
The engine executables are `zig-out/bin/dk3` and `zig-out/bin/dk3ded`; the runner is
`zig-out/bin/dkguard`. Independent native modules are in `zig-out/lib/dk3/`; campaign systems are incomplete.
See [building](building.md) for the bundled engine and optional QVM tool targets.

After [converting and installing your assets](assets.md), launch the checked
installation directly without repeating conversion:

```sh
python3 dkq3/tools/play.py launch --prefix zig-out --dkguard zig-out/bin/dkguard
```

This selects `zig-out/play/current`. Settings live under `zig-out/play/home`;
native saves live under `zig-out/play/state/dk3/saves`. Presentation and campaign
verification are still in progress; see the [opening repair record](../specs/bugs/BUG-opening-presentation-and-combat.md).

An existing locally generated HD package at
`zig-out/hd-textures/dkq3-textures_hd.pk3` is included by `play-install` automatically.
Use `-Dhd-textures=/path/to/package.pk3` to supply one elsewhere. The launcher selects
full texture resolution when this overlay is installed; `+set r_picmip 1` can override it.
The package stays local and contains texture images only.

For a brighter or darker image, open **Video**, adjust **Brightness**, then choose
**Apply**. Higher values brighten textures; 1.0 is neutral. Applying reloads the video
renderer. Fullscreen and windowed modes use software gamma rather than changing the
display's gamma ramp, so desktop gamma support is not required. The console equivalent
is `r_gamma 1.3` followed by `vid_restart`.

After gameplay verification, run the broad checks once with `make lint`. Build output lives in `zig-out/`; compiler caches live in
`.zig-cache/`. Both are ignored by Git.

## Format tools

The tools take explicit input and output paths. They never download game content.

To package a text file you created into a PK3:

```sh
mkdir -p zig-out/example
printf 'Hello from dk3\n' > zig-out/example/hello.txt
python3 dkq3/tools/pk3.py zig-out/example/example.pk3 hello.txt=zig-out/example/hello.txt
python3 -m zipfile -l zig-out/example/example.pk3
```

To extract one known ZIP member into an explicit output file:

```sh
python3 dkq3/tools/dk_unzip.py --zip zig-out/example/example.pk3 --member hello.txt --out zig-out/example/copy.txt
cmp zig-out/example/hello.txt zig-out/example/copy.txt
```

`dkpak.py` and `dkwal.py` are Python libraries for Daikatana PAK archives and WAL texture headers.
Their checks build synthetic archives and textures in temporary directories; no retail fixtures
are included. See their module documentation and the examples in `dkq3/tools/tests/`.

## Troubleshooting

- **Zig version mismatch:** use the 0.16 release series; a newer minor series is not assumed compatible.
- **Memory cap unavailable:** install util-linux so `prlimit` is on `PATH`.
- **Headless mode needs xvfb-run:** install your distribution's Xvfb wrapper and `xauth`.
- **Development launcher:** see [assets and installation](assets.md). It loads independent
  modules and identifies incomplete campaign support.

C4 charges explode on damageable contact and stick to solid surfaces. A stuck charge
arms after one simulation second and reacts to nearby visible players or actors,
including its owner. Shooting a charge starts its fuse; nearby charges can chain through
blast damage. Right mouse button detonates your deployed charges (`detonate`, also
accepted as `c4_detonate`). Existing settings can bind this action under Controls.

Gas Hands is temporary in the campaign. Its lifetime comes from the supplied
weapon table and appears in the HUD and inventory; collecting another extends
that lifetime. You may switch weapons while it counts down. Cameras pause the
countdown, and saves and level exits retain the remaining time. When it expires,
an equipped Gas Hands switches back to the Disruptor (or another owned weapon).
Gas Hands is reserved for players; companions leave its pickups available.
In multiplayer it remains available until death. Repeated campaign pickups are
bounded to one hour of remaining simulation time.

Face a ladder and move forward to climb. Its exit may need forward and jump to
clear the lip. Retractable ladders can require a nearby switch; leave room for
the rungs to extend. Authored rung delays are preserved.

Ion bolts discharge when they enter water, slime or lava, including shots fired
underwater. The local blast can hurt the shooter. Use the Disruptor for close
underwater combat. This uses the supplied ion damage with a 64-unit discharge
radius; dry bolts retain their ricochets.
