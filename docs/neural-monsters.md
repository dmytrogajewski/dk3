# Local neural monsters and characters

Six realistic separate-head replacements are reviewed and admitted in sequence
330: Toshiro, Hiro, Superfly, Usagi, Garroth and Charon. Separate 4096-pixel atlases,
closed geometry and mesh-conditioned painting replace the failed whole-body
portrait-fitting results. Hiro's head is enlarged by 15%. The reviewed package is
installed through the normal guarded native development launcher; affected head
filtering samples pass. All 102 cinematic models receive paired sample inspection
and 2,081 clips receive numeric triage. Sequence 332 repairs bounded cinematic
resource publication, performer boat riding, ninja standing scale/torso motion and
the female guard's two short blades. The opening's 115 shots, destination arrival
and Superfly's 13 shots now complete in guarded software GL2 diagnostics. Charon
still needs visual timing/framing repair; Osaka, Casseti and Mikiko still need
visual repair. Complete visual playback of every story scene remains open. See
[current native acceptance](native-acceptance.md) for exact evidence and limits.

Sequence 333 repairs connected arm/elbow fitting and bounds wrist bend separately
from forearm roll. A fresh capture of the owner's rear gate walk shows Hiro's
repaired left wrist. Human gameplay retains moving arms for each weapon grip;
running has opposed arm swing and a flight phase. Native players distinguish
walking from running by relative speed, and extra multiplayer appearances use
their own serialized clip ranges. Five human NPCs receive refreshed locomotion
on frozen admitted rigs. All geometry, heads, weights and atlases stay exact.
The full opening, five UDP walk/run appearances, three held-weapon grips,
Superfly movement and controlled human NPC rendering/restoration pass. Paired
sample inspection covers all 102 cinematic variants and five human NPCs; complete
visual playback and the remaining character repairs are still open.

The episode pipeline reads the monster roster from this checkout's converted
`dk3/tables/aidata.cfg`, photographs each original animated model, admits a reviewed
detailed image, runs local TRELLIS.2, converts its textured GLB to skeletal IQM,
authors anatomical biped motion or fits other creature performances, then packages
the cosmetic replacements. The current roster has 37 masters: 22 episode-one
monsters, Hiro, Mikiko, Superfly, Mishima and Usagi, and ten additional story
identities. Protopod is an egg launcher; its mechanical
Slaughterskeet is a separate actor. Mishima Guard is a living helmeted soldier.
The concept pass must preserve those identities, silhouettes and equipment.

Everything generated stays in `zig-out/neural-monsters/episode1/`. The existing
original converted model package remains an immutable input. Character masters
are rebuilt here, including the existing gameplay/cinematic variants, carried
Mikiko/Superfly body, weapons, hardpoints, team skins and multiplayer appearances.
Source captures, prompts, rejected concept revisions, GLBs, 4096-pixel atlases,
IQMs, stage logs and SHA-256 receipts are retained locally.

## Local TRELLIS.2 deployment

The qualified host is an RTX 5090 **Laptop** GPU with 24 GB VRAM. Generation uses
an isolated Python 3.12 environment, PyTorch 2.8 CUDA 12.8 wheels, CUDA 12.9 for
extension compilation, GCC 14 and native `sm_120` extension kernels. Blender
capture/conversion/preview uses CPU rendering. None of these generation libraries
is a deployed game dependency.

`neural_trellis_sources.json` records admitted source archive hashes; no Git command
is used. TRELLIS.2 is pinned to `75fbf0183001ed9876c8dbb35de6b68552ee08bd`.
Archives fetched from branch URLs are admitted only if their bytes still match:
keep the local `zig-out/neural-tools/downloads/` snapshots for reproduction.
System prerequisites are Python 3.12, `uv`, GCC/G++ 14, CUDA 12.9 and Eigen headers.

```sh
python3 -B dkq3/tools/neural_trellis_setup.py bootstrap
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_trellis_setup.py build
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_trellis_setup.py weights
```

