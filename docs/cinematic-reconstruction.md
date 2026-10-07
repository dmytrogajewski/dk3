# Cinematic reconstruction

Sequence **cinematic-reconstruction-336** starts an incremental reconstruction of
the supplied cinematics. Sequence 334's studio qualified an authoring path, not
the original campaign performances. Do not treat that result as cinematic quality
acceptance.

## Continuation note: cinematic-performance-337

The owner requested continued reconstruction rather than stopping after the
first slice. The paired footage exposes a reference-pose error: frame 122 has
Hiro's face turned sideways, while relative rotation transfer starts the target
at its forward-facing bind. Original hand/prop channels also need a measured
contact constraint when body proportions change. The current source trajectory,
IQM and original-model data paths remain as documented below.

This continuation will derive semantic face axes from pinned original eye/chin
landmarks, support explicitly selected absolute orientation transfer, and add
grouped prop contact solving/serialized validation with authored visibility
retained. Original fields keep their existing meaning. It will capture the full
two-character dojo dialogue (shots 15–25), author new cameras above the existing
task queue, retain original dialogue/events and qualify paired original/IQM
playback. Reference extraction must admit actors spawned within the selected
block; fixture use targets must retain their original brush/control records.

Expected changes are the existing reconstruction, motion, manifest, authoring
and preview tools, source recipes, their tests and these acceptance records.
Native cinematic/network/save/gameplay representations remain unchanged unless
a concrete unsupported source task proves an extension necessary. Generated
observations, rigs and packages stay local under `zig-out/`.

Risks are mirrored landmark axes, wrist/prop mismatch, lost visibility/release,
actor initialization, queued clips crossing camera cuts and omitted map uses.
Tests will cover measured axes and bind preservation, contacts before/after
serialization, zero-scale visibility, source-task/event equality, deterministic
compilation and source/fixture path limits. Native recording, save/load, paired
rendering and visual review follow the connected implementation. The earlier
slice's passing receipts stay immutable; this continuation records fresh results.


## Repair note before implementation: cinematic-fidelity-338

The owner rejected the 337 review with three frames: a mismatched gesture,
sideways katana and detached/jagged collar. Numeric runtime/package acceptance
remains evidence for those contracts; it is not performance/model acceptance.
The arm fitter can move a measured elbow plane by 30–50 degrees while satisfying
its own constraints. Prop orientation currently inherits an older approximate
IQM fit. The generic armored Hiro body also does not match this source model's
white dojo gi. A faithful reconstruction needs a source-specific replacement.

Current flow remains original MD3/animation → marker capture → independent IQM
clips and eight-field mapping → original authoritative queues and compiled scene.
The extension will preserve observable measured elbow planes, capture prop
transforms/visibility from original surface data, validate pose fidelity against
those observations, and create a separate reproducible dojo body/rig candidate
instead of freezing the rejected armored geometry. Existing character and source
assets remain read-only. New generation provenance must explicitly describe any
mesh/bind/weight changes; the previous frozen-geometry proof cannot qualify it.
No server, network, save or gameplay behavior needs to change for these repairs.

Expected changes are motion/reconstruction tools, bounded source-model repair
and packaging tooling, canonical source recipes, regression tests and these
records. Risks include poorly observable palms, original coarse finger motion,
source-to-target body proportions, wardrobe/neck joins, weapon visibility and
collision through different proportions. Implement the connected repair, then
check captured versus serialized directions/props, inspect matching original and
replacement poses, replay the same native scene with fallback/save-load, and
refresh the affected tooling aggregate. All failed candidates/reports stay local.

The rejected follow-up fits also expose nonrigid source arm motion: source-region
rigid fits are usable for surface reconstruction but their manually estimated
joint centers do not define fixed-length bones throughout every cough. For
Ebihara, extend the offline rig with eight explicit source-surface corrective joints
for the neck, head, upper arms, forearms and hands. Canonical anatomical bones keep their
length checks. Corrective joints get a separate exact-observation transform check,
with their names/mapping declared in the manifest. Existing IQM channels suffice;
no runtime interface or authority boundary changes. Grip validation can use the
declared corrective hand attachment. Preserve the observed staff lift/contact
trace rather than imposing a flat, fixed grip on its sliding hand.

## New generated dojo character: cinematic-body-339

The owner rejected 338's detailed head on the subdivided original gi body.
That candidate is retained as rejected; its motion and compatibility checks do
not qualify its clothing quality. This pass generates a complete new white-gi
character from a new transparent reference using the already admitted local
TRELLIS.2 deployment. Original body triangles, clothing UVs and the low-resolution
retail gi texture must not enter the generated body.

The existing flow is original MD3 marker/prop capture → measured source rig and
surface correctives → offline IQM clips → compact animation mapping → native
authoritative cinematic queues. The extension replaces only the explicitly
admitted cosmetic model baseline, using a measured neutral rig to repose the new
mesh onto the captured reference. The original prop meshes, identities, timing,
scene compiler, source paths, saves and optional-asset fallback remain unchanged.

Expected changes are a generated-model recipe, a bounded offline rig/admission
command, focused deformation/provenance tests and these records. Generated
images, mesh, atlas, rig, receipts and previews stay under
`zig-out/cinematic-body-339/` and `zig-out/reports/cinematic-body-339/`. Risks are
inferred hand/face geometry, shoulder skinning, cloth/leg influence ownership,
reference-pose alignment and prop contact. Inspect actual generated geometry,
validate weights/bind/serialized motion and input hashes, then run fresh guarded
native playback and paired captures. The earlier original-asset playback remains
valid because its inputs are unchanged. No runtime extension is needed for this
model replacement. See [generated-body implementation and exact commands](generated-dojo-model.md)
for the new canonical manifest, rig/material tooling and local review artifacts.

## Rejected dojo body candidate: cinematic-fidelity-338

The owner rejected 337's visual result. The replacement uses a source-specific
white dojo gi, its original UVs and 256×256 texture, the previously admitted
detailed head, measured source proportions and fitted skin weights. It removes
the generic armor/collar mismatch. Two welded subdivisions smooth the body
without inventing another texture atlas. Body detail remains limited by that
original texture; this is not a high-resolution clothing-texture upgrade.

