# Publication boundary

`dk3` publishes reviewed GPL components while the game runtime rewrite remains incomplete.
The initial publication is a new Git history made from an explicit list of reviewed source files.
It is not a recursive import of the playable workspace.

## Included

- Original Zig process supervision, resource limits, and headless-run support in `src/dkguard/`.
- Original Python PAK/WAL format readers, archive writers, and ZIP member extraction.
- Existing checks with generated fixtures; a standalone Zig build for these components.
- Newcomer documentation, GPL terms, contribution guidance, and the runtime replacement roadmap.

## Excluded

- `reference/`, original source archives, Gold-derived runtime and source patches.
- `install/`, original or converted game data, extracted strings, saved games, and screenshots.
- The unreviewed game, client, UI, and common-library adapters from the local workspace.
- Neural asset experiments, downloaded model weights, Python libraries, and node modules.
- Compiler caches, packaged assets, executables, credentials, local agent configuration, and logs.

`.gitignore` excludes these categories, but it is not the license review. The initial Git index
is compared against an exact file list and byte hashes before pushing. `PUBLICATION.json` records
the initial reviewed file identities; later changes are reviewed through normal Git history.

## Working copies

The original workspace retains its existing source paths and game build graph. Its
`publication/build.zig` supplies the separate public build root. The reviewed public Git working
copy lives at `zig-out/publish/dk3/` in that workspace; it can also be cloned independently.

Continue public component work in the Git checkout. When bringing in another local component,
review its source, provenance, dependencies, and documentation before adding it. Do not copy the
whole original workspace or use force-add to bypass the exclusions.

The game's full runtime is not licensed by association with its target engine. See
[copyright and licensing](../COPYRIGHT.md) for the scope of the GPL grant.
