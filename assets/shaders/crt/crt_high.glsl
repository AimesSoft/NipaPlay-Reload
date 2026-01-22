//!DESC CRT High
//!HOOK MAIN
//!BIND HOOKED

const float PI = 3.141592653589793;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 hook() {
    vec2 uv = HOOKED_pos;
    vec2 px = HOOKED_pt;

    vec2 centered = uv * 2.0 - 1.0;
    float r2 = dot(centered, centered);
    float curvature = 0.18;
    vec2 distorted = centered * (1.0 + curvature * r2);
    vec2 duv = distorted * 0.5 + 0.5;

    float inside = step(0.0, duv.x) * step(duv.x, 1.0) *
        step(0.0, duv.y) * step(duv.y, 1.0);
    vec2 clamped = clamp(duv, 0.0, 1.0);

    vec2 caOffset = vec2(px.x * 0.6, 0.0);
    float r = HOOKED_tex(clamped + caOffset).r;
    float g = HOOKED_tex(clamped).g;
    float b = HOOKED_tex(clamped - caOffset).b;
    vec3 color = vec3(r, g, b);

    vec3 bloom = vec3(0.0);
    bloom += HOOKED_tex(clamped + vec2(px.x, 0.0)).rgb;
    bloom += HOOKED_tex(clamped - vec2(px.x, 0.0)).rgb;
    bloom += HOOKED_tex(clamped + vec2(0.0, px.y)).rgb;
    bloom += HOOKED_tex(clamped - vec2(0.0, px.y)).rgb;
    bloom *= 0.25;
    color = mix(color, bloom, 0.25);

    float y = clamped.y / px.y;
    float line = mod(floor(y), 2.0);
    float scan = mix(1.0, 0.78, line);
    color *= scan;

    float x = clamped.x / px.x;
    float tri = x * (2.0 * PI / 3.0);
    vec3 mask = vec3(
        sin(tri) * 0.5 + 0.5,
        sin(tri + 2.094395102393195) * 0.5 + 0.5,
        sin(tri + 4.1887902047863905) * 0.5 + 0.5
    );
    const float maskStrength = 0.45;
    color *= mix(vec3(1.0 - maskStrength), vec3(1.0), mask);

    float vignette = 1.0 - smoothstep(0.45, 1.05, length(distorted));
    color *= mix(1.0, vignette, 0.55);

    float noise = rand(clamped * vec2(900.0, 600.0));
    color *= 1.0 + (noise - 0.5) * 0.03;

    color *= 1.12;
    color *= inside;
    return vec4(clamp(color, 0.0, 1.0), 1.0);
}
