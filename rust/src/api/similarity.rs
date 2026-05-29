use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};

/// Opaque C++ 引擎实例
#[repr(C)]
struct SimilarityEngine {
    _opaque: [u8; 0],
}

extern "C" {
    fn sim_engine_create() -> *mut SimilarityEngine;
    fn sim_engine_destroy(engine: *mut SimilarityEngine);
    fn sim_engine_begin_chunk(
        engine: *mut SimilarityEngine,
        str_buf: *mut u16,
        max_dist: c_int,
        max_cosine: c_int,
        use_pinyin: bool,
        cross_mode: bool,
    );
    fn sim_engine_check_similar(
        engine: *mut SimilarityEngine,
        mode: u32,
        index_l: u32,
    ) -> u32;
    fn sim_engine_begin_index_lock(engine: *mut SimilarityEngine);
    fn sim_engine_reset(engine: *mut SimilarityEngine);
}

/// RAII 包装：确保 C++ 引擎实例在 Drop 时被销毁
struct EngineGuard {
    ptr: *mut SimilarityEngine,
}

impl EngineGuard {
    fn new() -> Self {
        Self {
            ptr: unsafe { sim_engine_create() }
        }
    }
}

impl Drop for EngineGuard {
    fn drop(&mut self) {
        if !self.ptr.is_null() {
            unsafe { sim_engine_destroy(self.ptr) }
        }
    }
}