The three weight repositories have fixed revisions in the setup tool. The original
DINOv3 repository required gated access on this host. The public publisher's
[timm DINOv3 ViT-L/16 LVD1689M conversion](https://huggingface.co/timm/vit_large_patch16_dinov3.lvd1689m)
provides the same encoder weights. The adapter strictly loads them, uses the
original normalization and nonaffine output layer normalization, and reproduces
the bfloat16 RoPE period quantization. Transparent input bypasses background
removal rather than substituting another image encoder.

The xformers automatic dispatcher selected a Hopper FlashAttention 3 kernel that
failed on this Blackwell GPU. Dense attention uses PyTorch SDPA; sparse attention
explicitly selects xformers CUTLASS. Inference uses `1024_cascade`, low-VRAM model
offloading, deterministic per-class seeds, the original 12-step samplers and
32,768 token target for cascade sizing. The upstream 1024 path retains that
resolution even if it needs more tokens. There is no automatic 512 fallback.

CuMesh allocations require releasing inactive PyTorch decoder blocks before hole
filling. Its original vectorized remesh topology could also exhaust this host's
VRAM with a 16-million-face decoded mesh. `neural_trellis_memory.py` builds the same
topology in bounded batches; its CUDA comparison retained identical vertices and
triangles. Decoded meshes are checkpointed before export. Export remains at the
inferred voxel resolution, closes/remeshes geometry, reduces to 100,000 triangles
and bakes a 4096-pixel PBR atlas. The game converter then uses 36,000 triangles.

Upstream license files stay with the admitted source archives. `deployment.json`
records archive and license hashes, and `environment.txt` records installed
packages. `python-packages.json` records dependency metadata and license/notice
hashes. The encoder's [DINOv3 license](https://github.com/facebookresearch/dinov3/blob/main/LICENSE.md)
is retained separately; it is not the TRELLIS MIT license. TRELLIS.2 is
[Microsoft's upstream implementation](https://github.com/microsoft/TRELLIS.2).
Generated assets and supplied game assets remain local; this workflow establishes
no publication rights for them.

## Capture, concept and conversion

Run from the checkout root. `--assets` accepts another converted asset generation;
the default is `zig-out/assets/current`. `--out`, `--episode` and `--models` select
an output directory, episode and subset. The episode package always requires its
entire prepared roster.

```sh
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py prepare \
  --include-characters --include-story
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py capture
```

Each monster has a transparent 1024-pixel `photo.png`, a `side.png`, extracted
visible geometry/textures and authored frame/tag metadata. Reference poses use
the original idle pose, the raised pose for Rockgat, or Toshiro's standing walk
frame instead of his initial coffin pose. The source photograph is
a design reference, not the required final sculpt quality.

Use the built-in image-generation tool once per class with its `prompt.txt` and
`photo.png`. Also supply `side.png` when a costume or body part needs clarification.
For Mishima Guard, the second image is explicitly the original side view. A
separate existing neural character reference may demonstrate sculpt/render quality.
For the five established characters it also supplies their recognizable face;
their original capture remains authoritative for costume and proportions. Story
characters use their original front and side captures. Request
real transparency and retain the output alpha. The revised outputs are 1280 pixels
per edge; the prompt's requested 2048 size is not an achieved size claim.

Review species/body plan, helmet and costume, palette, proportions, pose, margin
and actual modeled depth. Rounded flesh, filleted machinery and modeled seams must
replace the coarse source facets. Texture sharpening or added scratches alone
are insufficient. Suitable bipeds require an upright symmetric A-pose with separated
relaxed hands and feet. Charon, Osaka and the priest keep their original closed
robes; their covered legs do not require a visible gap. Character body masters
have empty hands: cinematic props are attached separately during construction.
The prisoners are protected: keep their original chained poses, concepts and
converted performances. Concept re-admission is rejected for them.

Admit the selected built-in output from its saved path:

```sh
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py concept \
  --model mishimaguard --image /absolute/path/to/generated.png
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py trellis
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py convert
```

Image generation is an explicit reviewed intake. The script does not invent an
unconfigured image service or require an API key. `prompts --models NAME` updates
the saved specification after an identity correction and invalidates its concept
and downstream receipts. Re-admission backs up the prior concept by digest.

Stages retain passing products when input/tool hashes match. A changed input,
corrupt product or missing prerequisite causes a rebuild or a recorded failure.
Failures preserve their log when retried. Actor receipts are locked and updated
independently so CPU conversion can run while another actor uses the GPU. Run
only one TRELLIS producer on this GPU. A saved decoded mesh can resume export
without repeating inference if its concept, weights, resolution and seed match.

Blender imports the atlas, scales geometry, welds coincident glTF UV-seam
vertices before reduction, orients connected faces, and splits UV/surface data below the renderer's 1,000-vertex/2,000-triangle
surface limits. The isolated Python fitter avoids the observed Blender/OpenBLAS
DGESDD crash. Biped alignment measures the neutral arm axis, centers the actual
torso and preserves frontal polarity for visual review. Matching an A-pose against
an asymmetric gameplay pose can turn a soldier backwards. Source offsets are
restored for monsters; character masters use the normalized 56-unit body contract.

Suitable bipeds use the shared Hiro/Mikiko anatomical skeleton, localized welded
joint weights, fixed-length IK, foot planting and independent motion clips. The
monster conversion retains original sequence intervals and event frame numbers;
character construction preserves source gameplay timing, stance-specific moving
attacks, cinematic frame ordering, original props and named hardpoints. Robes and
long panels have pelvis-owned cloth bones so they do not stretch between legs.
New UV masks protect the new head and neck surfaces from team-color tinting.

## Face refinement after reconstruction

TRELLIS can lose eyes and facial albedo even when the concept is detailed. The
run therefore reviews 19 exposed-face identities on their actual new meshes.
Psyclaw's two eye stalks receive a separate registered eye-texture repair using
the same bounded projection stage, with a wider camera centered on its head.
Closed helmets and mechanical heads need no facial repaint; the protected
prisoners retain their existing textures. Generate registered face views after
conversion:

```sh
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py face-preview
```

The first views live in each actor's `face-source/`. Use its `front.png` as the
first built-in image-edit reference and `concept.png` as the identity reference.
Save the exact request as `face-prompt.txt`. Preserve the square canvas, fixed
orthographic camera, head outline and facial landmark positions. Restore detailed
diffuse color without moving features, changing masks, helmets, cheek markings,
glasses, hair or clothes. Charon remains a skull and the ninja remains masked.
Admission requires a square projection of at least 768 pixels:

```sh
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py face \
  --model hiro --image /absolute/path/to/registered-face.png
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py face-preview
```

`face-plan.json` records the character, mesh, projection, concept, prompt and
original front-view hashes, anatomical bounds and source-coordinate camera.
Blender bakes the bounded projection into the existing 4096-pixel atlas; the
unrefined atlas remains `body-before-face.png`. Geometry, skeletal weights and UVs
remain the reviewed master. `body.face.json` records the bake and source hashes.
Later previews go to `face-review/`, preserving the original reference. Review
front, quarter and both sides before accepting the face. A changed reference or
mesh requires a new reviewed projection. Head/neck masks are rebuilt from the
new UV layout before multiplayer tinting.
The plan also hashes vertex positions, UVs, normals and triangles. Weight or
animation repairs can retain the same registered reference only when this
geometry digest is unchanged; the bake records the resulting full IQM hash.

The conversion repair `convert --repair-uv-seams` can explicitly re-register an
existing face edit after welding and reducing the **same** TRELLIS GLB. It checks
the previous completed IQM/atlas/metadata, unchanged image-tool inputs and exact
original registered geometry. Both normalized face point clouds must remain
within 1.5 units maximum and 0.6 units at the 95th percentile. Other changes require
a new projection. The repair preserves a checkpoint and previous plan, renders
the new unrefined mesh into `face-seam-source/`, and records the bounded comparison
and both registrations in `face-seam-registration.json`. Review the resulting
atlas on the new mesh from all four angles. This reuses the existing image-tool
edit; it does not claim that edit was generated from the repaired mesh.

When this bounded comparison rejects the old projection, render the new mesh,
generate a fresh registered image edit and use `neural_seam_face.py --actor DIR
--image IMAGE --prompt PROMPT`. It requires the recorded rejection and a matching
new face-render receipt before admitting the edit. The current run regenerated
Psyclaw's eyes and Garroth's face this way.

## Animation review and packaging

Sequence 330 adds a paired original/replacement cinematic viewer and a bounded
rebuild tool. The fitter preserves semantic source surfaces, measures anatomical
landmarks, constrains connected limb lengths and keeps original props' rotations
and authored visibility. Source-pinned exceptions require matching geometry hashes.
Rebuilding checks existing master/material identities and preserves gameplay IQMs
and admitted textures; it stops publication if the implementation changes during
the run. Every rebuilt cinematic receives four matching skin files.

The optional `neural_cinematic_rebuild.py --human-motion` pass also regenerates
gameplay and extra multiplayer motion on the exact admitted bind rigs. The default
cinematic-only pass retains gameplay IQMs. `neural_human_motion.py` composes those
character outputs with refreshed Cryotech, Mishima Guard, Fatworker, Skinnyworker
and Surgeon loops; normal `neural_monsters.py package` applies the same human
motion policy. It normalizes authoring coordinates without changing vertices,
weights or binds. Appended 30 Hz loops retain original authority ranges/events.
Native qualification lives in separate run receipts. The embedded candidate
receipt records its status before scenario qualification; changing that embedded
receipt would create another archive identity.

```sh
OPENBLAS_NUM_THREADS=1 zig-out/neural-tools/runtime/bin/python -B \
  dkq3/tools/neural_cinematic_rebuild.py --workers 2
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py package \
  --characters zig-out/neural-monsters/episode1/dk3-neural-characters.pk3
OPENBLAS_NUM_THREADS=1 zig-out/neural-tools/runtime/bin/python -B \
  dkq3/tools/neural_cinematic_review.py \
  --packages zig-out/neural-monsters/episode1/dk3-neural-characters.pk3 \
  --out zig-out/reports/runtime-zig-330/all-cinematic-review
python3 -m http.server 8833 --bind 127.0.0.1 \
  --directory zig-out/reports/runtime-zig-330/all-cinematic-review
```

The viewer provides clip/frame selection, playback, orbit and zoom, with original
and serialized replacement geometry at the same scale. Numeric angular-step triage
excludes clip boundaries. Its clock is diagnostic; native interpolation, timing,
facial performance and whole-scene completion require separate acceptance. The
current review inspects 300 samples across all 102 models, retaining unresolved
cloth, rolled/death and prop defects in the acceptance matrix.

Combined packages use classic ZIP32 with unsigned offsets below 4 GiB. Python's
default switches to ZIP64 at 2 GiB, which the bundled reader cannot consume.
`neural_package.classic_archive` uses the actual ZIP32 bound and forbids ZIP64;
validation rejects ZIP64 directories, extra fields and local headers before
installation. A package above the format bound requires partitioning. The repaired
sequence-330 archive preserves every reviewed model/texture payload byte.

Other creatures use source vertex trajectories clustered into motion regions,
a parent-first hierarchy and fitted authored frames. Their upright yaw search
uses area-sampled original surfaces; GLB orientation alone proved unreliable for
Crox. Original frame numbers, intervals, class timing and hardpoint translations
remain intact; cosmetic skinning does not reschedule gameplay events.
Protopod uses a fixed base and four independently hinged rigid shell panels.
Panel boundary vertices are split before skinning so its original hatch interval
opens the egg without stretching it into a flat disk. The native mosquito spawn
remains a separate actor and original gameplay event. A reviewed `alignment.json`
can record an additional yaw correction, such as Sludgeminion's front/back
ambiguity; it is an admitted conversion input rather than a source-asset edit.

Venomvermin uses a measured, connected 16-joint quadruped instead of independently
fitted motion clusters. Local capsule weights connect its carapace and four limbs;
new diagonal walk/run cycles, strikes, reactions and collapse poses retain every
source sequence and event interval. Segment lengths stay fixed. Grounded forward
kinematics approximates paw contact; it does not provide independent four-paw IK.
The conversion receipt records semantic landmarks and their `creature_00`–`15`
physics labels. Its all-frame 99th-percentile edge stretch drops from 10.27 to 1.92.

`conversion.json` records frame counts, joint counts and residual errors by clip.
Anatomical performances report independently authored motion rather than a
misleading source-fit residual. Extreme poses, single-image reconstruction and merged cloth/armor geometry can
require refinement. Current runtime materials consume the base-color atlas;
the retained GLB also contains the generated PBR material data.
Pose previews frame each generated/original pair at a shared scale and position,
including jumping creatures. Their IQM positions and actual serialized normals
are rendered together; preview camera changes do not alter animation data.

```sh
OPENBLAS_NUM_THREADS=1 zig-out/neural-tools/runtime/bin/python -B \
  dkq3/tools/neural_monster_preview.py \
  --actor zig-out/neural-monsters/episode1/mishimaguard
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py status
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py package
```

Previews render the bind pose, reference pose and available idle, run, walk, attack, hatch
and death samples from the **serialized IQM**, including its actual skinned normals.
The studio renderer does not substitute recalculated smooth normals. They are visual diagnostics;
passing stage receipts alone are not visual or gameplay acceptance.
Each sample also renders the same original animation frame. Run
`neural_monster_gallery.py` to update the standalone `review.html` comparison.
`neural_monster_audit.py` checks serialized structure, original hardpoints and
source event/frame counts, finite skinning across every frame, and fixed
anatomical bone lengths. It records motion bounds and mesh-edge stretch for
review in `quality-audit.json`; these numerical checks do not establish visual
animation quality by themselves.

Generated masters receive a final lighting repair after any registered face
bake. `neural_surface.py` calculates area-weighted head normals across coincident UV
boundaries, then makes their tangents orthogonal. It preserves sculpt creases;
broad spatial smoothing produced incorrect shading on folded surfaces. Missing
normal vectors anywhere on a generated body are reconstructed from incident
faces; an unresolvable degenerate vector rejects conversion. It changes only
the two lighting arrays; positions, UVs, textures, weights, joints and encoded
animation frames remain byte-identical. Each `surface-normals.json` records the
input/output IQM hashes, changed byte ranges and preserved input file. Exact
lighting-only upgrades retain a completed conversion when every other input and
product still matches. Registered face provenance refers to the mesh before this
lighting pass. `face-lit-review/` separately records the current serialized head
under studio lighting; the original projection captures remain intact.

The close-up repair pass adds a closed-surface stage for the 19 human characters
and monsters with reviewed faces. Both chained prisoners remain protected. Thin
mechanical wings and the separately articulated pod panels keep their qualified
surface path. `face-quality-preview` prepares separate candidates, using the
untouched pre-face atlas and the existing serialized rig:

```sh
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py face-quality-preview \
  --models hiro mikiko superfly mishimaguard \
  --candidate zig-out/neural-monsters/face-candidates
```

Each candidate has actual albedo, lit, and gray clay views from the front and
both sides. Inspect the clay eyelid slots before generating paint. Use the built-in
image tool to restore diffuse skin detail against these exact references; preserve
the camera, head direction, clothing, and modeled hair. Generate independent side
images where hair or a hood hides the cheek. A frontal image must never be mirrored
onto an asymmetric hairstyle.

`face-plan-quality.json` pairs measured target-mesh UV landmarks with their positions
in each generated image. Coordinates use bottom-left image UVs; convert a top-left
pixel `(x,y)` to `(x/width,1-y/height)`. The inverse thin-plate mapping moves painted
eyes into actual sockets, and is bounded away from the face to preserve the canvas.
The baker checks the mapped 201-square coordinate grid and rejects a nonpositive
Jacobian, which signals a folded or collapsed registration. Keep glasses edges,
ears, jaws and clothing boundaries registered against the actual camera references.
Each `projections` entry contains a sibling PNG path, SHA-256, view angle (0, -60,
or +60 degrees), and registration anchors. Keep the actual reference hashes and
candidate geometry digest. Review the resulting `body-quality.png` on the mesh,
including both profiles; checking the generated painting alone is insufficient.

```sh
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py face-quality \
  --model hiro --candidate zig-out/neural-monsters/face-candidates/hiro
```

Admission records `surface-quality.json`, preserves the previous art inputs, and
rebuilds the candidate through the normal conversion pipeline. It does not substitute
a candidate IQM for conversion. The fine shell/voxel repair uses 0.14/0.1 normalized
units, a 36,000-triangle runtime budget, and a fresh atlas produced by the already
pinned `xatlas==0.0.11` tooling. Head and body are separate parameterization inputs;
scaling the head input by 2.5 increases its texture density without changing runtime
geometry. Eight-pixel chart padding leaves room for four-pixel bake expansion and
filtering. Positive-area triangle overlap and collapsed UV faces reject admission
and production conversion, including overlaps within one chart. The helper verifies
that vertex remapping preserves the exact triangle order and winding, and records
the atlas settings, producer version, input/output hashes and retained MIT notice.
Folded sliver faces receive independent charts and are repacked at the same density;
the overlap test runs again on the resulting atlas before Blender bakes its albedo.
See the [xatlas producer](https://github.com/jpcy/xatlas) and
[Python binding API](https://github.com/mworchel/xatlas-python).
Albedo is ray-baked from the original surface; existing skin influences are transferred
locally. Detached components smaller than two voxel widths are removed as remeshing
debris; connected skin is retained. Conversion rejects open/nonmanifold/degenerate topology or changes to skeleton,
attachment names, bind channels, and animation frame channels. `surface-closure.json`
records the exact input/output identities and preservation measurements.

Registered face baking renders 2048-square first-surface depth maps for each actual
camera, then checks visibility per atlas texel and blends independent views by
incidence. Scalar depth lives in the float EXR alpha channel to bypass color-space
and white-point transformations; the RGB channels do not encode qualified depth.
The measured frontal image takes priority within the registered eye sockets.
This override requires named eye anchors and is limited to the front of the head;
glasses-only portraits do not receive an invented eye region. A camera contributes
no weight where the serialized surface normal faces away from it, outside the
named anterior orbital override.
Side views cover the cheek and neck. Include ears and the full neck in the admitted
head bounds; a narrow frontal face box leaves old reconstruction patches at the sides.
The bake normalizes view weights per texel and keys the actual gray backdrop sampled
from each image's upper corners, with a smooth color-distance fade. It preserves gray
beard, cloth and bone detail rather than classifying all gray as background,
and leaves unseen surfaces on their original albedo. New islands allow four pixels of
padding; historical tightly packed atlases use none. The original atlas bytes remain
exact outside nonzero repair coverage. All side images, registration code, closure
settings, and source references participate in conversion and package validation.
Where edited portraits move a bob haircut across the cheek, measured hair-boundary
anchors and optional `protect_dark_hair: true` retain its dark surface outside the
eye region. Side views cannot repaint those hair texels as skin; visible frontal hair
detail can still transfer. Inspect the resulting hair and face together.
Geometry, art, motion, and native acceptance still need review after admission.

For CPU conversion/previews alongside an already running producer, invoke
`neural_monsters_watch.py --producer-pid PID --preview-workers 3` with the isolated
Python. It prioritizes character conversions, renders independent previews on
three CPU workers, reloads worker scripts for each actor, and drains receipts
published while conversion was running before stopping after producer exit.

The package builds selected character variants from the new masters and adds the
complete episode. After a monster-only repair, reuse the already rebuilt character
variants with:

```sh
zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_monsters.py package \
  --characters zig-out/neural-monsters/episode1/dk3-neural-characters.pk3
```

When character masters are present, reuse requires the exact current master roster,
IQM and atlas hashes, conversion metadata and face provenance. Without this option,
the variants are rebuilt from the current masters. A monster-only roster can also
merge an existing character overlay. Admission checks its closed cosmetic namespace, source
generation, mappings, physics skeletons and every file hash. Stale inputs or an
unfinished class prevent publication. The validated archive atomically replaces
only `zig-out/neural-monsters/episode1/dk3-neural-episode.pk3`.
The overlay includes all four existing native skin/render variants per monster.
Atlas export explicitly encodes PNG pixels; a packed WebP buffer with a renamed
suffix is rejected during conversion and package admission.

Additional story identities are Casseti, Charon/Ferryman, the female guard,
Garroth, the warrior guard, Ninja, Osaka, the priest, Tatsuo and Toshiro. Shared
identities retain their original cinematic aliases. The ledger, character manifest
and final package report record the exact admitted source and target paths.

For an existing completed prisoner conversion, `preserve --models prisoner prisonerb`
verifies and records its source/concept lineage and exact IQM/atlas hashes. Subsequent
stage commands retain these frozen products; packaging validates them explicitly.
This is an owner-requested exception, not a claim that prisoners were regenerated.

Sludgeminion and Ragemaster use measured mechanical shoulder, elbow and distal
claw pivots. Their armor triangles follow individual rigid segments, with split
vertices at articulation boundaries. This keeps long panels from stretching
between a moving forearm and a stationary shin. They share the fixed-length biped
leg motion, hardpoints and native humanoid physics, with independently authored
heavy arm swings and strikes measured from their own bind chains. Mechanical claws follow their
hand segment and boots follow their foot segment.

## Native physics and isolated gameplay verification

`dk3/neural-physics.cfg` opts generated creature skeletons into the native client
solver. Anatomical bipeds use the existing humanoid solver; Laser/Rockgat turrets
and Protopod use anchored roots; other creatures use free articulated bodies.
At ordinary death, the solver starts from the last
visible pose and velocity. It runs at 120 Hz with parent-length constraints,
approximate bend limits, self separation, swept world/brush contacts, friction
and sleep. Attachment bones follow their parent and are not extra particles.
Live matrices use the existing renderer path; `cg_ragdolls 0` restores authored
death presentation. Original gib/hatch behavior and server health remain authoritative.

The generic creature solver uses motion-region pivots; anatomical bipeds retain
the character hinge/length and mesh stability approach.
Collision boxes and self separation approximate a skinned mesh. Exact cloth,
triangle collision, body-to-body interaction and saved physical poses are outside
this cosmetic conversion. Keep implemented/unverified results separate from
actual scenario evidence.

Install into a separate development prefix:

```sh
zig build play-install --prefix zig-out/neural-monsters-dev -j8 \
  -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe \
  -Dneural-assets="$PWD/zig-out/neural-monsters/episode1/dk3-neural-episode.pk3"
```

Run engine diagnostics through that installation's `dkguard --headless`, without
`--gpu`, using isolated profiles and fresh report directories. Check all 22 model
loads, skeletal motion, rebuilt character variants, native deaths/contacts and the pod's separately spawned
mosquito. Preserve screenshots and inputs for failed cases, repair them and replay
the affected scenarios. A focused actor fixture does not establish complete
episode or hardware-renderer acceptance.

## Current run evidence

The pipeline has finished all 37 entries: 35 newly reconstructed masters and two
byte-identical protected prisoners. The published package contains 132 IQM variants:
110 character performances/appearances and all 22 episode-one monsters. All-frame
structural audit covers 37 masters and 11,458 frames; the gallery records 217 sampled
poses, 20 registered face/eye edits and 19 separately lit face reviews. A repeated
conversion command retains all 37 completed entries without regeneration.

Sequence 329 closes and repaints the 19 exposed character/monster faces. Measured
registration covers 41 front/side images with no sampled folds; candidate meshes
and atlases exactly reproduce in production while skeleton/bind/frame channels
remain unchanged. Ten independent side portraits and exact built-in imagegen
prompts are saved under
`zig-out/reports/runtime-zig-328/texture-quality-review/closed/` and indexed by
`continuation-side-artwork.json`. The shared bounded baker also refreshes Psyclaw's
atlas without changing its IQM, retaining source texels outside face coverage.

Local output: `zig-out/neural-monsters/episode1/review.html`, `quality-audit.json`,
`pipeline.json` and `dk3-neural-episode.pk3`. The final package SHA-256 is
`a3cce6c208de4e7977798ba2efd7959076ede55a48eb7990b2ff36466fde3ff1`.
The isolated installation is selected by `zig-out/neural-monsters-dev/play/current`.
At the owner's request, `zig-out/native-dev/play/current` now selects the identical
25-file installation, and the normal `dk3` command launches it through dkguard.
The local default package selector uses this episode package for `zig build play`.
Prior immutable installations and the preserved game/online selectors remain
available; all 120 snapshotted save/settings files remain exact. Previous package
and launcher bytes are retained. Promotion evidence is
`zig-out/reports/runtime-zig-328/texture-user-install.json`; owner hardware testing
is pending. Current protection and package
receipts are `zig-out/reports/runtime-zig-328/texture-prisoner-protection.json`
and `texture-package-diff.json`: both prisoners remain exact, 18 runtime IQMs
remain unchanged, and model/physics mappings match the sequence 328 package.
Executable, module, renderer and base-content hashes also match that preceding
qualified installation. The earlier quadruped/package receipts describe its history.

Eleven affected scenario groups pass on the new installation: all 22 monster
loads; guard articulated death/restoration and default gibs; five UDP character
appearances with gait, moving attacks, complete deaths, respawn and settling;
held sword/rifle/pistol; carry; companion death/restoration; intro motion/face
views through shot 35; and all 13 Superfly encounter shots with active/completed
restoration. Guard and UDP character checks include both software renderers.
All runs use dkguard and isolated profiles. Passing captures use 960×540,
with two GL2 workers or eight GL1 workers; the GL1 guard uses e1m1a.
The single broad aggregate passes 52 steps, 442 Zig tests, 130 Python tests and
C contracts. Earlier pod, Crox, robot and Venomvermin results retain their exact
relevant assets and runtime inputs.

Exact scenario receipts, native captures, installation identity, retained failed
setups and limits are in [native acceptance, sequence 329](native-acceptance.md)
and `zig-out/reports/runtime-zig-328/texture-final-evidence.json`. The current native
image gallery is `zig-out/reports/runtime-zig-328/texture-native-review.html`.
The HD software intro and heavier e1m3b GL1 guard profiles overflow reliable
commands; one drop-cleanup failure also reports `StaleEntity`. These failed inputs
and logs remain recorded. `--face-size WIDTH HEIGHT` selects intro face-capture
dimensions; the monster/network probes also expose `--capture-size WIDTH HEIGHT`
for explicit diagnostic profiles. These options retain the full model and atlas
inputs.

Full campaign, every cinematic performance, hardware rendering, higher-load
software behavior and drop cleanup remain unverified. Body collision remains
approximate; a wall/stair-adjacent Mishima fixture did not settle within 8.4 seconds,
while the isolated equal-spawn fixtures settle all five characters.
