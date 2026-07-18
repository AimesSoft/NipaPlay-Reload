use std::collections::{HashMap, HashSet};
use std::ffi::c_void;
#[cfg(target_os = "linux")]
use std::ffi::{c_char, CString};
use std::fs;
use std::hash::{Hash, Hasher};
use std::io::Write;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::thread;
use std::time::Duration;

static LOG_FILE: OnceLock<Mutex<std::fs::File>> = OnceLock::new();

pub(crate) fn n2log(msg: &str) {
    let file = LOG_FILE.get_or_init(|| {
        let path = std::env::temp_dir().join("next2_debug.log");
        Mutex::new(std::fs::File::create(path).unwrap())
    });
    if let Ok(mut f) = file.lock() {
        let _ = writeln!(f, "[next2] {}", msg);
        // Don't flush per-call: a synchronous fsync on every log line was a
        // stall source on the MSDF rasterization hot path (5+ logs per new
        // glyph). The OS buffers the write and flushes on drop/close. Error
        // and panic paths still log, just without forcing an fsync.
    }
}

use base64::Engine as _;
use bytemuck::{Pod, Zeroable};
use fdsm::bezier::scanline::FillRule;
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

#[cfg(target_os = "linux")]
use super::present::attach_present_gl_texture;
#[cfg(target_os = "windows")]
use super::present::create_dx12_shared_present_texture;
use super::present::{attach_present_texture, signal_frame_ready, PresentTarget};

#[cfg(target_os = "android")]
use ndk_sys::ANativeWindow;

#[cfg(target_os = "android")]
#[link(name = "android")]
extern "C" {
    fn ANativeWindow_release(window: *mut ANativeWindow);
}

const INITIAL_WIDTH: u32 = 2;
const INITIAL_HEIGHT: u32 = 2;
const TICK_INTERVAL: Duration = Duration::from_millis(16);
const BASE_ATLAS_SIZE: u32 = 8192;
const MSDF_RANGE: f64 = 6.0;
const MAX_FONT_COLLECTION_FACES: u32 = 32;
const EDGE_COLORING_CORNER_THRESHOLD: f64 = 0.03;
const EDGE_COLORING_SEED: u64 = 69441337420;
const ATLAS_GLYPH_PADDING: u32 = 2;
const EMOJI_ATLAS_SIZE: u32 = 2048;
const EMOJI_SDF_SPREAD: f32 = 8.0;
const EMOJI_OUTLINE_SCALE: f32 = 0.58;
const EMOJI_SIDE_BEARING_RATIO: f32 = 0.08;
const GLYPH_MODE_TEXT: f32 = 0.0;
const GLYPH_MODE_EMOJI: f32 = 1.0;
const SHADOW_ALPHA_SCALE: f32 = 1.0;
/// Shadow render texture scale relative to the screen. 0.5 renders the shadow
/// mask/blur at half resolution (1/4 the pixel area); the shadow is blurred
/// anyway so the visual difference is negligible while GPU pixel load on the
/// shadow passes drops ~75%.
const SHADOW_RENDER_SCALE: f32 = 0.5;
const MISSING_GLYPH_FALLBACK: char = '□';
const FALLBACK_GLYPH_ADVANCE_RATIO: f32 = 0.58;

static FONT_DATA: &[u8] = include_bytes!("../../../../assets/subfont.ttf");
static NEXT2_FALLBACK_FONTS: &[&[u8]] = &[
    include_bytes!("../../../assets/next2_fonts/NotoSansYi-Regular.ttf"),
    include_bytes!("../../../assets/next2_fonts/NotoSansGeorgian-Regular.ttf"),
    include_bytes!("../../../assets/next2_fonts/NotoSansLao-Regular.ttf"),
];

#[derive(Clone)]
pub struct RenderFrameInput {
    pub frame_json: String,
    pub font_size: f32,
    pub outline_width: f32,
    pub shadow_style: u8,
    pub opacity: f32,
    pub custom_font_family: String,
    pub custom_font_file_path: String,
}

#[cfg(target_os = "windows")]
#[derive(Clone, Copy)]
pub struct DxgiSharedTextureInfo {
    pub shared_handle: usize,
    pub width: u32,
    pub height: u32,
}

