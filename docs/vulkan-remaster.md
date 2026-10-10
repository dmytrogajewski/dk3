# Vulkan remaster renderer

Status: milestone 1 (`renderer_vulkan.so`, sequences 347-357) and the remaster
roadmap after it (sequences 358-373) are implemented. The owner directed the
remaster roadmap to completion; it remains outside the V-gates in
[rewrite-roadmap.md](rewrite-roadmap.md). Implemented, unverified and verified
states are tracked in [native-acceptance.md](native-acceptance.md), never here.

## Decision

dk3 gets its own hybrid Vulkan renderer, written in Zig 0.16 and shipped as a third
swappable renderer module beside OpenGL1 and OpenGL2:

- `renderer_vulkan.so` is the default `cl_renderer` (owner decision during milestone 1).
  When the module is missing or `GetRefAPI` refuses the machine, the client loads
  OpenGL2 for the session. OpenGL1/OpenGL2 remain selectable.
- Native resolution: the window is high-DPI aware and `r_mode -2` renders at the
  drawable's physical size; fullscreen is borderless at desktop size.
- Baseline is Vulkan 1.3. Ray tracing (`VK_KHR_acceleration_structure` +
  `VK_KHR_ray_query`) is optional and detected at run time; every RT feature has a
  raster answer, so non-RT GPUs and lavapipe stay supported.
- Native code, not an imported renderer. Q2RTX, RayTracedGL1 and Quake3e are
  reviewed as references only (see Licensing).

Rejected alternatives:

| Option | Why not |
| --- | --- |
| Wrap RayTracedGL1 (MIT) behind refexport | Fastest to RT visuals but RT-only, no raster tier, an external renderer the tree does not own, and its scene model (static sectors, one spotlight) does not fit resident worlds |
| Port Quake3e `renderervk` (GPL-2) | A Vulkan copy of the classic Q3 pipeline; PBR/RT would be a rewrite anyway and the dk3 world/bone/lightstyle extensions would need re-porting |
| NVIDIA RTX Remix | Hooks D3D8/9 only; OpenGL support never shipped, and it would replace authored behaviour with an opaque runtime |

## Remaster implementation

`r_vkRemaster 1` (the default, latched) renders world views into a linear HDR
target. Menus and HUD stay on the classic OpenGL1-exact path in a premultiplied
overlay, which `composite.frag` lays over the tone-mapped image.

