# Asset inputs and independent installation

The conversion and installation graph is implemented; corpus and gameplay verification
remain pending. No original game assets are distributed. All output is private below
`zig-out/`, and the preserved legacy installation is never modified.

Install Python dependencies from `dkq3/tools/requirements.txt`. Supply ffmpeg 7 with
PCM decoding/encoding and libvorbis support. Use `-Dpython=/path/to/python` to choose
the interpreter and `-Dffmpeg=/path/to/ffmpeg` to choose the encoder. The explicit
`-Dffmpeg-major` option records an alternate major in the generation identity; such
generations require their own conversion evidence.

The presentation package includes the supplied loading plaques, particle atlas
and authored cloud images. Per-map sky metadata selects two moving cloud layers
and sky-only lightning flashes through ioquake3 shaders. Cloud direction, tiling,
speed, alpha and lightning frequency come from worldspawn. The flash waveform is
an independent approximation using ioquake3's noise table, which is recreated
when the renderer starts. Its cloud projection uses ioquake3's sky dome. Maps without a cloud name
retain their skybox; missing named cloud images report the map and image path.

Completed deterministic conversion stages can be reused across worker-count
changes. Interpreter, input content, profile, converter code and relevant encoding
options still identify a stage; changing only concurrency does not rebuild AAS.

```sh
zig build
zig build assets -DDK_DATA=/path/to/data -Dasset-profile=retail
zig build play-install -DDK_DATA=/path/to/data -Dasset-profile=retail
zig build play -DDK_DATA=/path/to/data -Dasset-profile=retail
```

`retail` requires pak1.pak through pak4.pak. It reads present numbered archives in
ascending priority (pak0 through pak9), then loose game assets. `1.3` additionally
requires pak6.pak and either pak5.pak or pak5.zip containing exactly one pak5.pak;
pak5 overrides the other archives, matching the existing 1.3 asset installation.
Loose files override either profile. Names are resolved case-insensitively and
ambiguous loose-file names are diagnosed. Inputs are explicit; no source archive,
reference executable, generated Gold registry or legacy runtime is consulted.

For tables, 1.3 selects JSON before CSV/VSC; retail selects CSV/VSC before JSON.
VSC files are decoded as data and normalized into versioned quoted runtime records.
Raw supplied tables, scripts, route files and subtitles are also preserved locally.
Map entities remain verbatim, including authored target relationships. Image palette
selection uses the same effective .ent override as map conversion.

Conversion writes `zig-out/assets/<content-key>/`, with inputs, stage logs/reports,
packages and a final manifest. Completed stages can resume after interruption and are reused across navigation-compiler
changes when their inputs and commands match. AAS compilation resumes individual maps
and validates lump bounds and usable reachability before packaging. Navigation runs
after the independent conversions. Difficulty/mode selections share an AAS file when
their eligible brush entities match; otherwise the compiler emits separate variants
and a per-map selection record. The
`current` link changes only after completion and a check that inputs did not change.
The generation identity includes input hashes, converter hashes, profile, Python,
NumPy and ffmpeg. Package output uses fixed archive metadata and encoder settings.
Known missing/rejected asset names are explicit allowances, not wildcard suppressions;
their absence from a particular profile or repair by a loose override is allowed.

`play-install` checks package hashes, ZIP integrity and required startup assets, then
copies this build's client, server, renderers and native modules into a separate
generation below `zig-out/play/`. Its manifest states that gameplay is incomplete.
`play` launches that generation through dkguard, with settings in `zig-out/play/home/`
and new-format saves in `zig-out/play/state/dk3/saves/`. Extra engine arguments follow `--`.

The installer checks file integrity; it does not certify campaign progression. The
full scenario verification remains listed in [the roadmap](rewrite-roadmap.md).

Native sound references normalize backslashes, leading separators and repeated
separators before resolving the supplied sound/music root and converted extension.
Movers, actor scripts and cinematics use the same resolver. The shipped e1m2 entry
cinematic's `globa/a_speedwhoosh.wav` typo resolves to `global/a_speedwhoosh.wav`
only when the former is absent and the latter is supplied, with a console diagnostic.
Missing unrelated sounds remain visible errors; no replacement audio is embedded.

Native rectangular sprites use `AddPolyToScene`, with RGB and alpha supplied on
the four vertices. Converted SP2 shaders therefore use `rgbGen vertex` and
`alphaGen vertex`; entity-color stages cannot read this polygon color. Regenerate
the sprite package when updating from the earlier entity-color shaders. Artwork,
fonts and menu models are read from the supplied assets; no proprietary UI text
or imagery is embedded in the runtime.
