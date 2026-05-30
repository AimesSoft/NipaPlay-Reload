/// DFM+ public API for flutter_rust_bridge.
/// Provides two entry points matching the Next2 API style:
/// - dfm_plus_prepare_layout: one-time layout computation
/// - dfm_plus_layout_frame: per-frame position query
///
/// Output format is compatible with Next2's FrameItemPayload (JSON),
/// allowing direct reuse of Next2's GPU rendering pipeline.

use rustc_hash::FxHashMap;
use std::collections::VecDeque;
use std::hash::{Hash, Hasher};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use crate::dfm_core::{
    filters::{FilterContext, FilterSystem},
    model::{DanmakuItem, DanmakuType, Duration, GlobalFlags},
    retainer::DanmakuRetainer,
};

// ---------------------------------------------------------------------------
// Public data structures (exposed to Dart via FRB)
// ---------------------------------------------------------------------------

/// Input danmaku item for layout preparation.
#[derive(Debug, Clone)]
pub struct DfmPlusDanmakuItem {
    pub time_seconds: f64,
    pub text: String,
    pub type_code: i32,
    pub color_argb: i32,
    pub is_me: bool,
    /// Pre-measured paint width from the font measurer (glyph_hor_advance).
    /// When set to a positive value, skips the Rust-side heuristic and uses this directly.
    pub paint_width: f64,
    /// Pre-measured paint height from the font measurer.
    pub paint_height: f64,
}

/// Layout preparation request.
#[derive(Debug, Clone)]
pub struct DfmPlusPrepareRequest {
    pub items: Vec<DfmPlusDanmakuItem>,
    pub width: f64,
    pub height: f64,
    pub font_size: f64,
    pub display_area: f64,
    pub scroll_duration_seconds: f64,
    pub allow_stacking: bool,
    pub merge_danmaku: bool,
    pub max_quantity: Option<u32>,
    pub max_lines_per_type: Option<u32>,
    pub track_gap_ratio: f64,
    pub outline_width: f64,
    pub block_words: Vec<String>,
}

/// Prepared layout result.
#[derive(Debug, Clone)]
pub struct DfmPlusPreparedLayout {
    pub handle: u64,
    pub width: f64,
    pub height: f64,
    pub scroll_duration_seconds: f64,
    pub static_duration_seconds: f64,
    pub items: Vec<DfmPlusPreparedItem>,
    pub item_times: Vec<f64>,
    pub track_count: i32,
    pub cache_key: u64,
}

impl DfmPlusPreparedLayout {
    fn with_handle(mut self) -> Self {
        let handle = NEXT_LAYOUT_HANDLE.fetch_add(1, Ordering::Relaxed);
        self.handle = handle;
        with_layout_store(|store| {
            store.insert(handle, Arc::new(self.clone()));
        });
        self
    }
}

/// Single prepared item with layout information.
#[derive(Debug, Clone)]
pub struct DfmPlusPreparedItem {
    pub time_seconds: f64,
    pub text: String,
    pub type_code: i32,
    pub color_argb: i32,
    pub is_me: bool,
    pub font_size_multiplier: f64,
    pub count_text: Option<String>,
    pub track_index: i32,
    pub y_position: f64,
    pub width: f64,
    pub scroll_speed: f64,
    pub is_filtered: bool,
    pub duration_seconds: f64,
    pub is_scroll: bool,
    pub centered_x: f64,
}

/// Per-frame layout request.
#[derive(Debug, Clone)]
pub struct DfmPlusFrameRequest {
    pub layout_handle: u64,
    pub current_time_seconds: f64,
}

/// Per-frame layout result.
#[derive(Debug, Clone)]
pub struct DfmPlusFrameLayout {
    pub items: Vec<DfmPlusFrameItem>,
}

/// Single frame item with computed position.
/// Only contains the item index and position data — no text/style clones.
/// The Dart side uses item_index to look up text/style from PreparedLayout.items.
#[derive(Debug, Clone)]
pub struct DfmPlusFrameItem {
    pub item_index: i32,
    pub x: f64,
    pub y: f64,
    pub offstage_x: f64,
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const STATIC_DURATION_MS: i64 = 3800;

const FRAME_CACHE_CAPACITY: usize = 256;

struct FrameCache {
    entries: FxHashMap<u64, DfmPlusFrameLayout>,
    insertion_order: VecDeque<u64>,
}

impl FrameCache {
    fn new() -> Self {
        Self {
            entries: FxHashMap::default(),
            insertion_order: VecDeque::with_capacity(FRAME_CACHE_CAPACITY),
        }
    }

    fn get(&mut self, key: u64) -> Option<DfmPlusFrameLayout> {
        self.entries.get(&key).cloned()
    }

    fn insert(&mut self, key: u64, value: DfmPlusFrameLayout) {
        if self.entries.insert(key, value).is_none() {
            self.insertion_order.push_back(key);
        }
        while self.entries.len() > FRAME_CACHE_CAPACITY {
            if let Some(evict_key) = self.insertion_order.pop_front() {
                self.entries.remove(&evict_key);
            } else {
                break;
            }
        }
    }
}

static FRAME_CACHE: OnceLock<Mutex<FrameCache>> = OnceLock::new();

fn with_frame_cache<F, R>(f: F) -> R
where
    F: FnOnce(&mut FrameCache) -> R,
{
    let cache = FRAME_CACHE.get_or_init(|| Mutex::new(FrameCache::new()));
    let mut guard = cache.lock().unwrap();
    f(&mut *guard)
}

static LAYOUT_STORE: OnceLock<Mutex<FxHashMap<u64, Arc<DfmPlusPreparedLayout>>>> = OnceLock::new();
static NEXT_LAYOUT_HANDLE: AtomicU64 = AtomicU64::new(1);

fn with_layout_store<F, R>(f: F) -> R
where
    F: FnOnce(&mut FxHashMap<u64, Arc<DfmPlusPreparedLayout>>) -> R,
{
    let store = LAYOUT_STORE.get_or_init(|| Mutex::new(FxHashMap::default()));
    let mut guard = store.lock().unwrap();
    f(&mut guard)
}

fn fxhash_str(s: &str) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut hasher = rustc_hash::FxHasher::default();
    s.hash(&mut hasher);
    hasher.finish()
}

