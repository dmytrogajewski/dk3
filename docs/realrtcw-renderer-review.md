# RealRTCW renderer reuse investigation

Status: source inspection of the local RealRTCW and dk3 workspaces; no renderer
changes, builds, gameplay runs, or performance measurements in this investigation.
Recommendations below are proposals, not accepted implementation scope or verified
visual improvements. Source links to RealRTCW require the sibling local checkout.

## Recommendation

Keep dk3's bundled ioquake3 engine and selectively adapt useful components. The
highest-value candidate is weather contact/splash handling in **client game code**.
Next consider explicit fog transitions and persistent, visibility-aware coronas.
RealRTCW's OpenGL1 bloom is optional enhancement material. Its local SSGI is an
experimental starting point with concrete integration defects, not a ready upgrade.

Most headline modern-renderer capabilities already exist in dk3's OpenGL2 renderer.
Using them well requires materials, map data, configuration and visual verification;
replacing the renderer does not supply those inputs or fix gameplay effect timing.

## Candidate comparison

| Candidate | Observed implementation | dk3 fit and integration scope | Recommendation |
| --- | --- | --- | --- |
| Rain contact, water/solid splashes, roof checks | Client traces, surface/content classification, oriented splash quads, distance limits | Small-to-medium client effects change; retain Daikatana weather volumes, artwork and timing | Highest priority selective reuse/reference |
| Fog transitions | Renderer API with current/target fog, timed interpolation, water/map/sky contexts | Medium-to-large engine/client change across both renderers and module interfaces | Useful when driven by authored Daikatana fog requirements |
| Explicit coronas | Client-submitted lights with IDs, visibility flags, fade state and fog participation | Medium engine/client change, or smaller client-side implementation using existing polygons | Useful for lamps/searchlights; not a replacement for projected lighting |
| Surface splash primitive | `RT_SPLASH`, horizontal textured quad | Small but extends render entity interface; existing polygon API can already do it | Prefer existing polygon API initially |
| OpenGL1 bloom | Screen capture/downsample/filter/composite | Medium GL1 integration; optional, off by default | Low priority after parity repairs |
| SSGI | Half-resolution depth/color sampling, additive indirect-color pass | Medium-to-large GL2 integration plus repairs and visual validation | Experimental only |
| HDR, SSAO, normal/specular/parallax maps, cubemaps, sun shadows/rays | Present in both renderer families being compared | Primarily activation/content work in dk3 | Reuse dk3 implementation, do not import duplicate systems |
| Foliage technology advertised in README | No dedicated implementation identified in inspected renderer/cgame paths | Requires locating actual implementation and authoring inputs | Not an established port candidate |

Scope labels describe code dependencies, not effort estimates.

## 1. Weather: useful code close to the current problem

[RealRTCW cg_atmospheric.c](../../RealRTCW/code/cgame/cg_atmospheric.c):

- `CG_RainParticleGenerate` traces upward to world sky, rejects covered positions,
  then traces the drop path against `MASK_SOLID | MASK_WATER` (around line 258).
- It retains contact height, surface normal, surface flags and contents sampled
  below the hit. This distinguishes water/slime, lava and solid surfaces.
- `CG_RainParticleRender` clips the streak at contact and draws different splash
  sizes on water and solids; steep surfaces, sky and lava are excluded as coded
  (around line 322).
- `CG_EffectMark` constructs a surface-oriented quad with `AddPolyToScene`
  (line 119). It avoids the heavier projected-mark clipping used for bullet holes.
- Splash distance limiting, randomized particle start times and indoor/outdoor
  rain audio are also present. Weather remains a client subsystem, not a GL feature.

**Current dk3 differs from the earlier handoff:**
[dk_effects.c](../src/cgame/dk_effects.c) already traces rain with `MASK_WATER`,
has splash shaders, and reserves lifetime for contacts. This investigation does
not establish whether the user's water-splash complaint is fixed in the installed
game. Do not repeat the stale diagnosis that current source uses only `MASK_SOLID`.

Remaining useful comparisons: dk3's splash branch calls camera-facing
`AtlasParticle`, rather than orienting a quad to the contact plane; it does not
retain a water-versus-solid material category; and it permits a splash at the
trajectory endpoint when no surface was hit. Inspect authored weather-volume floors
and real rendered contacts before deciding how each should change.

