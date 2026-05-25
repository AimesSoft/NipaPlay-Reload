#[repr(C)]
#[derive(Copy, Clone, Debug, Pod, Zeroable)]
struct GlyphVertex {
    position: [f32; 2],
    uv: [f32; 2],
    uv_aux: [f32; 2],
    color: [f32; 4],
    outline_color: [f32; 4],
    params: [f32; 4],
}

impl GlyphVertex {
    const fn layout() -> wgpu::VertexBufferLayout<'static> {
        const ATTRS: [wgpu::VertexAttribute; 6] = [
            wgpu::VertexAttribute {
                format: wgpu::VertexFormat::Float32x2,
                offset: 0,
                shader_location: 0,
            },
            wgpu::VertexAttribute {
                format: wgpu::VertexFormat::Float32x2,
                offset: 8,
                shader_location: 1,
            },
            wgpu::VertexAttribute {
                format: wgpu::VertexFormat::Float32x2,
                offset: 16,
                shader_location: 2,
            },
            wgpu::VertexAttribute {
                format: wgpu::VertexFormat::Float32x4,
                offset: 24,
                shader_location: 3,
            },
            wgpu::VertexAttribute {
                format: wgpu::VertexFormat::Float32x4,
                offset: 40,
                shader_location: 4,
            },
            wgpu::VertexAttribute {
                format: wgpu::VertexFormat::Float32x4,
                offset: 56,
                shader_location: 5,
            },
        ];

        wgpu::VertexBufferLayout {
            array_stride: std::mem::size_of::<GlyphVertex>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Vertex,
            attributes: &ATTRS,
        }
    }
}

#[derive(Clone)]
struct FontFaceHandle {
    face: Face<'static>,
}

#[derive(Clone)]
struct GlyphMsdfData {
    pixels: Vec<u8>,
    width: u32,
    height: u32,
    spread: f32,
    offset_x: f32,
    offset_y: f32,
    advance: f32,
}

#[derive(Clone)]
struct GlyphAtlasEntry {
    uv_min: [f32; 2],
    uv_max: [f32; 2],
    width: u32,
    height: u32,
    offset_x: f32,
    offset_y: f32,
    advance: f32,
    spread: f32,
}

#[derive(Clone)]
struct EmojiAtlasEntry {
    uv_min: [f32; 2],
    uv_max: [f32; 2],
    mask_uv_min: [f32; 2],
    mask_uv_max: [f32; 2],
    width: u32,
    height: u32,
    advance: f32,
    offset_x: f32,
    offset_y: f32,
}

struct EmojiRasterData {
    id: String,
    width: u32,
    height: u32,
    advance: f32,
    offset_x: f32,
    offset_y: f32,
    rgba: Vec<u8>,
}

struct Next2EmojiAtlas {
    color_texture: wgpu::Texture,
    color_texture_view: wgpu::TextureView,
    mask_texture: wgpu::Texture,
    mask_texture_view: wgpu::TextureView,
    sampler: wgpu::Sampler,
    width: u32,
    height: u32,
    cursor_x: u32,
    cursor_y: u32,
    row_height: u32,
    entries: HashMap<String, EmojiAtlasEntry>,
}

