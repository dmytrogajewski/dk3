# Local skeletal characters

The [sequence-344 neutral cinematic diagnostic](cinematic-neutral-slice.md)
tests independently authored Hiro motion on a generated white-gi body with
the exact approved face. It remains local and visually unapproved; original
cinematic assets are still the default and are used for unmapped sequences.

[Animation authoring](animation-authoring.md) adds strict clip/cinematic recipes,
licensed BVH/FBX import and retargeting, serialized contact/joint/loop checks,
explicit prop policies, material-correct Blender reviews and native studio video
capture. Sequence 334 qualifies three isolated Hiro clips on the admitted rig;
the ordinary sequence-333 installation remains selected. Its
[scoped acceptance](native-acceptance.md) retains unresolved original performances
and later head/facial/layer migrations.

The current rebuild uses source photos → detailed A-pose concepts → local TRELLIS.2
→ anatomical IQM masters → existing gameplay/cinematic variant construction.
It includes the five established identities, remaining story characters and all
episode-one monsters. See [the pipeline and protected prisoners](neural-monsters.md).
The experimental meshes and sequence evidence described below are historical;
their capabilities are preserved in the rebuilt package, not their old geometry.
The rebuilt faces use projections registered to each new mesh and its own camera
plan; historical Hiro eye offsets below must not be applied to a different mesh.
Sequence 328 completed 35 new masters plus two protected prisoners and installed
132 runtime IQM variants in the separate `zig-out/neural-monsters-dev` prefix.
The final master/gallery receipts and [scoped native acceptance](native-acceptance.md)
cover skeletal motion, attachments, carry, multiplayer appearances, deaths and
restoration. The historical experimental meshes are no longer the masters of that
package. Its retained source archives, model weights and dependency licenses are
documented with [the local TRELLIS.2 deployment](neural-monsters.md).
Sequence 327 also adds localized post-death weapon impulses, wake behavior and
fragment retirement; older physics limitations below describe their earlier state.

Sequence 329 completes the subsequent close-up repair: 19 closed surfaces and
registered face atlases, 41 nonfolded measured front/side registrations, exact
skeleton/frame preservation, and refreshed serialized-pose/lit-face reviews.
The 132-model isolated package passes 11 scoped native groups, with both software
renderers represented, and one aggregate of 442 Zig/130 Python tests plus C
contracts. [Native acceptance](native-acceptance.md) retains failed higher-load
software profiles and their command-overflow/drop-cleanup limitation. Full campaign
and hardware rendering remain unqualified. The owner-authorized installation now
selects that exact package in the normal native development prefix and `dk3`
launcher; previous immutable installations and saves remain preserved. The local
default package selector uses the rebuilt episode package for `zig build play`.
Installation proof is `zig-out/reports/runtime-zig-328/texture-user-install.json`.

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
After the failed dojo native visual review, cinematic source paths default to
their original vertex-model presentation even when this optional package is
installed. Explicit authoring previews can set `cg_neuralCinematics 1` before
loading the map; see [the paired review and 3D pose stage](cinematic-performance-pivot.md).
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

Sequence 320 adds actual runtime physics for these gameplay skeletons: Hiro,
Mikiko, Superfly, Mishima/Kage and Usagi. A native Zig position-based solver hands
the last visible living pose and travel velocity to a 17-particle articulated
body at death. It runs at 120 Hz with mass-weighted length constraints, knee/elbow
hinges, hip/ankle limits, self separation, swept world/brush contacts, friction
and sleep. Both renderers consume scene-owned live skin matrices and updated
bounds. No new asset conversion or external physics library is required.

The simulation is cosmetic and local to each client; health, hits, respawn timing
and movement remain server-owned. Up to 32 bodies are retained, with detached
bodies removed 15 seconds after death. Active dead actors remain visible. Saves
retain authoritative deaths, not exact simulated bone positions; loading resets
presentation. `set cg_ragdolls 0` restores authored death playback and clears
retained bodies. The default is enabled. Scripted cinematic/carrying models and
classic vertex-animated models retain their authored performances. Collision uses
joint-sized boxes and approximate self separation, not exact skinned triangles;
body-to-body pushing, projectile impulses after death and waking sleeping bodies
on moving platforms are not implemented.

Sequence 343 (`ragdoll-joint-limits`) replaces the old hip/toe limits with
anatomical cones in the torso frame. Hips flex −25–120 degrees with −20–50 degrees
of spread. Shoulders swing −55–200 degrees with −35–90 degrees of spread. The head
nods −35–50 degrees and leans ±30 degrees on the chest; the head-to-shoulder links
are gone. A stop turns the whole limb about its joint, and the rest of the body takes
the reaction by mass, so a limb pinned by the floor rolls the body over instead of
staying bent backwards. Knee and elbow bend planes follow the limb, not the trunk.
Hands, elbows and feet stay outside a pelvis–chest capsule. Static friction holds
back only free motion, never a joint correction. A stop met hard (more than about
1 degree past it in one 120 Hz step) is inelastic: both sides lose half that step's
motion, so landings do not bounce. Resting on a stop costs nothing, so shots still
shove a settled body.

The offline harness for this pass covered 180 falls on floors, slopes and walls.
Time spent outside range dropped as follows: shoulders 36% → 0.01%, elbows
31% → 0.01%, hips 24% → 4.6%, neck 20% → 0, knees 18% → 0.06%. Pelvis rebound
after landing fell from median 3.7 / maximum 45.8 units to median 1.3 / maximum
8.6. A thigh tucked to the chest may still settle up to about 25 degrees past hip
flexion. Robot and creature bodies (`creature_body.zig`) are unchanged.

Sequence 321 improves geometry stability in two places. Ragdoll presentation
reconstructs child anchors through their parent transform; collision solver
residuals no longer become independent translations that stretch the skin between
joints. The weight repair starts with rigid anatomical segment assignments and
connected joint bands, then relaxes the transitions across the welded surface.
Identical positions across UV seams retain identical weights. Shoulders and hips
can retain several influences where a strict two-bone split would create creases.
Hard prop attachments remain protected.

To update an existing local package without regenerating performances or faces:

```sh
OPENBLAS_NUM_THREADS=1 python3 -B dkq3/tools/neural_reweight.py \
  --package /path/to/original-neural.pk3 \
  --base zig-out/native-dev/play/current/share/dk3/dk3-models.pk3 \
  --out zig-out/neural-assets/dk3-neural-stable-surface.pk3
```

This patches only IQM vertex weights/indices and conservative animation bounds.
Animations, bind poses, geometry, triangles, UVs, textures, and other package
entries retain their bytes. The full rig generator also uses this weighting
policy. The existing mesh still uses linear blend skinning; tight joint folds,
merged cloth/armor surfaces and extreme twists can still need manual topology,
weight painting or corrective shapes. This pass does not make all armor plates
independent rigid geometry or introduce dual-quaternion skinning.

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
