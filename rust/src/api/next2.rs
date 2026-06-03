use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::{Mutex, OnceLock};

const MERGE_WINDOW_SECONDS: f64 = 45.0;
const TRACK_GAP_RATIO: f64 = 0.25;

pub const NEXT2_TYPE_SCROLL: i32 = 0;
pub const NEXT2_TYPE_TOP: i32 = 1;
pub const NEXT2_TYPE_BOTTOM: i32 = 2;

#[derive(Clone)]
pub struct RustNext2DanmakuItem {
    pub time_seconds: f64,
    pub text: String,
    pub type_code: i32,
    pub color_argb: i32,
    pub is_me: bool,
}

#[derive(Clone)]
pub struct RustNext2PrepareRequest {
    pub items: Vec<RustNext2DanmakuItem>,
    pub width: f64,
    pub height: f64,
    pub font_size: f64,
    pub display_area: f64,
    pub scroll_duration_seconds: f64,
    pub allow_stacking: bool,
    pub merge_danmaku: bool,
    pub custom_font_family: String,
    pub custom_font_file_path: String,
}

#[derive(Clone)]
pub struct RustNext2PreparedLayout {
    pub width: f64,
    pub height: f64,
    pub scroll_duration_seconds: f64,
    pub static_duration_seconds: f64,
    pub items: Vec<RustNext2PreparedItem>,
    pub item_times: Vec<f64>,
    pub track_count: i32,
    pub cache_key: u64,
}

#[derive(Clone)]
pub struct RustNext2PreparedItem {
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
}

#[derive(Clone)]
pub struct RustNext2FrameRequest {
    pub layout: RustNext2PreparedLayout,
    pub current_time_seconds: f64,
}

#[derive(Clone)]
pub struct RustNext2FrameLayout {
    pub items: Vec<RustNext2FrameItem>,
}