Native comparison caught two further defects that direction checks missed:
a height-only neck cut removed sleeves, and fixed-length arm reconstruction
misplaced a moving shoulder/wrist even with correct segment directions. The
final body cut follows head/neck skin ownership and keeps higher sleeves.
Eleven explicitly declared torso/head/arm surface joints reproduce Hiro's
observed pivots. His source-specific rig has 44 joints; Ebihara's has 39.
The latter keeps canonical cloak/leg weights after a broader transfer visibly
distorted the robe. Original canonical bones retain their strict translation,
length and joint-limit checks. Declared corrective transforms instead require
position error ≤0.002 units and angular error ≤0.05° against captured observations.
Existing IQM channels carry them; no runtime extension was needed.

Prop capture now measures original rigid surfaces and visibility, including
collapsed hidden swords. `source_grip` retains the original sliding relationship;
`attachment_bone` selects its declared corrective hand. `intervals` is an optional
ordered list of inclusive local sample intervals. Hiro's `sad` grip ends at
sample 39, before the original sword release; remaining samples preserve the
captured falling prop rather than claiming hand contact. Actual skinned hand
support is also checked, because an exact attachment bone previously concealed a
detached hand mesh. Limits are 1.25 units for the original coarse Hiro glove/hilt
point and 0.75 for Ebihara, with exported maxima 0.94912 and 0.14807. These are
new surface checks, separate from the unchanged 0.02-unit attachment constraint.

Ebihara's captured shaft tip lifts and varies by approximately 0.39 units in the
original performance. Its recipe explicitly uses `floor_contact.solve: false`
and a 0.5-unit floor tolerance instead of forcing the rejected fixed-floor pose.
The numerical floor check remains enabled. The original 0.1-unit solver contract
is unchanged for other recipes. Existing alpha/fullbright skin variants remain
available, including matching shader variants for the new gi material.

Canonical additions are
[`dojo-hiro-source-model.yaml`](../dkq3/animation/dojo-hiro-source-model.yaml),
[`dojo-ebihara-source-rig.yaml`](../dkq3/animation/dojo-ebihara-source-rig.yaml),
[`dojo-source-retarget.yaml`](../dkq3/animation/dojo-source-retarget.yaml),
[`dojo-dialogue-fidelity-manifest.yaml`](../dkq3/animation/dojo-dialogue-fidelity-manifest.yaml)
and [`dojo-model-repairs.yaml`](../dkq3/animation/dojo-model-repairs.yaml).
`cinematic_model.py` admits changed meshes/binds/weights as explicit new masters.
The subsequent motion-only build still freezes those masters; the old 337 proof
that original geometry was unchanged cannot describe this repair.

The local [paired review](../zig-out/reports/cinematic-fidelity-338/cinematic-review.html)
contains native footage, matching captures for all eleven shots, the three owner
poses and exact serialized full-body views. Detailed receipts and limitations
are linked there. All 23 clips validate; independent processes reproduce both
model payloads and all 27 animation outputs plus their build receipt. Check-only
compilation passes and compiling identical output preserves its inode/mtime.
The refreshed Python aggregate passes 281 tests. The retained 312 Zig tests
describe the unchanged runtime contracts qualified in 336, not other concurrent
runtime edits. Compiled scene program bytes are unchanged from 337, preserving
its already compared actor/audio/use/timing contract and new cameras.

### Reproduce the repair

Use an explicit admitted immutable installation and a fresh output directory.
The pinned templates below come from that installation's optional package;
original models/textures remain read-only. These commands do not activate it.

```sh
dk3_fidelity_engine="$PWD/zig-out/native-dev/play/0b3f6bbb325cc304ec1be2254645af17afc34caf2e3273769a7d7ce80fb24b47"
dk3_fidelity_root="$PWD/zig-out/my-cinematic-fidelity"
/usr/bin/python3 -B - "$dk3_fidelity_engine" "$dk3_fidelity_root" <<'PY'
from pathlib import Path
import shutil, sys, zipfile
engine, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=False)
recipes = ['dojo-hiro-dialogue-capture.yaml', 'dojo-ebihara-dialogue-capture.yaml',
           'dojo-hiro-source-model.yaml', 'dojo-ebihara-source-rig.yaml',
           'dojo-source-retarget.yaml', 'dojo-dialogue-fidelity-manifest.yaml',
           'dojo-model-repairs.yaml', 'dojo-dialogue.yaml']
for name in recipes:
    shutil.copyfile(Path('dkq3/animation') / name, output / name)
with zipfile.ZipFile(engine / 'share/dk3/zz-dk3-neural.pk3') as archive:
    for actor, name in [('hiro', 'c_hiro_intr'), ('tosh', 'c_tosh_intr')]:
        (output / (actor + '.iqm')).write_bytes(archive.read('models/neural/' + name + '.iqm'))
with zipfile.ZipFile(engine / 'share/dk3/dk3-models.pk3') as archive:
    (output / 'hiro-original.png').write_bytes(archive.read('skins/c_hirodojo.png'))
PY
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py capture "$dk3_fidelity_root/dojo-hiro-dialogue-capture.yaml" --models "$dk3_fidelity_engine/share/dk3/dk3-models.pk3" --out "$dk3_fidelity_root/hiro-capture"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py capture "$dk3_fidelity_root/dojo-ebihara-dialogue-capture.yaml" --models "$dk3_fidelity_engine/share/dk3/dk3-models.pk3" --out "$dk3_fidelity_root/ebihara-capture"
/usr/bin/python3 -B dkq3/tools/cinematic_model.py rebuild "$dk3_fidelity_root/dojo-hiro-source-model.yaml" --base-models "$dk3_fidelity_engine/share/dk3/dk3-models.pk3" --out "$dk3_fidelity_root/hiro-master"
/usr/bin/python3 -B dkq3/tools/cinematic_model.py rebase "$dk3_fidelity_root/dojo-ebihara-source-rig.yaml" --base-models "$dk3_fidelity_engine/share/dk3/dk3-models.pk3" --out "$dk3_fidelity_root/ebihara-master-observed"
/usr/bin/python3 -B dkq3/tools/animation_author.py build "$dk3_fidelity_root/dojo-dialogue-fidelity-manifest.yaml" --base-models "$dk3_fidelity_engine/share/dk3/dk3-models.pk3" --out "$dk3_fidelity_root/build"
/usr/bin/python3 -B dkq3/tools/animation_author.py compile-manifest "$dk3_fidelity_root/build/animation-manifest.yaml" --base-models "$dk3_fidelity_engine/share/dk3/dk3-models.pk3" --check-only
/usr/bin/python3 -B dkq3/tools/cinematic_model.py package-set "$dk3_fidelity_root/dojo-model-repairs.yaml" --overlay "$dk3_fidelity_engine/share/dk3/zz-dk3-neural.pk3" --base-models "$dk3_fidelity_engine/share/dk3/dk3-models.pk3" --out "$dk3_fidelity_root/dk3-neural-baseline.pk3"
/usr/bin/python3 -B dkq3/tools/animation_author.py package --overlay "$dk3_fidelity_root/dk3-neural-baseline.pk3" --base-models "$dk3_fidelity_engine/share/dk3/dk3-models.pk3" --build "$dk3_fidelity_root/build" --out "$dk3_fidelity_root/dk3-neural-cinematic-fidelity.pk3"
/usr/bin/python3 -B dkq3/tools/animation_author.py compile-scene "$dk3_fidelity_root/dojo-dialogue.yaml" --manifest "$dk3_fidelity_root/dojo-dialogue-fidelity-manifest.yaml" --base-models "$dk3_fidelity_engine/share/dk3/dk3-models.pk3" --out "$dk3_fidelity_root/dojo_dialogue.cfg"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py package "$dk3_fidelity_root/dojo_dialogue.cfg" --source "$dk3_fidelity_root/dojo-dialogue.yaml" --manifest "$dk3_fidelity_root/dojo-dialogue-fidelity-manifest.yaml" --assets "$dk3_fidelity_engine/share/dk3/dk3-data.pk3" --assets "$dk3_fidelity_engine/share/dk3/dk3-models.pk3" --assets "$dk3_fidelity_engine/share/dk3/dk3-voice.pk3" --assets "$dk3_fidelity_engine/share/dk3/dk3-sound.pk3" --out "$dk3_fidelity_root/dk3-dojo-dialogue.pk3"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py fixture "$dk3_fidelity_root/dojo_dialogue.cfg" --maps "$dk3_fidelity_engine/share/dk3/dk3-maps.pk3" --navigation "$dk3_fidelity_engine/share/dk3/dk3-navigation.pk3" --map intr_dialogue --out "$dk3_fidelity_root/set"
/usr/bin/python3 -B dkq3/tools/animation_author.py inspect "$dk3_fidelity_root/build/hiro.iqm" > "$dk3_fidelity_root/hiro-inspection.json"
/usr/bin/python3 -B dkq3/tools/animation_author.py inspect "$dk3_fidelity_root/build/ebihara.iqm" > "$dk3_fidelity_root/ebihara-inspection.json"
PYTHONPATH=dkq3/tools /usr/bin/python3 -B -m unittest discover -s dkq3/tools/tests
```

