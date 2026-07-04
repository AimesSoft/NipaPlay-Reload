impl Next2Renderer {
    fn draw_to_view(
        &mut self,
        target_view: &wgpu::TextureView,
        glyph_pipeline: &wgpu::RenderPipeline,
        screen_pipeline: &wgpu::RenderPipeline,
        target_format: wgpu::TextureFormat,
    ) {
        // Ensure frame_texture format matches target_format so that pipeline
        // color target formats align with the attachment view format (required
        // by wgpu validation).  Recreate if format changed (e.g. Bgra8Unorm on
        // Windows/macOS vs Rgba8Unorm on Android).
        if self.frame_texture_format != target_format {
            self.frame_texture = create_render_texture_with_usage(
                self.ctx.device.as_ref(),
                self.width,
                self.height,
                Some("next2 frame buffer texture"),
                wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
                target_format,
            );
            self.frame_texture_format = target_format;
        }
        if self.shadow_mask_texture.size().width != self.shadow_width
            || self.shadow_mask_texture.size().height != self.shadow_height
            || self.shadow_blur_texture.size().width != self.shadow_width
            || self.shadow_blur_texture.size().height != self.shadow_height
        {
            let _ = self.resize(self.width, self.height);
        }

        self.build_vertices();

        if self.vertices.is_empty() {
            self.clear_target_view(target_view);
            return;
        }

        self.ensure_vertex_capacity();
        let mut encoder = self
            .ctx
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("next2 frame render encoder"),
            });

        // ── Phase 1: render the complete frame into frame_texture (offscreen) ──
        // frame_texture is a private texture that Flutter cannot read, so
        // intermediate states (e.g. shadow-only before glyphs are drawn) are
        // invisible to the compositor.  This eliminates the flickering caused
        // by ALLOW_SIMULTANEOUS_ACCESS on the shared DXGI texture.

        let frame_view = self
            .frame_texture
            .create_view(&wgpu::TextureViewDescriptor::default());

        if !self.shadow_vertices.is_empty() {
            let shadow_mask_view = self
                .shadow_mask_texture
                .create_view(&wgpu::TextureViewDescriptor::default());
            let shadow_blur_view = self
                .shadow_blur_texture
                .create_view(&wgpu::TextureViewDescriptor::default());

            let shadow_bytes = bytemuck::cast_slice(self.shadow_vertices.as_slice());
            self.ctx
                .queue
                .write_buffer(&self.shadow_vertex_buffer, 0, shadow_bytes);
            {
                let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("next2 shadow mask pass"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        view: &shadow_mask_view,
                        depth_slice: None,
                        resolve_target: None,
                        ops: wgpu::Operations {
                            load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                            store: wgpu::StoreOp::Store,
                        },
                    })],
                    depth_stencil_attachment: None,
                    timestamp_writes: None,
                    occlusion_query_set: None,
                });

                let shadow_pipeline = self.offscreen_pipeline.clone();
                pass.set_pipeline(&shadow_pipeline);
                pass.set_bind_group(0, &self.atlas_bind_group, &[]);
                pass.set_vertex_buffer(0, self.shadow_vertex_buffer.slice(..));
                pass.draw(0..self.shadow_vertices.len() as u32, 0..1);
            }

            let blur_pipeline_horizontal = self.blur_pipeline_horizontal.clone();
            let blur_pipeline_vertical = self.blur_pipeline_vertical.clone();
            Self::blit_screen_texture(
                self.ctx.device.as_ref(),
                &self.screen_bind_group_layout,
                &self.screen_sampler,
                &mut encoder,
                &shadow_mask_view,
                &shadow_blur_view,
                &blur_pipeline_horizontal,
            );
            Self::blit_screen_texture(
                self.ctx.device.as_ref(),
                &self.screen_bind_group_layout,
                &self.screen_sampler,
                &mut encoder,
                &shadow_blur_view,
                &shadow_mask_view,
                &blur_pipeline_vertical,
            );

            {
                let blur_bind_group =
                    self.ctx
                        .device
                        .create_bind_group(&wgpu::BindGroupDescriptor {
                            label: Some("next2 shadow composite bg"),
                            layout: &self.screen_bind_group_layout,
                            entries: &[
                                wgpu::BindGroupEntry {
                                    binding: 0,
                                    resource: wgpu::BindingResource::TextureView(&shadow_mask_view),
                                },
                                wgpu::BindGroupEntry {
                                    binding: 1,
                                    resource: wgpu::BindingResource::Sampler(&self.screen_sampler),
                                },
                            ],
                        });

                let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("next2 shadow composite pass"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        view: &frame_view,
                        depth_slice: None,
                        resolve_target: None,
                        ops: wgpu::Operations {
                            load: wgpu::LoadOp::Clear(wgpu::Color {
                                r: self.clear_color[0],
                                g: self.clear_color[1],
                                b: self.clear_color[2],
                                a: self.clear_color[3],
                            }),
                            store: wgpu::StoreOp::Store,
                        },
                    })],
                    depth_stencil_attachment: None,
                    timestamp_writes: None,
                    occlusion_query_set: None,
                });

                pass.set_pipeline(screen_pipeline);
                pass.set_bind_group(0, &blur_bind_group, &[]);
                pass.draw(0..3, 0..1);
            }
        }

        // Main glyph pass — renders into frame_texture (offscreen).
        // With shadow: Load the shadow layer already in frame_texture.
        // Without shadow: Clear frame_texture and draw glyphs.
        let main_bytes = bytemuck::cast_slice(self.vertices.as_slice());
        self.ctx
            .queue
            .write_buffer(&self.vertex_buffer, 0, main_bytes);
        {
            let has_shadow = !self.shadow_vertices.is_empty();
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("next2 main glyph pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &frame_view,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: if has_shadow {
                            wgpu::LoadOp::Load
                        } else {
                            wgpu::LoadOp::Clear(wgpu::Color {
                                r: self.clear_color[0],
                                g: self.clear_color[1],
                                b: self.clear_color[2],
                                a: self.clear_color[3],
                            })
                        },
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });

            pass.set_pipeline(glyph_pipeline);
            pass.set_bind_group(0, &self.atlas_bind_group, &[]);
            pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
            pass.draw(0..self.vertices.len() as u32, 0..1);
        }

        // ── Phase 2: atomic blit from frame_texture → target_view ──
        // This is the ONLY render pass that touches the shared DXGI texture.
        // A single draw call makes the window where ALLOW_SIMULTANEOUS_ACCESS
        // could expose an intermediate state negligibly short.
        {
            let frame_blit_bg = self
                .ctx
                .device
                .create_bind_group(&wgpu::BindGroupDescriptor {
                    label: Some("next2 frame blit bg"),
                    layout: &self.screen_bind_group_layout,
                    entries: &[
                        wgpu::BindGroupEntry {
                            binding: 0,
                            resource: wgpu::BindingResource::TextureView(&frame_view),
                        },
                        wgpu::BindGroupEntry {
                            binding: 1,
                            resource: wgpu::BindingResource::Sampler(&self.screen_sampler),
                        },
                    ],
                });

            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("next2 frame blit pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: target_view,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        // Use LoadOp::Load (not Clear) on the shared DXGI texture.
                        // With ALLOW_SIMULTANEOUS_ACCESS, Flutter may read the texture
                        // between render-pass start and our single draw call.  Load
                        // preserves the previous complete frame during that gap;
                        // Clear would expose a blank/invisible instant.
                        load: wgpu::LoadOp::Load,
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });

            pass.set_pipeline(if target_format == wgpu::TextureFormat::Bgra8Unorm {
                &self.copy_pipeline
            } else {
                if self.texture_copy_pipeline.is_none() {
                    self.texture_copy_pipeline = Some(Self::create_copy_pipeline(
                        self.ctx.device.as_ref(),
                        &self.screen_bind_group_layout,
                        target_format,
                    ));
                }
                self.texture_copy_pipeline.as_ref().unwrap()
            });
            pass.set_bind_group(0, &frame_blit_bg, &[]);
            pass.draw(0..3, 0..1);
        }

        self.ctx.queue.submit(std::iter::once(encoder.finish()));
    }

    /// Create a copy pipeline for the given target format.
    /// Same shader as screen_pipeline but with NO blending — every pixel
    /// from source overwrites destination (including transparent → zero).
    fn create_copy_pipeline(
        device: &wgpu::Device,
        screen_bind_group_layout: &wgpu::BindGroupLayout,
        target_format: wgpu::TextureFormat,
    ) -> wgpu::RenderPipeline {
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("next2 copy shader"),
            source: wgpu::ShaderSource::Wgsl(std::borrow::Cow::Borrowed(NEXT2_SCREEN_COPY_WGSL)),
        });
        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("next2 copy pipeline layout"),
            bind_group_layouts: &[screen_bind_group_layout],
            push_constant_ranges: &[],
        });
        device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("next2 copy pipeline"),
            layout: Some(&layout),
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
                    blend: None,
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            multiview: None,
            cache: None,
        })
    }

    fn blit_screen_texture(
        device: &wgpu::Device,
        screen_bind_group_layout: &wgpu::BindGroupLayout,
        screen_sampler: &wgpu::Sampler,
        encoder: &mut wgpu::CommandEncoder,
        source_view: &wgpu::TextureView,
        target_view: &wgpu::TextureView,
        pipeline: &wgpu::RenderPipeline,
    ) {
        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("next2 screen bg"),
            layout: screen_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(source_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(screen_sampler),
                },
            ],
        });

        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("next2 screen blit pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: target_view,
                depth_slice: None,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
        });

        pass.set_pipeline(pipeline);
        pass.set_bind_group(0, &bind_group, &[]);
        pass.draw(0..3, 0..1);
    }

    fn clear_target_view(&self, target_view: &wgpu::TextureView) {
        let mut encoder = self
            .ctx
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("next2 target clear encoder"),
            });

        {
            let _ = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("next2 target clear pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: target_view,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: self.clear_color[0],
                            g: self.clear_color[1],
                            b: self.clear_color[2],
                            a: self.clear_color[3],
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
        }

        self.ctx.queue.submit(std::iter::once(encoder.finish()));
    }

    fn ensure_vertex_capacity(&mut self) {
        let required = self.vertices.len().max(self.shadow_vertices.len())
            * std::mem::size_of::<GlyphVertex>();
        if required <= self.vertex_capacity_bytes && required <= self.shadow_vertex_capacity_bytes {
            return;
        }

        let next_capacity = required.next_power_of_two();
        self.vertex_buffer = self.ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("next2 vertex buffer resize"),
            size: next_capacity as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        self.vertex_capacity_bytes = next_capacity;
        self.shadow_vertex_buffer = self.ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("next2 shadow vertex buffer resize"),
            size: next_capacity as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        self.shadow_vertex_capacity_bytes = next_capacity;
    }

    /// Whether the engine loop should re-render on an idle tick to advance
    /// scroll interpolation. True only when the scene has at least one scroll
    /// item AND a frame was submitted within the last 50ms — so empty/static
    /// scenes and paused/stalled playback (no recent submission) incur no
    /// continuous GPU work. The 50ms window matches the interp_dt cap in
    /// build_vertices, guaranteeing we stop re-rendering exactly when motion
    /// would freeze anyway.
    fn needs_interpolation_render(&self) -> bool {
        // Submit-rate adaptive gate. Only fill between submissions when Dart
        // feeds slower than our 16ms tick (~30fps submit). When Dart sustains
        // ~1 submit/tick (ema <= 20ms, healthy 60fps), idle interp is
        // disabled: it would double-render alongside submit-draws, and the two
        // streams (drawn at the same ~60Hz but unlocked phase) get sampled
        // irregularly by the display link, producing non-uniform per-frame
        // displacement — visible as 时快时慢 (variable speed). Dart's 60fps
        // absolute positions are already smooth on their own. ema == 0
        // (startup, not yet converged) skips this gate and falls through to
        // the conservative 50ms + scroll-item checks below.
        if self.submit_interval_ema > 0.0
            && self.submit_interval_ema <= 0.020
        {
            return false;
        }
        if self.submit_instant.elapsed().as_secs_f32() >= 0.050 {
            return false;
        }
        self.frame_items
            .iter()
            .any(|item| item.scroll_speed != 0.0)
    }

    fn build_vertices(&mut self) {
        self.vertices.clear();
        self.shadow_vertices.clear();

        // Interpolation delta since the last frame submission. Capped at 50ms:
        // normal 60fps(16ms)/30fps(33ms) Dart submissions keep this <50ms so
        // scroll items advance smoothly between submits; if no new frame
        // arrives for >50ms (pause / upstream stall) dt clamps to 0, freezing
        // motion on the last submission without needing a pause command.
        let elapsed = self.submit_instant.elapsed().as_secs_f32();
        self.interp_dt = if elapsed < 0.050 { elapsed } else { 0.0 };
        let interp_dt = self.interp_dt as f64;

        // Take `frame_items` out of `self` so the loop body can borrow `self`
        // mutably (push_quad / push_shadow_quad / atlas.entry_for all need
        // &mut self) without contending with a shared borrow of self.frame_items.
        // The Vec move is O(1) (pointer swap); previously this cloned the whole
        // Vec plus every token's String on every frame.
        let frame_items = std::mem::take(&mut self.frame_items);
        for item in &frame_items {
            let outline_px = resolve_outline_px(item.font_size, item.outline_width);
            let shadow = resolve_shadow(item.font_size, item.shadow_style);
            let fill_color = argb_to_linear(item.color_argb, item.opacity);
            let outline_color = stroke_color(fill_color);
            let shadow_color = [
                0.0,
                0.0,
                0.0,
                shadow.opacity * item.opacity * SHADOW_ALPHA_SCALE,
            ];

            let mut cursor_x = (item.x + item.scroll_speed as f64 * interp_dt) as f32;
            let quantized_size = item.font_size.round().clamp(8.0, 256.0) as u32;
            let baseline_y = item.y as f32 + self.atlas.line_ascent(quantized_size);
            let tokens = &item.tokens;

            for token in tokens {
                match token {
                    FrameToken::Text(text) => {
                        for ch in text.chars() {
                            let Some(entry) = self
                                .atlas
                                .entry_for(self.ctx.queue.as_ref(), ch, quantized_size)
                                .cloned()
                            else {
                                continue;
                            };

                            if entry.width == 0 || entry.height == 0 {
                                cursor_x += entry.advance;
                                continue;
                            }

                            let glyph_left = cursor_x + entry.offset_x;
                            let glyph_top = baseline_y + entry.offset_y;
                            let glyph_right = glyph_left + entry.width as f32;
                            let glyph_bottom = glyph_top + entry.height as f32;

                            if shadow.opacity > 0.0 {
                                self.push_shadow_quad(
                                    (glyph_left + shadow.offset_x) * SHADOW_RENDER_SCALE as f32,
                                    (glyph_top + shadow.offset_y) * SHADOW_RENDER_SCALE as f32,
                                    (glyph_right + shadow.offset_x) * SHADOW_RENDER_SCALE as f32,
                                    (glyph_bottom + shadow.offset_y) * SHADOW_RENDER_SCALE as f32,
                                    entry.uv_min,
                                    entry.uv_max,
                                    entry.uv_min,
                                    entry.uv_max,
                                    shadow_color,
                                    [entry.spread, 0.0, GLYPH_MODE_TEXT, 1.0],
                                );
                            }

                            self.push_quad(
                                glyph_left,
                                glyph_top,
                                glyph_right,
                                glyph_bottom,
                                entry.uv_min,
                                entry.uv_max,
                                entry.uv_min,
                                entry.uv_max,
                                fill_color,
                                outline_color,
                                [entry.spread, outline_px, GLYPH_MODE_TEXT, 0.0],
                            );

                            cursor_x += entry.advance;
                        }
                    }
                    FrameToken::Emoji(id) => {
                        let Some(entry) = self.emoji_atlas.entry_for(id).cloned() else {
                            cursor_x += quantized_size as f32;
                            continue;
                        };

                        let side_bearing =
                            (quantized_size as f32 * EMOJI_SIDE_BEARING_RATIO).clamp(1.0, 5.0);
                        let emoji_outline_px = outline_px * EMOJI_OUTLINE_SCALE;
                        let glyph_left = cursor_x + side_bearing + entry.offset_x;
                        let glyph_top = baseline_y + entry.offset_y;
                        let glyph_right = glyph_left + entry.width as f32;
                        let glyph_bottom = glyph_top + entry.height as f32;

                        if shadow.opacity > 0.0 {
                            self.push_shadow_quad(
                                (glyph_left + shadow.offset_x) * SHADOW_RENDER_SCALE as f32,
                                (glyph_top + shadow.offset_y) * SHADOW_RENDER_SCALE as f32,
                                (glyph_right + shadow.offset_x) * SHADOW_RENDER_SCALE as f32,
                                (glyph_bottom + shadow.offset_y) * SHADOW_RENDER_SCALE as f32,
                                entry.uv_min,
                                entry.uv_max,
                                entry.mask_uv_min,
                                entry.mask_uv_max,
                                shadow_color,
                                [EMOJI_SDF_SPREAD, 0.0, GLYPH_MODE_EMOJI, 1.0],
                            );
                        }

                        self.push_quad(
                            glyph_left,
                            glyph_top,
                            glyph_right,
                            glyph_bottom,
                            entry.uv_min,
                            entry.uv_max,
                            entry.mask_uv_min,
                            entry.mask_uv_max,
                            [1.0, 1.0, 1.0, item.opacity],
                            outline_color,
                            [EMOJI_SDF_SPREAD, emoji_outline_px, GLYPH_MODE_EMOJI, 0.0],
                        );

                        cursor_x += entry.advance.max(1.0) + side_bearing * 2.0;
                    }
                }
            }
        }

        // Restore the frame_items taken before the loop.
        self.frame_items = frame_items;

        if !self.frame_items.is_empty() {
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
    }

    #[allow(clippy::too_many_arguments)]
    fn push_shadow_quad(
        &mut self,
        left: f32,
        top: f32,
        right: f32,
        bottom: f32,
        uv_min: [f32; 2],
        uv_max: [f32; 2],
        uv_aux_min: [f32; 2],
        uv_aux_max: [f32; 2],
        color: [f32; 4],
        params: [f32; 4],
    ) {
        let p0 = to_ndc(
            left,
            top,
            self.shadow_width as f32,
            self.shadow_height as f32,
        );
        let p1 = to_ndc(
            right,
            top,
            self.shadow_width as f32,
            self.shadow_height as f32,
        );
        let p2 = to_ndc(
            right,
            bottom,
            self.shadow_width as f32,
            self.shadow_height as f32,
        );
        let p3 = to_ndc(
            left,
            bottom,
            self.shadow_width as f32,
            self.shadow_height as f32,
        );

        let uv0 = [uv_min[0], uv_min[1]];
        let uv1 = [uv_max[0], uv_min[1]];
        let uv2 = [uv_max[0], uv_max[1]];
        let uv3 = [uv_min[0], uv_max[1]];
        let uv_aux0 = [uv_aux_min[0], uv_aux_min[1]];
        let uv_aux1 = [uv_aux_max[0], uv_aux_min[1]];
        let uv_aux2 = [uv_aux_max[0], uv_aux_max[1]];
        let uv_aux3 = [uv_aux_min[0], uv_aux_max[1]];

        let v0 = GlyphVertex {
            position: p0,
            uv: uv0,
            uv_aux: uv_aux0,
            color,
            outline_color: color,
            params,
        };
        let v1 = GlyphVertex {
            position: p1,
            uv: uv1,
            uv_aux: uv_aux1,
            color,
            outline_color: color,
            params,
        };
        let v2 = GlyphVertex {
            position: p2,
            uv: uv2,
            uv_aux: uv_aux2,
            color,
            outline_color: color,
            params,
        };
        let v3 = GlyphVertex {
            position: p3,
            uv: uv3,
            uv_aux: uv_aux3,
            color,
            outline_color: color,
            params,
        };

        self.shadow_vertices
            .extend_from_slice(&[v0, v1, v2, v0, v2, v3]);
    }

    #[allow(clippy::too_many_arguments)]
    fn push_quad(
        &mut self,
        left: f32,
        top: f32,
        right: f32,
        bottom: f32,
        uv_min: [f32; 2],
        uv_max: [f32; 2],
        uv_aux_min: [f32; 2],
        uv_aux_max: [f32; 2],
        color: [f32; 4],
        outline_color: [f32; 4],
        params: [f32; 4],
    ) {
        let p0 = to_ndc(left, top, self.width as f32, self.height as f32);
        let p1 = to_ndc(right, top, self.width as f32, self.height as f32);
        let p2 = to_ndc(right, bottom, self.width as f32, self.height as f32);
        let p3 = to_ndc(left, bottom, self.width as f32, self.height as f32);

        let uv0 = [uv_min[0], uv_min[1]];
        let uv1 = [uv_max[0], uv_min[1]];
        let uv2 = [uv_max[0], uv_max[1]];
        let uv3 = [uv_min[0], uv_max[1]];
        let uv_aux0 = [uv_aux_min[0], uv_aux_min[1]];
        let uv_aux1 = [uv_aux_max[0], uv_aux_min[1]];
        let uv_aux2 = [uv_aux_max[0], uv_aux_max[1]];
        let uv_aux3 = [uv_aux_min[0], uv_aux_max[1]];

        let v0 = GlyphVertex {
            position: p0,
            uv: uv0,
            uv_aux: uv_aux0,
            color,
            outline_color,
            params,
        };
        let v1 = GlyphVertex {
            position: p1,
            uv: uv1,
            uv_aux: uv_aux1,
            color,
            outline_color,
            params,
        };
        let v2 = GlyphVertex {
            position: p2,
            uv: uv2,
            uv_aux: uv_aux2,
            color,
            outline_color,
            params,
        };
        let v3 = GlyphVertex {
            position: p3,
            uv: uv3,
            uv_aux: uv_aux3,
            color,
            outline_color,
            params,
        };

        self.vertices.extend_from_slice(&[v0, v1, v2, v0, v2, v3]);
    }
}

