const NEXT2_SCREEN_COPY_WGSL: &str = r#"
struct VsOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@group(0) @binding(0) var source_tex: texture_2d<f32>;
@group(0) @binding(1) var source_sampler: sampler;

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VsOut {
    var positions = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -3.0),
        vec2<f32>(3.0, 1.0),
        vec2<f32>(-1.0, 1.0),
    );
    var uvs = array<vec2<f32>, 3>(
        vec2<f32>(0.0, 2.0),
        vec2<f32>(2.0, 0.0),
        vec2<f32>(0.0, 0.0),
    );
    var o: VsOut;
    o.pos = vec4<f32>(positions[vertex_index], 0.0, 1.0);
    o.uv = uvs[vertex_index];
    return o;
}

@fragment
fn fs_main(v: VsOut) -> @location(0) vec4<f32> {
    return textureSample(source_tex, source_sampler, v.uv);
}
"#;

const NEXT2_SHADOW_BLUR_HORIZONTAL_WGSL: &str = r#"
struct VsOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@group(0) @binding(0) var source_tex: texture_2d<f32>;
@group(0) @binding(1) var source_sampler: sampler;

const BLUR_SCALE: f32 = 1.6;

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VsOut {
    var positions = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -3.0),
        vec2<f32>(3.0, 1.0),
        vec2<f32>(-1.0, 1.0),
    );
    var uvs = array<vec2<f32>, 3>(
        vec2<f32>(0.0, 2.0),
        vec2<f32>(2.0, 0.0),
        vec2<f32>(0.0, 0.0),
    );
    var o: VsOut;
    o.pos = vec4<f32>(positions[vertex_index], 0.0, 1.0);
    o.uv = uvs[vertex_index];
    return o;
}

@fragment
fn fs_main(v: VsOut) -> @location(0) vec4<f32> {
    let dims = vec2<f32>(textureDimensions(source_tex));
    let step = vec2<f32>(BLUR_SCALE / max(dims.x, 1.0), 0.0);
    var color = textureSample(source_tex, source_sampler, v.uv) * 0.29411766;
    color += textureSample(source_tex, source_sampler, v.uv + step * 1.0) * 0.23529412;
    color += textureSample(source_tex, source_sampler, v.uv - step * 1.0) * 0.23529412;
    color += textureSample(source_tex, source_sampler, v.uv + step * 2.0) * 0.11764706;
    color += textureSample(source_tex, source_sampler, v.uv - step * 2.0) * 0.11764706;
    return color;
}
"#;

const NEXT2_SHADOW_BLUR_VERTICAL_WGSL: &str = r#"
struct VsOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@group(0) @binding(0) var source_tex: texture_2d<f32>;
@group(0) @binding(1) var source_sampler: sampler;

const BLUR_SCALE: f32 = 1.6;

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VsOut {
    var positions = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -3.0),
        vec2<f32>(3.0, 1.0),
        vec2<f32>(-1.0, 1.0),
    );
    var uvs = array<vec2<f32>, 3>(
        vec2<f32>(0.0, 2.0),
        vec2<f32>(2.0, 0.0),
        vec2<f32>(0.0, 0.0),
    );
    var o: VsOut;
    o.pos = vec4<f32>(positions[vertex_index], 0.0, 1.0);
    o.uv = uvs[vertex_index];
    return o;
}

@fragment
fn fs_main(v: VsOut) -> @location(0) vec4<f32> {
    let dims = vec2<f32>(textureDimensions(source_tex));
    let step = vec2<f32>(0.0, BLUR_SCALE / max(dims.y, 1.0));
    var color = textureSample(source_tex, source_sampler, v.uv) * 0.29411766;
    color += textureSample(source_tex, source_sampler, v.uv + step * 1.0) * 0.23529412;
    color += textureSample(source_tex, source_sampler, v.uv - step * 1.0) * 0.23529412;
    color += textureSample(source_tex, source_sampler, v.uv + step * 2.0) * 0.11764706;
    color += textureSample(source_tex, source_sampler, v.uv - step * 2.0) * 0.11764706;
    return color;
}
"#;

const NEXT2_WGSL: &str = r#"
struct VsIn {
    @location(0) pos: vec2<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) uv_aux: vec2<f32>,
    @location(3) color: vec4<f32>,
    @location(4) outline_color: vec4<f32>,
    @location(5) params: vec4<f32>,
};

struct VsOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) uv_aux: vec2<f32>,
    @location(2) color: vec4<f32>,
    @location(3) outline_color: vec4<f32>,
    @location(4) params: vec4<f32>,
};