Run native jobs sequentially. The preview CLI supplies dkguard software
`--headless` without `--gpu` and creates disposable profiles. Stage the scene
overlay after the fixture. Omit the optional overlay and select `legacy` for
the actual original-model fallback; add `--renderer opengl1` for GL1.

```sh
/usr/bin/python3 -B dkq3/tools/animation_preview.py record --engine "$dk3_fidelity_engine" --overlay "$dk3_fidelity_root/dk3-neural-cinematic-fidelity.pk3" --overlay "$dk3_fidelity_root/set/zzz-dk3-reconstruction-set.pk3" --overlay "$dk3_fidelity_root/dk3-dojo-dialogue.pk3" --presentation skeletal --map intr_dialogue --program dojo_dialogue --trigger 4 --shots 11 --restore --report "$dk3_fidelity_root/native-skeletal" --seconds 180
/usr/bin/python3 -B dkq3/tools/animation_preview.py replay --engine "$dk3_fidelity_engine" --overlay "$dk3_fidelity_root/dk3-neural-cinematic-fidelity.pk3" --overlay "$dk3_fidelity_root/set/zzz-dk3-reconstruction-set.pk3" --overlay "$dk3_fidelity_root/dk3-dojo-dialogue.pk3" --presentation skeletal --demo "$dk3_fidelity_root/native-skeletal/author_preview.dm_1351" --report "$dk3_fidelity_root/native-video" --seconds 220
```

The exact headless Blender JSON jobs are under
`zig-out/reports/cinematic-fidelity-338/{hiro,ebihara}-qualified-blender/job.json`.
Copy a job and change its explicit input, output and texture paths before
running `animation_author.py blender <job.json> --out <fresh-report-directory>`.
CPU Blender lighting has a host OCIO fallback and does not establish a match
to native engine lighting. Judge the native paired footage.

This repairs the rejected dojo block, not all cinematics. Facial/eye/lip motion,
expressive fingers, moving contacts, cloth behavior, unselected source clips,
the remaining opening shots, other campaign programs and original campaign
handoff remain unqualified. Numeric reconstruction and visual inspection do not
substitute for owner artistic acceptance. Failed/intermediate candidates stay
in local reports; ordinary installations and owner saves are untouched.

## Complete dojo dialogue: cinematic-performance-337

The reconstructed block now covers original opening shots 15–25: eleven shots,
64.79999995 seconds, Hiro and Ebihara (`cine_toshiro`). The source recipes are
[`dojo-hiro-dialogue-capture.yaml`](../dkq3/animation/dojo-hiro-dialogue-capture.yaml),
[`dojo-ebihara-dialogue-capture.yaml`](../dkq3/animation/dojo-ebihara-dialogue-capture.yaml),
[`dojo-dialogue-manifest.yaml`](../dkq3/animation/dojo-dialogue-manifest.yaml) and
[`dojo-dialogue.yaml`](../dkq3/animation/dojo-dialogue.yaml). The manifest bakes
12 Hiro clips and 11 Ebihara clips into their existing 33/31-joint cinematic rigs.

Measured eye/chin axes retain the original absolute head heading. Explicit
`bind_bones` keeps unmapped fingers/thumbs relative to their moving hands.
`stabilize_poles` carries the elbow plane through near-straight poses, bounds its
change to eight degrees per sample and warms it across loops. The old retarget
behavior remains the default for other recipes.