#[derive(Clone)]
pub struct RustNext2FrameItem {
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

pub fn next2_prepare_layout(
    request: RustNext2PrepareRequest,
) -> Result<RustNext2PreparedLayout, String> {
    let width = sanitize_positive(request.width, 1.0);
    let height = sanitize_positive(request.height, 1.0);
    let font_size = sanitize_positive(request.font_size, 24.0);
    let display_area = sanitize_display_area(request.display_area);
    let scroll_duration_seconds = sanitize_positive(request.scroll_duration_seconds, 10.0);
    let static_duration_seconds = scroll_duration_seconds;

    let parsed_items = if request.merge_danmaku {
        prepare_merged_items(request.items)
    } else {
        request
            .items
            .into_iter()
            .map(RawNext2Item::from_plain)
            .collect()
    };

    let base_danmaku_height = measure_text_height(font_size);
    let base_track_height = resolve_base_track_height(font_size, base_danmaku_height);
    let effective_height = (height * display_area).max(1.0);

    let mut track_count = if display_area <= 0.0 {
        1
    } else {
        (effective_height / base_track_height).floor() as i32
    };
    if (display_area - 1.0).abs() < f64::EPSILON {
        track_count -= 1;
    }
    if track_count <= 0 {
        track_count = 1;
    }

    let track_len = track_count as usize;

    let mut items: Vec<WorkingNext2Item> = parsed_items
        .into_iter()
        .filter(|raw| !raw.text.is_empty())
        .map(WorkingNext2Item::from_raw)
        .collect();

    items.sort_by(|a, b| cmp_f64(a.time_seconds, b.time_seconds));

    let mut scroll_tracks: Vec<Vec<usize>> = vec![Vec::new(); track_len];
    let mut top_track_items: Vec<Option<usize>> = vec![None; track_len];
    let mut bottom_track_items: Vec<Option<usize>> = vec![None; track_len];
    let scroll_track_heights = vec![base_track_height; track_len];
    let top_track_heights = vec![base_track_height; track_len];
    let bottom_track_heights = vec![base_track_height; track_len];

    for idx in 0..items.len() {
        let item_type = items[idx].type_code;
        let item_time = items[idx].time_seconds;
        {
            let item = &mut items[idx];
            item.width = measure_text_width(&item.text, font_size * item.font_size_multiplier);
            item.scroll_speed = (width + item.width) / scroll_duration_seconds;
        }

        match item_type {
            NEXT2_TYPE_SCROLL => {
                let selected = select_scroll_track(
                    idx,
                    &items,
                    &mut scroll_tracks,
                    track_len,
                    width,
                    scroll_duration_seconds,
                    request.allow_stacking,
                    base_danmaku_height,
                    base_track_height,
                );
                items[idx].track_index = selected.map(|v| v as i32).unwrap_or(-1);
                if let Some(track) = selected {
                    scroll_tracks[track].push(idx);
                }
            }
            NEXT2_TYPE_TOP => {
                let selected = select_static_track(
                    idx,
                    item_time,
                    &items,
                    &mut top_track_items,
                    track_len,
                    static_duration_seconds,
                    width,
                    base_danmaku_height,
                    base_track_height,
                );
                items[idx].track_index = selected.map(|v| v as i32).unwrap_or(-1);
                if let Some(track) = selected {
                    top_track_items[track] = Some(idx);
                }
            }
            NEXT2_TYPE_BOTTOM => {
                let selected = select_static_track(
                    idx,
                    item_time,
                    &items,
                    &mut bottom_track_items,
                    track_len,
                    static_duration_seconds,
                    width,
                    base_danmaku_height,
                    base_track_height,
                );
                items[idx].track_index = selected.map(|v| v as i32).unwrap_or(-1);
                if let Some(track) = selected {
                    bottom_track_items[track] = Some(idx);
                }
            }
            _ => {
                items[idx].track_index = -1;
            }
        }
    }

    let mut scroll_track_base_offsets = vec![0.0; track_len];
    let mut top_track_base_offsets = vec![0.0; track_len];
    let mut bottom_track_base_offsets = vec![0.0; track_len];

    let mut scroll_offset = 0.0;
    let mut top_offset = 0.0;
    let mut bottom_accumulated = 0.0;
    for i in 0..track_len {
        scroll_offset += scroll_track_heights[i];

        top_offset += top_track_heights[i];

        bottom_accumulated += bottom_track_heights[i];

        scroll_track_base_offsets[i] = scroll_offset - scroll_track_heights[i];
        top_track_base_offsets[i] = top_offset - top_track_heights[i];
        bottom_track_base_offsets[i] =
            height - bottom_accumulated + bottom_track_heights[i] - base_track_height;
    }

    for item in &mut items {
        if item.track_index < 0 {
            continue;
        }
        let track = item.track_index as usize;
        if track >= track_len {
            item.track_index = -1;
            continue;
        }
        item.y_position = match item.type_code {
            NEXT2_TYPE_SCROLL => scroll_track_base_offsets[track],
            NEXT2_TYPE_TOP => top_track_base_offsets[track],
            NEXT2_TYPE_BOTTOM => bottom_track_base_offsets[track],
            _ => 0.0,
        };
    }

    let mut prepared_items = Vec::with_capacity(items.len());
    let mut item_times = Vec::with_capacity(items.len());

    for item in items {
        item_times.push(item.time_seconds);
        prepared_items.push(RustNext2PreparedItem {
            time_seconds: item.time_seconds,
            text: item.text,
            type_code: item.type_code,
            color_argb: item.color_argb,
            is_me: item.is_me,
            font_size_multiplier: item.font_size_multiplier,
            count_text: item.count_text,
            track_index: item.track_index,
            y_position: item.y_position,
            width: item.width,
            scroll_speed: item.scroll_speed,
        });
    }

    let cache_key = calc_layout_cache_key(
        width,
        height,
        scroll_duration_seconds,
        static_duration_seconds,
        track_count,
        &prepared_items,
    );

    Ok(RustNext2PreparedLayout {
        width,
        height,
        scroll_duration_seconds,
        static_duration_seconds,
        items: prepared_items,
        item_times,
        track_count,
        cache_key,
    })
}

pub fn next2_layout_frame(request: RustNext2FrameRequest) -> RustNext2FrameLayout {
    let cache = frame_cache();
    if let Ok(mut guard) = cache.lock() {
        let (result, _) = next2_layout_frame_with_cache(request, &mut guard);
        return result;
    }
    build_next2_frame(&request.layout, request.current_time_seconds)
}

fn build_next2_frame(
    layout: &RustNext2PreparedLayout,
    current_time_seconds: f64,
) -> RustNext2FrameLayout {
    let max_duration = layout
        .scroll_duration_seconds
        .max(layout.static_duration_seconds);
    let window_start = current_time_seconds - max_duration;
    let left = lower_bound(&layout.item_times, window_start);
    let right = upper_bound(&layout.item_times, current_time_seconds);

    let mut out = Vec::with_capacity(right.saturating_sub(left));

    for idx in left..right {
        let item = &layout.items[idx];
        if item.track_index < 0 {
            continue;
        }
        let elapsed = current_time_seconds - item.time_seconds;
        if elapsed < 0.0 {
            continue;
        }

        match item.type_code {
            NEXT2_TYPE_SCROLL => {
                if elapsed > layout.scroll_duration_seconds {
                    continue;
                }
                let x = layout.width - item.scroll_speed * elapsed;
                out.push(RustNext2FrameItem {
                    time_seconds: item.time_seconds,
                    text: item.text.clone(),
                    type_code: item.type_code,
                    color_argb: item.color_argb,
                    is_me: item.is_me,
                    font_size_multiplier: item.font_size_multiplier,
                    count_text: item.count_text.clone(),
                    x,
                    y: item.y_position,
                    offstage_x: layout.width + item.width,
                });
            }
            NEXT2_TYPE_TOP | NEXT2_TYPE_BOTTOM => {
                if elapsed > layout.static_duration_seconds {
                    continue;
                }
                let x = (layout.width - item.width) / 2.0;
                out.push(RustNext2FrameItem {
                    time_seconds: item.time_seconds,
                    text: item.text.clone(),
                    type_code: item.type_code,
                    color_argb: item.color_argb,
                    is_me: item.is_me,
                    font_size_multiplier: item.font_size_multiplier,
                    count_text: item.count_text.clone(),
                    x,
                    y: item.y_position,
                    offstage_x: layout.width,
                });
            }
            _ => {}
        }
    }

    let result = RustNext2FrameLayout { items: out };
    result
}

#[derive(Clone)]
struct RawNext2Item {
    time_seconds: f64,
    text: String,
    type_code: i32,
    color_argb: i32,
    is_me: bool,
    font_size_multiplier: f64,
    count_text: Option<String>,
}

impl RawNext2Item {
    fn from_plain(item: RustNext2DanmakuItem) -> Self {
        Self {
            time_seconds: item.time_seconds,
            text: item.text,
            type_code: normalize_type_code(item.type_code),
            color_argb: normalize_color(item.color_argb),
            is_me: item.is_me,
            font_size_multiplier: 1.0,
            count_text: None,
        }
    }
}

struct WorkingNext2Item {
    time_seconds: f64,
    text: String,
    type_code: i32,
    color_argb: i32,
    is_me: bool,
    font_size_multiplier: f64,
    count_text: Option<String>,
    track_index: i32,
    y_position: f64,
    width: f64,
    scroll_speed: f64,
}

impl WorkingNext2Item {
    fn from_raw(raw: RawNext2Item) -> Self {
        Self {
            time_seconds: raw.time_seconds,
            text: raw.text,
            type_code: raw.type_code,
            color_argb: raw.color_argb,
            is_me: raw.is_me,
            font_size_multiplier: raw.font_size_multiplier,
            count_text: raw.count_text,
            track_index: -1,
            y_position: 0.0,
            width: 0.0,
            scroll_speed: 0.0,
        }
    }
}

fn prepare_merged_items(items: Vec<RustNext2DanmakuItem>) -> Vec<RawNext2Item> {
    if items.is_empty() {
        return Vec::new();
    }

    let mut sorted = items;
    sorted.sort_by(|a, b| cmp_f64(a.time_seconds, b.time_seconds));

    let mut window_counts: HashMap<String, usize> = HashMap::new();
    let mut first_time: HashMap<String, f64> = HashMap::new();
    let mut processed: HashMap<String, RawNext2Item> = HashMap::new();

    let mut left = 0usize;
    for right in 0..sorted.len() {
        let current = &sorted[right];
        if current.text.is_empty() {
            continue;
        }

        let content = current.text.clone();
        let time = current.time_seconds;
        *window_counts.entry(content.clone()).or_insert(0) += 1;

        while left <= right && time - sorted[left].time_seconds > MERGE_WINDOW_SECONDS {
            let left_content = sorted[left].text.clone();
            if !left_content.is_empty() {
                let next_count = window_counts.get(&left_content).copied().unwrap_or(1) - 1;
                if next_count == 0 {
                    window_counts.remove(&left_content);
                    first_time.remove(&left_content);
                } else {
                    window_counts.insert(left_content.clone(), next_count);
                }
            }
            left += 1;
        }

        let count = window_counts.get(&content).copied().unwrap_or(1);
        let key = merge_key(&content, time);

        if count > 1 {
            let first = *first_time.entry(content.clone()).or_insert(time);
            let first_key = merge_key(&content, first);
            let first_raw = processed.get(&first_key).cloned().unwrap_or_else(|| {
                RawNext2Item::from_plain(RustNext2DanmakuItem {
                    time_seconds: first,
                    text: current.text.clone(),
                    type_code: current.type_code,
                    color_argb: current.color_argb,
                    is_me: current.is_me,
                })
            });

            let mut first_processed = first_raw.clone();
            first_processed.font_size_multiplier = calc_merged_font_size_multiplier(count as i32);
            first_processed.count_text = Some(format!("x{count}"));
            processed.insert(first_key.clone(), first_processed);

            let mut current_processed = RawNext2Item::from_plain(RustNext2DanmakuItem {
                time_seconds: current.time_seconds,
                text: current.text.clone(),
                type_code: current.type_code,
                color_argb: current.color_argb,
                is_me: current.is_me,
            });
            current_processed.font_size_multiplier = calc_merged_font_size_multiplier(count as i32);
            current_processed.count_text = Some(format!("x{count}"));
            processed.insert(key, current_processed);
        } else {
            first_time.insert(content.clone(), time);
            processed.insert(
                key,
                RawNext2Item::from_plain(RustNext2DanmakuItem {
                    time_seconds: current.time_seconds,
                    text: current.text.clone(),
                    type_code: current.type_code,
                    color_argb: current.color_argb,
                    is_me: current.is_me,
                }),
            );
        }
    }

    let mut out = Vec::new();
    let mut emitted_first: HashMap<String, f64> = HashMap::new();

    for item in sorted {
        if item.text.is_empty() {
            continue;
        }
        let key = merge_key(&item.text, item.time_seconds);
        let Some(processed_item) = processed.get(&key).cloned() else {
            continue;
        };

        if processed_item.count_text.is_some() {
            let should_emit = match emitted_first.get(&item.text).copied() {
                Some(first_time) => {
                    let delta = item.time_seconds - first_time;
                    delta > MERGE_WINDOW_SECONDS || delta.abs() <= f64::EPSILON
                }
                None => true,
            };
            if !should_emit {
                continue;
            }
            emitted_first.insert(item.text.clone(), item.time_seconds);
        }

        out.push(processed_item);
    }

    out
}

fn select_scroll_track(
    item_index: usize,
    items: &[WorkingNext2Item],
    tracks: &mut [Vec<usize>],
    track_count: usize,
    width: f64,
    scroll_duration_seconds: f64,
    allow_stacking: bool,
    base_danmaku_height: f64,
    base_track_height: f64,
) -> Option<usize> {
    let item = &items[item_index];

    compact_scroll_tracks(item.time_seconds, items, tracks, scroll_duration_seconds);

    for i in 0..track_count {
        if !scroll_will_collide_with_any(
            item,
            i,
            items,
            tracks,
            width,
            scroll_duration_seconds,
            base_danmaku_height,
            base_track_height,
        ) {
            return Some(i);
        }
    }

    if item.is_me && track_count > 0 {
        return Some(0);
    }

    if allow_stacking && track_count > 0 {
        let base = (simple_text_hash(&item.text) as i64) ^ (item.time_seconds as i64);
        let hash = (base & 0x7fff_ffff) as usize;
        return Some(hash % track_count);
    }

    None
}

fn compact_scroll_tracks(
    time_seconds: f64,
    items: &[WorkingNext2Item],
    tracks: &mut [Vec<usize>],
    scroll_duration_seconds: f64,
) {
    for track_items in tracks {
        if track_items.is_empty() {
            continue;
        }
        track_items.retain(|existing_idx| {
            let existing = &items[*existing_idx];
            time_seconds - existing.time_seconds <= scroll_duration_seconds
        });
    }
}

fn scroll_will_collide_with_any(
    new_item: &WorkingNext2Item,
    candidate_track: usize,
    items: &[WorkingNext2Item],
    tracks: &[Vec<usize>],
    width: f64,
    scroll_duration_seconds: f64,
    base_danmaku_height: f64,
    base_track_height: f64,
) -> bool {
    for (existing_track, track_items) in tracks.iter().enumerate() {
        for existing_idx in track_items {
            let existing = &items[*existing_idx];
            if tracks_vertical_overlap(
                candidate_track,
                new_item.font_size_multiplier,
                existing_track,
                existing.font_size_multiplier,
                base_danmaku_height,
                base_track_height,
            ) && scroll_items_will_collide_in_duration(
                new_item,
                existing,
                width,
                scroll_duration_seconds,
            ) {
                return true;
            }
        }
    }
    false
}

fn tracks_vertical_overlap(
    track_a: usize,
    font_scale_a: f64,
    track_b: usize,
    font_scale_b: f64,
    base_danmaku_height: f64,
    base_track_height: f64,
) -> bool {
    let top_a = track_a as f64 * base_track_height;
    let top_b = track_b as f64 * base_track_height;
    let height_a = (base_danmaku_height * font_scale_a.max(1.0)).max(base_danmaku_height);
    let height_b = (base_danmaku_height * font_scale_b.max(1.0)).max(base_danmaku_height);
    let bottom_a = top_a + height_a;
    let bottom_b = top_b + height_b;
    top_a < bottom_b && top_b < bottom_a
}

fn scroll_items_will_collide_in_duration(
    new_item: &WorkingNext2Item,
    existing: &WorkingNext2Item,
    width: f64,
    scroll_duration_seconds: f64,
) -> bool {
    let start_t = new_item.time_seconds.max(existing.time_seconds);
    let end_t = (new_item.time_seconds + scroll_duration_seconds)
        .min(existing.time_seconds + scroll_duration_seconds);
    if end_t <= start_t {
        return false;
    }
    let d_start = scroll_item_x_at_time(new_item, start_t, width, scroll_duration_seconds)
        - scroll_item_x_at_time(existing, start_t, width, scroll_duration_seconds);
    let d_end = scroll_item_x_at_time(new_item, end_t, width, scroll_duration_seconds)
        - scroll_item_x_at_time(existing, end_t, width, scroll_duration_seconds);

    let min_d = d_start.min(d_end);
    let max_d = d_start.max(d_end);
    !(max_d <= -new_item.width || min_d >= existing.width)
}

fn scroll_item_x_at_time(
    item: &WorkingNext2Item,
    time: f64,
    width: f64,
    scroll_duration_seconds: f64,
) -> f64 {
    width - ((time - item.time_seconds) / scroll_duration_seconds) * (width + item.width)
}

fn select_static_track(
    item_index: usize,
    time_seconds: f64,
    items: &[WorkingNext2Item],
    tracks: &mut [Option<usize>],
    track_count: usize,
    static_duration_seconds: f64,
    width: f64,
    base_danmaku_height: f64,
    base_track_height: f64,
) -> Option<usize> {
    let item = &items[item_index];
    compact_static_tracks(time_seconds, items, tracks, static_duration_seconds);

    for i in 0..track_count {
        if !static_will_collide_with_any(
            item,
            i,
            items,
            tracks,
            static_duration_seconds,
            width,
            base_danmaku_height,
            base_track_height,
        ) {
            return Some(i);
        }
    }
    None
}

fn compact_static_tracks(
    time_seconds: f64,
    items: &[WorkingNext2Item],
    tracks: &mut [Option<usize>],
    static_duration_seconds: f64,
) {
    for track in tracks.iter_mut() {
        if let Some(existing_idx) = *track {
            let existing = &items[existing_idx];
            if time_seconds - existing.time_seconds >= static_duration_seconds {
                *track = None;
            }
        }
    }
}

fn static_will_collide_with_any(
    new_item: &WorkingNext2Item,
    candidate_track: usize,
    items: &[WorkingNext2Item],
    tracks: &[Option<usize>],
    static_duration_seconds: f64,
    width: f64,
    base_danmaku_height: f64,
    base_track_height: f64,
) -> bool {
    for (existing_track, existing_idx_opt) in tracks.iter().enumerate() {
        let Some(existing_idx) = existing_idx_opt else {
            continue;
        };
        let existing = &items[*existing_idx];
        if tracks_vertical_overlap(
            candidate_track,
            new_item.font_size_multiplier,
            existing_track,
            existing.font_size_multiplier,
            base_danmaku_height,
            base_track_height,
        ) && static_items_will_collide(new_item, existing, static_duration_seconds, width)
        {
            return true;
        }
    }
    false
}

fn static_items_will_collide(
    new_item: &WorkingNext2Item,
    existing: &WorkingNext2Item,
    static_duration_seconds: f64,
    width: f64,
) -> bool {
    let new_start = new_item.time_seconds;
    let new_end = new_item.time_seconds + static_duration_seconds;
    let existing_start = existing.time_seconds;
    let existing_end = existing.time_seconds + static_duration_seconds;

    if new_end <= existing_start || existing_end <= new_start {
        return false;
    }

    let new_x = (width - new_item.width) / 2.0;
    let existing_x = (width - existing.width) / 2.0;
    let new_end_x = new_x + new_item.width;
    let existing_end_x = existing_x + existing.width;
    new_x < existing_end_x && existing_x < new_end_x
}

fn sanitize_positive(value: f64, fallback: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        value
    } else {
        fallback
    }
}