Adopt the contact classification and budget ideas, while preserving Daikatana's
atlas sprites, dimensions, wind, density and timing. Do not substitute RTCW's
global sky-driven weather for Daikatana's authored volumes. Its fixed contact
height is also not a complete solution for changing movers or wind. RTCW's rain
textures and sounds are separate assets and must not become dk3 dependencies.

## 2. Fog transitions

[RealRTCW rend2/tr_main.c](../../RealRTCW/code/rend2/tr_main.c) implements
`R_SetFog` near line 81 and transition interpolation near line 734. The GL1
[counterpart](../../RealRTCW/code/renderer/tr_main.c) has the same state concepts.
[tr_public.h](../../RealRTCW/code/renderer/tr_public.h) exposes `SetFog`.

This supplies dynamic fog state for map, water, sky and other views, with timed
color/distance transitions. It is conventional fog, not volumetric light scattering.
dk3 already parses ordinary material `fogParms` in
[tr_shader.c](../engine/ioquake3/code/renderergl2/tr_shader.c); that does not provide
RTCW's explicit client-controlled transition API.

A port needs a narrow versioned dk3 interface, client syscall plumbing where
required, backend implementations, map/script inputs, and restored transition
state after save/load. Preserve HUD and cinematic behavior. First identify actual
Daikatana fog inputs and expected transitions; adding an attractive global haze
would not establish original-game parity.

## 3. Coronas and small effect primitives

[RE_AddCoronaToScene](../../RealRTCW/code/rend2/tr_scene.c) near line 386 accepts
origin, color, scale, stable ID and flags. The
[flare implementation](../../RealRTCW/code/rend2/tr_flares.c) maintains fade state,
handles fog, and combines the visibility flag with a depth-buffer test.

dk3 already has flare sprites, spotlights and ioquake3 flare infrastructure. The
incremental benefit is an explicit source with stable visibility/fade state.
It can improve light-source appearance at doorway/occlusion boundaries. It does
not create a light cone, projected spotlight, or correct an Ion impact event.

The donor performs synchronous `glReadPixels` depth tests. Do not assume this is
a performance improvement; assess whether dk3 client traces plus existing sprite
drawing suffice before expanding the renderer API. Use supplied Daikatana artwork.

`RB_SurfaceSplash` in
[rend2/tr_surface.c](../../RealRTCW/code/rend2/tr_surface.c), near line 245, draws
a horizontal quad. Useful, but not a water simulation or a necessity for ripples.
An existing `AddPolyToScene` call can express arbitrary surface orientation.

The `RT_RAIL_CORE_TAPER` enum exists in the donor's
[tr_types.h](../../RealRTCW/code/renderer/tr_types.h), but neither inspected
backend entity switch dispatches it. Do not mistake the enum for working tapered
lightning support. dk3 already has `TexturedBeam` and an Ion-specific effect path.

## 4. OpenGL1 bloom

[tr_bloom.c](../../RealRTCW/code/renderer/tr_bloom.c) provides a fixed-function
screen-space bloom pass. The local build includes it with `USE_BLOOM`; `r_bloom`
defaults to zero. It needs backend hook integration, texture lifecycle handling
and an explicit decision about applying the pass before HUD/menu rendering.

It is technically portable without RTCW art. It is a poor first response to this
session's excessive-glow complaints: bloom changes the image globally and does not
repair projectile brightness, attenuation or particle shape. Review resolution
math before reuse: `R_Bloom_InitTextures` calculates work height using integer
`vidWidth / vidHeight`, and `R_Bloom_DrawEffect` passes `readW` on both UV axes.
These are source-level concerns requiring non-square display verification.

## 5. Local SSGI: real implementation, significant caveats

The local checkout contains more than a cvar stub:

- [ssgi_fp.glsl](../../RealRTCW/code/rend2/glsl/ssgi_fp.glsl) samples nearby scene
  color with depth and estimated-normal weights.
- [tr_backend.c](../../RealRTCW/code/rend2/tr_backend.c), near line 2061, renders
  at half resolution and additively composites before tone mapping.
- [tr_image.c](../../RealRTCW/code/rend2/tr_image.c) and
  [tr_fbo.c](../../RealRTCW/code/rend2/tr_fbo.c) allocate its image/FBO.
- [tr_glsl.c](../../RealRTCW/code/rend2/tr_glsl.c) registers the shader; the local
  [build.zig](../../RealRTCW/build.zig) embeds the GLSL sources.

Concrete findings before any port:

1. `r_ssgiSamples` is registered but unused by the rendering implementation;
   the shader fixes `NUM_SAMPLES = 8`.