Grouped `prop_contacts` solve the katana's hilt/blade/guard together. Their
`orientation: source_world` preserves measured source prop orientation instead
of applying old parent-relative channels to a different wrist pose. Original
zero-scale visibility remains present in exported channels. Ebihara's staff adds
`floor_contact`: a pinned original shaft point, a -24-unit model-space floor and
a 0.1-unit tolerance. The solver adjusts the arm to the grip while retaining the
shaft orientation and floor point. It does not stretch the arm or scale the staff.

Declared foot plants can enable `solve_contact_root` and `contact_floor`.
The floating body shifts within the existing leg limits; planted feet retain
yaw, flatten against the bind sole plane and correct their height from actual
skinned sole support. The validator measures those same support vertices after
IQM serialization, with the unchanged 0.5-unit sole/penetration tolerance.
Ankle displacement alone previously missed visibly tilted boots. The walking
clip has no declared stationary plant; locomotion foot sliding still requires
separate qualification.

Authoring actions support either nonnegative `at` or explicit `queue: true`,
which compiles the original native negative queue time. Timed `enqueue: true`
allows pending performances across camera cuts; `clear: true` emits the existing
immediate queue clear. `move_to` with `mode: inherit` preserves the class's native
movement settings. It emits neither a speed nor run/walk-mode change. No runtime
format, gameplay/network/save field, original animation table or asset selector
changes. The single original empty, negative-time animation request is recorded
as an ignored source task. A timed empty request remains an admission barrier
and cannot be dropped by the compatibility checker.

`cinematic_reconstruction.py compare` checks the consumed actor/audio contract
against the original block: actor identities/classes, spawn transforms, movement,
clip sequence and queue order/times, door use, clears/removal, dialogue and scene
completion fields. It excludes authored camera curves. Native source task hints
ignored by `server/cinematics.zig` are not silently assigned new meaning. The
fixture retains the original `dojodoor1` brush entity (`*15`, speed 100, wait -1)
and rebuilds navigation for its exact BSP. Reviewed named control chains are
bounded; unknown controls fail before fixture output. Its explicit trigger is
entity 4. The diagnostic fixture does not prove the campaign's original entry
or exit handoff.

Fresh evidence lives under `zig-out/reports/cinematic-performance-337/`; outputs
live under `zig-out/cinematic-performance-337/`. Earlier failed source fits,
thumb limits, pole/loop/contact checks, prop orientation and sole checks remain
in their original directories. The first mechanically passing skeletal footage
is not the final visual candidate: it exposed the staff orientation defect.

### Reproduce the source and build

Use a fresh directory. These inputs remain local, with original game provenance
and no redistribution grant. Every reference/capture/build command rejects an
existing output directory. Manifest compilation supports check-only and unchanged-output preservation.
The scene CLI requires a fresh output; its pure compiler emits deterministic bytes.

```sh
dk3_cinematic_engine="$PWD/zig-out/native-dev/play/0b3f6bbb325cc304ec1be2254645af17afc34caf2e3273769a7d7ce80fb24b47"
dk3_dialogue_root="$PWD/zig-out/cinematic-performance-local"
mkdir "$dk3_dialogue_root"
cp dkq3/animation/dojo-dialogue-manifest.yaml dkq3/animation/dojo-performance-retarget.yaml dkq3/animation/dojo-dialogue.yaml "$dk3_dialogue_root/"
/usr/bin/python3 -B - "$dk3_cinematic_engine/share/dk3/zz-dk3-neural.pk3" "$dk3_dialogue_root" <<'PYINPUT'
import sys, zipfile
from pathlib import Path
with zipfile.ZipFile(sys.argv[1]) as archive:
    for filename, entry in [('hiro.iqm', 'models/neural/c_hiro_intr.iqm'),
                            ('tosh.iqm', 'models/neural/c_tosh_intr.iqm')]:
        with (Path(sys.argv[2]) / filename).open('xb') as output:
            output.write(archive.read(entry))
PYINPUT
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py reference dkq3/animation/dojo-dialogue-reference.yaml --data "$dk3_cinematic_engine/share/dk3/dk3-data.pk3" --out "$dk3_dialogue_root/reference"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py capture dkq3/animation/dojo-hiro-dialogue-capture.yaml --base-models "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --out "$dk3_dialogue_root/hiro-dialogue-capture-refined"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py capture dkq3/animation/dojo-ebihara-dialogue-capture.yaml --base-models "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --out "$dk3_dialogue_root/ebihara-dialogue-capture-qualified"
/usr/bin/python3 -B dkq3/tools/animation_author.py build "$dk3_dialogue_root/dojo-dialogue-manifest.yaml" --base-models "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --out "$dk3_dialogue_root/build"
/usr/bin/python3 -B dkq3/tools/animation_author.py compile-manifest "$dk3_dialogue_root/build/animation-manifest.yaml" --base-models "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --check-only
/usr/bin/python3 -B dkq3/tools/animation_author.py compile-scene "$dk3_dialogue_root/dojo-dialogue.yaml" --manifest "$dk3_dialogue_root/build/animation-manifest.yaml" --base-models "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --out "$dk3_dialogue_root/dojo_dialogue.cfg"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py compare "$dk3_dialogue_root/reference/dojo_dialogue_original.cfg" "$dk3_dialogue_root/dojo_dialogue.cfg" --out "$dk3_dialogue_root/performance-contract.json"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py package "$dk3_dialogue_root/dojo_dialogue.cfg" --source "$dk3_dialogue_root/dojo-dialogue.yaml" --manifest "$dk3_dialogue_root/build/animation-manifest.yaml" --assets "$dk3_cinematic_engine/share/dk3/dk3-data.pk3" --assets "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --assets "$dk3_cinematic_engine/share/dk3/dk3-voice.pk3" --assets "$dk3_cinematic_engine/share/dk3/dk3-sound.pk3" --out "$dk3_dialogue_root/dk3-dojo-dialogue.pk3"
/usr/bin/python3 -B dkq3/tools/animation_author.py package --overlay "$dk3_cinematic_engine/share/dk3/zz-dk3-neural.pk3" --base-models "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --build "$dk3_dialogue_root/build" --out "$dk3_dialogue_root/dk3-neural-dialogue.pk3"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py fixture "$dk3_dialogue_root/dojo_dialogue.cfg" --maps "$dk3_cinematic_engine/share/dk3/dk3-maps.pk3" --navigation "$dk3_cinematic_engine/share/dk3/dk3-navigation.pk3" --map intr_dialogue --out "$dk3_dialogue_root/set"
```

