# Animation authoring

Sequence **animation-authoring-334** adds an agent-operated Python CLI above the
current native IQM and `dk3_cinematic 1` runtime. YAML recipes, typed JSON Blender
jobs, imported motion arrays and hash receipts are the reproducible source of an
asset build. `.blend`, IQM, PK3, screenshots and videos are derived outputs.
No command changes the ordinary launcher, installation selectors or owner saves.

Sequence **cinematic-reconstruction-336** extends this tooling with original
surface-motion capture, explicit head/hand rotation transfer, bind identity,
stable source-mapped diagnostics, check-only/idempotent compilation, separate
scene packaging and previews with the optional package genuinely absent. See
[cinematic reconstruction](cinematic-reconstruction.md) for the first original
Hiro performance, exact reproduction commands, paired engine review and limits.
The native runtime formats and authority boundaries remain unchanged.

Sequence **cinematic-performance-337** reconstructs a complete two-character,
eleven-shot dojo dialogue. Measured absolute head axes, bound finger inheritance,
loop-aware elbow poles, grouped grips, original prop orientation, staff floor
contact and actual skinned sole checks are offline extensions. Explicit pending
queues preserve cross-cut native scheduling. See the same reconstruction guide
for the canonical recipes, compatibility proof and reproduction commands.

Sequence **cinematic-fidelity-338** repairs the owner's rejected visual result.
Source-specific model recipes now admit the original dojo costume, measured
proportions, fitted weights and explicitly observed surface joints before the
unchanged motion-only geometry freeze. Captured original prop motion/visibility,
declared grip/release intervals and skinned hand support complement direction,
foot and structural checks. Model admission preserves alpha/fullbright variants.
See [the retained repair and exact commands](cinematic-reconstruction.md#rejected-dojo-body-candidate-cinematic-fidelity-338).
The owner rejected the subdivided original body. Sequence **cinematic-body-339**
generates a new white-gi body and atlas, then reuses the captured performance and
independently generated detailed head. The generated model is a new cosmetic
baseline; the subsequent motion-only build still freezes geometry/bind/weights.
See [the generated-body continuation](cinematic-reconstruction.md#new-generated-dojo-character-cinematic-body-339).
The [generated dojo guide](generated-dojo-model.md) documents the new manifest,
hash-bound geometry/material admission and exact headless rebuild commands.

Use `/usr/bin/python3 -B dkq3/tools/animation_author.py --help` and
`/usr/bin/python3 -B dkq3/tools/animation_preview.py --help`. The host environment
needs NumPy, SciPy, PyYAML and Pillow; Blender supplies its own Python and NumPy.
The embedded Blender adapter deliberately does not import the host's SciPy ABI.
Blender 5.1.2 is exercised locally. BVH and FBX use its standard importers; no
third-party Blender MCP server or downloaded executable plugin is admitted.
Video conversion uses the installed ffmpeg/ffprobe. The studio uses the existing
reviewed q3map2 and bundled bspc compiler path from `map_build.py`.

## Motion sources and provenance

[CMU Graphics Lab](https://mocap.cs.cmu.edu/) permits all uses of its motion
dataset. The selected [walking trials](https://mocap.cs.cmu.edu/search.php?maincat=3&subcat=2)
and [running trials](https://mocap.cs.cmu.edu/search.php?maincat=3&subcat=1) include
07_01 and 09_01. Bruce Hahne's
[conversion README](https://github.com/una-dinosauria/cmu-mocap/blob/09a07f54f3bbb58797325f009282d0b2048a2871/READMEFIRST.txt)
adds no restrictions and explicitly permits research and commercial use. Keep
that full notice with the downloaded data; credit CMU and Hahne. The converted
capture contains an added T-pose at frame zero, which the sample recipes exclude.
CMU does not capture its added finger/thumb channels; they are not treated as
finger performance. Hand and toe noise still needs review.

`dkq3/animation/cmu-sources.yaml` pins two small BVHs and the full notice to a
repository revision and SHA-256. `fetch-source` downloads only these bounded
files into a fresh local directory and verifies every hash. Actual motion/texture
data remains under `zig-out`; nothing is imported from the private game's runtime.

For footage, [FreeMoCap's published classroom session](https://figshare.com/articles/dataset/FreeMoCap_Sample_Data_-_2022-09-19_16_16_50_in_class_jsm/22680424)
is a candidate containing synchronized videos and reconstructed motion. The
[NLM dataset catalog](https://datasetcatalog.nlm.nih.gov/dataset?q=0001512119)
records CC BY 4.0. The publisher/API endpoints returned HTTP 403 during this pass,
so this footage is **not downloaded, processed or admitted**. FreeMoCap's
[post-processing guide](https://docs.freemocap.org/freemocap/docs/guides/posthoc-mocap/)
describes calibrated multi-camera input and reconstructed 3D outputs. The toolchain
currently consumes BVH/FBX, not arbitrary monocular footage. Its separate small
GPL test dataset is labeled low-frame-rate functionality data by its publisher;
it is not used to judge motion quality.

Import with a JSON job:

```json
{
  "operation": "import_motion",
  "input": "/absolute/local/07_01.bvh",
  "output": "/absolute/local/walk-source.npz",
  "license": "/absolute/local/license.json"
}
```

```sh
/usr/bin/python3 -B dkq3/tools/animation_author.py fetch-source \
  dkq3/animation/cmu-sources.yaml --out zig-out/my-motion/sources
/usr/bin/python3 -B dkq3/tools/animation_author.py blender import.json \
  --out zig-out/my-motion/import-report
```

An FBX uses the same import operation, with an optional `armature` name when the
file contains several rigs. The adapter samples the action's actual range, not
Blender's default 250-frame scene range. Explicit `frames` use Blender frame
numbers; manifest `input_frames` use zero-based inclusive imported NPZ indices.
Source translation, rotations, rate, hierarchy, coordinate space, Blender version,
license receipt and input hash are recorded. Nonuniform scale and non-rigid source
transforms fail admission instead of silently deforming the target mesh.
The FBX importer uses zero additional frame offset and admits integer samples
within 0.01 frames of the action's boundaries. This avoids padded first/last holds
when FBX ticks round fractional source FPS. The qualified walk interchange retains
317 frames, with maximum source-position error 0.084 and angle error 0.648°;
FBX channels are not byte-identical to the BVH.

CMU also publishes [per-trial AVI references](https://mocap.cs.cmu.edu/subjects/07/).
The selected `07_01.avi` and `09_01.avi` downloads could not verify the publisher's
TLS certificate chain in the local clients. They are not downloaded or admitted;
their contents are not claimed as camera footage. The BVH qualification below
does not depend on those videos or the unavailable FreeMoCap session.

## Clip recipes

`dkq3/animation/opening-hiro-manifest.yaml` is a complete local example for the
admitted 955-frame opening Hiro. Copy it and `cmu-retarget.yaml` beside the local
`hiro.iqm`, `walk-source.npz` and `run-source.npz`. Extract that IQM and its atlas
from the reviewed local neural package. The example's neutral is an explicitly
procedural fallback; the walking and running performances are captured motion.

```sh
/usr/bin/python3 -B dkq3/tools/animation_author.py procedural hiro.iqm \
  --kind idle --frames 63 --out neutral.npz
/usr/bin/python3 -B dkq3/tools/animation_author.py build manifest.yaml \
  --base-models zig-out/native-dev/play/current/share/dk3/dk3-models.pk3 \
  --out zig-out/my-motion/build
```

The manifest names the source `.dkm`, admitted target IQM, skeleton identity and
named clips. Each clip retains an authoritative `sequence`, `source_frames` and
`authority_fps`. `target_frames` and cosmetic `fps` describe the IQM performance.
Cosmetic `fps` is an integer native-table field. `fps: 0` follows authoritative
sequence duration; its build uses the effective target-frame rate, not the source
rate, for travel/contact calculations. A zero-rate build needs the actual
authoritative rate rather than guessing it. `mapping_key` permits the
existing `player/name` mapping contract. `compile-manifest` emits the compact
runtime table; `build` also writes the enriched YAML, motion arrays, IQMs and
`build.json`. `--base-models` checks real sequence names, ranges and rates.

Retarget recipes explicitly map source names and declare source forward/up axes.
Directions and target segment lengths drive anatomical IK, avoiding application
of a T-pose rotation delta to the target's A-pose. Clavicles, fingers, attachments,
mesh geometry, UVs, weights, bind joints and parent order retain the admitted
contract. The current adapter does not generate a new deformation rig.

In-place clips retain removed travel separately. Their build derives a constant
forward `movement_speed` and solves contacts against that virtual actor path.
The declared root policy also applies when the motion already targets the rig:
`in_place` removes its planar root displacement; `preserve` restores separately
retained travel into the sampled pose. Motion inputs are never modified.
Loop sampling excludes the repeated endpoint. Contact intervals are inclusive
local frame indices; `loop` controls authoring resampling and seam validation.
Actual playback looping still comes from the authoritative server animation state.
`contacts` can propose intervals, which remain editable in
YAML. `solve_contacts` uses fixed-length two-bone IK for feet and hands. Validators
measure serialized IQM output, not only pre-export matrices. They report offending
frames for bone translations, knee/elbow/ankle/wrist bounds, joint steps, loop
seams, configured relative joint limits and attachment discontinuities. Plant
displacement uses a conservative axis-span bound with linear memory use.
Distances are **DK3 model units**, not assumed centimeters.

`props` names existing `prop_*` joints. Its modes are `inherit` (default, sampled
from the authoritative interval), `hide` (zero-scale visibility), and `attach`
(a named parent, local position and angles). Prop visibility remains discrete;
interpolation cannot produce a half-sized sword. Prop channels are retained
separately from rigid body matrices. A mocap body therefore cannot accidentally
leave old sword geometry at its bind transform. The sample studio is explicitly
unarmed. Animated prop visibility inside an independently looping body clip still
shares that clip's timeline; use an authoritative-duration performance for timed
prop gestures. Independent layers are a later runtime feature.

`retarget`, `contacts`, `solve-contacts`, `validate`, `attach` and `grid` are
standalone typed operations. `attach` adds a local attachment joint to a separate
output; a frozen motion-only package rejects rig mutations. `grid` builds the
existing 30 Hz attack-row × locomotion-column compatibility layout with an
explicit upper-body mask and u16 capacity checks. It preserves auxiliary prop
visibility. `fit-legacy` delegates to the existing vertex-motion fitter on a copy,
then retargets onto the frozen admitted skeleton. Its output is an approximation
requiring review, not production mocap. `audit` catalogs source-frame failures
without quietly fixing them or declaring artistic acceptance.

The YAML loader rejects duplicate keys, Python tags, unknown fields, nonfinite
values, invalid ranges and native capacity violations. It does not evaluate
expressions. Imports, builds and manifests are ordinary editable source files.

## Cinematic recipes and native review

`dkq3/animation/studio-scene.yaml` demonstrates walk, head look, idle and run shots.
Compile it against the **enriched build manifest**, which contains measured gait
speed:

```sh
/usr/bin/python3 -B dkq3/tools/animation_author.py compile-scene \
  dkq3/animation/studio-scene.yaml \
  --manifest zig-out/my-motion/build/animation-manifest.yaml \
  --base-models zig-out/native-dev/play/current/share/dk3/dk3-models.pk3 \
  --out zig-out/my-motion/author_studio.cfg
```

Anchors and actor declarations produce explicit positions, classes and unique
IDs. Camera keys use seconds, horizontal FOV degrees, Quake pitch/yaw/roll and
optional look-at anchors or RGBA blends. Cubic Hermite coefficients use the
runtime's descending polynomial order; angular curves unwrap the shortest arc.
Actor look curves have continuous velocity across the runtime's 200 ms segments.
`play`, `idle`, `move_to`, `turn`, `look_at`, `wait`, `use`, `remove` and `teleport`
compile to existing tasks; sound events use the existing shot sound table.

Actor tasks are sequential. The compiler rejects overlaps, missing sequence
aliases, mismatched authoritative play durations, out-of-shot actions and facial
or concurrent-layer requests that the current runtime cannot execute. Movement
`clip` selects an explicit alias, including classes without an original `runa`.
Its speed must match the built gait. Movement duration remains a queue budget;
collision-dependent arrival is checked in native replay. This pace check does
not add speed adaptation to every existing player/NPC locomotion state.
The existing task named `head` writes the whole performer's absolute angles.
`look_at` therefore rotates the body; it cannot provide independent head/eye
tracking. The compiler preserves the current heading at the curve's start and
reports this limitation. Actor `look_height` selects the look origin above its
position (22 by default, 44 in this admitted Hiro studio). `turn` changes yaw only;
its vector's pitch/roll slots must be zero. The compiler accounts for the native
tenfold yaw-speed multiplier, preserving requested turn duration.

`package` merges a passing build into a validated cosmetic base package, retains
unrelated assets, preserves the frozen rig/geometry again at admission, merges
the compact clip table, updates entry hashes and embeds provenance. Changed or
failed build outputs cannot be packaged. The output is a separate local PK3.

```sh
/usr/bin/python3 -B dkq3/tools/animation_author.py package \
  --overlay zig-out/native-dev/play/current/share/dk3/zz-dk3-neural.pk3 \
  --base-models zig-out/native-dev/play/current/share/dk3/dk3-models.pk3 \
  --build zig-out/my-motion/build --out zig-out/my-motion/authored.pk3
/usr/bin/python3 -B dkq3/tools/animation_preview.py studio \
  zig-out/my-motion/author_studio.cfg --out zig-out/my-motion/studio
/usr/bin/python3 -B dkq3/tools/animation_preview.py record \
  --engine zig-out/native-dev/play/current \
  --overlay zig-out/my-motion/authored.pk3 \
  --overlay zig-out/my-motion/studio/zzz-dk3-animation-studio.pk3 \
  --shots 3 --restore --report zig-out/my-motion/native
/usr/bin/python3 -B dkq3/tools/animation_preview.py replay \
  --engine zig-out/native-dev/play/current \
  --demo zig-out/my-motion/native/author_preview.dm_1351 \
  --overlay zig-out/my-motion/authored.pk3 \
  --overlay zig-out/my-motion/studio/zzz-dk3-animation-studio.pk3 \
  --report zig-out/my-motion/video
```

The generated `intr_anim` map selects existing opening character models. It has
sealed geometry, real lightmaps/visibility/lightgrid, a cinematic trigger and
compiled navigation. Every native run is a dkguard software `--headless` child
in a disposable profile, without `--gpu`. Run engine scenarios sequentially;
independent asset preparation can run concurrently. The recorder checks camera
ownership, all shots, input release and optional active save/load. The replay
captures 30 Hz engine AVI, then encodes H.264. Receipts identify exact engine,
modules, installed packages, additional overlays and demo/video hashes. A successful
run qualifies that studio and those clips; it does not qualify the whole campaign.
Replay requires the demo's successful `recording.json`; it rejects changed demos,
runtime identities or overlay hashes before capture.

The Blender adapter also supports `convert_fbx` and `render_preview`. A preview
job names the actual exported IQM, its material atlases, frame indices, views and image size.
Use `textures` to map IQM material names to local images, for example
`models/neural/hiro/body` → `hiro.png` and `models/neural/hiro/head` → `hiro-head.png`.
Every material needs a mapping or an explicit fallback `texture`. The adapter
rejects applying one atlas across a multi-material body/head model. A model with
no supplied textures can be reviewed in plain gray. Prop materials require their
own atlas for a visible carried object; the sample's props are deliberately hidden.
Textures use the same V convention as the IQM renderer. Rendering is CPU Cycles;
an optional `.blend` is derived review material. A locally mismatched OCIO library
and Blender data require a compatible `OCIO` configuration, as recorded for earlier
asset previews. Blender preview lighting is not a claim of native shading parity.

Masked skeletal layers, new twist/facial/eye controls, audio-driven faces and
automatic video reconstruction remain separate runtime/source migrations.
Production-quality scene performance still requires source selection and visual
review; passing geometry/contact checks alone cannot supply acting quality.

## Qualification: animation-authoring-334

The local [interactive review](../zig-out/reports/animation-authoring-334/animation-review.html)
contains the full native video, all 34 GL2 captures, ten corrected material
previews, source failure table, recipes and hash receipts. Browser inspection
decodes the H.264 file and exercises every shot/pose selector and half-speed
playback. The artifact can be rebuilt with
`/usr/bin/python3 -B zig-out/reports/animation-authoring-334/build_review.py`.

The admitted source walk/run import contains 317/149 frames and 31 joints at
approximately 120 Hz. A 33-joint frozen Hiro receives 63 neutral, 32 walk and 22
run frames at 30 Hz; target ranges are 955–1017, 1018–1049 and 1050–1071. Measured
movement speeds are 42.864 and 103.592 model units/s. On the same selected samples,
walk plant displacement falls from 2.0204 to 0.4853 units; run displacement falls
from 0.6809 to 0.00015. All declared contacts pass the 0.5-unit limit on serialized
output, together with anatomical, fixed-length, loop and attachment checks.

The final generated three-shot bundle passes software GL2 and GL1 on the immutable
sequence-333 engine/modules. Both movement targets are reached, all three
IQM ranges are observed at 30 Hz, camera/input ownership is retained and normal
control returns. GL2 additionally saves an active shot, restores it and completes
again. Exact-identity demo replay produces a 960×540, 30 Hz H.264 video. All engine
runs use dkguard; installation selectors and the ordinary launcher remain exact.
No native runtime source changes or replacement installation are part of this pass.

`package-proof.json` checks all 940 entries: 937 payload hashes remain exact,
one IQM and the clip table change, and provenance metadata is refreshed. Frozen
geometry, UVs, normals, weights, triangles, bind joints, parents and atlases are
exact. Appending clips re-encodes the 955 original frames through IQM's global
channel quantization: measured maximum rigid-joint position error is 0.00097
units, rotation error 0.00278°, and scale error zero. Original master inputs and
the installed source archive remain exact. The separate authored PK3 is
`zig-out/animation-authoring/dk3-neural-qualified.pk3`, SHA-256
`5bb319d0b57183aea2690b3b49b62b39c1af91a1a50ecba13ba9dd07fd216162`.

The final applicable Python aggregate passes **218 tests**, including 25 new
authoring regressions. Prior failures remain in their original reports: padded
import ranges, embedded SciPy dependency, single-atlas/prop previews, missing
studio navigation/trigger, and a concurrent headless-X collision. A late fixture
syntax error is repaired and the invalid aggregate is refreshed; the final suite
is not followed by duplicate broad native tests. `final-policy-proof.json` confirms
that the final root/FPS-policy build reproduces every native-qualified IQM, motion,
manifest and clip-table output byte for byte; the earlier native evidence remains
valid. Native binaries are unchanged.

Original Hiro audit retains **12 of 42** clips with anatomical joint-step
violations; excluding auxiliary prop rotations avoids misclassifying visibility
events as body motion. These original performances, all other story scenes,
masked layers, facial channels, new rigs and footage reconstruction remain open.
This pass qualifies the reusable authoring path and the three isolated examples,
not a full campaign animation replacement or production acting quality.

## Component review

New project tooling is GPL-2.0-or-later. PyYAML (MIT), SciPy and NumPy (BSD),
Pillow (HPND) and Blender retain their upstream licenses in their installed
distributions. Their use is confined to asset/development tooling. No code from
the third-party Blender MCP example, paid mocap service or private runtime is
copied. CMU data and its conversion notice remain local and are pinned above.
The implementation reuses reviewed IQM IO, anatomical fitting, ZIP32 admission,
map compilation/navigation and native diagnostic drivers.