impl Next2EmojiAtlas {
    fn new(device: &wgpu::Device) -> Self {
        let color_texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("next2 emoji color atlas"),
            size: wgpu::Extent3d {
                width: EMOJI_ATLAS_SIZE,
                height: EMOJI_ATLAS_SIZE,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let color_texture_view = color_texture.create_view(&wgpu::TextureViewDescriptor::default());

        let mask_texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("next2 emoji mask atlas"),
            size: wgpu::Extent3d {
                width: EMOJI_ATLAS_SIZE,
                height: EMOJI_ATLAS_SIZE,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::R8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let mask_texture_view = mask_texture.create_view(&wgpu::TextureViewDescriptor::default());

        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("next2 emoji atlas sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });

        Self {
            color_texture,
            color_texture_view,
            mask_texture,
            mask_texture_view,
            sampler,
            width: EMOJI_ATLAS_SIZE,
            height: EMOJI_ATLAS_SIZE,
            cursor_x: 0,
            cursor_y: 0,
            row_height: 0,
            entries: HashMap::new(),
        }
    }

    fn clear(&mut self) {
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.row_height = 0;
        self.entries.clear();
    }

    fn entry_for(&self, id: &str) -> Option<&EmojiAtlasEntry> {
        self.entries.get(id)
    }

    fn upload_glyphs(&mut self, queue: &wgpu::Queue, glyphs: &[EmojiRasterData]) {
        let mut index = 0usize;
        let mut restarted_after_clear = false;
        while index < glyphs.len() {
            let glyph = &glyphs[index];
            if self.entries.contains_key(&glyph.id) {
                index += 1;
                continue;
            }
            let Some(cleared) = self.upload_one(queue, glyph) else {
                index += 1;
                continue;
            };
            if cleared && !restarted_after_clear {
                restarted_after_clear = true;
                index = 0;
                continue;
            }
            index += 1;
        }
    }

    fn upload_one(&mut self, queue: &wgpu::Queue, glyph: &EmojiRasterData) -> Option<bool> {
        if glyph.width == 0 || glyph.height == 0 {
            return None;
        }
        let color_pixels = sanitize_emoji_rgba(glyph.width, glyph.height, &glyph.rgba)?;
        let mask_pixels = build_emoji_sdf_mask(glyph.width, glyph.height, &color_pixels);

        let padded_w = glyph
            .width
            .saturating_add(ATLAS_GLYPH_PADDING.saturating_mul(2))
            .max(1);
        let padded_h = glyph
            .height
            .saturating_add(ATLAS_GLYPH_PADDING.saturating_mul(2))
            .max(1);

        if self.cursor_x + padded_w > self.width {
            self.cursor_x = 0;
            self.cursor_y = self.cursor_y.saturating_add(self.row_height);
            self.row_height = 0;
        }
        let mut cleared = false;
        if self.cursor_y + padded_h > self.height {
            self.clear();
            cleared = true;
        }
        if self.cursor_x + padded_w > self.width || self.cursor_y + padded_h > self.height {
            return None;
        }

        let mut padded_color = vec![0u8; (padded_w * padded_h * 4) as usize];
        let mut padded_mask = vec![0u8; (padded_w * padded_h) as usize];
        let src_row_bytes = (glyph.width * 4) as usize;
        let dst_row_bytes = (padded_w * 4) as usize;
        let src_mask_row = glyph.width as usize;
        let dst_mask_row = padded_w as usize;
        let pad_bytes = (ATLAS_GLYPH_PADDING * 4) as usize;
        let pad_mask = ATLAS_GLYPH_PADDING as usize;
        for row in 0..glyph.height as usize {
            let src_start = row * src_row_bytes;
            let src_end = src_start + src_row_bytes;
            let dst_start = (row + ATLAS_GLYPH_PADDING as usize) * dst_row_bytes + pad_bytes;
            let dst_end = dst_start + src_row_bytes;
            padded_color[dst_start..dst_end].copy_from_slice(&color_pixels[src_start..src_end]);

            let src_m_start = row * src_mask_row;
            let src_m_end = src_m_start + src_mask_row;
            let dst_m_start = (row + ATLAS_GLYPH_PADDING as usize) * dst_mask_row + pad_mask;
            let dst_m_end = dst_m_start + src_mask_row;
            padded_mask[dst_m_start..dst_m_end]
                .copy_from_slice(&mask_pixels[src_m_start..src_m_end]);
        }

        queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &self.color_texture,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: self.cursor_x,
                    y: self.cursor_y,
                    z: 0,
                },
                aspect: wgpu::TextureAspect::All,
            },
            &padded_color,
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(padded_w * 4),
                rows_per_image: Some(padded_h),
            },
            wgpu::Extent3d {
                width: padded_w,
                height: padded_h,
                depth_or_array_layers: 1,
            },
        );

        queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &self.mask_texture,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: self.cursor_x,
                    y: self.cursor_y,
                    z: 0,
                },
                aspect: wgpu::TextureAspect::All,
            },
            &padded_mask,
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(padded_w),
                rows_per_image: Some(padded_h),
            },
            wgpu::Extent3d {
                width: padded_w,
                height: padded_h,
                depth_or_array_layers: 1,
            },
        );

        let glyph_x = self.cursor_x + ATLAS_GLYPH_PADDING;
        let glyph_y = self.cursor_y + ATLAS_GLYPH_PADDING;
        let half_texel_u = 0.5 / self.width as f32;
        let half_texel_v = 0.5 / self.height as f32;
        let uv_min = [
            glyph_x as f32 / self.width as f32 + half_texel_u,
            glyph_y as f32 / self.height as f32 + half_texel_v,
        ];
        let uv_max = [
            (glyph_x + glyph.width) as f32 / self.width as f32 - half_texel_u,
            (glyph_y + glyph.height) as f32 / self.height as f32 - half_texel_v,
        ];

        let entry = EmojiAtlasEntry {
            uv_min,
            uv_max,
            mask_uv_min: uv_min,
            mask_uv_max: uv_max,
            width: glyph.width,
            height: glyph.height,
            advance: glyph.advance.max(0.0),
            offset_x: glyph.offset_x,
            offset_y: glyph.offset_y,
        };
        self.entries.insert(glyph.id.clone(), entry);

        self.cursor_x = self.cursor_x.saturating_add(padded_w);
        self.row_height = self.row_height.max(padded_h);
        Some(cleared)
    }
}

struct Next2GlyphAtlas {
    fonts: Vec<FontFaceHandle>,
    texture: wgpu::Texture,
    texture_view: wgpu::TextureView,
    sampler: wgpu::Sampler,
    width: u32,
    height: u32,
    cursor_x: u32,
    cursor_y: u32,
    row_height: u32,
    entries: HashMap<(char, u32), GlyphAtlasEntry>,
    line_ascent_cache: HashMap<u32, f32>,
}

