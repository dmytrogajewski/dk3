# Cinematic model preservation — sequence 341

**Historical experiment, failed visual acceptance.** The generated body and
restored approved face still fail in the native opening. The active approach
and measured rejection are in
[cinematic performance pivot](cinematic-performance-pivot.md). Reproduction
commands below describe the rejected experiment only.

Sequence 339 failed owner visual acceptance. Its earlier captures already
showed the faults. Numerical motion and package checks must remain separate
from the visual decision to deliver a character.

Owner correction: the newly inferred head in the first sequence-341 candidate
changes Hiro's identity and is rejected. The next candidate must preserve the
exact approved head mesh and atlas from the pinned template. The generated gi
body remains usable as a source; its inferred face is discarded. The head is
unposed into the neutral reference, with only the neck connection reweighted.
Facial geometry and UV preservation require explicit evidence. The initial
341 native run completed all eleven shots and save/restore but exposed shoulder
and collar defects, so it is failure evidence, not artistic acceptance.

The current data flow is generated GLB → converted neutral mesh/UV atlas →
global signed-distance closure → vertex-colour texture transfer → captured
rig fit → separate head cut/graft → IQM → optional closed package → native
cinematic. The global closure changes the entire clothing surface. The material
transfer samples colour at vertices and bakes their interpolation; a 4096px
output cannot recover detail discarded at that step. The head cut creates a
second independent neck boundary. These are verified implementation facts;
the contribution of rig fitting remains to be measured.

The smallest diagnostic removes those three destructive stages, retaining the
newly generated character's own head, neck, clothing and atlas. Its source
geometry is still new, not a subdivided original body. Existing capture-derived
motion, rigid props, IQM, source identifiers and timing remain the inputs. Small
holes are a separate local repair problem, not grounds for remeshing and
repainting the entire model.

Expected changes: one source recipe, bounded local mesh repair/preservation
logic where needed, texture admission tied to the source hash, focused tests,
and this note. Inputs and historical mechanical receipts stay read-only.
Outputs remain under ignored `zig-out/cinematic-model-341/` and
`zig-out/reports/cinematic-model-341/`. No runtime, server, network, save,
retail installation or normal launch selector changes are proposed.

Risks: raw reconstruction holes, insufficient facial detail, shoulder/hand
deformation in the measured bind, and native lighting. Inspect neutral and
posed results with the actual source atlas, then native captures of the
affected shots. Reject visible defects before authoring more clips. Add
structural and source-preservation regression tests for the corrective code;
retain existing mapping, timing and original-asset fallback evidence when
their inputs do not change. A successful test or video decode does not approve
appearance.

Implemented replacement: a newly generated complete Hiro in a white gi, including
its own head. The 1536-cascade checkpoint is exported through a narrow voxel
surface band and local topology cleanup before UV unwrapping. Conversion retains
the exported triangles, UVs and corner normals. Material correction samples the
generated atlas per texel: 3.6% of vertex samples identify skin-coloured contamination
in the cotton volume; valid cloth detail is retained. No legacy body geometry,
head graft, global signed-distance closure or vertex-colour rebake is used.

The generated mesh binds to anatomical bones. The original vertex-model surface
correctives remain explicit, measured and validated, but do not skin this body.
Head rotation is measured in absolute model coordinates; half its axial turn is
shared by the neck without moving joint origins. The neutral generated head is
not baked into the old model's 108-degree reference turn. Explicit closed-fist
ownership avoids assigning the complete fist to a thumb bone. Grip validation
accepts the declared anatomical hand or its declared surface corrective; source
grip, captured props and actual visible hand-surface checks remain required.

Preserved compatibility: the 44-bone bind, legacy model identifier, source frame
ranges, authoritative rates, runtime clip mapping, scene, events and prop tracks.
Only the optional cinematic Hiro presentation changes. Ebihara and other package
characters retain their existing inputs. This is an eleven-shot opening-dialogue
slice, not acceptance of all opening shots or all game cinematics.

Source changes: `dkq3/tools/neural_character_export.py`,
`neural_monster_blender.py`, `generated_atlas_bake.py`,
`generated_character.py`, `animation_motion.py`, `animation_manifest.py`,
their focused tests, and the `dojo-hiro-preserved-model.yaml`,
`dojo-hiro-neutral-retarget.yaml`, `dojo-dialogue-preserved-manifest.yaml` and
`dojo-hiro-generation.txt` authoring sources. No runtime code changes are needed.