The original reference uses the same fixture command with its original program
and a different output directory. Record it with `--presentation legacy` and
`--program dojo_dialogue_original`. Run native jobs sequentially. The preview CLI
uses dkguard software `--headless` without `--gpu`, and disposable profiles.

```sh
/usr/bin/python3 -B dkq3/tools/animation_preview.py record --engine "$dk3_cinematic_engine" --overlay "$dk3_dialogue_root/set/zzz-dk3-reconstruction-set.pk3" --overlay "$dk3_dialogue_root/dk3-dojo-dialogue.pk3" --presentation legacy --map intr_dialogue --program dojo_dialogue --trigger 4 --shots 11 --restore --report "$dk3_dialogue_root/legacy-recording" --seconds 180
/usr/bin/python3 -B dkq3/tools/animation_preview.py record --engine "$dk3_cinematic_engine" --overlay "$dk3_dialogue_root/dk3-neural-dialogue.pk3" --overlay "$dk3_dialogue_root/set/zzz-dk3-reconstruction-set.pk3" --overlay "$dk3_dialogue_root/dk3-dojo-dialogue.pk3" --presentation skeletal --map intr_dialogue --program dojo_dialogue --trigger 4 --shots 11 --restore --report "$dk3_dialogue_root/skeletal-recording" --seconds 180
/usr/bin/python3 -B dkq3/tools/animation_preview.py replay --engine "$dk3_cinematic_engine" --overlay "$dk3_dialogue_root/dk3-neural-dialogue.pk3" --overlay "$dk3_dialogue_root/set/zzz-dk3-reconstruction-set.pk3" --overlay "$dk3_dialogue_root/dk3-dojo-dialogue.pk3" --presentation skeletal --demo "$dk3_dialogue_root/skeletal-recording/author_preview.dm_1351" --report "$dk3_dialogue_root/skeletal-video" --seconds 220
PYTHONPATH=dkq3/tools /usr/bin/python3 -B -m unittest discover -s dkq3/tools/tests
```

The final camera revision reuses the already qualified fixture: first camera
position, actor/audio contract, use controls and BSP/navigation are unchanged.
Stage the new scene package last so its program wins over the embedded first
draft. `final/fixture-reuse.json` records that check. This avoids recompiling
unchanged navigation or altering its content-hash admission.

### Qualified candidate and evidence

The [local interactive review](../zig-out/reports/cinematic-performance-337/cinematic-review.html)
contains the original eleven-shot recording, synchronized new-scene playback
with original models and reconstructed IQMs, every paired shot capture, twelve
CPU Blender body views, and links to the machine-readable evidence.
The final source build is `zig-out/cinematic-performance-337/deterministic/build/`.
The separate scene package remains `final/dk3-dojo-dialogue.pk3` (SHA-256
`6f3c11d9e0bdb3a6da60c49928481d43a40e681299c844acdf6004c52f30c9ed`).
The optional closed package is `deterministic/dk3-neural-dialogue.pk3` (SHA-256
`907c6f6fcd9bb8e71a65c32577a0f1db4237ee33ec22e1cadef107a6d10622c8`).
Neither package is activated in the ordinary installation.

| Check | Evidence and scope |
|---|---|
| Original reference and new cameras with original models | `original-recording/`, `original-video/`, `final-legacy/`, `final-legacy-video/`; all eleven shots, camera release and active save/load; the optional model archive is actually absent. |
| Final IQM candidate | `deterministic-skeletal/`, `deterministic-skeletal-gl1/`, `deterministic-skeletal-video/`; all eleven shots, GL2 active save/load, software GL2/GL1 and native demo replay. |
| Original actor/audio contract | `performance-contract-final.json`; all consumed task queues, classes/transforms, dialogue, door use, removes and timing match. Cameras are intentionally newly authored. |
| Serialized motion | `deterministic/build/build.json`; all 23 clips pass. Max marker RMS is 0.95385 Hiro / 0.82014 Ebihara; max plant displacement 0.27778, skinned sole height error 0.32942, penetration 0.32423, grip error 0.000801 and staff floor error 0.000817 model units. No limits are raised. |
| Runtime mappings | `native-clip-proof.json`; 19 observed ranges select the exact declared target ranges at rate 0. Two extra head aliases and two performances interrupted by original queues are unobserved; all four are qualified only offline. |
| Package preservation | `deterministic-package-proof.json`; 936/940 entries byte exact. Two cinematic IQMs, clip table and provenance change. Both geometries, bind, weights, UVs, normals, triangles and textures remain exact. |
| Fresh-process reproduction | `deterministic-reproduction-proof.json`; 27 payloads plus build receipt reproduce byte for byte in the qualified environment. `deterministic-scene-proof.json` confirms identical compiled program bytes; `manifest-idempotence-proof.json` confirms unchanged inode/mtime. |
| Headless and source tests | `hiro-deterministic-blender/`, `ebihara-deterministic-blender/`: Blender 5.1.2 CPU, six views each; `browser-review.json`: decoded videos, paired play/seek/half speed and all eleven capture selectors; `python-aggregate-deterministic.log`: 256 tests pass. |
| Retained runtime contracts | Sequence 336 `zig-runtime-final.log`: exit 0, 312/312 Zig tests and C contracts. This continuation changes no Zig/runtime source; these are retained results, not a fresh verification of other concurrent runtime work. |

Appending IQM clips re-encodes the shared channel ranges. Original 955 Hiro and
515 Ebihara frames remain present, with measured maximum world-joint errors
0.000395/0.000741 units and 0.00330/0.00336 degrees. Retained master files and
installed packages are unchanged. Generated channel values are rounded to twelve
decimal places, including canonical zero, before IQM range compression. This
removes floating-point residuals that otherwise create nondeterministic moving
channels at approximately 1e-15 scale. It does not loosen a motion tolerance or
round the retained input frames. The failed reproduction and existing-scene-output
probes are retained beside their corrected proofs.

