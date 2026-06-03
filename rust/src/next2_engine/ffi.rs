use std::ffi::{c_char, c_void, CStr};
#[cfg(not(target_os = "linux"))]
use std::sync::mpsc;

#[cfg(target_os = "windows")]
use super::engine::create_windows_dxgi_shared_texture;
#[cfg(not(target_os = "linux"))]
use super::engine::{
    create_engine, lookup_engine, n2log, remove_engine, EngineCommand, RenderFrameInput,
};
#[cfg(target_os = "linux")]
use super::engine::{
    create_linux_gl_engine, n2log, poll_linux_gl_frame_ready, remove_linux_gl_engine,
    render_linux_gl_texture, reset_linux_gl_engine, resize_linux_gl_engine, set_linux_gl_frame,
    GlProcLoader, RenderFrameInput,
};

fn parse_c_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let c_str = unsafe { CStr::from_ptr(ptr) };
    c_str.to_str().ok().map(ToOwned::to_owned)
}

#[no_mangle]
pub extern "C" fn next2_engine_create(width: u32, height: u32) -> u64 {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        #[cfg(target_os = "linux")]
        {
            create_linux_gl_engine(width, height).unwrap_or(0)
        }
        #[cfg(not(target_os = "linux"))]
        {
            create_engine(width, height).unwrap_or(0)
        }
    }));
    match result {
        Ok(handle) => handle,
        Err(e) => {
            let msg = e
                .downcast_ref::<String>()
                .map(|s| s.as_str())
                .or_else(|| e.downcast_ref::<&str>().copied())
                .unwrap_or("unknown");
            n2log(&format!("FFI create_engine PANIC: {msg}"));
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn next2_engine_get_mtl_device(handle: u64) -> *mut c_void {
    #[cfg(target_os = "linux")]
    {
        let _ = handle;
        std::ptr::null_mut()
    }
    #[cfg(not(target_os = "linux"))]
    {
        lookup_engine(handle)
            .map(|entry| entry.mtl_device_ptr as *mut c_void)
            .unwrap_or(std::ptr::null_mut())
    }
}

#[no_mangle]
pub extern "C" fn next2_engine_poll_frame_ready(handle: u64) -> bool {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        #[cfg(target_os = "linux")]
        {
            poll_linux_gl_frame_ready(handle)
        }
        #[cfg(not(target_os = "linux"))]
        {
            super::engine::poll_frame_ready(handle)
        }
    }));
    match result {
        Ok(ready) => ready,
        Err(e) => {
            let msg = e
                .downcast_ref::<String>()
                .map(|s| s.as_str())
                .or_else(|| e.downcast_ref::<&str>().copied())
                .unwrap_or("unknown");
            n2log(&format!("FFI poll_frame_ready PANIC: {msg}"));
            false
        }
    }
}

#[cfg(not(target_os = "linux"))]
#[no_mangle]
pub extern "C" fn next2_engine_attach_present_texture(
    handle: u64,
    mtl_texture_ptr: *mut c_void,
    width: u32,
    height: u32,
    bytes_per_row: u32,
) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::AttachPresentTexture {
        raw_target_ptr: mtl_texture_ptr as usize,
        width,
        height,
        bytes_per_row,
        reply: None,
    });
}

#[cfg(target_os = "linux")]
#[no_mangle]
pub extern "C" fn next2_engine_attach_present_texture(
    _handle: u64,
    _mtl_texture_ptr: *mut c_void,
    _width: u32,
    _height: u32,
    _bytes_per_row: u32,
) {
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "C" fn next2_engine_attach_present_surface(
    handle: u64,
    native_window_ptr: *mut c_void,
    width: u32,
    height: u32,
) {
    let Some(entry) = lookup_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::AttachPresentTexture {
        raw_target_ptr: native_window_ptr as usize,
        width,
        height,
        bytes_per_row: 0,
        reply: None,
    });
}

#[cfg(not(target_os = "android"))]
#[no_mangle]
pub extern "C" fn next2_engine_attach_present_surface(
    _handle: u64,
    _native_window_ptr: *mut c_void,
    _width: u32,
    _height: u32,
) {
}

