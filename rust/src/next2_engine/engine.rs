use std::collections::{HashMap, HashSet};
use std::fs;
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
const MSDF_SPREAD: i32 = 8;
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
    offset_x: f32,
    offset_y: f32,
    advance: f32,
    spread: f32,
}

struct Next2GlyphAtlas {
    fonts: Vec<Font>,
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
            if let Some(metrics) = font.horizontal_line_metrics(px) {
                ascent = ascent.max(metrics.ascent.ceil());
            }
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
            .any(|font| font.lookup_glyph_index(ch) != 0)
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

    fn rasterize_from_fonts(
        &self,
        ch: char,
        px: f32,
    ) -> Option<(fontdue::Metrics, Vec<u8>)> {
        for font in &self.fonts {
            let glyph_index = font.lookup_glyph_index(ch);
            if glyph_index == 0 {
                continue;
            }
            let (metrics, bitmap) = font.rasterize_indexed(glyph_index, px);
            return Some((metrics, bitmap));
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
        let (metrics, bitmap) = self.rasterize_from_fonts(ch, px)?;
        let advance = metrics.advance_width.max(px * FALLBACK_GLYPH_ADVANCE_RATIO);

        if metrics.width == 0 || metrics.height == 0 || bitmap.is_empty() {
            self.entries.insert(
                (ch, quantized_size),
                GlyphAtlasEntry {
                    uv_min: [0.0, 0.0],
                    uv_max: [0.0, 0.0],
                    width: 0,
                    height: 0,
                    offset_x: metrics.xmin as f32,
                    offset_y: 0.0,
                    advance,
                    spread: 0.0,
                },
            );
            return Some(());
        }

        let glyph_w = metrics.width as u32;
        let glyph_h = metrics.height as u32;
        let padded_w = glyph_w.saturating_add((MSDF_SPREAD as u32) * 2).max(1);
        let padded_h = glyph_h.saturating_add((MSDF_SPREAD as u32) * 2).max(1);

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

        let msdf = generate_msdf_from_alpha(
            &bitmap,
            glyph_w as usize,
            glyph_h as usize,
            padded_w as usize,
            padded_h as usize,
            MSDF_SPREAD,
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
            &msdf,
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
            offset_x: metrics.xmin as f32 - MSDF_SPREAD as f32,
            // Align with fontdue PositiveYDown layout: y = -height - ymin.
            offset_y: -(metrics.height as f32) - metrics.ymin as f32 - MSDF_SPREAD as f32,
            advance,
            spread: MSDF_SPREAD as f32,
        };

        self.entries.insert((ch, quantized_size), entry);

        self.cursor_x = self.cursor_x.saturating_add(padded_w);
        self.row_height = self.row_height.max(padded_h);

        Some(())
    }
}

fn load_font_chain() -> Result<Vec<Font>, String> {
    let mut fonts = Vec::new();
    let mut seen = HashSet::new();

    let primary = Font::from_bytes(FONT_DATA, FontSettings::default())
        .map_err(|err| format!("load primary font failed: {err}"))?;
    seen.insert(primary.file_hash());
    fonts.push(primary);

    for path in SYSTEM_FONT_FALLBACK_PATHS {
        load_collection_fonts(path, &mut seen, &mut fonts);
    }

    if fonts.is_empty() {
        return Err("next2: no usable font faces loaded".to_string());
    }
    Ok(fonts)
}

fn load_collection_fonts(path: &str, seen: &mut HashSet<usize>, out: &mut Vec<Font>) {
    let Ok(bytes) = fs::read(path) else {
        return;
    };

    let mut loaded_any = false;
    for collection_index in 0..16u32 {
        let settings = FontSettings {
            collection_index,
            ..FontSettings::default()
        };
        match Font::from_bytes(bytes.clone(), settings) {
            Ok(font) => {
                loaded_any = true;
                let hash = font.file_hash();
                if seen.insert(hash) {
                    out.push(font);
                }
            }
            Err(err) => {
                if is_face_index_out_of_bounds(err) {
                    break;
                }
                if collection_index == 0 {
                    break;
                }
            }
        }
    }

    if !loaded_any {
        let _ = path;
    }
}

fn is_face_index_out_of_bounds(err: &str) -> bool {
    err.to_ascii_lowercase()
        .contains("face index is larger than the number of faces")
}

#[derive(Clone)]
struct MsdfEdgeSegment {
    ax: f32,
    ay: f32,
    bx: f32,
    by: f32,
    color: usize,
}

#[derive(Copy, Clone)]
struct ContourEdge {
    index: usize,
    reversed: bool,
}

struct Contour {
    edges: Vec<ContourEdge>,
    closed: bool,
}

fn generate_msdf_from_alpha(
    alpha_bitmap: &[u8],
    src_width: usize,
    src_height: usize,
    out_width: usize,
    out_height: usize,
    spread: i32,
) -> Vec<u8> {
    let mut out = vec![0u8; out_width * out_height * 4];
    if src_width == 0 || src_height == 0 {
        return out;
    }

    let count = out_width * out_height;
    let mut alpha = vec![0u8; count];
    let offset_x = ((out_width as i32 - src_width as i32) / 2).max(0) as usize;
    let offset_y = ((out_height as i32 - src_height as i32) / 2).max(0) as usize;

    for y in 0..src_height {
        for x in 0..src_width {
            let dst_x = x + offset_x;
            let dst_y = y + offset_y;
            if dst_x >= out_width || dst_y >= out_height {
                continue;
            }
            alpha[dst_y * out_width + dst_x] = alpha_bitmap[y * src_width + x];
        }
    }

    let inside: Vec<u8> = alpha
        .iter()
        .map(|a| if *a > 127 { 1u8 } else { 0u8 })
        .collect();

    let mut segments = build_segments(&alpha, out_width, out_height);
    if segments.is_empty() {
        for i in 0..count {
            let dst = i * 4;
            out[dst + 3] = 255;
        }
        return out;
    }

    color_segments(&mut segments);

    let mut edge_all = vec![0u8; count];
    let mut edge_r = vec![0u8; count];
    let mut edge_g = vec![0u8; count];
    let mut edge_b = vec![0u8; count];

    let mut has_r = false;
    let mut has_g = false;
    let mut has_b = false;

    for seg in &segments {
        match seg.color {
            0 => {
                rasterize_segment(seg, &mut edge_r, &mut edge_all, out_width, out_height);
                has_r = true;
            }
            1 => {
                rasterize_segment(seg, &mut edge_g, &mut edge_all, out_width, out_height);
                has_g = true;
            }
            _ => {
                rasterize_segment(seg, &mut edge_b, &mut edge_all, out_width, out_height);
                has_b = true;
            }
        }
    }

    let dist_all = edt(&edge_all, out_width, out_height);
    let dist_r = if has_r {
        edt(&edge_r, out_width, out_height)
    } else {
        dist_all.clone()
    };
    let dist_g = if has_g {
        edt(&edge_g, out_width, out_height)
    } else {
        dist_all.clone()
    };
    let dist_b = if has_b {
        edt(&edge_b, out_width, out_height)
    } else {
        dist_all
    };

    let spread_value = spread.max(1) as f32;
    for i in 0..count {
        let sign = if inside[i] == 1 { -1.0 } else { 1.0 };

        let mut r = 0.5 + sign * dist_r[i].sqrt() / spread_value;
        let mut g = 0.5 + sign * dist_g[i].sqrt() / spread_value;
        let mut b = 0.5 + sign * dist_b[i].sqrt() / spread_value;

        r = r.clamp(0.0, 1.0);
        g = g.clamp(0.0, 1.0);
        b = b.clamp(0.0, 1.0);

        let dst = i * 4;
        out[dst] = (r * 255.0).round() as u8;
        out[dst + 1] = (g * 255.0).round() as u8;
        out[dst + 2] = (b * 255.0).round() as u8;
        out[dst + 3] = 255;
    }

    out
}

fn build_segments(alpha: &[u8], width: usize, height: usize) -> Vec<MsdfEdgeSegment> {
    if width == 0 || height == 0 {
        return Vec::new();
    }

    let grid_w = width + 1;
    let mut corners = vec![0.0f32; grid_w * (height + 1)];

    for y in 0..=height {
        for x in 0..=width {
            let mut sum = 0.0f32;
            let mut count = 0usize;

            for dy in -1..=0 {
                let py = y as i32 + dy;
                if py < 0 || py >= height as i32 {
                    continue;
                }
                let row = py as usize * width;
                for dx in -1..=0 {
                    let px = x as i32 + dx;
                    if px < 0 || px >= width as i32 {
                        continue;
                    }
                    sum += alpha[row + px as usize] as f32 / 255.0;
                    count += 1;
                }
            }

            corners[y * grid_w + x] = if count == 0 { 0.0 } else { sum / count as f32 };
        }
    }

    let iso = 0.5f32;
    let mut segments = Vec::new();

    for y in 0..height {
        for x in 0..width {
            let corner_idx = y * grid_w + x;
            let c0 = corners[corner_idx];
            let c1 = corners[corner_idx + 1];
            let c3 = corners[corner_idx + grid_w];
            let c2 = corners[corner_idx + grid_w + 1];

            let mut mask = 0u8;
            if c0 >= iso {
                mask |= 1;
            }
            if c1 >= iso {
                mask |= 2;
            }
            if c2 >= iso {
                mask |= 4;
            }
            if c3 >= iso {
                mask |= 8;
            }
            if mask == 0 || mask == 15 {
                continue;
            }

            let center = (c0 + c1 + c2 + c3) * 0.25;
            let e0 = edge_point(x as f32, y as f32, c0, c1, iso, 0);
            let e1 = edge_point(x as f32, y as f32, c1, c2, iso, 1);
            let e2 = edge_point(x as f32, y as f32, c2, c3, iso, 2);
            let e3 = edge_point(x as f32, y as f32, c3, c0, iso, 3);

            let mut add_seg = |a: (f32, f32), b: (f32, f32)| {
                let dx = a.0 - b.0;
                let dy = a.1 - b.1;
                if dx * dx + dy * dy < 1e-6 {
                    return;
                }
                segments.push(MsdfEdgeSegment {
                    ax: a.0,
                    ay: a.1,
                    bx: b.0,
                    by: b.1,
                    color: 0,
                });
            };

            match mask {
                1 => add_seg(e3, e0),
                2 => add_seg(e0, e1),
                3 => add_seg(e3, e1),
                4 => add_seg(e1, e2),
                5 => {
                    if center >= iso {
                        add_seg(e0, e1);
                        add_seg(e2, e3);
                    } else {
                        add_seg(e3, e0);
                        add_seg(e1, e2);
                    }
                }
                6 => add_seg(e0, e2),
                7 => add_seg(e3, e2),
                8 => add_seg(e2, e3),
                9 => add_seg(e0, e2),
                10 => {
                    if center >= iso {
                        add_seg(e3, e0);
                        add_seg(e1, e2);
                    } else {
                        add_seg(e0, e1);
                        add_seg(e2, e3);
                    }
                }
                11 => add_seg(e1, e2),
                12 => add_seg(e1, e3),
                13 => add_seg(e0, e1),
                14 => add_seg(e0, e3),
                _ => {}
            }
        }
    }

    segments
}

fn edge_point(x: f32, y: f32, v0: f32, v1: f32, iso: f32, edge: u8) -> (f32, f32) {
    let denom = v1 - v0;
    let mut t = if denom.abs() < 1e-6 {
        0.5
    } else {
        (iso - v0) / denom
    };
    t = t.clamp(0.0, 1.0);

    match edge {
        0 => (x + t, y),
        1 => (x + 1.0, y + t),
        2 => (x + 1.0 - t, y + 1.0),
        3 => (x, y + 1.0 - t),
        _ => (x, y),
    }
}

fn point_key(x: f32, y: f32) -> i64 {
    let qx = (x * 1024.0).round() as i64;
    let qy = (y * 1024.0).round() as i64;
    (qx << 32) ^ (qy & 0xffff_ffff)
}

fn color_segments(segments: &mut [MsdfEdgeSegment]) {
    let mut adjacency: HashMap<i64, Vec<usize>> = HashMap::new();
    for (i, seg) in segments.iter().enumerate() {
        let key_a = point_key(seg.ax, seg.ay);
        let key_b = point_key(seg.bx, seg.by);
        adjacency.entry(key_a).or_default().push(i);
        adjacency.entry(key_b).or_default().push(i);
    }

    let mut visited = vec![false; segments.len()];
    for i in 0..segments.len() {
        if visited[i] {
            continue;
        }
        let contour = trace_contour(i, segments, &adjacency, &mut visited);
        assign_contour_colors(&contour, segments);
    }
}

fn trace_contour(
    start_index: usize,
    segments: &[MsdfEdgeSegment],
    adjacency: &HashMap<i64, Vec<usize>>,
    visited: &mut [bool],
) -> Contour {
    let mut edges = Vec::new();
    let start = &segments[start_index];

    visited[start_index] = true;
    edges.push(ContourEdge {
        index: start_index,
        reversed: false,
    });

    let start_key = point_key(start.ax, start.ay);
    let mut current_key = point_key(start.bx, start.by);
    let mut closed = false;

    loop {
        if current_key == start_key {
            closed = true;
            break;
        }

        let Some(candidates) = adjacency.get(&current_key) else {
            break;
        };

        let Some(&next_index) = candidates.iter().find(|idx| !visited[**idx]) else {
            break;
        };

        let next = &segments[next_index];
        let key_a = point_key(next.ax, next.ay);
        let key_b = point_key(next.bx, next.by);
        let (reversed, next_key) = if key_a == current_key {
            (false, key_b)
        } else if key_b == current_key {
            (true, key_a)
        } else {
            break;
        };

        visited[next_index] = true;
        edges.push(ContourEdge {
            index: next_index,
            reversed,
        });
        current_key = next_key;
    }

    Contour { edges, closed }
}

fn assign_contour_colors(contour: &Contour, segments: &mut [MsdfEdgeSegment]) {
    if contour.edges.is_empty() {
        return;
    }
    let corner_threshold = std::f32::consts::PI / 3.0;

    let mut dirs = Vec::with_capacity(contour.edges.len());
    for edge in &contour.edges {
        let seg = &segments[edge.index];
        let (dx, dy) = if edge.reversed {
            (seg.ax - seg.bx, seg.ay - seg.by)
        } else {
            (seg.bx - seg.ax, seg.by - seg.ay)
        };
        dirs.push((dx, dy));
    }

    let mut best_colors = Vec::new();
    let mut best_conflicts = usize::MAX;
    for start_color in 0..3usize {
        let colors = assign_colors(&dirs, corner_threshold, start_color);
        let conflicts = count_conflicts(&colors, &dirs, corner_threshold, contour.closed);
        if conflicts < best_conflicts {
            best_conflicts = conflicts;
            best_colors = colors;
        }
    }

    if best_colors.is_empty() {
        best_colors = assign_colors(&dirs, corner_threshold, 0);
    }

    for (i, edge) in contour.edges.iter().enumerate() {
        segments[edge.index].color = best_colors[i];
    }
}

fn assign_colors(dirs: &[(f32, f32)], threshold: f32, start_color: usize) -> Vec<usize> {
    let mut colors = vec![start_color; dirs.len()];
    let mut color = start_color;
    for i in 1..dirs.len() {
        if angle_between(dirs[i - 1], dirs[i]) > threshold {
            color = (color + 1) % 3;
        }
        colors[i] = color;
    }
    colors
}

fn count_conflicts(
    colors: &[usize],
    dirs: &[(f32, f32)],
    threshold: f32,
    closed: bool,
) -> usize {
    let mut conflicts = 0usize;
    for i in 1..dirs.len() {
        if angle_between(dirs[i - 1], dirs[i]) > threshold && colors[i] == colors[i - 1] {
            conflicts += 1;
        }
    }
    if closed && dirs.len() > 1 {
        if angle_between(dirs[dirs.len() - 1], dirs[0]) > threshold
            && colors[colors.len() - 1] == colors[0]
        {
            conflicts += 1;
        }
    }
    conflicts
}

fn angle_between(a: (f32, f32), b: (f32, f32)) -> f32 {
    let mag_a = (a.0 * a.0 + a.1 * a.1).sqrt();
    let mag_b = (b.0 * b.0 + b.1 * b.1).sqrt();
    if mag_a <= f32::EPSILON || mag_b <= f32::EPSILON {
        return 0.0;
    }
    let dot = (a.0 * b.0 + a.1 * b.1) / (mag_a * mag_b);
    dot.clamp(-1.0, 1.0).acos()
}

fn rasterize_segment(
    seg: &MsdfEdgeSegment,
    map: &mut [u8],
    all: &mut [u8],
    width: usize,
    height: usize,
) {
    let dx = seg.bx - seg.ax;
    let dy = seg.by - seg.ay;
    let steps = dx.abs().max(dy.abs()).ceil() as i32;

    let mut mark = |px: f32, py: f32| {
        let ix = px.round() as i32;
        let iy = py.round() as i32;
        if ix < 0 || iy < 0 || ix >= width as i32 || iy >= height as i32 {
            return;
        }
        let idx = iy as usize * width + ix as usize;
        map[idx] = 1;
        all[idx] = 1;
    };

    if steps <= 0 {
        mark(seg.ax, seg.ay);
        return;
    }

    for i in 0..=steps {
        let t = i as f32 / steps as f32;
        mark(seg.ax + dx * t, seg.ay + dy * t);
    }
}

fn edt(binary: &[u8], width: usize, height: usize) -> Vec<f32> {
    let count = width * height;
    let inf = 1.0e20f32;
    let mut data = vec![0.0f32; count];
    for i in 0..count {
        data[i] = if binary[i] == 1 { 0.0 } else { inf };
    }

    let max_dim = width.max(height);
    let mut f = vec![0.0f32; max_dim];
    let mut d = vec![0.0f32; max_dim];

    for x in 0..width {
        for y in 0..height {
            f[y] = data[y * width + x];
        }
        edt1d(&f, height, &mut d);
        for y in 0..height {
            data[y * width + x] = d[y];
        }
    }

    for y in 0..height {
        let row = y * width;
        for x in 0..width {
            f[x] = data[row + x];
        }
        edt1d(&f, width, &mut d);
        for x in 0..width {
            data[row + x] = d[x];
        }
    }

    data
}

fn edt1d(f: &[f32], n: usize, d: &mut [f32]) {
    if n == 0 {
        return;
    }

    let mut v = vec![0usize; n];
    let mut z = vec![0.0f32; n + 1];
    let mut k = 0usize;

    v[0] = 0;
    z[0] = -1.0e20;
    z[1] = 1.0e20;

    for q in 1..n {
        let mut s;
        while {
            let p = v[k];
            s = ((f[q] + (q * q) as f32) - (f[p] + (p * p) as f32))
                / (2.0 * (q as f32 - p as f32));
            s <= z[k] && k > 0
        } {
            k -= 1;
        }

        let p = v[k];
        s = ((f[q] + (q * q) as f32) - (f[p] + (p * p) as f32))
            / (2.0 * (q as f32 - p as f32));
        k += 1;
        v[k] = q;
        z[k] = s;
        z[k + 1] = 1.0e20;
    }

    k = 0;
    for q in 0..n {
        while z[k + 1] < q as f32 {
            k += 1;
        }
        let p = v[k];
        d[q] = (q as f32 - p as f32) * (q as f32 - p as f32) + f[p];
    }
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
    let texel = textureSample(atlas_tex, atlas_sampler, v.uv).rgb;
    let dist = median3(texel.r, texel.g, texel.b);
    let spread = max(v.params.x, 0.001);
    let outline_px = max(v.params.y, 0.0);

    let d = (dist - 0.5) * spread;
    let px = fwidth(d);
    let fill_alpha = smoothstep(-px, px, -d);
    let outline_alpha = smoothstep(outline_px + px, outline_px - px, abs(d));
    let stroke_alpha = max(outline_alpha - fill_alpha, 0.0);

    let color = v.outline_color * stroke_alpha + v.color * fill_alpha;
    return vec4<f32>(color.rgb, color.a);
}
"#;