pub enum EngineCommand {
    AttachPresentTexture {
        raw_target_ptr: usize,
        width: u32,
        height: u32,
        bytes_per_row: u32,
        reply: Option<mpsc::Sender<bool>>,
    },
    #[cfg(target_os = "windows")]
    CreateDxgiSharedTexture {
        width: u32,
        height: u32,
        reply: mpsc::Sender<Option<DxgiSharedTextureInfo>>,
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

#[derive(Clone)]
pub struct FontSource {
    pub family: String,
    pub bytes: Box<[u8]>,
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

pub fn poll_frame_ready(handle: u64) -> bool {
    let Some(entry) = lookup_engine(handle) else {
        return false;
    };
    entry.frame_ready.swap(false, Ordering::AcqRel)
}

#[cfg(target_os = "linux")]
pub type GlProcLoader = unsafe extern "C" fn(*const c_char) -> *const c_void;

#[cfg(target_os = "linux")]
struct LinuxGlEngineEntry {
    width: u32,
    height: u32,
    frame_ready: Arc<AtomicBool>,
    pending_input: Option<RenderFrameInput>,
    pending_reset: bool,
    ctx: Option<Arc<EngineDeviceContext>>,
    renderer: Option<Next2Renderer>,
}

#[cfg(target_os = "linux")]
struct LinuxGlEngineRegistry {
    next_handle: AtomicU64,
    entries: Mutex<HashMap<u64, LinuxGlEngineEntry>>,
}

#[cfg(target_os = "linux")]
static LINUX_GL_REGISTRY: OnceLock<LinuxGlEngineRegistry> = OnceLock::new();

#[cfg(target_os = "linux")]
fn linux_gl_registry() -> &'static LinuxGlEngineRegistry {
    LINUX_GL_REGISTRY.get_or_init(|| LinuxGlEngineRegistry {
        next_handle: AtomicU64::new(1),
        entries: Mutex::new(HashMap::new()),
    })
}

#[cfg(target_os = "linux")]
pub fn create_linux_gl_engine(width: u32, height: u32) -> Result<u64, String> {
    let handle = linux_gl_registry()
        .next_handle
        .fetch_add(1, Ordering::Relaxed)
        .max(1);

    let mut guard = linux_gl_registry()
        .entries
        .lock()
        .map_err(|_| "linux GL engine registry lock poisoned".to_string())?;
    guard.insert(
        handle,
        LinuxGlEngineEntry {
            width: width.max(INITIAL_WIDTH),
            height: height.max(INITIAL_HEIGHT),
            frame_ready: Arc::new(AtomicBool::new(true)),
            pending_input: None,
            pending_reset: false,
            ctx: None,
            renderer: None,
        },
    );

    n2log(&format!(
        "linux GL engine created: {}x{}",
        width.max(INITIAL_WIDTH),
        height.max(INITIAL_HEIGHT)
    ));
    Ok(handle)
}

#[cfg(target_os = "linux")]
pub fn remove_linux_gl_engine(handle: u64) -> bool {
    if handle == 0 {
        return false;
    }
    match linux_gl_registry().entries.lock() {
        Ok(mut guard) => guard.remove(&handle).is_some(),
        Err(_) => false,
    }
}

#[cfg(target_os = "linux")]
pub fn poll_linux_gl_frame_ready(handle: u64) -> bool {
    if handle == 0 {
        return false;
    }
    let Ok(guard) = linux_gl_registry().entries.lock() else {
        return false;
    };
    guard
        .get(&handle)
        .map(|entry| entry.frame_ready.load(Ordering::Acquire))
        .unwrap_or(false)
}

#[cfg(target_os = "linux")]
pub fn resize_linux_gl_engine(handle: u64, width: u32, height: u32) -> bool {
    if handle == 0 {
        return false;
    }
    let Ok(mut guard) = linux_gl_registry().entries.lock() else {
        return false;
    };
    let Some(entry) = guard.get_mut(&handle) else {
        return false;
    };
    entry.width = width.max(INITIAL_WIDTH);
    entry.height = height.max(INITIAL_HEIGHT);
    entry.frame_ready.store(true, Ordering::Release);
    true
}

#[cfg(target_os = "linux")]
pub fn reset_linux_gl_engine(handle: u64) -> bool {
    if handle == 0 {
        return false;
    }
    let Ok(mut guard) = linux_gl_registry().entries.lock() else {
        return false;
    };
    let Some(entry) = guard.get_mut(&handle) else {
        return false;
    };
    entry.pending_reset = true;
    entry.frame_ready.store(true, Ordering::Release);
    true
}

#[cfg(target_os = "linux")]
pub fn set_linux_gl_frame(handle: u64, input: RenderFrameInput) -> bool {
    if handle == 0 {
        return false;
    }
    let Ok(mut guard) = linux_gl_registry().entries.lock() else {
        return false;
    };
    let Some(entry) = guard.get_mut(&handle) else {
        return false;
    };
    entry.pending_input = Some(input);
    entry.frame_ready.store(true, Ordering::Release);
    true
}

#[cfg(target_os = "linux")]
fn create_linux_gl_device_context(loader: GlProcLoader) -> Result<Arc<EngineDeviceContext>, String> {
    use wgpu_hal::Adapter as _;

    let exposed = unsafe {
        <wgpu_hal::api::Gles as wgpu_hal::Api>::Adapter::new_external(
            |name| {
                let Ok(name) = CString::new(name) else {
                    return std::ptr::null();
                };
                loader(name.as_ptr())
            },
            wgpu::GlBackendOptions::default(),
        )
    }
    .ok_or_else(|| "wgpu-hal: external GLES adapter init failed".to_string())?;

    let limits = exposed.capabilities.limits.clone();
    let open = unsafe {
        exposed.adapter.open(
            wgpu::Features::empty(),
            &limits,
            &wgpu::MemoryHints::Performance,
        )
    }
    .map_err(|err| format!("wgpu-hal: open external GLES device failed: {err:?}"))?;

    let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
        backends: wgpu::Backends::GL,
        flags: wgpu::InstanceFlags::default(),
        memory_budget_thresholds: wgpu::MemoryBudgetThresholds::default(),
        backend_options: wgpu::BackendOptions::default(),
    });
    let adapter = unsafe { instance.create_adapter_from_hal::<wgpu_hal::api::Gles>(exposed) };
    let device_desc = wgpu::DeviceDescriptor {
        label: Some("next2 linux external GL device"),
        required_features: wgpu::Features::empty(),
        required_limits: limits,
        experimental_features: wgpu::ExperimentalFeatures::disabled(),
        memory_hints: wgpu::MemoryHints::Performance,
        trace: wgpu::Trace::Off,
    };
    let (device, queue) = unsafe {
        adapter.create_device_from_hal::<wgpu_hal::api::Gles>(open, &device_desc)
    }
    .map_err(|err| format!("wgpu: create external GLES device failed: {err:?}"))?;