// ===== 公共数据结构 =====

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DanmakuItem {
    pub text: String,
    pub mode: i32,          // 0=scroll, 1=top, 2=bottom
    pub time_seconds: f64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SimilarityConfig {
    pub max_dist: i32,      // 编辑距离阈值，默认 3
    pub max_cosine: i32,    // 余弦相似度阈值 0-100，默认 70
    pub use_pinyin: bool,   // 启用拼音对比，默认 true
    pub cross_mode: bool,   // 跨弹幕类型对比，默认 false
    pub time_window: f64,   // 时间窗口秒数，默认 45.0
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SimilarityPair {
    pub source_index: i32,
    pub target_index: i32,
    pub reason: String,     // identical / edit_distance / pinyin_distance / cosine
    pub distance: i32,
    pub score: f64,          // 归一化相似度 0.0-1.0
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SimilarityResult {
    pub pairs: Vec<SimilarityPair>,
    pub groups: Vec<Vec<i32>>,
}

/// UTF-16 字符串缓冲区大小，与 pakku.js 一致
const MAX_STRING_LEN: usize = 16005;

/// 批量查重：对 N 条弹幕做全对比较，返回相似对和分组
pub fn danmaku_similarity_check(
    items: Vec<DanmakuItem>,
    config: SimilarityConfig,
) -> SimilarityResult {
    // 创建独立的引擎实例——无需 Mutex
    let engine = EngineGuard::new();

    // 分配 UTF-16 字符串缓冲区
    let mut str_buf = vec![0u16; MAX_STRING_LEN + 4];

    // 初始化引擎
    unsafe {
        sim_engine_begin_chunk(
            engine.ptr,
            str_buf.as_mut_ptr(),
            config.max_dist,
            config.max_cosine,
            config.use_pinyin,
            config.cross_mode,
        );
    }

    let mut pairs = Vec::new();
    let mut group_map: std::collections::HashMap<i32, i32> =
        std::collections::HashMap::new();
    let mut groups: Vec<Vec<i32>> = Vec::new();
    let time_window = config.time_window;

    // 逐条弹幕送入引擎
    for (i, item) in items.iter().enumerate() {
        // UTF-8 → UTF-16 转换
        let utf16: Vec<u16> = item.text.encode_utf16().collect();
        let copy_len = utf16.len().min(MAX_STRING_LEN - 1);
        str_buf[..copy_len].copy_from_slice(&utf16[..copy_len]);
        str_buf[copy_len] = 0; // null terminator

        // 计算 index_l（时间窗口裁剪）
        let mut index_l = 0u32;
        if time_window > 0.0 {
            for (j, prev) in items[..i].iter().enumerate().rev() {
                if item.time_seconds - prev.time_seconds <= time_window {
                    index_l = j as u32;
                } else {
                    break;
                }
            }
        }

        // 调用 C++ 查重
        let ret = unsafe {
            sim_engine_check_similar(engine.ptr, item.mode as u32, index_l)
        };

        if ret != 0 {
            let reason_code = ret >> 30;
            let dist = ((ret >> 19) & ((1 << 11) - 1)) as i32;
            let idx_diff = (ret & ((1 << 19) - 1)) as i32;

            let target_index = (i as i32) - idx_diff;
            let reason_str = match reason_code {
                0 => "identical",
                1 => "edit_distance",
                2 => "pinyin_distance",
                3 => "cosine",
                _ => "unknown",
            };

            let score = compute_score(reason_code, dist, item.text.len());

            pairs.push(SimilarityPair {
                source_index: i as i32,
                target_index,
                reason: reason_str.to_string(),
                distance: dist,
                score,
            });

            update_groups(&mut group_map, &mut groups, i as i32, target_index);
        }
    }

    // 清理引擎（EngineGuard Drop 时自动 sim_engine_destroy）
    unsafe { sim_engine_reset(engine.ptr); }

    SimilarityResult { pairs, groups }
}

/// 单对相似度：输入两段文本，返回 0.0-1.0 分数
pub fn danmaku_pair_similarity(
    text_a: String,
    text_b: String,
    use_pinyin: bool,
) -> f64 {
    let engine = EngineGuard::new();
    let mut str_buf = vec![0u16; MAX_STRING_LEN + 4];

    unsafe {
        sim_engine_begin_chunk(
            engine.ptr,
            str_buf.as_mut_ptr(),
            999,    // 不设编辑距离上限
            0,      // 禁用余弦检测
            use_pinyin,
            true,   // 单对比较忽略 mode
        );
    }

    // 送入第一条
    let utf16_0: Vec<u16> = text_a.encode_utf16().collect();
    let copy_len = utf16_0.len().min(MAX_STRING_LEN - 1);
    str_buf[..copy_len].copy_from_slice(&utf16_0[..copy_len]);
    str_buf[copy_len] = 0;
    let _ = unsafe {
        sim_engine_check_similar(engine.ptr, 0, 0)
    };

    // 送入第二条并获取结果
    let utf16_1: Vec<u16> = text_b.encode_utf16().collect();
    let copy_len = utf16_1.len().min(MAX_STRING_LEN - 1);
    str_buf[..copy_len].copy_from_slice(&utf16_1[..copy_len]);
    str_buf[copy_len] = 0;
    let ret = unsafe {
        sim_engine_check_similar(engine.ptr, 0, 0)
    };

    if ret == 0 {
        return 0.0;
    }

    let reason_code = ret >> 30;
    let dist = ((ret >> 19) & ((1 << 11) - 1)) as i32;
    compute_score(reason_code, dist, text_b.len())
}

fn compute_score(reason_code: u32, dist: i32, text_len: usize) -> f64 {
    match reason_code {
        0 => 1.0,                                              // identical
        1 | 2 => {                                              // edit/pinyin distance
            if text_len == 0 { return 0.0; }
            1.0 - (dist as f64 / (text_len as f64 * 2.0).max(1.0))
        }
        3 => dist as f64 / 100.0,                              // cosine similarity
        _ => 0.0,
    }
}

fn update_groups(
    group_map: &mut std::collections::HashMap<i32, i32>,
    groups: &mut Vec<Vec<i32>>,
    a: i32,
    b: i32,
) {
    let root_a = group_map.get(&a).copied();
    let root_b = group_map.get(&b).copied();

    match (root_a, root_b) {
        (Some(ra), Some(rb)) if ra == rb => {}
        (Some(ra), Some(rb)) => {
            let mut merged = std::mem::take(&mut groups[ra as usize]);
            merged.extend(std::mem::take(&mut groups[rb as usize]));
            for &idx in &merged {
                group_map.insert(idx, ra);
            }
            groups[ra as usize] = merged;
        }
        (Some(ra), None) => {
            groups[ra as usize].push(b);
            group_map.insert(b, ra);
        }
        (None, Some(rb)) => {
            groups[rb as usize].push(a);
            group_map.insert(a, rb);
        }
        (None, None) => {
            let group_idx = groups.len() as i32;
            groups.push(vec![b, a]);
            group_map.insert(a, group_idx);
            group_map.insert(b, group_idx);
        }
    }
}

// ===== 同步 FFI 导出（供 Dart FFI 直接调用，绕过 FRB 异步管线） =====

/// 批量查重：输入弹幕 JSON + 配置 JSON，返回结果 JSON
/// 调用者负责用 `similarity_free_cstring` 释放返回的 C 字符串
#[no_mangle]
pub extern "C" fn similarity_check_batch(
    items_json: *const c_char,
    config_json: *const c_char,
) -> *mut c_char {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let items_str = unsafe { CStr::from_ptr(items_json) }.to_str().unwrap_or("[]");
        let config_str = unsafe { CStr::from_ptr(config_json) }.to_str().unwrap_or("{}");

        let items: Vec<DanmakuItem> = serde_json::from_str(items_str).unwrap_or_default();
        let config: SimilarityConfig = serde_json::from_str(config_str).unwrap_or(SimilarityConfig {
            max_dist: 3,
            max_cosine: 70,
            use_pinyin: true,
            cross_mode: false,
            time_window: 45.0,
        });

        let result = danmaku_similarity_check(items, config);
        let json = serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string());
        CString::new(json).unwrap_or_else(|_| CString::new("{}").unwrap()).into_raw()
    }));

    result.unwrap_or_else(|_| CString::new("{}").unwrap().into_raw())
}

/// 单对相似度：输入两段文本 + 拼音开关，返回浮点分数（打包为 C 字符串）
#[no_mangle]
pub extern "C" fn similarity_pair(
    text_a: *const c_char,
    text_b: *const c_char,
    use_pinyin: c_int,
) -> f64 {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let a = unsafe { CStr::from_ptr(text_a) }.to_str().unwrap_or("").to_string();
        let b = unsafe { CStr::from_ptr(text_b) }.to_str().unwrap_or("").to_string();
        danmaku_pair_similarity(a, b, use_pinyin != 0)
    }));

    result.unwrap_or(0.0)
}

/// 释放 `similarity_check_batch` 返回的 C 字符串
#[no_mangle]
pub extern "C" fn similarity_free_cstring(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)); }
    }
}