fn create_render_texture_with_usage(
    device: &wgpu::Device,
    width: u32,
    height: u32,
    label: Option<&'static str>,
    usage: wgpu::TextureUsages,
    format: wgpu::TextureFormat,
) -> wgpu::Texture {
    device.create_texture(&wgpu::TextureDescriptor {
        label,
        size: wgpu::Extent3d {
            width: width.max(1),
            height: height.max(1),
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage,
        view_formats: &[],
    })
}

fn to_ndc(x: f32, y: f32, width: f32, height: f32) -> [f32; 2] {
    let nx = (x / width) * 2.0 - 1.0;
    let ny = 1.0 - (y / height) * 2.0;
    [nx, ny]
}

fn resolve_outline_px(font_size: f32, width_multiplier: f32) -> f32 {
    if !width_multiplier.is_finite() {
        return 0.0;
    }
    let width_multiplier = width_multiplier.clamp(0.0, 4.0);
    if width_multiplier <= 0.0 {
        return 0.0;
    }
    (font_size * 0.06).clamp(1.0, 2.6) * width_multiplier
}

#[derive(Copy, Clone)]
struct ShadowStyle {
    offset_x: f32,
    offset_y: f32,
    opacity: f32,
}

fn resolve_shadow(font_size: f32, style: u8) -> ShadowStyle {
    let unit = (font_size * 0.06).clamp(1.0, 3.2);
    match style {
        1 => ShadowStyle {
            offset_x: unit * 0.7,
            offset_y: unit * 0.7,
            opacity: 0.30,
        },
        2 => ShadowStyle {
            offset_x: unit * 1.0,
            offset_y: unit * 1.0,
            opacity: 0.40,
        },
        3 => ShadowStyle {
            offset_x: unit * 1.25,
            offset_y: unit * 1.25,
            opacity: 0.72,
        },
        _ => ShadowStyle {
            offset_x: 0.0,
            offset_y: 0.0,
            opacity: 0.0,
        },
    }
}

fn argb_to_linear(color_argb: i32, opacity: f32) -> [f32; 4] {
    let raw = color_argb as u32;
    let a = ((raw >> 24) & 0xFF) as f32 / 255.0;
    let r = ((raw >> 16) & 0xFF) as f32 / 255.0;
    let g = ((raw >> 8) & 0xFF) as f32 / 255.0;
    let b = (raw & 0xFF) as f32 / 255.0;
    [r, g, b, (a * opacity).clamp(0.0, 1.0)]
}

fn stroke_color(fill: [f32; 4]) -> [f32; 4] {
    let r = (fill[0] * 255.0).round() as i32;
    let g = (fill[1] * 255.0).round() as i32;
    let b = (fill[2] * 255.0).round() as i32;
    let is_black = r <= 8 && g <= 8 && b <= 8;
    if is_black {
        [1.0, 1.0, 1.0, fill[3]]
    } else {
        [0.0, 0.0, 0.0, fill[3]]
    }
}

fn sanitize_emoji_rgba(width: u32, height: u32, rgba: &[u8]) -> Option<Vec<u8>> {
    let expected = width.checked_mul(height)?.checked_mul(4)? as usize;
    if rgba.len() != expected {
        return None;
    }
    let mut out = vec![0u8; expected];
    for i in (0..expected).step_by(4) {
        let a = rgba[i + 3] as f32 / 255.0;
        if a <= 0.0 {
            continue;
        }
        let inv = (1.0 / a).min(64.0);
        out[i] = (rgba[i] as f32 * inv).clamp(0.0, 255.0) as u8;
        out[i + 1] = (rgba[i + 1] as f32 * inv).clamp(0.0, 255.0) as u8;
        out[i + 2] = (rgba[i + 2] as f32 * inv).clamp(0.0, 255.0) as u8;
        out[i + 3] = rgba[i + 3];
    }
    Some(out)
}

fn build_emoji_sdf_mask(width: u32, height: u32, rgba: &[u8]) -> Vec<u8> {
    let px_count = (width as usize).saturating_mul(height as usize);
    let mut alpha = vec![0.0f32; px_count];
    for i in 0..px_count {
        alpha[i] = rgba[i * 4 + 3] as f32 / 255.0;
    }

    let mut inside = vec![f32::INFINITY; px_count];
    let mut outside = vec![f32::INFINITY; px_count];
    for i in 0..px_count {
        if alpha[i] >= 0.5 {
            inside[i] = 0.0;
        } else {
            outside[i] = 0.0;
        }
    }

    distance_transform_2d(&mut inside, width as usize, height as usize);
    distance_transform_2d(&mut outside, width as usize, height as usize);

    let mut out = vec![0u8; px_count];
    let spread = EMOJI_SDF_SPREAD.max(1.0);
    for i in 0..px_count {
        let dist = outside[i].sqrt() - inside[i].sqrt();
        let norm = 0.5 + dist / (2.0 * spread);
        out[i] = (norm.clamp(0.0, 1.0) * 255.0).round() as u8;
    }
    out
}

fn distance_transform_2d(field: &mut [f32], width: usize, height: usize) {
    let mut row = vec![0.0f32; width];
    for y in 0..height {
        let start = y * width;
        row.copy_from_slice(&field[start..start + width]);
        distance_transform_1d(&mut row, width);
        field[start..start + width].copy_from_slice(&row);
    }

    let mut col = vec![0.0f32; height];
    for x in 0..width {
        for y in 0..height {
            col[y] = field[y * width + x];
        }
        distance_transform_1d(&mut col, height);
        for y in 0..height {
            field[y * width + x] = col[y];
        }
    }
}

fn distance_transform_1d(f: &mut [f32], n: usize) {
    if n == 0 {
        return;
    }

    let sites: Vec<usize> = (0..n).filter(|&i| f[i].is_finite()).collect();
    if sites.is_empty() {
        f.fill(f32::INFINITY);
        return;
    }

    let mut v = vec![0usize; sites.len()];
    let mut z = vec![0.0f32; sites.len() + 1];
    let mut k = 0usize;
    v[0] = sites[0];
    z[0] = f32::NEG_INFINITY;
    z[1] = f32::INFINITY;

    for &q in sites.iter().skip(1) {
        let mut s = intersection_1d(f, v[k], q);
        while k > 0 && s <= z[k] {
            k -= 1;
            s = intersection_1d(f, v[k], q);
        }
        if s <= z[k] && k == 0 {
            v[0] = q;
            z[1] = f32::INFINITY;
            continue;
        }
        k += 1;
        v[k] = q;
        z[k] = s;
        z[k + 1] = f32::INFINITY;
    }

    let mut g = vec![0.0f32; n];
    let mut kk = 0usize;
    let last = k;
    for q in 0..n {
        while kk < last && z[kk + 1] < q as f32 {
            kk += 1;
        }
        let dx = q as f32 - v[kk] as f32;
        g[q] = dx * dx + f[v[kk]];
    }
    f.copy_from_slice(&g);
}

fn intersection_1d(f: &[f32], i: usize, j: usize) -> f32 {
    let fi = f[i];
    let fj = f[j];
    if !fi.is_finite() && !fj.is_finite() {
        return f32::INFINITY;
    }
    if !fi.is_finite() {
        return f32::NEG_INFINITY;
    }
    if !fj.is_finite() {
        return f32::INFINITY;
    }
    ((fj + (j * j) as f32) - (fi + (i * i) as f32)) / (2.0 * (j as f32 - i as f32))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn emoji_sdf_mask_keeps_inside_above_midpoint() {
        let width = 5;
        let height = 5;
        let mut rgba = vec![0u8; width * height * 4];
        for y in 1..4 {
            for x in 1..4 {
                rgba[(y * width + x) * 4 + 3] = 255;
            }
        }

        let mask = build_emoji_sdf_mask(width as u32, height as u32, &rgba);

        let center = mask[2 * width + 2];
        let corner = mask[0];

        assert!(center > 128, "center={center} corner={corner}");
        assert!(corner < 128, "center={center} corner={corner}");
    }
}
