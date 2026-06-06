#version 460
#include <flutter/runtime_effect.glsl>

// ════════════════════════════════════════════════════════════════════
//  P5: MSDF Fragment Shader — Next++ 专用 (drawRect + Paint.shader per-glyph)
//
//  此 shader 为 Next++ MSDF 管线专用，与共享的 msdf_text.frag 分离，
//  避免修改共享 shader 导致其他引擎兼容性问题。
//
//  渲染管线：逐字形 canvas.drawRect(rect, Paint..shader)
//  Uniform 输入替代旧版 per-vertex varying（SkSL 兼容）。
//
//  Uniform:
//    uTexture       — MSDF 字形图集 (sampler2D, image sampler slot 0)
//    uSpread        — MSDF spread 值 (float, slot 0)
//    uOutlinePx     — 描边像素宽度 (float, slot 1)
//    uAtlasRect     — 图集纹理坐标 (vec4, slot 2-5: x=u0, y=v0, z=uW, w=vH)
//    uRectSize      — 绘制矩形尺寸 (vec2, slot 6-7: width, height)
//    uFillColor     — 填充颜色 + 描边选择 (vec4, slot 8-11: rgb=fill, a=outlineSelector)
//
//  uFillColor.a 编码 outlineSelector：0.0=黑描边, 1.0=白描边
// ════════════════════════════════════════════════════════════════════

precision highp float;

uniform sampler2D uTexture;
uniform float uSpread;
uniform float uOutlinePx;
uniform vec4 uAtlasRect;    // x=u0, y=v0, z=uW, w=vH
uniform vec2 uRectSize;     // draw rect width, height
uniform vec4 uFillColor;    // rgb=fillColor, a=outlineSelector (0.0=black, 1.0=white)

out vec4 fragColor;

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

void main() {
    // Normalize fragment position to (0,1) within the draw rect
    vec2 localUV = FlutterFragCoord().xy / uRectSize;

    // Map to atlas texture coordinates
    vec2 atlasUV = uAtlasRect.xy + localUV * uAtlasRect.zw;

    // Sample MSDF atlas
    vec3 texel = texture(uTexture, atlasUV).rgb;
    float dist = median(texel.r, texel.g, texel.b);

    // MSDF distance field parameters
    float smoothing = 0.01 / max(uSpread, 0.0001);
    float outline = uOutlinePx / max(uSpread, 0.0001);

    // Fill and outline alpha
    float fillAlpha = smoothstep(0.5 - smoothing, 0.5 + smoothing, dist);
    float outlineAlpha = smoothstep(0.5 - outline - smoothing, 0.5 - outline + smoothing, dist);
    float strokeAlpha = clamp(outlineAlpha - fillAlpha, 0.0, 1.0);

    // Outline color from uFillColor.a (outlineSelector)
    vec3 outlineColor = mix(vec3(0.0), vec3(1.0), uFillColor.a);
    vec3 fillColor = uFillColor.rgb;

    // Compose final color: outline layer + fill layer
    vec4 color = vec4(outlineColor, 1.0) * strokeAlpha + vec4(fillColor, 1.0) * fillAlpha;
    fragColor = vec4(color.rgb, color.a);
}