    device.on_uncaptured_error(Arc::new(|err| {
        eprintln!("wgpu linux GL uncaptured error: {err}");
    }));

    Ok(Arc::new(EngineDeviceContext {
        device: Arc::new(device),
        queue: Arc::new(queue),
    }))
}

#[cfg(target_os = "linux")]
pub fn render_linux_gl_texture(
    handle: u64,
    texture_name: u32,
    width: u32,
    height: u32,
    loader: GlProcLoader,
) -> bool {
    if handle == 0 || texture_name == 0 {
        return false;
    }

    let width = width.max(INITIAL_WIDTH);
    let height = height.max(INITIAL_HEIGHT);
    let Ok(mut guard) = linux_gl_registry().entries.lock() else {
        return false;
    };
    let Some(entry) = guard.get_mut(&handle) else {
        return false;
    };

    if entry.ctx.is_none() {
        let ctx = match create_linux_gl_device_context(loader) {
            Ok(ctx) => ctx,
            Err(err) => {
                n2log(&format!("linux GL context init failed: {err}"));
                return false;
            }
        };
        entry.ctx = Some(ctx);
    }
    let ctx = Arc::clone(entry.ctx.as_ref().unwrap());

    if entry.renderer.is_none() {
        let renderer = match Next2Renderer::new(Arc::clone(&ctx), width, height, None) {
            Ok(renderer) => renderer,
            Err(err) => {
                n2log(&format!("linux GL renderer init failed: {err}"));
                return false;
            }
        };
        entry.renderer = Some(renderer);
        entry.width = width;
        entry.height = height;
        entry.frame_ready.store(true, Ordering::Release);
    }

    let size_changed = entry.width != width || entry.height != height;
    if size_changed {
        entry.width = width;
        entry.height = height;
    }
    let pending_reset = std::mem::take(&mut entry.pending_reset);
    let pending_input = entry.pending_input.take();
    let mut should_draw = entry.frame_ready.load(Ordering::Acquire) || size_changed;

    let renderer = entry.renderer.as_mut().unwrap();
    if size_changed {
        let _ = renderer.resize(width, height);
    }
    if pending_reset {
        renderer.reset_scene();
        should_draw = true;
    }
    if let Some(input) = pending_input {
        let font_source = load_custom_font_source(
            input.custom_font_family.as_str(),
            input.custom_font_file_path.as_str(),
        )
        .ok()
        .flatten();
        if renderer.update_frame(input, font_source) {
            should_draw = true;
        } else {
            entry.frame_ready.store(false, Ordering::Release);
            return false;
        }
    }

    if !should_draw {
        return true;
    }

    let Some(mut target) = attach_present_gl_texture(ctx.device.as_ref(), texture_name, width, height)
    else {
        n2log("linux GL attach present texture failed");
        return false;
    };
    renderer.draw_to_present(&mut target);
    let _ = ctx.device.poll(wgpu::PollType::wait_indefinitely());
    entry.frame_ready.store(false, Ordering::Release);
    true
}

