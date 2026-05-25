use std::collections::{HashMap, HashSet};
use std::ffi::c_void;
use std::hash::{Hash, Hasher};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex, OnceLock};
use std::thread;
use std::time::Duration;

use base64::Engine as _;
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
const BASE_ATLAS_SIZE: u32 = 2048;
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
const SHADOW_RENDER_SCALE: u32 = 1;
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
}

pub struct Next2ReadbackFrame {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
}

pub enum EngineCommand {
    AttachPresentTexture {
        raw_target_ptr: usize,
        width: u32,
        height: u32,
        bytes_per_row: u32,
        reply: Option<mpsc::Sender<bool>>,
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
    ReadbackFrame {
        reply: mpsc::Sender<Option<Next2ReadbackFrame>>,
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

pub fn poll_frame_ready(handle: u64) -> bool {
    lookup_engine(handle)
        .map(|entry| entry.frame_ready.swap(false, Ordering::AcqRel))
        .unwrap_or(false)
}

pub fn readback_frame_bgra(handle: u64) -> Option<Next2ReadbackFrame> {
    let entry = lookup_engine(handle)?;
    let (reply_tx, reply_rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::ReadbackFrame { reply: reply_tx })
        .is_err()
    {
        return None;
    }
    reply_rx.recv().ok().flatten()
}

pub fn create_engine(width: u32, height: u32) -> Result<u64, String> {
    let width = width.max(INITIAL_WIDTH);
    let height = height.max(INITIAL_HEIGHT);

    let ctx = device_context()?;

    let mtl_device_ptr = extract_mtl_device_ptr(ctx.device.as_ref()) as usize;

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
        let instance = Arc::new(wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::PRIMARY,
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
                EngineCommand::ReadbackFrame { reply } => {
                    let _ = reply.send(renderer.readback_frame_bgra());
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
            if let Some(target) = present_target.as_mut() {
                renderer.draw_to_present(target);
            } else {
                renderer.draw_to_offscreen();
            }
            signal_frame_ready(ctx.queue.as_ref(), Arc::clone(&frame_ready));
            has_pending_frame = false;
        }
    }
}
