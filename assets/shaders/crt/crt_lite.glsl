//!DESC CRT Lite
//!HOOK MAIN
//!BIND HOOKED

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = HOOKED_pt;

    vec4 color = HOOKED_tex(uv);

    float y = uv.y / px.y;
    float line = mod(floor(y), 2.0);
    float scan = mix(1.0, 0.88, line);
    color.rgb *= scan;

    vec2 centered = uv * 2.0 - 1.0;
    float vignette = 1.0 - smoothstep(0.6, 1.2, length(centered));
    color.rgb *= mix(1.0, vignette, 0.35);

    color.rgb *= 1.05;
    return vec4(clamp(color.rgb, 0.0, 1.0), color.a);
}
