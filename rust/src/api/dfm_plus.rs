/// DFM+ public API for flutter_rust_bridge.
/// Provides two entry points matching the Next2 API style:
/// - dfm_plus_prepare_layout: one-time layout computation
/// - dfm_plus_layout_frame: per-frame position query
///
/// Output format is compatible with Next2's FrameItemPayload (JSON),
/// allowing direct reuse of Next2's GPU rendering pipeline.

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
    /// Gap ratio between tracks. 0.5 = 50% of item height as gap. Default: 0.5.
    pub track_gap_ratio: f64,
    /// Outline width in pixels, used to expand paint_width for accurate collision detection.
    pub outline_width: f64,
}

/// Prepared layout result.
#[derive(Debug, Clone)]
pub struct DfmPlusPreparedLayout {
    pub width: f64,
    pub height: f64,
    pub scroll_duration_seconds: f64,
    pub static_duration_seconds: f64,
    pub items: Vec<DfmPlusPreparedItem>,
    pub item_times: Vec<f64>,
    pub track_count: i32,
    pub cache_key: u64,
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
}

/// Per-frame layout request.
#[derive(Debug, Clone)]
pub struct DfmPlusFrameRequest {
    pub layout: DfmPlusPreparedLayout,
    pub current_time_seconds: f64,
}

/// Per-frame layout result.
#[derive(Debug, Clone)]
pub struct DfmPlusFrameLayout {
    pub items: Vec<DfmPlusFrameItem>,
}

/// Single frame item with computed position.
#[derive(Debug, Clone)]
pub struct DfmPlusFrameItem {
    pub time_seconds: f64,
    pub text: String,
    pub type_code: i32,
    pub color_argb: i32,
    pub is_me: bool,
    pub font_size_multiplier: f64,
    pub count_text: Option<String>,
    pub x: f64,
    pub y: f64,
    pub offstage_x: f64,
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const STATIC_DURATION_MS: i64 = 3800;

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
            // IMPORTANT: outline is rendered OUTSIDE text bounds by the GPU SDF shader,
            // so we must expand by outline_px (matching resolve_outline_px) on both sides.
            if raw.paint_width > 0.0 && raw.paint_height > 0.0 {
                item.paint_width = raw.paint_width as f32 + outline_px * 2.0;
                item.paint_height = raw.paint_height as f32 + outline_px * 2.0;
                if item.danmaku_type.is_scroll() {
                    let distance = width + item.paint_width;
                    item.step_x = distance / item.duration_ms as f32;
                }
                item.measure_flag = global_flags.measure_flag;
            }

