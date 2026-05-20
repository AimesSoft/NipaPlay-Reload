use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

#[cfg(any(target_os = "macos", target_os = "ios"))]
use metal::foreign_types::ForeignType;
#[cfg(any(target_os = "macos", target_os = "ios"))]
use metal::MTLTextureType;
#[cfg(any(target_os = "macos", target_os = "ios"))]
use wgpu_hal::{api::Metal, CopyExtent};

const BGRA8_UNORM_VIEW_FORMATS: &[wgpu::TextureFormat] = &[wgpu::TextureFormat::Bgra8UnormSrgb];

pub(crate) enum PresentTarget {
    Texture(PresentTextureTarget),
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

pub(crate) fn signal_frame_ready(queue: &wgpu::Queue, frame_ready: Arc<AtomicBool>) {
    frame_ready.store(false, Ordering::Release);
    let _ = queue.submit(std::iter::empty::<wgpu::CommandBuffer>());
    let frame_ready_done = Arc::clone(&frame_ready);
    queue.on_submitted_work_done(move || {
        frame_ready_done.store(true, Ordering::Release);
    });
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
