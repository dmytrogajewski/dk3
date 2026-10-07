# Slim gi body experiment — sequence 344

The sequence-341 costume was rejected for broad shoulders, ballooning trousers,
and broken arm/hand skinning. This experiment generated a new body-only concept
with a narrower gi and open hands. The head in the concept is deliberately
featureless; the approved Hiro face was never regenerated or replaced.

The [exact imagegen prompts](../dkq3/animation/dojo-hiro-slim-generation.txt)
and local inputs are retained. The opaque concept is
`zig-out/cinematic-body-344/hiro-gi-slim/concept.png` (SHA-256
`a92ecb3b45b6de5196bb787158dd77249f8632c8fe0b27751a175ecb187b19bf`).
The transparent authoring input is
`zig-out/cinematic-body-344/hiro-gi-slim-cutout/concept.png` (SHA-256
`9f80fb12c584947fdb4433074e43271cc13efe0367d7c6a44d1c46b288db31c5`).
The pinned local TRELLIS.2 pipeline produced a 5.8 MiB GLB (SHA-256
`a74b3645e4d3266491b663652b2c954286f1f41d72807e91c149c72dc7c9e5d7`).
The original body surface and UV atlas were not used as delivery geometry.
The local original capture metadata only supplied reference size and axes to
the existing conversion tool. None of these binaries are committed or installed.

The [front](../zig-out/cinematic-body-344/geometry-review-soft/front.png) and
[side](../zig-out/cinematic-body-344/geometry-review-soft/side.png) GLB renders
show substantially slimmer proportions and anatomically open hands. However,
the raw converted mesh has 12,009 boundary edges and 142 nonmanifold edges.
A single bounded voxel/SDF closure created a 99,752-triangle model with zero
boundary, nonmanifold, or degenerate edges. Its
[front](../zig-out/cinematic-body-344/closed-preview/front-00000.png) and
[side](../zig-out/cinematic-body-344/closed-preview/side-00000.png) previews
still have dark tears and stains at sleeves, head, trouser legs and boots.
The direct semantic [material bake](../zig-out/cinematic-body-344/closed-direct-preview/front-00000.png)
misclassified hands, belt and lapels. The source-transfer
[material bake](../zig-out/cinematic-body-344/source-transfer-preview/front-00000.png)
smears dark shading onto the lower trousers and skin. Neither passes visual
review. The candidate remains unrigged and unadmitted; no native preview or
cinematic package was produced from it.

Reproduction of the local geometry and inspection, after providing the pinned
concept PNG and the existing private TRELLIS source/weights:

```sh
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
  zig-out/neural-tools/runtime/bin/python -B dkq3/tools/neural_head_trellis.py \
  --source zig-out/neural-tools/sources/TRELLIS.2-75fbf0183001ed9876c8dbb35de6b68552ee08bd \
  --actor zig-out/cinematic-body-344/hiro-gi-slim-cutout --resolution 1536_cascade
blender --background --factory-startup --threads 4 --python-exit-code 1 \
  --python dkq3/tools/neural_monster_blender.py -- --stage convert \
  --actor zig-out/cinematic-body-344/hiro-gi-slim-cutout --triangles 100000 --preserve-topology
/usr/bin/python3 -B dkq3/tools/generated_character.py \
  dkq3/animation/dojo-hiro-slim-candidate.yaml \
  --actor zig-out/cinematic-body-344/hiro-gi-slim-cutout --prepare-geometry \
  --out zig-out/cinematic-body-344/closure-source
blender --background --factory-startup --threads 4 --python-exit-code 1 \
  --python dkq3/tools/neural_surface_close.py -- \
  --source zig-out/cinematic-body-344/closure-source \
  --out zig-out/cinematic-body-344/closed-slim \
  --texture zig-out/cinematic-body-344/closure-source/body.png \
  --voxel 0.07 --thickness 0.10 --seal-radius 0.18 \
  --triangles 100000 --partition-orientations
```

The next body strategy should preserve this narrower silhouette but author a
clean cloth/skin/boot material separation on the actual 3D surface before
atlas baking. Another unconstrained repaint of the damaged TRELLIS atlas is
unlikely to fix the UV mapping. Keep the exact approved face separate until a
clean body and neck opening can be attached and reviewed in Blender and native
captures.
