use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::thread;
use std::time::Duration;

use bytemuck::{Pod, Zeroable};
use fontdue::{Font, FontSettings};
#[cfg(any(target_os = "macos", target_os = "ios"))]
use metal::foreign_types::ForeignType;
use serde::Deserialize;

use super::present::{attach_present_texture, signal_frame_ready, PresentTarget};

const INITIAL_WIDTH: u32 = 2;
const INITIAL_HEIGHT: u32 = 2;
const TICK_INTERVAL: Duration = Duration::from_millis(16);
const BASE_ATLAS_SIZE: u32 = 2048;
const SDF_SPREAD: i32 = 6;
const SHADOW_ALPHA_SCALE: f32 = 0.85;

static FONT_DATA: &[u8] = include_bytes!("../../../assets/subfont.ttf");

#[derive(Clone)]
pub struct RenderFrameInput {
    pub frame_json: String,
    pub font_size: f32,
    pub outline_style: u8,
    pub shadow_style: u8,
    pub opacity: f32,
}

pub enum EngineCommand {
    AttachPresentTexture {
        mtl_texture_ptr: usize,
        width: u32,
        height: u32,
        bytes_per_row: u32,
    },
    Resize {
        width: u32,
        height: u32,
    },
    ResetScene,
    SetFrame {
        input: RenderFrameInput,
        reply: mpsc::Sender<bool>,
    },
    Stop,
}

pub struct EngineEntry {
    pub cmd_tx: mpsc::Sender<EngineCommand>,
    pub frame_ready: Arc<AtomicBool>,
    pub mtl_device_ptr: usize,
}

struct EngineRegistry {
    next_handle: AtomicU64,
    entries: Mutex<HashMap<u64, EngineEntry>>,
}

static REGISTRY: OnceLock<EngineRegistry> = OnceLock::new();

fn registry() -> &'static EngineRegistry {
    REGISTRY.get_or_init(|| EngineRegistry {
        next_handle: AtomicU64::new(1),
        entries: Mutex::new(HashMap::new()),
    })
}

pub fn lookup_engine(handle: u64) -> Option<EngineEntry> {
    if handle == 0 {
        return None;
    }
    let guard = registry().entries.lock().ok()?;
    let entry = guard.get(&handle)?;
    Some(EngineEntry {
        cmd_tx: entry.cmd_tx.clone(),
        frame_ready: Arc::clone(&entry.frame_ready),
        mtl_device_ptr: entry.mtl_device_ptr,
    })
}

pub fn remove_engine(handle: u64) -> Option<EngineEntry> {
    if handle == 0 {
        return None;
    }
    let mut guard = registry().entries.lock().ok()?;
    guard.remove(&handle)
}

pub fn create_engine(width: u32, height: u32) -> Result<u64, String> {
    let width = width.max(INITIAL_WIDTH);
    let height = height.max(INITIAL_HEIGHT);

    let ctx = device_context()?;

    let mtl_device_ptr = extract_mtl_device_ptr(ctx.device.as_ref()) as usize;
    if mtl_device_ptr == 0 {
        return Err("wgpu: failed to extract underlying MTLDevice".to_string());
    }

    let (cmd_tx, cmd_rx) = mpsc::channel::<EngineCommand>();
    let frame_ready = Arc::new(AtomicBool::new(false));
    let frame_ready_thread = Arc::clone(&frame_ready);

    thread::Builder::new()
        .name("next2-engine".to_string())
        .spawn(move || {
            run_engine_loop(ctx, width, height, frame_ready_thread, cmd_rx);
        })
        .map_err(|err| format!("spawn next2-engine failed: {err}"))?;

    let handle = registry()
        .next_handle
        .fetch_add(1, Ordering::Relaxed)
        .max(1);

    let mut guard = registry()
        .entries
        .lock()
        .map_err(|_| "engine registry lock poisoned".to_string())?;
    guard.insert(
        handle,
        EngineEntry {
            cmd_tx,
            frame_ready,
            mtl_device_ptr,
        },
    );

    Ok(handle)
}

struct EngineDeviceContext {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
}

static DEVICE_CONTEXT: OnceLock<Result<Arc<EngineDeviceContext>, String>> = OnceLock::new();

