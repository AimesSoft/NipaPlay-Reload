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

/// A free rectangular region in the atlas, available for reuse after LRU eviction.
#[derive(Clone, Copy)]
struct FreeRect {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
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
    /// Monotonically increasing frame counter at last access (LRU tracking).
    last_used: u64,
    /// Padded position in atlas texture (for recycling into free_list on eviction).
    atlas_x: u32,
    atlas_y: u32,
    padded_w: u32,
    padded_h: u32,
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
    font_key: String,
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
    /// Free regions recycled from LRU-evicted entries, sorted by area (smallest first).
    free_list: Vec<FreeRect>,
    /// Monotonically increasing frame counter for LRU eviction.
    frame_counter: u64,
}

impl Next2GlyphAtlas {
    fn new(device: &wgpu::Device, custom_font: Option<FontSource>) -> Result<Self, String> {
        let font_key = custom_font_key(custom_font.as_ref());
        let fonts = load_font_chain(custom_font)?;

        let max_dim = device.limits().max_texture_dimension_2d;
        let atlas_size = BASE_ATLAS_SIZE.min(max_dim);

        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("next2 msdf atlas"),
            size: wgpu::Extent3d {
                width: atlas_size,
                height: atlas_size,
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
            font_key,
            fonts,
            texture,
            texture_view,
            sampler,
            width: atlas_size,
            height: atlas_size,
            cursor_x: 0,
            cursor_y: 0,
            row_height: 0,
            entries: HashMap::new(),
            line_ascent_cache: HashMap::new(),
            free_list: Vec::new(),
            frame_counter: 0,
        })
    }

    fn clear(&mut self) {
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.row_height = 0;
        self.entries.clear();
        self.line_ascent_cache.clear();
        self.free_list.clear();
    }

    /// Try to find a free rect that fits (w, h). Prefers the smallest-fitting
    /// rect to minimise fragmentation. Returns the chosen rect index and its
    /// (x, y) position.
    fn alloc_atlas_space(&mut self, w: u32, h: u32) -> Option<(u32, u32, usize)> {
        // Search free_list for the smallest rect that fits (best-fit).
        let mut best_idx: Option<usize> = None;
        let mut best_area = u64::MAX;
        for (i, rect) in self.free_list.iter().enumerate() {
            if rect.w >= w && rect.h >= h {
                let area = (rect.w as u64) * (rect.h as u64);
                if area < best_area {
                    best_area = area;
                    best_idx = Some(i);
                    if area == (w as u64) * (h as u64) {
                        break; // perfect fit
                    }
                }
            }
        }

        if let Some(idx) = best_idx {
            let rect = self.free_list.swap_remove(idx);
            let x = rect.x;
            let y = rect.y;

            // Split remaining space: right strip and bottom strip.
            if rect.w > w {
                self.free_list.push(FreeRect {
                    x: rect.x + w,
                    y: rect.y,
                    w: rect.w - w,
                    h,
                });
            }
            if rect.h > h {
                self.free_list.push(FreeRect {
                    x: rect.x,
                    y: rect.y + h,
                    w,
                    h: rect.h - h,
                });
            }
            // Sort by area (ascending) to keep best-fit fast.
            self.free_list
                .sort_unstable_by_key(|r| (r.w as u64) * (r.h as u64));
            return Some((x, y, idx));
        }
        None
    }

    /// Evict the oldest 25% of entries (LRU) and recycle their atlas space
    /// into the free_list. This avoids the full-clear cascade where ALL visible
    /// characters must be re-rasterized at once.
    fn evict_oldest(&mut self) {
        if self.entries.len() < 16 {
            self.clear();
            return;
        }

        // Collect last_used values and find the 25th percentile.
        let mut ages: Vec<u64> = self.entries.values().map(|e| e.last_used).collect();
        ages.sort_unstable();
        let threshold = ages[ages.len() / 4];

        // Recycle evicted entries' atlas space into free_list.
        self.entries.retain(|_, entry| {
            if entry.last_used <= threshold {
                if entry.padded_w > 0 && entry.padded_h > 0 {
                    self.free_list.push(FreeRect {
                        x: entry.atlas_x,
                        y: entry.atlas_y,
                        w: entry.padded_w,
                        h: entry.padded_h,
                    });
                }
                false // remove
            } else {
                true // keep
            }
        });

        // Merge adjacent free rects to reduce fragmentation.
        self.free_list
            .sort_unstable_by_key(|r| (r.y, r.x));
        let mut i = 0;
        while i < self.free_list.len() {
            let mut merged = false;
            let mut j = i + 1;
            while j < self.free_list.len() {
                let a = self.free_list[i];
                let b = self.free_list[j];
                // Same row and adjacent horizontally?
                if a.y == b.y && a.h == b.h && a.x + a.w == b.x {
                    self.free_list[i].w += b.w;
                    self.free_list.swap_remove(j);
                    merged = true;
                } else {
                    j += 1;
                }
            }
            if !merged {
                i += 1;
            }
        }
        // Re-sort by area for best-fit allocation.
        self.free_list
            .sort_unstable_by_key(|r| (r.w as u64) * (r.h as u64));

        // Reset cursor — new glyphs will prefer free_list first, then cursor.
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.row_height = 0;
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
        self.frame_counter = self.frame_counter.wrapping_add(1);
        let resolved = self.resolve_char(ch);
        let key = (resolved, quantized_size);
        if self.entries.contains_key(&key) {
            self.entries.get_mut(&key).unwrap().last_used = self.frame_counter;
            return self.entries.get(&key);
        }
        self.rasterize_and_upload(queue, resolved, quantized_size)?;
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
                    last_used: self.frame_counter,
                    atlas_x: 0,
                    atlas_y: 0,
                    padded_w: 0,
                    padded_h: 0,
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

        // Try free_list first (recycled space from evicted entries).
        let (atlas_x, atlas_y) = if let Some((x, y, _)) = self.alloc_atlas_space(padded_w, padded_h) {
            (x, y)
        } else {
            // Fall back to cursor-based allocation.
            if self.cursor_x + padded_w > self.width {
                self.cursor_x = 0;
                self.cursor_y = self.cursor_y.saturating_add(self.row_height);
                self.row_height = 0;
            }

            if self.cursor_y + padded_h > self.height {
                self.evict_oldest();
                // Retry free_list after eviction.
                if let Some((x, y, _)) = self.alloc_atlas_space(padded_w, padded_h) {
                    (x, y)
                } else {
                    // Cursor was reset; try cursor path again.
                    if self.cursor_x + padded_w > self.width {
                        self.cursor_x = 0;
                        self.cursor_y = self.cursor_y.saturating_add(self.row_height);
                        self.row_height = 0;
                    }
                    if self.cursor_y + padded_h > self.height {
                        return None;
                    }
                    let x = self.cursor_x;
                    let y = self.cursor_y;
                    self.cursor_x = self.cursor_x.saturating_add(padded_w);
                    self.row_height = self.row_height.max(padded_h);
                    (x, y)
                }
            } else {
                let x = self.cursor_x;
                let y = self.cursor_y;
                self.cursor_x = self.cursor_x.saturating_add(padded_w);
                self.row_height = self.row_height.max(padded_h);
                (x, y)
            }
        };

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
                    x: atlas_x,
                    y: atlas_y,
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

        let glyph_x = atlas_x + ATLAS_GLYPH_PADDING;
        let glyph_y = atlas_y + ATLAS_GLYPH_PADDING;
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
            width: msdf.width,
            height: msdf.height,
            offset_x: msdf.offset_x,
            offset_y: msdf.offset_y,
            advance: msdf.advance,
            spread: msdf.spread,
            last_used: self.frame_counter,
            atlas_x,
            atlas_y,
            padded_w,
            padded_h,
        };

        self.entries.insert((ch, quantized_size), entry);

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