| Area | Implementation (`src/renderer_vulkan/`) | Main cvars |
| --- | --- | --- |
| HDR and post | Float linear lightmaps; histogram auto exposure (`post.zig`); 7-level bloom; AgX view transform with saturation; display gamma | `r_vkExposure`, `r_vkAutoExposure`, `r_vkBloom`, `r_vkSaturation` |
| PBR materials | GGX world and model shading. Normal maps (`<name>_n`), specular maps (`<name>_s`) or a procedural bump from albedo luminance. Light-grid direction volume steers bump and specular response | `r_vkBump`, `r_vkSpecular` |
| Material sidecars | `dkq3/tools/materialgen.py` writes `textures/<name>.mat` (roughness, metalness, bump, emissive, specular, liquid) plus `_n.png` normal maps from the image, name and shader scripts. `play-install` adds `zig-out/materials/dk3-materials.pk3` as the cosmetic `zz-dk3-materials.pk3`. OpenGL renderers never read it | — |
| Water | Liquids from brush contents. One-pass shading: Gerstner-style normals, refraction from a scene copy, Beer-Lambert absorption from depth, screen-space or ray-traced reflection, foam, emissive lava. The underwater composite uses the eye's brush contents | — |
| Volumetrics | `volume.zig`: 128x72x64 froxel grid. Inject: authored worldspawn fog, a thin base atmosphere lit by a light-grid colour volume, dynamic lights with Henyey-Greenstein phase. Integrate: front to back. Stage shaders apply it per fragment, blend aware, in place of linear fog | `r_vkVolumetric`, `r_vkFogDensity`, `r_vkFogScatter` |
| Anti-aliasing and scale | `taa.zig`: Halton jitter, depth reprojection, YCoCg variance clipping, Catmull-Rom history; upsamples from `r_vkRenderScale`; contrast-adaptive sharpening in the composite | `r_vkTAA`, `r_vkRenderScale` (latched), `r_vkSharpen` |
| Weather | `weather.zig`: the client hands each authored volume to `AddDk3WeatherToScene` (`CG_DK3_R_WEATHER_V1`, 716). The stage vertex shader derives drops, flakes and splash rings from the particle index in world-anchored tiles. OpenGL renderers decline the call and keep CPU particles. Surfaces under rain get wetness, puddles and ripples; under snow, upward faces get cover | `r_vkWeather`, `r_vkWeatherDensity`, `r_vkWeatherSplashes`, `r_vkWetness`, `r_vkSnowCover` |
| Lights | `clusters.zig`: compute binning into 16x9x24 clusters lifts the remaster dynamic-light limit to 256 | `r_dynamiclight` |
| Model shadows | `shadows.zig`: up to 24 nearest models each get a 256² depth tile along their light-grid direction; world materials darken baked light with PCF and a contact fade. Includes the player's third-person body. Replaces GL stencil volumes, which cannot follow GPU-skinned IQM | `cg_shadows`, `r_vkModelShadows` |
| Ray tracing tier | `rt.zig`: with `VK_KHR_acceleration_structure` and `VK_KHR_ray_query`, each resident world gets BLASes for its static opaque geometry and inline brush models, and a TLAS is rebuilt per frame with moving brush models. Ray queries give dynamic-light shadows and reflections on liquids and smooth or wet materials (`rt_common.glsl` hit shading: albedo x lightmap) | `r_vkRayTracing` (latched), `r_vkRtShadows`, `r_vkRtReflections` |
| DDGI | `ddgi.zig`: a 32x32x16 probe field, 96 units apart, scrolls with the eye (toroidal history). It traces 64 rays per probe for a rotating share each frame and stores L1 SH irradiance; grid-lit models take their ambient from it | `r_vkDdgi`, `r_vkDdgiProbes` |
| Directional lightmaps | `bake.zig`: once a world's structures exist, each lightmap page is rasterised in lightmap space and traces shadow rays to the map's `light` entities, giving deluxe pages (direction, directionality) that supersede the light-grid direction for bump response | `r_vkDirectionalBake`, `r_vkBakePages` |
| Path tracing mode | `pathtrace.zig`: primary rays through the jittered pixel. Direct light from map light entities uses RIS over a 256-unit light grid with one shadow ray, plus shadowed dynamic lights and one bounce that reads lightmap radiance at its hit. SVGF-style temporal accumulation and three à-trous iterations follow; the result replaces the opaque world where traced and raster depth agree. Off by default | `r_vkPathTracing`, `r_vkPtLightScale` |
| Debug | Path-traced lighting or mask, deluxe pages, world irradiance | `r_vkDebugView` |

The ray tracing tier is detected at device creation and used when present (lavapipe
also offers it, so the tier runs headless). Without it, the stage shaders compile
without ray queries and the DDGI, bake and path-tracing passes stay off.

## Starting state (before milestone 1)

Renderer stack:

- Only `renderer_opengl1.so` and `renderer_opengl2.so` exist
  ([build/ioq3.zig](../build/ioq3.zig)). Both are dlopened by `CL_InitRef`
  (`engine/ioquake3/code/client/cl_main.c:3294`) and own the SDL window
  (`sdl/sdl_glimp.c:409`, GL-only). No Vulkan code exists; the host SDL supports
  Vulkan surfaces.
- The interface is refexport v13 (`renderercommon/tr_public.h:27`): stock Q3 plus
  `SetDk3Fog` and the resident-world calls, `refEntity_t` bone matrices and world
  tags (`tr_types.h:120-126`), and `refdef_t.dk3Lightstyles` (`tr_types.h:142`).
- The Zig client reaches the renderer only through cgame syscalls
  (`src/runtime/engine/abi.zig`, `cl_cgame.c:651-711`). New renderer inputs follow
  one pattern: `CG_DK3_<NAME>_V1` (716+) in `cg_public.h`, a case in `cl_cgame.c`, a
  `refexport_t` member implemented by every renderer, or a new `refdef_t` field.

What GL2 already has but nothing feeds
([realrtcw-renderer-review.md](realrtcw-renderer-review.md)):

- HDR, tonemapping and auto exposure (on), SSAO, PBR, cubemaps, sun shadows and
  rays (off or idle). Converted maps carry no sun keys, probes, normal or specular
  maps (`dkq3/tools/shadergen.py`), so they have no inputs.

Gaps found in this investigation:

- **Fog is not drawn.** The renderers implement `SetDk3Fog`, but its only caller
  was the removed C cgame. No Zig code sends `CG_DK3_R_FOG_V1` (702), and
  `ClearScene` clears fog every frame (`renderergl1/tr_scene.c:77`).
- **Water has no material identity.** `shadergen.py:98-149` turns WARP into
  `tcMod turb`, FLOWING into `tcMod scroll` and SURGE into `deformVertexes wave`;
  the liquid kind exists only in the collision shaders
  `textures/dkq3/contents_%08x` (`dk2q3.py:43,66-78`). A renderer cannot tell
  water from lava or slime.
- **No underwater view.** The client knows the eye's water level (`client.zig:641`)
  but only passes it to sound.
- **Weather is CPU particles.** `src/runtime/client/weather.zig` culls brush volumes
  and sends one poly per drop (`fx_particles.zig:84`). Rain is in episodes 1 and 4,
  snow in episode 3, none in episode 2.

Lighting data:

- Lightmaps are Daikatana's own radiosity, style 0 baked, 128² pages, plus a light
  grid and the `DKLS` lightstyle trailer (`dkq3/tools/dk2q3.py:311-407`,
  `lightmap.py`). No deluxemaps.
- `light*` entities are preserved verbatim (e1m1a has 41), so a re-bake or a
  path tracer has the authored light list.

## Vulkan feature map

| Tier | Features | Use |
| --- | --- | --- |
| Baseline (1.3 core) | dynamic rendering, synchronization2, descriptor indexing, buffer device address, timeline semaphores | No render-pass objects; one bindless texture array; vertex pulling through device addresses; one timeline for frame pacing |
| Optional | `VK_EXT_shader_object` or graphics pipeline library | Q3 stage state (blend × depth × cull × alpha test) without pipeline explosion |
| Optional | `VK_KHR_fragment_shading_rate` (Roadmap 2026 requirement) | Coarse shading for volumetrics, water refraction and particles |
| Optional | async compute queue | GPU particles, froxel fog, denoisers overlapping raster |
| Optional | host image copy (Roadmap 2026), `shaderFloat16`, subgroup ops | Texture streaming for resident worlds; cheaper post passes |
| RT | `VK_KHR_acceleration_structure` + `VK_KHR_ray_query` | Shadows, reflections, AO and GI from raster shaders |
| RT (path tracing only) | `VK_KHR_ray_tracing_pipeline` | Full path-tracing mode |
| Later | `VK_EXT_descriptor_heap` | Still EXT in 2026; revisit once promoted to KHR |

In use: the baseline, plus the RT tier's acceleration structures and ray queries.
Ray queries also drive the path tracer, from compute shaders. Not used yet: shader
objects or graphics pipeline libraries (the pipeline cache stays small), fragment
shading rate, a separate async compute queue, host image copy and the ray tracing
pipeline extension.

Milestone 1 already shapes data for RT: world vertices and indices live in static
device-addressable buffers that are never rewritten (deforms run in the vertex
shader), and each resident world owns its allocations, so each can get its own BLAS.

## Lighting

1. **Keep the authored radiosity as ground truth.** Bicubic lightmap sampling; an
   L2 spherical-harmonic probe grid built from the light grid for moving models.
2. **Clustered forward+ lights.** Compute light culling replaces GL dlights. Every
   existing Zig `AddLightToScene` caller benefits without change.
3. **Shadows.** Cascaded shadow maps for authored suns; cached cube shadows for
   `light*` entities near the camera.
4. **Directional re-bake.** A Python baker re-lights from `light*` entities and
   Daikatana surface lights into directional lightmaps and the probe grid, so normal
   maps get a light direction. It *replaces* the radiosity data instead of adding to
   it, avoiding the double counting that rejected SSGI.
5. **RT tier.** Ray-query shadows for dynamic lights, RT reflections, RT AO, and
   dynamic diffuse GI through DDGI-style ray-updated probes.
6. **Path-tracing mode.** ReSTIR DI/GI over `light*` entities and emissive surfaces,
   an in-house A-SVGF-style denoiser and temporal upscaling. Daikatana is Quake 2
   derived, so Q2RTX's BSP-to-path-tracer mapping (surface lights, sky portals,
   materials table) is the closest reference.

### Ray traced light sources (implemented; sequence 376)

Ray traced lighting (`r_vkLighting 1`) lights the map from every source the original
radiosity used, each with the model measured against the shipped lightmaps:

| Source | Data | Model |
|---|---|---|
| `light*` entities | origin, `light` (300 when missing), `_color` (normalised to its brightest channel), `cap`, `style` | linear: (light − distance) × cosine, at most `cap` |
| Emitting faces | texinfo SURF_LIGHT `value` and the per-texinfo `extsurfinfo` colour (0 0 0 = the texture's colour), from `maps/<map>.lights` | area light: value × 0.4 × area × cos × cos′ / (d² + area/π); the face itself shows its own light (up to the radiosity's 196) |
| Sky | the emitting sky faces' area-weighted value and colour | value × 0.6 × the pixel's visible sky, summed with the direct light in radiosity units |
| Sun | worldspawn `_sun_light`, `_sun_angle`, `_sun_color`, `_sun_diffuse` | parallel light with a traced shadow; `_sun_diffuse` adds to the sky |
| Styles | the frame's `dk3Lightstyles` | per-light multiplier in the light buffer header; switched lights (styles ≥ 32, START_OFF) follow it |

Measured, not assumed:
- `cap` limits a light's own contribution: a light 300 cap 70 plateaus at 75.
- Targets and cone keys do not narrow lights: e1m4a's crematorium sign sits 50 degrees off its
  lights' targets and is fully lit.
- Per unit of visible sky (the same cosine-weighted traced fraction the shader uses), ground holds
  0.59–0.93 × the sky value including bounce (e2m2a, e2m1a, e3m1a).