fn device_context() -> Result<Arc<EngineDeviceContext>, String> {
    let init_result = DEVICE_CONTEXT.get_or_init(|| {
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::METAL,
            flags: wgpu::InstanceFlags::default(),
            memory_budget_thresholds: wgpu::MemoryBudgetThresholds::default(),
            backend_options: wgpu::BackendOptions::default(),
        });

        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
        }))
        .map_err(|err| format!("wgpu: request_adapter failed: {err:?}"))?;

        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("next2 render device"),
            required_features: wgpu::Features::empty(),
            required_limits: adapter.limits(),
            experimental_features: wgpu::ExperimentalFeatures::disabled(),
            memory_hints: wgpu::MemoryHints::Performance,
            trace: wgpu::Trace::Off,
        }))
        .map_err(|err| format!("wgpu: request_device failed: {err:?}"))?;

        Ok(Arc::new(EngineDeviceContext {
            device: Arc::new(device),
            queue: Arc::new(queue),
        }))
    });

    match init_result {
        Ok(ctx) => Ok(Arc::clone(ctx)),
        Err(err) => Err(err.clone()),
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn extract_mtl_device_ptr(device: &wgpu::Device) -> *mut std::ffi::c_void {
    let result = unsafe {
        device.as_hal::<wgpu_hal::api::Metal>().map(|hal_device| {
            let raw = hal_device.raw_device();
            raw.lock().as_ptr() as *mut std::ffi::c_void
        })
    };
    result.unwrap_or(std::ptr::null_mut())
}

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
fn extract_mtl_device_ptr(_device: &wgpu::Device) -> *mut std::ffi::c_void {
    std::ptr::null_mut()
}

fn run_engine_loop(
    ctx: Arc<EngineDeviceContext>,
    mut width: u32,
    mut height: u32,
    frame_ready: Arc<AtomicBool>,
    cmd_rx: mpsc::Receiver<EngineCommand>,
) {
    let mut renderer = match Next2Renderer::new(Arc::clone(&ctx), width, height) {
        Ok(renderer) => renderer,
        Err(_) => return,
    };
    let mut present_target: Option<PresentTarget> = None;
    let mut running = true;
    let mut has_pending_frame = false;

    while running {
        let mut received_command = false;

        loop {
            let recv_result = if received_command {
                cmd_rx.try_recv().map_err(|err| match err {
                    mpsc::TryRecvError::Empty => mpsc::RecvTimeoutError::Timeout,
                    mpsc::TryRecvError::Disconnected => mpsc::RecvTimeoutError::Disconnected,
                })
            } else {
                cmd_rx.recv_timeout(TICK_INTERVAL)
            };

            let cmd = match recv_result {
                Ok(cmd) => cmd,
                Err(mpsc::RecvTimeoutError::Timeout) => break,
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    running = false;
                    break;
                }
            };

            received_command = true;
            match cmd {
                EngineCommand::AttachPresentTexture {
                    mtl_texture_ptr,
                    width: w,
                    height: h,
                    bytes_per_row,
                } => {
                    present_target = attach_present_texture(
                        ctx.device.as_ref(),
                        mtl_texture_ptr,
                        w.max(1),
                        h.max(1),
                        bytes_per_row,
                    );
                    width = w.max(1);
                    height = h.max(1);
                    let _ = renderer.resize(width, height);
                    has_pending_frame = true;
                }
                EngineCommand::Resize {
                    width: w,
                    height: h,
                } => {
                    width = w.max(1);
                    height = h.max(1);
                    let _ = renderer.resize(width, height);
                    has_pending_frame = true;
                }
                EngineCommand::ResetScene => {
                    renderer.reset_scene();
                    has_pending_frame = true;
                }
                EngineCommand::SetFrame { input, reply } => {
                    let ok = renderer.update_frame(input);
                    let _ = reply.send(ok);
                    if ok {
                        has_pending_frame = true;
                    }
                }
                EngineCommand::Stop => {
                    running = false;
                    break;
                }
            }
        }

        if !running {
            break;
        }

        if has_pending_frame {
            if let Some(target) = present_target.as_ref() {
                renderer.draw_to_present(target);
                signal_frame_ready(ctx.queue.as_ref(), Arc::clone(&frame_ready));
                has_pending_frame = false;
            }
        }
    }
}

#[repr(C)]
#[derive(Copy, Clone, Debug, Pod, Zeroable)]
struct GlyphVertex {
    position: [f32; 2],
    uv: [f32; 2],
    color: [f32; 4],
    outline_color: [f32; 4],
    params: [f32; 4],
}