            item
        })
        .collect();

    // Measure any items not pre-measured (fallback to heuristic)
    for item in &mut items {
        item.measure_with_outline(width, height, &global_flags, outline_px);
    }

    // Merge duplicates if requested
    let mut merge_map: std::collections::HashMap<String, Vec<usize>> = std::collections::HashMap::new();
    if request.merge_danmaku {
        for (i, item) in items.iter().enumerate() {
            merge_map.entry(item.text.clone()).or_default().push(i);
        }
        for (_text, indices) in &merge_map {
            if indices.len() > 1 {
                let count = indices.len();
                let _multiplier = (1.0 + count as f64 / 10.0).clamp(1.0, 2.0);
                for &idx in indices.iter().skip(1) {
                    items[idx].is_filtered = true;
                    items[idx].filter_param = 99;
                }
                if let Some(&first_idx) = indices.first() {
                    items[first_idx].text = format!("{} x{}", items[first_idx].text, count);
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
    let track_gap_ratio = request.track_gap_ratio.clamp(0.0, 2.0) as f32;
    let mut retainer = DanmakuRetainer::new(2.0, track_gap_ratio);

    for i in 0..items.len() {
        if items[i].is_filtered {
            continue;
        }
        items[i].measure(width, height, &global_flags);
        let (placed, displaced_index) = retainer.fix(
            &mut items[i],
            width,
            height,
            &global_flags,
            display_area,
        );
        let is_top_current = items[i].danmaku_type == DanmakuType::FixTop;
        if !placed {
            if is_top_current {
                eprintln!("NOT PLACED TOP: i={}, time: {}, text: {}", i, items[i].time_ms as f64 / 1000.0, items[i].text);
            }
            continue;
        }
        if let Some(displaced) = displaced_index {
            if displaced < items.len() && !items[displaced].is_filtered {
                let is_top_displaced = items[displaced].danmaku_type == DanmakuType::FixTop;
                if is_top_displaced {
                    eprintln!("DISPLACED TOP: displacing index {}, i={}, time: {}, text: {} because of {}", 
                        displaced, i, items[displaced].time_ms as f64 / 1000.0, items[displaced].text, items[i].text);
                }
                items[displaced].is_filtered = true;
                items[displaced].filter_param = 99;
            }
        }
    }

    // Build prepared output
    let mut prepared_items = Vec::with_capacity(items.len());
    let mut item_times = Vec::with_capacity(items.len());
    let mut top_prepared = 0;
    let mut top_filtered_count = 0;

    for item in &items {
        let is_top = item.danmaku_type == DanmakuType::FixTop;
        if item.is_filtered {
            if is_top {
                top_filtered_count +=1;
                eprintln!("FILTERED TOP: time: {}, text: {}, param: {}", item.time_ms as f64 / 1000.0, item.text, item.filter_param);
            }
            continue;
        }
        let type_code = item.danmaku_type as i32;
        if is_top {
            eprintln!("KEEPING TOP: time: {}, text: {}, y: {}", item.time_ms as f64 /1000.0, item.text, item.y);
        }
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
        });
        item_times.push(item.time_ms as f64 / 1000.0);
    }
    eprintln!("Prepared items total: {} (top filtered: {})", prepared_items.len(), top_filtered_count);

    // Sort by time for binary search
    let mut pairs: Vec<(f64, DfmPlusPreparedItem)> = item_times
        .iter()
        .zip(prepared_items.iter())
        .map(|(&t, item)| (t, item.clone()))
        .collect();
    pairs.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));

    let sorted_times: Vec<f64> = pairs.iter().map(|(t, _)| *t).collect();
    let sorted_items: Vec<DfmPlusPreparedItem> = pairs.into_iter().map(|(_, item)| item).into_iter().collect();

    let cache_key = fnv1a_hash(&format!("{:?}_{:?}_{:?}_{:?}", width, height, font_size, items.len()));

    Ok(DfmPlusPreparedLayout {
        width: width as f64,
        height: height as f64,
        scroll_duration_seconds: scroll_dur_secs,
        static_duration_seconds: STATIC_DURATION_MS as f64 / 1000.0,
        items: sorted_items,
        item_times: sorted_times,
        track_count: ((height * display_area) / (font_size * 1.2 * 1.25)).max(1.0) as i32,
        cache_key,
    })
}

