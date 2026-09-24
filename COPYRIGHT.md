# Copyright and licensing

The original dk3 code published in this repository is licensed under the GNU General Public
License, version 2 or (at your option) any later version, SPDX `GPL-2.0-or-later`.
Contributors retain copyright in their contributions. See [LICENSE](LICENSE) for the complete terms.

The software is distributed without any warranty, including the implied warranties of
merchantability or fitness for a particular purpose, as detailed in that license.

This grant covers the reviewed original code in the public repository. It does not relicense
files elsewhere in the maintainer's development workspace. In particular, original Daikatana
source, source patches containing its text, game assets, extracted text, converted assets,
reference executables, and saved games are not included and receive no license grant here.

The [README screenshots](docs/screenshots/README.md) depict locally supplied game artwork.
The depicted artwork belongs to its respective owners; publishing these development
captures does not relicense that artwork under the project's GPL grant.

The PAK/WAL tools implement file-format rules and use synthetic test fixtures. References to
original filenames in comments document format research; those source files are not distributed.
The process runner uses Zig's standard library and Linux interfaces. The development tree
also bundles ioquake3 and its third-party sources with their original notices. This project's
GPL grant does not replace those licenses; see [component dispositions](docs/provenance.md).

ioquake3 is bundled under `engine/ioquake3` with its own
[GPL license and notices](engine/ioquake3/COPYING.txt). Its LCC tools carry separate
[terms](engine/ioquake3/code/tools/lcc/COPYRIGHT) and are optional development targets.
The Daikatana 1.3 maintainers explicitly say they cannot release the game's source in their
[project README](https://github.com/maraakate/daikatana). We have not established a GPL grant for
the Gold source used by the local playable build, so that runtime remains excluded.

Daikatana and Quake names belong to their respective owners. Their use identifies compatibility
and project goals, and does not imply endorsement.