2. The pass samples `hdrDepthImage`, but allocation of that image tests only
   `r_shadowBlur || r_ssao`. SSGI alone does not request its required resource.
3. Depth-copy population lives inside the depth-prepass path. Disabling that
   prepass requires an explicit dependency or another valid depth path.
4. C supplies reciprocal width then height in `u_ViewInfo.zw`; the shader reads
   `.wz`. This swaps the axes on non-square targets. Also reconcile sampling
   resolution with the full-resolution depth texture.
5. Normals are estimated from depth differences, without full view-position
   reconstruction. The pass uses a fixed additive strength of 0.35 and has no
   dedicated temporal accumulation or bilateral denoising stage in this path.
6. The pass draws full-target UVs; viewport/portal/cubemap handling must be reviewed
   rather than assumed correct from a full-screen screenshot.

Expected risks, not measured failures here: view-dependent color bleeding,
edge artifacts, extra green spill around Ion effects, noise and GPU cost.
No off-screen geometry contributes, so this is not full global illumination.

A prototype can reuse dk3's existing FBO/GLSL infrastructure, repair the resource
dependencies and sampling math, expose effective controls, and default off. It
must preserve a reproducible original-look configuration. Do not adopt the donor's
default-on SSGI/SSAO as a brightness fix.

## 6. Already available, or not demonstrated

[dk3 GL2 registration](../engine/ioquake3/code/renderergl2/tr_init.c) already has
HDR/tone mapping/auto exposure, SSAO, normal/specular/deluxe/parallax mapping,
cubemaps, PBR mode, projected/sun shadows, sun rays and MSAA controls. Their presence
is not proof that the current Daikatana packages provide suitable materials or
that every option has been validated in gameplay.

Normal/specular/height maps require corresponding material data; high-resolution
diffuse textures alone do not supply it. Sky/sun parameters and reflection probes
also need appropriate map inputs. Retain dk3's recent dynamic-light/material and
gamma fixes when integrating anything. Do not overwrite whole donor renderer files.

I did not identify dedicated foliage generation in the inspected `renderer`,
`rend2` and `cgame` paths despite the README claim. Likewise, no demonstrated new
soft-particle, SSR, TAA or physically simulated water system was found in this
renderer inspection. Vulkan headers in the tree are not evidence of a usable
Vulkan renderer. RTCW MDC/MDS loaders exist, but importing them would not restore
Daikatana DKM animation semantics; dk3's existing model conversion is the relevant
path for those assets.

## 7. Provenance boundary

Observed file notices differ. dk3's original code and ioquake3 files declare
GPL-2.0-or-later. Many donor renderer files declare GPL-3.0-or-later plus references
to RTCW additional terms. `cg_atmospheric.c` carries ET:Legacy GPL-3.0-or-later,
id and Q3F notices. `tr_bloom.c` has a GPL-2.0-or-later notice. The SSGI shader has
no explicit per-file license header; local authorship/provenance needs recording.

This is a notice inventory, not a completed license-admission review. Before
copying code, identify the exact donor revision/content hashes, retain notices,
resolve applicable terms and document distribution requirements. Prefer shared
ioquake3 implementations where already available. The donor README expressly
separates game data from the source release; do not import its `main`, `media`,
extracted game assets, sounds or textures into dk3.

## Proposed implementation and verification order

1. Complete one coherent weather batch: contact classification, surface-oriented
   splashes where original behavior calls for them, roof/volume handling, and
   particle budgeting. Check original Daikatana behavior throughout.
2. Add fog/corona support only with identified map/effect consumers. Keep render
   services small and gameplay timing in the game/client modules.
3. Separately evaluate optional visual enhancements: existing GL2 settings first,
   then repaired SSGI or GL1 bloom if their rendered results justify inclusion.

After each coherent implementation batch, build and repair the integrated result,
then use existing real scenarios: marsh water/shore/covered areas, rain at grazing
angles, moving camera, snow maps, lamp occlusion, water/fog transitions and saves,
Ion flight/bounces/impacts, cinematics and menus. Exercise GL1 and GL2 for shared
features, non-square resolutions and renderer restart; test SSGI with SSAO and
shadow blur disabled if it is implemented. Capture comparable frames and frame
times. Broad checks belong at the end of the repair batch, not after each edit.

No complete-campaign or visual-parity claim follows from this investigation.

## Implementation status

