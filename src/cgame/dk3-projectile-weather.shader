// SPDX-License-Identifier: GPL-2.0-or-later
dk3/fx/shotcycler-mark
{
 polygonOffset
 cull disable
 { clampMap skins/we_bhole2.png
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
 }
}

dk3/fx/shotcycler-flash
{
 cull disable
 { map skins/genflash.png
   blendFunc GL_SRC_ALPHA GL_ONE
   rgbGen entity
   alphaGen entity
 }
}

dk3/fx/ion-flash
{
 cull disable
 { map skins/genflashg.png
   blendFunc GL_SRC_ALPHA GL_ONE
   rgbGen entity
   alphaGen entity
 }
}

dk3/fx/ion-lightning
{
 cull disable
 { map pics/misc/w_zap001.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
 }
}
dk3/fx/ion-spark
{
 cull disable
 { map pics/misc/beamspark.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
 }
}
dk3/particle/rain
{
 cull disable
 { map pics/particles/particles.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
   tcMod transform 0.1171875 0 0 0.2421875 0.880859375 0.25390625
 }
}
dk3/particle/ion-sparkle
{
 cull disable
 { map pics/particles/particles.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
   tcMod transform 0.12109375 0 0 0.2421875 0.126953125 0.75390625
 }
}
dk3/particle/rain-splash
{
 cull disable
 { map pics/particles/particles.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
   tcMod transform 0.12109375 0 0 0.2109375 0.376953125 0.50390625
 }
}
dk3/particle/rain-splash3
{
 cull disable
 { map pics/particles/particles.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
   tcMod transform 0.12109375 0 0 0.2109375 0.626953125 0.50390625
 }
}

// Petrified actors retain their silhouette and static pose.
dk3/fx/stone
{
 { map $whiteimage
   blendFunc blend
   rgbGen lightingDiffuse
   alphaGen entity
 }
}

dk3/fx/dklevel
{
 cull disable
 { map skins/we_dklevel.png
   blendFunc GL_SRC_ALPHA GL_ONE
   rgbGen entity
   alphaGen entity
 }
}

dk3/fx/freeze
{
 deformVertexes wave 100 sin 0.4 0 0 0
 { map $whiteimage
   blendFunc GL_ONE GL_ONE
   rgbGen entity
 }
}
dk3/particle/blood1
{
 cull disable
 { map pics/particles/particles.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
   tcMod transform 0.05859375 0 0 0.1171875 0.439453125 0.75390625
 }
}
dk3/particle/blood2
{
 cull disable
 { map pics/particles/particles.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
   tcMod transform 0.05859375 0 0 0.1171875 0.501953125 0.75390625
 }
}
dk3/particle/blood3
{
 cull disable
 { map pics/particles/particles.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
   tcMod transform 0.05859375 0 0 0.1171875 0.564453125 0.75390625
 }
}
dk3/particle/blood4
{
 cull disable
 { map pics/particles/particles.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
   tcMod transform 0.05859375 0 0 0.1171875 0.439453125 0.87890625
 }
}
dk3/particle/sparks
{
 cull disable
 { map pics/particles/particles.tga
   blendFunc blend
   rgbGen vertex
   alphaGen vertex
   tcMod transform 0.05859375 0 0 0.1171875 0.564453125 0.87890625
 }
}
dk3/mark/blood1
{
 polygonOffset
 cull disable
 { clampMap skins/we_blood001
 blendFunc blend
 rgbGen vertex
 alphaGen vertex
 }
}
dk3/mark/blood2
{
 polygonOffset
 cull disable
 { clampMap skins/we_blood002
 blendFunc blend
 rgbGen vertex
 alphaGen vertex
 }
}

// Black-backed muzzle art needs additive blending, independent of model skins.
dk3/fx/glock-flash
{
 cull disable
 { map skins/we_mflash1.png
   blendFunc GL_SRC_ALPHA GL_ONE
   rgbGen entity
   alphaGen entity
 }
}

dk3/fx/weapon-shine
{
 { map gfx/dk3/particle.tga
   tcGen environment
   blendFunc GL_SRC_ALPHA GL_ONE
   rgbGen entity
   alphaGen entity
 }
}
