# Cinematic neutral character diagnostic — sequence 344

This is an **unapproved diagnostic**, not an installed replacement. It tests a
different animation strategy for the opening dojo dialogue: a generated white-gi
body is rigged in a neutral pose, the previously approved Hiro face is placed on
that rig without regenerating his identity, and two performances are authored
directly on the skeleton. Original DKM/MD3 models remain the default. Enabling
`cg_neuralCinematics 1` selects the optional IQM; a cinematic sequence absent
from its clip table uses the original converted DKM/MD3 frame animation.

## Verified data flow and authority

The server still owns cinematic actor IDs, source model paths, animation frame
ranges, start times, movement, events, saves and networking. The client samples
those original ranges, optionally selects the IQM in `neural_models.zig`, and
maps only declared ranges to authored IQM frames. The new client-side
per-sequence fallback restores the registered original converted model for an
unmapped cinematic range. The default `cg_neuralCinematics 0` keeps the entire
original presentation. The `dk3_cinematic` parser and low-level scene program
remain unchanged; this slice used the existing 11-shot `dojo_dialogue` fixture.

The canonical source files are
`dkq3/animation/dojo-hiro-neutral-character.yaml`,
`dojo-hiro-neutral-stance.yaml` and `dojo-hiro-neutral-look-left.yaml`.
`cinematic_neutral_character.py` makes the neutral IQM from the generated body,
the SHA-pinned approved head and one static head orientation. It does not read
the original animation frames. `cinematic_motion_author.py` produces 63-frame
stance and 30-frame look motions from versioned rig-space controls. The local
`cinematic_partial_package.py` compiles exactly those two legacy ranges into
`neural-animations.cfg`, writes the IQM/skins/shaders/textures and validates a
deterministic ZIP32 package against the current converted model generation.
`cinematic_slim_material_blender.py` bakes a neutral-space semantic material;
its source atlas had black bake holes, so cloth albedo is synthesized while mesh
folds still provide shading. The exact head face texture remains unchanged.

## Reproduce in an isolated output directory

Inputs named below are local generated products and are deliberately ignored by
version control. The SHA pins in the neutral character recipe must match the
body, approved head and static rest input before rebuilding the rig.

```sh
/usr/bin/python3 -B dkq3/tools/cinematic_neutral_character.py \
  dkq3/animation/dojo-hiro-neutral-character.yaml \
  --body zig-out/cinematic-body-344/closed-slim-wide/model.iqm \
  --head zig-out/cinematic-fidelity-338/qualified/final/hiro-master/hiro-dojo.iqm \
  --rest zig-out/cinematic-fidelity-338/qualified/final/hiro-master/observed.npz \
  --out zig-out/cinematic-body-344/rebuilt-neutral

/usr/bin/python3 -B dkq3/tools/cinematic_motion_author.py \
  dkq3/animation/dojo-hiro-neutral-stance.yaml \
  --rig zig-out/cinematic-body-344/rebuilt-neutral/neutral.iqm \
  --out zig-out/cinematic-body-344/rebuilt-stance

/usr/bin/python3 -B dkq3/tools/cinematic_motion_author.py \
  dkq3/animation/dojo-hiro-neutral-look-left.yaml \
  --rig zig-out/cinematic-body-344/rebuilt-neutral/neutral.iqm \
  --out zig-out/cinematic-body-344/rebuilt-look

blender --background --factory-startup --python-exit-code 1 \
  --python dkq3/tools/cinematic_slim_material_blender.py -- \
  --model zig-out/cinematic-body-344/rebuilt-neutral/neutral.iqm \
  --texture zig-out/cinematic-body-344/hiro-gi-slim-cutout/body.png \
  --out zig-out/cinematic-body-344/rebuilt-material

/usr/bin/python3 -B dkq3/tools/cinematic_partial_package.py \
  --rig zig-out/cinematic-body-344/rebuilt-neutral/neutral.iqm \
  --stance zig-out/cinematic-body-344/rebuilt-stance/motion.npz \
  --look zig-out/cinematic-body-344/rebuilt-look/motion.npz \
  --body zig-out/cinematic-body-344/rebuilt-material/body.png \
  --head zig-out/cinematic-body-344/approved-head.png \
  --base-models zig-out/assets/current/packages/dk3-models.pk3 \
  --out zig-out/cinematic-body-344/rebuilt-partial.pk3
```

Every output path must be fresh. The source model, head, original installation
and saves are read-only. The report beside the PK3 records every input hash and
the two exact clip mappings.

## Evidence and limits

`zig fmt --check src/runtime/client/neural_models.zig` and `zig build
test-runtime` passed after the per-sequence fallback change. Focused Python
tests cover package determinism, exact mapping, refusal to overwrite output,
and rejection of the hand-weighted robe tab as skin. The guarded native
`dojo_dialogue` capture completed all 11 shots with the partial v3 package at
`zig-out/reports/cinematic-body-344/native-partial-skeletal-v3/recording.json`.
Its diagnostics show the authored stance (`122..142 → 1..63`) playing on Hiro;
other scene sequences visibly use the original model. The most recent material
preview is `zig-out/cinematic-body-344/neutral-clean-v11-preview/`, but that
material has **not** yet had its own guarded native replay.

The recorded diagnostic used a local hard-linked native build snapshot under
`zig-out/cinematic-body-344/native-preview` so it did not alter the preserved
installation. With that snapshot and the local scene fixtures present, repeat
the guarded native capture using:

```sh
/usr/bin/python3 -B dkq3/tools/animation_preview.py record \
  --engine zig-out/cinematic-body-344/native-preview \
  --guard zig-out/native-dev/bin/dkguard \
  --report zig-out/reports/cinematic-body-344/replay \
  --overlay zig-out/cinematic-body-344/dk3-neural-neutral-partial-v3.pk3 \
  --overlay zig-out/cinematic-performance-337/authored-set/zzz-dk3-reconstruction-set.pk3 \
  --overlay zig-out/cinematic-body-339/reviewed-generated/dk3-dojo-dialogue.pk3 \
  --map intr_dialogue --program dojo_dialogue --shots 11 --trigger 4 \
  --seconds 90 --presentation skeletal
```

The current default development installation is another valid engine input
after rebuilding it with the edited native client module; its package identity
will differ from the recorded local snapshot.

Visual acceptance is still open. The white gi has plain material detail,
bright/pale elbow patches remain, the approved head has a visible neck join,
the acting has no prop grip, and the partial clip set cannot recreate the full
scene. The 11-shot recording proves runtime compatibility and camera completion,
not cinematic quality. No generated package from this slice is installed in the
normal launcher. The next slice should solve the neck as actual geometry,
segment skin and cloth from reliable mesh regions, author the remaining actions
and prop contacts, then review paired original/optional captures before installing.
