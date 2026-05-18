use std::collections::{HashMap, HashSet};
use std::fs;
use std::hash::{Hash, Hasher};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::thread;
use std::time::Duration;

use bytemuck::{Pod, Zeroable};
use fdsm::bezier::scanline::FillRule;
use fdsm::correct_error::{correct_error_mtsdf, ErrorCorrectionConfig};
use fdsm::generate::generate_mtsdf;
use fdsm::render::correct_sign_mtsdf;
use fdsm::shape::{Contour, Shape};
use fdsm::transform::Transform;
use image::{buffer::ConvertBuffer, Rgba32FImage, RgbaImage};
#[cfg(any(target_os = "macos", target_os = "ios"))]
use metal::foreign_types::ForeignType;
use nalgebra::{Affine2, Similarity2, Vector2};
use serde::Deserialize;
use ttf_parser::{Face, GlyphId};

use super::present::{attach_present_texture, signal_frame_ready, PresentTarget};

const INITIAL_WIDTH: u32 = 2;
const INITIAL_HEIGHT: u32 = 2;
const TICK_INTERVAL: Duration = Duration::from_millis(16);
const BASE_ATLAS_SIZE: u32 = 2048;
const MSDF_RANGE: f64 = 6.0;
const MAX_FONT_COLLECTION_FACES: u32 = 32;
const EDGE_COLORING_CORNER_THRESHOLD: f64 = 0.03;
const EDGE_COLORING_SEED: u64 = 69441337420;
const ATLAS_GLYPH_PADDING: u32 = 2;
const SHADOW_ALPHA_SCALE: f32 = 0.85;
const MISSING_GLYPH_FALLBACK: char = '□';
const FALLBACK_GLYPH_ADVANCE_RATIO: f32 = 0.58;

const SYSTEM_FONT_FALLBACK_PATHS: &[&str] = &[
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/CJKSymbolsFallback.ttc",
    "/System/Library/Fonts/Apple Symbols.ttf",
    "/System/Library/Fonts/Apple Color Emoji.ttc",
];

static FONT_DATA: &[u8] = include_bytes!("../../../assets/subfont.ttf");

#[derive(Clone)]
pub struct RenderFrameInput {
    pub frame_json: String,
    pub font_size: f32,
    pub outline_width: f32,
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
            ascent = ascent.max(scale_metric_to_px(font.face.ascender() as f32, &font.face, px));
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
        self.fonts.iter().any(|font| font.face.glyph_index(ch).is_some())
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

    for path in SYSTEM_FONT_FALLBACK_PATHS {
        if let Ok(bytes) = fs::read(path) {
            let _ = load_faces_from_owned_bytes(bytes.into_boxed_slice(), &mut seen, &mut fonts);
        }
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
    let advance = scale_metric_to_px(advance_units, face, px)
        .max(px * FALLBACK_GLYPH_ADVANCE_RATIO);

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
                            blend: Some(wgpu::BlendState::PREMULTIPLIED_ALPHA_BLENDING),
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
        let outline_width = if input.outline_width.is_finite() {
            input.outline_width.clamp(0.0, 4.0)
        } else {
            0.0
        };
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
                outline_width,
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

            let outline_px = resolve_outline_px(item.font_size, item.outline_width);
            let shadow = resolve_shadow(item.font_size, item.shadow_style);
            let fill_color = argb_to_linear(item.color_argb, item.opacity);
            let outline_color = stroke_color(fill_color);
            let shadow_color = [0.0, 0.0, 0.0, shadow.opacity * item.opacity * SHADOW_ALPHA_SCALE];

            let mut cursor_x = item.x as f32;
            let quantized_size = item.font_size.round().clamp(8.0, 128.0) as u32;
            let baseline_y = item.y as f32 + self.atlas.line_ascent(quantized_size);

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
                    self.push_quad(
                        glyph_left + shadow.offset_x,
                        glyph_top + shadow.offset_y,
                        glyph_right + shadow.offset_x,
                        glyph_bottom + shadow.offset_y,
                        entry.uv_min,
                        entry.uv_max,
                        shadow_color,
                        shadow_color,
                        [entry.spread, 0.0, self.width as f32, self.height as f32],
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
                    [entry.spread, outline_px, self.width as f32, self.height as f32],
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
    outline_width: f32,
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
    let texel = textureSample(atlas_tex, atlas_sampler, v.uv);
    let dist_msdf = median3(texel.r, texel.g, texel.b);
    let dist_sdf = texel.a;
    let spread = max(v.params.x, 0.001);
    let outline_px = max(v.params.y, 0.0);

    let d_fill = (dist_msdf - 0.5) * spread;
    let px_fill = max(fwidth(d_fill), 0.0001);
    let fill_coverage_aa = smoothstep(-px_fill, px_fill, d_fill);

    let d_outline = (dist_sdf - 0.5) * spread;
    let px_outline = max(fwidth(d_outline), 0.0001);

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
