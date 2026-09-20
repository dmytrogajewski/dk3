# Getting started

You can build the published tools without owning Daikatana. Playing the game from a public build
is not available yet: the [runtime rewrite](rewrite-roadmap.md) is incomplete.

## Requirements

| Component | Requirement |
|---|---|
| OS | Linux x86-64 |
| Compiler | Zig 0.16.x, at least 0.16.0 |
| Tool scripts | Python 3.10 or newer; standard library only |
| Convenience commands | Make |
| Memory limits | `prlimit` from util-linux, or a working systemd user session |
| Optional headless graphics | `xvfb-run` and `xauth` |

Download Zig from [the official download page](https://ziglang.org/download/) and put its directory
on `PATH`. `zig version` should report a supported version. A system C/C++ compiler is not needed
for the published subset.

## Build and run

```sh
git clone https://github.com/dmytrogajewski/dk3.git
cd dk3
make build
./zig-out/bin/dkguard --mem 512M --timeout 30s -- python3 --version
```

You should see the Python version and `dkguard: finished status=0 (exited)`.
The executable is `zig-out/bin/dkguard`. The `daikatana` game executable is not part of this build.

Run the existing checks with `make lint`. Build output lives in `zig-out/`; compiler caches live in
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
- **Where is the game launcher?** It is still in the separate local workspace. Adding retail files
  to this checkout will not supply the missing runtime. See [local development](local-development.md).