impl GlyphVertex {
    const fn layout() -> wgpu::VertexBufferLayout<'static> {
        const ATTRS: [wgpu::VertexAttribute; 5] = [
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
                format: wgpu::VertexFormat::Float32x4,
                offset: 16,
                shader_location: 2,
            },
            wgpu::VertexAttribute {
                format: wgpu::VertexFormat::Float32x4,
                offset: 32,
                shader_location: 3,
            },
            wgpu::VertexAttribute {
                format: wgpu::VertexFormat::Float32x4,
                offset: 48,
                shader_location: 4,
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
struct GlyphAtlasEntry {
    uv_min: [f32; 2],
    uv_max: [f32; 2],
    width: u32,
    height: u32,
    bearing_x: f32,
    bearing_y: f32,
    advance: f32,
}

struct Next2GlyphAtlas {
    font: Font,
    texture: wgpu::Texture,
    texture_view: wgpu::TextureView,
    sampler: wgpu::Sampler,
    width: u32,
    height: u32,
    cursor_x: u32,
    cursor_y: u32,
    row_height: u32,
    entries: HashMap<(char, u32), GlyphAtlasEntry>,
}

impl Next2GlyphAtlas {
    fn new(device: &wgpu::Device) -> Result<Self, String> {
        let font = Font::from_bytes(FONT_DATA, FontSettings::default())
            .map_err(|err| format!("font load failed: {err}"))?;

        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("next2 sdf atlas"),
            size: wgpu::Extent3d {
                width: BASE_ATLAS_SIZE,
                height: BASE_ATLAS_SIZE,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::R8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let texture_view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("next2 sdf sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });

        Ok(Self {
            font,
            texture,
            texture_view,
            sampler,
            width: BASE_ATLAS_SIZE,
            height: BASE_ATLAS_SIZE,
            cursor_x: 0,
            cursor_y: 0,
            row_height: 0,
            entries: HashMap::new(),
        })
    }

    fn clear(&mut self) {
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.row_height = 0;
        self.entries.clear();
    }

    fn entry_for(
        &mut self,
        queue: &wgpu::Queue,
        ch: char,
        quantized_size: u32,
    ) -> Option<&GlyphAtlasEntry> {
        let key = (ch, quantized_size);
        if !self.entries.contains_key(&key) {
            self.rasterize_and_upload(queue, ch, quantized_size)?;
        }
        self.entries.get(&key)
    }

    fn rasterize_and_upload(
        &mut self,
        queue: &wgpu::Queue,
        ch: char,
        quantized_size: u32,
    ) -> Option<()> {
        let px = quantized_size as f32;
        let (metrics, bitmap) = self.font.rasterize(ch, px);
        let advance = metrics.advance_width.max(px * 0.4);

        let glyph_w = metrics.width as u32;
        let glyph_h = metrics.height as u32;
        let padded_w = glyph_w.saturating_add((SDF_SPREAD as u32) * 2).max(1);
        let padded_h = glyph_h.saturating_add((SDF_SPREAD as u32) * 2).max(1);

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

        let sdf = generate_sdf_from_alpha(
            &bitmap,
            glyph_w as usize,
            glyph_h as usize,
            padded_w as usize,
            padded_h as usize,
            SDF_SPREAD,
        );

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
            &sdf,
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

        let uv_min = [
            self.cursor_x as f32 / self.width as f32,
            self.cursor_y as f32 / self.height as f32,
        ];
        let uv_max = [
            (self.cursor_x + padded_w) as f32 / self.width as f32,
            (self.cursor_y + padded_h) as f32 / self.height as f32,
        ];

        let entry = GlyphAtlasEntry {
            uv_min,
            uv_max,
            width: padded_w,
            height: padded_h,
            bearing_x: metrics.xmin as f32 - SDF_SPREAD as f32,
            // fontdue metrics.ymin is from baseline to bitmap bottom.
            bearing_y: metrics.ymin as f32 - SDF_SPREAD as f32,
            advance,
        };

        self.entries.insert((ch, quantized_size), entry);

        self.cursor_x = self.cursor_x.saturating_add(padded_w);
        self.row_height = self.row_height.max(padded_h);

        Some(())
    }
}

fn generate_sdf_from_alpha(
    alpha_bitmap: &[u8],
    src_width: usize,
    src_height: usize,
    out_width: usize,
    out_height: usize,
    spread: i32,
) -> Vec<u8> {
    let mut out = vec![0u8; out_width * out_height];
    if src_width == 0 || src_height == 0 {
        return out;
    }

    let offset_x = ((out_width - src_width) / 2) as i32;
    let offset_y = ((out_height - src_height) / 2) as i32;

    let spread_sq = (spread * spread) as f32;

    for oy in 0..out_height {
        for ox in 0..out_width {
            let mut is_inside = false;
            let sx = ox as i32 - offset_x;
            let sy = oy as i32 - offset_y;
            if sx >= 0 && sy >= 0 && (sx as usize) < src_width && (sy as usize) < src_height {
                let alpha = alpha_bitmap[sy as usize * src_width + sx as usize];
                is_inside = alpha > 127;
            }

            let mut min_dist_sq = spread_sq;
            let min_x = (sx - spread).max(0) as usize;
            let max_x = (sx + spread).min(src_width as i32 - 1).max(0) as usize;
            let min_y = (sy - spread).max(0) as usize;
            let max_y = (sy + spread).min(src_height as i32 - 1).max(0) as usize;

            for ny in min_y..=max_y {
                for nx in min_x..=max_x {
                    let alpha = alpha_bitmap[ny * src_width + nx];
                    let neighbor_inside = alpha > 127;
                    if neighbor_inside == is_inside {
                        continue;
                    }
                    let dx = (nx as i32 - sx) as f32;
                    let dy = (ny as i32 - sy) as f32;
                    let dist_sq = dx * dx + dy * dy;
                    if dist_sq < min_dist_sq {
                        min_dist_sq = dist_sq;
                    }
                }
            }

            let dist = min_dist_sq.sqrt().min(spread as f32);
            let signed = if is_inside { -dist } else { dist };
            let normalized = (0.5 + signed / (spread as f32 * 2.0)).clamp(0.0, 1.0);
            out[oy * out_width + ox] = (normalized * 255.0) as u8;
        }
    }

    out
}

struct Next2Renderer {
    ctx: Arc<EngineDeviceContext>,
    pipeline: wgpu::RenderPipeline,
    atlas_bind_group_layout: wgpu::BindGroupLayout,
    atlas_bind_group: wgpu::BindGroup,
    atlas: Next2GlyphAtlas,
    vertex_buffer: wgpu::Buffer,
    vertex_capacity_bytes: usize,
    vertices: Vec<GlyphVertex>,
    frame_items: Vec<FrameItem>,
    clear_color: [f64; 4],
    width: u32,
    height: u32,
}

impl Next2Renderer {
    fn new(ctx: Arc<EngineDeviceContext>, width: u32, height: u32) -> Result<Self, String> {
        let atlas = Next2GlyphAtlas::new(ctx.device.as_ref())?;

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
                    ],
                });

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
            ],
        });

        let shader =
            ctx.device
                .create_shader_module(wgpu::ShaderModuleDescriptor {
                    label: Some("next2 sdf shader"),
                    source: wgpu::ShaderSource::Wgsl(std::borrow::Cow::Borrowed(NEXT2_WGSL)),
                });

        let pipeline_layout =
            ctx.device
                .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                    label: Some("next2 pipeline layout"),
                    bind_group_layouts: &[&atlas_bind_group_layout],
                    push_constant_ranges: &[],
                });

        let pipeline =
            ctx.device
                .create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                    label: Some("next2 render pipeline"),
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
                            format: wgpu::TextureFormat::Bgra8Unorm,
                            blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                            write_mask: wgpu::ColorWrites::ALL,
                        })],
                    }),
                    multiview: None,
                    cache: None,
                });

        let vertex_capacity = 4096usize * std::mem::size_of::<GlyphVertex>();
        let vertex_buffer = ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("next2 vertex buffer"),
            size: vertex_capacity as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        Ok(Self {
            ctx,
            pipeline,
            atlas_bind_group_layout,
            atlas_bind_group,
            atlas,
            vertex_buffer,
            vertex_capacity_bytes: vertex_capacity,
            vertices: Vec::new(),
            frame_items: Vec::new(),
            clear_color: [0.0, 0.0, 0.0, 0.0],
            width: width.max(1),
            height: height.max(1),
        })
    }

    fn resize(&mut self, width: u32, height: u32) -> bool {
        self.width = width.max(1);
        self.height = height.max(1);
        true
    }

    fn reset_scene(&mut self) {
        self.frame_items.clear();
        self.vertices.clear();
    }

    fn update_frame(&mut self, input: RenderFrameInput) -> bool {
        let parsed = match serde_json::from_str::<FramePayload>(&input.frame_json) {
            Ok(parsed) => parsed,
            Err(_) => return false,
        };

        self.frame_items.clear();
        self.frame_items.reserve(parsed.items.len());

        let opacity = input.opacity.clamp(0.0, 1.0);
        let outline_style = input.outline_style;
        let shadow_style = input.shadow_style;
        let font_size = input.font_size.max(1.0);

        for item in parsed.items {
            self.frame_items.push(FrameItem {
                text: item.text,
                count_text: item.count_text,
                x: item.x,
                y: item.y,
                color_argb: item.color_argb,
                font_size: (font_size as f64 * item.font_size_multiplier.max(0.5)) as f32,
                outline_style,
                shadow_style,
                opacity,
            });
        }

        true
    }

    fn draw_to_present(&mut self, present: &PresentTarget) {
        let PresentTarget::Texture(texture_target) = present;
        self.width = texture_target.width.max(1);
        self.height = texture_target.height.max(1);

        self.build_vertices();

        if self.vertices.is_empty() {
            self.clear_only(texture_target);
            return;
        }

        self.ensure_vertex_capacity();

        let bytes = bytemuck::cast_slice(self.vertices.as_slice());
        self.ctx.queue.write_buffer(&self.vertex_buffer, 0, bytes);

        let view = texture_target
            .render_texture()
            .create_view(&wgpu::TextureViewDescriptor {
                format: Some(wgpu::TextureFormat::Bgra8Unorm),
                ..Default::default()
            });

        let mut encoder = self
            .ctx
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("next2 render encoder"),
            });

        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("next2 render pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
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

            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &self.atlas_bind_group, &[]);
            pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
            pass.draw(0..self.vertices.len() as u32, 0..1);
        }

        self.ctx.queue.submit(std::iter::once(encoder.finish()));
    }

    fn clear_only(&self, texture_target: &super::present::PresentTextureTarget) {
        let view = texture_target
            .render_texture()
            .create_view(&wgpu::TextureViewDescriptor {
                format: Some(wgpu::TextureFormat::Bgra8Unorm),
                ..Default::default()
            });

        let mut encoder = self
            .ctx
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("next2 clear encoder"),
            });

        {
            let _ = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("next2 clear pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
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
        let required = self.vertices.len() * std::mem::size_of::<GlyphVertex>();
        if required <= self.vertex_capacity_bytes {
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
    }

    fn build_vertices(&mut self) {
        self.vertices.clear();

        for item in self.frame_items.clone() {
            let mut text = item.text.clone();
            if let Some(count_text) = &item.count_text {
                text.push(' ');
                text.push_str(count_text);
            }

            let outline_px = resolve_outline_px(item.font_size, item.outline_style);
            let shadow = resolve_shadow(item.font_size, item.shadow_style);
            let fill_color = argb_to_linear(item.color_argb, item.opacity);
            let outline_color = stroke_color(fill_color);
            let shadow_color = [0.0, 0.0, 0.0, shadow.opacity * item.opacity * SHADOW_ALPHA_SCALE];

            let mut cursor_x = item.x as f32;
            let baseline_y = item.y as f32 + item.font_size;
            let quantized_size = item.font_size.round().clamp(8.0, 128.0) as u32;

            for ch in text.chars() {
                let Some(entry) = self
                    .atlas
                    .entry_for(self.ctx.queue.as_ref(), ch, quantized_size)
                    .cloned()
                else {
                    continue;
                };

                let glyph_left = cursor_x + entry.bearing_x;
                let glyph_bottom = baseline_y + entry.bearing_y;
                let glyph_top = glyph_bottom - entry.height as f32;
                let glyph_right = glyph_left + entry.width as f32;

                if shadow.opacity > 0.0 {
                    self.push_quad(
                        glyph_left + shadow.offset_x,
                        glyph_top + shadow.offset_y,
                        glyph_right + shadow.offset_x,
                        glyph_bottom + shadow.offset_y,
                        entry.uv_min,
                        entry.uv_max,
                        shadow_color,
                        shadow_color,
                        [SDF_SPREAD as f32, 0.0, self.width as f32, self.height as f32],
                    );
                }

                self.push_quad(
                    glyph_left,
                    glyph_top,
                    glyph_right,
                    glyph_bottom,
                    entry.uv_min,
                    entry.uv_max,
                    fill_color,
                    outline_color,
                    [SDF_SPREAD as f32, outline_px, self.width as f32, self.height as f32],
                );

                cursor_x += entry.advance;
            }
        }

        if !self.frame_items.is_empty() {
            self.atlas_bind_group =
                self.ctx
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
                        ],
                    });
        }
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

        let v0 = GlyphVertex {
            position: p0,
            uv: uv0,
            color,
            outline_color,
            params,
        };
        let v1 = GlyphVertex {
            position: p1,
            uv: uv1,
            color,
            outline_color,
            params,
        };
        let v2 = GlyphVertex {
            position: p2,
            uv: uv2,
            color,
            outline_color,
            params,
        };
        let v3 = GlyphVertex {
            position: p3,
            uv: uv3,
            color,
            outline_color,
            params,
        };

        self.vertices.extend_from_slice(&[v0, v1, v2, v0, v2, v3]);
    }
}