fn sanitize_display_area(value: f64) -> f64 {
    if !value.is_finite() {
        return 1.0;
    }
    value.clamp(0.0, 1.0)
}

fn normalize_type_code(type_code: i32) -> i32 {
    match type_code {
        1 | 5 => NEXT2_TYPE_TOP,
        2 | 4 => NEXT2_TYPE_BOTTOM,
        _ => NEXT2_TYPE_SCROLL,
    }
}

fn normalize_color(color_argb: i32) -> i32 {
    // Keep alpha from input when present; if alpha is zero, force opaque.
    if (color_argb as u32) >> 24 == 0 {
        (0xFF00_0000u32 | (color_argb as u32 & 0x00FF_FFFFu32)) as i32
    } else {
        color_argb
    }
}

fn measure_text_width(text: &str, font_size: f64) -> f64 {
    // Fast heuristic to avoid per-frame font shaping in Rust.
    // CJK and full-width chars are treated close to 1.0em; ASCII around 0.55em.
    let mut width_em: f64 = 0.0;
    for ch in text.chars() {
        let code = ch as u32;
        width_em += if is_wide_char(code) {
            1.0
        } else if ch.is_ascii_whitespace() {
            0.35
        } else {
            0.55
        };
    }

    (width_em.max(1.0) * font_size).max(font_size * 0.8)
}