@group(0) @binding(0) var atlas_tex: texture_2d<f32>;
@group(0) @binding(1) var atlas_sampler: sampler;
@group(0) @binding(2) var emoji_tex: texture_2d<f32>;
@group(0) @binding(3) var emoji_mask_tex: texture_2d<f32>;
@group(0) @binding(4) var emoji_sampler: sampler;

@vertex
fn vs_main(v: VsIn) -> VsOut {
    var o: VsOut;
    o.pos = vec4<f32>(v.pos, 0.0, 1.0);
    o.uv = v.uv;
    o.uv_aux = v.uv_aux;
    o.color = v.color;
    o.outline_color = v.outline_color;
    o.params = v.params;
    return o;
}

fn median3(r: f32, g: f32, b: f32) -> f32 {
    return max(min(r, g), min(max(r, g), b));
}

@fragment
fn fs_main(v: VsOut) -> @location(0) vec4<f32> {
    let mode = v.params.z;
    let is_emoji = mode > 0.5;
    let is_shadow = v.params.w > 0.5;
    let spread = max(v.params.x, 0.001);
    let outline_px = max(v.params.y, 0.0);

    if (is_emoji) {
        let color_texel = textureSample(emoji_tex, emoji_sampler, v.uv);
        let sdf_texel = textureSample(emoji_mask_tex, emoji_sampler, v.uv_aux).r;
        let d = (sdf_texel - 0.5) * spread;
        let px = max(fwidth(d), 0.0001);

        if (is_shadow) {
            let shadow_coverage = smoothstep(-px, px, d);
            let shadow_alpha = shadow_coverage * color_texel.a * v.color.a;
            return vec4<f32>(v.color.rgb * shadow_alpha, shadow_alpha);
        }

        let fill_coverage = smoothstep(-px, px, d);

        var outline_coverage = 0.0;
        if (outline_px > 0.0) {
            let outer_alpha = smoothstep(
                -outline_px - px,
                -outline_px + px,
                d,
            );
            outline_coverage = max(outer_alpha - fill_coverage, 0.0);
        }

        let fill_alpha = fill_coverage * color_texel.a * v.color.a;
        let outline_alpha = outline_coverage * v.outline_color.a;
        let fill_rgb = color_texel.rgb * fill_alpha;
        let outline_rgb = v.outline_color.rgb * outline_alpha;
        let out_rgb = fill_rgb + outline_rgb * (1.0 - fill_alpha);
        let out_alpha = fill_alpha + outline_alpha * (1.0 - fill_alpha);
        return vec4<f32>(out_rgb, out_alpha);
    }

    let texel = textureSample(atlas_tex, atlas_sampler, v.uv);
    let dist_msdf = median3(texel.r, texel.g, texel.b);
    let dist_sdf = texel.a;

    let d_fill = (dist_msdf - 0.5) * spread;
    let px_fill = max(fwidth(d_fill), 0.0001);
    let fill_coverage_aa = smoothstep(-px_fill, px_fill, d_fill);

    let d_outline = (dist_sdf - 0.5) * spread;
    let px_outline = max(fwidth(d_outline), 0.0001);

    if (is_shadow) {
        let shadow_coverage = smoothstep(-px_outline, px_outline, d_outline);
        let shadow_alpha = shadow_coverage * v.color.a;
        return vec4<f32>(v.color.rgb * shadow_alpha, shadow_alpha);
    }

    let fill_coverage_sdf = smoothstep(-px_outline, px_outline, d_outline);
    var outline_coverage = 0.0;
    if (outline_px > 0.0) {
        let outer_alpha = smoothstep(
            -outline_px - px_outline,
            -outline_px + px_outline,
            d_outline,
        );
        outline_coverage = max(outer_alpha - fill_coverage_sdf, 0.0);
    }

    let fill_alpha = fill_coverage_aa * v.color.a;
    let outline_alpha = outline_coverage * v.outline_color.a;

    // Premultiplied "fill over outline" composition avoids a bright seam at
    // the inner stroke boundary while keeping anti-aliased edges.
    let fill_rgb = v.color.rgb * fill_alpha;
    let outline_rgb = v.outline_color.rgb * outline_alpha;
    let out_rgb = fill_rgb + outline_rgb * (1.0 - fill_alpha);
    let out_alpha = fill_alpha + outline_alpha * (1.0 - fill_alpha);
    return vec4<f32>(out_rgb, out_alpha);
}
"#;
