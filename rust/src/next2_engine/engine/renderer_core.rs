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

        let offscreen_texture = create_render_texture(
            ctx.device.as_ref(),
            width.max(1),
            height.max(1),
            Some("next2 offscreen texture"),
        );
        let shadow_width = width.max(1).saturating_mul(SHADOW_RENDER_SCALE);
        let shadow_height = height.max(1).saturating_mul(SHADOW_RENDER_SCALE);
        let shadow_mask_texture = create_render_texture_with_usage(
            ctx.device.as_ref(),
            shadow_width,
            shadow_height,
            Some("next2 shadow mask texture"),
            wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
        );
        let shadow_blur_texture = create_render_texture_with_usage(
            ctx.device.as_ref(),
            shadow_width,
            shadow_height,
            Some("next2 shadow blur texture"),
            wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
        );

        Ok(Self {
            ctx,
            #[cfg(target_os = "android")]
            surface_pipeline: None,
            offscreen_pipeline,
            blur_pipeline_horizontal,
            blur_pipeline_vertical,
            screen_pipeline,
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
            offscreen_texture,
            shadow_mask_texture,
            shadow_blur_texture,
            shadow_width,
            shadow_height,
            #[cfg(target_os = "android")]
            surface_format: None,
            #[cfg(target_os = "android")]
            surface_screen_pipeline: None,
        })
    }

    fn resize(&mut self, width: u32, height: u32) -> bool {
        self.width = width.max(1);
        self.height = height.max(1);
        self.offscreen_texture = create_render_texture(
            self.ctx.device.as_ref(),
            self.width,
            self.height,
            Some("next2 offscreen texture"),
        );
        self.shadow_width = self.width.saturating_mul(SHADOW_RENDER_SCALE);
        self.shadow_height = self.height.saturating_mul(SHADOW_RENDER_SCALE);
        self.shadow_mask_texture = create_render_texture_with_usage(
            self.ctx.device.as_ref(),
            self.shadow_width,
            self.shadow_height,
            Some("next2 shadow mask texture"),
            wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
        );
        self.shadow_blur_texture = create_render_texture_with_usage(
            self.ctx.device.as_ref(),
            self.shadow_width,
            self.shadow_height,
            Some("next2 shadow blur texture"),
            wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
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
            });
        }

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
                let view = frame
                    .texture
                    .create_view(&wgpu::TextureViewDescriptor::default());
                let glyph_pipeline = self.surface_pipeline.as_ref().unwrap().clone();
                let screen_pipeline = self.surface_screen_pipeline.as_ref().unwrap().clone();
                self.draw_to_view(&view, &glyph_pipeline, &screen_pipeline);
                frame.present();
            }
            PresentTarget::Texture(texture_target) => {
                self.width = texture_target.width.max(1);
                self.height = texture_target.height.max(1);
                let glyph_pipeline = self.offscreen_pipeline.clone();
                let screen_pipeline = self.screen_pipeline.clone();
                let offscreen_view =
                    self.offscreen_texture
                        .create_view(&wgpu::TextureViewDescriptor {
                            format: Some(wgpu::TextureFormat::Bgra8Unorm),
                            ..Default::default()
                        });
                self.draw_to_view(&offscreen_view, &glyph_pipeline, &screen_pipeline);

                let mut encoder =
                    self.ctx
                        .device
                        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("next2 present blit encoder"),
                        });
                encoder.copy_texture_to_texture(
                    wgpu::TexelCopyTextureInfo {
                        texture: &self.offscreen_texture,
                        mip_level: 0,
                        origin: wgpu::Origin3d::ZERO,
                        aspect: wgpu::TextureAspect::All,
                    },
                    wgpu::TexelCopyTextureInfo {
                        texture: texture_target.render_texture(),
                        mip_level: 0,
                        origin: wgpu::Origin3d::ZERO,
                        aspect: wgpu::TextureAspect::All,
                    },
                    wgpu::Extent3d {
                        width: self.width.max(1),
                        height: self.height.max(1),
                        depth_or_array_layers: 1,
                    },
                );
                self.ctx.queue.submit(std::iter::once(encoder.finish()));
            }
        }
    }

    fn draw_to_offscreen(&mut self) {
        let view = self
            .offscreen_texture
            .create_view(&wgpu::TextureViewDescriptor {
                format: Some(wgpu::TextureFormat::Bgra8Unorm),
                ..Default::default()
            });
        let glyph_pipeline = self.offscreen_pipeline.clone();
        let screen_pipeline = self.screen_pipeline.clone();
        self.draw_to_view(&view, &glyph_pipeline, &screen_pipeline);
    }

    fn readback_frame_bgra(&mut self) -> Option<Next2ReadbackFrame> {
        self.draw_to_offscreen();

        let width = self.width.max(1);
        let height = self.height.max(1);
        let bytes_per_pixel = 4u32;
        let unpadded_bytes_per_row = width.checked_mul(bytes_per_pixel)?;
        let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
        let padded_bytes_per_row = unpadded_bytes_per_row.div_ceil(align) * align;
        let output_size = padded_bytes_per_row.checked_mul(height)? as u64;

        let output_buffer = self.ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("next2 readback buffer"),
            size: output_size,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });

        let mut encoder = self
            .ctx
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("next2 readback encoder"),
            });
        encoder.copy_texture_to_buffer(
            wgpu::TexelCopyTextureInfo {
                texture: &self.offscreen_texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::TexelCopyBufferInfo {
                buffer: &output_buffer,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(padded_bytes_per_row),
                    rows_per_image: Some(height),
                },
            },
            wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
        );
        self.ctx.queue.submit(std::iter::once(encoder.finish()));

        let slice = output_buffer.slice(..);
        let (tx, rx) = mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = tx.send(result.is_ok());
        });
        let _ = self.ctx.device.poll(wgpu::PollType::wait_indefinitely());
        if rx.recv().ok()? != true {
            return None;
        }

        let mapped = slice.get_mapped_range();
        let mut pixels = vec![0u8; unpadded_bytes_per_row.checked_mul(height)? as usize];
        for row in 0..height as usize {
            let src_start = row * padded_bytes_per_row as usize;
            let src_end = src_start + unpadded_bytes_per_row as usize;
            let dst_start = row * unpadded_bytes_per_row as usize;
            let dst_end = dst_start + unpadded_bytes_per_row as usize;
            pixels[dst_start..dst_end].copy_from_slice(&mapped[src_start..src_end]);
        }
        drop(mapped);
        output_buffer.unmap();

        Some(Next2ReadbackFrame {
            width,
            height,
            pixels,
        })
    }
}