`dkq3/tools/surface_lights.py` writes the sidecars into the remaster materials package
(`materialgen.py --data` does too). The converted maps stay byte-identical, so save checksums
hold. Faces that emit into a liquid are left out: probe rays pass through liquids and would
carry a lake bed's light into the air. Light cells keep the lights with the most light inside
them and drop lights whose cluster cannot see the cell (the map's PVS).

A visibility cache (`light_visibility.comp`) measures each cell's listed lights: 32 rays from the
cell to the light, refreshing 512 cells per frame, so opened doors are picked up. Lights no ray
reached are skipped; the rest are weighted by how often they were seen. The four strongest lights
get exact shadow rays; the rest get two importance-sampled rays, which temporal anti-aliasing
averages.

Shading normals of world and model surfaces are turned toward the viewer before lighting:
under the flipped viewport, `gl_FrontFacing` is false on ordinary visible faces, and flipping
on it inverted them. Probe bounce and visible sky join the direct light in radiosity units
before the single conversion, as the lightmaps summed them. See
docs/vulkan-rt-lighting-postmortem.md. Probes, the path tracer and the per-pixel term all take the same
data-driven sky. Without the sidecars, the previous emissive-material guess and skybox
calibration remain.

## Materials and water

- **Material sidecars.** A new `dkq3/tools/materialgen.py` writes per-texture JSON
  (roughness, metalness, emissive, normal, liquid kind). Sidecars keep unknown
  keywords out of the shader scripts the GL renderers parse.
- **Liquid tagging.** `shadergen.py` joins WARP faces with their collision contents
  so each liquid face carries water, slime or lava.
- **Inputs.** Normal and roughness from the HD overlay through the existing
  `neural_textures.py` / `craft_textures.py`; renderergl2 already reads `_n`/`_s`.
- **Water.** Screen-space refraction from a scene colour copy; reflections
  (screen-space, RT when available); Beer-Lambert depth absorption; shoreline foam
  from scene depth; flow and Gerstner normal maps; projected caustics.
- **Underwater.** A post pass for tint, fog and distortion, driven by a new
  `CG_DK3_R_ENVIRONMENT_V1` carrying the eye's liquid kind and the authored fog.
- **Lava** emissive with heat haze; **slime** with tinted subsurface absorption.

## Weather and atmosphere

- **Restore fog first.** The Zig client sends `CG_DK3_R_FOG_V1` after each
  `CLEARSCENE`; this also fixes OpenGL1/OpenGL2.
- **Volumetric fog.** Froxel scattering with lights and sun shafts, driven by the
  authored fog values.
- **GPU weather.** Compute-simulated rain and snow with depth-buffer collision and
  splashes, replacing per-drop polys. A new `CG_DK3_R_WEATHER_V1` passes kind, rate,
  wind and volume boxes from `src/runtime/domain/weather.zig`; gameplay rules stay
  in Zig.
- **Wet surfaces.** A top-down rain occlusion map drives puddles (lower roughness,
  darker albedo), ripple normals and drips; snow accumulates on upward faces.
- **Lightning.** A directional flash light synchronised with the existing sky flash.

## Image quality

- TAA, then FSR 3.1 temporal upscaling (MIT, bundleable).
- Bloom, auto exposure, AgX or ACES tonemapping, GTAO, cinematic motion blur and
  depth of field, HDR10 swapchain output where offered.

## Licensing

The tree is GPL-2.0-or-later. Every admitted component is reviewed.

| Source | Licence | Use |
| --- | --- | --- |
| Q2RTX | GPL-2.0 | Reference for BSP path tracing; any adapted code keeps notices |
| RayTracedGL1 | MIT | Reference for ReSTIR/A-SVGF; adaptable with notice |
| Quake3e `renderervk` | GPL-2.0 | Reference for Q3 stage state on Vulkan |
| AMD FSR 3.1 (FidelityFX SDK) | MIT | Candidate bundled upscaler |
| AMD FSR 4 | binaries only officially | Not admitted |
| NVIDIA DLSS, Intel XeSS, NVIDIA NRD | proprietary SDK terms | Not bundled; at most an optional, user-supplied runtime plugin |
| GPL-3.0 code (e.g. RealRTCW SSGI) | incompatible | Excluded |

## Roadmap

Milestone 1 brings `renderer_vulkan.so` to basic OpenGL2 parity. Its sequences are
recorded in [native-acceptance.md](native-acceptance.md):

| Sequence | Topic slug |
| --- | --- |
| 347 | `vulkan-renderer-build` |
| 348 | `vulkan-renderer-boot` |
| 349 | `vulkan-renderer-images-2d` |
| 350 | `vulkan-renderer-materials` |
| 351 | `vulkan-renderer-world` |
| 352 | `vulkan-renderer-resident-worlds` |
| 353 | `vulkan-renderer-lightstyles-fog` (also restores the native fog call) |
| 354 | `vulkan-renderer-models` |
| 355 | `vulkan-renderer-effects` |
| 356 | `vulkan-renderer-capture` |
| 357 | `vulkan-renderer-acceptance` |

After milestone 1, implemented in this order:

| Sequence | Topic slug |
| --- | --- |
| 358 | `vulkan-renderer-hdr-pbr-core` |
| 359 | `native-runtime-environment` (underwater from brush contents inside the renderer; no new client call was needed) |
| 360 | `vulkan-renderer-water` |
| 361 | `vulkan-renderer-volumetrics` |
| 362 | `vulkan-renderer-taa-fsr` (TAA and an in-house temporal upscaler; FSR 3.1 not bundled yet) |
| 363 | `vulkan-renderer-weather-gpu` |
| 364 | `vulkan-renderer-clustered-lights-shadows` |
| 365 | `material-sidecars` |
| 366 | `vulkan-renderer-rt-shadows-reflections` |
| 367 | `vulkan-renderer-ddgi` |
| 368 | `lightmap-rebake-directional` (GPU bake at load from map lights, not an offline tool) |
| 369 | `vulkan-renderer-path-tracing` |
| 370 | `vulkan-renderer-m1-gaps` (beam, rail and lightning entities; model shadows; material scan) |
| 371 | `vulkan-renderer-rain-occlusion` (top-down rain occlusion map for particles and wet surfaces; fixes from the owner's first in-game screenshots) |
| 372 | `vulkan-renderer-lighting-scale` (lightmaps normalised like the original with a little headroom, PBR Neutral default tonemap, fog remapped to the authored blend, TAA model mask) |
| 373 | `vulkan-renderer-rain-realism` (physical drop sizes, speeds and streak lengths, per-drop lighting with back-lit glints, distant rain as froxel fog, crown splashes, puddle-only ripples, TAA motion mark) |

## Verification approach

- Headless: `dkguard --headless` selects lavapipe for Vulkan and llvmpipe for GL, so
  every raster feature can be compared against OpenGL2 with
  `dkq3/tools/map_frame_audit.py` and per-view RMSE.
- Hardware: RT tiers verify only with `dkguard --gpu` on owner hardware.
- Brightness: OpenGL2 renders HDR with tonemapping; parity compares against an
  OpenGL2 `+set r_hdr 0 +set r_toneMap 0` reference with recorded tolerances.