impl Next2GlyphAtlas {
    fn new(device: &wgpu::Device) -> Result<Self, String> {
        let fonts = load_font_chain()?;

        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("next2 msdf atlas"),
            size: wgpu::Extent3d {
                width: BASE_ATLAS_SIZE,
                height: BASE_ATLAS_SIZE,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let texture_view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("next2 msdf sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });

        Ok(Self {
            fonts,
            texture,
            texture_view,
            sampler,
            width: BASE_ATLAS_SIZE,
            height: BASE_ATLAS_SIZE,
            cursor_x: 0,
            cursor_y: 0,
            row_height: 0,
            entries: HashMap::new(),
            line_ascent_cache: HashMap::new(),
        })
    }

    fn clear(&mut self) {
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.row_height = 0;
        self.entries.clear();
    }

    fn line_ascent(&mut self, quantized_size: u32) -> f32 {
        if let Some(cached) = self.line_ascent_cache.get(&quantized_size) {
            return *cached;
        }

        let px = quantized_size as f32;
        let mut ascent = (px * 0.82).max(1.0);
        for font in &self.fonts {
            ascent = ascent.max(scale_metric_to_px(
                font.face.ascender() as f32,
                &font.face,
                px,
            ));
        }

        self.line_ascent_cache.insert(quantized_size, ascent);
        ascent
    }

    fn entry_for(
        &mut self,
        queue: &wgpu::Queue,
        ch: char,
        quantized_size: u32,
    ) -> Option<&GlyphAtlasEntry> {
        let resolved = self.resolve_char(ch);
        let key = (resolved, quantized_size);
        if !self.entries.contains_key(&key) {
            self.rasterize_and_upload(queue, resolved, quantized_size)?;
        }
        self.entries.get(&key)
    }

    fn has_glyph(&self, ch: char) -> bool {
        self.fonts
            .iter()
            .any(|font| font.face.glyph_index(ch).is_some())
    }

    fn resolve_char(&self, ch: char) -> char {
        if self.has_glyph(ch) {
            return ch;
        }
        if ch != MISSING_GLYPH_FALLBACK && self.has_glyph(MISSING_GLYPH_FALLBACK) {
            return MISSING_GLYPH_FALLBACK;
        }
        if self.has_glyph('?') {
            return '?';
        }
        ch
    }

    fn glyph_from_fonts(&self, ch: char, px: f32) -> Option<GlyphMsdfData> {
        for font in &self.fonts {
            let Some(glyph_id) = font.face.glyph_index(ch) else {
                continue;
            };
            let data = glyph_msdf_from_face(&font.face, glyph_id, px)?;
            return Some(data);
        }
        None
    }

    fn rasterize_and_upload(
        &mut self,
        queue: &wgpu::Queue,
        ch: char,
        quantized_size: u32,
    ) -> Option<()> {
        let px = quantized_size as f32;
        let msdf = self.glyph_from_fonts(ch, px)?;

        if msdf.width == 0 || msdf.height == 0 || msdf.pixels.is_empty() {
            self.entries.insert(
                (ch, quantized_size),
                GlyphAtlasEntry {
                    uv_min: [0.0, 0.0],
                    uv_max: [0.0, 0.0],
                    width: 0,
                    height: 0,
                    offset_x: msdf.offset_x,
                    offset_y: 0.0,
                    advance: msdf.advance,
                    spread: 0.0,
                },
            );
            return Some(());
        }

        let padded_w = msdf
            .width
            .saturating_add(ATLAS_GLYPH_PADDING.saturating_mul(2))
            .max(1);
        let padded_h = msdf
            .height
            .saturating_add(ATLAS_GLYPH_PADDING.saturating_mul(2))
            .max(1);

        if self.cursor_x + padded_w > self.width {
            self.cursor_x = 0;
            self.cursor_y = self.cursor_y.saturating_add(self.row_height);
            self.row_height = 0;
        }

        if self.cursor_y + padded_h > self.height {
            self.clear();
        }

        if self.cursor_x + padded_w > self.width || self.cursor_y + padded_h > self.height {
            return None;
        }

        let mut padded_pixels = vec![0u8; (padded_w * padded_h * 4) as usize];
        let src_row_bytes = (msdf.width * 4) as usize;
        let dst_row_bytes = (padded_w * 4) as usize;
        let pad_bytes = (ATLAS_GLYPH_PADDING * 4) as usize;
        for row in 0..msdf.height as usize {
            let src_start = row * src_row_bytes;
            let src_end = src_start + src_row_bytes;
            let dst_start = (row + ATLAS_GLYPH_PADDING as usize) * dst_row_bytes + pad_bytes;
            let dst_end = dst_start + src_row_bytes;
            padded_pixels[dst_start..dst_end].copy_from_slice(&msdf.pixels[src_start..src_end]);
        }

        queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &self.texture,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: self.cursor_x,
                    y: self.cursor_y,
                    z: 0,
                },
                aspect: wgpu::TextureAspect::All,
            },
            &padded_pixels,
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(padded_w * 4),
                rows_per_image: Some(padded_h),
            },
            wgpu::Extent3d {
                width: padded_w,
                height: padded_h,
                depth_or_array_layers: 1,
            },
        );

        let glyph_x = self.cursor_x + ATLAS_GLYPH_PADDING;
        let glyph_y = self.cursor_y + ATLAS_GLYPH_PADDING;
        let half_texel_u = 0.5 / self.width as f32;
        let half_texel_v = 0.5 / self.height as f32;
        let uv_min = [
            glyph_x as f32 / self.width as f32 + half_texel_u,
            glyph_y as f32 / self.height as f32 + half_texel_v,
        ];
        let uv_max = [
            (glyph_x + msdf.width) as f32 / self.width as f32 - half_texel_u,
            (glyph_y + msdf.height) as f32 / self.height as f32 - half_texel_v,
        ];

        let entry = GlyphAtlasEntry {
            uv_min,
            uv_max,
            // Geometry must use real MTSDF bounds. Atlas padding is for sampling
            // isolation only and should not be drawn, otherwise glyph edges blur.
            width: msdf.width,
            height: msdf.height,
            offset_x: msdf.offset_x,
            offset_y: msdf.offset_y,
            advance: msdf.advance,
            spread: msdf.spread,
        };

        self.entries.insert((ch, quantized_size), entry);

        self.cursor_x = self.cursor_x.saturating_add(padded_w);
        self.row_height = self.row_height.max(padded_h);

        Some(())
    }
}