#[cfg(target_os = "windows")]
#[no_mangle]
pub extern "C" fn next2_engine_create_dxgi_shared_texture(
    handle: u64,
    width: u32,
    height: u32,
    out_shared_handle: *mut usize,
    out_width: *mut u32,
    out_height: *mut u32,
) -> u8 {
    if out_shared_handle.is_null() || out_width.is_null() || out_height.is_null() {
        return 0;
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        create_windows_dxgi_shared_texture(handle, width, height)
    }));

    match result {
        Ok(Some(info)) => {
            unsafe {
                *out_shared_handle = info.shared_handle;
                *out_width = info.width;
                *out_height = info.height;
            }
            1
        }
        Ok(None) => 0,
        Err(e) => {
            let msg = e
                .downcast_ref::<String>()
                .map(|s| s.as_str())
                .or_else(|| e.downcast_ref::<&str>().copied())
                .unwrap_or("unknown");
            n2log(&format!("FFI create_dxgi_shared_texture PANIC: {msg}"));
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn next2_engine_dispose(handle: u64) {
    #[cfg(target_os = "linux")]
    {
        let _ = remove_linux_gl_engine(handle);
    }
    #[cfg(not(target_os = "linux"))]
    {
        let Some(entry) = remove_engine(handle) else {
            return;
        };
        let _ = entry.cmd_tx.send(EngineCommand::Stop);
    }
}

#[no_mangle]
pub extern "C" fn next2_engine_resize(handle: u64, width: u32, height: u32) -> u8 {
    #[cfg(target_os = "linux")]
    {
        return if resize_linux_gl_engine(handle, width, height) {
            1
        } else {
            0
        };
    }
    #[cfg(not(target_os = "linux"))]
    {
        let Some(entry) = lookup_engine(handle) else {
            return 0;
        };
        let _ = entry.cmd_tx.send(EngineCommand::Resize { width, height });
        1
    }
}

#[no_mangle]
pub extern "C" fn next2_engine_reset_scene(handle: u64) -> u8 {
    #[cfg(target_os = "linux")]
    {
        return if reset_linux_gl_engine(handle) { 1 } else { 0 };
    }
    #[cfg(not(target_os = "linux"))]
    {
        let Some(entry) = lookup_engine(handle) else {
            return 0;
        };
        let _ = entry.cmd_tx.send(EngineCommand::ResetScene);
        1
    }
}

#[no_mangle]
pub extern "C" fn next2_engine_set_frame(
    handle: u64,
    frame_json: *const c_char,
    font_size: f32,
    outline_width: f32,
    shadow_style: u8,
    opacity: f32,
    custom_font_family: *const c_char,
    custom_font_file_path: *const c_char,
) -> u8 {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let Some(json) = parse_c_string(frame_json) else {
            return 0;
        };

        let custom_font_family = parse_c_string(custom_font_family).unwrap_or_default();
        let custom_font_file_path = parse_c_string(custom_font_file_path).unwrap_or_default();
        let input = RenderFrameInput {
            frame_json: json,
            font_size,
            outline_width,
            shadow_style,
            opacity,
            custom_font_family,
            custom_font_file_path,
        };

        #[cfg(target_os = "linux")]
        {
            return if set_linux_gl_frame(handle, input) {
                1
            } else {
                0
            };
        }
        #[cfg(not(target_os = "linux"))]
        {
            let Some(entry) = lookup_engine(handle) else {
                return 0;
            };
            let (reply_tx, reply_rx) = mpsc::channel();
            if entry
                .cmd_tx
                .send(EngineCommand::SetFrame {
                    input,
                    reply: reply_tx,
                })
                .is_err()
            {
                return 0;
            }
            match reply_rx.recv() {
                Ok(true) => 1,
                _ => 0,
            }
        }
    }));
    match result {
        Ok(v) => v,
        Err(e) => {
            let msg = e
                .downcast_ref::<String>()
                .map(|s| s.as_str())
                .or_else(|| e.downcast_ref::<&str>().copied())
                .unwrap_or("unknown");
            n2log(&format!("FFI set_frame PANIC: {msg}"));
            0
        }
    }
}

#[cfg(target_os = "linux")]
#[no_mangle]
pub extern "C" fn next2_engine_render_gl_texture(
    handle: u64,
    texture_name: u32,
    width: u32,
    height: u32,
    loader: Option<GlProcLoader>,
) -> u8 {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let Some(loader) = loader else {
            return 0;
        };
        if render_linux_gl_texture(handle, texture_name, width, height, loader) {
            1
        } else {
            0
        }
    }));
    match result {
        Ok(v) => v,
        Err(e) => {
            let msg = e
                .downcast_ref::<String>()
                .map(|s| s.as_str())
                .or_else(|| e.downcast_ref::<&str>().copied())
                .unwrap_or("unknown");
            n2log(&format!("FFI render_gl_texture PANIC: {msg}"));
            0
        }
    }
}

#[cfg(not(target_os = "linux"))]
#[no_mangle]
pub extern "C" fn next2_engine_render_gl_texture(
    _handle: u64,
    _texture_name: u32,
    _width: u32,
    _height: u32,
    _loader: *const c_void,
) -> u8 {
    0
}
