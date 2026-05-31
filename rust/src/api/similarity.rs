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
        use_pinyin: c_int,   // int 代替 bool，FFI 跨语言安全
        cross_mode: c_int,   // int 代替 bool，FFI 跨语言安全
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

    /// 引擎指针是否有效（非 null）
    fn is_valid(&self) -> bool {
        !self.ptr.is_null()
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
    if !engine.is_valid() {
        return SimilarityResult { pairs: vec![], groups: vec![] };
    }

    // 分配 UTF-16 字符串缓冲区
    let mut str_buf = vec![0u16; MAX_STRING_LEN + 4];

    // 初始化引擎
    unsafe {
        sim_engine_begin_chunk(
            engine.ptr,
            str_buf.as_mut_ptr(),
            config.max_dist,
            config.max_cosine,
            config.use_pinyin as c_int,
            config.cross_mode as c_int,
        );
    }

    let mut pairs = Vec::new();
    let mut group_map: std::collections::HashMap<i32, i32> =
        std::collections::HashMap::new();
    let mut groups: Vec<Vec<i32>> = Vec::new();
    let time_window = config.time_window;

    // ===== 诊断：脱同步追踪 =====
    // c_nearby_count 追踪 C++ nearby_danmu_ 的实际大小
    // 规则：ret==0 时 C++ 会 push → +1；ret!=0 时 C++ 不 push → 不变
    // Rust 侧 engine_to_orig 也会在 ret==0 时 push，但对齐
    // 只有 Rust 拒绝匹配时 engine_to_orig push 而 C++ 不 push，产生脱同步
    let mut c_nearby_count: u32 = 0;
    let mut rejection_count: u32 = 0;

    eprintln!("[SIM-DEBUG] === 开始批量查重 === items={}, time_window={}, max_dist={}, max_cosine={}, cross_mode={}",
        items.len(), time_window, config.max_dist, config.max_cosine, config.cross_mode);

    // ===== 索引映射 =====
    // C++ 引擎在匹配成功时不将弹幕加入 nearby_danmu_（只保留组代表），
    // 因此引擎内部索引与原始数组索引会产生偏差。
    // 必须维护双向映射才能正确传递 index_l 和解析 target_index。

    /// 引擎内部索引 → 原始数组索引（仅被加入 nearby_danmu_ 的项才有映射）
    let mut engine_to_orig: Vec<i32> = Vec::new();

    /// 原始数组索引 → 该项的组代表在引擎中的内部索引
    /// （未匹配项的代表就是自身；匹配项的代表是它匹配到的那条）
    let mut orig_to_rep_engine_idx: Vec<u32> = Vec::with_capacity(items.len());

    // 逐条弹幕送入引擎
    for (i, item) in items.iter().enumerate() {
        // UTF-8 → UTF-16 转换
        let utf16: Vec<u16> = item.text.encode_utf16().collect();
        let copy_len = utf16.len().min(MAX_STRING_LEN - 1);
        str_buf[..copy_len].copy_from_slice(&utf16[..copy_len]);
        str_buf[copy_len] = 0; // null terminator

        // 计算 index_l（时间窗口裁剪）
        // 关键修正：index_l 必须是引擎内部索引空间中的值，而非原始数组索引。
        // 默认值 = 当前引擎内部数组长度，表示"不搜索任何已有条目"（全在窗口外）。
        let mut index_l: u32 = engine_to_orig.len() as u32;
        if time_window > 0.0 && !orig_to_rep_engine_idx.is_empty() {
            // 从最近的弹幕向前扫描，找到时间窗口内的所有原始索引，
            // 取其组代表的引擎内部索引的最小值作为 index_l。
            for (j, prev) in items[..i].iter().enumerate().rev() {
                if item.time_seconds - prev.time_seconds <= time_window {
                    if j < orig_to_rep_engine_idx.len() {
                        let ej = orig_to_rep_engine_idx[j];
                        if ej < index_l {
                            index_l = ej;
                        }
                    }
                } else {
                    break;
                }
            }
        }

        // 诊断：index_l 与 C++ nearby_danmu_.size() 的关系
        let desync = engine_to_orig.len() as u32 - c_nearby_count;
        if desync > 0 {
            eprintln!("[SIM-DEBUG] i={} time={:.2} text='{}' DESYNC={} engine_to_orig.len()={} c_nearby_count={} index_l={}",
                i, item.time_seconds, &item.text[..item.text.len().min(20)], desync,
                engine_to_orig.len(), c_nearby_count, index_l);
        }

        // 调用 C++ 查重
        let ret = unsafe {
            sim_engine_check_similar(engine.ptr, item.mode as u32, index_l)
        };

        if ret != 0 {
            let reason_code = ret >> 30;
            let dist = ((ret >> 19) & ((1 << 11) - 1)) as i32;
            let idx_diff = (ret & ((1 << 19) - 1)) as i32;

            // C++ 引擎返回的 idx_diff = p.idx - q.idx（引擎内部索引差）
            // p.idx = 当前 nearby_danmu_.size()（本条若不匹配将被插入的位置）
            // q.idx = 匹配到的条目在 nearby_danmu_ 中的索引
            // 因此匹配到的条目的引擎内部索引 = engine_to_orig.len() - idx_diff
            let current_engine_size = engine_to_orig.len() as u32;
            let matched_engine_idx = current_engine_idx_saturating_sub(current_engine_size, idx_diff as u32);

            // 通过反向映射还原原始数组索引
            let target_index = if (matched_engine_idx as usize) < engine_to_orig.len() {
                engine_to_orig[matched_engine_idx as usize]
            } else {
                // 映射失败时的安全回退（不应发生）
                (i as i32).saturating_sub(idx_diff)
            };

            // 诊断：记录 C++ 匹配原始信息
            eprintln!("[SIM-DEBUG] i={} C++_MATCH reason={} idx_diff={} c_nearby_count={} current_engine_size={} matched_engine_idx={} target_index={}",
                i, reason_code, idx_diff, c_nearby_count, current_engine_size, matched_engine_idx, target_index);

            // 时间窗口安全校验：引擎可能在 index_l 映射不完美时
            // 返回窗口外的匹配对，此处过滤掉
            if target_index < 0
                || (target_index as usize) >= items.len()
                || (time_window > 0.0
                    && item.time_seconds - items[target_index as usize].time_seconds > time_window)
            {
                // 诊断：记录拒绝信息
                rejection_count += 1;
                let time_delta = if target_index >= 0 && (target_index as usize) < items.len() {
                    item.time_seconds - items[target_index as usize].time_seconds
                } else {
                    -1.0
                };
                eprintln!("[SIM-DEBUG] i={} REJECTED! target_index={} time_delta={:.2} window={} rejection_count={} DESYNC_WILL_BE={}",
                    i, target_index, time_delta, time_window, rejection_count,
                    engine_to_orig.len() as u32 + 1 - c_nearby_count);
                // ^^^ 关键：这里 Rust 推了 engine_to_orig 但 C++ 没推 nearby_danmu_，
                // 所以 DESYNC 将在下一轮增加 1

                // 窗口外的匹配无效：将本条视为未匹配，加入引擎
                let new_engine_idx = engine_to_orig.len() as u32;
                engine_to_orig.push(i as i32);
                orig_to_rep_engine_idx.push(new_engine_idx);
                continue;
            }

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

            // 本条匹配成功，不加入 nearby_danmu_，
            // 记录其组代表在引擎中的内部索引
            orig_to_rep_engine_idx.push(matched_engine_idx);
        } else {
            // 本条未匹配，被加入 nearby_danmu_ 的末尾
            c_nearby_count += 1; // 诊断：C++ 会 push
            let new_engine_idx = engine_to_orig.len() as u32;
            engine_to_orig.push(i as i32);
            orig_to_rep_engine_idx.push(new_engine_idx);
        }
    }

    // 清理引擎（EngineGuard Drop 时自动 sim_engine_destroy）
    unsafe { sim_engine_reset(engine.ptr); }

    // 诊断：汇总
    eprintln!("[SIM-DEBUG] === 查重完成 === pairs={}, groups={}, rejections={}, final_desync={}",
        pairs.len(), groups.len(), rejection_count,
        engine_to_orig.len() as u32 - c_nearby_count);

    SimilarityResult { pairs, groups }
}

/// 安全的饱和减法，防止 idx_diff > current_engine_size 时下溢
fn current_engine_idx_saturating_sub(size: u32, diff: u32) -> u32 {
    size.saturating_sub(diff)
}

/// 单对相似度：输入两段文本，返回 0.0-1.0 分数
pub fn danmaku_pair_similarity(
    text_a: String,
    text_b: String,
    use_pinyin: bool,
) -> f64 {
    let engine = EngineGuard::new();
    if !engine.is_valid() {
        return 0.0;
    }
    let mut str_buf = vec![0u16; MAX_STRING_LEN + 4];

    unsafe {
        sim_engine_begin_chunk(
            engine.ptr,
            str_buf.as_mut_ptr(),
            999,    // 不设编辑距离上限
            0,      // 禁用余弦检测
            use_pinyin as c_int,
            1,      // 单对比较忽略 mode
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
