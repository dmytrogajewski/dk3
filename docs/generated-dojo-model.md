# Generated dojo Hiro

**Sequence 339 is visually rejected.** Its engine capture has a broken neck,
inflated shoulders, smeared cloth and poor hands. The reproduction commands
below preserve the failed experiment, not an approved replacement. Historical
mechanical receipts remain available; they do not establish model quality.
The default local candidate launcher is disabled. Original assets remain usable.

Sequence **cinematic-body-339** replaces the owner-rejected original-body
subdivision with a newly generated white-gi body. Its canonical sources are
[`dojo-hiro-generated-model.yaml`](../dkq3/animation/dojo-hiro-generated-model.yaml)
and [`dojo-dialogue-generated-manifest.yaml`](../dkq3/animation/dojo-dialogue-generated-manifest.yaml).
The [architecture note](cinematic-reconstruction.md#new-generated-dojo-character-cinematic-body-339)
records the boundaries and risks before implementation.

The new image, GLB and conversion receipts feed `generated_character.py`.
It verifies their hashes, prepares geometry-only closure inputs, admits the
closed/UV-qualified surface, fits it onto the captured 44-joint bind, and retains
the independently generated detailed head with an explicit lower collar cut.
Original rigid props remain. No original body triangles, clothing UVs or retail
gi albedo enter the new body. Local hand/sole alignment changes the mesh, not
server movement or authoritative sequence timing.

`generated_materials.py` transfers the new model's own albedo using bounded
closest-surface queries. Hair/skin contamination on declared cotton regions is
repaired from neighbouring generated cotton samples; valid fold shading is
retained and leather darkened to the original design. The result is baked to a
new 4096×4096 atlas. Blender uses its bundled spatial tree, without importing
the host SciPy ABI. Source images remain read-only. Earlier flat-material and
raw-transfer candidates are retained locally as visually rejected.

The subsequent motion build freezes the new master geometry, bind, normals,
weights and UVs. Its compact animation table and authored cinematic program
remain byte exact with sequence 338. Neither runtime format needs an extension.
The ordinary installation, selectors, original assets and owner saves remain
untouched. Numerical validation does not establish artistic acceptance.

## Reproduction

Run from the repository root with a fresh output directory. The admitted
concept and exact prompt are under `zig-out/cinematic-body-339/hiro-dojo/`.
The local TRELLIS source is revision `75fbf0183001ed9876c8dbb35de6b68552ee08bd`;
weight hashes, environment and licenses are under `zig-out/neural-tools/`.
AI inference is a pinned authored input, not a promise of identical generation
on another GPU stack. These offline rebuilds do not access the network.

```sh
dk3_gi_input="$PWD/zig-out/cinematic-body-339"
dk3_gi_work="$PWD/zig-out/my-generated-dojo"
dk3_gi_models="$PWD/zig-out/assets/current/packages/dk3-models.pk3"
dk3_gi_template="$PWD/zig-out/cinematic-fidelity-338/qualified/final/hiro-master/hiro-dojo.iqm"
/usr/bin/python3 -B dkq3/tools/generated_character.py dkq3/animation/dojo-hiro-generated-model.yaml --actor "$dk3_gi_input/hiro-dojo" --prepare-closure --out "$dk3_gi_work/closure-source"
blender --background --factory-startup --threads 4 --python-exit-code 1 --python dkq3/tools/neural_surface_close.py -- --source "$dk3_gi_work/closure-source" --out "$dk3_gi_work/closed-body" --voxel 0.1 --thickness 0.18 --seal-radius 0.8 --triangles 60000 --partition-orientations --fill-volumes "$dk3_gi_work/closure-source/anatomy-volumes.json"
blender --background --factory-startup --threads 4 --python-exit-code 1 --python dkq3/tools/generated_materials.py -- --input "$dk3_gi_work/closed-body/model.iqm" --source "$dk3_gi_work/closure-source" --out "$dk3_gi_work/materials"
/usr/bin/python3 -B dkq3/tools/generated_character.py dkq3/animation/dojo-hiro-generated-model.yaml --actor "$dk3_gi_input/hiro-dojo" --template "$dk3_gi_template" --base-models "$dk3_gi_models" --closed-body "$dk3_gi_work/closed-body" --materials "$dk3_gi_work/materials" --out "$dk3_gi_work/hiro-generated"
/usr/bin/python3 -B - "$dk3_gi_work" <<'PY'
from pathlib import Path
import shutil, sys
out = Path(sys.argv[1])
admitted = Path('zig-out/cinematic-body-339/reviewed-generated')
for name in ['hiro-capture', 'ebihara-capture', 'ebihara-master-observed']:
    shutil.copytree(admitted / name, out / name)
for name in ['dojo-dialogue-generated-manifest.yaml', 'dojo-source-retarget.yaml', 'dojo-dialogue.yaml']:
    shutil.copyfile(Path('dkq3/animation') / name, out / name)
PY
/usr/bin/python3 -B dkq3/tools/animation_author.py build "$dk3_gi_work/dojo-dialogue-generated-manifest.yaml" --base-models "$dk3_gi_models" --out "$dk3_gi_work/build"
/usr/bin/python3 -B dkq3/tools/animation_author.py compile-manifest "$dk3_gi_work/build/animation-manifest.yaml" --base-models "$dk3_gi_models" --check-only
/usr/bin/python3 -B dkq3/tools/cinematic_model.py package --overlay zig-out/cinematic-fidelity-338/qualified/final/dk3-neural-baseline-compatible.pk3 --base-models "$dk3_gi_models" --rebuild "$dk3_gi_work/hiro-generated" --texture "$dk3_gi_work/materials/body.png" --target models/neural/c_hiro_intr.iqm --out "$dk3_gi_work/dk3-neural-generated-baseline.pk3"
/usr/bin/python3 -B dkq3/tools/animation_author.py package --overlay "$dk3_gi_work/dk3-neural-generated-baseline.pk3" --base-models "$dk3_gi_models" --build "$dk3_gi_work/build" --out "$dk3_gi_work/dk3-neural-dojo-generated.pk3"
/usr/bin/python3 -B dkq3/tools/animation_author.py compile-scene "$dk3_gi_work/dojo-dialogue.yaml" --manifest "$dk3_gi_work/dojo-dialogue-generated-manifest.yaml" --base-models "$dk3_gi_models" --out "$dk3_gi_work/dojo_dialogue.cfg"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py package "$dk3_gi_work/dojo_dialogue.cfg" --source "$dk3_gi_work/dojo-dialogue.yaml" --manifest "$dk3_gi_work/dojo-dialogue-generated-manifest.yaml" --assets zig-out/assets/current/packages/dk3-data.pk3 --assets "$dk3_gi_models" --assets zig-out/assets/current/packages/dk3-voice.pk3 --assets zig-out/assets/current/packages/dk3-sound.pk3 --out "$dk3_gi_work/dk3-dojo-dialogue.pk3"
/usr/bin/python3 -B dkq3/tools/animation_author.py inspect "$dk3_gi_work/build/hiro.iqm" > "$dk3_gi_work/hiro-inspection.json"
```

The template provides the measured bind, independent head and original props;
its original gi geometry is excluded. Capture and Ebihara recipes are unchanged.
The output directory contains only derived local products. Keep generator,
atlas and original-performance provenance with them.

## Native review

For historical comparison only, the staged interactive profile plays the selected
eleven-shot recording with the rejected body when explicitly requested. It uses its own home and guard;
the ordinary launcher remains unchanged. Hardware GUI execution is for owner
testing; the automated qualification below uses guarded software rendering.

```sh
/usr/bin/python3 -B zig-out/cinematic-body-339/owner-test/play-generated.py --rejected
/usr/bin/python3 -B zig-out/cinematic-body-339/owner-test/play-generated.py --legacy
```

Native runs use an isolated dereferenced installation at
`zig-out/cinematic-body-339/native-runtime/`, pinned in each recording receipt.
An earlier generation was removed by concurrent work, so its old path cannot
reproduce these captures. The CLI supplies dkguard `--headless` without `--gpu`
and disposable profiles. Run engine jobs sequentially.

```sh
dk3_gi_engine="$PWD/zig-out/cinematic-body-339/native-runtime"
/usr/bin/python3 -B dkq3/tools/animation_preview.py record --engine "$dk3_gi_engine" --overlay "$dk3_gi_work/dk3-neural-dojo-generated.pk3" --overlay zig-out/cinematic-performance-337/authored-set/zzz-dk3-reconstruction-set.pk3 --overlay "$dk3_gi_work/dk3-dojo-dialogue.pk3" --presentation skeletal --map intr_dialogue --program dojo_dialogue --trigger 4 --shots 11 --restore --report "$dk3_gi_work/native-skeletal" --seconds 210
/usr/bin/python3 -B dkq3/tools/animation_preview.py replay --engine "$dk3_gi_engine" --overlay "$dk3_gi_work/dk3-neural-dojo-generated.pk3" --overlay zig-out/cinematic-performance-337/authored-set/zzz-dk3-reconstruction-set.pk3 --overlay "$dk3_gi_work/dk3-dojo-dialogue.pk3" --presentation skeletal --demo "$dk3_gi_work/native-skeletal/author_preview.dm_1351" --report "$dk3_gi_work/native-video" --seconds 240
PYTHONPATH=dkq3/tools /usr/bin/python3 -B -m unittest discover -s dkq3/tools/tests
zig build test-runtime --prefix zig-out/cinematic-body-339/zig-check
```

For original-model fallback, omit the neural overlay and choose
`--presentation legacy`; the optional archive is actually excluded. Add
`--renderer opengl1` for GL1. Headless full-body inspection uses the typed
`animation_author.py blender <job.json> --out <fresh-report>` command, with
explicit body/head/prop texture paths. Blender's host OCIO fallback changes
lighting; judge native footage for appearance.

Local products are under `zig-out/cinematic-body-339/reviewed-generated/` and
evidence under `zig-out/reports/cinematic-body-339/`. The scope remains opening
shots 15–25, eleven shots, 64.8 seconds and 23 clips. Facial acting, expressive
fingers, cloth dynamics, walking contact qualification and the remaining
cinematics are separate work. Owner artistic acceptance failed.