pub fn create_engine(width: u32, height: u32) -> Result<u64, String> {
    let width = width.max(INITIAL_WIDTH);
    let height = height.max(INITIAL_HEIGHT);

    let ctx = device_context()?;

    n2log(&format!("engine created: {}x{}", width, height));

    let mtl_device_ptr = extract_mtl_device_ptr(ctx.device.as_ref()) as usize;

    let (cmd_tx, cmd_rx) = mpsc::channel::<EngineCommand>();
    let frame_ready = Arc::new(AtomicBool::new(false));
    let frame_ready_thread = Arc::clone(&frame_ready);

    thread::Builder::new()
        .name("next2-engine".to_string())
        .spawn(move || {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                run_engine_loop(ctx, width, height, frame_ready_thread, cmd_rx);
            }));
            if let Err(e) = result {
                if let Some(s) = e.downcast_ref::<String>() {
                    n2log(&format!("ENGINE THREAD PANIC: {}", s));
                } else if let Some(s) = e.downcast_ref::<&str>() {
                    n2log(&format!("ENGINE THREAD PANIC: {}", s));
                } else {
                    n2log("ENGINE THREAD PANIC: unknown");
                }
            }
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
    #[cfg(target_os = "android")]
    instance: Arc<wgpu::Instance>,
    #[cfg(target_os = "android")]
    adapter: Arc<wgpu::Adapter>,
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
}

static DEVICE_CONTEXT: OnceLock<Result<Arc<EngineDeviceContext>, String>> = OnceLock::new();

