#version 460
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform sampler2D uTexture;

uniform vec4 uRect;       // x, y, w, h in screen coords
uniform vec4 uAtlasRect;  // x, y, w, h in atlas UV (0..1)
uniform vec4 uFillColor;
uniform vec4 uOutlineColor;
uniform float uOpacity;
uniform float uSpread;
uniform float uOutlinePx;

out vec4 fragColor;

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = (fragCoord - uRect.xy) / uRect.zw;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        discard;
    }

    vec2 atlasUv = uAtlasRect.xy + uv * uAtlasRect.zw;
    vec3 texel = texture(uTexture, atlasUv).rgb;
    float dist = median(texel.r, texel.g, texel.b);

    float smoothing = fwidth(dist);
    float outline = uOutlinePx / max(uSpread, 0.0001);

    float fillAlpha = smoothstep(0.5 - smoothing, 0.5 + smoothing, dist);
    float outlineAlpha = smoothstep(0.5 - outline - smoothing, 0.5 - outline + smoothing, dist);
    float strokeAlpha = clamp(outlineAlpha - fillAlpha, 0.0, 1.0);

    vec4 color = uOutlineColor * strokeAlpha + uFillColor * fillAlpha;
    fragColor = vec4(color.rgb, color.a * uOpacity);
}