fn to_ndc(x: f32, y: f32, width: f32, height: f32) -> [f32; 2] {
    let nx = (x / width) * 2.0 - 1.0;
    let ny = 1.0 - (y / height) * 2.0;
    [nx, ny]
}

fn resolve_outline_px(font_size: f32, style: u8) -> f32 {
    match style {
        1 => (font_size * 0.06).clamp(1.0, 2.6),
        2 => (font_size * 0.045).clamp(0.8, 2.0),
        _ => 0.0,
    }
}

#[derive(Copy, Clone)]
struct ShadowStyle {
    offset_x: f32,
    offset_y: f32,
    opacity: f32,
}

fn resolve_shadow(font_size: f32, style: u8) -> ShadowStyle {
    let unit = (font_size * 0.045).clamp(0.8, 2.0);
    match style {
        1 => ShadowStyle {
            offset_x: unit * 0.8,
            offset_y: unit * 0.8,
            opacity: 0.34,
        },
        2 => ShadowStyle {
            offset_x: unit,
            offset_y: unit,
            opacity: 0.44,
        },
        3 => ShadowStyle {
            offset_x: unit * 1.2,
            offset_y: unit * 1.2,
            opacity: 0.55,
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
    let luminance = 0.299 * fill[0] + 0.587 * fill[1] + 0.114 * fill[2];
    if luminance < 0.45 {
        [1.0, 1.0, 1.0, fill[3]]
    } else {
        [0.0, 0.0, 0.0, fill[3]]
    }
}

#[derive(Deserialize)]
struct FramePayload {
    items: Vec<FrameItemPayload>,
}

#[derive(Deserialize)]
struct FrameItemPayload {
    text: String,
    #[serde(default)]
    count_text: Option<String>,
    x: f64,
    y: f64,
    color_argb: i32,
    #[serde(default = "default_font_size_multiplier")]
    font_size_multiplier: f64,
}

fn default_font_size_multiplier() -> f64 {
    1.0
}

#[derive(Clone)]
struct FrameItem {
    text: String,
    count_text: Option<String>,
    x: f64,
    y: f64,
    color_argb: i32,
    font_size: f32,
    outline_style: u8,
    shadow_style: u8,
    opacity: f32,
}

const NEXT2_WGSL: &str = r#"
struct VsIn {
    @location(0) pos: vec2<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) color: vec4<f32>,
    @location(3) outline_color: vec4<f32>,
    @location(4) params: vec4<f32>,
};

struct VsOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) outline_color: vec4<f32>,
    @location(3) params: vec4<f32>,
};

@group(0) @binding(0) var atlas_tex: texture_2d<f32>;
@group(0) @binding(1) var atlas_sampler: sampler;

@vertex
fn vs_main(v: VsIn) -> VsOut {
    var o: VsOut;
    o.pos = vec4<f32>(v.pos, 0.0, 1.0);
    o.uv = v.uv;
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
    let texel = textureSample(atlas_tex, atlas_sampler, v.uv).r;
    let dist = texel;
    let spread = max(v.params.x, 0.001);
    let outline_px = max(v.params.y, 0.0);

    let d = (dist - 0.5) * spread;
    let px = fwidth(d);

    let fill_alpha = smoothstep(-px, px, -d);
    let outline_edge = outline_px;
    let outline_alpha = smoothstep(outline_edge + px, outline_edge - px, abs(d));
    let stroke_alpha = max(outline_alpha - fill_alpha, 0.0);

    let color = v.outline_color * stroke_alpha + v.color * fill_alpha;
    return vec4<f32>(color.rgb, color.a);
}
"#;