fn scale_metric_to_px(units: f32, face: &Face<'static>, px: f32) -> f32 {
    let units_per_em = face.units_per_em().max(1) as f32;
    units * (px / units_per_em)
}

fn hash_font_bytes(bytes: &[u8], collection_index: u32) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    bytes.hash(&mut hasher);
    collection_index.hash(&mut hasher);
    hasher.finish()
}

fn load_font_chain() -> Result<Vec<FontFaceHandle>, String> {
    let mut fonts = Vec::new();
    let mut seen = HashSet::new();

    let primary_bytes = FONT_DATA.to_vec().into_boxed_slice();
    load_faces_from_owned_bytes(primary_bytes, &mut seen, &mut fonts)?;

    for bytes in NEXT2_FALLBACK_FONTS {
        let boxed = (*bytes).to_vec().into_boxed_slice();
        let _ = load_faces_from_owned_bytes(boxed, &mut seen, &mut fonts);
    }

    if fonts.is_empty() {
        return Err("next2: no usable font faces loaded".to_string());
    }
    Ok(fonts)
}

fn load_faces_from_owned_bytes(
    bytes: Box<[u8]>,
    seen: &mut HashSet<u64>,
    out: &mut Vec<FontFaceHandle>,
) -> Result<(), String> {
    let leaked: &'static [u8] = Box::leak(bytes);
    let face_count = ttf_parser::fonts_in_collection(leaked).unwrap_or(1);
    let face_limit = face_count.max(1).min(MAX_FONT_COLLECTION_FACES);

    for collection_index in 0..face_limit {
        let face = match Face::parse(leaked, collection_index) {
            Ok(face) => face,
            Err(ttf_parser::FaceParsingError::FaceIndexOutOfBounds) => break,
            Err(_) => {
                if collection_index == 0 {
                    return Err("load primary font failed: parse face failed".to_string());
                }
                break;
            }
        };

        let hash = hash_font_bytes(leaked, collection_index);
        if seen.insert(hash) {
            out.push(FontFaceHandle { face });
        }
    }

    Ok(())
}