Visual inspection covered each native shot and all twelve full-body samples.
The staff stays upright with a solved grip/floor point, feet flatten during
stationary performances, and measured head/hand orientation replaces the old
reference-pose error. This is technical review. Facial/eye motion, expressive
fingers, cloth/body deformation and artistic approval remain open. The walking
clip has no declared stationary contact and has not passed locomotion-contact
qualification. Full opening replacement, all other scenes and original campaign
entry/exit remain pending. The next connected milestone is the rest of the opening,
with additional actors, moving contacts and original handoff verification.

Headless rig inspection uses no Blender UI:

```sh
/usr/bin/python3 -B dkq3/tools/animation_author.py inspect "$dk3_dialogue_root/build/hiro.iqm" > "$dk3_dialogue_root/hiro-inspection.json"
/usr/bin/python3 -B dkq3/tools/animation_author.py inspect "$dk3_dialogue_root/build/ebihara.iqm" > "$dk3_dialogue_root/ebihara-inspection.json"
```

The exact qualified Blender JSON jobs are in
`zig-out/reports/cinematic-performance-337/preview-input/{hiro,ebihara}-deterministic-job.json`.
Copy a job, change its explicit input/output to fresh local paths, then run
`animation_author.py blender <job.json> --out <fresh-report-directory>`.
The adapter resets factory settings, uses background CPU rendering and returns
structured hashes, tool versions and errors. It does not save over a source blend.

## Architecture note before implementation

The admitted local data package contains 62 `dk3_cinematic 1` programs. The
opening contains 115 shots, approximately 567 seconds. The offline GCE reader in
`dkq3/tools/cinematics.py` converts supplied version-15 data into this bounded
text format. `domain/cinematics.zig` parses it; `server/cinematics.zig` schedules
shots, performer queues, movement, uses, audio, camera ownership and completion.
Its `head` task changes the whole actor's absolute angles. It is not an
independent head-bone control.

`domain/animation.zig` and `engine/animation.zig` retain source frame ranges,
rates, reverse/loop flags and start times. `src/network/message_schema.zig`
serializes that authoritative state. `client/models.zig` resolves original DKM
paths to locally converted MD3 assets. The optional `client/neural_models.zig`
mapping selects IQM presentation, translates clips through
`domain/skeletal_animation.zig`, blends transitions over 100 ms and selects
precomposed attack/locomotion grids. `domain/bone_matrix.zig` provides
bind-relative transforms and attachment axes. The client ragdoll uses live skin
matrices and the separate articulated `domain/ragdoll.zig` solver; scripted
cinematic rigs deliberately retain their authored performances.

Original vertex motion is retained in the converted MD3 frames with stable
vertex correspondence and source metadata. Recording it as 3D surface markers
avoids guessing depth or losing occluded joints from a single camera. This is
motion reconstruction from supplied game data, not new actor mocap. Native video
references complement the data capture and remain necessary for visual review.
The existing generic vertex fitter is approximate; its failures must not be
hidden by raising validator limits.

The first extension adds a bounded reconstruction CLI, hash-pinned anatomical
marker recipes, temporal rigid fitting and retargeting through the existing
fixed-length IK. It produces three original-source Hiro clips, a newly authored
dojo scene and a separate deterministic scene package. The existing source
model paths and sequence names are used by both presentations. Preview tooling
will explicitly run with optional skeletal packages absent, as well as with the
candidate present. No YAML parser, unrestricted execution interface, gameplay
animation graph or save/network pose dependency is added to the runtime.

Expected changes: `dkq3/tools/cinematic_reconstruction.py`, the existing manifest
and preview tools where needed, `dkq3/animation/` recipes, focused Python tests,
this document, animation-authoring documentation and the acceptance/run records.
Generated meshes, motion arrays, packages, demos and videos remain local under
`zig-out/`.

Risks include poorly observable source regions, twist ambiguity, deformed faces,
different body proportions, prop timing, cinematic queue timing and collisions.
Reports must expose marker residuals and uncertainty, preserve source hashes,
keep geometry/bind/weights frozen, and separate numeric validation from visual
approval. The complete opening and other cinematics remain pending; a short
replacement must never silently override the full opening or its completion
targets.

Verification follows connected implementation: deterministic source capture and
compile fixtures; rejection of tampered inputs, unknown bones and unsafe paths;
serialized motion validation; paired native original/IQM scene recording, camera
release and active save/load; rendered video inspection; relevant Zig tests and
one final applicable Python aggregate. Engine jobs run sequentially through
dkguard software `--headless`, in disposable profiles. Ordinary installations,
selectors, retail inputs and owner saves are read-only.

## Acceptance

The first reconstruction slice is implemented and mechanically verified. The
local [interactive review](../zig-out/reports/cinematic-reconstruction-336/cinematic-review.html)
contains the original shot reference, synchronized original-model/IQM versions
of the new scene, every native capture and hash-bound reports. All 62 supplied
programs parse and round-trip byte for byte. The original opening is not replaced.

The canonical source is
[`dojo-hiro-manifest.yaml`](../dkq3/animation/dojo-hiro-manifest.yaml). It selects
only `models/cinematic/c_hiro_intr.dkm`, the frozen 33-joint
`dk3_humanoid_v1` rig and three clips:

| Semantic clip | Original sequence/frames | Appended IQM frames | Behavior |
|---|---|---|---|
| stance | `ambba`, 122–142 | 955–1017 | Loop |
| look_left | `lftlook`, 163–172 | 1018–1047 | One-shot head performance |
| sad | `lksadb`, 234–263 | 1048–1137 | Cinematic performance |

Source rates remain 10 Hz. Runtime mapping rate `0` preserves authoritative
source duration; it does not freeze playback. Offline samples are 30 Hz. The
compiler verifies the original `.anim` names, ranges and rates. Its eight-field
runtime rows retain the existing contract. Check-only compilation writes
nothing; identical compiled output keeps its inode and modification time.
Diagnostic JSON includes a stable code, field, source, message and severity.
Bind identity and unknown contact/attachment joints are validated before export.

[`dojo-hiro-capture.yaml`](../dkq3/animation/dojo-hiro-capture.yaml) pins the exact
converted original MD3 and specifies 19 anatomical marker groups. The CLI keeps
the original surface observations, triangle/UV correspondence and source frame
indices beside fitted transforms. Mixed thigh/hand/hair regions failed the
initial fit. Corrected explicit vertex groups pass the unchanged 1-unit RMS
limit; worst residual is 0.94482 units. Singular support, changed source hashes
and non-rigid regions fail before publishing their fitted motion.

