use std::cmp::Ordering;
use std::collections::HashMap;

const MERGE_WINDOW_SECONDS: f64 = 45.0;
const TRACK_GAP_RATIO: f64 = 0.25;

pub const NEXT2_TYPE_SCROLL: i32 = 0;
pub const NEXT2_TYPE_TOP: i32 = 1;
pub const NEXT2_TYPE_BOTTOM: i32 = 2;

pub struct RustNext2DanmakuItem {
    pub time_seconds: f64,
    pub text: String,
    pub type_code: i32,
    pub color_argb: i32,
    pub is_me: bool,
}

pub struct RustNext2PrepareRequest {
    pub items: Vec<RustNext2DanmakuItem>,
    pub width: f64,
    pub height: f64,
    pub font_size: f64,
    pub display_area: f64,
    pub scroll_duration_seconds: f64,
    pub allow_stacking: bool,
    pub merge_danmaku: bool,
}

pub struct RustNext2PreparedLayout {
    pub width: f64,
    pub height: f64,
    pub scroll_duration_seconds: f64,
    pub static_duration_seconds: f64,
    pub items: Vec<RustNext2PreparedItem>,
    pub item_times: Vec<f64>,
    pub track_count: i32,
}

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

pub struct RustNext2FrameRequest {
    pub layout: RustNext2PreparedLayout,
    pub current_time_seconds: f64,
}

pub struct RustNext2FrameLayout {
    pub items: Vec<RustNext2FrameItem>,
}

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
    let mut scroll_track_heights = vec![base_track_height; track_len];
    let mut top_track_heights = vec![base_track_height; track_len];
    let mut bottom_track_heights = vec![base_track_height; track_len];

    for idx in 0..items.len() {
        let item_type = items[idx].type_code;
        let item_time = items[idx].time_seconds;
        let item_height = {
            let item = &mut items[idx];
            item.width = measure_text_width(&item.text, font_size * item.font_size_multiplier);
            item.scroll_speed = (width + item.width) / scroll_duration_seconds;
            base_danmaku_height * item.font_size_multiplier
        };

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
                );
                items[idx].track_index = selected.map(|v| v as i32).unwrap_or(-1);
                if let Some(track) = selected {
                    scroll_tracks[track].push(idx);
                    if item_height > scroll_track_heights[track] {
                        scroll_track_heights[track] = item_height;
                    }
                }
            }
            NEXT2_TYPE_TOP => {
                let selected = select_static_track(
                    item_time,
                    &items,
                    &mut top_track_items,
                    track_len,
                    static_duration_seconds,
                );
                items[idx].track_index = selected.map(|v| v as i32).unwrap_or(-1);
                if let Some(track) = selected {
                    top_track_items[track] = Some(idx);
                    if item_height > top_track_heights[track] {
                        top_track_heights[track] = item_height;
                    }
                }
            }
            NEXT2_TYPE_BOTTOM => {
                let selected = select_static_track(
                    item_time,
                    &items,
                    &mut bottom_track_items,
                    track_len,
                    static_duration_seconds,
                );
                items[idx].track_index = selected.map(|v| v as i32).unwrap_or(-1);
                if let Some(track) = selected {
                    bottom_track_items[track] = Some(idx);
                    if item_height > bottom_track_heights[track] {
                        bottom_track_heights[track] = item_height;
                    }
                }
            }
            _ => {
                items[idx].track_index = -1;
            }
        }
    }

    let mut scroll_track_offsets = vec![0.0; track_len];
    let mut top_track_offsets = vec![0.0; track_len];
    let mut bottom_track_offsets = vec![0.0; track_len];
    let mut scroll_track_base_offsets = vec![0.0; track_len];
    let mut top_track_base_offsets = vec![0.0; track_len];
    let mut bottom_track_base_offsets = vec![0.0; track_len];

    let mut scroll_offset = 0.0;
    let mut top_offset = 0.0;
    let mut bottom_accumulated = 0.0;
    for i in 0..track_len {
        scroll_track_offsets[i] = scroll_offset;
        scroll_offset += scroll_track_heights[i];

        top_track_offsets[i] = top_offset;
        top_offset += top_track_heights[i];

        bottom_accumulated += bottom_track_heights[i];
        bottom_track_offsets[i] = height - bottom_accumulated;

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

    Ok(RustNext2PreparedLayout {
        width,
        height,
        scroll_duration_seconds,
        static_duration_seconds,
        items: prepared_items,
        item_times,
        track_count,
    })
}

pub fn next2_layout_frame(request: RustNext2FrameRequest) -> RustNext2FrameLayout {
    let layout = request.layout;
    if layout.items.is_empty() || layout.width <= 0.0 || layout.height <= 0.0 {
        return RustNext2FrameLayout { items: Vec::new() };
    }

    let max_duration = layout
        .scroll_duration_seconds
        .max(layout.static_duration_seconds);
    let window_start = request.current_time_seconds - max_duration;
    let left = lower_bound(&layout.item_times, window_start);
    let right = upper_bound(&layout.item_times, request.current_time_seconds);

    let mut out = Vec::with_capacity(right.saturating_sub(left));

    for idx in left..right {
        let item = &layout.items[idx];
        if item.track_index < 0 {
            continue;
        }
        let elapsed = request.current_time_seconds - item.time_seconds;
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

    RustNext2FrameLayout { items: out }
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
) -> Option<usize> {
    let item = &items[item_index];

    for (i, track_items) in tracks.iter_mut().enumerate().take(track_count) {
        if !track_items.is_empty() {
            track_items.retain(|existing_idx| {
                let existing = &items[*existing_idx];
                item.time_seconds - existing.time_seconds <= scroll_duration_seconds
            });
        }

        if scroll_can_add_to_track(item, items, track_items, width, scroll_duration_seconds) {
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

fn scroll_can_add_to_track(
    new_item: &WorkingNext2Item,
    items: &[WorkingNext2Item],
    track_items: &[usize],
    width: f64,
    scroll_duration_seconds: f64,
) -> bool {
    for existing_idx in track_items {
        let existing = &items[*existing_idx];
        let elapsed = new_item.time_seconds - existing.time_seconds;
        if elapsed < 0.0 || elapsed > scroll_duration_seconds {
            continue;
        }

        let existing_x = width - (elapsed / scroll_duration_seconds) * (width + existing.width);
        let existing_end = existing_x + existing.width;

        if width - existing_end < 0.0 {
            return false;
        }

        if existing.width < new_item.width {
            let progress = (width - existing_x) / (existing.width + width);
            if (1.0 - progress) > (width / (width + new_item.width)) {
                return false;
            }
        }
    }
    true
}

fn select_static_track(
    time_seconds: f64,
    items: &[WorkingNext2Item],
    tracks: &mut [Option<usize>],
    track_count: usize,
    static_duration_seconds: f64,
) -> Option<usize> {
    for (i, existing_opt) in tracks.iter_mut().enumerate().take(track_count) {
        match existing_opt {
            None => return Some(i),
            Some(existing_idx) => {
                let existing = &items[*existing_idx];
                if time_seconds - existing.time_seconds >= static_duration_seconds {
                    return Some(i);
                }
            }
        }
    }
    None
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
}