fn glyph_msdf_from_face(face: &Face<'static>, glyph_id: GlyphId, px: f32) -> Option<GlyphMsdfData> {
    let bbox = face.glyph_bounding_box(glyph_id)?;

    let advance_units = face
        .glyph_hor_advance(glyph_id)
        .map(|v| v as f32)
        .unwrap_or_else(|| face.units_per_em() as f32 * FALLBACK_GLYPH_ADVANCE_RATIO);
    let advance =
        scale_metric_to_px(advance_units, face, px).max(px * FALLBACK_GLYPH_ADVANCE_RATIO);

    let width_units = (bbox.x_max - bbox.x_min).max(0) as f64;
    let height_units = (bbox.y_max - bbox.y_min).max(0) as f64;
    if width_units <= 0.0 || height_units <= 0.0 {
        let side_bearing = face.glyph_hor_side_bearing(glyph_id).unwrap_or(0) as f32;
        return Some(GlyphMsdfData {
            pixels: Vec::new(),
            width: 0,
            height: 0,
            spread: 0.0,
            offset_x: scale_metric_to_px(side_bearing, face, px),
            offset_y: 0.0,
            advance,
        });
    }

    let units_per_em = face.units_per_em().max(1) as f64;
    let px_scale = px as f64 / units_per_em;

    let translated_x = MSDF_RANGE - (bbox.x_min as f64) * px_scale;
    let translated_y = MSDF_RANGE - (bbox.y_min as f64) * px_scale;
    let transform = nalgebra::convert::<_, Affine2<f64>>(Similarity2::new(
        Vector2::new(translated_x, translated_y),
        0.0,
        px_scale,
    ));

    let mut shape: Shape<Contour> = fdsm_ttf_parser::load_shape_from_face(face, glyph_id)?;
    shape.transform(&transform);

    let width = (width_units * px_scale + 2.0 * MSDF_RANGE).ceil().max(1.0) as u32;
    let height = (height_units * px_scale + 2.0 * MSDF_RANGE).ceil().max(1.0) as u32;

    let colored_shape =
        Shape::edge_coloring_simple(shape, EDGE_COLORING_CORNER_THRESHOLD, EDGE_COLORING_SEED);
    let prepared_colored_shape = colored_shape.prepare();

    let mut mtsdf_f32 = Rgba32FImage::new(width, height);
    generate_mtsdf(&prepared_colored_shape, MSDF_RANGE, &mut mtsdf_f32);
    correct_error_mtsdf(
        &mut mtsdf_f32,
        &colored_shape,
        &prepared_colored_shape,
        MSDF_RANGE,
        &ErrorCorrectionConfig::default(),
    );
    correct_sign_mtsdf(&mut mtsdf_f32, &prepared_colored_shape, FillRule::Nonzero);

    let mtsdf_u8: RgbaImage = mtsdf_f32.convert();
    let raw_rgba = mtsdf_u8.into_raw();
    let mut rgba = Vec::with_capacity((width * height * 4) as usize);
    for y in 0..height {
        let src_y = height - 1 - y;
        let row_start = (src_y * width * 4) as usize;
        let row_end = row_start + (width * 4) as usize;
        for chunk in raw_rgba[row_start..row_end].chunks_exact(4) {
            rgba.extend_from_slice(chunk);
        }
    }

    let side_bearing = face.glyph_hor_side_bearing(glyph_id).unwrap_or(0) as f32;
    let offset_x = scale_metric_to_px(side_bearing, face, px) - MSDF_RANGE as f32;

    let ymin = bbox.y_min as f32;
    let height_px = height as f32;
    let offset_y = -height_px + MSDF_RANGE as f32 - scale_metric_to_px(ymin, face, px);

    Some(GlyphMsdfData {
        pixels: rgba,
        width,
        height,
        spread: MSDF_RANGE as f32,
        offset_x,
        offset_y,
        advance,
    })
}

struct Next2Renderer {
    ctx: Arc<EngineDeviceContext>,
    #[cfg(target_os = "android")]
    surface_pipeline: Option<wgpu::RenderPipeline>,
    offscreen_pipeline: wgpu::RenderPipeline,
    blur_pipeline_horizontal: wgpu::RenderPipeline,
    blur_pipeline_vertical: wgpu::RenderPipeline,
    screen_pipeline: wgpu::RenderPipeline,
    atlas_bind_group_layout: wgpu::BindGroupLayout,
    atlas_bind_group: wgpu::BindGroup,
    screen_bind_group_layout: wgpu::BindGroupLayout,
    screen_sampler: wgpu::Sampler,
    atlas: Next2GlyphAtlas,
    emoji_atlas: Next2EmojiAtlas,
    vertex_buffer: wgpu::Buffer,
    vertex_capacity_bytes: usize,
    shadow_vertex_buffer: wgpu::Buffer,
    shadow_vertex_capacity_bytes: usize,
    vertices: Vec<GlyphVertex>,
    shadow_vertices: Vec<GlyphVertex>,
    frame_items: Vec<FrameItem>,
    clear_color: [f64; 4],
    width: u32,
    height: u32,
    offscreen_texture: wgpu::Texture,
    shadow_mask_texture: wgpu::Texture,
    shadow_blur_texture: wgpu::Texture,
    shadow_width: u32,
    shadow_height: u32,
    #[cfg(target_os = "android")]
    surface_format: Option<wgpu::TextureFormat>,
    #[cfg(target_os = "android")]
    surface_screen_pipeline: Option<wgpu::RenderPipeline>,
}