/// Per-frame layout query.
/// Computes X positions for visible danmaku at the current time.
/// Output format is compatible with Next2's FrameItemPayload.
pub fn dfm_plus_layout_frame(request: DfmPlusFrameRequest) -> DfmPlusFrameLayout {
    let layout = &request.layout;
    let current_time = request.current_time_seconds;
    let width = layout.width as f32;
    let scroll_dur = layout.scroll_duration_seconds;
    let static_dur = layout.static_duration_seconds;
    let max_dur = scroll_dur.max(static_dur);

    // Binary search for the time window [current_time - max_dur, current_time]
    let window_start = current_time - max_dur;
    let start_idx = lower_bound(&layout.item_times, window_start);
    let end_idx = upper_bound(&layout.item_times, current_time);

    let mut frame_items = Vec::with_capacity(end_idx.saturating_sub(start_idx));

    for i in start_idx..end_idx {
        let item = &layout.items[i];
        let elapsed = current_time - item.time_seconds;
        if elapsed < 0.0 {
            continue; // not yet visible
        }

        let type_code = item.type_code;
        let is_scroll = type_code == 1 || type_code == 6; // DFM ScrollRL(1) or ScrollLR(6)

        if !is_scroll && elapsed > item.duration_seconds {
            continue; // fixed danmaku expired
        }

        let (x, offstage_x) = if is_scroll {
            let speed = item.scroll_speed; // px/s
            let x = width as f64 - speed * elapsed;
            let offstage = width as f64 + item.width;
            (x, offstage)
        } else {
            let x = (width as f64 - item.width) / 2.0;
            let offstage = width as f64;
            (x, offstage)
        };

        // Skip if fully offscreen
        if is_scroll && x < -item.width {
            continue;
        }

        // Skip items that weren't placed by the retainer
        if item.y_position < 0.0 {
            continue;
        }

        frame_items.push(DfmPlusFrameItem {
            time_seconds: item.time_seconds,
            text: item.text.clone(),
            type_code: item.type_code,
            color_argb: item.color_argb,
            is_me: item.is_me,
            font_size_multiplier: item.font_size_multiplier,
            count_text: item.count_text.clone(),
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
    let mut lo = 0;
    let mut hi = times.len();
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if times[mid] < target {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    lo
}

/// Find the first index where item_times[i] > target.
fn upper_bound(times: &[f64], target: f64) -> usize {
    let mut lo = 0;
    let mut hi = times.len();
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if times[mid] <= target {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    lo
}

/// FNV-1a hash.
fn fnv1a_hash(s: &str) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in s.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
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
    custom_font_bytes: Option<Vec<u8>>,
) -> Result<DfmPlusFontMetrics, String> {
    let measurer = crate::dfm_core::measure::FontMeasurer::new(custom_font_bytes)?;
    let fs = font_size as f32;
    let ow = outline_width as f32;
    Ok(DfmPlusFontMetrics {
        ascent: measurer.line_ascent(fs) as f64,
        descent: measurer.line_descent(fs) as f64,
        line_height: measurer.line_height(fs) as f64,
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
    custom_font_bytes: Option<Vec<u8>>,
) -> Result<f64, String> {
    let measurer = crate::dfm_core::measure::FontMeasurer::new(custom_font_bytes)?;
    Ok(measurer.measure_width(&text, font_size as f32) as f64)
}

/// Measure widths of multiple text strings in a single call (amortizes font loading).
/// Returns a Vec of widths in the same order as the input texts.
pub fn dfm_plus_measure_text_widths(
    texts: Vec<String>,
    font_size: f64,
    custom_font_bytes: Option<Vec<u8>>,
) -> Result<Vec<f64>, String> {
    let measurer = crate::dfm_core::measure::FontMeasurer::new(custom_font_bytes)?;
    Ok(texts
        .iter()
        .map(|t| measurer.measure_width(t, font_size as f32) as f64)
        .collect())
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
        };
        
        let layout = dfm_plus_prepare_layout(req).expect("prepare should work");
        eprintln!("Prepared {} items", layout.items.len());
        
        for item in &layout.items {
            eprintln!(" - text={}, y={}, type={}", item.text, item.y_position, item.type_code);
        }
        
        assert_eq!(layout.items.len(), 2, "should have 2 items");
        
        let frame = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout: layout.clone(),
            current_time_seconds: 0.5,
        });
        
        eprintln!("Frame at 0.5s has {} items", frame.items.len());
        for item in &frame.items {
            eprintln!(" - text={}, y={}, x={}, type={}", item.text, item.y, item.x, item.type_code);
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
                layout: layout.clone(),
                current_time_seconds: test_time,
            });

            let top_items: Vec<_> = frame.items.iter()
                .filter(|i| i.type_code == 5)
                .collect();

            eprintln!("Frame at t={:.2}s, total items: {}, top items: {}", test_time, frame.items.len(), top_items.len());
            for item in &top_items {
                eprintln!("  text={:.20}, y={:.1}, time={:.2}", item.text, item.y, item.time_seconds);
            }

            for i in 0..top_items.len() {
                for j in (i+1)..top_items.len() {
                    let y_diff = (top_items[i].y - top_items[j].y).abs();
                    assert!(y_diff > 1.0,
                        "At t={:.2}s, top items '{}' (y={:.1}) and '{}' (y={:.1}) share same y!",
                        test_time, top_items[i].text, top_items[i].y, top_items[j].text, top_items[j].y);
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
        };

        let layout = dfm_plus_prepare_layout(req).unwrap();
        let frame = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout,
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
        };

        let layout = dfm_plus_prepare_layout(req).unwrap();
        let frame = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout: layout.clone(),
            current_time_seconds: 1.0,
        });

        let top_items: Vec<_> = frame.items.iter()
            .filter(|i| i.type_code == 5)
            .collect();

        eprintln!("Frame at t=1.0, top items: {}", top_items.len());
        for item in &top_items {
            eprintln!("  text={}, y={}", item.text, item.y);
        }

        for i in 0..top_items.len() {
            for j in (i+1)..top_items.len() {
                let y_diff = (top_items[i].y - top_items[j].y).abs();
                assert!(y_diff > 1.0, 
                    "TOP items {} and {} share y={}, causing visual overlap!", 
                    top_items[i].text, top_items[j].text, top_items[i].y);
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
                    item.paint_height = raw.paint_height as f32 + outline_px * 2.0;
                    item.measure_flag = global_flags.measure_flag;
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
            let (placed, displaced_index) = retainer.fix(
                item,
                width,
                height,
                &global_flags,
                display_area
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
        };

        let layout = dfm_plus_prepare_layout(req).expect("prepare layout failed");
        eprintln!("Prepared items: {}", layout.items.len());
        let top_prepared = layout.items.iter().filter(|i| i.type_code ==5).count();
        let bottom_prepared = layout.items.iter().filter(|i| i.type_code ==4).count();
        eprintln!("Top prepared: {}, Bottom prepared: {}", top_prepared, bottom_prepared);

        // Test t= 1.0 看看有没有
        let test_time = 1.0;
        let frame = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout: layout.clone(),
            current_time_seconds: test_time,
        });
        eprintln!("Frame at {}s has {} items total", test_time, frame.items.len());
        let top_in_frame = frame.items.iter().filter(|i| i.type_code ==5).count();
        let bottom_in_frame = frame.items.iter().filter(|i| i.type_code ==4).count();
        let scroll_in_frame = frame.items.iter().filter(|i| i.type_code ==1 || i.type_code ==6).count();
        eprintln!("Top in frame: {}, bottom: {}, scroll: {}", top_in_frame, bottom_in_frame, scroll_in_frame);

        // 打印 frame 的 top:
        eprintln!("Top in frame:");
        for item in frame.items.iter().filter(|i| i.type_code ==5) {
            eprintln!("  text=\"{}\", y={}, time={}", item.text, item.y, item.time_seconds);
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
        };

        let layout = dfm_plus_prepare_layout(req).unwrap();

        let frame_at_1s = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout: layout.clone(),
            current_time_seconds: 1.0,
        });
        let top_at_1s: Vec<_> = frame_at_1s.items.iter()
            .filter(|i| i.type_code == 5)
            .collect();

        eprintln!("Frame at t=1.0, top items: {}", top_at_1s.len());
        for item in &top_at_1s {
            eprintln!("  text={}, y={}", item.text, item.y);
        }

        let frame_at_5s = dfm_plus_layout_frame(DfmPlusFrameRequest {
            layout: layout.clone(),
            current_time_seconds: 5.0,
        });
        let top_at_5s: Vec<_> = frame_at_5s.items.iter()
            .filter(|i| i.type_code == 5)
            .collect();

        eprintln!("Frame at t=5.0, top items: {}", top_at_5s.len());
        for item in &top_at_5s {
            eprintln!("  text={}, y={}", item.text, item.y);
        }

        for i in 0..top_at_1s.len() {
            for j in (i+1)..top_at_1s.len() {
                let y_diff = (top_at_1s[i].y - top_at_1s[j].y).abs();
                assert!(y_diff > 1.0, 
                    "At t=1.0, top items {} and {} share y={}!", 
                    top_at_1s[i].text, top_at_1s[j].text, top_at_1s[i].y);
            }
        }

        for i in 0..top_at_5s.len() {
            for j in (i+1)..top_at_5s.len() {
                let y_diff = (top_at_5s[i].y - top_at_5s[j].y).abs();
                assert!(y_diff > 1.0, 
                    "At t=5.0, top items {} and {} share y={}!", 
                    top_at_5s[i].text, top_at_5s[j].text, top_at_5s[i].y);
            }
        }
    }
}
