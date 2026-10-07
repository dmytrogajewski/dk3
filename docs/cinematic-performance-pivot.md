# Cinematic performance pivot — sequence 342

The sequence-341 white-gi Hiro package failed native visual review. The head
retains the previously approved face geometry and atlas, but its pose, the
costume silhouette, shoulders and arms do not match the original acting. The
package remains a local diagnostic product, not a delivery candidate.

## Verified data flow and authority

The server and cinematic program retain the source model path, animation
sequence/frame identifiers, actor transforms, dialogue and game events. Original
`.dkm` content is presented through the converted `.md3` vertex frames.
`neural_models.zig` optionally resolves the same source path to an IQM and
translates the original frame interval through `neural-animations.cfg`.
That translation is client presentation only; gameplay, networking and saves
remain authoritative on the server. A missing optional package already falls
back to the original presentation. Sequence 342 also defaults *cinematic*
source models to the original presentation even when the general optional IQM
package exists. A native authoring preview opts in with
`+set cg_neuralCinematics 1` before model registration.

The original opening is recorded with `animation_preview.py record
--presentation legacy`. Its `recording.json` retains shot/time, performer
diagnostics, render-frame diagnostics, runtime and overlay identities. The
source-specific `dojo-hiro-dialogue-capture.yaml` pins the converted original
MD3 hash and maps original vertex frames to observed anatomical markers. The
current authored scene is `dojo-dialogue.yaml`; it keeps the dialogue and
required story events. The next authored scene may change choreography and
shot timing, while retaining those events.

## Why the current candidate fails

At shot 8, 51,000 ms, original source frame 686 and candidate IQM frame 1579
have nearly upright pelvis-to-chest joint axes. Yet the native candidate has a
large backward-leaning costume and distorted collar. The mismatch is in the
posed mesh and bind/weight/proportion relationship, so tuning only a head yaw
or animation identifier cannot repair it. The new surface audit compares the
*skinned IQM vertices* against original MD3 frames linked by the actual native
render diagnostics. The latest guarded native run fails on all 50 matched Hiro
frames. At the cited shot, the upper-torso horizontal center differs by 1.65
model units and the neck band depth ratio is 0.73. These are geometric
diagnostics, not an artistic-quality score.

The accepted next body must be authored to the approved Hiro head and calibrated
from observed source proportions; it should not use the rejected generated
costume or an old-body head graft as its delivery basis. Motion authoring should
use captured original 3D motion as a constraint and include manual correction
of shoulders, hands, prop contact and acting. Native paired captures are required
for each representative pose before packaging further scenes.

## Reproduce the current rejection evidence

These commands read local original and candidate outputs. They write only to
fresh ignored report paths, and do not alter retail assets or saves. Use
`/usr/bin/python3`, which has the project tooling dependencies here.

```sh
/usr/bin/python3 -B dkq3/tools/cinematic_pair_review.py \
  --original zig-out/reports/cinematic-pivot-342/native-fallback-with-package-run \
  --candidate zig-out/reports/cinematic-pivot-342/native-skeletal-explicit \
  --out zig-out/reports/cinematic-pivot-342/recheck-review

/usr/bin/python3 -B dkq3/tools/cinematic_surface_audit.py \
  --profile dkq3/animation/dojo-hiro-dialogue-capture.yaml \
  --base-models zig-out/assets/current/packages/dk3-models.pk3 \
  --candidate-iqm zig-out/cinematic-model-341/review-build/build-final/hiro.iqm \
  --recording zig-out/reports/cinematic-pivot-342/native-skeletal-explicit/recording.json \
  --out zig-out/reports/cinematic-pivot-342/recheck-audit.json

/usr/bin/python3 -B dkq3/tools/cinematic_pose_stage.py \
  --profile dkq3/animation/dojo-hiro-dialogue-capture.yaml \
  --base-models zig-out/assets/current/packages/dk3-models.pk3 \
  --candidate-iqm zig-out/cinematic-model-341/review-build/build-final/hiro.iqm \
  --recording zig-out/reports/cinematic-pivot-342/native-skeletal-explicit/recording.json \
  --shot 8 --time-ms 51000 \
  --out zig-out/reports/cinematic-pivot-342/recheck-blender-shot-008

PYTHONPATH=dkq3/tools /usr/bin/python3 -B -m unittest tests.test_cinematic_pair_review
zig build test-runtime
```

The surface-audit command exits 1 for this rejected candidate and writes the
measurements first. Open `native-paired-review/index.html` locally to scrub original
and IQM frames side by side. It deliberately emits
`decision: requires_visual_review`; mechanical success must never mark a
performance accepted. Native capture runs use `animation_preview.py`, which
launches through `dkguard --headless` and does not request `--gpu` for software
rendering. For a new IQM preview, supply the candidate package explicitly and
select `--presentation skeletal`; use `--presentation legacy` for the reference.
`--presentation fallback` retains the optional package while verifying the
default original cinematic model path. The new guarded native evidence is under
`zig-out/reports/cinematic-pivot-342/native-fallback-with-package-run/`,
`native-skeletal-explicit/`, `native-paired-review/`, and
`native-surface-audit.json`. Both native records finish all 11 shots; the
fallback has 140 original frame diagnostics and zero skeletal diagnostics,
while the explicit IQM preview reproduces the visible failure. Neither result
is an artistic acceptance of a replacement.
The headless Blender stage under `blender-shot-008-lit/` contains a `.blend`,
render and hash receipt for original frame 686 beside IQM frame 1579. It makes
the larger shoulders, changed collar and hand proportions inspectable in 3D.
It is a static authoring reference and does not supply a repaired model.

Verification: `zig build` and `zig build test-runtime` passed. The consolidated
`zig build test -Dpython=/usr/bin/python3` passed with 318 Python tests and
453 Zig tests after updating an unrelated co-op test fixture with its required
`status_ms` argument. The initial broad run exposed that stale fixture; it
was corrected and the aggregate check was rerun once.

## Remaining implementation

Sequence 343 begins the independent movement path described in
[cinematic-authored-motion.md](cinematic-authored-motion.md). Two opening clips
are authored from new acting keys and pass the existing motion build without
captured source poses. Their Blender review still rejects the current body, so
they are retained as a local trial rather than packaged for the game.

The newly authored white-gi body, calibrated bind, hand/prop contact corrections,
new performance clips, changed shot choreography, and other cinematics are not
yet implemented or visually accepted. Keep original cinematic presentation as
the default until representative native frames pass both the surface diagnostics
and human visual review. Structural checks and scene completion alone are
insufficient.
