# Contributing to dk3

Welcome! The public repository contains development tools while the game runtime is being
replaced. See the [roadmap](docs/rewrite-roadmap.md) before starting gameplay work.

## Build and check a change

Use Linux x86-64, Zig 0.16.x, Python 3.10+, and Make:

```sh
make build
make lint
```

`make lint` runs formatting checks and the existing component checks. `make fmt` formats Zig
source. For headless process checks, install `xvfb-run` and `xauth`; on Debian/Ubuntu those come
from `xvfb` and `xauth`. Without them, the display-dependent check is explicitly skipped.

## Report a problem

Open an [issue](https://github.com/dmytrogajewski/dk3/issues) with the command you ran, what you
expected, what happened, your OS, and `zig version`. Include relevant log excerpts after checking
for personal paths or credentials. Do not attach retail files, extracted assets, or saved games.

## Submit a change

Fork the repository, make a focused branch, and open a pull request. Describe the behavior changed
and the checks you ran. Update the relevant documentation when commands or requirements change.
Use a descriptive title such as `fix: reject a truncated archive directory`.

Submit only code you have the right to contribute under GPL-2.0-or-later. Preserve existing
copyright and license notices. A contribution does not transfer copyright; no separate CLA or
sign-off is required. Discuss third-party code and its license before adding it.

Do not copy or mechanically translate unlicensed Gold implementation code. New runtime components
need an original implementation, a documented interface, and behavior checked against synthetic
fixtures or observations. Proprietary strings and artwork belong in locally supplied game data.

Treat other contributors respectfully. Questions and small documentation fixes are welcome.
