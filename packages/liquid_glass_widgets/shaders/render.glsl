// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared rendering functions for liquid glass shaders.
//
// Functions used by liquid_glass_final_render.frag:
//   getHighlightColor  — adaptive specular highlight tint
//   applySaturation    — Rec. 709 saturation matrix
//   applyGlassColor    — iOS 26 luminosity-preserving tint

// Constants
const vec3 LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114);

// NOTE: rotate2d() was removed — it was never called by any shader and was
// compiled into every shader binary that includes render.glsl for no benefit.

// ── getHighlightColor ─────────────────────────────────────────────────────────
// Optimized highlight color - ~60% fewer operations than original version.
// Computes a luminosity-tinted white using a fast rational approximation for
// the lum/saturation blend weight instead of the slower smoothstep path.
vec3 getHighlightColor(vec3 backgroundColor, float targetBrightness) {
    float luminance = dot(backgroundColor, LUMA_WEIGHTS);
    
    // Fast saturation approximation using max component only
    float maxComponent = max(max(backgroundColor.r, backgroundColor.g), backgroundColor.b);
    
    // Combined color influence factor using fast rational approximation
    // x/(1+x) is faster than smoothstep and visually similar
    float lum = luminance * 2.5;
    float lumFactor = lum / (1.0 + lum);
    
    float sat = maxComponent * 2.5;
    float satFactor = sat / (1.0 + sat);
    
    float colorInfluence = lumFactor * satFactor;
    
    // Normalize and tint in one step
    vec3 tinted = (backgroundColor / max(luminance, 0.001)) * targetBrightness;
    
    return mix(vec3(targetBrightness), tinted, colorInfluence);
}

// ── applySaturation ───────────────────────────────────────────────────────────
// Rec. 709 luminance-preserving saturation.
// saturation = 1.0 → no change; > 1.0 → over-saturated; < 1.0 → desaturated.
vec3 applySaturation(vec3 color, float saturation) {
    float luminance = dot(color, LUMA_WEIGHTS);
    vec3 saturatedColor = mix(vec3(luminance), color, saturation);
    return clamp(saturatedColor, 0.0, 1.0);
}

// ── applyGlassColor ───────────────────────────────────────────────────────────
// Apply glass color tinting to the liquid color.
// iOS 26 model: chromatic glass (blue, amber) preserves backdrop luminance while
// shifting hue — unlike Overlay which produced unintuitive darkening/brightening.
// Achromatic glass (white, grey, black) uses a direct alpha-composite mix so
// that white glass actually lifts toward white (brightness effect). Without this,
// whites collapse to a luminance-matched grey and can never frost the surface.
// The chroma factor blends smoothly between the two paths — fully branchless.
// glassColor.a = 0 naturally returns liquidColor via mix() in both paths.
vec4 applyGlassColor(vec4 liquidColor, vec4 glassColor) {
    float backdropLuminance = dot(liquidColor.rgb, LUMA_WEIGHTS);
    float glassLuminance    = dot(glassColor.rgb, LUMA_WEIGHTS);

    // Luminosity-preserving tint: shift chroma toward glass, keep backdrop brightness.
    vec3 tinted = clamp(glassColor.rgb + (backdropLuminance - glassLuminance), 0.0, 1.0);

    // Chroma of the glass colour: 0 = achromatic (white/grey/black), 1 = fully saturated.
    // Use a sharp ramp so anything with meaningful colour uses the luminosity path.
    float chroma = max(max(glassColor.r, glassColor.g), glassColor.b)
                 - min(min(glassColor.r, glassColor.g), glassColor.b);
    float chromaWeight = clamp(chroma * 8.0, 0.0, 1.0);

    // achromatic path: direct mix toward the glass colour (white lifts to white)
    vec3 directMix     = mix(liquidColor.rgb, glassColor.rgb, glassColor.a);
    // chromatic path:  mix toward luminosity-shifted tint (hue shift, brightness held)
    vec3 luminosityMix = mix(liquidColor.rgb, tinted, glassColor.a);

    return vec4(mix(directMix, luminosityMix, chromaWeight), liquidColor.a);
}
