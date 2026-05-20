#![allow(non_snake_case)]

#[cfg(target_os = "android")]
use crate::next2_engine::engine::attach_present_surface;
#[cfg(target_os = "android")]
use crate::next2_engine::engine::readback_frame_bgra;
#[cfg(target_os = "android")]
use jni_sys::{
    jboolean, jclass, jint, jlong, jobject, jsize, jstring, JNIEnv, JNI_FALSE, JNI_TRUE,
};
#[cfg(target_os = "android")]
use ndk_sys::ANativeWindow;
#[cfg(target_os = "android")]
use std::ffi::c_void;

#[cfg(target_os = "android")]
#[link(name = "android")]
extern "C" {
    fn ANativeWindow_fromSurface(env: *mut JNIEnv, surface: jobject) -> *mut ANativeWindow;
    fn ANativeWindow_release(window: *mut ANativeWindow);
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1nipaplay_RustLibNipaplayPlugin_nativeNext2AttachSurface(
    env: *mut JNIEnv,
    _class: jclass,
    handle: jlong,
    surface: jobject,
    width: jint,
    height: jint,
) -> jboolean {
    if handle == 0 || surface.is_null() || width <= 0 || height <= 0 {
        return JNI_FALSE;
    }

    let native_window = unsafe { ANativeWindow_fromSurface(env, surface) };
    if native_window.is_null() {
        return JNI_FALSE;
    }

    let attached = attach_present_surface(
        handle as u64,
        native_window as *mut c_void,
        width as u32,
        height as u32,
    );
    unsafe { ANativeWindow_release(native_window) };
    if attached {
        JNI_TRUE
    } else {
        JNI_FALSE
    }
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1nipaplay_RustLibNipaplayPlugin_nativeNext2EngineCreate(
    _env: *mut JNIEnv,
    _class: jclass,
    width: jint,
    height: jint,
) -> jlong {
    crate::next2_engine::ffi::next2_engine_create(width.max(1) as u32, height.max(1) as u32)
        as jlong
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1nipaplay_RustLibNipaplayPlugin_nativeNext2EngineResize(
    _env: *mut JNIEnv,
    _class: jclass,
    handle: jlong,
    width: jint,
    height: jint,
) -> jint {
    crate::next2_engine::ffi::next2_engine_resize(handle as u64, width.max(1) as u32, height.max(1) as u32)
        as jint
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1nipaplay_RustLibNipaplayPlugin_nativeNext2EngineDispose(
    _env: *mut JNIEnv,
    _class: jclass,
    handle: jlong,
) {
    crate::next2_engine::ffi::next2_engine_dispose(handle as u64);
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1nipaplay_RustLibNipaplayPlugin_nativeNext2EnginePollFrameReady(
    _env: *mut JNIEnv,
    _class: jclass,
    handle: jlong,
) -> jboolean {
    if crate::next2_engine::ffi::next2_engine_poll_frame_ready(handle as u64) {
        JNI_TRUE
    } else {
        JNI_FALSE
    }
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1nipaplay_RustLibNipaplayPlugin_nativeNext2EngineSetFrame(
    env: *mut JNIEnv,
    _class: jclass,
    handle: jlong,
    frame_json: jstring,
    font_size: f32,
    outline_width: f32,
    shadow_style: jint,
    opacity: f32,
) -> jint {
    if env.is_null() || frame_json.is_null() {
        return 0;
    }
    unsafe {
        let get_string_utf_chars = (**env).v1_1.GetStringUTFChars;
        let release_string_utf_chars = (**env).v1_1.ReleaseStringUTFChars;
        let c_str_ptr = get_string_utf_chars(env, frame_json, std::ptr::null_mut());
        if c_str_ptr.is_null() {
            return 0;
        }
        let ok = crate::next2_engine::ffi::next2_engine_set_frame(
            handle as u64,
            c_str_ptr,
            font_size,
            outline_width,
            shadow_style as u8,
            opacity,
        ) as jint;
        release_string_utf_chars(env, frame_json, c_str_ptr);
        ok
    }
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1nipaplay_RustLibNipaplayPlugin_nativeNext2EngineResetScene(
    _env: *mut JNIEnv,
    _class: jclass,
    handle: jlong,
) -> jint {
    crate::next2_engine::ffi::next2_engine_reset_scene(handle as u64) as jint
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1nipaplay_RustLibNipaplayPlugin_nativeNext2EngineCopyBgraFrame(
    env: *mut JNIEnv,
    _class: jclass,
    handle: jlong,
    out_buffer: jobject,
    out_len: jint,
) -> jlong {
    if env.is_null() || out_buffer.is_null() || out_len <= 0 {
        return 0;
    }

    let Some(frame) = readback_frame_bgra(handle as u64) else {
        return 0;
    };

    let required_len = frame
        .width
        .checked_mul(frame.height)
        .and_then(|v| v.checked_mul(4u32))
        .unwrap_or(0u32) as usize;
    if required_len == 0 || required_len != out_len as usize || frame.pixels.len() < required_len
    {
        return 0;
    }

    unsafe {
        let get_direct_buffer_address = (**env).v1_4.GetDirectBufferAddress;
        let get_direct_buffer_capacity = (**env).v1_4.GetDirectBufferCapacity;

        let dst = get_direct_buffer_address(env, out_buffer) as *mut u8;
        let capacity = get_direct_buffer_capacity(env, out_buffer) as jsize;
        if dst.is_null() || capacity < required_len as jsize {
            return 0;
        }

        std::ptr::copy_nonoverlapping(frame.pixels.as_ptr(), dst, required_len);
    }

    ((frame.width as jlong) << 32) | (frame.height as jlong & 0xFFFF_FFFF)
}
