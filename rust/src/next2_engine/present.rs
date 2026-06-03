use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

#[cfg(any(target_os = "macos", target_os = "ios"))]
use metal::foreign_types::ForeignType;
#[cfg(any(target_os = "macos", target_os = "ios"))]
use metal::MTLTextureType;
#[cfg(any(target_os = "macos", target_os = "ios"))]
use wgpu_hal::{api::Metal, CopyExtent};

#[cfg(target_os = "linux")]
use std::num::NonZeroU32;
#[cfg(target_os = "linux")]
use wgpu_hal::api::Gles;

#[cfg(target_os = "windows")]
use wgpu_hal::api::Dx12;
#[cfg(target_os = "windows")]
use windows::{
    core::PCWSTR,
    Win32::{
        Foundation::GENERIC_ALL,
        Graphics::{
            Direct3D12::{
                ID3D12Resource, D3D12_CLEAR_VALUE, D3D12_CLEAR_VALUE_0,
                D3D12_CPU_PAGE_PROPERTY_UNKNOWN, D3D12_HEAP_FLAG_SHARED, D3D12_HEAP_PROPERTIES,
                D3D12_HEAP_TYPE_DEFAULT, D3D12_MEMORY_POOL_UNKNOWN, D3D12_RESOURCE_DESC,
                D3D12_RESOURCE_DIMENSION_TEXTURE2D, D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET,
                D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS, D3D12_RESOURCE_STATE_COMMON,
                D3D12_TEXTURE_LAYOUT_UNKNOWN,
            },
            Dxgi::Common::{DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_SAMPLE_DESC},
        },
    },
};

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
    pub(crate) format: wgpu::TextureFormat,
    _bytes_per_row: u32,
}

impl PresentTextureTarget {
    pub(crate) fn render_texture(&self) -> &wgpu::Texture {
        &self.render_texture
    }

    pub(crate) fn format(&self) -> wgpu::TextureFormat {
        self.format
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
            format: wgpu::TextureFormat::Bgra8Unorm,
            _bytes_per_row: bytes_per_row,
        }));
    }
    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        let _ = (device, mtl_texture_ptr, width, height, bytes_per_row);
        None
    }
}

#[cfg(target_os = "windows")]
pub(crate) fn create_dx12_shared_present_texture(
    device: &wgpu::Device,
    width: u32,
    height: u32,
) -> Option<(PresentTarget, usize)> {
    if width == 0 || height == 0 {
        return None;
    }

    let raw_device = unsafe {
        device
            .as_hal::<Dx12>()
            .map(|hal_device| hal_device.raw_device().clone())
    }?;

    let heap_properties = D3D12_HEAP_PROPERTIES {
        Type: D3D12_HEAP_TYPE_DEFAULT,
        CPUPageProperty: D3D12_CPU_PAGE_PROPERTY_UNKNOWN,
        MemoryPoolPreference: D3D12_MEMORY_POOL_UNKNOWN,
        CreationNodeMask: 1,
        VisibleNodeMask: 1,
    };
    let resource_desc = D3D12_RESOURCE_DESC {
        Dimension: D3D12_RESOURCE_DIMENSION_TEXTURE2D,
        Alignment: 0,
        Width: width as u64,
        Height: height,
        DepthOrArraySize: 1,
        MipLevels: 1,
        Format: DXGI_FORMAT_B8G8R8A8_UNORM,
        SampleDesc: DXGI_SAMPLE_DESC {
            Count: 1,
            Quality: 0,
        },
        Layout: D3D12_TEXTURE_LAYOUT_UNKNOWN,
        Flags: D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET
            | D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS,
    };
    let clear_value = D3D12_CLEAR_VALUE {
        Format: DXGI_FORMAT_B8G8R8A8_UNORM,
        Anonymous: D3D12_CLEAR_VALUE_0 {
            Color: [0.0, 0.0, 0.0, 0.0],
        },
    };

    let mut resource: Option<ID3D12Resource> = None;
    unsafe {
        raw_device
            .CreateCommittedResource(
                &heap_properties,
                D3D12_HEAP_FLAG_SHARED,
                &resource_desc,
                D3D12_RESOURCE_STATE_COMMON,
                Some(&clear_value as *const _),
                &mut resource,
            )
            .ok()?;
    }
    let resource = resource?;
    let shared_handle = unsafe {
        raw_device
            .CreateSharedHandle(&resource, None, GENERIC_ALL.0, PCWSTR::null())
            .ok()?
    };
    if shared_handle.is_invalid() {
        return None;
    }

    let size = wgpu::Extent3d {
        width,
        height,
        depth_or_array_layers: 1,
    };
    let hal_texture = unsafe {
        wgpu_hal::dx12::Device::texture_from_raw(
            resource,
            wgpu::TextureFormat::Bgra8Unorm,
            wgpu::TextureDimension::D2,
            size,
            1,
            1,
        )
    };
    let desc = wgpu::TextureDescriptor {
        label: Some("next2 present texture (DXGI shared D3D12 resource)"),
        size,
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
    let texture = unsafe { device.create_texture_from_hal::<Dx12>(hal_texture, &desc) };
    Some((
        PresentTarget::Texture(PresentTextureTarget {
            render_texture: texture,
            width,
            height,
            format: wgpu::TextureFormat::Bgra8Unorm,
            _bytes_per_row: 0,
        }),
        shared_handle.0 as usize,
    ))
}

#[cfg(target_os = "linux")]
pub(crate) fn attach_present_gl_texture(
    device: &wgpu::Device,
    texture_name: u32,
    width: u32,
    height: u32,
) -> Option<PresentTarget> {
    let name = NonZeroU32::new(texture_name)?;
    if width == 0 || height == 0 {
        return None;
    }

    let format = wgpu::TextureFormat::Rgba8Unorm;
    let hal_desc = wgpu_hal::TextureDescriptor {
        label: Some("next2 present texture (external GL texture)"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage: wgpu::TextureUses::COLOR_TARGET | wgpu::TextureUses::RESOURCE,
        memory_flags: wgpu_hal::MemoryFlags::empty(),
        view_formats: vec![],
    };

    let hal_texture = unsafe {
        device
            .as_hal::<Gles>()
            .map(|hal_device| hal_device.texture_from_raw(name, &hal_desc, Some(Box::new(|| {}))))
    }?;

    let desc = wgpu::TextureDescriptor {
        label: Some("next2 present texture (external GL texture)"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
        view_formats: &[],
    };

    let texture = unsafe { device.create_texture_from_hal::<Gles>(hal_texture, &desc) };
    Some(PresentTarget::Texture(PresentTextureTarget {
        render_texture: texture,
        width,
        height,
        format,
        _bytes_per_row: 0,
    }))
}
