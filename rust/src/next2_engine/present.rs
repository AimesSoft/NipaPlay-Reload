use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

#[cfg(any(target_os = "macos", target_os = "ios"))]
use metal::foreign_types::ForeignType;
#[cfg(any(target_os = "macos", target_os = "ios"))]
use metal::MTLTextureType;
#[cfg(any(target_os = "macos", target_os = "ios"))]
use wgpu_hal::{api::Metal, CopyExtent};

#[cfg(target_os = "android")]
use std::{ffi::c_void, ptr::NonNull};
#[cfg(target_os = "android")]
use {
    ndk_sys::ANativeWindow,
    raw_window_handle::{
        AndroidDisplayHandle, AndroidNdkWindowHandle, RawDisplayHandle, RawWindowHandle,
    },
    wgpu::SurfaceTargetUnsafe,
};

#[cfg(target_os = "android")]
#[link(name = "android")]
extern "C" {
    fn ANativeWindow_release(window: *mut ANativeWindow);
}

const BGRA8_UNORM_VIEW_FORMATS: &[wgpu::TextureFormat] = &[wgpu::TextureFormat::Bgra8UnormSrgb];

pub(crate) enum PresentTarget {
    Texture(PresentTextureTarget),
    #[cfg(target_os = "android")]
    Surface(PresentSurfaceTarget),
}

pub(crate) struct PresentTextureTarget {
    render_texture: wgpu::Texture,
    pub(crate) width: u32,
    pub(crate) height: u32,
    _bytes_per_row: u32,
}

impl PresentTextureTarget {
    pub(crate) fn render_texture(&self) -> &wgpu::Texture {
        &self.render_texture
    }
}

impl PresentTarget {
    #[cfg(target_os = "android")]
    pub(crate) fn as_surface_mut(&mut self) -> Option<&mut PresentSurfaceTarget> {
        match self {
            PresentTarget::Surface(surface) => Some(surface),
            _ => None,
        }
    }
}

#[cfg(target_os = "android")]
pub(crate) struct PresentSurfaceTarget {
    instance: Arc<wgpu::Instance>,
    surface: wgpu::Surface<'static>,
    config: wgpu::SurfaceConfiguration,
    _window: AndroidNativeWindow,
}

#[cfg(target_os = "android")]
impl PresentSurfaceTarget {
    pub(crate) fn format(&self) -> wgpu::TextureFormat {
        self.config.format
    }

    pub(crate) fn width(&self) -> u32 {
        self.config.width
    }

    pub(crate) fn height(&self) -> u32 {
        self.config.height
    }

    pub(crate) fn surface(&self) -> &wgpu::Surface<'static> {
        &self.surface
    }

    pub(crate) fn configure(&mut self, device: &wgpu::Device) {
        self.surface.configure(device, &self.config);
    }

    pub(crate) fn recreate(&mut self, device: &wgpu::Device) -> Result<(), String> {
        let surface = create_android_surface(self.instance.as_ref(), &self._window)?;
        surface.configure(device, &self.config);
        self.surface = surface;
        Ok(())
    }
}

#[cfg(target_os = "android")]
struct AndroidNativeWindow {
    ptr: NonNull<ANativeWindow>,
}

#[cfg(target_os = "android")]
impl AndroidNativeWindow {
    unsafe fn from_raw(ptr: *mut ANativeWindow) -> Option<Self> {
        NonNull::new(ptr).map(|ptr| Self { ptr })
    }

    fn as_ptr(&self) -> *mut ANativeWindow {
        self.ptr.as_ptr()
    }
}

#[cfg(target_os = "android")]
unsafe impl Send for AndroidNativeWindow {}

#[cfg(target_os = "android")]
unsafe impl Sync for AndroidNativeWindow {}

#[cfg(target_os = "android")]
impl Drop for AndroidNativeWindow {
    fn drop(&mut self) {
        unsafe {
            ANativeWindow_release(self.ptr.as_ptr());
        }
    }
}

#[cfg(target_os = "android")]
fn create_android_surface(
    instance: &wgpu::Instance,
    window: &AndroidNativeWindow,
) -> Result<wgpu::Surface<'static>, String> {
    let raw_window_handle = RawWindowHandle::AndroidNdk(AndroidNdkWindowHandle::new(
        NonNull::new(window.as_ptr() as *mut c_void)
            .ok_or_else(|| "present surface invalid window pointer".to_string())?,
    ));
    let raw_display_handle = RawDisplayHandle::Android(AndroidDisplayHandle::new());

    unsafe {
        instance
            .create_surface_unsafe(SurfaceTargetUnsafe::RawHandle {
                raw_display_handle,
                raw_window_handle,
            })
            .map_err(|err| format!("wgpu: create_surface failed: {err:?}"))
    }
}