Current evidence: all 23 clips pass the existing motion limits; 55 focused tests
pass (`final-pose-tests-corrected.log`). The earlier broad tooling run had 307
passing tests and one unrelated cooperative-bot fixture missing `status_ms`.
Native review is pending. Intermediate diagnostic models with the collar
classification policy are rejected: that policy misclassified jaw vertices and
has been removed. Those captures are failure evidence, not delivery candidates.

Reproduction uses `/usr/bin/python3`, not the unrelated default Python environment.
All commands run at the repository root. The pinned local generator and capture
inputs are required; generated binary assets remain ignored and owner-local.

```sh
dk3_model_work="$PWD/zig-out/cinematic-model-341"
dk3_model_report="$PWD/zig-out/reports/cinematic-model-341"
dk3_model_base="$PWD/zig-out/assets/current/packages/dk3-models.pk3"
dk3_model_template="$PWD/zig-out/cinematic-fidelity-338/qualified/final/hiro-master/hiro-dojo.iqm"
dk3_model_trellis="$PWD/zig-out/neural-tools/sources/TRELLIS.2-75fbf0183001ed9876c8dbb35de6b68552ee08bd"

# Generation input: regenerated/hiro-dojo/concept.png plus the pinned receipts.
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_head_trellis.py --source "$dk3_model_trellis" --actor "$dk3_model_work/regenerated/hiro-dojo" --resolution 1536_cascade
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_character_export.py --source "$dk3_model_trellis" --actor "$dk3_model_work/regenerated/hiro-dojo" --out "$dk3_model_work/clean-extraction/hiro-dojo" --band 3 --projection 0 --triangles 100000
# Copy clean-extraction/hiro-dojo into a fresh retained-source/hiro-dojo first.
blender --background --factory-startup --threads 4 --python-exit-code 1 --python dkq3/tools/neural_monster_blender.py -- --stage convert --actor "$dk3_model_work/retained-source/hiro-dojo" --triangles 100000 --preserve-topology
/usr/bin/python3 -B dkq3/tools/generated_character.py dkq3/animation/dojo-hiro-preserved-model.yaml --actor "$dk3_model_work/retained-source/hiro-dojo" --prepare-geometry --out "$dk3_model_work/material-source"
blender --background --factory-startup --threads 4 --python-exit-code 1 --python dkq3/tools/generated_atlas_bake.py -- --input "$dk3_model_work/material-source/model.iqm" --texture "$dk3_model_work/retained-source/hiro-dojo/body.png" --out "$dk3_model_work/texel-materials"
/usr/bin/python3 -B dkq3/tools/generated_character.py dkq3/animation/dojo-hiro-preserved-model.yaml --actor "$dk3_model_work/retained-source/hiro-dojo" --template "$dk3_model_template" --base-models "$dk3_model_base" --materials "$dk3_model_work/texel-materials" --out "$dk3_model_work/final-master"

# review-build contains read-only capture copies, Ebihara's observed master,
# source recipes and final-master copied to hiro-generated. Its manifest uses
# those explicit relative inputs. These private prerequisites are not committed.
/usr/bin/python3 -B dkq3/tools/animation_author.py build "$dk3_model_work/review-build/dojo-dialogue-preserved-manifest.yaml" --base-models "$dk3_model_base" --out "$dk3_model_work/review-build/build-final"
/usr/bin/python3 -B dkq3/tools/cinematic_model.py package --overlay zig-out/cinematic-fidelity-338/qualified/final/dk3-neural-baseline-compatible.pk3 --base-models "$dk3_model_base" --rebuild "$dk3_model_work/final-master" --texture "$dk3_model_work/texel-materials/body.png" --target models/neural/c_hiro_intr.iqm --out "$dk3_model_work/dk3-neural-preserved-baseline.pk3"
/usr/bin/python3 -B dkq3/tools/animation_author.py package --overlay "$dk3_model_work/dk3-neural-preserved-baseline.pk3" --base-models "$dk3_model_base" --build "$dk3_model_work/review-build/build-final" --out "$dk3_model_work/dk3-neural-dojo-preserved.pk3"
PYTHONPATH=dkq3/tools /usr/bin/python3 -B -m unittest tests.test_generated_character tests.test_cinematic_fidelity tests.test_cinematic_performance
```

Fresh output paths are required. Receipts record source/tool hashes, Blender and
Python versions and generated asset provenance. Export itself is offline; first
provisioning of the pinned model weights is separate from reproducible builds.
Numerical checks do not establish acting quality or human visual approval.
