use std::ffi::{c_char, c_void, CStr};
use std::sync::atomic::Ordering;
use std::sync::mpsc;

use super::engine::{
    create_engine, lookup_engine, readback_frame_bgra, remove_engine, EngineCommand, RenderFrameInput,
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
    create_engine(width, height).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn next2_engine_get_mtl_device(handle: u64) -> *mut c_void {
    lookup_engine(handle)
        .map(|entry| entry.mtl_device_ptr as *mut c_void)
        .unwrap_or(std::ptr::null_mut())
}

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
        mtl_texture_ptr: mtl_texture_ptr as usize,
        width,
        height,
        bytes_per_row,
    });
}

#[no_mangle]
pub extern "C" fn next2_engine_dispose(handle: u64) {
    let Some(entry) = remove_engine(handle) else {
        return;
    };
    let _ = entry.cmd_tx.send(EngineCommand::Stop);
}

#[no_mangle]
pub extern "C" fn next2_engine_poll_frame_ready(handle: u64) -> bool {
    let Some(entry) = lookup_engine(handle) else {
        return false;
    };
    entry.frame_ready.swap(false, Ordering::AcqRel)
}

#[no_mangle]
pub extern "C" fn next2_engine_resize(handle: u64, width: u32, height: u32) -> u8 {
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };
    let _ = entry.cmd_tx.send(EngineCommand::Resize { width, height });
    1
}

#[no_mangle]
pub extern "C" fn next2_engine_reset_scene(handle: u64) -> u8 {
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };
    let _ = entry.cmd_tx.send(EngineCommand::ResetScene);
    1
}

#[no_mangle]
pub extern "C" fn next2_engine_set_frame(
    handle: u64,
    frame_json: *const c_char,
    font_size: f32,
    outline_width: f32,
    shadow_style: u8,
    opacity: f32,
) -> u8 {
    let Some(entry) = lookup_engine(handle) else {
        return 0;
    };
    let Some(json) = parse_c_string(frame_json) else {
        return 0;
    };

    let (reply_tx, reply_rx) = mpsc::channel();
    if entry
        .cmd_tx
        .send(EngineCommand::SetFrame {
            input: RenderFrameInput {
                frame_json: json,
                font_size,
                outline_width,
                shadow_style,
                opacity,
            },
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

#[no_mangle]
pub extern "C" fn next2_engine_copy_bgra_frame(
    handle: u64,
    out_pixels: *mut u8,
    out_len: u32,
    out_width: *mut u32,
    out_height: *mut u32,
) -> u8 {
    if out_pixels.is_null() || out_width.is_null() || out_height.is_null() || out_len == 0 {
        return 0;
    }

    let Some(frame) = readback_frame_bgra(handle) else {
        return 0;
    };

    let required_len = frame
        .width
        .checked_mul(frame.height)
        .and_then(|v| v.checked_mul(4))
        .unwrap_or(0) as usize;
    if required_len == 0 || frame.pixels.len() < required_len {
        return 0;
    }

    if out_len as usize != required_len {
        return 0;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(frame.pixels.as_ptr(), out_pixels, required_len);
        *out_width = frame.width;
        *out_height = frame.height;
    }
    1
}