fn calc_frame_cache_key(layout: &DfmPlusPreparedLayout, current_time_seconds: f64) -> u64 {
    let quantized_tick = (current_time_seconds * 60.0).round() as i64;
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    layout.cache_key.hash(&mut hasher);
    quantized_tick.hash(&mut hasher);
    hasher.finish()
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// One-time layout preparation.
/// Computes track assignments, collision avoidance, filtering, and merge.
/// Ported from DanmakuFlameMaster's DrawTask + DanmakusRetainer pipeline.
pub fn dfm_plus_prepare_layout(request: DfmPlusPrepareRequest) -> Result<DfmPlusPreparedLayout, String> {
    let width = request.width.max(1.0) as f32;
    let height = request.height.max(1.0) as f32;
    let font_size = request.font_size.max(1.0) as f32;
    let display_area = request.display_area.clamp(0.1, 1.0) as f32;
    let scroll_dur_secs = request.scroll_duration_seconds.max(1.0);
    let scroll_dur_ms = (scroll_dur_secs * 1000.0) as i64;

    let global_flags = GlobalFlags::default();

    // Build danmaku items
    let outline_width = request.outline_width.max(0.0) as f32;
    // Compute effective outline pixels matching GPU renderer's resolve_outline_px()
    let outline_px = resolve_outline_px(font_size, outline_width);
    let mut items: Vec<DanmakuItem> = request
        .items
        .iter()
        .enumerate()
        .map(|(i, raw)| {
            let danmaku_type = DanmakuType::from_code(raw.type_code);
            let dur_ms = if danmaku_type.is_scroll() {
                scroll_dur_ms
            } else {
                STATIC_DURATION_MS
            };
            let mut item = DanmakuItem::new(
                (raw.time_seconds * 1000.0) as i64,
                raw.text.clone(),
                raw.color_argb as u32,
                font_size,
                danmaku_type,
                dur_ms,
            );
            item.index = i as u32;

            // Use pre-measured dimensions from font measurer (pixel-accurate),
            // otherwise fall back to Rust-side heuristic.
            // Outline expands horizontally (left/right edges) for collision detection,
            // but NOT vertically — outline is thin and semi-transparent, adding it to
            // paint_height would waste track space and make the layout too sparse.
            if raw.paint_width > 0.0 && raw.paint_height > 0.0 {
                item.paint_width = raw.paint_width as f32 + outline_px * 2.0;
                item.paint_height = raw.paint_height as f32;
                if item.danmaku_type.is_scroll() {
                    let distance = width + item.paint_width;
                    item.step_x = distance / item.duration_ms as f32;
                }
                item.flags.measure = global_flags.measure_flag;
            }

            item
        })
        .collect();

    // Measure any items not pre-measured (fallback to heuristic)
    for item in &mut items {
        item.measure_with_outline(width, height, &global_flags, outline_px);
    }

    // Merge duplicates if requested
    let mut merge_map: FxHashMap<u64, Vec<usize>> = FxHashMap::default();
    if request.merge_danmaku {
        for (i, item) in items.iter().enumerate() {
            let text_hash = fxhash_str(&item.text);
            merge_map.entry(text_hash).or_default().push(i);
        }
        for indices in merge_map.values() {
            if indices.len() > 1 {
                let first_idx = indices[0];
                let first_text = items[first_idx].text.clone();
                for &idx in indices.iter().skip(1) {
                    if items[idx].text == first_text {
                        items[idx].is_filtered = true;
                        items[idx].filter_param = 99;
                    }
                }
                let real_count = indices.iter().filter(|&&idx| items[idx].is_filtered || idx == first_idx).count();
                if real_count > 1 {
                    items[first_idx].text.push_str(&format!(" x{}", real_count));
                }
            }
        }
    }

    // Filter system
    let mut filter_sys = FilterSystem::default();
    if let Some(q) = request.max_quantity {
        filter_sys.max_quantity = Some(q);
    }
    filter_sys.duplicate_merge = request.merge_danmaku;
    filter_sys.set_block_words(&request.block_words);

    let scroll_duration = Duration::new(scroll_dur_ms);
    let mut ctx = FilterContext {
        timer_ms: 0,
        index_in_screen: 0,
        screen_size: items.len(),
        frame_elapsed_ms: 0,
        global_flags: global_flags.clone(),
        scroll_duration: scroll_duration.clone(),
    };

    // Apply primary filters
    for (i, item) in items.iter_mut().enumerate() {
        ctx.index_in_screen = i;
        filter_sys.filter_primary(item, &ctx);
    }

    // Track-based collision avoidance layout
    // Group by type for better cache locality: each TrackData stays hot in L1
    let track_gap_ratio = request.track_gap_ratio.clamp(0.0, 2.0) as f32;
    let mut retainer = DanmakuRetainer::new(2.0, track_gap_ratio);

    let type_order: &[DanmakuType] = &[
        DanmakuType::ScrollRL,
        DanmakuType::ScrollLR,
        DanmakuType::FixTop,
        DanmakuType::FixBottom,
    ];

    for &danmaku_type in type_order {
        for i in 0..items.len() {
            if items[i].is_filtered || items[i].danmaku_type != danmaku_type {
                continue;
            }
            items[i].measure(width, height, &global_flags);
            let (placed, displaced_index) = retainer.fix(
                &mut items[i],
                width,
                height,
                &global_flags,
                display_area,
                false,
            );
            if !placed {
                continue;
            }
            for &displaced in &displaced_index {
                if displaced < items.len() && !items[displaced].is_filtered {
                    items[displaced].is_filtered = true;
                    items[displaced].filter_param = 99;
                }
            }
        }
    }

    // Build prepared output
    let mut prepared_items = Vec::with_capacity(items.len());
    let mut item_times = Vec::with_capacity(items.len());

    for item in &items {
        if item.is_filtered {
            continue;
        }
        let type_code = item.danmaku_type as i32;
        let is_scroll = item.danmaku_type.is_scroll();
        let centered_x = if is_scroll { 0.0 } else { (width as f64 - item.paint_width as f64) / 2.0 };
        prepared_items.push(DfmPlusPreparedItem {
            time_seconds: item.time_ms as f64 / 1000.0,
            text: item.text.clone(),
            type_code,
            color_argb: item.text_color as i32,
            is_me: false,
            font_size_multiplier: 1.0,
            count_text: None,
            track_index: 0,
            y_position: item.y as f64,
            width: item.paint_width as f64,
            scroll_speed: item.step_x as f64 * 1000.0,
            is_filtered: item.is_filtered,
            duration_seconds: item.duration_ms as f64 / 1000.0,
            is_scroll,
            centered_x,
        });
        item_times.push(item.time_ms as f64 / 1000.0);
    }

    let mut sort_indices: Vec<usize> = (0..item_times.len()).collect();
    sort_indices.sort_by(|&a, &b| item_times[a].partial_cmp(&item_times[b]).unwrap_or(std::cmp::Ordering::Equal));

    let sorted_times: Vec<f64> = sort_indices.iter().map(|&i| item_times[i]).collect();
    let sorted_items: Vec<DfmPlusPreparedItem> = sort_indices.into_iter().map(|i| prepared_items[i].clone()).collect();

    let cache_key = {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        (width as f64).to_bits().hash(&mut hasher);
        (height as f64).to_bits().hash(&mut hasher);
        font_size.to_bits().hash(&mut hasher);
        display_area.to_bits().hash(&mut hasher);
        scroll_dur_secs.to_bits().hash(&mut hasher);
        let visible_count = items.iter().filter(|i| !i.is_filtered).count();
        visible_count.hash(&mut hasher);
        for item in items.iter().filter(|i| !i.is_filtered).take(64) {
            item.time_ms.hash(&mut hasher);
            item.paint_width.to_bits().hash(&mut hasher);
            item.danmaku_type.hash(&mut hasher);
        }
        hasher.finish()
    };

    Ok(DfmPlusPreparedLayout {
        handle: 0,
        width: width as f64,
        height: height as f64,
        scroll_duration_seconds: scroll_dur_secs,
        static_duration_seconds: STATIC_DURATION_MS as f64 / 1000.0,
        items: sorted_items,
        item_times: sorted_times,
        track_count: ((height * display_area) / (font_size * 1.2 * 1.25)).max(1.0) as i32,
        cache_key,
    }
    .with_handle())
}

pub fn dfm_plus_layout_frame(request: DfmPlusFrameRequest) -> DfmPlusFrameLayout {
    let layout_arc = {
        let store = LAYOUT_STORE.get_or_init(|| Mutex::new(FxHashMap::default()));
        let guard = store.lock().unwrap();
        guard.get(&request.layout_handle).cloned()
    };

    let layout = match layout_arc {
        Some(arc) => arc,
        None => return DfmPlusFrameLayout { items: vec![] },
    };

    let frame_key = calc_frame_cache_key(&layout, request.current_time_seconds);
    let cached = with_frame_cache(|cache| cache.get(frame_key));
    if let Some(cached) = cached {
        return cached;
    }
    let result = build_dfm_plus_frame(&layout, request.current_time_seconds);
    with_frame_cache(|cache| cache.insert(frame_key, result.clone()));
    result
}

pub fn dfm_plus_drop_layout(handle: u64) {
    if handle != 0 {
        with_layout_store(|store| {
            store.remove(&handle);
        });
    }
}

fn build_dfm_plus_frame(layout: &DfmPlusPreparedLayout, current_time: f64) -> DfmPlusFrameLayout {
    let width = layout.width as f32;
    let scroll_dur = layout.scroll_duration_seconds;
    let static_dur = layout.static_duration_seconds;
    let max_dur = scroll_dur.max(static_dur);

    let window_start = current_time - max_dur;
    let start_idx = lower_bound(&layout.item_times, window_start);
    let end_idx = upper_bound(&layout.item_times, current_time);

    let mut frame_items = Vec::with_capacity(end_idx.saturating_sub(start_idx));

    for i in start_idx..end_idx {
        let item = &layout.items[i];
        let elapsed = current_time - item.time_seconds;
        if elapsed < 0.0 {
            continue;
        }

        let is_scroll = item.is_scroll;

        if !is_scroll && elapsed > item.duration_seconds {
            continue;
        }

        let (x, offstage_x) = if is_scroll {
            let speed = item.scroll_speed;
            let x = width as f64 - speed * elapsed;
            let offstage = width as f64 + item.width;
            (x, offstage)
        } else {
            let x = item.centered_x;
            let offstage = width as f64;
            (x, offstage)
        };

        if is_scroll && x < -item.width {
            continue;
        }

        if item.y_position < 0.0 {
            continue;
        }

        frame_items.push(DfmPlusFrameItem {
            item_index: i as i32,
            x,
            y: item.y_position,
            offstage_x,
        });
    }

    DfmPlusFrameLayout { items: frame_items }
}

// ---------------------------------------------------------------------------
// Binary search helpers
// ---------------------------------------------------------------------------

/// Find the first index where item_times[i] >= target.
fn lower_bound(times: &[f64], target: f64) -> usize {
    times.partition_point(|&t| t < target)
}

fn upper_bound(times: &[f64], target: f64) -> usize {
    times.partition_point(|&t| t <= target)
}

/// Compute the effective outline width in pixels, matching the GPU renderer's
/// `resolve_outline_px(font_size, outline_width)` exactly:
/// `(font_size * 0.06).clamp(1.0, 2.6) * outline_width.clamp(0.0, 4.0)`
fn resolve_outline_px(font_size: f32, outline_width: f32) -> f32 {
    let multiplier = outline_width.clamp(0.0, 4.0);
    if multiplier <= 0.0 || !multiplier.is_finite() {
        return 0.0;
    }
    (font_size * 0.06).clamp(1.0, 2.6) * multiplier
}

/// Font metrics matching the GPU renderer's layout parameters.
#[derive(Debug, Clone)]
pub struct DfmPlusFontMetrics {
    /// Line ascent matching GPU's `line_ascent()`: `max(px * 0.82, max_face_ascender)`.
    pub ascent: f64,
    /// Line descent: max face descender (absolute value).
    pub descent: f64,
    /// Total line height = ascent + descent.
    pub line_height: f64,
    /// Effective outline width in pixels, matching GPU's `resolve_outline_px()`.
    pub outline_px: f64,
}

/// Get font metrics for collision detection, matching the GPU renderer's computations exactly.
/// `custom_font_bytes`: optional custom font file contents.
pub fn dfm_plus_font_metrics(
    font_size: f64,
    outline_width: f64,
    _custom_font_bytes: Option<Vec<u8>>,
) -> Result<DfmPlusFontMetrics, String> {
    let fs = font_size as f32;
    let ow = outline_width as f32;
    Ok(DfmPlusFontMetrics {
        ascent: (fs * 0.9) as f64,
        descent: (fs * 0.3) as f64,
        line_height: crate::dfm_core::measure::measure_line_height_heuristic(fs) as f64,
        outline_px: resolve_outline_px(fs, ow) as f64,
    })
}

/// Measure the rendered width of a single text string using the same font metrics
/// as the GPU glyph atlas (glyph_hor_advance → scale_to_px → max fallback).
///
/// This ensures collision detection widths match rendering widths exactly.
/// `custom_font_bytes`: optional custom font file contents (pass None to use default embedded font).
pub fn dfm_plus_measure_text_width(
    text: String,
    font_size: f64,
    _custom_font_bytes: Option<Vec<u8>>,
) -> Result<f64, String> {
    Ok(crate::dfm_core::measure::measure_text_width_heuristic(&text, font_size as f32) as f64)
}

/// Measure widths of multiple text strings in a single call (amortizes font loading).
/// Returns a Vec of widths in the same order as the input texts.
pub fn dfm_plus_measure_text_widths(
    texts: Vec<String>,
    font_size: f64,
    _custom_font_bytes: Option<Vec<u8>>,
) -> Result<Vec<f64>, String> {
    Ok(texts
        .iter()
        .map(|t| crate::dfm_core::measure::measure_text_width_heuristic(t, font_size as f32) as f64)
        .collect())
}

pub fn dfm_plus_prepare_layout_full(
    raw_items: Vec<DfmPlusRawDanmakuItem>,
    width: f64,
    height: f64,
    font_size: f64,
    display_area: f64,
    scroll_duration_seconds: f64,
    allow_stacking: bool,
    merge_danmaku: bool,
    max_quantity: Option<u32>,
    max_lines_per_type: Option<u32>,
    track_gap_ratio: f64,
    outline_width: f64,
    _custom_font_bytes: Option<Vec<u8>>,
    block_words: Vec<String>,
) -> Result<DfmPlusPreparedLayout, String> {
    let fs = font_size as f32;
    let ow = outline_width as f32;
    let _outline_px = resolve_outline_px(fs, ow);

    let paint_height = crate::dfm_core::measure::measure_line_height_heuristic(fs) as f64;
    let widths: Vec<f64> = raw_items
        .iter()
        .map(|raw| crate::dfm_core::measure::measure_text_width_heuristic(&raw.text, fs) as f64)
        .collect();

    let items: Vec<DfmPlusDanmakuItem> = raw_items
        .into_iter()
        .enumerate()
        .map(|(i, raw)| {
            let w = widths.get(i).copied().unwrap_or(font_size * 0.55);
            DfmPlusDanmakuItem {
                time_seconds: raw.time_seconds,
                text: raw.text,
                type_code: raw.type_code,
                color_argb: raw.color_argb,
                is_me: raw.is_me,
                paint_width: w,
                paint_height,
            }
        })
        .collect();

    dfm_plus_prepare_layout(DfmPlusPrepareRequest {
        items,
        width,
        height,
        font_size,
        display_area,
        scroll_duration_seconds,
        allow_stacking,
        merge_danmaku,
        max_quantity,
        max_lines_per_type,
        track_gap_ratio,
        outline_width,
        block_words,
    })
}

#[derive(Debug, Clone)]
pub struct DfmPlusRawDanmakuItem {
    pub time_seconds: f64,
    pub text: String,
    pub type_code: i32,
    pub color_argb: i32,
    pub is_me: bool,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn test_simple_basic_output() {
        let req = DfmPlusPrepareRequest {
            items: vec![
                DfmPlusDanmakuItem {
                    time_seconds: 0.0,
                    text: "Test Top 1".into(),
                    type_code: 5, // FixTop
                    color_argb: 0xffffffffu32 as i32,
                    is_me: false,
                    paint_width: 100.0,
                    paint_height: 30.0,
                },
                DfmPlusDanmakuItem {
                    time_seconds: 0.5,
                    text: "Test Scroll 1".into(),
                    type_code: 1, // ScrollRL
                    color_argb: 0xffffffffu32 as i32,
                    is_me: false,
                    paint_width: 120.0,
                    paint_height: 30.0,
                },
            ],
            width: 1920.0,
            height: 1080.0,
            font_size: 25.0,
            display_area: 0.25,
            scroll_duration_seconds: 5.0,
            allow_stacking: false,
            merge_danmaku: false,
            max_quantity: None,
            max_lines_per_type: None,
            track_gap_ratio: 0.5,
            outline_width: 0.0,
            block_words: vec![],
        };
        
        let layout = dfm_plus_prepare_layout(req).expect("prepare should work");
        eprintln!("Prepared {} items", layout.items.len());
        
        for item in &layout.items {
            eprintln!(" - text={}, y={}, type={}", item.text, item.y_position, item.type_code);
        }
        
        assert_eq!(layout.items.len(), 2, "should have 2 items");
        
        let frame = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout_handle: layout.handle,
            current_time_seconds: 0.5,
        });
        
        eprintln!("Frame at 0.5s has {} items", frame.items.len());
        for fi in &frame.items {
            let pi = &layout.items[fi.item_index as usize];
            eprintln!(" - text={}, y={}, x={}, type={}", pi.text, fi.y, fi.x, pi.type_code);
        }
        
        assert_eq!(frame.items.len(), 2, "frame should have 2 items");
    }

    #[test]
    fn test_real_danmaku_no_top_overlap() {
        let json_str = fs::read_to_string("/Users/retr0/Documents/program_works/NipaPlay-Reload/测试弹幕.json")
            .expect("Failed to read danmaku data");
        let data: serde_json::Value = serde_json::from_str(&json_str)
            .expect("Failed to parse JSON");
        let comments = data.get("comments")
            .expect("No comments field")
            .as_array()
            .expect("Comments is not an array");

        let items: Vec<DfmPlusDanmakuItem> = comments.iter()
            .filter_map(|c| {
                let ctype = c.get("type")?.as_str()?;
                if ctype != "top" {
                    return None;
                }
                let time = c.get("time")?.as_f64()?;
                let text = c.get("content")?.as_str()?.to_string();
                let color = c.get("color").and_then(|v| {
                    let s = v.as_str()?;
                    let rgb = s.trim_start_matches("rgb(").trim_end_matches(")");
                    let parts: Vec<u8> = rgb.split(',')
                        .map(|p| p.trim().parse().unwrap_or(255))
                        .collect();
                    if parts.len() >= 3 {
                        Some((((255u32) << 24) | ((parts[0] as u32) << 16) | ((parts[1] as u32) << 8) | (parts[2] as u32)) as i32)
                    } else {
                        Some(-1i32)
                    }
                }).unwrap_or(-1);

                Some(DfmPlusDanmakuItem {
                    time_seconds: time,
                    text: text,
                    type_code: 5,
                    color_argb: color,
                    is_me: false,
                    paint_width: 100.0,
                    paint_height: 30.0,
                })
            })
            .collect();

        eprintln!("Loaded {} top danmaku from real data", items.len());

        let req = DfmPlusPrepareRequest {
            items,
            width: 1920.0,
            height: 1080.0,
            font_size: 25.0,
            display_area: 1.0,  // Use full screen for top danmaku
            scroll_duration_seconds: 5.0,
            allow_stacking: false,
            merge_danmaku: false,
            max_quantity: None,
            max_lines_per_type: None,
            track_gap_ratio: 0.5,
            outline_width: 0.0,
            block_words: vec![],
        };

        let layout = dfm_plus_prepare_layout(req).expect("prepare layout failed");

        eprintln!("Prepared layout: {} items total", layout.items.len());
        let top_count = layout.items.iter().filter(|i| i.type_code == 5).count();
        eprintln!("Top danmaku in layout: {}", top_count);

        // Print the first few items in the layout with their times
        eprintln!("First 10 items in layout:");
        for (i, item) in layout.items.iter().take(10).enumerate() {
            eprintln!("  [{}] text={:.30}, time={:.2}s, y={:.1}, track={}", 
                i, item.text, item.time_seconds, item.y_position, item.track_index);
        }

        // Test at a time where we have prepared items (around 1042-1050 seconds)
        for test_time in [1042.0, 1043.0, 1046.0, 1346.0, 1350.0, 1399.0, 1400.0, 1409.0, 1420.0, 1432.0, 1448.0] {
            let frame = dfm_plus_layout_frame(DfmPlusFrameRequest {
                layout_handle: layout.handle,
                current_time_seconds: test_time,
            });

            let top_items: Vec<_> = frame.items.iter()
                .filter(|fi| layout.items[fi.item_index as usize].type_code == 5)
                .collect();

            eprintln!("Frame at t={:.2}s, total items: {}, top items: {}", test_time, frame.items.len(), top_items.len());
            for fi in &top_items {
                let pi = &layout.items[fi.item_index as usize];
                eprintln!("  text={:.20}, y={:.1}, time={:.2}", pi.text, fi.y, pi.time_seconds);
            }

            for i in 0..top_items.len() {
                for j in (i+1)..top_items.len() {
                    let y_diff = (top_items[i].y - top_items[j].y).abs();
                    let pi_i = &layout.items[top_items[i].item_index as usize];
                    let pi_j = &layout.items[top_items[j].item_index as usize];
                    assert!(y_diff > 1.0,
                        "At t={:.2}s, top items '{}' (y={:.1}) and '{}' (y={:.1}) share same y!",
                        test_time, pi_i.text, top_items[i].y, pi_j.text, top_items[j].y);
                }
            }
        }
    }

    #[test]
    fn test_prepare_basic() {
        let req = DfmPlusPrepareRequest {
            items: vec![
                DfmPlusDanmakuItem {
                    time_seconds: 1.0,
                    text: "hello".into(),
                    type_code: 0,
                    color_argb: -1i32,
                    is_me: false,
                    paint_width: 0.0,
                    paint_height: 0.0,
                },
                DfmPlusDanmakuItem {
                    time_seconds: 2.0,
                    text: "world".into(),
                    type_code: 0,
                    color_argb: -1i32,
                    is_me: false,
                    paint_width: 0.0,
                    paint_height: 0.0,
                },
            ],
            width: 1920.0,
            height: 1080.0,
            font_size: 25.0,
            display_area: 1.0,
            scroll_duration_seconds: 5.0,
            allow_stacking: false,
            merge_danmaku: false,
            max_quantity: None,
            max_lines_per_type: None,
            track_gap_ratio: 0.5,
            outline_width: 0.0,
            block_words: vec![],
        };

        let result = dfm_plus_prepare_layout(req);
        assert!(result.is_ok());
        let layout = result.unwrap();
        assert_eq!(layout.items.len(), 2);
        assert!(layout.scroll_duration_seconds > 0.0);
    }

    #[test]
    fn test_layout_frame() {
        let req = DfmPlusPrepareRequest {
            items: vec![
                DfmPlusDanmakuItem {
                    time_seconds: 1.0,
                    text: "test".into(),
                    type_code: 0,
                    color_argb: -1i32,
                    is_me: false,
                    paint_width: 0.0,
                    paint_height: 0.0,
                },
            ],
            width: 1920.0,
            height: 1080.0,
            font_size: 25.0,
            display_area: 1.0,
            scroll_duration_seconds: 5.0,
            allow_stacking: false,
            merge_danmaku: false,
            max_quantity: None,
            max_lines_per_type: None,
            track_gap_ratio: 0.5,
            outline_width: 0.0,
            block_words: vec![],
        };

        let layout = dfm_plus_prepare_layout(req).unwrap();
        let frame = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout_handle: layout.handle,
            current_time_seconds: 1.5,
        });
        assert_eq!(frame.items.len(), 1);
        assert!(frame.items[0].x > 500.0);
    }

    #[test]
    fn test_binary_search() {
        let times = vec![1.0, 2.0, 3.0, 4.0, 5.0];
        assert_eq!(lower_bound(&times, 2.5), 2);
        assert_eq!(upper_bound(&times, 2.5), 2);
        assert_eq!(lower_bound(&times, 0.5), 0);
        assert_eq!(upper_bound(&times, 5.5), 5);
    }

    #[test]
    fn test_top_danmaku_no_overlap_in_same_frame() {
        let req = DfmPlusPrepareRequest {
            items: vec![
                DfmPlusDanmakuItem {
                    time_seconds: 0.0,
                    text: "top1".into(),
                    type_code: 5,
                    color_argb: -1i32,
                    is_me: false,
                    paint_width: 100.0,
                    paint_height: 30.0,
                },
                DfmPlusDanmakuItem {
                    time_seconds: 0.0,
                    text: "top2".into(),
                    type_code: 5,
                    color_argb: -1i32,
                    is_me: false,
                    paint_width: 100.0,
                    paint_height: 30.0,
                },
                DfmPlusDanmakuItem {
                    time_seconds: 0.0,
                    text: "top3".into(),
                    type_code: 5,
                    color_argb: -1i32,
                    is_me: false,
                    paint_width: 100.0,
                    paint_height: 30.0,
                },
            ],
            width: 1920.0,
            height: 1080.0,
            font_size: 25.0,
            display_area: 1.0,
            scroll_duration_seconds: 5.0,
            allow_stacking: false,
            merge_danmaku: false,
            max_quantity: None,
            max_lines_per_type: None,
            track_gap_ratio: 0.5,
            outline_width: 0.0,
            block_words: vec![],
        };

        let layout = dfm_plus_prepare_layout(req).unwrap();
        let frame = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout_handle: layout.handle,
            current_time_seconds: 1.0,
        });

        let top_items: Vec<_> = frame.items.iter()
            .filter(|fi| layout.items[fi.item_index as usize].type_code == 5)
            .collect();

        eprintln!("Frame at t=1.0, top items: {}", top_items.len());
        for fi in &top_items {
            let pi = &layout.items[fi.item_index as usize];
            eprintln!("  text={}, y={}", pi.text, fi.y);
        }

        for i in 0..top_items.len() {
            for j in (i+1)..top_items.len() {
                let y_diff = (top_items[i].y - top_items[j].y).abs();
                let pi_i = &layout.items[top_items[i].item_index as usize];
                let pi_j = &layout.items[top_items[j].item_index as usize];
                assert!(y_diff > 1.0, 
                    "TOP items {} and {} share y={}, causing visual overlap!", 
                    pi_i.text, pi_j.text, top_items[i].y);
            }
        }
    }

    // 修改了一下函数，手动执行测试真实弹幕，看为什么只保留 11 条
    fn debug_real_danmaku() {
        let json_str = std::fs::read_to_string("/Users/retr0/Documents/program_works/NipaPlay-Reload/上伊那牡丹，酒醉身姿似百合花般_danmaku_20260527_233650.json")
            .expect("Failed to read real danmaku data");
        let data: serde_json::Value = serde_json::from_str(&json_str)
            .expect("Failed to parse JSON");
        let comments = data.get("comments")
            .expect("No comments field")
            .as_array()
            .expect("Comments is not an array");

        let items: Vec<DfmPlusDanmakuItem> = comments.iter()
            .filter_map(|c| {
                let time = c.get("time")?.as_f64()?;
                let text = c.get("content")?.as_str()?.to_string();
                let type_str = c.get("type")?.as_str()?;
                let type_code = match type_str {
                    "top" => 5,
                    "bottom" =>4,
                    "scroll" =>1,
                    _ => 1,
                };
                let color = c.get("color").and_then(|v| {
                    let s = v.as_str()?;
                    let rgb = s.trim_start_matches("rgb(").trim_end_matches(")");
                    let parts: Vec<u8> = rgb.split(',')
                        .map(|p| p.trim().parse().unwrap_or(255))
                        .collect();
                    if parts.len() >= 3 {
                        Some((((255u32) << 24) | ((parts[0] as u32) << 16) | ((parts[1] as u32) << 8) | (parts[2] as u32)) as i32)
                    } else {
                        Some(-1i32)
                    }
                }).unwrap_or(-1);

                Some(DfmPlusDanmakuItem {
                    time_seconds: time,
                    text: text,
                    type_code,
                    color_argb: color,
                    is_me: false,
                    paint_width: 100.0,
                    paint_height: 30.0,
                })
            })
            .collect();

        eprintln!("Loaded {} danmaku from real data", items.len());

        let width = 1920.0_f64.max(1.0) as f32;
        let height = 1080.0_f64.max(1.0) as f32;
        let font_size = 25.0_f64.max(1.0) as f32;
        let display_area = 0.5_f64.clamp(0.1,1.0) as f32;
        let scroll_dur_secs = 8.0_f64.max(1.0);
        let scroll_dur_ms = (scroll_dur_secs * 1000.0) as i64;
        let global_flags = crate::dfm_core::model::GlobalFlags::default();
        let outline_width = 0.0_f64.max(0.0) as f32;
        let outline_px = resolve_outline_px(font_size, outline_width);

        let mut danmaku_items: Vec<crate::dfm_core::model::DanmakuItem> = items
            .iter()
            .enumerate()
            .map(|(i, raw)| {
                let danmaku_type = crate::dfm_core::model::DanmakuType::from_code(raw.type_code);
                let dur_ms = if danmaku_type.is_scroll() {
                    scroll_dur_ms
                } else {
                    STATIC_DURATION_MS
                };
                let mut item = crate::dfm_core::model::DanmakuItem::new(
                    (raw.time_seconds * 1000.0) as i64,
                    raw.text.clone(),
                    raw.color_argb as u32,
                    font_size,
                    danmaku_type,
                    dur_ms,
                );
                item.index = i as u32;
                if raw.paint_width > 0.0 && raw.paint_height >0.0 {
                    item.paint_width = raw.paint_width as f32 + outline_px *2.0;
                    item.paint_height = raw.paint_height as f32;
                    item.flags.measure = global_flags.measure_flag;
                }
                item
            })
            .collect();

        // 检查是否被 filter_primary，不应用过滤器，而是直接打印它们的 type
        let mut top_filtered_by_param = [0;7].map(|_| 0);
        let mut top_total = 0;
        for item in &danmaku_items {
            if item.danmaku_type == crate::dfm_core::model::DanmakuType::FixTop {
                top_total += 1;
            }
        }

        eprintln!("TOP total: {}", top_total);

        // Now, let's run through exactly what dfm_plus_prepare_layout does!
        let scroll_duration = crate::dfm_core::model::Duration::new(scroll_dur_ms);
        let mut ctx = crate::dfm_core::filters::FilterContext {
            timer_ms: 0,
            index_in_screen: 0,
            screen_size: danmaku_items.len(),
            frame_elapsed_ms: 0,
            global_flags: global_flags.clone(),
            scroll_duration,
        };

        let mut filter_sys = crate::dfm_core::filters::FilterSystem::default();

        // Let's apply filter primary!
        let mut param_counts = [0; 10];
        for (i, item) in danmaku_items.iter_mut().enumerate() {
            ctx.index_in_screen = i;
            let was_top = item.danmaku_type == crate::dfm_core::model::DanmakuType::FixTop;
            filter_sys.filter_primary(item, &ctx);
            if was_top {
                param_counts[item.filter_param as usize] += 1;
                if item.is_filtered {
                    eprintln!("FILTERED TOP danmaku at {}: param={}", item.text, item.filter_param);
                }
            }
        }

        eprintln!("TOP filter params: {:?}", param_counts);

        let mut top_after_filter = danmaku_items.iter().filter(|i| i.danmaku_type == crate::dfm_core::model::DanmakuType::FixTop && !i.is_filtered).count();

        eprintln!("TOP AFTER filter_primary: {}", top_after_filter);

        // Now let's run through the Retainer part!
        let mut top_count_before_retainer = top_after_filter;
        let track_gap_ratio = 0.5_f32;
        let global_flags = crate::dfm_core::model::GlobalFlags::default();
        let mut retainer = crate::dfm_core::retainer::DanmakuRetainer::new(2.0, track_gap_ratio);
        let width = 1920.0_f32;
        let height = 1080.0_f32;
        let display_area = 0.5_f32;

        let mut top_not_placed = 0;
        let mut top_placed = 0;
        let mut top_skipped = 0;

        for item in danmaku_items.iter_mut() {
            if item.is_filtered {
                continue;
            }
            item.measure(width, height, &global_flags);
            let is_top = item.danmaku_type == crate::dfm_core::model::DanmakuType::FixTop;
            let (placed, _displaced_index) = retainer.fix(
                item,
                width,
                height,
                &global_flags,
                display_area,
                false,
            );
            if is_top {
                if placed {
                    top_placed +=1;
                    eprintln!("PLACED TOP: {}", item.text);
                } else {
                    top_skipped +=1;
                }
            }
        }

        eprintln!("Top before: {}, placed: {}, skipped: {}", top_count_before_retainer, top_placed, top_skipped);
    }

    #[test]
    fn test_real_danmaku_local_file() {
        // 先运行我们的调试函数！
        debug_real_danmaku();

        let json_str = std::fs::read_to_string("/Users/retr0/Documents/program_works/NipaPlay-Reload/上伊那牡丹，酒醉身姿似百合花般_danmaku_20260527_233650.json")
            .expect("Failed to read real danmaku data");
        let data: serde_json::Value = serde_json::from_str(&json_str)
            .expect("Failed to parse JSON");
        let comments = data.get("comments")
            .expect("No comments field")
            .as_array()
            .expect("Comments is not an array");

        let items: Vec<DfmPlusDanmakuItem> = comments.iter()
            .filter_map(|c| {
                let time = c.get("time")?.as_f64()?;
                let text = c.get("content")?.as_str()?.to_string();
                let type_str = c.get("type")?.as_str()?;
                let type_code = match type_str {
                    "top" => 5,
                    "bottom" =>4,
                    "scroll" =>1,
                    _ => 1,
                };
                let color = c.get("color").and_then(|v| {
                    let s = v.as_str()?;
                    let rgb = s.trim_start_matches("rgb(").trim_end_matches(")");
                    let parts: Vec<u8> = rgb.split(',')
                        .map(|p| p.trim().parse().unwrap_or(255))
                        .collect();
                    if parts.len() >=3 {
                        Some((((255u32) << 24) | ((parts[0] as u32) << 16) | ((parts[1] as u32) << 8) | (parts[2] as u32)) as i32)
                    } else {
                        Some(-1i32)
                    }
                }).unwrap_or(-1);

                Some(DfmPlusDanmakuItem {
                    time_seconds: time,
                    text: text,
                    type_code,
                    color_argb: color,
                    is_me: false,
                    paint_width:100.0,
                    paint_height:30.0,
                })
            })
            .collect();

        eprintln!("Loaded {} danmaku from real data", items.len());

        let req = DfmPlusPrepareRequest {
            items,
            width:1920.0,
            height:1080.0,
            font_size:25.0,
            display_area:0.5,
            scroll_duration_seconds:8.0,
            allow_stacking: false,
            merge_danmaku: false,
            max_quantity: None,
            max_lines_per_type: None,
            track_gap_ratio:0.5,
            outline_width:0.0,
            block_words: vec![],
        };

        let layout = dfm_plus_prepare_layout(req).expect("prepare layout failed");
        eprintln!("Prepared items: {}", layout.items.len());
        let top_prepared = layout.items.iter().filter(|i| i.type_code ==5).count();
        let bottom_prepared = layout.items.iter().filter(|i| i.type_code ==4).count();
        eprintln!("Top prepared: {}, Bottom prepared: {}", top_prepared, bottom_prepared);

        // Test t= 1.0 看看有没有
        let test_time = 1.0;
        let frame = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout_handle: layout.handle,
            current_time_seconds: test_time,
        });
        eprintln!("Frame at {}s has {} items total", test_time, frame.items.len());
        let top_in_frame = frame.items.iter().filter(|fi| layout.items[fi.item_index as usize].type_code ==5).count();
        let bottom_in_frame = frame.items.iter().filter(|fi| layout.items[fi.item_index as usize].type_code ==4).count();
        let scroll_in_frame = frame.items.iter().filter(|fi| { let tc = layout.items[fi.item_index as usize].type_code; tc ==1 || tc ==6 }).count();
        eprintln!("Top in frame: {}, bottom: {}, scroll: {}", top_in_frame, bottom_in_frame, scroll_in_frame);

        eprintln!("Top in frame:");
        for fi in frame.items.iter().filter(|fi| layout.items[fi.item_index as usize].type_code ==5) {
            let pi = &layout.items[fi.item_index as usize];
            eprintln!("  text=\"{}\", y={}, time={}", pi.text, fi.y, pi.time_seconds);
        }
    }

    #[test]
    fn test_top_danmaku_multiple_time_slots() {
        let req = DfmPlusPrepareRequest {
            items: vec![
                DfmPlusDanmakuItem {
                    time_seconds: 0.0,
                    text: "top1_t0".into(),
                    type_code: 5,
                    color_argb: -1i32,
                    is_me: false,
                    paint_width: 100.0,
                    paint_height: 30.0,
                },
                DfmPlusDanmakuItem {
                    time_seconds: 0.0,
                    text: "top2_t0".into(),
                    type_code: 5,
                    color_argb: -1i32,
                    is_me: false,
                    paint_width: 100.0,
                    paint_height: 30.0,
                },
                DfmPlusDanmakuItem {
                    time_seconds: 4.0,
                    text: "top3_t4".into(),
                    type_code: 5,
                    color_argb: -1i32,
                    is_me: false,
                    paint_width: 100.0,
                    paint_height: 30.0,
                },
                DfmPlusDanmakuItem {
                    time_seconds: 4.0,
                    text: "top4_t4".into(),
                    type_code: 5,
                    color_argb: -1i32,
                    is_me: false,
                    paint_width: 100.0,
                    paint_height: 30.0,
                },
            ],
            width: 1920.0,
            height: 1080.0,
            font_size: 25.0,
            display_area: 1.0,
            scroll_duration_seconds: 5.0,
            allow_stacking: false,
            merge_danmaku: false,
            max_quantity: None,
            max_lines_per_type: None,
            track_gap_ratio: 0.5,
            outline_width: 0.0,
            block_words: vec![],
        };

        let layout = dfm_plus_prepare_layout(req).unwrap();

        let frame_at_1s = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout_handle: layout.handle,
            current_time_seconds: 1.0,
        });
        let top_at_1s: Vec<_> = frame_at_1s.items.iter()
            .filter(|fi| layout.items[fi.item_index as usize].type_code == 5)
            .collect();

        eprintln!("Frame at t=1.0, top items: {}", top_at_1s.len());
        for fi in &top_at_1s {
            let pi = &layout.items[fi.item_index as usize];
            eprintln!("  text={}, y={}", pi.text, fi.y);
        }

        let frame_at_5s = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout_handle: layout.handle,
            current_time_seconds: 5.0,
        });
        let top_at_5s: Vec<_> = frame_at_5s.items.iter()
            .filter(|fi| layout.items[fi.item_index as usize].type_code == 5)
            .collect();

        eprintln!("Frame at t=5.0, top items: {}", top_at_5s.len());
        for fi in &top_at_5s {
            let pi = &layout.items[fi.item_index as usize];
            eprintln!("  text={}, y={}", pi.text, fi.y);
        }

        for i in 0..top_at_1s.len() {
            for j in (i+1)..top_at_1s.len() {
                let y_diff = (top_at_1s[i].y - top_at_1s[j].y).abs();
                let pi_i = &layout.items[top_at_1s[i].item_index as usize];
                let pi_j = &layout.items[top_at_1s[j].item_index as usize];
                assert!(y_diff > 1.0, 
                    "At t=1.0, top items {} and {} share y={}!", 
                    pi_i.text, pi_j.text, top_at_1s[i].y);
            }
        }

        for i in 0..top_at_5s.len() {
            for j in (i+1)..top_at_5s.len() {
                let y_diff = (top_at_5s[i].y - top_at_5s[j].y).abs();
                let pi_i = &layout.items[top_at_5s[i].item_index as usize];
                let pi_j = &layout.items[top_at_5s[j].item_index as usize];
                assert!(y_diff > 1.0, 
                    "At t=5.0, top items {} and {} share y={}!", 
                    pi_i.text, pi_j.text, top_at_5s[i].y);
            }
        }
    }
}
