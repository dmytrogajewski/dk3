# Authored cinematic movement — sequence 343

Hiro's opening performance can be designed for the skeletal character instead
of fitted to the old MD3 poses. The original recording remains the reference
for dialogue, scene events, sequence identifiers, timing, and editorial intent.
The original model and animation remain the default cinematic presentation.

The first local trial has two hand-authored clips: a guarded breathing stance
and a glance to the side. `cinematic_motion_author.py` reads keyed root, torso,
head, hand, elbow, and palm controls, solves the arm chains with fixed bone lengths,
and emits the existing NPZ motion interchange. It consumes no original vertex
frames or captured skeletal poses. The source skeleton supplies only bind and
attachment structure. `animation_author.py` accepts those exact 30 Hz frames;
it rejects an authored clip whose count/rate differs from its target interval.
That avoids world-space interpolation stretching IK limbs. Authored corrective
bones follow their anatomical parent in bind-local space, while captured clips
continue to require measured source correctives. Server sequence IDs and
movement remain authoritative, and IQM remains optional cosmetic presentation.

The test manifest is generated into an ignored report directory by
`cinematic_motion_trial.py`. Only explicitly named clips switch to authored
motion. The remaining captured clips are unchanged. For this *trial*, the
original prop transforms are inherited from the frozen rig because new
hand/prop acting has not been authored. That policy is recorded in the trial
receipt; it is not a final sword-contact solution.

The four-frame Blender contact sheets under
`zig-out/reports/cinematic-motion-343/stance-palm-preview/` and
`look-left-palm-preview/` confirm the independently keyed head turn and raised arm
targets. They also show the rejected sequence-341 body still has large
trousers, squared shoulders, and badly formed forearms/hands. The authored
clips passed structural validation, but neither the model nor the acting is
visually accepted for installation. No new cinematic package was admitted.
The isolated 23-clip `trial-palm-build/` passed, and its `neural-animations.cfg` SHA-256 is
`e8f52f7c65cf0b9ede44fc261d65f12b5d7009f5efe747538f10a3abcab825e1`,
identical to the prior captured-motion build. This confirms the trial changed
cosmetic pose frames without changing the server-facing mapping table.

## Reproduce the local trial

Run from the repository root. The ignored local IQM master and capture manifest
are private inputs; these commands never write installed retail assets.

```sh
dk3_trial="$PWD/zig-out/reports/cinematic-motion-343/my-trial"
dk3_rig="$PWD/zig-out/cinematic-model-341/final-master/generated.iqm"
dk3_source="$PWD/zig-out/cinematic-model-341/review-build/dojo-dialogue-preserved-manifest.yaml"
mkdir -p "$dk3_trial"
/usr/bin/python3 -B dkq3/tools/cinematic_motion_author.py \
  dkq3/animation/dojo-hiro-authored-stance.yaml --rig "$dk3_rig" \
  --out "$dk3_trial/stance"
/usr/bin/python3 -B dkq3/tools/cinematic_motion_author.py \
  dkq3/animation/dojo-hiro-authored-look-left.yaml --rig "$dk3_rig" \
  --out "$dk3_trial/look-left"
/usr/bin/python3 -B dkq3/tools/cinematic_motion_preview.py \
  --rig "$dk3_rig" --motion "$dk3_trial/look-left/motion.npz" \
  --frames 0 9 21 29 --out "$dk3_trial/look-left-preview"
/usr/bin/python3 -B dkq3/tools/cinematic_motion_trial.py \
  --base-manifest "$dk3_source" \
  --clip-motion "hiro.stance=$dk3_trial/stance/motion.npz" \
  --clip-motion "hiro.look_left=$dk3_trial/look-left/motion.npz" \
  --out "$dk3_trial/animation-manifest.yaml"
/usr/bin/python3 -B dkq3/tools/animation_author.py build \
  "$dk3_trial/animation-manifest.yaml" \
  --base-models zig-out/assets/current/packages/dk3-models.pk3 \
  --out "$dk3_trial/build" > "$dk3_trial/build.log"
PYTHONPATH=dkq3/tools /usr/bin/python3 -B -m unittest \
  tests.test_cinematic_motion_author tests.test_animation_author
```

The next implementation must author a narrower, properly skinned body around
the exact approved Hiro face, then create distinct locomotion, gesture, prop
contact, and dialogue clips. Rebuild the opening scene and inspect native
captures before enabling skeletal cinematic presentation. The current default
fallback is preserved until that visual review passes.
The next [slim-body experiment](cinematic-body-344.md) improves the raw shape,
but its generated texture and two automated material bakes fail visual review.

Verification for this trial: 29 focused Python tests passed; the local 23-clip
build passed; `zig build test-runtime` passed (453 Zig tests). The wider
`zig build test -Dpython=/usr/bin/python3` run reached 453/453 Zig tests but
failed on two checks outside this change: `test_texture_scale`'s ramp
expectation and formatting in `src/runtime/server/coop_bot.zig`. Neither file
was changed for this motion trial. The full run log is
`zig-out/reports/cinematic-motion-343/zig-test.log`.