No RealRTCW code was copied; each item below was rewritten from the original
Daikatana behavior. Status is implemented unless marked verified.

1. Weather. Original splashes are camera-facing triangles at the volume floor,
   with no surface classification, so none was added. Rain stops at liquid as
   well as solid surfaces. `effect_drip` is inert, as in Gold, which removed it
   from the exported spawn functions. Snow now uses the original rate
   (`floor(area / 4096) * 55 / height`), speed 50, `FALL_STRAIGHT` spread,
   distance-scaled radius, constant alpha and a lifetime long enough to reach
   the floor. Each volume prefills to a quarter of its target population at
   random heights. The emission seed now changes every frame; the old
   `cg.time / 32` seed repeated spawn sequences about four times over.
   Verified: splashes on the e1m1a pool on GL1 and GL2. The seed spread was
   verified offline; live snow density has been probed in GDB but not judged
   visually.
2. Fog and coronas. Consumers: 47 converted maps set worldspawn fog
   (`fog_value`, `fog_start`, `fog_end`, `fog_skyend`, `fog_color`/`_color`), and
   457 `light_flare` entities exist. No map uses `trigger_fog_value`, so there
   are no fog transitions. The cgame parses worldspawn fog and submits it every
   frame through `trap_R_Dk3Fog` (syscall 702, `REF_API_VERSION` 9). GL1 uses
   fixed-function linear fog; GL2 uses the `u_Dk3FogColor`/`u_Dk3FogRange`
   uniforms in the generic, dlight and lightall fragment shaders. Both use
   black, white or gray fog colors on additive and modulate passes, and apply
   the original constant sky fog factor from `fog_skyend`. `r_dk3Fog 0` turns fog
   off. Flares follow `CL_AddLightFlares`: occlusion trace, midpoint placement,
   distance alpha, per-axis `scale` and untinted sprites. Verified: fog A/B
   frames on e2m1a on GL1 and GL2; flares on e2m5d and e4m4a on GL1 and GL2.
   Gap: underwater fog color comes from Daikatana surface info, which Q3 BSP
   does not carry per brush side. It needs converter data, so underwater areas
   currently inherit world fog.
3. Optional enhancements. Each variant was a separate launch from the same
   saved setting baseline, at 640x480, captured at an e1m1a marsh view, the
   e4m4a lamp corridor and the e2m5d medusa panel. Brightness is the mean
   8-bit gray level at the e4m4a view:
   - GL2 defaults (HDR, tone mapping, auto exposure) measure 85. Turning all
     three off measures 74; fixed exposure measures 88; GL1 measures 71. The
     defaults stay: they are brighter without clipping, and the flat setting
     remains available as the closest to fixed-function output.
   - `r_ssao 1` darkens contact corners slightly (85 to 82). It stays off; the
     result is subtle and costs an extra pass.
   - `r_cubeMapping` and `r_drawSunRays` differ from the default only by
     animation noise. The converted maps provide no reflection probes or sun
     parameters, so neither has a consumer.
   - GL1 bloom: implemented as `r_bloom` (default 0) in
     `renderergl1/tr_bloom.c`. It is adapted from RealRTCW `code/renderer/tr_bloom.c`
     at ef7a6ceed7d980a4a9584e169a75d15f62f3c057 (sha256 62fa72a2…f672c),
     which carries an id Software GPL-2.0-or-later notice that is retained.
     Changes: the sample height follows the display aspect (the donor used
     integer `vidWidth / vidHeight`); the composite uses `readH` on the
     vertical axis; the pass runs once per frame after the first world scene
     and before 2D drawing, screenshots and video frames, so the HUD, menus
     and model-only UI scenes are not bloomed; an unusable sample size
     disables it with a warning instead of changing the cvar. Verified on GL1
     at 640x480 and 1280x720: glow on bright surfaces, no offset or stretch
     (e4m4a mean 71 to 77).
   - SSGI: not implemented. The donor pass lives in GPL-3.0-or-later rend2
     files, which cannot be admitted into this GPL-2.0-or-later tree. Also,
     Daikatana lightmaps are radiosity-compiled and already contain bounced
     light, so a screen-space bounce pass would double-count indirect light;
     SSAO already covers the contact-darkening part. Revisit only with an
     independently written pass and a map consumer that shows a benefit.

Seen during capture and not caused by this work: saturated yellow patches on
GL2 lit surfaces (also present in the pre-change build), and cyan noise at the
bottom of GL2 frames on e4m4a, a map without fog.
