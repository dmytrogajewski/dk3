# Publication boundary

`dk3` publishes reviewed GPL components while the game runtime rewrite remains incomplete.
The initial publication is a new Git history made from an explicit list of reviewed source files.
It is not a recursive import of the playable workspace.

## Included

- Original Zig process supervision, resource limits, and headless-run support in `src/dkguard/`.
- Original Python PAK/WAL format readers, archive writers, and ZIP member extraction.
- Existing checks with generated fixtures; a standalone Zig build for these components.
- Bundled pinned ioquake3 and BSPC trees with upstream notices and recorded modifications.
- Independent native game, client and UI modules, asset conversion and installation tooling.
- Zig build integration for the engine, renderers, modules, navigation compiler and tools.
- Newcomer documentation, GPL terms, contribution guidance, and the runtime replacement roadmap.
- Three reviewed development screenshots in `docs/screenshots/`, displayed in the README.

## Excluded

- `reference/`, original source archives, Gold-derived runtime and source patches.
- `install/`, original or converted game data, extracted strings, saved games, and local
  captures other than the three reviewed README screenshots.
- The unreviewed game, client, UI, and common-library adapters from the local workspace.
- Neural asset experiments, downloaded model weights, Python libraries, and node modules.
- Compiler caches, packaged game assets, locally built executables, credentials, local agent configuration, and logs.

The complete ioquake3 upstream tree retains its bundled SDL development libraries for
Windows/macOS, verified against `engine/UPSTREAM.json`. These are upstream third-party
files, not local build output; the Linux build uses the documented system SDL dependency.

`.gitignore` excludes these categories, but it is not the license review. The initial Git index
is compared against an exact file list and byte hashes before pushing. `PUBLICATION.json` records
the initial reviewed file identities; later changes are reviewed through normal Git history.

## Working copies

The original workspace retains its existing source paths and game build graph. Its
`publication/build.zig` supplies the separate public build root. The initial export was created at `zig-out/publish/dk3/`. Continued development uses
the stable sibling `dk3` checkout; the generated export is preserved as historical evidence.

Continue public component work in the Git checkout. When bringing in another local component,
review its source, provenance, dependencies, and documentation before adding it. Do not copy the
whole original workspace or use force-add to bypass the exclusions.

The game's full runtime is not licensed by association with its target engine. See
[copyright and licensing](../COPYRIGHT.md) for the scope of the GPL grant.

## Development after the initial tools publication

The canonical working copy is `/home/dmitriy/sources/dk3`, outside generated output.
The current publication includes the engine/source graph additions and independently
implemented runtime. See [provenance](provenance.md) for component dispositions and
[the active roadmap](rewrite-roadmap.md) for implementation versus acceptance status.
The initial manifest describes the initial tools release, not these additions.