fn device_context() -> Result<Arc<EngineDeviceContext>, String> {
    let init_result = DEVICE_CONTEXT.get_or_init(|| {
        let backends = if cfg!(target_os = "windows") {
            wgpu::Backends::DX12
        } else if cfg!(any(target_os = "macos", target_os = "ios")) {
            wgpu::Backends::METAL
        } else if cfg!(target_os = "android") {
            wgpu::Backends::VULKAN
        } else {
            wgpu::Backends::PRIMARY
        };
        let instance = Arc::new(wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends,
            flags: wgpu::InstanceFlags::default(),
            memory_budget_thresholds: wgpu::MemoryBudgetThresholds::default(),
            backend_options: wgpu::BackendOptions::default(),
        }));

        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
        }))
        .map_err(|err| format!("wgpu: request_adapter failed: {err:?}"))?;
        let adapter = Arc::new(adapter);

        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("next2 render device"),
            required_features: wgpu::Features::empty(),
            required_limits: adapter.limits(),
            experimental_features: wgpu::ExperimentalFeatures::disabled(),
            memory_hints: wgpu::MemoryHints::Performance,
            trace: wgpu::Trace::Off,
        }))
        .map_err(|err| format!("wgpu: request_device failed: {err:?}"))?;

        device.on_uncaptured_error(Arc::new(|err| {
            eprintln!("wgpu uncaptured error: {err}");
        }));

        Ok(Arc::new(EngineDeviceContext {
            #[cfg(target_os = "android")]
            instance,
            #[cfg(target_os = "android")]
            adapter,
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

#[cfg(target_os = "android")]
#[allow(dead_code)]
pub fn attach_present_surface(
    handle: u64,
    native_window_ptr: *mut c_void,
    width: u32,
    height: u32,
) -> bool {
    fn release_window(native_window_ptr: *mut c_void) {
        if native_window_ptr.is_null() {
            return;
        }
        unsafe { ANativeWindow_release(native_window_ptr as *mut ANativeWindow) };
    }

    let Some(entry) = lookup_engine(handle) else {
        release_window(native_window_ptr);
        return false;
    };
    if native_window_ptr.is_null() {
        return false;
    }
    let (reply_tx, reply_rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::AttachPresentTexture {
            raw_target_ptr: native_window_ptr as usize,
            width,
            height,
            bytes_per_row: 0,
            reply: Some(reply_tx),
        })
        .is_err()
    {
        release_window(native_window_ptr);
        return false;
    }
    reply_rx
        .recv_timeout(Duration::from_secs(2))
        .unwrap_or(false)
}

#[cfg(not(target_os = "android"))]
#[allow(dead_code)]
pub fn attach_present_surface(
    _handle: u64,
    _native_window_ptr: *mut c_void,
    _width: u32,
    _height: u32,
) -> bool {
    false
}

#[cfg(target_os = "windows")]
pub fn create_windows_dxgi_shared_texture(
    handle: u64,
    width: u32,
    height: u32,
) -> Option<DxgiSharedTextureInfo> {
    let entry = lookup_engine(handle)?;
    let (reply_tx, reply_rx) = mpsc::channel();
    entry
        .cmd_tx
        .send(EngineCommand::CreateDxgiSharedTexture {
            width,
            height,
            reply: reply_tx,
        })
        .ok()?;
    reply_rx.recv_timeout(Duration::from_secs(2)).ok().flatten()
}

fn run_engine_loop(
    ctx: Arc<EngineDeviceContext>,
    mut width: u32,
    mut height: u32,
    frame_ready: Arc<AtomicBool>,
    cmd_rx: mpsc::Receiver<EngineCommand>,
) {
    let mut renderer = match Next2Renderer::new(Arc::clone(&ctx), width, height, None) {
        Ok(renderer) => renderer,
        Err(_) => return,
    };
    let mut present_target: Option<PresentTarget> = None;
    let mut running = true;
    let mut has_pending_frame = false;
    // Diagnostics (temporary): per-60-frame avg/max of draw_to_present.
    let mut diag_draw_count: u32 = 0;
    let mut diag_draw_ms_sum: f32 = 0.0;
    let mut diag_draw_ms_max: f32 = 0.0;

    while running {
        // Drain completed async glyph prefetches before any command/draw this
        // iteration, so prefetched glyphs land in the atlas before they're
        // needed by `draw_to_present`. Non-blocking; cheap when empty.
        renderer.drain_prefetch(ctx.queue.as_ref());
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
                    raw_target_ptr,
                    width: w,
                    height: h,
                    bytes_per_row,
                    reply,
                } => {
                    let attached;
                    #[cfg(target_os = "android")]
                    {
                        attached = match super::present::attach_present_surface(
                            ctx.instance.as_ref(),
                            ctx.adapter.as_ref(),
                            ctx.device.as_ref(),
                            raw_target_ptr as *mut c_void,
                            w.max(1),
                            h.max(1),
                        ) {
                            Ok(target) => {
                                present_target = Some(target);
                                true
                            }
                            Err(_) => {
                                present_target = None;
                                false
                            }
                        };
                    }
                    #[cfg(not(target_os = "android"))]
                    {
                        attached = if let Some(target) = attach_present_texture(
                            ctx.device.as_ref(),
                            raw_target_ptr,
                            w.max(1),
                            h.max(1),
                            bytes_per_row,
                        ) {
                            present_target = Some(target);
                            true
                        } else {
                            present_target = None;
                            false
                        };
                    }
                    if let Some(reply_tx) = reply {
                        let _ = reply_tx.send(attached);
                    }
                    if !attached {
                        continue;
                    }
                    width = w.max(1);
                    height = h.max(1);
                    let _ = renderer.resize(width, height);
                    has_pending_frame = true;
                }
                #[cfg(target_os = "windows")]
                EngineCommand::CreateDxgiSharedTexture {
                    width: w,
                    height: h,
                    reply,
                } => {
                    let w = w.max(1);
                    let h = h.max(1);
                    let response = if let Some((target, shared_handle)) =
                        create_dx12_shared_present_texture(ctx.device.as_ref(), w, h)
                    {
                        present_target = Some(target);
                        width = w;
                        height = h;
                        let _ = renderer.resize(width, height);
                        has_pending_frame = true;
                        Some(DxgiSharedTextureInfo {
                            shared_handle,
                            width,
                            height,
                        })
                    } else {
                        present_target = None;
                        None
                    };
                    let _ = reply.send(response);
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
                    let font_source = load_custom_font_source(
                        input.custom_font_family.as_str(),
                        input.custom_font_file_path.as_str(),
                    )
                    .ok()
                    .flatten();
                    let ok = renderer.update_frame(input, font_source);
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

        // Re-render not only on a freshly submitted frame, but also on idle
        // 16ms ticks while scroll interpolation is active. needs_interpolation_render
        // is true only when there are scroll items AND a frame was submitted
        // within the last 50ms — so paused/empty scenes add no continuous GPU
        // load. draw_to_present recomputes interp_dt internally, advancing
        // scroll items between Dart submissions (30fps submit → ~60fps motion).
        let needs_interp = renderer.needs_interpolation_render();
        if has_pending_frame || needs_interp {
            if let Some(target) = present_target.as_mut() {
                let draw_start = std::time::Instant::now();
                renderer.draw_to_present(target);
                let draw_ms = draw_start.elapsed().as_secs_f32() * 1000.0;
                signal_frame_ready(ctx.queue.as_ref(), Arc::clone(&frame_ready));
                diag_draw_count += 1;
                diag_draw_ms_sum += draw_ms;
                if draw_ms > diag_draw_ms_max {
                    diag_draw_ms_max = draw_ms;
                }
                if diag_draw_count >= 60 {
                    n2log(&format!(
                        "DFM+ draw diag: n={} avg={:.2}ms max={:.2}ms | sync_fb={} drain={}",
                        diag_draw_count,
                        diag_draw_ms_sum / diag_draw_count as f32,
                        diag_draw_ms_max,
                        SYNC_FALLBACK_COUNT.swap(0, std::sync::atomic::Ordering::Relaxed),
                        DRAIN_COUNT.swap(0, std::sync::atomic::Ordering::Relaxed)
                    ));
                    // Flush so the diag line is visible in next2_debug.log
                    // immediately (n2log otherwise buffers; Android investigation
                    // relies on reading the file on a rooted device).
                    if let Some(m) = LOG_FILE.get() {
                        if let Ok(mut f) = m.lock() {
                            let _ = f.flush();
                        }
                    }
                    diag_draw_count = 0;
                    diag_draw_ms_sum = 0.0;
                    diag_draw_ms_max = 0.0;
                }
            } else {
                frame_ready.store(false, Ordering::Release);
            }

            has_pending_frame = false;
        }
    }
}

fn load_custom_font_source(family: &str, file_path: &str) -> Result<Option<FontSource>, String> {
    let family = family.trim();
    let file_path = file_path.trim();
    if family.is_empty() || file_path.is_empty() {
        return Ok(None);
    }

    let bytes = fs::read(file_path)
        .map_err(|err| format!("next2: failed to read custom font '{file_path}': {err}"))?;
    if bytes.is_empty() {
        return Ok(None);
    }

    Ok(Some(FontSource {
        family: family.to_string(),
        bytes: bytes.into_boxed_slice(),
    }))
}