fn load_font_chain(custom_font: Option<FontSource>) -> Result<Vec<FontFaceHandle>, String> {
    let mut fonts = Vec::new();
    let mut seen = HashSet::new();

    if let Some(custom_font) = custom_font {
        let boxed = custom_font.bytes;
        let _ = load_faces_from_owned_bytes(boxed, &mut seen, &mut fonts)?;
    }

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

fn custom_font_key(custom_font: Option<&FontSource>) -> String {
    match custom_font {
        Some(font) => {
            let mut hasher = std::collections::hash_map::DefaultHasher::new();
            font.family.hash(&mut hasher);
            font.bytes.hash(&mut hasher);
            format!("{}:{:x}", font.family, hasher.finish())
        }
        None => String::new(),
    }
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
    #[cfg(debug_assertions)]
    n2log(&format!("glyph_msdf: glyph_id={}, px={}", glyph_id.0, px));
    let advance_units = face
        .glyph_hor_advance(glyph_id)
        .map(|v| v as f32)
        .unwrap_or_else(|| face.units_per_em() as f32 * FALLBACK_GLYPH_ADVANCE_RATIO);
    let advance =
        scale_metric_to_px(advance_units, face, px).max(px * FALLBACK_GLYPH_ADVANCE_RATIO);

    let Some(bbox) = face.glyph_bounding_box(glyph_id) else {
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
    };

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
    #[cfg(debug_assertions)]
    n2log("glyph_msdf: shape loaded");
    shape.transform(&transform);

    let width = (width_units * px_scale + 2.0 * MSDF_RANGE).ceil().max(1.0) as u32;
    let height = (height_units * px_scale + 2.0 * MSDF_RANGE).ceil().max(1.0) as u32;

    let colored_shape =
        Shape::edge_coloring_simple(shape, EDGE_COLORING_CORNER_THRESHOLD, EDGE_COLORING_SEED);
    #[cfg(debug_assertions)]
    n2log("glyph_msdf: edge colored");
    let prepared_colored_shape = colored_shape.prepare();

    // fdsm 0.8.0 generate_mtsdf / correct_sign_mtsdf can hang on certain glyphs.
    // Run in a separate thread with a timeout to prevent permanent deadlock.
    #[cfg(debug_assertions)]
    n2log(&format!("glyph_msdf: generating {}x{}", width, height));
    let (tx, rx) = std::sync::mpsc::channel();
    let _worker = std::thread::Builder::new()
        .name("next2-msdf".into())
        .spawn(move || {
            let mut mtsdf_f32 = Rgba32FImage::new(width, height);
            generate_mtsdf(&prepared_colored_shape, MSDF_RANGE, &mut mtsdf_f32);
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
            let _ = tx.send(rgba);
        });

    let result = match rx.recv_timeout(std::time::Duration::from_secs(2)) {
        Ok(pixels) => {
            #[cfg(debug_assertions)]
            n2log("glyph_msdf: done");
            Some(pixels)
        }
        Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
            n2log(&format!("glyph_msdf: TIMEOUT glyph_id={}", glyph_id.0));
            None
        }
        Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
            n2log(&format!("glyph_msdf: CRASH glyph_id={}", glyph_id.0));
            None
        }
    };

    let Some(rgba) = result else {
        return None;
    };

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
    texture_format: wgpu::TextureFormat,
    texture_pipeline: Option<wgpu::RenderPipeline>,
    texture_screen_pipeline: Option<wgpu::RenderPipeline>,
    offscreen_pipeline: wgpu::RenderPipeline,
    blur_pipeline_horizontal: wgpu::RenderPipeline,
    blur_pipeline_vertical: wgpu::RenderPipeline,
    screen_pipeline: wgpu::RenderPipeline,
    /// Copy pipeline for Bgra8Unorm: identical to screen_pipeline but with NO blending.
    /// Used for the final atomic blit from offscreen frame_texture to the
    /// shared DXGI texture.  Without blending, every pixel is overwritten
    /// (transparent source pixels → zero/cleared), preventing "ghost"
    /// danmaku from lingering on target_view when using LoadOp::Load.
    copy_pipeline: wgpu::RenderPipeline,
    /// Copy pipeline for non-Bgra8Unorm target formats (e.g. Rgba8Unorm on Android).
    /// Lazily created when a non-Bgra8Unorm target is encountered.
    texture_copy_pipeline: Option<wgpu::RenderPipeline>,
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
    /// Monotonic instant captured when the most recent frame was submitted
    /// (in `update_frame`). Used by `build_vertices` to interpolate scroll
    /// item x between Dart submissions: `x_render = x + scroll_speed * dt`,
    /// where `dt = submit_instant.elapsed()` capped at 50ms.
    submit_instant: std::time::Instant,
    /// Interpolation delta (seconds) for the current draw. Recomputed at the
    /// top of `build_vertices` from `submit_instant`. 0 when paused/stalled
    /// (>50ms since last submit) so motion freezes on the last submission.
    interp_dt: f32,
    /// Previous submission instant, used to measure the Dart submit interval.
    last_submit_instant: Option<std::time::Instant>,
    /// Exponential moving average of the Dart submit interval (seconds).
    /// Gates idle-tick interpolation: when Dart sustains ~1 submit/tick
    /// (ema < 20ms, i.e. healthy 60fps), idle interp is disabled to avoid
    /// double-rendering phase jitter (visible as 时快时慢 speed variation).
    /// Enabled only when Dart feeds slower than the tick (~30fps submit).
    submit_interval_ema: f32,
    width: u32,
    height: u32,
    shadow_mask_texture: wgpu::Texture,
    shadow_blur_texture: wgpu::Texture,
    shadow_width: u32,
    shadow_height: u32,
    /// Offscreen frame buffer: all rendering (shadow + glyphs) completes here
    /// first, then a single atomic blit copies the finished frame to the
    /// shared texture (target_view).  This prevents Flutter's compositor
    /// from reading a partially-rendered frame via ALLOW_SIMULTANEOUS_ACCESS.
    frame_texture: wgpu::Texture,
    /// The texture format of frame_texture.  Must match the target_format
    /// passed to draw_to_view so that pipeline color target formats align
    /// with the attachment view format (required by wgpu validation).
    frame_texture_format: wgpu::TextureFormat,
    #[cfg(target_os = "android")]
    surface_format: Option<wgpu::TextureFormat>,
    #[cfg(target_os = "android")]
    surface_screen_pipeline: Option<wgpu::RenderPipeline>,
}