The retargeter transfers explicitly selected head and hand rotations relative
to the measured reference pose, then applies the existing fixed-length IK and
contact solver. Serialized clips pass anatomical, length, loop and joint-step
checks. Maximum foot plant displacement is 0.16271 units against a 0.5-unit
limit. Prop visibility/animation inherits the existing source channels. Finger
motion and a measured hand-to-hilt constraint are not reconstructed in this slice.

[`dojo-retake.yaml`](../dkq3/animation/dojo-retake.yaml) authors a separate
16-second, three-shot scene with new staging/cameras and original voice audio.
It starts Hiro at the measured settled floor position. Its compiler targets
`dk3_cinematic 1`; it does not reinterpret native task 14 as a skeletal look-at.
The scene pack resolves original MD3/animation and converted sound dependencies,
checks the source recompiles exactly and refuses an existing campaign scene name.

| Scenario | State | Evidence under `zig-out/reports/cinematic-reconstruction-336/` |
|---|---|---|
| Opening shots 12–14, original models, GL2, active save/load | Passed | `original-reference-nav/recording.json`, `original-video/video.json` |
| New scene, optional skeletal package absent, GL2, active save/load | Passed | `retake-original/recording.json`, `retake-original-video/video.json` |
| New scene, IQM package, GL2, active save/load | Passed | `retake-skeletal-final/recording.json`, `retake-skeletal-video/video.json` |
| New scene, IQM package, GL1 | Passed | `retake-skeletal-gl1/recording.json` |
| Source capture, serialized motion, frozen package, deterministic reproduction | Passed | `package-proof.json`, `reproduction-proof.json`, `native-clip-proof.json` |
| Headless Blender full-body inspection, three poses × two views | Passed | `blender-job/result.json`, `full-body-preview/` (Blender 5.1.2, CPU) |
| Browser decoding, paired playback/seek/half speed, all capture selectors | Passed | `browser-review.json`, `review-browser.png` |
| Applicable Python aggregate | Passed | `aggregate-refreshed.log`: 239 tests, including 16 new reconstruction regressions; refreshed after adding JSON rejection before preview launch |
| Zig 0.16 native/runtime and catalog contracts | Passed | `zig-runtime-final.log`: exit 0, 312/312 tests; 225 native root tests and C contracts |
| Full recreated opening, other characters/scenes, campaign completion handoff | Unrun | Original programs remain available; not replaced or accepted by this fixture |
| Artistic performance, facial acting, absolute neutral-head calibration and hand-to-hilt fit | Unverified | Side-by-side review exposes the remaining pose differences |

Every engine run uses the explicit immutable installation
`zig-out/native-dev/play/0b3f6bbb325cc304ec1be2254645af17afc34caf2e3273769a7d7ce80fb24b47`,
runtime receipt `87c4af02a78616375e32d0bb3abf1c86eff356e7e3c78d07c0a1cbc72cf0adef`,
dkguard software rendering and disposable profiles. The latest source Zig test
build is a separate check; no runtime binary is installed or campaign route
replayed by this pass. The existing ragdoll debug stderr prints remain in the
passing Zig log.

Original-only previews omit the optional package from a disposable base path;
they do not simulate absence with an empty mapping. The ordinary installations,
launcher selectors and owner saves are not written. The diagnostic map reuses
all 16 original geometric BSP lumps byte for byte, but substitutes its entity
lump and rebuilds matching AAS navigation. Its explicit trigger demonstrates
scene playback, not original campaign trigger/completion parity.

First failures remain in `original-reference/` (reusing navigation after changing
the BSP entity lump), the initial capture/build reports (mixed marker regions and
foot-contact failure), and `retake-skeletal/` (SIGTERM during restoration). Their
repaired/restarted results are separate directories; failed evidence is retained.

## Local products and compatibility

Generated source inputs, observations and output packages remain under
`zig-out/cinematic-reconstruction-336/`; no original/private binary is added to
version control. Source provenance records the original game performance as
proprietary local owner-supplied data with no redistribution grant. Project tools
are GPL-2.0-or-later and reuse the reviewed local converters, IQM IO, NumPy,
SciPy, PyYAML, Blender and ZIP32 admission. No external runtime or character
asset is imported.

The scene-only product is `final/dk3-dojo-retake.pk3`, SHA-256
`b81331c7d227b8b9c2cdb20b67ae83ae70c3b3ffc78d64a78078d69fa5e26c56`.
The separate optional skeletal package is `final/dk3-neural-dojo.pk3`, SHA-256
`582ae87d5ac4dd41a0cb630a337183394d98595b5b4777a0c85384fab964ac03`.
It passes existing closed-package admission: 940 entries, 937 byte-exact payloads,
one changed cinematic IQM, one changed clip table and updated provenance.
Geometry, triangles, UVs, normals, weights, materials, bone names/parents, bind
channels and textures remain exact. Appending clips re-encodes the 955 existing
frames through global IQM quantization; maximum measured joint position error is
0.0003054 units, rigid-joint rotation error 0.003086°, scale error zero.

The current tools reproduce all twelve tested surface/motion/IQM/manifest/table
payloads byte for byte. Original authoritative timing, identifiers, collision,
gameplay, network and save representation are unchanged. Original-model playback
and active saves pass for this scene; this does not establish all-map asset or
all-save compatibility. Neither pack is activated in the ordinary installation.

## Reproduction commands

Run from the repository root with the host Python used for asset tooling. Select
an admitted installation explicitly; do not modify its assets or user home.
The recipe pins source MD3 and bind hashes, so incompatible inputs fail.

