impl Next2Renderer {
    fn create_pipeline(
        device: &wgpu::Device,
        atlas_bind_group_layout: &wgpu::BindGroupLayout,
        target_format: wgpu::TextureFormat,
        label: &'static str,
    ) -> wgpu::RenderPipeline {
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("next2 sdf shader"),
            source: wgpu::ShaderSource::Wgsl(std::borrow::Cow::Borrowed(NEXT2_WGSL)),
        });
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("next2 pipeline layout"),
            bind_group_layouts: &[atlas_bind_group_layout],
            push_constant_ranges: &[],
        });
        device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some(label),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                buffers: &[GlyphVertex::layout()],
            },
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: None,
                unclipped_depth: false,
                polygon_mode: wgpu::PolygonMode::Fill,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: target_format,
                    blend: Some(wgpu::BlendState::PREMULTIPLIED_ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            multiview: None,
            cache: None,
        })
    }

    fn create_screen_pipeline(
        device: &wgpu::Device,
        screen_bind_group_layout: &wgpu::BindGroupLayout,
        target_format: wgpu::TextureFormat,
        source: &'static str,
        label: &'static str,
    ) -> wgpu::RenderPipeline {
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some(label),
            source: wgpu::ShaderSource::Wgsl(std::borrow::Cow::Borrowed(source)),
        });
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("next2 screen pipeline layout"),
            bind_group_layouts: &[screen_bind_group_layout],
            push_constant_ranges: &[],
        });
        device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some(label),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                buffers: &[],
            },
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: None,
                unclipped_depth: false,
                polygon_mode: wgpu::PolygonMode::Fill,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: target_format,
                    blend: Some(wgpu::BlendState::PREMULTIPLIED_ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            multiview: None,
            cache: None,
        })
    }

    fn new(
        ctx: Arc<EngineDeviceContext>,
        width: u32,
        height: u32,
        custom_font: Option<FontSource>,
    ) -> Result<Self, String> {
        let atlas = Next2GlyphAtlas::new(ctx.device.as_ref(), custom_font)?;

        let atlas_bind_group_layout =
            ctx.device
                .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("next2 atlas bgl"),
                    entries: &[
                        wgpu::BindGroupLayoutEntry {
                            binding: 0,
                            visibility: wgpu::ShaderStages::FRAGMENT,
                            ty: wgpu::BindingType::Texture {
                                sample_type: wgpu::TextureSampleType::Float { filterable: true },
                                view_dimension: wgpu::TextureViewDimension::D2,
                                multisampled: false,
                            },
                            count: None,
                        },
                        wgpu::BindGroupLayoutEntry {
                            binding: 1,
                            visibility: wgpu::ShaderStages::FRAGMENT,
                            ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                            count: None,
                        },
                        wgpu::BindGroupLayoutEntry {
                            binding: 2,
                            visibility: wgpu::ShaderStages::FRAGMENT,
                            ty: wgpu::BindingType::Texture {
                                sample_type: wgpu::TextureSampleType::Float { filterable: true },
                                view_dimension: wgpu::TextureViewDimension::D2,
                                multisampled: false,
                            },
                            count: None,
                        },
                        wgpu::BindGroupLayoutEntry {
                            binding: 3,
                            visibility: wgpu::ShaderStages::FRAGMENT,
                            ty: wgpu::BindingType::Texture {
                                sample_type: wgpu::TextureSampleType::Float { filterable: true },
                                view_dimension: wgpu::TextureViewDimension::D2,
                                multisampled: false,
                            },
                            count: None,
                        },
                        wgpu::BindGroupLayoutEntry {
                            binding: 4,
                            visibility: wgpu::ShaderStages::FRAGMENT,
                            ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                            count: None,
                        },
                    ],
                });

        let screen_bind_group_layout =
            ctx.device
                .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("next2 screen bgl"),
                    entries: &[
                        wgpu::BindGroupLayoutEntry {
                            binding: 0,
                            visibility: wgpu::ShaderStages::FRAGMENT,
                            ty: wgpu::BindingType::Texture {
                                sample_type: wgpu::TextureSampleType::Float { filterable: true },
                                view_dimension: wgpu::TextureViewDimension::D2,
                                multisampled: false,
                            },
                            count: None,
                        },
                        wgpu::BindGroupLayoutEntry {
                            binding: 1,
                            visibility: wgpu::ShaderStages::FRAGMENT,
                            ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                            count: None,
                        },
                    ],
                });

        let emoji_atlas = Next2EmojiAtlas::new(ctx.device.as_ref());

        let atlas_bind_group = ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("next2 atlas bg"),
            layout: &atlas_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&atlas.texture_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&atlas.sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(&emoji_atlas.color_texture_view),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: wgpu::BindingResource::TextureView(&emoji_atlas.mask_texture_view),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: wgpu::BindingResource::Sampler(&emoji_atlas.sampler),
                },
            ],
        });

        let offscreen_pipeline = Self::create_pipeline(
            ctx.device.as_ref(),
            &atlas_bind_group_layout,
            wgpu::TextureFormat::Bgra8Unorm,
            "next2 render pipeline",
        );

        let blur_pipeline_horizontal = Self::create_screen_pipeline(
            ctx.device.as_ref(),
            &screen_bind_group_layout,
            wgpu::TextureFormat::Bgra8Unorm,
            NEXT2_SHADOW_BLUR_HORIZONTAL_WGSL,
            "next2 shadow blur horizontal pipeline",
        );
        let blur_pipeline_vertical = Self::create_screen_pipeline(
            ctx.device.as_ref(),
            &screen_bind_group_layout,
            wgpu::TextureFormat::Bgra8Unorm,
            NEXT2_SHADOW_BLUR_VERTICAL_WGSL,
            "next2 shadow blur vertical pipeline",
        );
        let screen_pipeline = Self::create_screen_pipeline(
            ctx.device.as_ref(),
            &screen_bind_group_layout,
            wgpu::TextureFormat::Bgra8Unorm,
            NEXT2_SCREEN_COPY_WGSL,
            "next2 shadow composite pipeline",
        );

        // Copy pipeline — same shader as screen_pipeline but NO blending.
        // Every pixel from source overwrites destination (including
        // transparent → zero), which is essential for the final blit
        // from offscreen frame_texture to the shared DXGI texture when
        // using LoadOp::Load to avoid flicker.
        let copy_shader = ctx.device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("next2 copy shader"),
            source: wgpu::ShaderSource::Wgsl(std::borrow::Cow::Borrowed(NEXT2_SCREEN_COPY_WGSL)),
        });
        let copy_pipeline_layout = ctx.device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("next2 copy pipeline layout"),
            bind_group_layouts: &[&screen_bind_group_layout],
            push_constant_ranges: &[],
        });
        let copy_pipeline = ctx.device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("next2 copy pipeline"),
            layout: Some(&copy_pipeline_layout),
            vertex: wgpu::VertexState {
                module: &copy_shader,
                entry_point: Some("vs_main"),
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                buffers: &[],
            },
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: None,
                unclipped_depth: false,
                polygon_mode: wgpu::PolygonMode::Fill,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            fragment: Some(wgpu::FragmentState {
                module: &copy_shader,
                entry_point: Some("fs_main"),
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: wgpu::TextureFormat::Bgra8Unorm,
                    blend: None,  // ← NO blending — overwrite every pixel
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            multiview: None,
            cache: None,
        });

        let screen_sampler = ctx.device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("next2 screen sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Nearest,
            lod_min_clamp: 0.0,
            lod_max_clamp: 0.0,
            compare: None,
            anisotropy_clamp: 1,
            border_color: None,
        });

        let vertex_capacity = 4096usize * std::mem::size_of::<GlyphVertex>();
        let vertex_buffer = ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("next2 vertex buffer"),
            size: vertex_capacity as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let shadow_vertex_buffer = ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("next2 shadow vertex buffer"),
            size: vertex_capacity as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let shadow_width = ((width.max(1) as f32) * SHADOW_RENDER_SCALE).max(1.0) as u32;
        let shadow_height = ((height.max(1) as f32) * SHADOW_RENDER_SCALE).max(1.0) as u32;
        let shadow_mask_texture = create_render_texture_with_usage(
            ctx.device.as_ref(),
            shadow_width,
            shadow_height,
            Some("next2 shadow mask texture"),
            wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            wgpu::TextureFormat::Bgra8Unorm,
        );
        let shadow_blur_texture = create_render_texture_with_usage(
            ctx.device.as_ref(),
            shadow_width,
            shadow_height,
            Some("next2 shadow blur texture"),
            wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            wgpu::TextureFormat::Bgra8Unorm,
        );

        let frame_texture_format = wgpu::TextureFormat::Bgra8Unorm;
        let frame_texture = create_render_texture_with_usage(
            ctx.device.as_ref(),
            width.max(1),
            height.max(1),
            Some("next2 frame buffer texture"),
            wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            frame_texture_format,
        );

        Ok(Self {
            ctx,
            #[cfg(target_os = "android")]
            surface_pipeline: None,
            texture_format: wgpu::TextureFormat::Bgra8Unorm,
            texture_pipeline: None,
            texture_screen_pipeline: None,
            offscreen_pipeline,
            blur_pipeline_horizontal,
            blur_pipeline_vertical,
            screen_pipeline,
            copy_pipeline,
            texture_copy_pipeline: None,
            atlas_bind_group_layout,
            atlas_bind_group,
            screen_bind_group_layout,
            screen_sampler,
            atlas,
            emoji_atlas,
            vertex_buffer,
            vertex_capacity_bytes: vertex_capacity,
            shadow_vertex_buffer,
            shadow_vertex_capacity_bytes: vertex_capacity,
            vertices: Vec::new(),
            shadow_vertices: Vec::new(),
            frame_items: Vec::new(),
            clear_color: [0.0, 0.0, 0.0, 0.0],
            width: width.max(1),
            height: height.max(1),
            shadow_mask_texture,
            shadow_blur_texture,
            shadow_width,
            shadow_height,
            frame_texture,
            frame_texture_format,
            #[cfg(target_os = "android")]
            surface_format: None,
            #[cfg(target_os = "android")]
            surface_screen_pipeline: None,
            submit_instant: std::time::Instant::now(),
            interp_dt: 0.0,
            last_submit_instant: None,
            submit_interval_ema: 0.0,
        })
    }

    fn resize(&mut self, width: u32, height: u32) -> bool {
        self.width = width.max(1);
        self.height = height.max(1);
        self.shadow_width = ((self.width as f32) * SHADOW_RENDER_SCALE).max(1.0) as u32;
        self.shadow_height = ((self.height as f32) * SHADOW_RENDER_SCALE).max(1.0) as u32;
        self.shadow_mask_texture = create_render_texture_with_usage(
            self.ctx.device.as_ref(),
            self.shadow_width,
            self.shadow_height,
            Some("next2 shadow mask texture"),
            wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            wgpu::TextureFormat::Bgra8Unorm,
        );
        self.shadow_blur_texture = create_render_texture_with_usage(
            self.ctx.device.as_ref(),
            self.shadow_width,
            self.shadow_height,
            Some("next2 shadow blur texture"),
            wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            wgpu::TextureFormat::Bgra8Unorm,
        );
        self.frame_texture = create_render_texture_with_usage(
            self.ctx.device.as_ref(),
            self.width,
            self.height,
            Some("next2 frame buffer texture"),
            wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
            self.frame_texture_format,
        );
        true
    }

    fn reset_scene(&mut self) {
        self.frame_items.clear();
        self.vertices.clear();
        self.shadow_vertices.clear();
        self.atlas.clear();
        self.emoji_atlas.clear();
    }

    /// Drain completed async prefetch results and upload to the atlas. Called
    /// at the top of each engine loop iteration so prefetched glyphs land in
    /// the atlas before the next draw.
    pub(crate) fn drain_prefetch(&mut self, queue: &wgpu::Queue) {
        self.atlas.drain_prefetch(queue);
    }

    fn update_frame(&mut self, input: RenderFrameInput, custom_font: Option<FontSource>) -> bool {
        let parsed = match serde_json::from_str::<FramePayload>(&input.frame_json) {
            Ok(parsed) => parsed,
            Err(_) => return false,
        };

        let font_key = custom_font_key(custom_font.as_ref());
        if self.atlas.font_key != font_key {
            let Ok(atlas) = Next2GlyphAtlas::new(self.ctx.device.as_ref(), custom_font) else {
                return false;
            };
            self.atlas = atlas;
            self.rebuild_atlas_bind_group();
        }

        let emoji_rasters = decode_emoji_rasters(parsed.emoji_glyphs.as_deref().unwrap_or(&[]));
        if !emoji_rasters.is_empty() {
            self.emoji_atlas
                .upload_glyphs(self.ctx.queue.as_ref(), &emoji_rasters);
        }

        self.frame_items.clear();
        self.frame_items.reserve(parsed.items.len());

        let opacity = input.opacity.clamp(0.0, 1.0);
        let outline_width = if input.outline_width.is_finite() {
            input.outline_width.clamp(0.0, 4.0)
        } else {
            0.0
        };
        let shadow_style = input.shadow_style;
        let font_size = input.font_size.max(1.0);

        for item in parsed.items {
            let tokens =
                normalize_tokens(item.tokens, item.text.as_str(), item.count_text.as_deref());
            self.frame_items.push(FrameItem {
                tokens,
                x: item.x,
                y: item.y,
                color_argb: item.color_argb,
                font_size: (font_size as f64 * item.font_size_multiplier.max(0.5)) as f32,
                outline_width,
                shadow_style,
                opacity,
                scroll_speed: item.scroll_speed as f32,
            });
        }

        // Prefetch-rasterize lookahead chars asynchronously. Workers run the
        // full pipeline off the render thread; results drain into the atlas
        // at the top of the next loop iteration. Deduplicated by `pending`.
        if let Some(chars) = &parsed.prefetch_chars {
            let qz = font_size.round().clamp(8.0, 256.0) as u32;
            for ch in chars.chars() {
                self.atlas.request_rasterize(ch, qz);
            }
        }

        // Re-baseline the interpolation clock to this submission. The render
        // thread's idle-tick re-renders will advance scroll items from this
        // instant until the next setFrame arrives (~16-33ms later at 60/30fps
        // Dart submission). The 50ms cap in build_vertices freezes motion if
        // no new frame arrives (pause / upstream stall).
        let now = std::time::Instant::now();
        if let Some(prev) = self.last_submit_instant {
            let interval = now.duration_since(prev).as_secs_f32();
            // Clamp outlier intervals (seek / pause-resume) so they don't
            // poison the EMA — only steady-state cadence drives the gate.
            let clamped = interval.min(0.200);
            self.submit_interval_ema = 0.2 * clamped + 0.8 * self.submit_interval_ema;
        }
        self.last_submit_instant = Some(now);
        self.submit_instant = now;

        true
    }

    fn rebuild_atlas_bind_group(&mut self) {
        self.atlas_bind_group = self
            .ctx
            .device
            .create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("next2 atlas bg"),
                layout: &self.atlas_bind_group_layout,
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: wgpu::BindingResource::TextureView(&self.atlas.texture_view),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: wgpu::BindingResource::Sampler(&self.atlas.sampler),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: wgpu::BindingResource::TextureView(
                            &self.emoji_atlas.color_texture_view,
                        ),
                    },
                    wgpu::BindGroupEntry {
                        binding: 3,
                        resource: wgpu::BindingResource::TextureView(
                            &self.emoji_atlas.mask_texture_view,
                        ),
                    },
                    wgpu::BindGroupEntry {
                        binding: 4,
                        resource: wgpu::BindingResource::Sampler(&self.emoji_atlas.sampler),
                    },
                ],
            });
    }

    fn draw_to_present(&mut self, present: &mut PresentTarget) {
        match present {
            #[cfg(target_os = "android")]
            PresentTarget::Surface(surface) => {
                let surface_format = surface.format();
                if self.surface_format != Some(surface_format) || self.surface_pipeline.is_none() {
                    self.surface_pipeline = Some(Self::create_pipeline(
                        self.ctx.device.as_ref(),
                        &self.atlas_bind_group_layout,
                        surface_format,
                        "next2 android surface render pipeline",
                    ));
                    self.surface_screen_pipeline = Some(Self::create_screen_pipeline(
                        self.ctx.device.as_ref(),
                        &self.screen_bind_group_layout,
                        surface_format,
                        NEXT2_SCREEN_COPY_WGSL,
                        "next2 android surface composite pipeline",
                    ));
                    self.surface_format = Some(surface_format);
                }
                self.width = surface.width().max(1);
                self.height = surface.height().max(1);
                let acquire_start = std::time::Instant::now();
                let frame = match surface.surface().get_current_texture() {
                    Ok(frame) => frame,
                    Err(wgpu::SurfaceError::Outdated | wgpu::SurfaceError::Lost) => {
                        let _ = surface.recreate(self.ctx.device.as_ref());
                        return;
                    }
                    Err(wgpu::SurfaceError::Timeout) => return,
                    Err(wgpu::SurfaceError::OutOfMemory) => return,
                    Err(wgpu::SurfaceError::Other) => return,
                };
                let acquire_ms = acquire_start.elapsed().as_secs_f32() * 1000.0;
                let view = frame
                    .texture
                    .create_view(&wgpu::TextureViewDescriptor::default());
                let glyph_pipeline = self.surface_pipeline.as_ref().unwrap().clone();
                let screen_pipeline = self.surface_screen_pipeline.as_ref().unwrap().clone();
                let render_start = std::time::Instant::now();
                self.draw_to_view(&view, &glyph_pipeline, &screen_pipeline, surface_format);
                let render_ms = render_start.elapsed().as_secs_f32() * 1000.0;
                let present_start = std::time::Instant::now();
                frame.present();
                let present_ms = present_start.elapsed().as_secs_f32() * 1000.0;
                // Diagnostics: per-60-frame avg of acquire/render/present to locate
                // the ~16ms draw bottleneck on Android. acquire = get_current_texture
                // (swapchain/vsync), render = GPU glyph pass, present = queue submit.
                static T_N: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
                static T_ACQ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
                static T_REN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
                static T_PRES: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
                T_N.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                T_ACQ.fetch_add((acquire_ms * 1000.0) as u64, std::sync::atomic::Ordering::Relaxed);
                T_REN.fetch_add((render_ms * 1000.0) as u64, std::sync::atomic::Ordering::Relaxed);
                T_PRES.fetch_add((present_ms * 1000.0) as u64, std::sync::atomic::Ordering::Relaxed);
                let n = T_N.load(std::sync::atomic::Ordering::Relaxed);
                if n >= 60 {
                    n2log(&format!(
                        "DFM+ timing: acquire={:.2}ms render={:.2}ms present={:.2}ms",
                        T_ACQ.load(std::sync::atomic::Ordering::Relaxed) as f32 / 1000.0 / n as f32,
                        T_REN.load(std::sync::atomic::Ordering::Relaxed) as f32 / 1000.0 / n as f32,
                        T_PRES.load(std::sync::atomic::Ordering::Relaxed) as f32 / 1000.0 / n as f32,
                    ));
                    T_N.store(0, std::sync::atomic::Ordering::Relaxed);
                    T_ACQ.store(0, std::sync::atomic::Ordering::Relaxed);
                    T_REN.store(0, std::sync::atomic::Ordering::Relaxed);
                    T_PRES.store(0, std::sync::atomic::Ordering::Relaxed);
                }
            }
            PresentTarget::Texture(texture_target) => {
                self.width = texture_target.width.max(1);
                self.height = texture_target.height.max(1);
                let target_format = texture_target.format();
                let (glyph_pipeline, screen_pipeline) = if target_format == wgpu::TextureFormat::Bgra8Unorm {
                    (self.offscreen_pipeline.clone(), self.screen_pipeline.clone())
                } else {
                    if self.texture_format != target_format
                        || self.texture_pipeline.is_none()
                        || self.texture_screen_pipeline.is_none()
                    {
                        self.texture_pipeline = Some(Self::create_pipeline(
                            self.ctx.device.as_ref(),
                            &self.atlas_bind_group_layout,
                            target_format,
                            "next2 texture render pipeline",
                        ));
                        self.texture_screen_pipeline = Some(Self::create_screen_pipeline(
                            self.ctx.device.as_ref(),
                            &self.screen_bind_group_layout,
                            target_format,
                            NEXT2_SCREEN_COPY_WGSL,
                            "next2 texture composite pipeline",
                        ));
                        self.texture_format = target_format;
                    }
                    (
                        self.texture_pipeline.as_ref().unwrap().clone(),
                        self.texture_screen_pipeline.as_ref().unwrap().clone(),
                    )
                };
                let view = texture_target.render_texture().create_view(
                    &wgpu::TextureViewDescriptor {
                        format: Some(target_format),
                        ..Default::default()
                    },
                );
                self.draw_to_view(&view, &glyph_pipeline, &screen_pipeline, target_format);
            }
        }
    }
}
