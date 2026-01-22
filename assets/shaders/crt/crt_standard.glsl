//!DESC CRT Standard
//!HOOK MAIN
//!BIND HOOKED

const float PI = 3.141592653589793;

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = HOOKED_pt;

    vec2 centered = uv * 2.0 - 1.0;
    float r2 = dot(centered, centered);
    float curvature = 0.12;
    vec2 distorted = centered * (1.0 + curvature * r2);
    vec2 duv = distorted * 0.5 + 0.5;

    float inside = step(0.0, duv.x) * step(duv.x, 1.0) *
        step(0.0, duv.y) * step(duv.y, 1.0);
    vec4 color = HOOKED_tex(clamp(duv, 0.0, 1.0));
    color.rgb *= inside;

    float y = duv.y / px.y;
    float line = mod(floor(y), 2.0);
    float scan = mix(1.0, 0.85, line);
    color.rgb *= scan;

    float x = duv.x / px.x;
    float tri = x * (2.0 * PI / 3.0);
    vec3 mask = vec3(
        sin(tri) * 0.5 + 0.5,
        sin(tri + 2.094395102393195) * 0.5 + 0.5,
        sin(tri + 4.1887902047863905) * 0.5 + 0.5
    );
    const float maskStrength = 0.35;
    color.rgb *= mix(vec3(1.0 - maskStrength), vec3(1.0), mask);

    float vignette = 1.0 - smoothstep(0.5, 1.1, length(distorted));
    color.rgb *= mix(1.0, vignette, 0.45);

    color.rgb *= 1.08;
    return vec4(clamp(color.rgb, 0.0, 1.0), color.a);
}