```sh
dk3_cinematic_engine="$PWD/zig-out/native-dev/play/0b3f6bbb325cc304ec1be2254645af17afc34caf2e3273769a7d7ce80fb24b47"
dk3_reconstruction_root="$PWD/zig-out/cinematic-reconstruction-local"
mkdir "$dk3_reconstruction_root"
cp dkq3/animation/dojo-hiro-manifest.yaml dkq3/animation/dojo-retarget.yaml dkq3/animation/dojo-retake.yaml "$dk3_reconstruction_root/"
/usr/bin/python3 -B - "$dk3_cinematic_engine/share/dk3/zz-dk3-neural.pk3" "$dk3_reconstruction_root/hiro.iqm" <<'PY'
import sys, zipfile
from pathlib import Path
with zipfile.ZipFile(sys.argv[1]) as archive:
    with Path(sys.argv[2]).open('xb') as output:
        output.write(archive.read('models/neural/c_hiro_intr.iqm'))
PY
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py inventory --data "$dk3_cinematic_engine/share/dk3/dk3-data.pk3" --out "$dk3_reconstruction_root/inventory"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py reference dkq3/animation/dojo-reference.yaml --data "$dk3_cinematic_engine/share/dk3/dk3-data.pk3" --out "$dk3_reconstruction_root/reference"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py capture dkq3/animation/dojo-hiro-capture.yaml --base-models "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --out "$dk3_reconstruction_root/capture"
/usr/bin/python3 -B dkq3/tools/animation_author.py inspect "$dk3_reconstruction_root/hiro.iqm"
/usr/bin/python3 -B dkq3/tools/animation_author.py build "$dk3_reconstruction_root/dojo-hiro-manifest.yaml" --base-models "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --out "$dk3_reconstruction_root/build"
/usr/bin/python3 -B dkq3/tools/animation_author.py compile-manifest "$dk3_reconstruction_root/build/animation-manifest.yaml" --base-models "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --check-only
/usr/bin/python3 -B dkq3/tools/animation_author.py compile-scene "$dk3_reconstruction_root/dojo-retake.yaml" --manifest "$dk3_reconstruction_root/build/animation-manifest.yaml" --base-models "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --out "$dk3_reconstruction_root/dojo_retake.cfg"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py package "$dk3_reconstruction_root/dojo_retake.cfg" --source "$dk3_reconstruction_root/dojo-retake.yaml" --manifest "$dk3_reconstruction_root/build/animation-manifest.yaml" --assets "$dk3_cinematic_engine/share/dk3/dk3-data.pk3" --assets "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --assets "$dk3_cinematic_engine/share/dk3/dk3-voice.pk3" --out "$dk3_reconstruction_root/dk3-dojo-retake.pk3"
/usr/bin/python3 -B dkq3/tools/animation_author.py package --overlay "$dk3_cinematic_engine/share/dk3/zz-dk3-neural.pk3" --base-models "$dk3_cinematic_engine/share/dk3/dk3-models.pk3" --build "$dk3_reconstruction_root/build" --out "$dk3_reconstruction_root/dk3-neural-dojo.pk3"
/usr/bin/python3 -B dkq3/tools/cinematic_reconstruction.py fixture "$dk3_reconstruction_root/dojo_retake.cfg" --maps "$dk3_cinematic_engine/share/dk3/dk3-maps.pk3" --navigation "$dk3_cinematic_engine/share/dk3/dk3-navigation.pk3" --out "$dk3_reconstruction_root/set"
```

The same fixture operation with `reference/dojo_reference.cfg` prepares the
original shot block. Record it first with `--presentation legacy`. The new scene
uses the following paired commands; run native jobs sequentially to avoid Xvfb
display races. Each report directory must be fresh.

```sh
/usr/bin/python3 -B dkq3/tools/animation_preview.py record --engine "$dk3_cinematic_engine" --overlay "$dk3_reconstruction_root/dk3-dojo-retake.pk3" --overlay "$dk3_reconstruction_root/set/zzz-dk3-reconstruction-set.pk3" --presentation legacy --map intr_retake --program dojo_retake --shots 3 --restore --report "$dk3_reconstruction_root/original-model-recording" --seconds 120
/usr/bin/python3 -B dkq3/tools/animation_preview.py record --engine "$dk3_cinematic_engine" --overlay "$dk3_reconstruction_root/dk3-neural-dojo.pk3" --overlay "$dk3_reconstruction_root/dk3-dojo-retake.pk3" --overlay "$dk3_reconstruction_root/set/zzz-dk3-reconstruction-set.pk3" --presentation skeletal --map intr_retake --program dojo_retake --shots 3 --restore --report "$dk3_reconstruction_root/skeletal-recording" --seconds 120
/usr/bin/python3 -B dkq3/tools/animation_preview.py replay --engine "$dk3_cinematic_engine" --overlay "$dk3_reconstruction_root/dk3-neural-dojo.pk3" --overlay "$dk3_reconstruction_root/dk3-dojo-retake.pk3" --overlay "$dk3_reconstruction_root/set/zzz-dk3-reconstruction-set.pk3" --presentation skeletal --demo "$dk3_reconstruction_root/skeletal-recording/author_preview.dm_1351" --report "$dk3_reconstruction_root/skeletal-video" --seconds 150
PYTHONPATH=dkq3/tools /usr/bin/python3 -B -m unittest discover -s dkq3/tools/tests
zig build test-runtime -j2 --summary all
```

Exact Blender inputs, material paths, poses, versions and output hashes are in
`zig-out/reports/cinematic-reconstruction-336/preview-input/job.json`. Reproduce
using `animation_author.py blender <job.json> --out <fresh-job-report>` after
changing the job's output to a fresh allowed directory. No UI interaction is
required. The local review is reproducible through `build_review.py` and its
browser controls through `inspect_review.py` in that report directory.

## Next slice and eventual cosmetic layers

Next qualify the original head reference orientation and hand/sword grip, then
extend marker capture to the remaining dojo performances and a second actor.
Recreate a complete dialogue block with original events/completion targets before
overriding any campaign program. Footage-only reconstruction remains a separate
adapter; this slice uses richer original 3D trajectories and recorded video.
The rest of the opening and all other cinematic programs remain open.

The future minimal runtime extension retains source sequence/start/rate, movement,
firing and gameplay events as authoritative server fields. Saves keep those
semantic fields; they never require exact cosmetic bone poses. The client derives
a full-body locomotion pose, masked upper-body action, additive aim/recoil,
head/eye look-at and optional facial layer from those fields and bounded authored
metadata. Hand/weapon constraints resolve after layering, transitions blend at
known sequence boundaries, and visual footstep/prop cues have explicit identities
to avoid repeats during restoration. Root motion stays cosmetic; it cannot move
the collision body or change damage timing. Masks/additive channels require an
explicit versioned manifest extension and validators; do not silently reinterpret
the current compact clip fields. Clients without the optional rig retain the
original MD3 sequence and attachment path. No animation graph or layered runtime
is implemented by sequence 336.
