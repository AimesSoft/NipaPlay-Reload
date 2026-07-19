// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Geometry precomputation shader for blended liquid glass shapes
// This shader pre-computes the surface normal and encodes it into a texture.
// Only needs to be re-run when shape geometry or layout changes.
//
// Texture layout (slots → displacement_encoding.glsl):
//   R: normal.x  [-1, 1] → [0, 1]
//   G: normal.y  [-1, 1] → [0, 1]
//   B: height    normalized to thickness
//   A: foreground alpha (SDF anti-aliasing)

#version 460 core
precision highp float; // mediump caused ~1.5px displacement banding on mobile (10-bit mantissa)

#include <flutter/runtime_effect.glsl>

// MAX_SHAPES must be defined before uShapeData so the array size is known.
// sdf.glsl uses an #ifndef guard so this definition takes precedence.
#define MAX_SHAPES 16

layout(location = 0) uniform vec2 uSize;
layout(location = 1) uniform vec4 uOpticalProps;
layout(location = 2) uniform vec2 uShapeSettings; // x = numShapes, y = dpr
layout(location = 3) uniform float uShapeData[MAX_SHAPES * 7];

// sdf.glsl functions access uShapeData as a global (no array-by-value parameters,
// which are rejected by glslang on Windows/Vulkan SPIR-V compilation).
#include "sdf.glsl"
#include "displacement_encoding.glsl"

layout(location = 0) out vec4 fragColor;

void main() {
    // Unpacked here rather than at global scope: global non-constant initialisers
    // (e.g. float x = uniform.y) are valid in desktop GLSL 4.6 but rejected by
    // SkSL / glslang on Windows.
    float uThickness = uOpticalProps.z;
    float uBlend = uOpticalProps.w;

    float uNumShapes = uShapeSettings.x;
    float uDpr = uShapeSettings.y;

    vec2 fragCoord = FlutterFragCoord().xy;

    float sd = sceneSDF(fragCoord, int(uNumShapes), uBlend);

    // Apply logical-pixel anti-aliasing.
    // Centering the smoothstep around 0.0 ensures the mathematical boundary (sd=0)
    // is exactly 50% opaque. This correctly aligns the peak edge highlight with
    // the visual edge of the shape, restoring maximum brightness.
    // 1.5 logical pixels of smoothing guarantees a pristine edge that survives
    // the 4% bilinear scaling of press animations without stair-stepping.
    float smoothing = 1.5 * max(1.0, uDpr);
    float foregroundAlpha = smoothstep(smoothing * 0.5, -smoothing * 0.5, sd);
    if (foregroundAlpha < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    // Compute the SDF gradient for surface normal generation.
    //
    // We MUST use central ±0.5 px finite differences on ALL platforms.
    // While Metal supports dFdx/dFdy on scalar floats, hardware derivatives are
    // computed in 2x2 pixel quads, resulting in blocky 2x2 normals. When these
    // blocky normals refract high-contrast edges (like the base pill's white rim),
    // they produce severe stair-step aliasing.
    // Central differences guarantee a perfectly smooth, continuous normal per-pixel.
    //
    // PP4: Reduce 5 sceneSDF() calls to 4 by approximating the center sample
    // from the average of the 4 offset samples. The approximation error is ~0.5%
    // — below the AA smoothstep band and imperceptible in the alpha/height output.
    // For a blend group with N shapes this saves N smooth-union evaluations.
    float sdPX = sceneSDF(fragCoord + vec2(0.5, 0.0), int(uNumShapes), uBlend);
    float sdMX = sceneSDF(fragCoord - vec2(0.5, 0.0), int(uNumShapes), uBlend);
    float sdPY = sceneSDF(fragCoord + vec2(0.0, 0.5), int(uNumShapes), uBlend);
    float sdMY = sceneSDF(fragCoord - vec2(0.0, 0.5), int(uNumShapes), uBlend);
    sd = (sdPX + sdMX + sdPY + sdMY) * 0.25; // reassign center approximation
    float dx = sdPX - sdMX;
    float dy = sdPY - sdMY;

    float n_cos = max(uThickness + sd, 0.0) / uThickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));

    // True surface normal from the SDF gradient — this is what we store.
    // In blend-group neck zones the displacement vector diverges from this
    // normal, which is why storing the normal (not displacement) fixes lighting.
    vec3 normal = normalize(vec3(dx * n_cos, dy * n_cos, n_sin));

    if (sd >= 0.0 || uThickness <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float x = uThickness + sd;
    float sqrtTerm = sqrt(max(0.0, uThickness * uThickness - x * x));
    float height = mix(sqrtTerm, uThickness, float(sd < -uThickness));

    // Encode normal.xy + height + alpha.
    // The render pass recomputes displacement = refract(incident, normal, 1/n)
    // so there is no information loss compared to storing displacement directly.
    fragColor = encodeGeometryData(normal.xy, height, uThickness, foregroundAlpha);
}