pub(crate) fn signal_frame_ready(queue: &wgpu::Queue, frame_ready: Arc<AtomicBool>) {
    frame_ready.store(false, Ordering::Release);
    let _ = queue.submit(std::iter::empty::<wgpu::CommandBuffer>());
    let frame_ready_done = Arc::clone(&frame_ready);
    queue.on_submitted_work_done(move || {
        frame_ready_done.store(true, Ordering::Release);
    });
}

#[cfg(target_os = "android")]
pub(crate) fn attach_present_surface(
    instance: &wgpu::Instance,
    adapter: &wgpu::Adapter,
    device: &wgpu::Device,
    native_window_ptr: *mut c_void,
    width: u32,
    height: u32,
) -> Result<PresentTarget, String> {
    if native_window_ptr.is_null() || width == 0 || height == 0 {
        return Err("present surface requires valid window and size".to_string());
    }

    let window = unsafe {
        AndroidNativeWindow::from_raw(native_window_ptr as *mut ANativeWindow)
            .ok_or_else(|| "present surface invalid ANativeWindow".to_string())?
    };

    let surface = create_android_surface(instance, &window)?;

    let caps = surface.get_capabilities(adapter);
    let format = if caps
        .formats
        .iter()
        .any(|fmt| *fmt == wgpu::TextureFormat::Bgra8Unorm)
    {
        wgpu::TextureFormat::Bgra8Unorm
    } else if caps
        .formats
        .iter()
        .any(|fmt| *fmt == wgpu::TextureFormat::Rgba8Unorm)
    {
        wgpu::TextureFormat::Rgba8Unorm
    } else {
        *caps
            .formats
            .first()
            .ok_or_else(|| "wgpu: surface has no supported formats".to_string())?
    };

    let alpha_mode = caps
        .alpha_modes
        .first()
        .copied()
        .unwrap_or(wgpu::CompositeAlphaMode::Opaque);

    let config = wgpu::SurfaceConfiguration {
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
        format,
        width,
        height,
        present_mode: wgpu::PresentMode::Fifo,
        alpha_mode,
        desired_maximum_frame_latency: 2,
        view_formats: vec![],
    };

    surface.configure(device, &config);

    Ok(PresentTarget::Surface(PresentSurfaceTarget {
        instance: Arc::new(instance.clone()),
        surface,
        config,
        _window: window,
    }))
}

pub(crate) fn attach_present_texture(
    device: &wgpu::Device,
    mtl_texture_ptr: usize,
    width: u32,
    height: u32,
    bytes_per_row: u32,
) -> Option<PresentTarget> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        if width == 0 || height == 0 {
            return None;
        }
        let raw_ptr = mtl_texture_ptr as *mut metal::MTLTexture;
        if raw_ptr.is_null() {
            return None;
        }

        let raw_texture = unsafe { metal::Texture::from_ptr(raw_ptr) };
        let hal_texture = unsafe {
            wgpu_hal::metal::Device::texture_from_raw(
                raw_texture,
                wgpu::TextureFormat::Bgra8Unorm,
                MTLTextureType::D2,
                1,
                1,
                CopyExtent {
                    width,
                    height,
                    depth: 1,
                },
            )
        };

        let desc = wgpu::TextureDescriptor {
            label: Some("next2 present texture (external MTLTexture)"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Bgra8Unorm,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT
                | wgpu::TextureUsages::TEXTURE_BINDING
                | wgpu::TextureUsages::COPY_SRC
                | wgpu::TextureUsages::COPY_DST,
            view_formats: BGRA8_UNORM_VIEW_FORMATS,
        };

        let texture = unsafe { device.create_texture_from_hal::<Metal>(hal_texture, &desc) };
        return Some(PresentTarget::Texture(PresentTextureTarget {
            render_texture: texture,
            width,
            height,
            _bytes_per_row: bytes_per_row,
        }));
    }
    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        let _ = (device, mtl_texture_ptr, width, height, bytes_per_row);
        None
    }
}