fn measure_text_height(font_size: f64) -> f64 {
    (font_size * 1.2).max(font_size)
}

fn resolve_base_track_height(_font_size: f64, base_danmaku_height: f64) -> f64 {
    let gap = base_danmaku_height * TRACK_GAP_RATIO;
    base_danmaku_height + gap
}

fn is_wide_char(code: u32) -> bool {
    matches!(
        code,
        0x1100..=0x115f
            | 0x2329..=0x232a
            | 0x2e80..=0xa4cf
            | 0xac00..=0xd7a3
            | 0xf900..=0xfaff
            | 0xfe10..=0xfe19
            | 0xfe30..=0xfe6f
            | 0xff00..=0xff60
            | 0xffe0..=0xffe6
            | 0x20000..=0x3fffd
    )
}

fn lower_bound(values: &[f64], value: f64) -> usize {
    let mut lo = 0usize;
    let mut hi = values.len();
    while lo < hi {
        let mid = (lo + hi) >> 1;
        if values[mid] < value {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    lo
}

fn upper_bound(values: &[f64], value: f64) -> usize {
    let mut lo = 0usize;
    let mut hi = values.len();
    while lo < hi {
        let mid = (lo + hi) >> 1;
        if values[mid] <= value {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    lo
}

fn cmp_f64(a: f64, b: f64) -> Ordering {
    a.partial_cmp(&b).unwrap_or_else(|| {
        if a.is_nan() && b.is_nan() {
            Ordering::Equal
        } else if a.is_nan() {
            Ordering::Greater
        } else {
            Ordering::Less
        }
    })
}

fn calc_merged_font_size_multiplier(merge_count: i32) -> f64 {
    let value = 1.0 + (merge_count as f64 / 10.0);
    value.clamp(1.0, 2.0)
}

fn merge_key(content: &str, time_seconds: f64) -> String {
    format!("{content}-{time_seconds:.6}")
}

fn simple_text_hash(value: &str) -> u64 {
    // FNV-1a 64-bit
    let mut hash = 0xcbf29ce484222325u64;
    for b in value.as_bytes() {
        hash ^= *b as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

struct FrameCacheEntry {
    value: RustNext2FrameLayout,
    last_used_tick: u64,
}

struct FrameCache {
    entries: HashMap<u64, FrameCacheEntry>,
    use_tick: u64,
}

impl FrameCache {
    fn new() -> Self {
        Self {
            entries: HashMap::new(),
            use_tick: 0,
        }
    }

    fn get(&mut self, key: u64) -> Option<RustNext2FrameLayout> {
        let next_tick = self.use_tick.wrapping_add(1);
        self.use_tick = next_tick;
        let entry = self.entries.get_mut(&key)?;
        entry.last_used_tick = next_tick;
        Some(entry.value.clone())
    }

    fn insert(&mut self, key: u64, value: RustNext2FrameLayout) {
        let next_tick = self.use_tick.wrapping_add(1);
        self.use_tick = next_tick;
        self.entries.insert(
            key,
            FrameCacheEntry {
                value,
                last_used_tick: next_tick,
            },
        );
        while self.entries.len() > FRAME_CACHE_CAPACITY {
            let Some((&victim, _)) = self
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.last_used_tick)
            else {
                break;
            };
            self.entries.remove(&victim);
        }
    }
}

static FRAME_CACHE: OnceLock<Mutex<FrameCache>> = OnceLock::new();

fn frame_cache() -> &'static Mutex<FrameCache> {
    FRAME_CACHE.get_or_init(|| Mutex::new(FrameCache::new()))
}

const FRAME_CACHE_CAPACITY: usize = 256;

fn calc_layout_cache_key(
    width: f64,
    height: f64,
    scroll_duration_seconds: f64,
    static_duration_seconds: f64,
    track_count: i32,
    items: &[RustNext2PreparedItem],
) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    width.to_bits().hash(&mut hasher);
    height.to_bits().hash(&mut hasher);
    scroll_duration_seconds.to_bits().hash(&mut hasher);
    static_duration_seconds.to_bits().hash(&mut hasher);
    track_count.hash(&mut hasher);
    for item in items {
        item.time_seconds.to_bits().hash(&mut hasher);
        item.text.hash(&mut hasher);
        item.type_code.hash(&mut hasher);
        item.color_argb.hash(&mut hasher);
        item.is_me.hash(&mut hasher);
        item.font_size_multiplier.to_bits().hash(&mut hasher);
        item.count_text.hash(&mut hasher);
        item.track_index.hash(&mut hasher);
        item.y_position.to_bits().hash(&mut hasher);
        item.width.to_bits().hash(&mut hasher);
        item.scroll_speed.to_bits().hash(&mut hasher);
    }
    hasher.finish()
}

fn calc_frame_cache_key(layout: &RustNext2PreparedLayout, current_time_seconds: f64) -> u64 {
    let quantized_tick = (current_time_seconds * 60.0).round() as i64;
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    layout.cache_key.hash(&mut hasher);
    quantized_tick.hash(&mut hasher);
    hasher.finish()
}

fn next2_layout_frame_with_cache(
    request: RustNext2FrameRequest,
    cache: &mut FrameCache,
) -> (RustNext2FrameLayout, bool) {
    let layout = request.layout;
    if layout.items.is_empty() || layout.width <= 0.0 || layout.height <= 0.0 {
        return (RustNext2FrameLayout { items: Vec::new() }, false);
    }

    let frame_key = calc_frame_cache_key(&layout, request.current_time_seconds);
    if let Some(cached) = cache.get(frame_key) {
        return (cached, true);
    }

    let result = build_next2_frame(&layout, request.current_time_seconds);
    cache.insert(frame_key, result.clone());
    (result, false)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mk_item(time_seconds: f64, text: &str) -> RustNext2DanmakuItem {
        RustNext2DanmakuItem {
            time_seconds,
            text: text.to_string(),
            type_code: NEXT2_TYPE_SCROLL,
            color_argb: 0x00FF_FFFFu32 as i32,
            is_me: false,
        }
    }

    fn mk_working_scroll_item(
        time_seconds: f64,
        text: &str,
        width: f64,
        font_size_multiplier: f64,
        track_index: i32,
        count_text: Option<&str>,
    ) -> WorkingNext2Item {
        WorkingNext2Item {
            time_seconds,
            text: text.to_string(),
            type_code: NEXT2_TYPE_SCROLL,
            color_argb: 0x00FF_FFFFu32 as i32,
            is_me: false,
            font_size_multiplier,
            count_text: count_text.map(|v| v.to_string()),
            track_index,
            y_position: 0.0,
            width,
            scroll_speed: (1280.0 + width) / 10.0,
        }
    }

    #[test]
    fn merged_deduplication_is_scoped_per_window() {
        let merged = prepare_merged_items(vec![
            mk_item(0.0, "same"),
            mk_item(1.0, "same"),
            mk_item(60.0, "same"),
            mk_item(61.0, "same"),
        ]);

        assert_eq!(merged.len(), 2);
        assert_eq!(merged[0].time_seconds, 0.0);
        assert_eq!(merged[0].count_text.as_deref(), Some("x2"));
        assert_eq!(merged[1].time_seconds, 60.0);
        assert_eq!(merged[1].count_text.as_deref(), Some("x2"));
    }

    #[test]
    fn merged_danmaku_scales_font_size_multiplier() {
        let merged = prepare_merged_items(vec![mk_item(0.0, "same"), mk_item(1.0, "same")]);

        assert!(!merged.is_empty());
        for item in merged {
            assert!(item.font_size_multiplier > 1.0);
        }
    }

    #[test]
    fn merged_danmaku_preserves_layout_for_distant_items() {
        let prepared = next2_prepare_layout(RustNext2PrepareRequest {
            items: vec![
                mk_item(0.0, "same"),
                mk_item(0.2, "same"),
                mk_item(5.0, "other-1"),
                mk_item(5.2, "other-2"),
            ],
            width: 1280.0,
            height: 720.0,
            font_size: 24.0,
            display_area: 1.0,
            scroll_duration_seconds: 10.0,
            allow_stacking: false,
            merge_danmaku: true,
            custom_font_family: String::new(),
            custom_font_file_path: String::new(),
        })
        .expect("prepare layout should succeed");

        let tracks: Vec<i32> = prepared.items.iter().map(|item| item.track_index).collect();
        assert!(tracks.iter().all(|t| *t >= 0));
    }

    #[test]
    fn merged_danmaku_pushes_overlapping_scroll_items_to_farther_tracks() {
        let width = 1280.0;
        let font_size = 24.0;
        let base_danmaku_height = measure_text_height(font_size);
        let base_track_height = resolve_base_track_height(font_size, base_danmaku_height);
        let duration = 10.0;

        let mut items = vec![
            mk_working_scroll_item(0.0, "merged", 520.0, 2.0, 0, Some("x10")),
            mk_working_scroll_item(0.05, "neighbor", 180.0, 1.0, -1, None),
        ];
        let mut tracks = vec![vec![0], Vec::new(), Vec::new()];

        let selected = select_scroll_track(
            1,
            &items,
            &mut tracks,
            3,
            width,
            duration,
            false,
            base_danmaku_height,
            base_track_height,
        );

        assert_eq!(selected, Some(2));
        items[1].track_index = selected.map(|v| v as i32).unwrap_or(-1);
        assert_eq!(items[1].track_index, 2);
    }

    #[test]
    fn scroll_collision_detects_later_catch_up() {
        let width = 1280.0;
        let duration = 10.0;
        let existing = mk_working_scroll_item(0.0, "slow", 120.0, 1.0, 0, None);
        let new_item = mk_working_scroll_item(1.0, "wide", 420.0, 1.0, -1, None);

        assert!(scroll_items_will_collide_in_duration(
            &new_item, &existing, width, duration,
        ));
    }

    #[test]
    fn frame_cache_hits_inside_same_quantized_tick() {
        let mut cache = FrameCache::new();

        let prepared = next2_prepare_layout(RustNext2PrepareRequest {
            items: vec![mk_item(0.0, "hello"), mk_item(0.2, "world")],
            width: 1280.0,
            height: 720.0,
            font_size: 24.0,
            display_area: 1.0,
            scroll_duration_seconds: 10.0,
            allow_stacking: false,
            merge_danmaku: false,
            custom_font_family: String::new(),
            custom_font_file_path: String::new(),
        })
        .expect("prepare layout should succeed");

        let (first, hit1) = next2_layout_frame_with_cache(
            RustNext2FrameRequest {
                layout: prepared.clone(),
                current_time_seconds: 0.3001,
            },
            &mut cache,
        );
        let (second, hit2) = next2_layout_frame_with_cache(
            RustNext2FrameRequest {
                layout: prepared,
                current_time_seconds: 0.3002,
            },
            &mut cache,
        );

        assert_eq!(first.items.len(), second.items.len());
        assert!(!hit1);
        assert!(hit2);
    }

    #[test]
    fn frame_cache_misses_when_quantized_tick_changes() {
        let mut cache = FrameCache::new();

        let prepared = next2_prepare_layout(RustNext2PrepareRequest {
            items: vec![mk_item(0.0, "hello")],
            width: 1280.0,
            height: 720.0,
            font_size: 24.0,
            display_area: 1.0,
            scroll_duration_seconds: 10.0,
            allow_stacking: false,
            merge_danmaku: false,
            custom_font_family: String::new(),
            custom_font_file_path: String::new(),
        })
        .expect("prepare layout should succeed");

        let (_, hit1) = next2_layout_frame_with_cache(
            RustNext2FrameRequest {
                layout: prepared.clone(),
                current_time_seconds: 0.3001,
            },
            &mut cache,
        );
        let (_, hit2) = next2_layout_frame_with_cache(
            RustNext2FrameRequest {
                layout: prepared,
                current_time_seconds: 0.3170,
            },
            &mut cache,
        );

        assert!(!hit1);
        assert!(!hit2);
    }
}
