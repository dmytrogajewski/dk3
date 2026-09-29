# Local skeletal characters

Sequences 315–316 integrate the local experimental Hiro, Mikiko, Superfly, Mishima
(Kage), and Usagi meshes with the native runtime. The asset generator reads the
five selected GLBs. The detailed mesh
stage closes disconnected neural surfaces, reduces them to 36,000 triangles and
bakes the original base color at source resolution.
The subsequent rig stage replaces the experimental joints, weights and clips
with reviewed anatomical landmarks, surface-smoothed weights and fixed-length
inverse kinematics. All five characters have hand/finger, toe and weapon joints;
Mishima additionally has tabard bones.
It does not execute or import the experiment's code or legacy runtime. Generated
assets remain local; their publication rights have not been established.

Generate the optional package with Blender, ffmpeg, Python and NumPy, supplying
the experiment directory explicitly:

```sh
OPENBLAS_NUM_THREADS=1 blender -b --threads 4 --python-exit-code 1 \
  --python dkq3/tools/neural_meshes.py -- --closed \
  --source /path/to/neural_experimental_assets --out zig-out/neural-assets/meshes-closed
OPENBLAS_NUM_THREADS=1 python3 -B dkq3/tools/neural_rig.py \
  --source zig-out/neural-assets/meshes-closed --out zig-out/neural-assets/meshes-rigged
OPENBLAS_NUM_THREADS=1 python3 -B dkq3/tools/neural_assets.py \
  --source /path/to/neural_experimental_assets \
  --meshes zig-out/neural-assets/meshes-rigged \
  --assets zig-out/assets --out zig-out/neural-assets/dk3-neural.pk3
zig build play-install --prefix zig-out/native-dev \
  -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe
```

The installer admits the locally generated package automatically when present.
`-Dneural-assets=/path/to/package.pk3` selects an explicit package. Installation
checks its closed cosmetic namespace, content hashes, and source model generation.
It publishes a separate installation and preserves saves. A checkout without the
optional package keeps the converted source characters.

The client selects skeletal models from an explicit mapping. Animation frame
numbers, collision, gameplay metadata, and server timing remain authoritative.
Gameplay uses independently authored skeletal clips with Quake III clip names.
Loops retain their own cadence (a run cycle is 15 frames at 30 Hz), independent
of the old vertex animation's frame count. One-shot clips retain authoritative
duration. The client interpolates poses and blends sequence changes over 100 ms;
the appended cosmetic frames do not change server events or save data.
The three established multiplayer characters keep
their selection indexes and colors. Mishima and Usagi add cosmetic selections
using Hiro and Mikiko's existing gameplay classes respectively; clients without
the optional package display those fallback bodies. Team color changes preserve
the selected character.

Cinematics fit authored vertex motion on anatomical segments, then use fixed bone
lengths and two-bone inverse kinematics for hands and feet. Typical body height
sets character scale; a raised hand cannot enlarge the whole model. The converter
preserves frame counts, floor height, attachment paths and hidden/visible props.
Held cinematic props share one rigid hand attachment, including disconnected
pieces with different visibility intervals; released props keep authored motion.
Gameplay weapons use the full hand orientation and class-owned handle offset.
Sequence 319 adds pelvis-relative knee planes and joint limits during conversion:
knee flexion 3–145 degrees, hip target pitch −50–110 degrees, side-relative spread
−12–55 degrees, ankle rotation within 70 degrees of the shin and toe rotation
within 35 degrees of the foot. These restrict the fitted poses without changing
bone lengths. They are animation constraints, not runtime ragdoll physics or
collision between body parts; extreme authored performances still require review.

Moving attacks use precomposed upper-body attack/leg-cycle frame grids. The server
replicates the actual firing timestamp in the player entity's existing `time2`
field; the client selects the 30 Hz attack phase while retaining the locomotion
phase. The weapon follows that same hand pose. Stationary attacks keep their
existing authoritative sequence. Respawn eligibility now includes the selected
death clip's complete duration plus a 300 ms final-pose hold. No external game's
animation data or physics library is imported by this revision.
The combined Superfly/Mikiko models use a measured over-shoulder reference pose,
keep both characters at gameplay size, and anchor Mikiko on the carrier rather
than pulling her feet onto the floor.
Hiro's reference-based face repair uses frontal and 60-degree side projections,
generated with the built-in image tool from the selected `hiro.png` concept.
`neural_face.py` bakes them into the existing UV atlas. Its per-texel mask keeps
real hair dark and protects facial color in multiplayer variants. A skin-only
front projection prevents painting duplicate hair strands on the cheeks. The
selected skin projections are in the sequence-317 local report. Sequence 318 adds
a separate orbital projection and a bounded vertical remap that lowers the eyes
without moving the nose or mouth. Its orbital mask replaces old dark eyebrow
texels instead of treating them as protected hair; lateral hair locks stay protected.
Only the eye/brow area is admitted from that edit, preserving the earlier cheek skin.
The two new exact prompts and outputs are in the sequence-318 local report.
Run this bake after the rig stage and before packaging to reproduce that atlas:

```sh
blender -b --threads 4 --python-exit-code 1 --python dkq3/tools/neural_face.py -- \
  --mesh zig-out/neural-assets/meshes-rigged/hiro.iqm \
  --texture zig-out/neural-assets/meshes-closed/hiro.png \
  --projection zig-out/reports/runtime-zig-317/hiro-skin-front.png \
  --side-projection zig-out/reports/runtime-zig-317/hiro-reference-side.png \
  --eye-projection zig-out/reports/runtime-zig-318/hiro-eye-detail.png \
  --out zig-out/neural-assets/meshes-rigged/hiro.png
```

`neural_face_preview.py` renders the actual mesh at four fixed angles for review.
The bake writes `.face.json` provenance and a `.face-mask.png` tint mask beside
the atlas. `neural_retexture.py` can update a validated package's body and twelve
color textures without rebuilding skeletal motion. The 317 local report records
a compatible OCIO profile override used for a Blender/config version mismatch;
normal installations should use matching Blender and OpenColorIO data.

Sequence 319 applies the same reference-based workflow to Mikiko, Superfly,
Mishima and Usagi with `neural_face.py --character NAME`. Their bounded face
regions use 4096-pixel atlases; Superfly also receives a mirrored side projection.
The local `runtime-zig-319/face-edits.md` records exact built-in imagegen prompts,
projections, atlases and mesh reviews. Hiro's accepted sequence-318 atlas remains
unchanged. These edits cannot replace missing facial geometry or animate eyes.

This conversion approximates the original performance: facial morph animation is
not preserved, and the procedural body clips are not motion capture.
Body textures retain source resolution (up to 4096 pixels), with
colored multiplayer variants capped at 2048. The glTF metallic/roughness maps are
not yet used by this material path. The package report records source hashes,
clip mappings, cinematic fit residuals, and known losses.

Implementation and scenario evidence are tracked in [native acceptance](native-acceptance.md).
